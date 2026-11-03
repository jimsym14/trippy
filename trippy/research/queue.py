"""Durable local completion queue: immutable results, bounded retries and budgets."""
from collections import Counter
from contextlib import closing
from datetime import datetime, timezone
from decimal import Decimal
import fcntl
import json
from pathlib import Path
import sqlite3
from threading import Event, Thread
import time

from trippy.sources.batch import request_with_deadline
from trippy.sources.extraction import fingerprint
from trippy.sources.luna import BudgetError, ProviderConfigurationError, TransientProviderError
from trippy.sources.semantic_review import ledger_state, reservation
from trippy.sources.unattended import (immutable_write, mutable_write, unattended_worker,
    recover_provider_response, request_count, retry_delay)
from .providers import fetch_operator, fetch_operator_feed, bounded_http_get, host
from .reviews import validate_source, validate_annotations, page_chunk, validate_page


TERMINAL = {'succeeded', 'review_required', 'blocked', 'budget_deferred', 'attempts_exhausted'}
AI_STAGES = {'source', 'facets', 'details', 'activity_fit', 'operator_extract'}


def emit(message):
    print('['+datetime.now(timezone.utc).strftime('%H:%M:%S UTC')+'] '+message, flush=True)


def job(kind, payload, *, deps=()):
    spec = {'kind': kind, 'payload': payload, 'deps': sorted(deps)}
    return spec | {'id': fingerprint(spec)}


class Store:
    def __init__(self, path):
        self.path = Path(path); self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, spec TEXT NOT NULL, state TEXT NOT NULL, '
                       'attempts INTEGER NOT NULL DEFAULT 0, retry_at REAL NOT NULL DEFAULT 0, result_path TEXT, '
                       'result_sha256 TEXT, error TEXT, kind TEXT, ordinal INTEGER NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS http_requests (id INTEGER PRIMARY KEY, host TEXT, at REAL)')
        self.path.chmod(0o600)

    def connect(self):
        return closing_transaction(self.path)

    def bind(self, plan_sha256):
        with self.connect() as db:
            row = db.execute("SELECT value FROM meta WHERE key='plan_sha256'").fetchone()
            if row and row[0] != plan_sha256: raise ValueError('Queue belongs to another frozen plan')
            db.execute("INSERT OR IGNORE INTO meta VALUES ('plan_sha256',?)", (plan_sha256,))

    def add(self, spec):
        if spec['id'] != fingerprint({k:v for k,v in spec.items() if k!='id'}):
            raise ValueError('Job input hash differs')
        with self.connect() as db:
            row = db.execute('SELECT spec FROM jobs WHERE id=?', (spec['id'],)).fetchone()
            encoded = json.dumps(spec, ensure_ascii=False, sort_keys=True)
            if row:
                if row[0]!=encoded: raise ValueError('Existing job input changed')
                return
            ordinal = db.execute('SELECT COALESCE(MAX(ordinal),0)+1 FROM jobs').fetchone()[0]
            db.execute('INSERT INTO jobs (id,spec,state,kind,ordinal) VALUES (?,?,?,?,?)',
                       (spec['id'], encoded, 'queued', spec['kind'], ordinal))

    def rows(self):
        with self.connect() as db:
            db.row_factory=sqlite3.Row
            return [dict(r) for r in db.execute('SELECT * FROM jobs ORDER BY ordinal')]

    def update(self, key, **fields):
        if not fields or not set(fields)<={'state','attempts','retry_at','result_path','result_sha256','error'}:
            raise ValueError('Invalid job state update')
        with self.connect() as db:
            db.execute('UPDATE jobs SET '+','.join(k+'=?' for k in fields)+' WHERE id=?', (*fields.values(),key))

    def get_meta(self, key, default=None):
        with self.connect() as db:
            row=db.execute('SELECT value FROM meta WHERE key=?',(key,)).fetchone()
            return json.loads(row[0]) if row else default

    def set_meta(self, key, value):
        with self.connect() as db:
            db.execute('INSERT OR REPLACE INTO meta VALUES (?,?)', (key,json.dumps(value)))

    def reserve_http(self, domain, maximum, now):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute('SELECT COUNT(*) FROM http_requests').fetchone()[0]>=maximum:
                raise BudgetError('HTTP request ceiling reached')
            db.execute('INSERT INTO http_requests (host,at) VALUES (?,?)',(domain,now))

    def http_count(self):
        with self.connect() as db: return db.execute('SELECT COUNT(*) FROM http_requests').fetchone()[0]

    def reserve_slot(self, key, now, interval):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT value FROM meta WHERE key=?',(key,)).fetchone()
            slot=max(now,json.loads(row[0]) if row else 0)
            db.execute('INSERT OR REPLACE INTO meta VALUES (?,?)',(key,json.dumps(slot+interval)))
            return slot-now

    def extend_cooldown(self, key, until):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT value FROM meta WHERE key=?',(key,)).fetchone()
            until=max(until,json.loads(row[0]) if row else 0)
            db.execute('INSERT OR REPLACE INTO meta VALUES (?,?)',(key,json.dumps(until)))


