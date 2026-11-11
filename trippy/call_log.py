"""A log of every outbound AI and API call, for the admin page (Admin → Call log).

One row per call: when, provider, operation, model, outcome, HTTP status, how long it
took, tokens, bytes, which install and which plan asked, and the error type.
Never stored: prompts, queries, place names, responses, keys. The error is the
exception's class name, not its message.

Rows live in a memory ring (newest 5,000) and are flushed every 30 seconds:
* to Postgres (`trippy_admin.call_log`, pruned to 30 days) when the usage store uses Postgres;
* otherwise to `.local/usage/calls.jsonl` (newest 5,000, a Render restart wipes it).

Recording never raises into the code it wraps.

    with call_log.track('google:details', model=None) as call:
        ...                       # the real request
        call.tokens(prompt, completion)     # optional
Errors raised inside the block are recorded and re-raised.
"""
from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path

RING = 5000
KEEP_DAYS = 30
FIELDS = ('id', 'ts', 'kind', 'provider', 'operation', 'model', 'status', 'http_status', 'ms',
          'client', 'plan', 'tokens_in', 'tokens_out', 'nbytes', 'error')
# Anything that is an AI model; everything else outbound is an API.
AI_PROVIDERS = {'gemini', 'azure'}


class _Context(threading.local):
    plan = None


_context = _Context()


def set_plan(job_id):
    """The plan whose worker thread this is, so its calls can be grouped (like usage.set_client)."""
    _context.plan = str(job_id)[:40] if job_id else None


class Call:
    """What one wrapped call reports about itself; filled in by the caller, completed by `track`."""
    def __init__(self, metric, model, client, plan):
        self.metric, self.model, self.client, self.plan = metric, model, client, plan
        self.status = 'ok'
        self.http_status = None
        self.tokens_in = self.tokens_out = None
        self.nbytes = 0
        self.error = None
        self.started = time.monotonic()

    def tokens(self, prompt, completion):
        self.tokens_in, self.tokens_out = _int(prompt), _int(completion)

    def cached(self): self.status = 'cached'


def _int(value):
    try: return int(value) if value is not None else None
    except (TypeError, ValueError): return None


def _classify(error):
    """(status, http_status, error name) for an exception from urllib or the OpenAI SDK."""
    code = getattr(error, 'code', None)
    if not isinstance(code, int): code = getattr(error, 'status_code', None)
    if not isinstance(code, int): code = None
    name = type(error).__name__
    if code == 429: return 'rate_limited', code, name
    if code is None and isinstance(error, TimeoutError) or 'Timeout' in name: return 'timeout', code, name
    return 'error', code, name


class _Track:
    def __init__(self, log, call): self.log, self.call = log, call
    def __enter__(self): return self.call
    def __exit__(self, kind, error, _tb):
        call = self.call
        if error is not None:
            call.status, call.http_status, call.error = _classify(error)
        elif call.http_status is None and call.status == 'ok':
            call.http_status = 200
        self.log.add(call)
        return False


