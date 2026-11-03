"""Size-based private video batch, shared budget, exact evidence checkpoints."""
import argparse
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import sqlite3
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import closing
from datetime import datetime,timezone
from threading import Event,Thread
import multiprocessing

REQUEST_DEADLINE_SECONDS=180


def api_request_worker(values,ledger,chunk,connection):
    """Isolate network I/O so the parent can enforce a total wall deadline."""
    try:
        from .luna import make_provider
        result=make_provider(values,ledger,max_output_tokens=16000)(chunk)
        connection.send(('ok',result))
    except Exception as exc:
        connection.send(('error',type(exc).__name__,str(exc) if isinstance(exc,ValueError) else 'Provider worker failed; credentials redacted'))
    finally:connection.close()


def request_with_deadline(values,ledger,chunk,*,timeout=REQUEST_DEADLINE_SECONDS,worker=api_request_worker,
                          retryable_deadline=False):
    context=multiprocessing.get_context('spawn');receiver,sender=context.Pipe(duplex=False)
    process=context.Process(target=worker,args=(values,ledger,chunk,sender),daemon=True)
    try:
        process.start();sender.close()
        if not receiver.poll(timeout):
            if retryable_deadline:
                from .luna import TransientProviderError
                raise TransientProviderError('worker_deadline')
            raise ValueError('Request exceeded the '+str(timeout)+'s wall deadline; reservation retained, no automatic retry')
        try:message=receiver.recv()
        except EOFError:raise ValueError('Provider worker exited without a response; no automatic retry') from None
        if message[0]=='ok':return message[1]
        from .luna import BudgetError,ProviderConfigurationError,TransientProviderError
        if message[1] == 'TransientProviderError':
            hints = message[3] if len(message) > 3 else {}
            raise TransientProviderError(hints.get('kind','temporary_provider_error'), hints.get('retry_after_seconds'))
        kind={'BudgetError':BudgetError,'ProviderConfigurationError':ProviderConfigurationError}.get(message[1],ValueError)
        raise kind(message[2])
    finally:
        sender.close();receiver.close()
        if process.pid is not None:
            if process.is_alive():process.terminate()
            process.join(timeout=3)
            if process.is_alive():process.kill();process.join(timeout=3)


def progress(message):
    print('['+datetime.now(timezone.utc).strftime('%H:%M:%S UTC')+'] '+message,flush=True)

from .extraction import Extraction, fingerprint, aggregate, execute_chunks, validate_result
from .coverage import private_write, reservation_preview, prepare_final, validate_prepared, execute as execute_audit
from .planner import canonical_video

AUDIT_CEILING=Decimal('0.06')
PILOTS={'quxiSJMqrHk','RXG2VUCMPVA'}


def prepare_batch(original,values,used):
    groups=defaultdict(list)
    for chunk in original['chunks']:
        if chunk['id']!=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']}):
            raise ValueError('Original manifest fingerprint mismatch')
        groups[chunk['payload']['source']['external_id']].append(chunk)
    videos=[];requests=[]
    prompt=(Path(__file__).resolve().parents[2]/'configs/source_research/extraction-prompt-v2.md').read_text()
    for sid,chunks in groups.items():
        cues={s['segment_id']:s for c in chunks for s in c['payload']['segments']}
        chars=sum(len(s['text']) for s in cues.values())
        quota=0 if chars<=6000 else 1 if chars<=14000 else 2 if chars<=26000 else 3
        status='reuse_completed_pilot' if sid in PILOTS else 'scheduled'
        if chars<1000 and len(cues)<10:status='thin_transcript_requires_manual_review'
        planned=[]
        if status=='scheduled':
            for original_chunk in chunks:
                c=deepcopy(original_chunk);c['system_prompt']=prompt;c['prompt_version']=2
                c['response_schema']=Extraction.model_json_schema()
                c['id']=fingerprint({'prompt':prompt,'schema':c['response_schema'],'payload':c['payload']})
                planned.append(c);requests.append(c)
        else:quota=0
        preview=reservation_preview(planned,values,16000)
        videos.append({'source_id':sid,'title':chunks[0]['payload']['metadata'].get('title',sid),
            'transcript_characters':chars,'cues':len(cues),'status':status,
            'primary_calls':len(planned),'audit_calls':quota,'total_calls':len(planned)+quota,
            'primary_reservation':preview['reservation'],'audit_reservation_ceiling':str(AUDIT_CEILING*quota),
            'chunks':planned})
    primary=sum((Decimal(v['primary_reservation']) for v in videos),Decimal(0))
    audit=sum((Decimal(v['audit_reservation_ceiling']) for v in videos),Decimal(0))
    result={'version':1,'status':'private_batch_prepared','original_manifest_sha256':fingerprint(original),
        'videos':videos,'policy':{'characters_per_audit_tier':[6000,14000,26000],
            'audits_per_tier':[0,1,2,3],'audit_reservation_per_call':str(AUDIT_CEILING),
            'one_attempt_per_request':True,'publication_approved':False},
        'summary':{'scheduled_videos':sum(v['status']=='scheduled' for v in videos),
            'primary_calls':len(requests),'audit_calls':sum(v['audit_calls'] for v in videos),
            'new_calls':len(requests)+sum(v['audit_calls'] for v in videos),
            'primary_reservation':str(primary),'audit_reservation_ceiling':str(audit),
            'additional_reservation_ceiling':str(primary+audit),
            'existing_reserved':str(used),'total_reservation_ceiling':str(Decimal(used)+primary+audit)},
        'ready_to_publish':False}
    result['plan_sha256']=fingerprint(result)
    return result


