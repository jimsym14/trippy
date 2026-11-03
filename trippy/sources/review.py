"""Audit raw model responses into evidence-valid drafts and a quarantine queue.

No model calls. Exact quotes can locate a unique existing cue, allowing IDs/times
to be reconstructed deterministically. Unsupported names/claims remain rejected.
"""
from collections import Counter
from contextlib import closing
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path
import sqlite3

from .extraction import Extraction, aggregate, validate_result


def split_exact_quote(citation, segments):
    """Recover a unique quote spanning adjacent cues, without rewriting speech."""
    quote=citation['quote'];matches=[]
    for start in range(len(segments)):
        for length in range(2,min(4,len(segments)-start)+1):
            window=segments[start:start+length]
            # Never stitch omitted cues or sources together.
            ids=[s['segment_id'].rsplit(':',1) for s in window]
            if any(len(i)!=2 or not i[1].isdigit() for i in ids):continue
            if any(a[0]!=b[0] or int(b[1])!=int(a[1])+1 for a,b in zip(ids,ids[1:])):continue
            joined=' '.join(s['text'] for s in window)
            offset=joined.find(quote)
            if offset<0 or joined.find(quote,offset+1)>=0:continue
            end=offset+len(quote);position=0;parts=[]
            for segment in window:
                left=max(offset,position);right=min(end,position+len(segment['text']))
                if left<right:
                    parts.append({'segment_id':segment['segment_id'],
                        'start_seconds':segment['start_seconds'],'end_seconds':segment['end_seconds'],
                        'quote':segment['text'][left-position:right-position]})
                position+=len(segment['text'])+1
            if len(parts)>1 and ' '.join(p['quote'] for p in parts)==quote and parts not in matches:
                matches.append(parts)
    return matches[0] if len(matches)==1 else None


def repair_citations(mention,chunk):
    repaired=deepcopy(mention);repairs=[]
    segments=chunk['payload']['segments'];by_id={s['segment_id']:s for s in segments}
    collections=[repaired['citations'],*(c['citations'] for c in repaired['claims'])]
    if repaired['rating']:collections.append(repaired['rating']['citations'])
    for citations in collections:
        updated=[]
        for citation in citations:
            segment=by_id.get(citation['segment_id'])
            if not segment or citation['quote'] not in segment['text']:
                matches=[s for s in segments if citation['quote'] in s['text']]
                segment=matches[0] if len(matches)==1 else None
            if not segment:
                parts=split_exact_quote(citation,segments)
                if parts:
                    repairs.append({'original':deepcopy(citation),'corrected':parts,
                        'basis':'unique_exact_quote_across_adjacent_cues; joined_quote_text_unchanged'})
                    updated.extend(parts)
                else:updated.append(citation)
                continue
            expected={'segment_id':segment['segment_id'],'start_seconds':segment['start_seconds'],
                      'end_seconds':segment['end_seconds'],'quote':citation['quote']}
            if citation!=expected:
                repairs.append({'original':deepcopy(citation),'corrected':expected,
                    'basis':'exact_quote_in_cited_or_unique_existing_segment; quote_text_unchanged'})
                citation.update(expected)
            updated.append(citation)
        citations[:]=updated
    return repaired,repairs


def partition_mentions(chunk,candidate):
    accepted,rejected,repairs=[],[],[]
    if not isinstance(candidate,dict) or set(candidate)!={'mentions'} or not isinstance(candidate['mentions'],list) or len(candidate['mentions'])>120:
        raise ValueError('Invalid extraction envelope')
    for entry in candidate['mentions']:
        try:original=Extraction.model_validate({'mentions':[entry]}).model_dump()['mentions'][0]
        except ValueError:
            rejected.append({'kind':'mention_schema','name':entry.get('name') if isinstance(entry,dict) else None,
                'reason':'Mention does not satisfy strict extraction schema','candidate':entry})
            continue
        mention,changes=repair_citations(original,chunk)
        base={**mention,'claims':[],'rating':None}
        try:validate_result(chunk,{'mentions':[base]})
        except ValueError as exc:
            rejected.append({'kind':'mention','name':mention['name'],'reason':str(exc),'candidate':original});continue
        for claim in mention['claims']:
            try:validate_result(chunk,{'mentions':[{**base,'claims':[claim]}]})
            except ValueError as exc:
                rejected.append({'kind':'claim','name':mention['name'],'reason':str(exc),'candidate':claim});continue
            base['claims'].append(claim)
        if mention['rating']:
            try:validate_result(chunk,{'mentions':[{**base,'rating':mention['rating']}]})
            except ValueError as exc:
                rejected.append({'kind':'rating','name':mention['name'],'reason':str(exc),'candidate':mention['rating']})
            else:base['rating']=mention['rating']
        accepted.append(base);repairs.extend(changes)
    return {'mentions':accepted},rejected,repairs


