"""Materialize explicitly adjudicated source claims, preserving every upstream claim.

Model repair proposals are held for review; only source-bound agent repairs apply.
This creates a private source pack, never canonical/current planner facts.
"""
from collections import Counter
from copy import deepcopy
import argparse
import json
from pathlib import Path

from .coverage import private_write
from .curation_cycle import load_pack, validate_pack
from .extraction import Citation, Claim, fingerprint
from .semantic_review import validate_review


def materialize(records, cues, prepared, effective, manual_documents):
    if effective['prepared_sha256'] != fingerprint(prepared):
        raise ValueError('Source dispositions belong to another prepared input')
    entries = {e['key']:e for chunk in prepared['chunks'] for e in chunk['payload']['entries']}
    original_keys = {fingerprint({'occurrence':r['id'], 'claim':c})
                     for r in records for c in r['claims']}
    if set(entries) != original_keys:
        raise ValueError('Prepared claims differ from normalized source pack')
    decisions = {}; manual_keys = set()
    for decision in effective['decisions']:
        key = decision['key']
        if key not in entries or key in decisions:
            raise ValueError('Missing, unknown or duplicate effective source disposition')
        entry = entries[key]
        if decision['original_entry_sha256'] != fingerprint(entry):
            raise ValueError('Effective source disposition targets stale context')
        clean = {k:v for k,v in decision.items() if k not in {'approval','original_entry_sha256'}}
        validate_review({'payload':{'entries':[entry]}}, {'decisions':[clean]})
        decisions[key] = {'decision':deepcopy(decision), 'review_kind':'model_source_comparison'}
    if set(decisions) != original_keys:
        raise ValueError('Effective source dispositions incomplete')
    for document in manual_documents:
        if document.get('review_method') != 'agent_source_comparison':
            raise ValueError('Only explicit agent source comparisons may adjudicate repairs')
        supplied = document.get('decisions', document.get('review', {}).get('decisions'))
        if supplied is None: raise ValueError('Manual source decisions missing')
        for decision in supplied:
            key = decision['key']
            if key not in entries or key in manual_keys:
                raise ValueError('Unknown or duplicate manual adjudication')
            entry = entries[key]
            if decision['original_entry_sha256'] != fingerprint(entry):
                raise ValueError('Manual adjudication targets stale claim/context')
            clean = {k:v for k,v in decision.items() if k not in {'approval','original_entry_sha256'}}
            reviewed = validate_review({'payload':{'entries':[entry]}}, {'decisions':[clean]})['decisions'][0]
            decisions[key] = {'decision':reviewed, 'review_kind':'agent_source_comparison',
                              'manual_document_sha256':fingerprint(document)}
            manual_keys.add(key)
    output = []; held = []; events = []; id_mapping = {}; states = Counter()
    for source_record in records:
        record = deepcopy(source_record); claims = []; review_metadata = []
        for original in source_record['claims']:
            key = fingerprint({'occurrence':source_record['id'], 'claim':original})
            adjudication = decisions[key]; decision = adjudication['decision']
            if decision['action'] == 'unresolved': state = 'held_unresolved'
            elif decision['action'] == 'repair' and key not in manual_keys: state = 'held_repair_proposal'
            elif decision['action'] == 'repair': state = 'source_repair_applied'
            else: state = 'source_supported'
            states[state] += 1
            if state.startswith('held_'):
                held.append({'key':key, 'upstream_occurrence_id':source_record['id'],
                    'original_claim':deepcopy(original), 'state':state,
                    'adjudication':adjudication, 'planner_use':'excluded_pending_review'})
                continue
            claim = deepcopy(original)
            if state == 'source_repair_applied':
                claim.update({f:decision[f] for f in ('dimension','value','basis')})
                quotes = []
                for segment_id in decision['evidence_segment_ids']:
                    cue = cues.get(segment_id)
                    if cue is None or segment_id.rsplit(':',1)[0] != source_record['source']['external_id']:
                        raise ValueError('Repair evidence missing or belongs to another video')
                    quotes.append(Citation.model_validate({k:cue[k] for k in
                        ('segment_id','start_seconds','end_seconds')} | {'quote':cue['text']}).model_dump())
                claim['citations'] = quotes
                Claim.model_validate(claim)
                events.append({'key':key, 'upstream_occurrence_id':source_record['id'],
                    'original_claim':deepcopy(original), 'corrected_claim':deepcopy(claim),
                    'before_sha256':fingerprint(original), 'after_sha256':fingerprint(claim),
                    'adjudication':adjudication,
                    'scope':'Source editorial repair only; no independent/current fact approval'})
            claims.append(claim)
            review_metadata.append({'claim_sha256':fingerprint(claim), 'upstream_key':key,
                'state':state, 'review_kind':adjudication['review_kind'],
                'use_scope':decision['use_scope'], 'independently_verified':False,
                'current_trip_verified':False})
        record['claims'] = claims
        record['claim_review_metadata'] = review_metadata
        record['category_review_pending'] = True
        record['upstream_occurrence_id'] = source_record['id']
        record['id'] = fingerprint({'upstream_occurrence_id':source_record['id'],
            'source_editorial_claims':claims, 'reviews':review_metadata})
        id_mapping[source_record['id']] = record['id']; output.append(record)
    validate_pack(output, cues)
    if sum(states.values()) != len(original_keys): raise ValueError('Claims lost in materialization')
    manifest = {'version':1, 'engine_sha256':fingerprint(Path(__file__).read_text()),
        'records_sha256':fingerprint(records), 'cues_sha256':fingerprint(cues),
        'prepared_sha256':fingerprint(prepared), 'effective_sha256':fingerprint(effective),
        'manual_document_sha256s':[fingerprint(d) for d in manual_documents]}
    return {'manifest':manifest, 'run_id':fingerprint(manifest), 'normalized':{'drafts':output,
        'upstream_to_normalized_ids':id_mapping, 'status':'private_adjudicated_source_pack_not_canonical',
        'ready_to_publish':False}, 'held_claims':held, 'editorial_events':events,
        'summary':{'records':len(output), 'upstream_claims':len(original_keys),
            'active_source_claims':sum(len(r['claims']) for r in output),
            'states':dict(states), 'manual_claim_adjudications':len(manual_keys),
            'claims_preserved_in_active_or_held':sum(states.values()),
            'source_evidence_revalidated':True, 'names_or_identities_merged':0,
            'approved_canonical_places':0, 'planner_ready':False, 'paid_model_calls':0,
            'remaining':'Pending repairs/unresolved subjects, category/fit review, canonical identities, primary/current facts, coverage and executed planner scenarios'}}