def validate_plan(plan,original):
    document={k:v for k,v in plan.items() if k!='plan_sha256'}
    if plan.get('version')!=1 or plan.get('plan_sha256')!=fingerprint(document):raise ValueError('Batch plan fingerprint mismatch')
    if plan['original_manifest_sha256']!=fingerprint(original):raise ValueError('Batch original manifest mismatch')
    for video in plan['videos']:
        for c in video['chunks']:
            if c['id']!=fingerprint({'prompt':c['system_prompt'],'schema':c['response_schema'],'payload':c['payload']}):
                raise ValueError('Batch request fingerprint mismatch')
            validate_result(c,{'mentions':[]})
            if canonical_video(c['payload']['source']['url'])['external_id']!=video['source_id']:
                raise ValueError('Batch source identity mismatch')


def select_audits(base,original,quota,values):
    if not quota:return None
    # Short cores bound repeated context/claims. Shrink before spending if
    # a video's scene is unusually dense; never exceed its per-call allowance.
    for size in (50,35,20,10):
        prepared=prepare_final(base,original,core_cues=size,keyed_coverage=True)
        windows=prepared['chunks'];selected=[]
        cited={q['segment_id'] for d in base['drafts'] for c in d['claims'] for q in c['citations']}
        count=min(quota,len(windows))
        for band in range(count):
            start=band*len(windows)//count;stop=(band+1)*len(windows)//count
            candidates=windows[start:stop]
            def rank(c):
                return sum(len(s['text']) for s in c['payload']['segments'] if
                           s['segment_id'] not in cited and not s['text'].strip().startswith(('[','(')))
            selected.append(max(candidates,key=rank))
        if all(Decimal(reservation_preview([c],values,16000)['reservation'])<=AUDIT_CEILING for c in selected):
            prepared['chunks']=selected
            prepared['selection_policy']='temporal_bands_prioritizing_uncited_speech; not_exhaustive_coverage'
            validate_prepared(prepared,base)
            return prepared
    raise ValueError('Audit payload cannot fit the allocated per-call ceiling; no audit call made')


def guarded_provider(values,ledger,group,max_requests):
    configured={**values,'TRIPPY_LUNA_REQUEST_GROUP':group,'TRIPPY_LUNA_MAX_REQUESTS':str(max_requests)}
    def request(chunk):
        label=('audit' if group.endswith('-audit') else 'extraction')+' '+chunk['payload']['source']['external_id']+' / '+chunk['id'][:8]
        with closing(sqlite3.connect(Path(ledger).resolve().as_uri()+'?mode=ro',uri=True)) as db:
            previous=db.execute('SELECT id FROM extraction_requests WHERE request_group=? AND chunk_id=? ORDER BY id LIMIT 1',
                                (group,chunk['id'])).fetchone()
        if previous:
            receipt=Path(ledger).parent/'extraction-raw-responses'/f'request-{previous[0]}.json'
            if not receipt.exists():
                allowed={int(x) for x in values.get('TRIPPY_INTERRUPTED_REQUESTS','').split(',') if x}
                if previous[0] not in allowed:
                    raise ValueError('Prior request has no usable receipt; implicit retry refused')
                progress('Recovering confirmed interrupted request '+str(previous[0])+'; old reservation retained')
                return guarded_provider(values,ledger,group+'-recovery-'+str(previous[0]),1)(chunk)
            document=json.loads(receipt.read_text());choice=document['choices'][0]
            if choice['finish_reason']!='stop' or choice['message'].get('refusal'):
                raise ValueError('Prior request did not complete; implicit retry refused')
            progress('Reusing saved response: '+label)
            return json.loads(choice['message']['content'])
        progress('Calling Luna: '+label)
        stop=Event()
        def heartbeat():
            seconds=0
            while not stop.wait(20):
                seconds+=20;progress('Waiting for Luna: '+label+' ('+str(seconds)+'s)')
        thread=Thread(target=heartbeat,daemon=True);thread.start()
        try:
            result=request_with_deadline(configured,ledger,chunk);progress('Response received: '+label);return result
        except Exception:
            progress('Request failed: '+label+'; retained receipt/checkpoint will show details')
            raise
        finally:stop.set();thread.join()
    return request


