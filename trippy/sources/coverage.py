"""Additive transcript audit with checked cue accounting and private proposals."""
import argparse
from collections import Counter
from copy import deepcopy
from decimal import Decimal
import json
import os
from pathlib import Path
import sqlite3
from contextlib import closing
from typing import Literal

from pydantic import Field
from .extraction import Strict, Citation, Claim, Mention, fingerprint, validate_result, aggregate
from .review import partition_mentions, repair_citations

PROMPT=Path(__file__).resolve().parents[2]/'configs/source_research/coverage-audit-prompt-v1.md'
FINAL_PROMPT=PROMPT.with_name('coverage-audit-prompt-v2.md')
KEYED_PROMPT=PROMPT.with_name('coverage-audit-prompt-v3.md')
MENTION_FIELDS=('name','aliases','kind','categories','stance','identity_uncertain',
    'identity_uncertainty_reason','experience','branch','claims','rating','citations')


class Addition(Strict):
    target_id: str
    association_citations: list[Citation] = Field(min_length=1,max_length=12)
    claims: list[Claim] = Field(min_length=1,max_length=80)


class Relationship(Strict):
    subject_id: str
    predicate: Literal['located_in','part_of_market','serves','route_includes','same_entity_candidate']
    object_id: str
    citations: list[Citation] = Field(min_length=1,max_length=12)


class Issue(Strict):
    kind: Literal['semantic_mismatch','wrong_dimension','contradiction','transcription_uncertain',
        'entity_link_uncertain','duplicate_candidate','missing_context','not_current']
    target_refs: list[str] = Field(max_length=20)
    explanation: str = Field(min_length=1,max_length=2000)
    citations: list[Citation] = Field(min_length=1,max_length=12)


class CoverageGroup(Strict):
    segment_ids: list[str] = Field(min_length=1,max_length=250)
    classification: Literal['covered','added','context','non_research','uncertain']
    references: list[str] = Field(max_length=80)
    reason: str = Field(min_length=1,max_length=800)


class Audit(Strict):
    additions: list[Addition] = Field(max_length=120)
    new_mentions: list[Mention] = Field(max_length=120)
    relationships: list[Relationship] = Field(max_length=120)
    issues: list[Issue] = Field(max_length=120)
    coverage_groups: list[CoverageGroup] = Field(max_length=400)


def private_write(path,document):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as stream:
        json.dump(document,stream,ensure_ascii=False,indent=2)


def prepare(base,extraction,*,context_cues=8):
    if not 0<=context_cues<=20:raise ValueError('Invalid context cap')
    chunks=extraction['chunks'];all_segments={};metadata={};receipts={}
    for chunk in chunks:
        if chunk['id']!=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']}):
            raise ValueError('Original chunk fingerprint mismatch')
        source=chunk['payload']['source']['external_id']
        receipts.setdefault(source,set()).add(chunk['payload']['source_evidence_sha256'])
        metadata[source]=chunk['payload']
        for cue in chunk['payload']['segments']:
            previous=all_segments.get(cue['segment_id'])
            if previous and previous!=cue:raise ValueError('Conflicting source cues')
            all_segments[cue['segment_id']]=cue
    for draft in base['drafts']:
        source=draft['source']['external_id']
        if receipts.get(source)!={draft['source_evidence_sha256']}:raise ValueError('Base source receipt mismatch')
        validate_result({'payload':{'segments':[s for k,s in all_segments.items() if k.rsplit(':',1)[0]==source]}},
            {'mentions':[{k:draft[k] for k in MENTION_FIELDS}]})
    plans=[]
    for chunk in chunks:
        source=chunk['payload']['source']['external_id']
        ordered=sorted((s for k,s in all_segments.items() if k.rsplit(':',1)[0]==source),key=lambda s:s['start_seconds'])
        core_ids={s['segment_id'] for s in chunk['payload']['segments']}
        indices=[i for i,s in enumerate(ordered) if s['segment_id'] in core_ids]
        context=[s for s in ordered[max(0,min(indices)-context_cues):max(indices)+context_cues+1] if s['segment_id'] not in core_ids]
        window_ids=core_ids|{s['segment_id'] for s in context}
        entities=[];existing=[]
        for draft in base['drafts']:
            if draft['source']['external_id']!=source:continue
            entities.append({'id':draft['id'],**{k:draft[k] for k in MENTION_FIELDS if k not in {'claims','rating'}},
                'source_evidence_sha256':draft['source_evidence_sha256']})
            for claim in draft['claims']:
                if any(q['segment_id'] in window_ids for q in claim['citations']):
                    existing.append({'ref':'claim:'+draft['id']+':'+fingerprint(claim),'target_id':draft['id'],'claim':claim})
        payload={'source':chunk['payload']['source'],'source_evidence_sha256':chunk['payload']['source_evidence_sha256'],
            'original_chunk_id':chunk['id'],'base_report_sha256':fingerprint(base),
            'segments':chunk['payload']['segments'],'context_segments':context,
            'entity_registry':entities,'existing_claims':existing,
            'metadata':chunk['payload']['metadata']}
        schema=Audit.model_json_schema();prompt=PROMPT.read_text()
        plans.append({'id':fingerprint({'prompt':prompt,'schema':schema,'payload':payload}),
            'system_prompt':prompt,'response_schema':schema,'payload':payload,'prompt_version':'coverage-1'})
    return {'version':1,'status':'coverage_audit_prepared','base_report_sha256':fingerprint(base),
        'chunks':plans,'model_calls':0,'catalog_writes':0}