class closing_transaction:
    def __init__(self, path): self.path=path
    def __enter__(self):
        self.db=sqlite3.connect(self.path,timeout=10); return self.db
    def __exit__(self, exc_type, exc, tb):
        try:
            if exc_type: self.db.rollback()
            else: self.db.commit()
        finally: self.db.close()


def pool_used(config):
    return sum((ledger_state(config['ledger'], config['request_prefix']+'-'+name)[2]
                for name in AI_STAGES), Decimal(0))


class Runner:
    def __init__(self, plan, values, *, requester=None, fetcher=None, sleep=time.sleep, now=time.time):
        self.plan=plan; self.config=plan['config']; self.root=Path(self.config['output_root'])
        self.store=Store(self.root/'jobs.sqlite'); self.store.bind(fingerprint(plan))
        self.provider_state=Store(Path(self.config['ledger']).parent/'completion-provider.sqlite')
        self.values=values; self.requester=requester; self.fetcher=fetcher
        self.sleep=sleep; self.now=now; self.active=None; self.provider_blocked=False
        self.network_enabled=True; self.ai_enabled=True
        for spec in plan['jobs']: self.store.add(spec)

    def checkpoint(self, state='running'):
        rows=self.store.rows(); counts=Counter(r['state'] for r in rows)
        stages={kind: dict(Counter(r['state'] for r in rows if r['kind']==kind))
                for kind in sorted({r['kind'] for r in rows})}
        report={'plan_sha256':fingerprint(self.plan),'state':state,'active_job':self.active,
            'jobs':dict(counts),'stages':stages,'http_requests':self.store.http_count(),
            'total_wait_seconds':self.store.get_meta('total_wait_seconds',0),
            'shared_reserved':str(ledger_state(self.config['ledger'],self.config['request_prefix']+'-source')[1]),
            'queue_reserved':str(pool_used(self.config)), 'shared_cap':self.config['shared_cap'],
            'queue_cap':self.config['queue_cap'],'updated_at':datetime.now(timezone.utc).isoformat(),
            'queue_drained':all(r['state'] in TERMINAL for r in rows),
            'execution_complete':all(r['state']=='succeeded' for r in rows),
            'dataset_ready':False,'ready_to_publish':False,
            'note':'Execution completion is not semantic, canonical, current-trip or planner approval'}
        mutable_write(self.root/'status.json',report); return report

    def result(self, row):
        if not row.get('result_path'): return None
        value=json.loads(Path(row['result_path']).read_text())
        if fingerprint(value)!=row['result_sha256']: raise ValueError('Saved result content changed')
        return value

    def save(self, spec, result):
        path=self.root/'results'/(spec['id']+'.json')
        document={'job_sha256':spec['id'],'result':result}
        immutable_write(path,document)
        self.store.update(spec['id'],state='succeeded',result_path=str(path),result_sha256=fingerprint(document),error=None)

    def wait(self, seconds):
        spent=self.store.get_meta('total_wait_seconds',0)
        if spent+seconds>self.config['max_total_wait_seconds']: return False
        remaining=seconds
        while remaining>0:
            interval=min(30,remaining); self.checkpoint('waiting_for_provider')
            emit(f'Waiting {int(remaining)}s; checkpoints retained')
            self.sleep(interval); spent+=interval; remaining-=interval
            self.store.set_meta('total_wait_seconds',spent)
        return True

    def request_hook(self, domain):
        delay=self.provider_state.reserve_slot('host_cooldown:'+domain,self.now(),self.config['host_delay_seconds'])
        if delay and not self.wait(delay):
            raise BudgetError('Cumulative provider wait limit reached')
        self.store.reserve_http(domain,self.config['max_http_requests'],self.now())

    def ai(self, spec):
        # All completion versions sharing this ledger serialize dispatch, so
        # check/reserve and receipt adoption cannot race or duplicate paid calls.
        lock_path=Path(self.config['ledger']).with_suffix('.completion-dispatch.lock')
        with lock_path.open('a') as lock:
            while True:
                try:
                    fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB); break
                except BlockingIOError:
                    if not self.wait(15): raise BudgetError('Shared provider wait limit reached')
            cooldown=self.provider_state.get_meta('luna_cooldown',0)
            if cooldown>self.now() and not self.wait(cooldown-self.now()):
                raise BudgetError('Shared Luna cooldown exceeds wait limit')
            return self._ai_locked(spec)

    def _ai_locked(self, spec):
        request=spec['payload']['request']; kind=spec['kind']; group=self.config['request_prefix']+'-'+kind
        # Adopt provider receipts saved before an interruption before reserving
        # another paid request. An invalid cached response is never paid-retried.
        candidate_path=self.root/'candidates'/(request['id']+'.json')
        if candidate_path.exists():
            candidate=json.loads(candidate_path.read_text())
            if candidate['chunk_sha256']!=request['id']: raise ValueError('Candidate input changed')
            response=candidate['response']
        else:
            response=recover_provider_response(self.config['ledger'],group,request['id'])
            if response is not None: emit('Recovered saved Luna response without a request')
            if response is None:
                if self.provider_blocked: raise ProviderConfigurationError('Luna provider configuration needs attention')
                if not self.ai_enabled: raise BudgetError('AI disabled for this execution')
                output=self.config['output_tokens'][kind]
                amount=reservation(request,self.values,output=output)
                currency,shared,used=ledger_state(self.config['ledger'],group)
                if currency!='USD' or self.values.get('TRIPPY_AI_BUDGET_CURRENCY')!='USD':
                    raise BudgetError('Completion queue requires original USD ledger')
                if Decimal(self.values['TRIPPY_AI_BUDGET_AMOUNT'])!=Decimal(self.config['shared_cap']) or Decimal(self.config['shared_cap'])>15:
                    raise BudgetError('Keep the original shared $15 ceiling')
                task_limit=Decimal(self.config['task_caps'][kind])
                if shared+amount>Decimal(self.config['shared_cap']) or pool_used(self.config)+amount>Decimal(self.config['queue_cap']) or used+amount>task_limit:
                    raise BudgetError('Shared, queue or stage reservation ceiling reached')
                call_values={**self.values,'TRIPPY_LUNA_REQUEST_GROUP':group,
                    'TRIPPY_LUNA_MAX_REQUESTS':str(self.config['max_ai_requests_per_stage']),
                    'TRIPPY_LUNA_MAX_OUTPUT_TOKENS':str(output),
                    'TRIPPY_LUNA_REQUEST_TIMEOUT':str(self.config['provider_timeout_seconds'])}
                emit(f'Luna {kind}; reserve ${amount}')
                if self.requester: response=self.requester(call_values,self.config['ledger'],request)
                else: response=request_with_deadline(call_values,self.config['ledger'],request,
                    timeout=self.config['worker_timeout_seconds'],worker=unattended_worker,retryable_deadline=True)
            immutable_write(candidate_path,{'chunk_sha256':request['id'],'response':response})
        if kind=='source': return validate_source(request,response)
        if kind=='operator_extract':
            result=validate_page(request,response)
            for fact in result['facts']:
                fact['checked_at']=spec['payload']['source_checked_at']
                fact['source_body_sha256']=spec['payload']['source_body_sha256']
            return result
        return validate_annotations(request,response)

    def perform(self, spec):
        kind=spec['kind']; payload=spec['payload']
        if kind in AI_STAGES: return self.ai(spec)
        if kind=='identity_inventory': return payload
        if kind in {'operator_fetch','operator_feed'}:
            return self.operator(spec)
        raise ValueError('Unsupported completion job kind')

    def operator(self, spec):
        payload=spec['payload']; kind=spec['kind']
        key=fingerprint({'url':payload['url'],'adapter':kind,'feed':payload.get('feed')})
        folder=Path(self.config['ledger']).parent/'completion-http-cache'
        folder.mkdir(parents=True,exist_ok=True,mode=0o700)
        cache=folder/(key+'.json')
        with (folder/(key+'.lock')).open('a') as lock:
            while True:
                try:
                    fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB); break
                except BlockingIOError:
                    if not self.wait(15): raise BudgetError('Shared HTTP wait limit reached')
            if cache.exists():
                saved=json.loads(cache.read_text()); receipt=saved['receipt']
                if fingerprint(receipt)!=saved['receipt_sha256']: raise ValueError('Operator cache content changed')
                checked=datetime.fromisoformat(receipt['checked_at']).timestamp()
                age=self.now()-checked
                if 0<=age<self.config.get('web_cache_max_age_seconds',86400):
                    emit('Reused operator receipt; checked_at unchanged')
                    return {**receipt,'cache_reused':True}
            if not self.network_enabled: raise BudgetError('Network disabled and no fresh operator receipt available')
            if self.fetcher: result=self.fetcher(payload['url'],request_hook=self.request_hook)
            elif kind=='operator_feed': result=fetch_operator_feed(payload['feed'],getter=bounded_http_get,request_hook=self.request_hook)
            else: result=fetch_operator(payload['url'],getter=bounded_http_get,request_hook=self.request_hook)
            mutable_write(cache,{'receipt':result,'receipt_sha256':fingerprint(result)})
            return result

    def add_page_job(self, spec, result):
        if spec['kind']!='operator_fetch' or not result['sections'] or not self.config['extract_operator_prose']: return
        request=page_chunk(result)
        self.store.add(job('operator_extract',{'request':request,'fetch_job_id':spec['id'],
            'source_checked_at':result['checked_at'],'source_body_sha256':result['body_sha256']},deps=[spec['id']]))

    def run(self, *, network=True, ai=True):
        self.network_enabled=network; self.ai_enabled=ai
        self.root.mkdir(parents=True,exist_ok=True,mode=0o700)
        with (self.root/'runner.lock').open('a') as lock:
            try: fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError: raise ValueError('Another completion runner is active') from None
            return self._run()

    def _run(self):
        # Successful receipts are checked on every resume, including interrupted
        # saves where the immutable file exists but the SQLite commit did not.
        for row in self.store.rows():
            spec=json.loads(row['spec'])
            if row['state']=='succeeded':
                result=self.result(row)['result']; self.add_page_job(spec,result); continue
            saved=self.root/'results'/(spec['id']+'.json')
            if saved.exists():
                document=json.loads(saved.read_text())
                if document['job_sha256']!=spec['id']: raise ValueError('Interrupted result input differs')
                self.store.update(spec['id'],state='succeeded',result_path=str(saved),result_sha256=fingerprint(document))
                self.add_page_job(spec,document['result'])
            elif row['state']=='running': self.store.update(row['id'],state='queued')
            elif row['state']=='budget_deferred': self.store.update(row['id'],state='queued')
        while True:
            rows=self.store.rows(); by_id={r['id']:r for r in rows}
            pending=[r for r in rows if r['state'] not in TERMINAL]
            if not pending: break
            runnable=[]
            for row in pending:
                spec=json.loads(row['spec']); deps=spec['deps']
                if any(dep not in by_id for dep in deps): raise ValueError('Unknown job dependency')
                if any(by_id[dep]['state'] in TERMINAL-{'succeeded'} for dep in deps):
                    self.store.update(row['id'],state='blocked',error='dependency_requires_review'); continue
                if all(by_id[dep]['state']=='succeeded' for dep in deps): runnable.append(row)
            if not runnable:
                if any(r['state'] not in TERMINAL for r in self.store.rows()):
                    raise ValueError('Dependency graph cannot make progress')
                break
            cooldown=self.provider_state.get_meta('luna_cooldown',0)
            def ready_at(row):
                return max(row['retry_at'],cooldown if row['kind'] in AI_STAGES else 0)
            eligible=[r for r in runnable if ready_at(r)<=self.now()]
            if not eligible:
                delay=min(ready_at(r) for r in runnable)-self.now()
                if not self.wait(delay):
                    for row in runnable: self.store.update(row['id'],state='blocked',error='provider_wait_limit_reached')
                    break
                continue
            row=eligible[0]; spec=json.loads(row['spec']); self.active=row['id']
            attempts=row['attempts']
            if spec['kind'] in AI_STAGES:
                group=self.config['request_prefix']+'-'+spec['kind']
                attempts=max(attempts,request_count(self.config['ledger'],group,spec['payload']['request']['id']))
            attempt_limit=self.config['max_rate_limit_attempts'] if row['error']=='rate_limit' else self.config['max_attempts']
            cached=False
            if spec['kind'] in AI_STAGES:
                request=spec['payload']['request']; group=self.config['request_prefix']+'-'+spec['kind']
                cached=(self.root/'candidates'/(request['id']+'.json')).exists()
                if not cached:
                    try: cached=recover_provider_response(self.config['ledger'],group,request['id']) is not None
                    except (ValueError,KeyError,TypeError):
                        self.store.update(row['id'],state='review_required',error='invalid_saved_provider_response'); continue
            if attempts>=attempt_limit and not cached:
                self.store.update(row['id'],state='attempts_exhausted'); continue
            self.store.update(row['id'],state='running',attempts=attempts+1); self.checkpoint()
            emit(f'{spec["kind"]}: attempt {attempts+1}; {sum(r["state"]=="succeeded" for r in rows)}/{len(rows)} saved')
            stop=Event()
            def heartbeat():
                while not stop.wait(15): emit('Working; saved checkpoints retained')
            thread=Thread(target=heartbeat,daemon=True); thread.start()
            try:
                result=self.perform(spec); self.save(spec,result); self.add_page_job(spec,result)
            except TransientProviderError as exc:
                delay=retry_delay(exc,attempts+1)
                self.store.update(row['id'],state='retry_wait',retry_at=self.now()+delay,error=exc.kind)
                if spec['kind'] in {'operator_fetch','operator_feed'}:
                    domain=host(spec['payload']['url'])
                    self.provider_state.extend_cooldown('host_cooldown:'+domain,self.now()+delay)
                elif exc.kind=='rate_limit':
                    self.provider_state.extend_cooldown('luna_cooldown',self.now()+delay)
                emit(f'Temporary {exc.kind}; retry no earlier than {int(delay)}s. Other jobs continue.')
            except ProviderConfigurationError:
                self.provider_blocked=True
                self.store.update(row['id'],state='blocked',error='luna_provider_configuration')
            except BudgetError:
                self.store.update(row['id'],state='budget_deferred',attempts=attempts,
                    error='budget_or_execution_mode_limit')
            except (ValueError, KeyError, TypeError, RecursionError):
                self.store.update(row['id'],state='review_required',error='invalid_or_unavailable_source_result')
                emit('Evidence/content issue saved for review; continuing independent jobs')
            finally:
                stop.set(); thread.join(timeout=1); self.active=None; self.checkpoint()
        state='complete_with_evidence_handoffs' if all(r['state']=='succeeded' for r in self.store.rows()) else 'partial_with_review_or_resume_handoffs'
        report=self.checkpoint(state)
        emit('Queue finished. See status.json and completion-report.json for remaining evidence gates.')
        return report
