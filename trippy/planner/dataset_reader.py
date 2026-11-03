"""Source discovery reader. No inferred identity, current service or map point."""
from copy import deepcopy
from collections import Counter
from trippy.sources.extraction import fingerprint


ACTIVITY_MATCHES = {
    'coffee_break': [('service', 'coffee')],
    'breakfast_out': [('service', 'breakfast'), ('meal_context', 'breakfast')],
    'brunch': [('service', 'brunch'), ('meal_context', 'brunch')],
    'local_market': [('place_type', 'market')],
    'sweet_break': [('service', x) for x in ('pastries', 'dessert', 'ice_cream')],
    'park_pause': [('place_type', 'park')], 'beach_pause': [('place_type', 'beach')],
    'live_music': [('service', 'live_music')],
    'groceries': [('service', 'groceries'), ('place_type', 'supermarket'), ('place_type', 'convenience_store')],
}
LAYERS = {
    'coffee': [('service', 'coffee'), ('place_type', 'cafe')],
    'breakfast_brunch': [('service', 'breakfast'), ('meal_context', 'breakfast'), ('service', 'brunch'), ('meal_context', 'brunch')],
    'restaurants': [('place_type', 'restaurant')],
    'bars': [('place_type', 'bar'), ('service', 'drinks')],
    'sights': [('place_type', x) for x in ('landmark', 'museum', 'church', 'stadium', 'plaza', 'park', 'beach', 'viewpoint')],
    'groceries': ACTIVITY_MATCHES['groceries'],
}


def compile_dataset(bundle, *, pack=None, held=None, migrations=()):
    pack = pack or bundle['normalized']
    records = {r['id']: r for r in pack['drafts']}
    aliases = {**{k: k for k in records}, **pack.get('previous_to_normalized_ids', {})}
    places = {}
    for record in records.values():
        key = 'source:'+record['upstream_occurrence_id']
        if key in places:
            raise ValueError('Duplicate source occurrence')
        places[key] = {'id': key, 'record_id': record['id'], 'name': record['name'],
            'kind': record['kind'], 'identity': 'ambiguous' if record['identity_uncertain'] else 'candidate',
            'canonical_id': None, 'latitude': None, 'longitude': None,
            'location': 'unknown', 'tags': [], 'activities': [], 'details': [],
            'source': deepcopy(record['source']), 'published_at': record.get('published_at'),
            'record': deepcopy(record), 'limitations': ['canonical_identity_pending', 'current_fields_pending']}
    by_record = {p['record_id']: p for p in places.values()}
    admitted = []; deferred = []; migration_by_key = {m['annotation_key']: m for m in migrations}
    if len(migration_by_key) != len(migrations):
        raise ValueError('Duplicate migration')
    applied = []

    def binding(old_id, claim_ids):
        record_id = aliases.get(old_id, old_id)
        record = records.get(record_id)
        return by_record.get(record_id), bool(record and set(claim_ids) <= {fingerprint(c) for c in record['claims']})

    def attach(place, key, kind, proposal, method):
        value = deepcopy(proposal)
        value.update(annotation_key=key, review_method=method,
                     scope='source_recommendation_not_current_service')
        field = 'activities' if kind == 'activity_fit' else 'tags' if kind == 'facet' else 'details'
        place[field].append(value)
        admitted.append(key)

    for item in bundle['annotations']:
        entry = item['original_entry']; proposal = item['effective']['proposal']
        place, bound = binding(entry['record_id'], proposal['claim_ids'])
        eligible = bool(item['source_discovery_eligible'] and item['manual_decision'] and bound)
        if not eligible:
            deferred.append({'key': item['key'], 'status': item['status'], 'binding_current': bound,
                             'record_id': place['id'] if place else None})
            continue
        attach(place, item['key'], item['effective']['kind'], proposal, 'existing_manual_source_comparison')
        migration = migration_by_key.get(item['key'])
        if migration:
            if (migration['source_entry_sha256'] != fingerprint(entry) or
                migration['effective_sha256'] != fingerprint(item['effective']) or
                migration['review_method'] != 'agent_exact_source_quote_comparison' or not migration['reason']):
                raise ValueError('Stale/unreviewed taxonomy migration')
            attach(place, item['key']+':typed', 'facet', {
                'key': migration['key'], 'value': migration['value'], 'claim_ids': proposal['claim_ids']},
                migration['review_method'])
            applied.append(item['key'])
    for i, review in enumerate(bundle['preserved_manual_reviews']):
        place, bound = binding(review['record_id'], review['facet']['claim_ids'])
        if bound and review['source_discovery_eligible']:
            attach(place, 'prior:'+str(i), 'facet', review['facet'], review['review_method'])
    # Preserve ALL originals, including holds/proposals, outside discovery eligibility.
    return {'version': 1, 'bundle_sha256': fingerprint(bundle), 'pack_sha256': fingerprint(pack),
        'places': sorted(places.values(), key=lambda p: p['id']),
        'held_claims': deepcopy(bundle['held_claims'] if held is None else held),
        'annotation_lineage': deepcopy(bundle['annotations']),
        'prior_manual_reviews': deepcopy(bundle['preserved_manual_reviews']),
        'identity_evidence': deepcopy(bundle['identity_links']),
        'operational_evidence': deepcopy(bundle['operational']),
        'metrics': {'source_occurrences': len(places), 'admitted_annotation_items': len(admitted),
                    'taxonomy_migrations_applied': len(applied), 'deferred_annotations': len(deferred)},
        'deferred_annotations': deferred, 'planner_ready': False, 'ready_to_publish': False}