def validate_prepared(document,base):
    if document.get('version')!=1 or document.get('base_report_sha256')!=fingerprint(base):raise ValueError('Audit base mismatch')
    chunks=document['chunks']
    if not chunks or len({c['id'] for c in chunks})!=len(chunks):raise ValueError('Invalid audit chunk IDs')
    for c in chunks:
        prompt_path={'coverage-1':PROMPT,'coverage-2':FINAL_PROMPT,'coverage-3':KEYED_PROMPT}.get(c.get('prompt_version'))
        if not prompt_path or c['system_prompt']!=prompt_path.read_text() or c['response_schema']!=response_schema(c['payload'],c['prompt_version']):raise ValueError('Audit contract mismatch')
        if c['id']!=fingerprint({'prompt':c['system_prompt'],'schema':c['response_schema'],'payload':c['payload']}):raise ValueError('Audit fingerprint mismatch')
        if c['payload']['base_report_sha256']!=fingerprint(base):raise ValueError('Audit payload base mismatch')
    return chunks


def response_schema(payload,revision):
    schema=Audit.model_json_schema()
    if revision!='coverage-3':return schema
    # Make cue omission, duplication and context-cue accounting impossible in
    # a completed strict response. Meaning/entailment remain separate checks.
    group=deepcopy(schema['$defs']['CoverageGroup'])
    group['properties'].pop('segment_ids');group['required'].remove('segment_ids')
    schema['$defs']['CueDisposition']=group
    ids=[s['segment_id'] for s in payload['segments']]
    schema['properties'].pop('coverage_groups');schema['required'].remove('coverage_groups')
    schema['properties']['cue_coverage']={'type':'object','additionalProperties':False,
        'properties':{sid:{'$ref':'#/$defs/CueDisposition'} for sid in ids},'required':ids}
    schema['required'].append('cue_coverage')
    cue_ids=list(dict.fromkeys(s['segment_id'] for s in payload['segments']+payload['context_segments']))
    schema['$defs']['Citation']['properties']['segment_id']['enum']=cue_ids
    targets=[d['id'] for d in payload['entity_registry']]
    for definition,field in (('Addition','target_id'),('Relationship','subject_id'),('Relationship','object_id')):
        schema['$defs'][definition]['properties'][field]['enum']=targets or ['NO_LOCAL_TARGET']
    return schema