class CallLog:
    def __init__(self, path=None, database_url=None, *, usage=None, flush_seconds=30):
        self.path = Path(path) if path else None
        self.database_url = (database_url or '').strip() or None
        self.usage = usage          # borrows its Postgres connection (and its table setup)
        self.lock = threading.Lock()
        self.ring = deque(maxlen=RING)
        self.pending = []
        self.sequence = int(time.time() * 1000) * 1000
        self.last_error = None
        self._db_ready = False
        self._load()
        if flush_seconds:
            threading.Thread(target=self._loop, daemon=True).start()

    @property
    def mode(self):
        return 'postgres' if self.database_url else 'file' if self.path else 'memory'

    # -- recording -------------------------------------------------------------
    def track(self, metric, *, model=None, client=None):
        from trippy import usage as usage_module
        return _Track(self, Call(metric, model, client or usage_module.current_client(), _context.plan))

    def add(self, call):
        try:
            group, _, operation = call.metric.partition(':')
            provider = {'google': 'google', 'ai': operation if operation in AI_PROVIDERS else group}.get(group, group)
            if group == 'ai': operation = 'generate'
            elif group == 'free': provider, operation = operation, 'request'
            row = {'ts': datetime.now(timezone.utc).isoformat(timespec='milliseconds'),
                   'kind': 'ai' if provider in AI_PROVIDERS else 'api',
                   'provider': provider, 'operation': operation or call.metric, 'model': call.model,
                   'status': call.status, 'http_status': call.http_status,
                   'ms': int((time.monotonic() - call.started) * 1000),
                   'client': call.client, 'plan': call.plan, 'tokens_in': call.tokens_in,
                   'tokens_out': call.tokens_out, 'nbytes': call.nbytes or 0, 'error': (call.error or '')[:60] or None}
            with self.lock:
                self.sequence += 1
                row['id'] = self.sequence
                self.ring.append(row); self.pending.append(row)
                if len(self.pending) > 20000: del self.pending[:10000]
        except Exception:  # noqa: BLE001 - logging must never break the call it describes
            pass

    # -- reading ---------------------------------------------------------------
    def rows(self, *, limit=500):
        """Newest first, from memory (the ring covers what the admin page shows)."""
        with self.lock:
            return list(reversed(self.ring))[:limit]

    def query(self, *, kind=None, provider=None, operation=None, model=None, status=None, client=None,
              plan=None, since=None, min_ms=None, limit=300, offset=0):
        """Filtered rows, newest first, plus counts per filter value (over the time window only)
        so the dropdowns can say how many calls each option would show."""
        with self.lock:
            rows = list(reversed(self.ring))
        if since: rows = [r for r in rows if r['ts'] >= since]
        facets = {}
        for field in ('kind', 'provider', 'status', 'model', 'operation'):
            counts = {}
            for r in rows:
                if r[field]: counts[r[field]] = counts.get(r[field], 0) + 1
            facets[field] = sorted(counts.items(), key=lambda x: -x[1])
        wanted = {'kind': kind, 'provider': provider, 'operation': operation, 'model': model, 'status': status,
                  'client': client, 'plan': plan}
        for field, value in wanted.items():
            if value == '': continue
            if value is not None: rows = [r for r in rows if r[field] == value]
        if min_ms: rows = [r for r in rows if r['ms'] >= min_ms]
        slow = sorted(r['ms'] for r in rows)
        stats = {'calls': len(rows), 'errors': sum(1 for r in rows if r['status'] in ('error', 'timeout', 'rate_limited')),
                 'tokens_in': sum(r['tokens_in'] or 0 for r in rows), 'tokens_out': sum(r['tokens_out'] or 0 for r in rows),
                 'p50_ms': slow[len(slow) // 2] if slow else 0, 'p95_ms': slow[int(len(slow) * .95)] if slow else 0}
        return {'rows': rows[offset:offset + limit], 'total': len(rows), 'stats': stats, 'facets': facets,
                'oldest': self.ring[0]['ts'] if self.ring else None, 'mode': self.mode, 'last_error': self.last_error}

    # -- persistence -----------------------------------------------------------
    def _loop(self):
        while True:
            time.sleep(30)
            try: self.flush()
            except Exception as error:  # noqa: BLE001
                self.last_error = type(error).__name__
                logging.warning('Call log flush failed: %s', type(error).__name__)

    def _connect(self):
        connection = self.usage._connect()   # creates the trippy_admin schema
        if not self._db_ready:
            connection.execute('''CREATE TABLE IF NOT EXISTS trippy_admin.call_log (
                id bigint PRIMARY KEY, ts timestamptz NOT NULL, kind text, provider text, operation text, model text,
                status text, http_status int, ms int, client text, plan text, tokens_in int, tokens_out int,
                nbytes bigint, error text)''')
            connection.execute('CREATE INDEX IF NOT EXISTS call_log_ts ON trippy_admin.call_log (ts DESC)')
            self._db_ready = True
        return connection

    def flush(self):
        with self.lock:
            pending, self.pending = self.pending, []
        if not pending: return
        try:
            if self.database_url and self.usage:
                with self._connect() as db:
                    with db.cursor() as cur:
                        cur.executemany('''INSERT INTO trippy_admin.call_log (id, ts, kind, provider, operation, model, status,
                            http_status, ms, client, plan, tokens_in, tokens_out, nbytes, error)
                            VALUES (%(id)s, %(ts)s, %(kind)s, %(provider)s, %(operation)s, %(model)s, %(status)s, %(http_status)s,
                            %(ms)s, %(client)s, %(plan)s, %(tokens_in)s, %(tokens_out)s, %(nbytes)s, %(error)s)
                            ON CONFLICT (id) DO NOTHING''', pending)
                        cur.execute('DELETE FROM trippy_admin.call_log WHERE ts < now() - %s::interval', (f'{KEEP_DAYS} days',))
            elif self.path:
                self._write_file()
            self.last_error = None
        except Exception:
            with self.lock: self.pending = pending + self.pending
            raise

    def _write_file(self):
        with self.lock: rows = list(self.ring)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temp = self.path.with_suffix('.tmp')
        temp.write_text('\n'.join(json.dumps(r) for r in rows)); temp.replace(self.path)

    def _load(self):
        """Start with what the last run left: the file, or the newest rows in Postgres."""
        try:
            if self.database_url and self.usage:
                def warm():
                    try:
                        with self._connect() as db:
                            cols = ', '.join(FIELDS)
                            found = db.execute(f'SELECT {cols} FROM trippy_admin.call_log ORDER BY ts DESC LIMIT %s', (RING,)).fetchall()
                        rows = []
                        for values in reversed(found):
                            row = dict(zip(FIELDS, values))
                            row['ts'] = row['ts'].astimezone(timezone.utc).isoformat(timespec='milliseconds')
                            rows.append(row)
                        with self.lock:
                            known = {r['id'] for r in self.ring}
                            merged = [r for r in rows if r['id'] not in known] + list(self.ring)
                            self.ring.clear(); self.ring.extend(sorted(merged, key=lambda r: r['id'])[-RING:])
                    except Exception as error:  # noqa: BLE001
                        self.last_error = type(error).__name__
                threading.Thread(target=warm, daemon=True).start()
            elif self.path and self.path.is_file():
                for line in self.path.read_text().splitlines()[-RING:]:
                    try: self.ring.append(json.loads(line))
                    except ValueError: continue
                if self.ring: self.sequence = max(self.sequence, max(r['id'] for r in self.ring))
        except OSError:
            pass


# The process-wide log, like usage.install / usage.hit.
_current = None


def install(log):
    global _current
    _current = log


class _Nothing:
    """Used before install() (tests, scripts): tracking is a no-op."""
    def __enter__(self): return Call('', None, None, None)
    def __exit__(self, *exc): return False


def track(metric, *, model=None, client=None):
    return _current.track(metric, model=model, client=client) if _current is not None else _Nothing()
