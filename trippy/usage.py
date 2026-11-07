"""Usage counters for the admin dashboard: every API call, per day and per install.

The app sends an anonymous install id (`X-Trippy-Client`, a random UUID made on
the phone) and, on launch, a small report: how many trips and saved places it
holds and how much storage it uses. Nothing personal is stored: no names, no
trip contents, no locations.

Counters live in memory and are flushed every 30 seconds:
* to Postgres when TRIPPY_STATS_DATABASE_URL is set (schema `trippy_admin`, which the
  Supabase REST API does not expose), so they survive Render restarts;
* otherwise to `.local/usage/usage.json`, which a Render restart or deploy wipes.
"""
from __future__ import annotations

import json
import logging
import threading
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ANONYMOUS = 'unknown'


def today():
    return datetime.now(timezone.utc).date().isoformat()


def clean_client(value):
    """An install id is a UUID; anything else counts as unknown."""
    from uuid import UUID
    try: return str(UUID(str(value or '').strip()))
    except ValueError: return ANONYMOUS


class Usage:
    def __init__(self, path=None, database_url=None, *, flush_seconds=30):
        self.path = Path(path) if path else None
        self.database_url = (database_url or '').strip() or None
        self.lock = threading.Lock()
        self.pending = {}        # (day, metric, client) -> [count, bytes]
        self.totals = {}         # same, everything loaded or recorded (file mode / memory view)
        self.clients = {}        # client -> {'report': {...}, 'first_seen', 'last_seen'}
        self.pending_clients = set()
        self.started = time.time()
        self.flush_seconds = flush_seconds
        self.last_error = None
        self._db_ready = False
        self.today_counts = {}   # (day, client, group) -> count, for fast limit checks
        self._load()
        if self.database_url:
            # Off the startup path: a slow database never delays the server.
            def warm():
                try: self._load_today()
                except Exception as error:  # noqa: BLE001
                    self.last_error = type(error).__name__
            threading.Thread(target=warm, daemon=True).start()
        if flush_seconds:
            threading.Thread(target=self._loop, daemon=True).start()

    @property
    def mode(self):
        return 'postgres' if self.database_url else 'file' if self.path else 'memory'

    # -- recording -------------------------------------------------------------
    def hit(self, metric, client=ANONYMOUS, units=1, nbytes=0):
        key = (today(), metric, client or ANONYMOUS)
        group = metric.split(':', 1)[0]
        with self.lock:
            for who in (client or ANONYMOUS, '*'):
                k = (key[0], who, group); self.today_counts[k] = self.today_counts.get(k, 0) + units
            for store in (self.pending, self.totals):
                row = store.setdefault(key, [0, 0])
                row[0] += units; row[1] += nbytes
            if client and client != ANONYMOUS:
                seen = self.clients.setdefault(client, {'report': {}, 'first_seen': time.time()})
                seen['last_seen'] = time.time()
                self.pending_clients.add(client)

    def report(self, client, payload):
        """The phone's own snapshot: trips, saved places, storage, versions."""
        keep = {}
        for key, kind in (('trips', int), ('planned_trips', int), ('saved_places', int), ('videos', int),
                          ('storage_mb', float), ('app_version', str), ('ios', str), ('device', str)):
            value = payload.get(key)
            try: keep[key] = kind(value) if value is not None else None
            except (TypeError, ValueError): keep[key] = None
            if kind is str and keep[key]: keep[key] = keep[key][:40]
        with self.lock:
            seen = self.clients.setdefault(client, {'first_seen': time.time()})
            seen['report'] = keep; seen['last_seen'] = time.time()
            self.pending_clients.add(client)

    def count_today(self, group, client='*'):
        """Calls of a group ("google", "ai") today, by one install or ('*') by everyone."""
        with self.lock:
            return self.today_counts.get((today(), client, group), 0)

    def _load_today(self):
        with self._connect() as db:
            for metric, client, count in db.execute(
                    'SELECT metric, client, count FROM trippy_admin.usage_daily WHERE day = %s', (today(),)).fetchall():
                group = metric.split(':', 1)[0]
                for who in (client, '*'):
                    k = (today(), who, group); self.today_counts[k] = self.today_counts.get(k, 0) + count

    # -- persistence -----------------------------------------------------------
    def _loop(self):
        while True:
            time.sleep(self.flush_seconds)
            try: self.flush()
            except Exception as error:  # noqa: BLE001 - counters must never break requests
                self.last_error = type(error).__name__
                logging.warning('Usage flush failed: %s', type(error).__name__)

    def _connect(self):
        import psycopg
        connection = psycopg.connect(self.database_url, connect_timeout=8, autocommit=True)
        if not self._db_ready:
            connection.execute('CREATE SCHEMA IF NOT EXISTS trippy_admin')
            connection.execute('''CREATE TABLE IF NOT EXISTS trippy_admin.usage_daily (
                day date NOT NULL, metric text NOT NULL, client text NOT NULL,
                count bigint NOT NULL DEFAULT 0, bytes bigint NOT NULL DEFAULT 0,
                PRIMARY KEY (day, metric, client))''')
            connection.execute('''CREATE TABLE IF NOT EXISTS trippy_admin.clients (
                client text PRIMARY KEY, report jsonb NOT NULL DEFAULT '{}',
                first_seen timestamptz NOT NULL DEFAULT now(), last_seen timestamptz NOT NULL DEFAULT now())''')
            self._db_ready = True
        return connection

    def flush(self):
        with self.lock:
            pending, self.pending = self.pending, {}
            clients = {c: dict(self.clients[c]) for c in self.pending_clients if c in self.clients}
            self.pending_clients = set()
        if not pending and not clients: return
        try:
            if self.database_url:
                with self._connect() as db:
                    with db.cursor() as cur:
                        cur.executemany('''INSERT INTO trippy_admin.usage_daily (day, metric, client, count, bytes)
                            VALUES (%s, %s, %s, %s, %s) ON CONFLICT (day, metric, client) DO UPDATE
                            SET count = usage_daily.count + EXCLUDED.count, bytes = usage_daily.bytes + EXCLUDED.bytes''',
                            [(d, m, c, v[0], v[1]) for (d, m, c), v in pending.items()])
                        cur.executemany('''INSERT INTO trippy_admin.clients (client, report, first_seen, last_seen)
                            VALUES (%s, %s, to_timestamp(%s), to_timestamp(%s)) ON CONFLICT (client) DO UPDATE
                            SET report = CASE WHEN EXCLUDED.report = '{}'::jsonb THEN clients.report ELSE EXCLUDED.report END,
                                last_seen = EXCLUDED.last_seen''',
                            [(c, json.dumps(v.get('report') or {}), v.get('first_seen', time.time()), v.get('last_seen', time.time()))
                             for c, v in clients.items()])
            elif self.path:
                self._write_file()
            self.last_error = None
        except Exception:
            # Put the counts back so a database hiccup loses nothing.
            with self.lock:
                for key, (count, nbytes) in pending.items():
                    row = self.pending.setdefault(key, [0, 0]); row[0] += count; row[1] += nbytes
                self.pending_clients |= set(clients)
            raise

    def _write_file(self):
        with self.lock:
            data = {'usage': [[d, m, c, v[0], v[1]] for (d, m, c), v in self.totals.items()], 'clients': self.clients}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temp = self.path.with_suffix('.tmp'); temp.write_text(json.dumps(data)); temp.replace(self.path)

    def _load(self):
        if self.database_url or not self.path or not self.path.is_file(): return
        try:
            data = json.loads(self.path.read_text())
            self.totals = {(d, m, c): [n, b] for d, m, c, n, b in data.get('usage', [])}
            for (d, m, c), (n, b) in self.totals.items():
                if d == today():
                    for who in (c, '*'):
                        k = (d, who, m.split(':', 1)[0]); self.today_counts[k] = self.today_counts.get(k, 0) + n
            self.clients = data.get('clients', {})
        except (OSError, ValueError):
            pass

    # -- reading ---------------------------------------------------------------
    def rows(self, days=30):
        """[(day, metric, client, count, bytes)] for the last `days` days, unflushed counts included."""
        since = (datetime.now(timezone.utc).date() - timedelta(days=days - 1)).isoformat()
        merged = {}
        if self.database_url:
            with self._connect() as db:
                for d, m, c, n, b in db.execute('SELECT day, metric, client, count, bytes FROM trippy_admin.usage_daily WHERE day >= %s',
                                                (since,)).fetchall():
                    merged[(d.isoformat() if isinstance(d, date) else str(d), m, c)] = [n, b]
            with self.lock:
                for key, v in self.pending.items():
                    row = merged.setdefault(key, [0, 0]); row[0] += v[0]; row[1] += v[1]
        else:
            with self.lock:
                merged = {k: list(v) for k, v in self.totals.items()}
        return [(d, m, c, v[0], v[1]) for (d, m, c), v in merged.items() if d >= since]

    def client_reports(self):
        clients = {}
        if self.database_url:
            with self._connect() as db:
                for c, report, first, last in db.execute('SELECT client, report, first_seen, last_seen FROM trippy_admin.clients').fetchall():
                    clients[c] = {'report': report or {}, 'first_seen': first.timestamp(), 'last_seen': last.timestamp()}
        with self.lock:
            for c, v in self.clients.items():
                merged = clients.setdefault(c, {})
                merged['report'] = v.get('report') or merged.get('report') or {}
                merged['first_seen'] = min(v.get('first_seen', time.time()), merged.get('first_seen', time.time()))
                merged['last_seen'] = max(v.get('last_seen', 0), merged.get('last_seen', 0))
        return clients