def review_responses(prepared,ledger,*,group,catalog=None):
    chunks={c['id']:c for c in prepared['chunks']};responses=[];results=[];quarantine=[];repairs=[]
    coverage={key:{'responses':0,'accepted_mentions':0,'quarantined_items':0} for key in chunks}
    with closing(sqlite3.connect(Path(ledger).resolve().as_uri()+'?mode=ro',uri=True)) as db:
        rows=db.execute('SELECT id,chunk_id FROM extraction_requests WHERE request_group=? ORDER BY id',(group,)).fetchall()
    raw_dir=Path(ledger).parent/'extraction-raw-responses'
    for request_id,chunk_id in rows:
        if chunk_id not in chunks:continue
        path=raw_dir/f'request-{request_id}.json'
        if not path.exists():continue
        document=json.loads(path.read_text());choice=document['choices'][0]
        receipt={'request_id':request_id,'chunk_id':chunk_id,'raw_file':str(path.resolve()),
            'raw_sha256':sha256(path.read_bytes()).hexdigest(),'finish_reason':choice['finish_reason']}
        responses.append(receipt)
        if choice['finish_reason']!='stop' or choice['message'].get('refusal'):continue
        try:
            candidate=json.loads(choice['message']['content'])
            accepted,rejected,changes=partition_mentions(chunks[chunk_id],candidate)
        except (ValueError,TypeError) as exc:
            quarantine.append({**receipt,'kind':'response','reason':type(exc).__name__});continue
        results.append((chunks[chunk_id],accepted));coverage[chunk_id]['responses']+=1
        coverage[chunk_id]['accepted_mentions']+=len(accepted['mentions'])
        coverage[chunk_id]['quarantined_items']+=len(rejected)
        quarantine.extend({**entry,'request_id':request_id,'chunk_id':chunk_id,
            'status':'unvalidated_not_publishable'} for entry in rejected)
        repairs.extend({**entry,'request_id':request_id,'chunk_id':chunk_id} for entry in changes)
    report=aggregate(results,catalog)
    report.update(response_receipts=responses,quarantine=quarantine,citation_repairs=repairs,chunk_coverage=coverage,
        summary={'chunks_with_complete_responses':sum(c['responses']>0 for c in coverage.values()),
            'chunks_with_accepted_mentions':sum(c['accepted_mentions']>0 for c in coverage.values()),
            'planned_chunks':len(chunks),'draft_mentions':len(report['drafts']),
            'possible_identity_groups':len(report['review_queue']),
            'citation_valid_claims':sum(len(d['claims']) for d in report['drafts']),
            'quarantined_items':len(quarantine),'citation_repairs':len(repairs),
            'by_category':dict(Counter(c for d in report['drafts'] for c in d['categories']))},
        fact_check_status='not_independently_fact_checked',
        semantic_review_status='required; exact_citations_do_not_prove_claim_meaning_or_entity_identity',
        additional_model_calls=0)
    return report


def main(argv=None):
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared',type=Path,required=True)
    parser.add_argument('--ledger',type=Path,required=True)
    parser.add_argument('--group',required=True)
    parser.add_argument('--catalog',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(argv)
    prepared=json.loads(args.prepared.read_text())
    # Reserve a private, exclusive output before performing the audit.
    import os
    descriptor=os.open(args.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'w') as output:
        report=review_responses(prepared,args.ledger,group=args.group,catalog=args.catalog)
        output.write(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['summary'],ensure_ascii=False))


if __name__=='__main__':main()