def prepare_final(base,extraction,*,core_cues=50,context_cues=12,review_findings=None,keyed_coverage=False):
    """Small disjoint windows, local registry and explicit existing cue references.

    This is an offline final-run design, not a scale approval or a paid retry.
    V1 request fingerprints and cached responses remain unchanged.
    """
    if not 10<=core_cues<=80 or not 0<=context_cues<=20:raise ValueError('Invalid final window bounds')
    original=prepare(base,extraction,context_cues=context_cues)
    feedback=[]
    if review_findings is not None:
        if review_findings.get('report_sha256')!=fingerprint(base):raise ValueError('Review findings base mismatch')
        for finding in review_findings['findings']:
            draft=next((d for d in base['drafts'] if d['id']==finding['draft_id']),None)
            claim=next((c for c in draft['claims'] if fingerprint(c)==finding['claim_sha256']),None) if draft else None
            if not claim or claim['citations']!=finding['citations'] or claim['value']!=finding['claim_value']:
                raise ValueError('Review finding does not match retained claim')
            feedback.append({'target_ref':'claim:'+draft['id']+':'+fingerprint(claim),
                'finding':finding['finding'],'citations':claim['citations']})
    sources={};templates={}
    for chunk in original['chunks']:
        payload=chunk['payload'];sid=payload['source']['external_id']
        templates[sid]=payload
        for cue in payload['segments']:sources.setdefault(sid,{})[cue['segment_id']]=cue
    plans=[];revision='coverage-3' if keyed_coverage else 'coverage-2'
    prompt=(KEYED_PROMPT if keyed_coverage else FINAL_PROMPT).read_text()
    for sid,cues in sources.items():
        ordered=sorted(cues.values(),key=lambda s:(s['start_seconds'],s['segment_id']))
        registry=[d for d in base['drafts'] if d['source']['external_id']==sid]
        for start in range(0,len(ordered),core_cues):
            core=ordered[start:start+core_cues];core_ids={s['segment_id'] for s in core}
            context=[s for s in ordered[max(0,start-context_cues):start+len(core)+context_cues]
                     if s['segment_id'] not in core_ids]
            window=core_ids|{s['segment_id'] for s in context};entities=[];existing=[]
            for draft in registry:
                local_claims=[c for c in draft['claims'] if any(q['segment_id'] in window for q in c['citations'])]
                local_citations=[q for q in draft['citations'] if q['segment_id'] in window]
                if local_claims or local_citations:
                    entity={'id':draft['id'],**{k:deepcopy(draft[k]) for k in MENTION_FIELDS if k not in {'claims','rating'}},
                            'source_evidence_sha256':draft['source_evidence_sha256']}
                    if local_citations:entity['citations']=local_citations
                    entities.append(entity)
                    existing.extend({'ref':'claim:'+draft['id']+':'+fingerprint(c),'target_id':draft['id'],'claim':c}
                                    for c in local_claims)
            refs={s['segment_id']:[] for s in core}
            for item in existing:
                for q in item['claim']['citations']:
                    if q['segment_id'] in refs:refs[q['segment_id']].append(item['ref'])
            for entity in entities:
                for q in entity['citations']:
                    if q['segment_id'] in refs:refs[q['segment_id']].append('mention:'+entity['id'])
            template=templates[sid]
            payload={k:deepcopy(template[k]) for k in ('source','source_evidence_sha256','base_report_sha256','metadata')}
            payload.update(segments=core,context_segments=context,entity_registry=entities,existing_claims=existing,
                cue_evidence_refs={k:sorted(set(v)) for k,v in refs.items()},
                continuity_index=[{'name':d['name'],'aliases':d['aliases'],'kind':d['kind']} for d in registry],
                review_feedback=[deepcopy(f) for f in feedback if any(q['segment_id'] in window for q in f['citations'])],
                original_chunk_ids=[c['id'] for c in extraction['chunks'] if
                    core_ids&{s['segment_id'] for s in c['payload']['segments']}])
            schema=response_schema(payload,revision)
            plans.append({'id':fingerprint({'prompt':prompt,'schema':schema,'payload':payload}),
                'system_prompt':prompt,'response_schema':schema,'payload':payload,'prompt_version':revision})
    return {'version':1,'status':'final_coverage_design_prepared_not_evaluated',
        'base_report_sha256':fingerprint(base),'chunks':plans,'model_calls':0,'catalog_writes':0,
        'ready_to_scale':False,'ready_to_publish':False,
        'window_policy':{'core_cues':core_cues,'context_cues':context_cues,'disjoint_core':True}}