def run_video(video,plan,values,ledger,root,catalog):
    sid=video['source_id'];folder=Path(root)/sid;folder.mkdir(parents=True,exist_ok=True)
    progress('Starting video: '+video['title']+' ('+str(video['primary_calls'])+' extraction + '+str(video['audit_calls'])+' audit calls)')
    final=folder/'final.json'
    if final.exists():
        saved=json.loads(final.read_text())
        if saved.get('batch_plan_sha256')!=plan['plan_sha256']:raise ValueError('Final checkpoint belongs to a different batch')
        return saved['batch_summary']
    primary_path=folder/'primary.json';original={'chunks':video['chunks']}
    group='barcelona-size-v1-'+plan['plan_sha256'][:12]+'-'+sid
    if primary_path.exists():
        base=json.loads(primary_path.read_text())
        if base.get('batch_plan_sha256')!=plan['plan_sha256']:raise ValueError('Primary checkpoint belongs to a different batch')
    else:
        provider=guarded_provider(values,ledger,group+'-primary',video['primary_calls'])
        results,errors=execute_chunks(video['chunks'],provider,folder/'primary-cache',max_attempts=1)
        base=aggregate(results,catalog);base.update(primary_failures=errors,batch_plan_sha256=plan['plan_sha256'])
        private_write(primary_path,base)
    progress('Extraction saved: '+video['title']+' / '+str(len(base['drafts']))+' draft records')
    prepared=select_audits(base,original,video['audit_calls'],values)
    if prepared:
        manifest=folder/'audit-manifest.json'
        if manifest.exists():
            saved=json.loads(manifest.read_text());validate_prepared(saved,base);prepared=saved
        else:private_write(manifest,prepared)
        provider=guarded_provider(values,ledger,group+'-audit',len(prepared['chunks']))
        result=execute_audit(prepared,base,provider,folder/'audit-cache',catalog,original)
    else:result=base
    # Keep all original speech available even when no paid second pass is needed.
    cues={s['segment_id']:s for c in original['chunks'] for s in c['payload']['segments']}
    audited={s['segment_id'] for c in prepared['chunks'] for s in c['payload']['segments']} if prepared else set()
    result['source_evidence_inventory']=[{**s,'additional_audit_selected':key in audited} for key,s in cues.items()]
    result['primary_failures']=base.get('primary_failures',[])
    result['ready_to_publish']=False;result['ready_to_scale']=False
    summary={'source_id':sid,'title':video['title'],'planned_primary_calls':video['primary_calls'],
        'planned_audit_calls':video['audit_calls'],'actual_audit_windows':len(prepared['chunks']) if prepared else 0,
        'draft_records':len(result['drafts']),'claims':sum(len(d['claims']) for d in result['drafts']),
        'original_cues':len(cues),'additional_audited_cues':len(audited),
        'primary_failures':len(result.get('primary_failures',[])),
        'audit_failures':len(result.get('execution_failures',[])),
        'status':'private_results_require_semantic_identity_and_current_fact_review'}
    result['batch_summary']=summary;result['batch_plan_sha256']=plan['plan_sha256']
    private_write(final,result)
    print(json.dumps(summary,ensure_ascii=False),flush=True)
    return summary