def retrieve_activity(compiled, activity, *, excluded_ids=(), limit=6):
    if type(limit) is not int or not 1 <= limit <= 100:
        raise ValueError('Bounded retrieval limit required')
    results = []
    for place in compiled['places']:
        if place['id'] in excluded_ids or place['kind'] != 'venue':
            continue
        evidence = [a for a in place['activities'] if a['activity_id'] == activity]
        evidence += [t for t in place['tags'] if (t['key'], t['value']) in ACTIVITY_MATCHES.get(activity, [])]
        if not evidence:
            continue
        results.append({'place_id': place['id'], 'name': place['name'], 'identity': place['identity'],
            'location': place['location'], 'evidence': deepcopy(evidence),
            'state': 'source_discovery_candidate_needs_identity_and_selected_checks'})
    results.sort(key=lambda p: (p['name'].casefold(), p['place_id']))
    return {'activity_id': activity, 'items': results[:limit], 'total_occurrences': len(results),
            'coverage_gap': not results, 'unique_canonical_places': 0,
            'ranking_basis': 'reviewed_source_match_then_stable_name_and_occurrence_id_no_route_or_rating_claim'}


def map_layers(compiled, selected_ids=()):
    selected = set(selected_ids); layers = {}
    for name, matches in LAYERS.items():
        rows = []
        for p in compiled['places']:
            activity_match = any(a['activity_id'] in {
                'coffee': {'coffee_break'}, 'breakfast_brunch': {'breakfast_out', 'brunch'}}.get(name, set()) for a in p['activities'])
            if not activity_match and not any((t['key'], t['value']) in matches for t in p['tags']):
                continue
            rows.append({'place_id': p['id'], 'name': p['name'], 'identity': p['identity'],
                         'pin': None, 'pin_state': 'coordinates_and_identity_pending',
                         'selected_in_draft': p['id'] in selected})
        layers[name] = {'all_known_candidates': rows,
                        'according_to_plan': [r for r in rows if r['selected_in_draft']]}
    layers['plan'] = {'according_to_plan': [{'place_id': p['id'], 'name': p['name'], 'pin': None}
        for p in compiled['places'] if p['id'] in selected]}
    return {'layers': layers, 'coverage': 'known_source_occurrences_not_all_city_businesses',
            'scheduled_or_verified': False}
