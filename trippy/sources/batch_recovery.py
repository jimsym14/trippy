"""Explicit, checkpointed recovery of failed primary passages; private outputs."""
import argparse
from contextlib import closing
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import sqlite3

from .batch import guarded_provider, progress
from .coverage import MENTION_FIELDS, private_write, reservation_preview
from .extraction import aggregate, execute_chunks, fingerprint, validate_result


def prepare(plan, root, values):
    tasks=[]
    for video in plan['videos']:
        if video['status']!='scheduled':continue
        path=Path(root)/video['source_id']/'final.json'
        base=json.loads(path.read_text())
        if base['batch_plan_sha256']!=plan['plan_sha256']:
            raise ValueError('Final checkpoint belongs to another plan')
        failures=[e for e in base.get('primary_failures',[]) if e['error_type']!='PartialEvidenceValidation']
        if not failures:continue
        chunks=[]
        for failure in failures:
            original=next(c for c in video['chunks'] if c['id']==failure['chunk_id'])
            segments=original['payload']['segments']
            # Smaller passages prevent the previous 16k output truncation and
            # reduce latency. Two-cue overlap retains boundary context.
            middle=len(segments)//2
            parts=([segments] if len(segments)==1 else
                [segments[:middle],segments[middle:]] if len(segments)<4 else
                [segments[:middle+1],segments[middle-1:]])
            for part in parts:
                chunk=deepcopy(original);chunk['payload']['segments']=part
                chunk['id']=fingerprint({'prompt':chunk['system_prompt'],
                    'schema':chunk['response_schema'],'payload':chunk['payload']})
                chunks.append(chunk)
        tasks.append({'source_id':video['source_id'],'title':video['title'],
            'base_path':str(path),'base_sha256':fingerprint(base),
            'failed_chunk_ids':[e['chunk_id'] for e in failures],'chunks':chunks})
    manifest={'version':1,'batch_plan_sha256':plan['plan_sha256'],'tasks':tasks,
        'calls':sum(len(t['chunks']) for t in tasks),'ready_to_publish':False,
        'reservation_ceiling':reservation_preview([c for t in tasks for c in t['chunks']],values,16000)['reservation']}
    manifest['sha256']=fingerprint(manifest)
    return manifest


def execute(manifest, values, ledger, output_root, catalog=None):
    if manifest['sha256']!=fingerprint({k:v for k,v in manifest.items() if k!='sha256'}):
        raise ValueError('Recovery manifest fingerprint mismatch')
    root=Path(output_root);prefix='barcelona-failed-passages-'+manifest['sha256'][:12]
    with closing(sqlite3.connect(Path(ledger).resolve().as_uri()+'?mode=ro',uri=True)) as db:
        used=Decimal(db.execute('SELECT reserved FROM extraction_budget WHERE id=1').fetchone()[0])
        attempted={(g,c) for g,c in db.execute('SELECT request_group,chunk_id FROM extraction_requests')}
    pending=[c for t in manifest['tasks'] for c in t['chunks']
        if (prefix+'-'+t['source_id'],c['id']) not in attempted]
    extra=Decimal(reservation_preview(pending,values,16000)['reservation'])
    if used+extra>Decimal(values['TRIPPY_AI_BUDGET_AMOUNT']):
        raise ValueError('Shared cap cannot cover recovery; no requests made')
    progress('Recovery: '+str(manifest['calls'])+' planned calls; additional reserve $'+str(extra)+
        '; shared ceiling $'+str(used+extra)+' / $'+values['TRIPPY_AI_BUDGET_AMOUNT'])
    summaries=[]
    for task in manifest['tasks']:
        folder=root/task['source_id'];final=folder/'final.json'
        base=json.loads(Path(task['base_path']).read_text())
        if fingerprint(base)!=task['base_sha256']:raise ValueError('Recovery base changed')
        if final.exists():
            saved=json.loads(final.read_text())
            if saved['recovery_manifest_sha256']!=manifest['sha256']:raise ValueError('Recovery checkpoint mismatch')
            summaries.append(saved['recovery_summary']);continue
        provider=guarded_provider(values,ledger,prefix+'-'+task['source_id'],len(task['chunks']))
        results,errors=execute_chunks(task['chunks'],provider,folder/'cache',max_attempts=1)
        cues=base['source_evidence_inventory']
        original={'payload':{**task['chunks'][0]['payload'],'segments':cues}}
        old={'mentions':[{k:d[k] for k in MENTION_FIELDS} for d in base['drafts']]}
        validate_result(original,old)
        merged=aggregate([(original,old),*results],catalog)
        for draft in merged['drafts']:
            validate_result(original,{'mentions':[{k:draft[k] for k in MENTION_FIELDS}]})
        complete=len(results)==len(task['chunks'])
        retained=[e for e in base.get('primary_failures',[]) if not complete or e['chunk_id'] not in task['failed_chunk_ids']]
        summary={'source_id':task['source_id'],'title':task['title'],
            'replacement_chunks':len(task['chunks']),'validated_replacement_chunks':len(results),
            'old_records':len(base['drafts']),'records':len(merged['drafts']),
            'old_claims':sum(len(d['claims']) for d in base['drafts']),
            'claims':sum(len(d['claims']) for d in merged['drafts']),
            'failed_passages_recovered':complete,'replacement_validation_issues':len(errors)}
        merged.update(recovery_manifest_sha256=manifest['sha256'],recovery_summary=summary,
            prior_result={'path':task['base_path'],'sha256':task['base_sha256']},
            prior_review_metadata={k:base.get(k) for k in ('review_issues','final_check','audit_lineage',
                'relationship_proposals','audit_results','primary_failures')},
            prior_review_reconciliation_pending=True,primary_failures=retained,
            recovery_failures=errors,source_evidence_inventory=cues,
            ready_to_publish=False,ready_to_scale=False)
        # Write a separate version; original outputs and audit references remain
        # available for review and cannot be silently overwritten.
        private_write(final,merged);summaries.append(summary)
        progress(json.dumps(summary,ensure_ascii=False))
    result={'version':1,'manifest_sha256':manifest['sha256'],'videos':summaries,
        'ready_to_publish':False,'semantic_identity_current_fact_review_pending':True}
    path=root/'summary.json'
    if not path.exists():private_write(path,result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',type=Path,default=Path('.local/stage3/sources/barcelona-size-based-batch-plan.json'))
    parser.add_argument('--results-root',type=Path,default=Path('.local/stage3/size-batch-v1'))
    parser.add_argument('--output-root',type=Path,default=Path('.local/stage3/failed-passages-recovery-v1'))
    parser.add_argument('--ledger',type=Path,default=Path('.local/stage3/extraction-budget.sqlite'))
    parser.add_argument('--env-file',type=Path,default=Path('.env'))
    parser.add_argument('--execute',action='store_true')
    args=parser.parse_args()
    from trippy_config import read_environment
    values=read_environment(args.env_file)
    manifest=prepare(json.loads(args.plan.read_text()),args.results_root,values)
    path=args.output_root/'manifest.json'
    if path.exists():
        if json.loads(path.read_text())!=manifest:raise ValueError('Recovery manifest changed')
    else:private_write(path,manifest)
    progress('Prepared '+str(manifest['calls'])+' calls; conservative additional reserve $'+manifest['reservation_ceiling'])
    if args.execute:execute(manifest,values,args.ledger,args.output_root,Path('.local/catalog.sqlite'))


if __name__=='__main__':main()
