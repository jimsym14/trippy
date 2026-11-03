"""Prepare, run and report all three dataset evidence layers without publication."""
import argparse
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import datetime, timezone
from decimal import Decimal
import json
from pathlib import Path

from trippy_config import read_environment, configured
from trippy.sources.curation_cycle import load_pack, validate_pack
from trippy.sources.extraction import fingerprint
from trippy.sources.extraction import Claim
from trippy.sources.identity_review import read_inventory, propose
from trippy.sources.semantic_review import ledger_state, reservation
from trippy.sources.unattended import immutable_write, mutable_write
from trippy.sources.unattended import recover_provider_response
from trippy.sources.scoped_annotations import materialize as materialize_manual_tags
from . import reviews, providers, queue
from .reviews import source_chunk, annotation_chunk
from .queue import job, Runner
from .providers import CAPABILITIES, canonical_url, automatic_identity, field_state


def read(path): return json.loads(Path(path).read_text())


def engine_sha256():
    files=[Path(__file__),Path(reviews.__file__),Path(providers.__file__),Path(queue.__file__)]
    from trippy.sources import luna, semantic_review, unattended, batch
    files += [Path(m.__file__) for m in (luna,semantic_review,unattended,batch)]
    return fingerprint({str(p.relative_to(Path(__file__).parents[2])):fingerprint(p.read_text()) for p in files})


def limited_chunks(entries, builder, *, per_call, max_bytes):
    output=[]; page=[]
    for entry in entries:
        candidate=builder(page+[entry])
        if page and (len(page)>=per_call or len(json.dumps(candidate).encode())>max_bytes):
            output.append(builder(page)); page=[entry]
        else: page.append(entry)
        if len(json.dumps(builder(page)).encode())>max_bytes:
            raise ValueError('Single review exceeds bounded input; split the source case explicitly')
    if page: output.append(builder(page))
    return output


def observation(record):
    urls=[c['value'].strip() for c in record['claims'] if c['dimension']=='website' and c['value'].strip().startswith('https://')]
    return {'id':record['id'],'name':record['name'],'branch':record.get('branch'),
        'source_url':urls[0] if len(urls)==1 else '',
        'facts':[{'field':'address','value':c['value']} for c in record['claims'] if c['dimension']=='address']}


def discovery_inventory(rows, config):
    selected=[]
    for role, spec in config['discovery_roles'].items():
        eligible=[r for r in rows if r['source_category'] in spec['source_categories'] and
                  r.get('website_url') and r.get('address') and
                  r.get('operating_status') not in {'temporarily_closed','permanently_closed'}]
        by_area=defaultdict(list)
        for row in sorted(eligible,key=lambda r:(-(r.get('confidence') or 0),r['entity_id'])):
            by_area[row['area_key'] or 'unknown'].append(row)
        areas=sorted(by_area); chosen=[]
        while len(chosen)<spec['limit'] and any(by_area.values()):
            for area in areas:
                if by_area[area]: chosen.append(by_area[area].pop(0))
                if len(chosen)>=spec['limit']: break
        selected += [{'role':role,'candidate':r,'status':'inventory_discovery_candidate_not_service_verified'} for r in chosen]
    return selected


def operator_candidate_url(url):
    domain=providers.host(url)
    excluded={'google.com','google.es','maps.app.goo.gl','goo.gl','g.page',
        'facebook.com','instagram.com','youtube.com','youtu.be','tiktok.com',
        'tripadvisor.com','tripadvisor.es','booking.com','yelp.com','foursquare.com'}
    return not any(domain==target or domain.endswith('.'+target) for target in excluded)