def write_artifact(root, result):
    folder = Path(root)/result['run_id'][:16]
    for name, document in {'manifest.json':result['manifest'], 'normalized.json':result['normalized'],
        'held-claims.json':result['held_claims'], 'editorial-events.json':result['editorial_events'],
        'summary.json':result['summary']}.items():
        path = folder/name
        if path.exists():
            if json.loads(path.read_text()) != document:
                raise ValueError('Materialized artifact differs; do not overwrite')
        else: private_write(path, document)
    return folder


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', required=True, type=Path)
    args = parser.parse_args()
    recipe = json.loads(args.recipe.read_text())
    source_recipe = json.loads(Path(recipe['source_recipe']).read_text())
    audit = json.loads(Path(source_recipe['inputs']).read_text())
    original = json.loads(Path(source_recipe['original']).read_text())
    _, cues, _ = load_pack(audit['inputs'], original)
    records = json.loads(Path(recipe['normalized_input']).read_text())['drafts']
    result = materialize(records, cues,
        json.loads(Path(recipe['prepared']).read_text()),
        json.loads(Path(recipe['effective']).read_text()),
        [json.loads(Path(path).read_text()) for path in recipe['manual_documents']])
    folder = write_artifact(recipe['output_root'], result)
    print(json.dumps({'folder':str(folder), 'summary':result['summary']}, indent=2))


if __name__ == '__main__': main()