def validate_audit(chunk,raw):
    """Preserve valid proposals; invalid proposals cannot satisfy cue coverage."""
    if chunk.get('prompt_version')=='coverage-3':
        if not isinstance(raw,dict) or set(raw)!= {'additions','new_mentions','relationships','issues','cue_coverage'}:
            raise ValueError('Invalid keyed audit envelope')
        coverage=raw['cue_coverage'];core={s['segment_id'] for s in chunk['payload']['segments']}
        if not isinstance(coverage,dict) or set(coverage)!=core:raise ValueError('Keyed coverage must match every core cue exactly')
        if any(not isinstance(v,dict) or set(v)!={'classification','references','reason'} for v in coverage.values()):
            raise ValueError('Invalid keyed cue disposition')
        raw={k:v for k,v in raw.items() if k!='cue_coverage'}
        raw['coverage_groups']=[{'segment_ids':[key],**value} for key,value in coverage.items()]
    parsed=Audit.model_validate(raw).model_dump()
    payload=chunk['payload'];cues={s['segment_id']:s for s in payload['segments']+payload['context_segments']}
    window={'payload':{'segments':list(cues.values())}}
    source=payload['source']['external_id']
    registry={m['id']:m for m in payload['entity_registry']}
    accepted={'additions':[],'new_mentions':[],'relationships':[],'issues':[]};quarantine=[];repairs=[];refs={};reference_repairs=[]
    for item in payload['existing_claims']:
        refs[item['ref']]={q['segment_id'] for q in item['claim']['citations']}
    for key,m in registry.items():refs['mention:'+key]={q['segment_id'] for q in m['citations']}
    def checked_citations(citations):
        dummy={'citations':citations,'claims':[],'rating':None}
        fixed,changes=repair_citations(dummy,window)
        for q in fixed['citations']:
            s=cues.get(q['segment_id'])
            if not s or not q['quote'] or q['quote'] not in s['text'] or (q['start_seconds'],q['end_seconds'])!=(s['start_seconds'],s['end_seconds']):
                raise ValueError('Audit citation does not match supplied evidence')
        return fixed['citations'],changes
    for field in accepted:
        prefix={'additions':'addition','new_mentions':'new','relationships':'relation','issues':'issue'}[field]
        for index,item in enumerate(parsed[field]):
            ref=f'{prefix}:{index}'
            try:
                if field=='new_mentions':
                    result,rejected,changes=partition_mentions(window,{'mentions':[item]})
                    if not result['mentions']:raise ValueError('New mention failed evidence validation')
                    fixed=result['mentions'][0]
                    quarantine.extend({'ref':ref+':part:'+str(i),'parent_ref':ref,
                        'reason':part['reason'],'candidate':part['candidate']} for i,part in enumerate(rejected))
                    used={q['segment_id'] for q in fixed['citations']+[q for c in fixed['claims'] for q in c['citations']]}
                elif field=='additions':
                    target=registry.get(item['target_id'])
                    if not target:raise ValueError('Unknown or cross-source addition target')
                    association,changes=checked_citations(item['association_citations'])
                    from trippy.catalog.normalize import normalize_text
                    names=[normalize_text(n) for n in [target['name'],*target['aliases']]]
                    if not any(n and n in normalize_text(q['quote']) for n in names for q in association):
                        # Inflected ASR names can miss the canonical original
                        # spelling. Append a supplied, exact local registry
                        # anchor; never invent aliases or use distant evidence.
                        anchors=[q for q in target['citations'] if q['segment_id'] in cues and
                                 any(n and n in normalize_text(q['quote']) for n in names)]
                        if anchors and len(association)<12:
                            anchor,more=checked_citations([anchors[0]])
                            association+=anchor;changes+=more
                            changes.append({'kind':'local_identity_anchor_appended','citation':anchor[0]})
                    # The association must be anchored in this passage; registry
                    # context alone cannot attach arbitrary facts to a venue.
                    base={k:deepcopy(target[k]) for k in MENTION_FIELDS if k not in {'claims','rating'}}
                    base.update(citations=association,claims=item['claims'],rating=None)
                    result,rejected,more=partition_mentions(window,{'mentions':[base]})
                    if not result['mentions'] or not result['mentions'][0]['claims']:
                        raise ValueError('Addition target/claim is not anchored in this passage')
                    quarantine.extend({'ref':ref+':part:'+str(i),'parent_ref':ref,
                        'reason':part['reason'],'candidate':part['candidate']} for i,part in enumerate(rejected))
                    fixed={**item,'association_citations':result['mentions'][0]['citations'],'claims':result['mentions'][0]['claims']}
                    changes+=more
                    used={q['segment_id'] for q in fixed['association_citations']+[q for c in fixed['claims'] for q in c['citations']]}
                else:
                    cited,changes=checked_citations(item['citations']);fixed={**item,'citations':cited}
                    if field=='relationships':
                        if item['subject_id'] not in registry or item['object_id'] not in registry:raise ValueError('Unknown or cross-source relationship target')
                        for target_id in (item['subject_id'],item['object_id']):
                            target=registry[target_id]
                            base={k:deepcopy(target[k]) for k in MENTION_FIELDS if k not in {'claims','rating'}}
                            base.update(citations=cited,claims=[],rating=None)
                            validate_result(window,{'mentions':[base]})
                    else:
                        targets=[]
                        for r in item['target_refs']:
                            # A bare, exact registry ID has one unambiguous meaning.
                            # Record the formatting repair; never guess an identity.
                            normalized='mention:'+r if r in registry else r
                            if normalized not in refs:raise ValueError('Unknown issue target reference')
                            targets.append(normalized)
                            if normalized!=r:
                                reference_repairs.append({'ref':ref,'original':r,'replacement':normalized})
                        fixed['target_refs']=targets
                    used={q['segment_id'] for q in cited}
                accepted[field].append({'ref':ref,**fixed});refs[ref]=used
                repairs.extend({'ref':ref,**r} for r in changes)
            except ValueError as exc:quarantine.append({'ref':ref,'reason':str(exc),'candidate':item})
    core={s['segment_id'] for s in payload['segments']};seen=Counter();coverage=[];coverage_errors=[]
    for group in parsed['coverage_groups']:
        problems=[]
        for cue in group['segment_ids']:
            seen[cue]+=1
            if cue not in core:problems.append('Unknown/non-core cue '+cue)
            cls=group['classification'];referenced=group['references']
            if any(r not in refs for r in referenced):problems.append('Unknown/rejected evidence reference')
            if cls in {'covered','added','context'} and not any(cue in refs.get(r,set()) for r in referenced):
                problems.append('Cue has no cited evidence reference')
            if cls=='covered' and not any(r.startswith(('claim:','mention:')) and cue in refs.get(r,set()) for r in referenced):
                problems.append('Covered cue needs an existing evidence reference')
            if cls=='added' and not any(r.startswith(('addition:','new:','relation:','issue:')) and cue in refs.get(r,set()) for r in referenced):
                problems.append('Added cue needs a validated output reference')
            if cls=='uncertain' and not any(r.startswith('issue:') and cue in refs.get(r,set()) for r in referenced):
                problems.append('Uncertain cue needs a cited review issue')
        record={**group,'validation_errors':sorted(set(problems))};coverage.append(record)
        coverage_errors.extend(record['validation_errors'])
    missing=sorted(core-set(seen));duplicates=sorted(k for k,v in seen.items() if v>1)
    return {**accepted,'quarantine':quarantine,'citation_repairs':repairs,'reference_repairs':reference_repairs,'coverage_groups':coverage,
        'missing_core_cues':missing,'duplicate_cues':duplicates,'coverage_errors':sorted(set(coverage_errors)),
        'cue_accounting_complete':not missing and not duplicates and not coverage_errors,
        'semantic_review_status':'not_approved; model_dispositions_are_proposals',
        'source_id':source,'chunk_id':chunk['id']}


