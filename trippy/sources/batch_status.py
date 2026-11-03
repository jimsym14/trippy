"""Read-only monitoring of a running video batch; never calls an API."""
import argparse
from contextlib import closing
from datetime import datetime,timezone
import json
from pathlib import Path
import sqlite3
import time
from decimal import Decimal
import html
import shutil
import sys
import unicodedata


def snapshot(plan,ledger,root,*,rates=None,cap='5',summary_path=None):
    prefix='barcelona-size-v1-'+plan['plan_sha256'][:12]+'-'
    with closing(sqlite3.connect(Path(ledger).resolve().as_uri()+'?mode=ro',uri=True)) as db:
        reserved=db.execute('SELECT reserved FROM extraction_budget WHERE id=1').fetchone()[0]
        rows=db.execute('SELECT id,request_group,created_at,amount FROM extraction_requests WHERE request_group LIKE ? ORDER BY id',
                        (prefix+'%',)).fetchall()
    received=0;incomplete=0;pending=[];recovery_started=0
    videos=[v for v in plan['videos'] if v['status']=='scheduled']
    tasks={v['source_id']:{'source_id':v['source_id'],'title':v['title'],
        'planned_calls':v.get('total_calls',v.get('primary_calls',0)+v.get('audit_calls',0)),
        'reservation_ceiling':str(Decimal(v.get('primary_reservation','0'))+Decimal(v.get('audit_reservation_ceiling','0'))),
        'primary':{'started':0,'received':0,'reserved':Decimal(0),'estimated':Decimal(0),'usage_receipts':0},
        'audit':{'started':0,'received':0,'reserved':Decimal(0),'estimated':Decimal(0),'usage_receipts':0}}
        for v in videos}
    activity=[]
    for request_id,group,at,amount in rows:
        activity.append(datetime.fromisoformat(at).timestamp())
        suffix=group[len(prefix):];sid,stage=suffix[:11],suffix[12:]
        if '-recovery-' in stage:
            stage=stage.split('-recovery-',1)[0];recovery_started+=1
        task=tasks.get(sid);stage_data=task.get(stage) if task else None
        if stage_data is not None:
            stage_data['started']+=1;stage_data['reserved']+=Decimal(amount)
        path=Path(ledger).parent/'extraction-raw-responses'/f'request-{request_id}.json'
        if path.exists():
            try:
                result=json.loads(path.read_text());reason=result['choices'][0]['finish_reason']
            except (ValueError,KeyError):pending.append((request_id,group,at));continue
            received+=1;incomplete+=reason!='stop'
            activity.append(path.stat().st_mtime)
            if stage_data is not None:
                stage_data['received']+=1
                usage=result.get('usage')
                if rates and usage and usage.get('prompt_tokens') is not None and usage.get('completion_tokens') is not None:
                    estimate=(Decimal(usage['prompt_tokens'])*Decimal(rates['input'])+
                              Decimal(usage['completion_tokens'])*Decimal(rates['output']))/Decimal(1000000)
                    stage_data['estimated']+=estimate;stage_data['usage_receipts']+=1
        else:pending.append((request_id,group,at))
    finished=[v for v in videos if (Path(root)/v['source_id']/'final.json').exists()]
    finished_ids={v['source_id'] for v in finished};now=datetime.now(timezone.utc)
    primary_issue_chunks=0;primary_execution_failures=0
    for sid,task in tasks.items():
        waits=[(g,at) for _,g,at in pending if g.startswith(prefix+sid+'-')]
        task['started']=sum(task[s]['started'] for s in ('primary','audit'))
        if sid in finished_ids:
            task['state']='saved';activity.append((Path(root)/sid/'final.json').stat().st_mtime)
            document=json.loads((Path(root)/sid/'final.json').read_text())
            issues=document.get('primary_failures',[])
            primary_issue_chunks+=len(issues)
            primary_execution_failures+=sum(e.get('error_type')!='PartialEvidenceValidation' for e in issues)
        elif waits:
            age=max((now-datetime.fromisoformat(at)).total_seconds() for _,at in waits)
            task['state']='check wait' if age>180 else ('audit' if waits[0][0].endswith('-audit') else 'extract')
        else:task['state']='processing' if task['started'] else 'queued'
        for stage in ('primary','audit'):
            for name in ('reserved','estimated'):task[stage][name]=str(task[stage][name])
    summary=None
    if summary_path and Path(summary_path).exists():
        try:summary=json.loads(Path(summary_path).read_text())
        except ValueError:pass
    return {'reserved':reserved,'started':len(rows),'received':received,'incomplete':incomplete,
        'pending':pending,'finished':len(finished),'planned_videos':len(videos),
        'max_calls':plan['summary']['new_calls']+recovery_started,'recovery_started':recovery_started,
        'primary_issue_chunks':primary_issue_chunks,'primary_execution_failures':primary_execution_failures,
        'titles':{v['source_id']:v['title'] for v in videos},
        'prefix':prefix,'tasks':list(tasks.values()),'cap':cap,
        'batch_reserved':str(sum((Decimal(t[s]['reserved']) for t in tasks.values() for s in ('primary','audit')),Decimal(0))),
        'batch_estimated':str(sum((Decimal(t[s]['estimated']) for t in tasks.values() for s in ('primary','audit')),Decimal(0))),
        'usage_receipts':sum(t[s]['usage_receipts'] for t in tasks.values() for s in ('primary','audit')),
        'last_activity':datetime.fromtimestamp(max(activity),timezone.utc).isoformat() if activity else None,
        'batch_complete':summary is not None,'failed_videos':len(summary.get('failed_videos',[])) if summary else 0}