def validate_config(config):
    if config['automatic_publication'] is not False: raise ValueError('Completion runner cannot publish')
    caps=[Decimal(config['task_caps'][k]) for k in queue.AI_STAGES]
    if any(not c.is_finite() or not Decimal(0)<c<=Decimal(config['queue_cap']) for c in caps):
        raise ValueError('Each stage maximum must fit the combined queue cap')
    # Stage maxima overlap; their sum is not an additional budget allocation.
    # Every dispatch also checks the combined queue and original shared ledger.
    if not Decimal(0)<Decimal(config['queue_cap'])<=Decimal(config['shared_cap'])<=Decimal(15):
        raise ValueError('Preserve the original $15 shared budget')
    for key, low, high in [('max_attempts',1,5),('max_rate_limit_attempts',1,10),
            ('max_http_requests',1,500),('max_ai_requests_per_stage',1,100),('max_operator_pages',1,100),
            ('max_total_wait_seconds',1,43200),('provider_timeout_seconds',1,600),('worker_timeout_seconds',1,660)]:
        if type(config[key]) is not int or not low<=config[key]<=high: raise ValueError('Invalid bounded queue setting: '+key)
    if config['worker_timeout_seconds']<=config['provider_timeout_seconds']:
        raise ValueError('Worker deadline must exceed provider timeout')
    if not 1<=config['host_delay_seconds']<=60: raise ValueError('Bounded per-host pacing required')
    if not 1<=config['annotation_per_call']<=20 or not 1<=config['source_per_call']<=8:
        raise ValueError('Bounded editorial batches required')
    if any(type(n) is not int or not 1000<=n<=16000 for n in config['output_tokens'].values()):
        raise ValueError('Invalid output token allocation')
    if set(config['output_tokens'])!=queue.AI_STAGES or set(config['task_caps'])!=queue.AI_STAGES:
        raise ValueError('All AI stages require explicit caps')
    if any(not 0<days<=365 for days in config['refresh_days'].values()):
        raise ValueError('Explicit bounded field refresh policy required')
    if not 1<=config.get('web_cache_max_age_seconds',86400)<=min(config['refresh_days'].values())*86400:
        raise ValueError('Operator cache cannot exceed the strictest requested field refresh interval')
    if not config['request_prefix'].replace('-','').replace('_','').isalnum() or len(config['request_prefix'])>70:
        raise ValueError('Invalid durable request group prefix')