def check(prepared,audits):
    """Build an offline evidence review queue; a model ledger never approves itself."""
    observations={};review=[];completed={c['id'] for c,_ in audits}
    for chunk,audit in audits:
        cues={s['segment_id']:s for s in chunk['payload']['segments']}
        for cue in audit['missing_core_cues']:
            review.append({'kind':'unaccounted_cue','chunk_id':chunk['id'],'segment':cues[cue]})
        for item in audit['quarantine']:
            review.append({'kind':'quarantined_proposal','chunk_id':chunk['id'],**item})
        for group in audit['coverage_groups']:
            for cue in group['segment_ids']:
                if cue not in cues:continue
                observations.setdefault(cue,[]).append({'chunk_id':chunk['id'],
                    'classification':group['classification'],'references':group['references']})
                # Context and non-research exclusions need transcript comparison:
                # they can hide omissions even when the structural ledger passes.
                review.append({'kind':'cue_disposition_review','chunk_id':chunk['id'],
                    'segment':cues[cue],'classification':group['classification'],
                    'references':group['references'],'reason':group['reason'],
                    'validation_errors':group['validation_errors']})
        for field in ('additions','new_mentions','relationships','issues'):
            review.extend({'kind':'semantic_'+field,'chunk_id':chunk['id'],'proposal':item}
                          for item in audit[field])
    conflicts=[{'segment_id':cue,'observations':items} for cue,items in observations.items()
               if len({i['classification'] for i in items})>1]
    core={s['segment_id'] for c in prepared['chunks'] for s in c['payload']['segments']}
    return {'status':'requires_transcript_comparison_and_independent_current_fact_checks',
        'unique_core_cues':len(core),'unique_accounted_cues':len(core&set(observations)),
        'missing_chunk_ids':[c['id'] for c in prepared['chunks'] if c['id'] not in completed],
        'overlap_disposition_conflicts':conflicts,'review_queue':review,
        'cue_accounting_complete':len(audits)==len(prepared['chunks']) and
            all(a['cue_accounting_complete'] for _,a in audits) and not conflicts,
        'semantic_approved':False,'current_facts_verified':False,
        'ready_to_scale':False,'ready_to_publish':False}