def display(status,*,dashboard=False,clear=False):
    now=datetime.now(timezone.utc)
    if dashboard:
        if clear and sys.stdout.isatty():print('\033[2J\033[H',end='')
        print('BARCELONA RESEARCH  |  '+now.strftime('%H:%M:%S UTC'),flush=True)
        print(str(status['finished'])+'/'+str(status['planned_videos'])+' videos saved   '+str(status['received'])+
              ' responses received   '+str(status['started'])+'/'+str(status['max_calls'])+' calls started')
        print('Shared reservation: $'+format(Decimal(status['reserved']),'.4f')+' / $'+status['cap']+
              '   Batch reservation: $'+format(Decimal(status['batch_reserved']),'.4f')+
              '   Batch token estimate: $'+format(Decimal(status['batch_estimated']),'.4f'))
        if status.get('primary_issue_chunks'):
            print('Saved outputs contain '+str(status['primary_execution_failures'])+' failed primary chunks and '+
                  str(status['primary_issue_chunks']-status['primary_execution_failures'])+' chunks with quarantined evidence. Quality review remains pending.')
        if status['last_activity']:
            last=datetime.fromisoformat(status['last_activity']);age=int((now-last).total_seconds())
            print('Last real request/response activity: '+last.strftime('%H:%M:%S UTC')+' ('+str(age)+'s ago)')
            if age>180 and not status['batch_complete']:
                print('No recent API/file activity. A refreshed screen or increasing wait timer is not job progress.')
        width=max(24,min(46,shutil.get_terminal_size((120,40)).columns-77))
        print('\n'+f'{"Video":<{width}} {"State":<10} {"Calls":<7} {"Extract est/res $":<18} {"Audit est/res $":<18} {"Cap $":>7}')
        order={'check wait':0,'extract':1,'audit':1,'processing':2,'saved':3,'queued':4}
        def money(stage):
            estimate=format(Decimal(stage['estimated']),'.4f') if stage['usage_receipts'] else '--'
            return estimate+'/'+format(Decimal(stage['reserved']),'.4f')
        for task in sorted(status['tasks'],key=lambda t:order.get(t['state'],9)):
            title=html.unescape(task['title']);title=''.join(c for c in title if unicodedata.category(c)!='So')
            title=' '.join(title.split());title=title[:width-1]+'…' if len(title)>width else title
            calls=str(task['started'])+'/'+str(task['planned_calls'])
            print(f'{title:<{width}} {task["state"]:<10} {calls:<7} {money(task["primary"]):<18} {money(task["audit"]):<18} {Decimal(task["reservation_ceiling"]):>7.4f}')
        print('\nEst = recorded tokens at configured rates, without cache discounts; not an invoice.')
        print('Res = conservative reservation, including calls without a saved response. -- = usage unavailable.')
        if status['batch_complete']:print('Batch finished. Videos with execution failures: '+str(status['failed_videos']))
        print('',flush=True)
        return
    print('\n['+now.strftime('%H:%M:%S UTC')+'] '+str(status['finished'])+'/'+str(status['planned_videos'])+
          ' videos saved | '+str(status['started'])+'/'+str(status['max_calls'])+
          ' calls started | '+str(status['received'])+' responses received | $'+status['reserved']+' reserved',flush=True)
    for request_id,group,at in status['pending']:
        suffix=group[len(status['prefix']):];sid,stage=suffix.rsplit('-',1)
        age=int((now-datetime.fromisoformat(at)).total_seconds())
        print('  Pending receipt #'+str(request_id)+': '+status['titles'].get(sid,sid)+' / '+stage+
              ' / '+str(age)+'s since request started',flush=True)
    if status['incomplete']:print('  Incomplete API responses retained: '+str(status['incomplete']),flush=True)
    print('  This reads saved files; a pending receipt alone does not prove the process is still alive.',flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan',type=Path,default=Path('.local/stage3/sources/barcelona-size-based-batch-plan.json'))
    p.add_argument('--ledger',type=Path,default=Path('.local/stage3/extraction-budget.sqlite'))
    p.add_argument('--root',type=Path,default=Path('.local/stage3/size-batch-v1'))
    p.add_argument('--watch',action='store_true');p.add_argument('--dashboard',action='store_true')
    p.add_argument('--env-file',type=Path,default=Path('.env'))
    p.add_argument('--summary',type=Path,default=Path('.local/stage3/sources/barcelona-size-based-batch-result.json'))
    p.add_argument('--status-file',type=Path)
    args=p.parse_args();plan=json.loads(args.plan.read_text())
    from trippy_config import read_environment
    values=read_environment(args.env_file)
    rates={'input':values['TRIPPY_LUNA_INPUT_PER_MILLION'],'output':values['TRIPPY_LUNA_OUTPUT_PER_MILLION']}
    while True:
        status=snapshot(plan,args.ledger,args.root,rates=rates,cap=values['TRIPPY_AI_BUDGET_AMOUNT'],summary_path=args.summary)
        display(status,dashboard=args.dashboard,clear=args.watch)
        if args.status_file:
            args.status_file.parent.mkdir(parents=True,exist_ok=True)
            temporary=args.status_file.with_suffix('.tmp');temporary.write_text(json.dumps(status,ensure_ascii=False,indent=2));temporary.replace(args.status_file)
        if not args.watch or status['batch_complete'] or status['finished']==status['planned_videos']:break
        try:time.sleep(15)
        except KeyboardInterrupt:break


if __name__=='__main__':main()