def prepare(config, values, *, inventory_reader=read_inventory):
    validate_config(config)
    if not Path(config['ledger']).is_file(): raise ValueError('Original shared budget ledger missing; do not create a replacement')
    paths={k:config[k] for k in ('pack','held','expanded_prepared','annotation_proposals','manual_tag_audit','registry','primary_observations','source_recipe')}
    inputs={k:read(p) for k,p in paths.items()}
    source_recipe=inputs['source_recipe']; _,cues,_=load_pack(read(source_recipe['inputs'])['inputs'],read(source_recipe['original']))
    pack=inputs['pack']; held=inputs['held']; validate_pack(pack['drafts'],cues)
    expanded={e['key']:e for c in inputs['expanded_prepared']['chunks'] for e in c['payload']['entries']}
    source_entries=[]
    for pending in held:
        if pending.get('followup_review'): continue  # Existing manual holds are authoritative.
        entry=expanded[pending['key']]
        if entry['claim']!=pending['original_claim'] or entry['occurrence_id']!=pending['upstream_occurrence_id']:
            raise ValueError('Pending source/context binding differs')
        source_entries.append(entry)
    jobs=[]
    for request in limited_chunks(source_entries,lambda es:source_chunk(es,cues),per_call=config['source_per_call'],max_bytes=config['max_request_bytes']):
        jobs.append(job('source',{'request':request}))
    reviewed={(r['record_id'],r['facet_sha256']) for r in inputs['manual_tag_audit']['reviews']}
    proposals=inputs['annotation_proposals']; prepared_records={}; annotation_entries=defaultdict(list)
    for c in proposals['chunks']:
        sources={e['record_id']:e for e in c['source_entries']}
        for record_id, response in c['response']['records'].items():
            source=sources[record_id]; claims={c['id']:c for c in source['claims']}; prepared_records[record_id]=source
            for kind, field in [('facet','facets'),('detail','details'),('activity_fit','activity_fit_proposals')]:
                for value in response[field]:
                    if kind=='facet' and (record_id,fingerprint(value)) in reviewed: continue
                    ids=value['claim_ids']
                    if not ids or not set(ids)<=set(claims): raise ValueError('Annotation proposal has foreign evidence')
                    entry={'key':fingerprint({'record_id':record_id,'kind':kind,'proposal':value}),
                        'record_id':record_id,'name':source['name'],'kind':kind,'proposal':value,
                        'claims':[claims[i] for i in ids],'record_kind':source['kind'],
                        'identity_uncertain':source['identity_uncertain']}
                    annotation_entries[{'facet':'facets','detail':'details','activity_fit':'activity_fit'}[kind]].append(entry)
    quarantined=read(config['quarantined_facets'])
    for item in quarantined:
        source=prepared_records[item['record_id']]; claims={c['id']:c for c in source['claims']}
        entry={'key':fingerprint({'record_id':item['record_id'],'kind':'facet','proposal':item['facet']}),
            'record_id':item['record_id'],'name':source['name'],'kind':'facet','proposal':item['facet'],
            'claims':[claims[i] for i in item['facet']['claim_ids']],
            'record_kind':source['kind'],'identity_uncertain':source['identity_uncertain'],
            'taxonomy_admission_pending':True}
        annotation_entries['facets'].append(entry)
    for kind, entries in annotation_entries.items():
        if len({e['key'] for e in entries})!=len(entries): raise ValueError('Duplicate annotation review target')
        for request in limited_chunks(entries,lambda es:annotation_chunk(es,inputs['registry']),
                per_call=config['annotation_per_call'],max_bytes=config['max_request_bytes']):
            jobs.append(job(kind,{'request':request}))
    rows,version=inventory_reader(source_recipe['catalog'],source_recipe['catalog_city_id'],source_recipe['catalog_version_id'])
    observations=[observation(r) for r in pack['drafts'] if r['kind'] in {'venue','chain'}]
    for source in inputs['primary_observations']:
        observations.append({'id':source['id'],'name':source['name'],'source_url':source['source_url'],
            'branch':source.get('branch'),'facts':[f for f in source['facts'] if f['field']=='address']})
    groups=propose(observations,rows,limit=config['identity_candidate_limit'])
    discovery=discovery_inventory(rows,config)
    identity=job('identity_inventory',{'groups':groups,'catalog_version':version,
        'catalog_sha256':fingerprint(rows),'discovery_candidates':discovery,
        'status':'candidates_only; operator branch evidence required'})
    jobs.append(identity)
    urls={}; deferred_urls=[]; excluded_urls=[]
    def add_url(url, priority, candidate=None):
        try: url=canonical_url(url)
        except (ValueError,TypeError): return
        if not operator_candidate_url(url):
            excluded_urls.append({'url':url,'reason':'social_or_aggregator_url_not_an_operator_feed'}); return
        if url not in urls: urls[url]={'url':url,'priority':priority,'candidates':[]}
        urls[url]['priority']=min(priority,urls[url]['priority'])
        if candidate and candidate['entity_id'] not in {c['entity_id'] for c in urls[url]['candidates']}:
            urls[url]['candidates'].append(candidate)
    for source in inputs['primary_observations']: add_url(source['source_url'],0)
    for item in discovery: add_url(item['candidate']['website_url'],1,item['candidate'])
    for group in groups:
        for index,candidate in enumerate(group['candidates'][:config['web_candidates_per_group']]):
            if candidate.get('website_url'): add_url(candidate['website_url'],2+index,candidate)
    # Include all same-host shortlisted branch candidates for branch-level JSON-LD
    # comparison, without adding additional homepage requests.
    candidate_rows={r['entity_id']:r for r in rows}
    for item in urls.values():
        domain=providers.host(item['url'])
        for group in groups:
            for candidate in group['candidates']:
                if providers.host(candidate.get('website_url'))==domain:
                    full=candidate_rows[candidate['entity_id']]
                    if full['entity_id'] not in {c['entity_id'] for c in item['candidates']}: item['candidates'].append(full)
    ordered=sorted(urls.values(),key=lambda p:(p['priority'],p['url']))
    for index,item in enumerate(ordered):
        if index>=config['max_operator_pages']: deferred_urls.append(item); continue
        jobs.append(job('operator_fetch',item,deps=[identity['id']]))
    for feed in config.get('operator_feeds',[]):
        # The URL/field mapping is explicit configuration, never model generated.
        payload={'url':canonical_url(feed['url']),'feed':feed,'candidates':[
            r for r in rows if providers.host(r.get('website_url'))==providers.host(feed['url'])]}
        jobs.append(job('operator_feed',payload,deps=[identity['id']]))
    shared=ledger_state(config['ledger'],config['request_prefix']+'-source')[1]
    full_stage_reservations={kind:sum((reservation(j['payload']['request'],values,output=config['output_tokens'][kind])
        for j in jobs if j['kind']==kind),Decimal(0)) for kind in queue.AI_STAGES}
    stage_reservations={kind:Decimal(0) for kind in queue.AI_STAGES}; cached_requests=0
    for j in jobs:
        if j['kind'] not in queue.AI_STAGES: continue
        request=j['payload']['request']; group=config['request_prefix']+'-'+j['kind']
        try: cached=recover_provider_response(config['ledger'],group,request['id']) is not None
        except (ValueError,KeyError,TypeError): cached=True  # Invalid receipts become review handoffs, not paid retries.
        if cached: cached_requests+=1
        else: stage_reservations[j['kind']]+=reservation(request,values,output=config['output_tokens'][j['kind']])
    for kind,amount in stage_reservations.items():
        if amount>Decimal(config['task_caps'][kind]):
            raise ValueError(f'{kind} first pass exceeds allocation; no requests dispatched')
    fixed=sum(stage_reservations.values())
    if fixed>Decimal(config['queue_cap']) or shared+fixed>Decimal(config['shared_cap']):
        raise ValueError('Prepared fixed first pass exceeds remaining shared budget')
    input_hashes={key:{'path':path,'sha256':fingerprint(inputs[key])} for key,path in paths.items()}
    input_hashes['quarantined_facets']={'path':config['quarantined_facets'],'sha256':fingerprint(quarantined)}
    plan={'version':1,'config':config,'engine_sha256':engine_sha256(),'inputs':input_hashes,
        'jobs':jobs,'deferred_operator_urls':deferred_urls,'excluded_operator_urls':excluded_urls,
        'provider_capabilities':CAPABILITIES,
        'scope':'Private staged dataset; preserve manual decisions; never publish automatically'}
    preview={'source_claims':len(source_entries),'preserved_manual_holds':len(held)-len(source_entries),
        'annotation_items':{k:len(v) for k,v in annotation_entries.items()},
        'identity_candidate_groups':len(groups),'catalog_entities':len(rows),
        'discovery_candidates':len(discovery),'operator_pages':sum(j['kind']=='operator_fetch' for j in jobs),
        'deferred_operator_pages':len(deferred_urls),'fixed_ai_calls':sum(j['kind'] in queue.AI_STAGES for j in jobs),
        'excluded_social_or_aggregator_urls':len(excluded_urls),
        'configured_operator_api_feeds':len(config.get('operator_feeds',[])),
        'cached_fixed_ai_responses':cached_requests,
        'full_fixed_first_pass_reservation_before_cache':str(sum(full_stage_reservations.values())),
        'fixed_first_pass_reservation':str(fixed),'stage_first_pass_reservations':{k:str(v) for k,v in stage_reservations.items()},
        'operator_extraction_pool_cap':config['task_caps']['operator_extract'],
        'stage_caps_are_overlapping_maxima':True,
        'queue_cap':config['queue_cap'],'shared_reserved':str(shared),'shared_cap':config['shared_cap'],
        'web_search_connected':False,'automatic_publication':False}
    root=Path(config['output_root']); immutable_write(root/'prepared.json',plan)
    mutable_write(root/'preview.json',preview)
    return plan,preview