def retain_unresolved_cues(chunk,raw):
    """Preserve failed cue links as exact evidence, never as invented facts.

    Original output stays unchanged. Generated issues explicitly require review;
    complete accounting after this repair is not complete semantic extraction.
    """
    if chunk.get('prompt_version')!='coverage-3':raise ValueError('Unresolved-cue retention requires keyed accounting')
    before=validate_audit(chunk,raw);candidate=deepcopy(raw);adjustments=[]
    cues={s['segment_id']:s for s in chunk['payload']['segments']}
    for group in before['coverage_groups']:
        if not group['validation_errors']:continue
        for sid in group['segment_ids']:
            cue=cues[sid];index=len(candidate['issues'])
            citation={k:cue[k] for k in ('segment_id','start_seconds','end_seconds')}
            citation['quote']=cue['text']
            if len(citation['quote'])>2000:raise ValueError('Unresolved cue exceeds exact-quote limit')
            candidate['issues'].append({'kind':'missing_context','target_refs':[],
                'explanation':'Deterministic checker: the initial cue disposition used unsupported evidence links. Retain this exact cue for transcript comparison; no extracted fact or entity association is approved.',
                'citations':[citation]})
            candidate['cue_coverage'][sid]={'classification':'uncertain','references':[f'issue:{index}'],
                'reason':'Exact source evidence retained after failed reference validation; semantic review required.'}
            adjustments.append({'segment_id':sid,'original_disposition':deepcopy(raw['cue_coverage'][sid]),
                'original_errors':group['validation_errors'],'generated_issue_ref':f'issue:{index}'})
    after=validate_audit(chunk,candidate)
    return after,{'chunk_id':chunk['id'],'original_candidate_sha256':fingerprint(raw),
        'adjustments':adjustments,'method':'deterministic_unresolved_evidence_retention; not_model_output_or_fact_approval'}


def merge(base,prepared,audits,catalog=None,original_extraction=None):
    """Add exact-backed details; review issues and relationships never overwrite."""
    drafts={d['id']:deepcopy(d) for d in base['drafts']};new=[];issues=[];relations=[];lineage=[]
    for chunk,audit in audits:
        for addition in audit['additions']:
            target=drafts[addition['target_id']]
            for claim in addition['claims']:
                if fingerprint(claim) not in {fingerprint(c) for c in target['claims']}:
                    target['claims'].append(claim)
                    lineage.append({'target_id':target['id'],'claim_sha256':fingerprint(claim),'audit_chunk_id':chunk['id'],
                        'ref':addition['ref'],'association_citations':addition['association_citations']})
        for mention in audit['new_mentions']:
            new.append((chunk,{k:mention[k] for k in MENTION_FIELDS}))
        issues.extend({**i,'audit_chunk_id':chunk['id']} for i in audit['issues'])
        relations.extend({**r,'audit_chunk_id':chunk['id'],'status':'evidence_validated_identity_and_meaning_need_review'} for r in audit['relationships'])
    results=[]
    all_cues={};source_chunks={}
    if original_extraction is not None:
        # A selected-window evaluation must preserve base evidence from the
        # rest of the video, without sending it all to the model again.
        prepare(base,original_extraction)
        for c in original_extraction['chunks']:
            source_chunks[c['payload']['source']['external_id']]=c
            all_cues.update({s['segment_id']:s for s in c['payload']['segments']})
    for c in prepared['chunks']:
        sid=c['payload']['source']['external_id'];source_chunks[sid]=c
        for s in c['payload']['segments']+c['payload']['context_segments']:all_cues[s['segment_id']]=s
    for draft in drafts.values():
        sid=draft['source']['external_id'];c=source_chunks[sid]
        payload={**c['payload'],'segments':[s for key,s in all_cues.items() if key.rsplit(':',1)[0]==sid]}
        results.append(({'payload':payload},{'mentions':[{k:draft[k] for k in MENTION_FIELDS}]}))
    for c,mention in new:
        payload={**c['payload'],'segments':c['payload']['segments']+c['payload']['context_segments']}
        results.append(({'payload':payload},{'mentions':[mention]}))
    report=aggregate(results,catalog)
    from trippy.catalog.normalize import normalize_text
    mapping={}
    for previous in base['drafts']:
        anchors={fingerprint(q) for q in previous['citations']}
        mapping[previous['id']]=[d['id'] for d in report['drafts'] if
            d['source']['external_id']==previous['source']['external_id'] and
            (normalize_text(d['name']),d['kind'],d['branch'])==(normalize_text(previous['name']),previous['kind'],previous['branch']) and
            anchors&{fingerprint(q) for q in d['citations']}]
    for relation in relations:
        relation['subject_draft_ids']=mapping[relation['subject_id']]
        relation['object_draft_ids']=mapping[relation['object_id']]
    report.update(status='private_additive_audit_needs_semantic_identity_and_current_fact_review',
        base_report_sha256=fingerprint(base),base_to_merged_ids=mapping,
        prior_editorial_audit=base.get('editorial_audit',base.get('prior_editorial_audit',[])),
        prior_excluded_drafts=base.get('excluded_drafts',base.get('prior_excluded_drafts',[])),
        prior_audit_lineage=base.get('audit_lineage',[]),prior_final_check=base.get('final_check'),
        prior_relationship_proposals=base.get('relationship_proposals',[]),
        audit_lineage=lineage,review_issues=[*base.get('review_issues',[]),*issues],relationship_proposals=relations,
        audit_results=[a for _,a in audits],final_check=check(prepared,audits),ready_to_scale=False,ready_to_publish=False,
        summary={'base_mentions':len(base['drafts']),'merged_mentions':len(report['drafts']),
            'base_claims':sum(len(d['claims']) for d in base['drafts']),
            'merged_claims':sum(len(d['claims']) for d in report['drafts']),
            'new_claim_occurrences':len(lineage),'review_issues':len(issues)+len(base.get('review_issues',[])),'relationship_proposals':len(relations),
            'chunks_with_complete_cue_accounting':sum(a['cue_accounting_complete'] for _,a in audits),
            'audited_chunks':len(audits),'planned_chunks':len(prepared['chunks']),
            'quarantined_items':sum(len(a['quarantine']) for _,a in audits)})
    return report


