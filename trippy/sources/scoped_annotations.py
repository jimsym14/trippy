"""Keep manually compared source annotations separate from planner capabilities."""
from collections import Counter
from copy import deepcopy
from pathlib import Path

from .extraction import fingerprint


STATUS_SCOPES = {
    'source_supported_with_qualifier': 'exact_venue',
    'source_observation_only': 'visit_context',
    'context_only': 'general_or_area',
    'compound_venue_context': 'subvenue_unspecified',
    'held_insufficient_citation': 'unresolved',
}


def materialize(proposals, audit, current_pack):
    if audit['upstream_manifest_sha256'] != fingerprint(proposals['manifest']):
        raise ValueError('Tag audit belongs to another recovered input')
    slots = {}
    for chunk in proposals['chunks']:
        sources = {e['record_id']: e for e in chunk['source_entries']}
        for record_id, record in chunk['response']['records'].items():
            for facet in record['facets']:
                key = (record_id, fingerprint(facet))
                if key in slots:
                    raise ValueError('Duplicate source facet')
                slots[key] = (facet, sources[record_id])
    id_mapping = current_pack['previous_to_normalized_ids']
    current = {r['id']: r for r in current_pack['drafts']}
    reviewed = []; seen = set(); counts = Counter()
    for review in audit['reviews']:
        key = (review['record_id'], review['facet_sha256'])
        if key not in slots or key in seen:
            raise ValueError('Unknown or duplicate tag review')
        seen.add(key); facet, source = slots[key]
        if review['facet'] != facet or fingerprint(facet) != review['facet_sha256']:
            raise ValueError('Stale facet review')
        claims = {c['id']: c for c in source['claims']}
        if any(c['id'] != fingerprint({k: v for k, v in c.items() if k != 'id'}) for c in source['claims']):
            raise ValueError('Source annotation claim hash differs from content')
        if review['source_claims'] != [claims[i] for i in facet['claim_ids']]:
            raise ValueError('Manual tag comparison targets stale evidence')
        if review.get('review_method') != 'agent_exact_source_quote_comparison':
            raise ValueError('Manual exact source comparison required')
        status = review['status']
        if status not in STATUS_SCOPES:
            raise ValueError('Unknown manual tag disposition')
        old_id = review['record_id']; new_id = id_mapping.get(old_id)
        if new_id not in current:
            raise ValueError('Reviewed occurrence missing from current source pack')
        available = {fingerprint(c) for c in current[new_id]['claims']}
        # Source annotations use a content hash as claim identity. New editorial
        # repairs must never silently inherit annotations from superseded text.
        unchanged = all(i in available for i in facet['claim_ids'])
        counts[status] += 1
        reviewed.append({**deepcopy(review), 'current_record_id': new_id,
            'assertion_scope': STATUS_SCOPES[status],
            'claim_binding_current': unchanged,
            'source_discovery_eligible': unchanged and status=='source_supported_with_qualifier',
            'canonical_identity_verified': False, 'current_trip_verified': False,
            'planner_fact_eligible': False,
            'gate': 'canonical_identity_and_current_evidence_required' if unchanged else 'changed_claim_requires_new_annotation_review'})
    manifest = {'proposals_sha256': fingerprint(proposals), 'audit_sha256': fingerprint(audit),
                'current_pack_sha256': fingerprint(current_pack),
                'engine_sha256': fingerprint(Path(__file__).read_text()), 'version': 1}
    return {'manifest': manifest, 'reviews': reviewed,
        'summary': {'reviewed_facets': len(reviewed), 'dispositions': dict(counts),
            'unreviewed_facets': len(slots)-len(seen),
            'source_discovery_eligible': sum(r['source_discovery_eligible'] for r in reviewed),
            'stale_claim_bindings': sum(not r['claim_binding_current'] for r in reviewed),
            'planner_ready': False, 'paid_model_calls': 0}, 'ready_to_publish': False}


def main():
    import argparse
    import json
    from .unattended import immutable_write
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, required=True)
    args = parser.parse_args()
    read = lambda path: json.loads(Path(path).read_text())
    recipe = read(args.recipe)
    result = materialize(read(recipe['proposals']), read(recipe['audit']), read(recipe['current_pack']))
    folder = Path(recipe['output_root']) / fingerprint(result['manifest'])[:16]
    immutable_write(folder/'reviewed-tags.json', result)
    print(json.dumps({'folder': str(folder), 'summary': result['summary']}, indent=2))


if __name__ == '__main__': main()
