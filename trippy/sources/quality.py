"""Offline extraction quality gate. Evidence validity never implies truth."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
from decimal import Decimal

from trippy.catalog.normalize import normalize_text
from .extraction import fingerprint, validate_result

LIVE_FIELDS={'opening_hours','price','booking','tickets','date','allergies','accessibility'}


def require_scale_approval(chunks,approval):
    if len(chunks)<=6:return
    if not approval or approval.get('version')!=1 or not approval.get('gates',{}).get('ready_to_scale_extraction') or not approval.get('gates',{}).get('benchmark_passed'):
        raise ValueError('Bulk extraction requires a passed, reviewed quality gate; run a bounded pilot first')
    if approval.get('benchmark_scope')!='exhaustive_actionable_inventory':
        raise ValueError('Bulk extraction requires exhaustive pilot reference coverage')
    if approval.get('prompt_sha256')!=sorted({fingerprint(c['system_prompt']) for c in chunks}):
        raise ValueError('Quality approval belongs to a different prompt version')
    if approval.get('semantic_review_pending') or approval.get('issues') or approval.get('cue_review_pending')!=[] or approval.get('uncertain_source_cues')!=[]:
        raise ValueError('Quality approval has unresolved semantic blockers')
    summary=approval.get('summary',{})
    if not summary.get('reference_targets') or summary.get('covered_targets')!=summary['reference_targets'] or summary.get('unreviewed_mentions')!=0:
        raise ValueError('Quality approval is missing complete benchmark/review measurements')


def evidence_key(claim):
    return fingerprint({k:claim[k] for k in ('dimension','basis','observed_at','citations')})


def metadata_observations(chunks):
    """Keep chapter names/disclosures as separate provenance, never speech."""
    sources={c['payload']['source']['external_id']:c['payload']['metadata'] for c in chunks}
    observations=[]
    for source_id,metadata in sources.items():
        description=metadata.get('description','')
        for number,line in enumerate(description.splitlines()):
            chapter=re.fullmatch(r'\s*(?:(\d+):)?(\d{1,2}):(\d{2})\s+(.+)',line)
            if chapter:
                hours,minutes,seconds,name=chapter.groups()
                observations.append({'source_id':source_id,'kind':'chapter_name_identity_hint',
                    'value':name,'start_seconds':int(hours or 0)*3600+int(minutes)*60+int(seconds),
                    'citation':{'field':'metadata.description','line':number,'quote':line},
                    'metadata_sha256':fingerprint(metadata),'status':'not_verified_identity; not_spoken_evidence'})
            if re.search(r'\b(?:our .{0,30}(?:tour|business)|join a .{0,30}tour)\b',line,re.I):
                observations.append({'source_id':source_id,'kind':'commercial_or_promotional_disclosure',
                    'citation':{'field':'metadata.description','line':number,'quote':line},
                    'metadata_sha256':fingerprint(metadata),'status':'promotional_context; venue_payment_not_established'})
    return observations


def assess(report,prepared,reference,annotations=None):
    annotations=annotations or {}
    chunks=prepared['chunks'];segments={}
    for chunk in chunks:
        if chunk['id']!=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']}):
            raise ValueError('Prepared chunk fingerprint mismatch')
        validate_result(chunk,{'mentions':[]})
        for segment in chunk['payload']['segments']:
            prior=segments.get(segment['segment_id'])
            if prior and prior!=segment:raise ValueError('Conflicting overlap evidence')
            segments[segment['segment_id']]=segment
    for source,receipt in reference['source_evidence_sha256'].items():
        actual={c['payload']['source_evidence_sha256'] for c in chunks if c['payload']['source']['external_id']==source}
        if actual!={receipt}:raise ValueError('Reference source evidence mismatch')
    if {c['payload']['source']['external_id'] for c in chunks}!=set(reference['source_evidence_sha256']):
        raise ValueError('Reference must cover every evaluated source')
    if reference.get('version')!=1:raise ValueError('Unsupported reference version')
    targets=[]
    if len({t['id'] for t in reference['targets']})!=len(reference['targets']):raise ValueError('Duplicate reference target IDs')
    for target in reference['targets']:
        if any(s.rsplit(':',1)[0]!=target['source_id'] for s in target['segments']+target.get('claim_segments',[])):
            raise ValueError('Cross-source reference citation')
        cited=[segments[s] for s in target['segments']]
        if any(s not in segments for s in target.get('claim_segments',[])):raise ValueError('Missing reference claim cue')
        anchor=normalize_text(target['anchor'])
        if not anchor or not any(anchor in normalize_text(s['text']) for s in cited):
            raise ValueError('Reference anchor is not in supplied evidence')
        found=[]
        for draft in report['drafts']:
            if draft['source']['external_id']!=target['source_id']:continue
            if not any(c['segment_id'] in target['segments'] and anchor in normalize_text(c['quote']) for c in draft['citations']):continue
            if target.get('dimension'):
                dimensions=target.get('allowed_dimensions',[target['dimension']])
                claims=[c for c in draft['claims'] if c['dimension'] in dimensions and
                    any(q['segment_id'] in target.get('claim_segments',target['segments']) for q in c['citations'])]
                if not claims:continue
            found.append(draft['id'])
        targets.append({**target,'matched_draft_ids':found,'covered':bool(found)})
    issues=[];bundles=[];relations=[];semantic_pending=[];identity_pending=[];freshness_pending=[]
    drafts_by_id={d['id']:d for d in report['drafts']}
    for finding in report.get('source_review_findings',[]):
        draft=drafts_by_id.get(finding.get('draft_id'))
        claim=next((c for c in draft['claims'] if fingerprint(c)==finding.get('claim_sha256')),None) if draft else None
        if not claim or finding.get('review_method')!='manual_source_comparison' or not finding.get('reviewer') or not finding.get('finding'):
            raise ValueError('Source review finding must match a retained claim and named review')
        issues.append({'draft_id':draft['id'],'kind':'targeted_source_review_finding',
            'claim':claim,'reason':finding['finding'],'reviewer':finding['reviewer']})
    valid_ids=set()
    for draft in report['drafts']:
        # Revalidate every retained occurrence against its original chunk.
        matching=[c for c in chunks if c['payload']['source']['external_id']==draft['source']['external_id']]
        # Aggregates may consolidate overlapping chunks: check against their
        # complete original cue union, never against external or synthetic text.
        union={s['segment_id']:s for c in matching for s in c['payload']['segments']}
        composite={'payload':{'segments':list(union.values())}}
        mention={k:draft[k] for k in ('name','aliases','kind','categories','stance','identity_uncertain',
            'identity_uncertainty_reason','experience','branch','claims','rating','citations')}
        validate_result(composite,{'mentions':[mention]})
        key=fingerprint({'source':draft['source']['external_id'],'mention':mention})
        valid_ids.add(key)
        decision=annotations.get(key,{})
        if decision and (decision.get('review_method')!='manual_source_comparison' or not decision.get('reviewer') or not decision.get('reason')):
            raise ValueError('Review decisions require named reviewer, method and rationale')
        if decision.get('semantic')!='approved':semantic_pending.append(key)
        if draft['kind'] in {'venue','chain','district','route'} and decision.get('identity')!='resolved':identity_pending.append(key)
        if (draft['kind'] in {'venue','chain'} or any(c['dimension'] in LIVE_FIELDS for c in draft['claims'])) and decision.get('current_facts')!='verified':freshness_pending.append(key)
        if draft['identity_uncertain']!=bool(draft['identity_uncertainty_reason']):
            issues.append({'draft_id':draft['id'],'kind':'inconsistent_identity_uncertainty'})
        grouped=defaultdict(list)
        for claim in draft['claims']:
            grouped[evidence_key(claim)].append(claim)
            quote=' '.join(c['quote'] for c in claim['citations'])
            if re.search(r'την\s+εχουν\s+(?:ε)?πατησει',normalize_text(quote)) and re.search(r'stepped on|trampled',claim['value'],re.I):
                issues.append({'draft_id':draft['id'],'kind':'possible_greek_idiom_as_literal_trampling',
                    'claim':claim,'reason':'The Greek idiom can mean having a bad experience; compare the source context before accepting a literal stepping/trampling assertion.'})
            if claim['dimension']=='price':
                canonical=lambda n:Decimal(n.replace(',','.')).normalize()
                stated={canonical(n) for n in re.findall(r'\d+(?:[.,]\d+)?',quote)}
                number_words={'one':'1','two':'2','three':'3','four':'4','five':'5','six':'6','seven':'7',
                    'eight':'8','nine':'9','ten':'10','ένα':'1','δύο':'2','τρία':'3','πέντε':'5','δέκα':'10'}
                stated.update(canonical(n) for word,n in number_words.items() if re.search(r'(?<!\w)'+re.escape(word)+r'(?!\w)',quote,re.I))
                claimed={canonical(n) for n in re.findall(r'\d+(?:[.,]\d+)?',claim['value'])}
                if claimed-stated:
                    issues.append({'draft_id':draft['id'],'kind':'numeric_price_not_in_cited_speech','claim':claim})
            # Conservative, visible diagnostic; never silently reclassify facts.
            if claim['dimension']=='opening_hours' and re.search(r'\b(?:18|19|20)\d{2}\b',quote) and not re.search(r'\b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b',quote,re.I):
                issues.append({'draft_id':draft['id'],'kind':'historical_date_as_opening_hours','claim':claim})
            if claim['dimension']=='audience' and re.search(r'family.run|family members|sisters.{0,40}run|fourth generation|capacity',claim['value'],re.I):
                issues.append({'draft_id':draft['id'],'kind':'ownership_or_capacity_as_audience','claim':claim})
            if claim['dimension']=='opening_hours' and re.search(r'closed when|historical observation',claim['value'],re.I):
                issues.append({'draft_id':draft['id'],'kind':'past_closure_as_schedule','claim':claim})
            if claim['dimension']=='accessibility' and re.search(r'anatomically|back and pelvis',claim['value'],re.I):
                issues.append({'draft_id':draft['id'],'kind':'bench_comfort_does_not_establish_accessibility','claim':claim})
            if claim['dimension']=='subcategory' and re.search(r'our.{0,40}tour',quote,re.I):
                issues.append({'draft_id':draft['id'],'kind':'commercial_tour_membership_as_subcategory','claim':claim})
            if claim['dimension'] in {'dishes','neighborhood','branch','transport'}:
                relations.append({'subject_draft_id':draft['id'],'predicate':claim['dimension'],
                    'object_text':claim['value'],'citations':claim['citations'],
                    'status':'source_assertion_needs_semantic_review; not_resolved_entity_relation'})
        bundles.append({'draft_id':draft['id'],'review_key':key,'claims':[
            {'evidence_key':k,'variants':values,'semantic_equivalence':'not_assumed'} for k,values in grouped.items()]})
    stale=set(annotations)-valid_ids
    if stale:raise ValueError('Annotations do not match current content fingerprints')
    used={q['segment_id'] for d in report['drafts'] for q in [*d['citations'],
        *(q for c in d['claims'] for q in c['citations']),
        *(d['rating']['citations'] if d['rating'] else [])]}
    dispositions=reference.get('segment_dispositions',{})
    if set(dispositions)-set(segments):raise ValueError('Reference dispositions cite unknown cues')
    target_ids={t['id'] for t in targets}
    for cue,disposition in dispositions.items():
        if disposition.get('classification') not in {'actionable','context','non_research','uncertain'} or not disposition.get('reason'):
            raise ValueError('Cue disposition requires classification and rationale')
        if disposition['classification']=='actionable' and (not disposition.get('target_ids') or not set(disposition['target_ids'])<=target_ids):
            raise ValueError('Actionable cue disposition needs reference targets')
        if disposition['classification']=='actionable' and not any(cue in t['segments']+t.get('claim_segments',[]) for t in targets if t['id'] in disposition['target_ids']):
            raise ValueError('Actionable cue is not anchored by its reference targets')
    cue_review_pending=sorted(set(segments)-set(dispositions))
    uncertain_cues=sorted(cue for cue,d in dispositions.items() if d['classification']=='uncertain')
    covered=sum(t['covered'] for t in targets)
    benchmark_passed=bool(targets) and covered==len(targets)
    # An annotation cannot override a detected blocker or missing benchmark item.
    ready=benchmark_passed and not issues and not semantic_pending and not cue_review_pending and not uncertain_cues and reference['scope']=='exhaustive_actionable_inventory'
    return {'version':1,'status':'quality_review','benchmark_scope':reference['scope'],
        'reference_sha256':fingerprint(reference),'report_sha256':fingerprint(report),
        'prompt_sha256':sorted({fingerprint(c['system_prompt']) for c in chunks}),
        'targets':targets,'issues':issues,'evidence_bundles':bundles,'relation_observations':relations,
        'metadata_observations':metadata_observations(chunks),
        'uncited_transcript_cues':[segments[key] for key in sorted(set(segments)-used)],
        'cue_review_pending':cue_review_pending,
        'uncertain_source_cues':uncertain_cues,
        'semantic_review_pending':semantic_pending,'identity_review_pending':identity_pending,
        'current_fact_review_pending':freshness_pending,
        'gates':{'benchmark_passed':benchmark_passed,'ready_to_scale_extraction':ready,
            'ready_to_publish':ready and not identity_pending and not freshness_pending and
                reference.get('scope')=='exhaustive_actionable_inventory'},
        'summary':{'reference_targets':len(targets),'covered_targets':covered,'semantic_blockers':len(issues),
            'unreviewed_mentions':len(semantic_pending),'unresolved_identities':len(identity_pending),
            'evidence_bundles':sum(len(b['claims']) for b in bundles),
            'raw_claim_records':sum(len(d['claims']) for d in report['drafts'])},
        'model_calls':0,'catalog_writes':0}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('report','prepared','reference','output'):parser.add_argument('--'+field,type=Path,required=True)
    parser.add_argument('--annotations',type=Path)
    args=parser.parse_args()
    result=assess(json.loads(args.report.read_text()),json.loads(args.prepared.read_text()),
        json.loads(args.reference.read_text()),json.loads(args.annotations.read_text()) if args.annotations else None)
    import os
    with os.fdopen(os.open(args.output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w') as stream:
        json.dump(result,stream,ensure_ascii=False,indent=2)
    print(json.dumps({'summary':result['summary'],'gates':result['gates']}))


if __name__=='__main__':main()