def validate_plan(plan):
    if plan['engine_sha256']!=engine_sha256(): raise ValueError('Version the run when engine changes; do not reset its ledger')
    validate_config(plan['config'])
    for value in plan['inputs'].values():
        if fingerprint(read(value['path']))!=value['sha256']: raise ValueError('Frozen completion input changed')
    ids={j['id'] for j in plan['jobs']}
    if len(ids)!=len(plan['jobs']): raise ValueError('Duplicate completion jobs')
    for j in plan['jobs']:
        if j['id']!=fingerprint({k:v for k,v in j.items() if k!='id'}) or not set(j['deps'])<=ids:
            raise ValueError('Invalid completion job binding/dependency')


def export(runner, *, as_of=None):
    plan=runner.plan; config=plan['config']; now=as_of or datetime.now(timezone.utc).isoformat()
    pack=read(config['pack']); held=read(config['held']); records=deepcopy(pack['drafts'])
    by_upstream={r['upstream_occurrence_id']:r for r in records}; pending={h['key']:deepcopy(h) for h in held}
    annotation_reviews=[]; page_results=[]; page_facts=[]; identity_groups=[]; source_counts=Counter(); source_events=[]
    for row in runner.store.rows():
        if row['state']!='succeeded': continue
        spec=json.loads(row['spec']); result=runner.result(row)['result']
        if row['kind']=='source':
            request=spec['payload']['request']; entries={e['key']:e for e in request['payload']['entries']}
            cues={c['segment_id']:c for c in request['payload']['original_context_cues']}
            for decision in result['decisions']:
                key=decision['key']; original=pending[key]; source_counts[decision['action']]+=1
                if decision['action']=='unresolved':
                    original['automated_followup']=decision; continue
                claim=deepcopy(original['original_claim'])
                if decision['action']=='repair':
                    claim.update({k:decision[k] for k in ('dimension','value','basis')})
                    claim['citations']=[{k:cues[s][k] for k in ('segment_id','start_seconds','end_seconds')} | {'quote':cues[s]['text']}
                                        for s in decision['evidence_segment_ids']]
                Claim.model_validate(claim)
                record=by_upstream[original['upstream_occurrence_id']]; record['claims'].append(claim)
                record['claim_review_metadata'].append({'upstream_key':key,'claim_sha256':fingerprint(claim),
                    'state':'automated_editorial_candidate','assertion_scope':decision['assertion_scope'],
                    'lifecycle':decision['lifecycle'],'subject_note':decision['subject_note'],
                    'review_kind':'automated_source_comparison','manual_reviewed':False,
                    'canonical_identity_verified':False,'current_trip_verified':False,'planner_fact_eligible':False,
                    'decision_sha256':fingerprint(decision)})
                source_events.append({'key':key,'original_claim':original['original_claim'],'candidate_claim':claim,'decision':decision})
                del pending[key]
        elif row['kind'] in {'facets','details','activity_fit'}:
            request=spec['payload']['request']; entries={e['key']:e for e in request['payload']['entries']}
            for decision in result['decisions']:
                entry=entries[decision['key']]
                annotation_reviews.append({'entry':entry,'decision':decision,
                    'taxonomy_admission_pending':entry.get('taxonomy_admission_pending',False) and decision['action']=='retain'})
        elif row['kind'] in {'operator_fetch','operator_feed'}: page_results.append((spec,result))
        elif row['kind']=='operator_extract': page_facts+=result['facts']
        elif row['kind']=='identity_inventory': identity_groups=result['groups']
    prior_claims=sum(len(r['claims']) for r in pack['drafts'])+len(held)
    final_claims=sum(len(r['claims']) for r in records)+len(pending)
    keys=[m['upstream_key'] for r in records for m in r['claim_review_metadata']]+list(pending)
    if prior_claims!=final_claims or len(keys)!=len(set(keys)): raise ValueError('Staged editorial pack lost or duplicated claims')
    mapping={}
    for record in records:
        old=record['id']; base=next(r for r in pack['drafts'] if r['id']==old)
        if record!=base: record['id']=fingerprint({'previous_id':old,'claims':record['claims'],'reviews':record['claim_review_metadata']})
        mapping[old]=record['id']
    old_mapping=pack['previous_to_normalized_ids']
    new_records={r['id']:r for r in records}
    for review in annotation_reviews:
        entry=review['entry']; base_id=old_mapping[entry['record_id']]; current_id=mapping[base_id]
        review['current_record_id']=current_id
        available={fingerprint(c) for c in new_records[current_id]['claims']}
        review['claim_binding_current']=set(review['decision']['evidence_claim_ids'])<=available
        if not review['claim_binding_current']:
            review['decision']['source_discovery_candidate']=False
    manual_tags=None
    if config.get('annotation_proposals'):
        scoped_pack={**pack,'drafts':records,'previous_to_normalized_ids':{
            old:mapping[base] for old,base in old_mapping.items()}}
        manual_tags=materialize_manual_tags(read(config['annotation_proposals']),read(config['manual_tag_audit']),scoped_pack)
    branch_links=[]; structured_fields=[]
    for spec,receipt in page_results:
        for obs in receipt['structured_observations']:
            link=automatic_identity(obs,spec['payload']['candidates']); branch_links.append(link)
            for fact in obs['facts']:
                policy=config['refresh_days'].get(fact['field'],config['refresh_days']['default'])
                structured_fields.append({'observation_id':obs['id'],'subject_name':obs['name'],
                    'subject_address':obs['address'],'fact':fact,'identity':link,
                    'refresh':field_state(fact,as_of=now,refresh_days=policy,requested_date=config.get('requested_date'))})
    errors=[{'job_id':r['id'],'stage':r['kind'],'state':r['state'],'reason':r['error']}
            for r in runner.store.rows() if r['state']!='succeeded']
    unsupported_fields=['date_specific_ticket_or_table_availability','verified_entrance_and_access_chain']
    report={'plan_sha256':fingerprint(plan),'execution':runner.checkpoint('finished_with_review_handoffs'),
        'editorial':{'reviewed_source_claims':sum(source_counts.values()),'actions':dict(source_counts),
            'staged_active_claims':sum(len(r['claims']) for r in records),'held_claims':len(pending),
            'claims_conserved':final_claims,'annotation_reviews':len(annotation_reviews),
            'annotation_actions':dict(Counter(r['decision']['action'] for r in annotation_reviews)),
            'existing_manual_review_metadata_preserved':sum(
                m.get('review_kind','').startswith('agent_') for r in pack['drafts'] for m in r['claim_review_metadata']),
            'manual_held_decisions_preserved':sum(bool(h.get('followup_review')) for h in held),
            'manual_tag_reviews_preserved':len(read(config['manual_tag_audit'])['reviews'])},
        'identity':{'candidate_groups':len(identity_groups),'structured_operator_branches':len(branch_links),
            'branch_correspondences':sum(l['status']=='operator_catalog_branch_correspondence' for l in branch_links),
            'admitted_operator_branch_identities':sum(l['canonical_identity_verified'] for l in branch_links),
            'confirmed_transcript_aliases':0,'verified_entrances':0},
        'operational':{'fetched_sources':len(page_results),'structured_field_observations':len(structured_fields),
            'prose_field_proposals':len(page_facts),'trip_verified_fields':0,
            'unsupported_provider_capabilities':unsupported_fields},
        'job_handoffs':errors,'deferred_operator_urls':plan['deferred_operator_urls'],
        'as_of':now,'ready_to_publish':False,'dataset_ready':False,
        'next':'Adjudicate remaining ambiguous subjects/identities and validate selected trip dates; counts do not release the planner'}
    root=runner.root
    mutable_write(root/'staged-source-pack.json',{'drafts':records,'held_claims':list(pending.values()),
        'previous_to_staged_ids':mapping,'editorial_events':source_events,'status':'automated_editorial_candidates_not_active_release',
        'ready_to_publish':False})
    mutable_write(root/'annotation-review-results.json',{'reviews':annotation_reviews,
        'preserved_manual_reviews':manual_tags['reviews'] if manual_tags else read(config['manual_tag_audit'])['reviews'],
        'ready_to_publish':False})
    mutable_write(root/'identity-results.json',{'groups':identity_groups,'branch_links':branch_links,'ready_to_publish':False})
    mutable_write(root/'operational-results.json',{'structured_fields':structured_fields,'prose_proposals':page_facts,
        'provider_capabilities':CAPABILITIES,'ready_to_publish':False})
    mutable_write(root/'completion-report.json',report)
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe',type=Path,required=True)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--status',action='store_true')
    parser.add_argument('--offline',action='store_true',help='Execute local inventory only, without HTTP or AI')
    parser.add_argument('--refresh',action='store_true',help='Create a new dated output folder; retain original inference pools/ledger')
    args=parser.parse_args(); config=read(args.recipe)
    if args.refresh:
        stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        config['output_root']=config['output_root']+'-refresh-'+stamp
        # A persisted recipe allows resuming this exact refresh after interruption.
        root_recipe=Path(config['output_root'])/'recipe.json'
        immutable_write(root_recipe,config)
        print('Refresh recipe for resume: '+str(root_recipe),flush=True)
    root=Path(config['output_root'])
    if args.status:
        path=root/'completion-report.json'
        print(json.dumps(read(path) if path.exists() else read(root/'preview.json'),ensure_ascii=False,indent=2)); return
    values=read_environment('.env')
    if (root/'prepared.json').exists():
        plan=read(root/'prepared.json'); validate_plan(plan)
        if plan['config']!=config: raise ValueError('Config changed: version the run and retain its original ledger')
        preview=read(root/'preview.json')
    else: plan,preview=prepare(config,values)
    print(json.dumps(preview,ensure_ascii=False,indent=2),flush=True)
    if args.execute or args.offline:
        if args.execute and not args.offline and (values.get('TRIPPY_ALLOW_PAID_RESEARCH','').lower()!='true' or
                not configured(values.get('AZURE_OPENAI_API_KEY')) or not configured(values.get('AZURE_DEPLOYMENT_LUNA'))):
            raise ValueError('Explicit paid-research environment and Luna credentials required')
        runner=Runner(plan,values)
        try:
            runner.run(network=not args.offline,ai=not args.offline)
        except KeyboardInterrupt:
            runner.active=None; runner.checkpoint('interrupted_resume_same_command'); export(runner)
            raise SystemExit(130)
        report=export(runner)
        print(json.dumps({k:v for k,v in report.items() if k not in {'job_handoffs','deferred_operator_urls'}},ensure_ascii=False,indent=2))
        if not report['execution']['execution_complete'] and not args.offline: raise SystemExit(2)


if __name__=='__main__': main()