def execute_batch(plan,original,values,ledger,root,catalog=None,workers=2):
    validate_plan(plan,original)
    if Decimal(values['TRIPPY_AI_BUDGET_AMOUNT'])<Decimal(plan['summary']['total_reservation_ceiling']):
        raise ValueError('Configured shared cap cannot cover the complete planned batch')
    with closing(sqlite3.connect(Path(ledger).resolve().as_uri()+'?mode=ro',uri=True)) as db:
        used=Decimal(db.execute('SELECT reserved FROM extraction_budget WHERE id=1').fetchone()[0])
        attempted={(g,c) for g,c in db.execute('SELECT request_group,chunk_id FROM extraction_requests')}
        recovery_rows=[]
        for request_id in {int(x) for x in values.get('TRIPPY_INTERRUPTED_REQUESTS','').split(',') if x}:
            row=db.execute('SELECT request_group,chunk_id FROM extraction_requests WHERE id=?',(request_id,)).fetchone()
            if row is None:raise ValueError('Unknown interrupted request')
            if not row[0].startswith('barcelona-size-v1-'+plan['plan_sha256'][:12]+'-'):
                raise ValueError('Interrupted request belongs to another plan')
            recovery_rows.append((request_id,*row))
    # Do not bypass a shared cap if other work consumed funds after preparation.
    if used<Decimal(plan['summary']['existing_reserved']):raise ValueError('Shared budget ledger was reset')
    tasks=[v for v in plan['videos'] if v['status']=='scheduled'];summaries=[];failures=[]
    progress('Batch starting: '+str(len(tasks))+' videos; '+str(workers)+' workers; shared hard cap $'+values['TRIPPY_AI_BUDGET_AMOUNT'])
    remaining=Decimal(0)
    for request_id,group,chunk_id in recovery_rows:
        receipt=Path(ledger).parent/'extraction-raw-responses'/f'request-{request_id}.json'
        if receipt.exists() or (group+'-recovery-'+str(request_id),chunk_id) in attempted:continue
        chunks=[c for v in tasks for c in v['chunks'] if c['id']==chunk_id]
        if len(chunks)!=1:raise ValueError('Recovery requires one matching primary chunk')
        remaining+=Decimal(reservation_preview(chunks,values,16000)['reservation'])
    for video in tasks:
        if (Path(root)/video['source_id']/'final.json').exists():continue
        group='barcelona-size-v1-'+plan['plan_sha256'][:12]+'-'+video['source_id']
        pending=[c for c in video['chunks'] if (group+'-primary',c['id']) not in attempted]
        remaining+=Decimal(reservation_preview(pending,values,16000)['reservation'])
        audits_attempted=sum(g==group+'-audit' for g,c in attempted)
        remaining+=AUDIT_CEILING*max(0,video['audit_calls']-audits_attempted)
    if used+remaining>Decimal(values['TRIPPY_AI_BUDGET_AMOUNT']):
        raise ValueError('Shared budget cannot cover outstanding batch requests')
    progress('Outstanding reservation ceiling $'+str(remaining)+'; total ceiling $'+str(used+remaining))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        jobs={pool.submit(run_video,v,plan,values,ledger,root,catalog):v for v in tasks}
        for job in as_completed(jobs):
            video=jobs[job]
            try:summaries.append(job.result())
            except Exception as exc:
                failure={'source_id':video['source_id'],'error_type':type(exc).__name__,
                    'reason':str(exc) if isinstance(exc,ValueError) else 'Batch video failed; inspect retained checkpoints'}
                failures.append(failure);print(json.dumps(failure),flush=True)
    return {'version':1,'status':'private_batch_completed_with_review_pending','plan_sha256':plan['plan_sha256'],
        'videos':summaries,'failed_videos':failures,
        'retained_pilots':[v['source_id'] for v in plan['videos'] if v['status']=='reuse_completed_pilot'],
        'manual_review_sources':[v['source_id'] for v in plan['videos'] if v['status']=='thin_transcript_requires_manual_review'],
        'ready_to_publish':False,'ready_to_scale':False}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--env-file',type=Path,default=Path('.env'))
    p.add_argument('--ledger',type=Path,default=Path('.local/stage3/extraction-budget.sqlite'))
    p.add_argument('--plan',type=Path);p.add_argument('--execute-private-batch',action='store_true')
    p.add_argument('--recover-interrupted-request',type=int,action='append',default=[])
    p.add_argument('--results-root',type=Path,default=Path('.local/stage3/size-batch-v1'))
    p.add_argument('--catalog',type=Path,default=Path('.local/catalog.sqlite'))
    args=p.parse_args()
    from trippy_config import read_environment
    values=read_environment(args.env_file)
    values['TRIPPY_INTERRUPTED_REQUESTS']=','.join(str(x) for x in args.recover_interrupted_request)
    with closing(sqlite3.connect(args.ledger.resolve().as_uri()+'?mode=ro',uri=True)) as db:
        used=db.execute('SELECT reserved FROM extraction_budget WHERE id=1').fetchone()[0]
    original=json.loads(args.original.read_text())
    if args.execute_private_batch:
        if not args.plan:p.error('Execution requires the prepared --plan')
        plan=json.loads(args.plan.read_text())
        result=execute_batch(plan,original,values,args.ledger,args.results_root,args.catalog)
        private_write(args.output,result);print(json.dumps({'completed':len(result['videos']),'failed':len(result['failed_videos'])}));return
    plan=prepare_batch(original,values,used)
    private_write(args.output,plan)
    lines=['# Barcelona video run allocation','',
        'Private source research. Completed pilots are reused. Thin transcripts remain for manual review.','',
        '| Video | Transcript characters | Primary calls | Additional audit calls | Status |',
        '|---|---:|---:|---:|---|']
    for v in plan['videos']:
        lines.append('| '+v['title'].replace('|','/')+' | '+str(v['transcript_characters'])+' | '+str(v['primary_calls'])+' | '+str(v['audit_calls'])+' | '+v['status']+' |')
    lines+=['','```json',json.dumps(plan['summary'],indent=2),'```']
    args.output.with_suffix('.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps(plan['summary']))


if __name__=='__main__':main()
