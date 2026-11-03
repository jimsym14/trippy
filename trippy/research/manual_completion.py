"""Apply content-bound manual annotation corrections without paid calls or publication."""
import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path

from trippy.sources.extraction import fingerprint
from trippy.sources.followup_materialize import SCOPES, LIFECYCLES
from trippy.sources.unattended import immutable_write


FINDINGS = {'confirmed_annotation_error', 'model_review_error', 'taxonomy_gap',
            'insufficient_evidence', 'scope_clarification', 'formatting_error'}


def materialize(items, quarantined, audit, registry, baseline, staged):
    inputs = {'items_sha256': fingerprint(items), 'quarantine_sha256': fingerprint(quarantined),
              'registry_sha256': fingerprint(registry), 'baseline_sha256': fingerprint(baseline),
              'staged_sha256': fingerprint(staged)}
    if audit['inputs'] != inputs:
        raise ValueError('Manual audit belongs to different source inputs')
    slots = {}
    for item in items + quarantined:
        entry = item['entry']
        if entry['key'] in slots:
            raise ValueError('Duplicate annotation slot')
        slots[entry['key']] = item
    current = {r['id']: r for r in staged['drafts']}
    decisions = {}; findings = Counter(); actions = Counter(); effective = []
    for d in audit['decisions']:
        key = d['key']
        if key not in slots or key in decisions:
            raise ValueError('Unknown or duplicate manual decision')
        entry = slots[key]['entry']
        if fingerprint(entry) != d['entry_sha256']:
            raise ValueError('Stale manual entry')
        if d['review_method'] != 'agent_exact_source_quote_comparison' or not d['reason']:
            raise ValueError('Explicit source comparison required')
        if d['finding'] not in FINDINGS or d['action'] not in {'retain', 'replace', 'context', 'reject', 'hold'}:
            raise ValueError('Unsupported manual disposition')
        if d['assertion_scope'] not in SCOPES or d['lifecycle'] not in LIFECYCLES:
            raise ValueError('Explicit scope/lifecycle required')
        claims = {c['id']: c for c in entry['claims']}
        for c in claims.values():
            if c['id'] != fingerprint({k:v for k,v in c.items() if k!='id'}):
                raise ValueError('Source claim content hash differs')
        if not d['evidence_claim_ids'] or not set(d['evidence_claim_ids']) <= claims.keys():
            raise ValueError('Foreign or absent manual evidence')
        if d['evidence_sha256'] != fingerprint([claims[i] for i in d['evidence_claim_ids']]):
            raise ValueError('Stale manual evidence')
        after = d['after']
        if d['action'] == 'replace':
            if not isinstance(after, dict) or set(after) != {'kind', 'proposal'}:
                raise ValueError('Explicit typed replacement required')
            kind = after['kind']; proposal = after['proposal']
            if set(proposal) != {'key','value','claim_ids'} or proposal['claim_ids'] != d['evidence_claim_ids']:
                raise ValueError('Replacement must preserve selected evidence')
            if not isinstance(proposal['value'], str) or not proposal['value'].strip():
                raise ValueError('Empty manual replacement')
            name, value = proposal['key'], proposal['value']
            if kind == 'facet':
                if name not in registry['facet_keys'] or (name in registry['closed_values'] and value not in registry['closed_values'][name]):
                    raise ValueError('Replacement facet outside taxonomy')
            elif kind == 'detail':
                if name not in registry['detail_keys']:
                    raise ValueError('Replacement detail outside taxonomy')
            else:
                raise ValueError('New activity fits require separately reviewed proposals')
        elif after is not None:
            raise ValueError('Only replace may change original content')
        if d['action']=='retain' and entry['kind']=='facet':
            name,value=entry['proposal']['key'],entry['proposal']['value']
            if name not in registry['facet_keys'] or (name in registry['closed_values'] and value not in registry['closed_values'][name]):
                raise ValueError('Retained facet outside taxonomy; migrate or hold explicitly')
        decisions[key] = deepcopy(d); findings[d['finding']] += 1; actions[d['action']] += 1
    for key, item in slots.items():
        entry = item['entry']; d = decisions.get(key)
        base_id = baseline.get('previous_to_normalized_ids', {}).get(entry['record_id'], entry['record_id'])
        current_id = staged['previous_to_staged_ids'].get(base_id, base_id)
        record = current.get(current_id)
        ids = d['evidence_claim_ids'] if d else entry['proposal']['claim_ids']
        available = {fingerprint(c) for c in record['claims']} if record else set()
        bound = set(ids) <= available
        status = d['action'] if d else 'manual_review_pending'
        selected = (d['after'] if d and d['action']=='replace'
                    else {'kind':entry['kind'],'proposal':entry['proposal']})
        effective.append({'key':key, 'source_entry_sha256':fingerprint(entry),
            'original_entry':deepcopy(entry), 'effective':deepcopy(selected),
            'manual_decision':d, 'status':status,
            'current_record_id':current_id if record else None, 'claim_binding_current':bound,
            'source_discovery_eligible':bool(d and status in {'retain','replace'} and bound
                and d['assertion_scope'] in {'exact_venue','visit_context'}
                and entry['record_kind']=='venue' and not entry.get('identity_uncertain')),
            'canonical_identity_verified':False, 'current_trip_verified':False,
            'planner_fact_eligible':False,
            'upstream_automated_result':deepcopy(item.get('decision', item.get('original_fields'))),
            'unapplied_suggestions':deepcopy(item.get('unapplied_suggestions',[]))})
    return {'manifest':{'inputs':inputs,'audit_sha256':fingerprint(audit),
                       'engine_sha256':fingerprint(Path(__file__).read_text()),'version':1},
        'annotations':effective,
        'summary':{'total_slots':len(slots), 'manual_reviewed':len(decisions),
            'manual_review_pending':len(slots)-len(decisions), 'findings':dict(findings),
            'actions':dict(actions), 'stale_manual_claim_bindings':sum(
                bool(e['manual_decision']) and not e['claim_binding_current'] for e in effective),
            'source_discovery_eligible':sum(e['source_discovery_eligible'] for e in effective),
            'source_claims_modified':0, 'paid_calls':0, 'http_requests':0,
            'ready_to_publish':False},'ready_to_publish':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe',type=Path,required=True)
    args=parser.parse_args(); read=lambda p:json.loads(Path(p).read_text())
    recipe=read(args.recipe); root=Path(recipe['recovery_root'])
    result=materialize(read(root/'annotation-items.json'),read(root/'quarantined-items.json'),
        read(recipe['audit']),read(recipe['registry']),read(recipe['baseline']),read(root/'staged-source-pack.json'))
    preserved=read(recipe['preserved_reviews'])['preserved_manual_reviews']
    result['manifest']['preserved_manual_reviews_sha256']=fingerprint(preserved)
    result['preserved_manual_reviews']=preserved
    result['summary']['previous_manual_reviews_preserved']=len(preserved)
    folder=Path(recipe['output_root'])/fingerprint(result['manifest'])[:16]
    immutable_write(folder/'effective-annotations.json',result)
    immutable_write(folder/'summary.json',result['summary'])
    print(json.dumps({'folder':str(folder),'summary':result['summary']},indent=2))


if __name__=='__main__': main()