def reservation_preview(chunks,values,output_cap):
    input_rate=Decimal(values['TRIPPY_LUNA_INPUT_PER_MILLION']);output_rate=Decimal(values['TRIPPY_LUNA_OUTPUT_PER_MILLION'])
    amounts=[]
    for c in chunks:
        messages=[{'role':'system','content':c['system_prompt']},{'role':'user','content':json.dumps(c['payload'],ensure_ascii=False)}]
        allowance=len(json.dumps(messages,ensure_ascii=False).encode())+len(json.dumps(c['response_schema']).encode())+4096
        amounts.append((allowance*input_rate+output_cap*output_rate)/Decimal(1000000))
    return {'calls':len(chunks),'output_cap':output_cap,'reservation':str(sum(amounts)),
        'per_call':[str(a) for a in amounts],'currency':values['TRIPPY_AI_BUDGET_CURRENCY']}


def execute(prepared,base,provider,cache_dir,catalog=None,original_extraction=None):
    chunks=validate_prepared(prepared,base);audits=[];failures=[]
    if original_extraction is not None:
        prepare(base,original_extraction)
    else:
        evidence={s['segment_id']:s for c in chunks for s in
                  c['payload']['segments']+c['payload']['context_segments']}
        for draft in base['drafts']:
            validate_result({'payload':{'segments':list(evidence.values())}},
                {'mentions':[{k:draft[k] for k in MENTION_FIELDS}]})
    cache_dir=Path(cache_dir);cache_dir.mkdir(parents=True,exist_ok=True,mode=0o700)
    for chunk in chunks:
        path=cache_dir/(chunk['id']+'.json')
        try:
            if path.exists():
                cached=json.loads(path.read_text())
                if cached['request_sha256']!=fingerprint(chunk):raise ValueError('Audit cache request mismatch')
                raw=cached['raw_candidate']
            else:
                raw=provider(chunk)
                private_write(path,{'request_sha256':fingerprint(chunk),'raw_candidate':raw})
            audits.append((chunk,validate_audit(chunk,raw)))
        except Exception as exc:
            failures.append({'chunk_id':chunk['id'],'error_type':type(exc).__name__,
                'reason':str(exc) if isinstance(exc,ValueError) else 'Audit failed; inspect retained provider receipt'})
            if type(exc).__name__ in {'BudgetError','ProviderConfigurationError'}:break
    report=merge(base,prepared,audits,catalog,original_extraction);report['execution_failures']=failures
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for field in ('base','extraction','output'):p.add_argument('--'+field,type=Path,required=True)
    p.add_argument('--execute-luna',action='store_true');p.add_argument('--env-file',type=Path,default=Path('.env'))
    p.add_argument('--replay-cache',action='store_true',help='Revalidate cached audit responses offline; missing responses fail without calling a model')
    p.add_argument('--prepare-final',action='store_true',help='Prepare compact v2 audit windows offline; evaluation required before live use')
    p.add_argument('--review-findings',type=Path,help='Content-bound transcript review findings for final offline preparation')
    p.add_argument('--audit-manifest',type=Path,help='Previously prepared audit manifest; exact prompt/base fingerprints are checked')
    p.add_argument('--window-indices',help='Comma-separated indices for a bounded final-design evaluation manifest')
    p.add_argument('--keyed-coverage',action='store_true',help='Use v3 required per-cue keys in final preparation')
    p.add_argument('--complete-pilot-audit',action='store_true',help='Audit up to 18 keyed windows from at most two existing pilot sources; never scale to new videos')
    p.add_argument('--budget-ledger',type=Path,default=Path('.local/stage3/extraction-budget.sqlite'))
    p.add_argument('--cache-dir',type=Path,default=Path('.local/stage3/coverage-cache'))
    p.add_argument('--catalog',type=Path,default=Path('.local/catalog.sqlite'))
    args=p.parse_args();base=json.loads(args.base.read_text());extraction=json.loads(args.extraction.read_text())
    if args.prepare_final:
        if args.execute_luna or args.replay_cache:p.error('Final-run preparation is offline only')
        findings=json.loads(args.review_findings.read_text()) if args.review_findings else None
        document=prepare_final(base,extraction,review_findings=findings,keyed_coverage=args.keyed_coverage)
        if args.window_indices:
            indices=[int(x) for x in args.window_indices.split(',')]
            if not indices or len(set(indices))!=len(indices) or any(i<0 or i>=len(document['chunks']) for i in indices):
                p.error('Invalid evaluation window indices')
            document['chunks']=[document['chunks'][i] for i in indices]
            document['evaluation_window_indices']=indices
        private_write(args.output,document)
        print(json.dumps({'status':document['status'],'chunks':len(document['chunks']),'model_calls':0}));return
    if args.execute_luna and args.replay_cache:p.error('Choose live execution or offline replay')
    prepared=json.loads(args.audit_manifest.read_text()) if args.audit_manifest else prepare(base,extraction)
    validate_prepared(prepared,base)
    if args.replay_cache:
        def unavailable(chunk):raise ValueError('Missing cached response; offline replay cannot call a model')
        report=execute(prepared,base,unavailable,args.cache_dir,args.catalog,extraction)
        private_write(args.output,report);print(json.dumps(report['summary']));return
    if not args.execute_luna:private_write(args.output,prepared);print(json.dumps({'status':prepared['status'],'chunks':len(prepared['chunks'])}));return
    limit=18 if args.complete_pilot_audit else 6
    if len(prepared['chunks'])>limit:raise ValueError('Coverage pilot window limit exceeded')
    if args.complete_pilot_audit:
        sources={c['payload']['source']['external_id'] for c in prepared['chunks']}
        base_sources={d['source']['external_id'] for d in base['drafts']}
        if len(sources)>2 or not sources<=base_sources or any(c['prompt_version']!='coverage-3' for c in prepared['chunks']):
            raise ValueError('Complete pilot audit requires keyed windows from the existing two-source pilot')
    from trippy_config import read_environment
    from .luna import make_provider
    values=read_environment(args.env_file)
    revisions={c['prompt_version'] for c in prepared['chunks']}
    if len(revisions)!=1:raise ValueError('Mixed audit prompt revisions are not supported')
    values['TRIPPY_LUNA_REQUEST_GROUP']=('barcelona-coverage-v1-20261030' if revisions=={'coverage-1'}
        else 'barcelona-'+next(iter(revisions))+'-eval-'+fingerprint(prepared)[:16])
    values['TRIPPY_LUNA_MAX_REQUESTS']=str(len(prepared['chunks']))
    # Preflight the whole first-attempt batch against the existing shared cap.
    pending=[c for c in prepared['chunks'] if not (args.cache_dir/(c['id']+'.json')).exists()]
    preview=reservation_preview(pending,values,16000)
    with closing(sqlite3.connect(args.budget_ledger.resolve().as_uri()+'?mode=ro',uri=True)) as db:
        row=db.execute('SELECT currency,reserved FROM extraction_budget WHERE id=1').fetchone()
    if row and row[0]!=preview['currency']:raise ValueError('Audit budget currency mismatch')
    if Decimal(row[1] if row else '0')+Decimal(preview['reservation'])>Decimal(values['TRIPPY_AI_BUDGET_AMOUNT']):
        raise ValueError('Six-call audit reservation would exceed the existing budget cap')
    private_write(args.output,{'status':'coverage_audit_running','reservation_preview':preview})
    provider=make_provider(values,args.budget_ledger,max_output_tokens=16000)
    report=execute(prepared,base,provider,args.cache_dir,args.catalog,extraction);report['reservation_preview']=preview
    temporary=args.output.with_suffix('.tmp');private_write(temporary,report);temporary.replace(args.output)
    print(json.dumps(report['summary']))


if __name__=='__main__':main()
