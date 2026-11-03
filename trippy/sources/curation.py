"""Apply explicit content-bound editorial decisions without rewriting evidence."""
from copy import deepcopy
from .extraction import aggregate, fingerprint


def apply_curation(report,prepared,decisions):
    drafts={d['id']:deepcopy(d) for d in report['drafts']}
    audit=[];excluded=[]
    for decision in decisions:
        if not decision.get('reviewer') or not decision.get('reason'):raise ValueError('Editorial decision needs reviewer and rationale')
        draft=drafts.get(decision['draft_id'])
        if draft is None or fingerprint(draft)!=decision['before_sha256']:raise ValueError('Stale editorial decision')
        before=deepcopy(draft)
        target_before=None;target=None
        if decision['action']=='exclude':
            excluded.append(before);del drafts[draft['id']]
        elif decision['action']=='claim_dimension':
            matches=[c for c in draft['claims'] if fingerprint(c)==decision['claim_sha256']]
            if len(matches)!=1:raise ValueError('Editorial claim fingerprint mismatch')
            matches[0]['dimension']=decision['dimension']
        elif decision['action']=='claim_value':
            matches=[c for c in draft['claims'] if fingerprint(c)==decision['claim_sha256']]
            if len(matches)!=1:raise ValueError('Editorial claim fingerprint mismatch')
            matches[0]['value']=decision['value']
        elif decision['action']=='claim_add':
            from .extraction import Claim
            claim=Claim.model_validate(decision['claim']).model_dump()
            if any(fingerprint(c)==fingerprint(claim) for c in draft['claims']):raise ValueError('Editorial claim already exists')
            draft['claims'].append(claim)
        elif decision['action']=='claim_citations_add':
            from .extraction import Citation
            matches=[c for c in draft['claims'] if fingerprint(c)==decision['claim_sha256']]
            if len(matches)!=1:raise ValueError('Editorial claim fingerprint mismatch')
            for supplied in decision['additional_citations']:
                citation=Citation.model_validate(supplied).model_dump()
                if fingerprint(citation) not in {fingerprint(q) for q in matches[0]['citations']}:
                    matches[0]['citations'].append(citation)
        elif decision['action']=='claim_move':
            target=drafts.get(decision['target_draft_id'])
            if target is None or target is draft or fingerprint(target)!=decision['target_before_sha256']:
                raise ValueError('Stale editorial target')
            if target['source']['external_id']!=draft['source']['external_id']:raise ValueError('Cross-source editorial claim move')
            matches=[c for c in draft['claims'] if fingerprint(c)==decision['claim_sha256']]
            if len(matches)!=1:raise ValueError('Editorial claim fingerprint mismatch')
            target_before=deepcopy(target);claim=matches[0];draft['claims'].remove(claim)
            if fingerprint(claim) not in {fingerprint(c) for c in target['claims']}:target['claims'].append(claim)
        elif decision['action']=='mention_kind':draft['kind']=decision['kind']
        else:raise ValueError('Unsupported editorial action')
        audit.append({'decision':decision,'original':before,'corrected':deepcopy(draft) if decision['action']!='exclude' else None,
            'original_target':target_before,'corrected_target':deepcopy(target) if target else None,
            'status':'editorial_source_review; not_independent_fact_check'})
    results=[]
    for draft in drafts.values():
        source_id=draft['source']['external_id']
        originals=[c for c in prepared['chunks'] if c['payload']['source']['external_id']==source_id]
        cues={s['segment_id']:s for c in originals for s in c['payload']['segments']}
        payload={**originals[0]['payload'],'segments':list(cues.values())}
        mention={k:draft[k] for k in ('name','aliases','kind','categories','stance','identity_uncertain',
            'identity_uncertainty_reason','experience','branch','claims','rating','citations')}
        results.append(({'payload':payload},{'mentions':[mention]}))
    result={**deepcopy(report),**aggregate(results)}
    result.update(editorial_audit=audit,excluded_drafts=excluded,model_calls=0,
        upstream_report_sha256=fingerprint(report),
        status='private_editorial_draft_needs_identity_and_fact_review',ready_to_scale=False,ready_to_publish=False)
    result['prior_editorial_audit']=report.get('editorial_audit',report.get('prior_editorial_audit',[]))
    result['prior_excluded_drafts']=report.get('excluded_drafts',report.get('prior_excluded_drafts',[]))
    result['summary']={'retained_mentions':len(result['drafts']),
        'retained_claims':sum(len(d['claims']) for d in result['drafts']),
        'editorial_decisions':len(audit),'upstream_summary':report.get('summary')}
    # Keep identity proposals only for unchanged name/branch. Editorial operations
    # above never modify identity or quote evidence.
    for draft in result['drafts']:
        original=next(d for d in drafts.values() if d['source']['external_id']==draft['source']['external_id'] and
            all(d[k]==draft[k] for k in ('name','kind','branch','stance','experience','citations')))
        draft['identity_candidates']=original['identity_candidates']
    mapping={d['id']:next(n['id'] for n in result['drafts'] if n['source']['external_id']==d['source']['external_id'] and
             all(n[k]==d[k] for k in ('name','kind','branch','stance','experience','citations'))) for d in drafts.values()}
    result['upstream_to_editorial_ids']=mapping
    for relation in result.get('relationship_proposals',[]):
        for field in ('subject_draft_ids','object_draft_ids'):
            relation[field]=[mapping[i] for i in relation.get(field,[]) if i in mapping]
    linked={}
    for draft in result['drafts']:
        for candidate in draft['identity_candidates']:
            linked.setdefault(candidate['entity_id'],set()).add(draft['id'])
    result['identity_link_review_queue']=[{'candidate_entity_id':key,'draft_ids':sorted(ids),
        'decision':'shared_candidate_not_merged; verify_multilingual_names_and_branch'} for key,ids in linked.items() if len(ids)>1]
    return result


def main():
    import argparse,json,os
    from pathlib import Path
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('report','prepared','decisions','output'):parser.add_argument('--'+field,type=Path,required=True)
    args=parser.parse_args()
    result=apply_curation(json.loads(args.report.read_text()),json.loads(args.prepared.read_text()),json.loads(args.decisions.read_text()))
    with os.fdopen(os.open(args.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream:
        json.dump(result,stream,ensure_ascii=False,indent=2)
    print(json.dumps({'retained_mentions':len(result['drafts']),'editorial_decisions':len(result['editorial_audit']),
        'excluded_mentions':len(result['excluded_drafts']),'model_calls':0,'catalog_writes':0}))


if __name__=='__main__':main()