class Controls:
    """What an admin can change without a deploy: blocks, daily caps, paid research.

    Stored next to the usage counters (Postgres table `trippy_admin.controls`, or a
    JSON file). Read on every guarded request from memory; written only by admins.
    """
    DEFAULTS = {'blocked': [], 'client_caps': {}, 'default_google_cap': 60, 'global_google_cap': 200,
                'paid_research': True, 'notes': {}, 'free_plans_per_month': 3, 'free_videos_per_month': 20}

    def __init__(self, usage):
        self.usage = usage
        self.lock = threading.Lock()
        self.values = dict(self.DEFAULTS)
        try: self.values.update(self._read())
        except Exception as error:  # noqa: BLE001 - defaults keep the service safe
            logging.warning('Admin controls unavailable: %s', type(error).__name__)

    def _file(self):
        return self.usage.path.with_name('controls.json') if self.usage.path else None

    def _read(self):
        if self.usage.database_url:
            with self.usage._connect() as db:
                db.execute("CREATE TABLE IF NOT EXISTS trippy_admin.controls (key text PRIMARY KEY, value jsonb NOT NULL)")
                return {k: v for k, v in db.execute('SELECT key, value FROM trippy_admin.controls').fetchall() if k in self.DEFAULTS}
        path = self._file()
        return {k: v for k, v in json.loads(path.read_text()).items() if k in self.DEFAULTS} if path and path.is_file() else {}

    def snapshot(self):
        with self.lock:
            return json.loads(json.dumps(self.values))

    def update(self, changes):
        """Validated partial update; unknown keys and bad types are refused (ValueError)."""
        clean = {}
        for key, value in changes.items():
            if key == 'blocked':
                if not isinstance(value, list) or len(value) > 5000: raise ValueError(key)
                clean[key] = sorted({clean_client(v) for v in value} - {ANONYMOUS})
            elif key == 'client_caps':
                if not isinstance(value, dict) or len(value) > 5000: raise ValueError(key)
                clean[key] = {clean_client(c): int(n) for c, n in value.items()
                              if clean_client(c) != ANONYMOUS and n is not None and 0 <= int(n) <= 100000}
            elif key in {'free_plans_per_month', 'free_videos_per_month'}:
                if not isinstance(value, int) or not -1 <= value <= 100000: raise ValueError(key)
                clean[key] = value
            elif key in {'default_google_cap', 'global_google_cap'}:
                if value is not None and (not isinstance(value, int) or not 0 <= value <= 1_000_000): raise ValueError(key)
                clean[key] = value
            elif key == 'paid_research':
                if not isinstance(value, bool): raise ValueError(key)
                clean[key] = value
            elif key == 'notes':
                if not isinstance(value, dict) or len(value) > 5000: raise ValueError(key)
                clean[key] = {clean_client(c): str(t)[:80] for c, t in value.items() if clean_client(c) != ANONYMOUS and str(t).strip()}
            else:
                raise ValueError(key)
        with self.lock:
            self.values.update(clean)
            values = dict(self.values)
        if self.usage.database_url:
            with self.usage._connect() as db:
                db.execute("CREATE TABLE IF NOT EXISTS trippy_admin.controls (key text PRIMARY KEY, value jsonb NOT NULL)")
                for key, value in clean.items():
                    db.execute('INSERT INTO trippy_admin.controls (key, value) VALUES (%s, %s) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
                               (key, json.dumps(value)))
        elif self._file():
            path = self._file(); path.parent.mkdir(parents=True, exist_ok=True)
            temp = path.with_suffix('.tmp'); temp.write_text(json.dumps(values)); temp.replace(path)
        return self.snapshot()

    def refusal(self, client, *, google=False, paid=False):
        """None when the request may go ahead, else a short error code."""
        v = self.snapshot()
        if client in v['blocked']: return 'install_blocked'
        if paid and not v['paid_research']: return 'paid_research_paused'
        if google:
            cap = v['client_caps'].get(client, v['default_google_cap'])
            if cap is not None and client != ANONYMOUS and self.usage.count_today('google', client) >= cap: return 'daily_limit_reached'
            if v['global_google_cap'] is not None and self.usage.count_today('google') >= v['global_google_cap']: return 'service_daily_limit_reached'
        return None


CREDITS = [('plans', 'Plans', 'credit:plan', 'free_plans_per_month'), ('videos', 'Video reads', 'credit:video', 'free_videos_per_month')]


def credits(usage, controls, user_id, *, admin=False):
    """This month's credits for an account: the frame plans and subscriptions will extend.

    Limits come from the admin controls (-1 = unlimited); use is counted per account id.
    """
    month = today()[:7]
    values = controls.snapshot()
    used = {metric: 0 for _, _, metric, _ in CREDITS}
    try:
        for day, metric, client, count, _ in usage.rows(31):
            if client == user_id and day.startswith(month) and metric in used: used[metric] += count
    except Exception:  # noqa: BLE001 - an unreadable store must not lock people out
        pass
    items = [{'id': key, 'label': label, 'used': used[metric], 'limit': -1 if admin else int(values.get(setting, -1))}
             for key, label, metric, setting in CREDITS]
    return {'plan': 'admin' if admin else 'free', 'month': month, 'items': items}


def credit_left(summary, key):
    item = next((i for i in summary['items'] if i['id'] == key), None)
    return item is None or item['limit'] < 0 or item['used'] < item['limit']


# The process-wide recorder. Planner modules call `hit` without knowing who set it up.
_current = None


def install(usage):
    global _current
    _current = usage


def hit(metric, client=None, units=1, nbytes=0):
    if _current is not None:
        try: _current.hit(metric, client or _client.get(), units, nbytes)
        except Exception:  # noqa: BLE001
            pass


# The install that started the current request or plan (thread-local, so a plan's
# Wikidata and Gemini calls count for the phone that asked for it).
class _Client(threading.local):
    value = ANONYMOUS
    def get(self): return self.value
    def set(self, value): self.value = value or ANONYMOUS


_client = _Client()


def set_client(value):
    _client.set(value)


def current_client():
    return _client.get()
