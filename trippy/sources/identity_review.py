"""Read-only branch-aware matching proposals, never canonical identity approval."""
import argparse
from collections import defaultdict
from contextlib import closing
import json
from pathlib import Path
import re
import sqlite3
from urllib.parse import urlsplit

from trippy.catalog.normalize import normalize_text
from .coverage import private_write
from .extraction import fingerprint


GENERIC_NAMES = {'barcelona', 'cafe', 'cafes', 'coffee', 'bar', 'club', 'clubs',
                 'restaurant', 'restaurante', 'sala', 'museum', 'museu', 'de', 'del', 'la', 'el'}
STREET_WORDS = {'carrer', 'calle', 'c', 'avinguda', 'avenida', 'av', 'de', 'del',
                'd', 'els', 'les', 'la', 'el', 'l', 'barcelona'}


def host(url):
    return (urlsplit(url or '').hostname or '').lower().removeprefix('www.')


def address_key(value):
    """Limited diagnostic key; multiple entrances/ranges are not disambiguated."""
    text = normalize_text(value or '')
    if not text or ';' in (value or '') or re.search(r'\d\s*[–-]\s*\d|\bs/n\b', value or ''):
        return None
    words = [w for w in text.split() if w not in STREET_WORDS and not re.fullmatch(r'\d{5}', w)]
    # A civic number and street name are both required, not just a postcode.
    if not any(w.isdigit() for w in words) or not any(not w.isdigit() for w in words):
        return None
    return ' '.join(words)


def name_words(value):
    return set(normalize_text(value).split()) - GENERIC_NAMES


def read_inventory(path, city_id, version_id):
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        version = db.execute('SELECT * FROM catalog_versions WHERE id=? AND geography_id=?',
                             (version_id, city_id)).fetchone()
        if version is None:
            raise ValueError('Explicit catalog version must belong to requested geography')
        rows = [dict(r) for r in db.execute('SELECT * FROM catalog_snapshots WHERE catalog_version_id=? ORDER BY entity_id',
                                           (version_id,))]
    return rows, dict(version)


def propose(observations, rows, *, limit=12):
    if limit < 1:
        raise ValueError('Positive review limit required')
    index = defaultdict(set)
    for i, row in enumerate(rows):
        for word in name_words(row['search_text']):
            index[('word', word)].add(i)
        if host(row.get('website_url')):
            index[('host', host(row['website_url']))].add(i)
    groups = []
    for observation in observations:
        words = name_words(observation['name'])
        website_host = host(observation['source_url'])
        addresses = [f['value'] for f in observation['facts'] if f['field'] == 'address']
        address = address_key(addresses[0]) if len(addresses) == 1 else None
        indexes = set(index.get(('host', website_host), set()))
        for word in words:
            indexes.update(index.get(('word', word), set()))
        candidates = []
        for i in sorted(indexes):
            row = rows[i]
            candidate_words = name_words(row['search_text'])
            overlap = len(words & candidate_words) / max(1, len(words | candidate_words))
            host_equal = bool(website_host and website_host == host(row.get('website_url')))
            if not host_equal and overlap < .5:
                continue
            candidate_address = address_key(row.get('address'))
            address_comparison = ('equal_diagnostic_key' if address == candidate_address else 'conflict_requires_review') \
                if address and candidate_address else 'insufficient_or_scoped_address'
            blockers = ['identity_not_approved', 'coordinate_entrance_not_verified']
            if address_comparison != 'equal_diagnostic_key':
                blockers.append(address_comparison)
            if row.get('operating_status') in {'permanently_closed', 'temporarily_closed'}:
                blockers.append('source_reports_closure')
            if row.get('identity_status') == 'review_needed':
                blockers.append('catalog_identity_conflict')
            candidates.append({'entity_id': row['entity_id'], 'catalog_version_id': row['catalog_version_id'],
                'snapshot_sha256': fingerprint(row), 'name': row['name'], 'address': row.get('address'),
                'website_url': row.get('website_url'), 'family': row['family'],
                'latitude': row['latitude'], 'longitude': row['longitude'],
                'operating_status': row.get('operating_status'),
                'signals': {'official_page_host_equals_catalog_website': host_equal,
                    'name_token_overlap_diagnostic': round(overlap, 4),
                    'address_comparison': address_comparison}, 'blockers': blockers,
                'status': 'proposal_only_not_canonical'})
        candidates.sort(key=lambda c: (
            c['signals']['address_comparison'] != 'equal_diagnostic_key',
            not c['signals']['official_page_host_equals_catalog_website'],
            -c['signals']['name_token_overlap_diagnostic'], c['entity_id']))
        groups.append({'observation_id': observation['id'], 'observation_sha256': fingerprint(observation),
            'name': observation['name'], 'source_url': observation['source_url'],
            'source_addresses': addresses, 'source_branch': observation.get('branch'),
            'source_fit_limit': observation.get('fit_limit'),
            'candidate_count_before_limit': len(candidates), 'candidates_truncated': len(candidates) > limit,
            'candidates': candidates[:limit],
            'status': 'review_required' if candidates else 'no_catalog_candidate_detected',
            'scope_instruction': 'Check branch, venue versus programme/subvenue, family, entrances and source conflicts; no name-only merge'})
    return groups


def run_review(cycle_folder, catalog, city_id, version_id, *, limit=12):
    cycle_folder = Path(cycle_folder)
    observations = json.loads((cycle_folder / 'external-observations.json').read_text())
    cycle = json.loads((cycle_folder / 'summary.json').read_text())
    rows, version = read_inventory(catalog, city_id, version_id)
    spec = {'engine_sha256': fingerprint(Path(__file__).read_text()), 'curation_run_id': cycle['run_id'],
            'observations_sha256': fingerprint(observations), 'catalog_version': version,
            'catalog_snapshots_sha256': fingerprint(rows), 'candidate_limit': limit}
    review_id = fingerprint(spec)
    groups = propose(observations, rows, limit=limit)
    summary = {'review_id': review_id, 'observations': len(observations), 'catalog_snapshots_examined': len(rows),
        'observations_with_candidates': sum(bool(g['candidates']) for g in groups),
        'observations_without_detected_candidate': sum(not g['candidates'] for g in groups),
        'observations_with_address_conflict': sum(any(c['signals']['address_comparison'] == 'conflict_requires_review'
            for c in g['candidates']) for g in groups),
        'truncated_groups': sum(g['candidates_truncated'] for g in groups),
        'approved_canonical_links': 0, 'model_api_calls': 0, 'catalog_writes': 0,
        'limitation': 'Lexical proposals are neither exhaustive matches nor independent factual verification'}
    document = {'manifest': spec, 'summary': summary, 'groups': groups}
    output = cycle_folder / ('identity-review-' + review_id[:16] + '.json')
    if output.exists():
        if json.loads(output.read_text()) != document:
            raise ValueError('Immutable identity review differs')
    else:
        private_write(output, document)
    return output, summary


def review_source_links(document, decisions):
    """Content-bound editorial links; never promote coordinates or venue facts."""
    groups = {g['observation_id']: g for g in document['groups']}
    events = []; seen = set(); linked = set()
    for decision in decisions:
        if decision.get('review_method') != 'agent_source_catalog_comparison' or not decision.get('reason'):
            raise ValueError('Explicit source/catalog review and rationale required')
        group = groups.get(decision['observation_id'])
        if group is None or group['observation_sha256'] != decision['observation_sha256']:
            raise ValueError('Stale source observation decision')
        matches = [c for c in group['candidates'] if fingerprint(c) == decision['candidate_sha256']]
        if len(matches) != 1:
            raise ValueError('Stale candidate decision')
        candidate = matches[0]; key = (group['observation_id'], candidate['entity_id'])
        if key in seen:
            raise ValueError('Duplicate candidate decision')
        seen.add(key)
        if decision['action'] == 'link_source_identity':
            signals = candidate['signals']
            if not signals['official_page_host_equals_catalog_website'] or signals['address_comparison'] != 'equal_diagnostic_key':
                raise ValueError('Source link needs reviewed official website and branch address agreement')
            if decision.get('expected_family') != candidate['family']:
                raise ValueError('Explicit semantic family comparison required')
            if group['observation_id'] in linked:
                raise ValueError('Multiple candidate identities cannot be approved for one branch observation')
            if any(b in candidate['blockers'] for b in ('source_reports_closure', 'catalog_identity_conflict')):
                raise ValueError('Resolve source closure/identity conflict before linking')
            linked.add(group['observation_id'])
            status = 'source_identity_link_reviewed_coordinate_and_fields_pending'
        elif decision['action'] == 'reject_candidate':
            status = 'candidate_rejected_for_this_observation_only'
        else:
            raise ValueError('Unsupported identity decision')
        events.append({'decision': decision, 'source_observation_sha256': group['observation_sha256'],
            'candidate': candidate, 'status': status,
            'approval_scope': 'Source-to-catalog identity only; not transcript aliases, coordinates, current facts, fit or publication'})
    return {'upstream_review_id': document['summary']['review_id'], 'events': events,
        'summary': {'reviewed_source_links': len(linked), 'rejected_observation_candidate_pairs': sum(
            e['decision']['action'] == 'reject_candidate' for e in events),
            'approved_canonical_places': 0, 'ready_to_publish': False, 'model_api_calls': 0, 'catalog_writes': 0}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cycle', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--city-id', required=True)
    parser.add_argument('--version-id', required=True)
    parser.add_argument('--limit', type=int, default=12)
    args = parser.parse_args()
    output, summary = run_review(args.cycle, args.catalog, args.city_id, args.version_id, limit=args.limit)
    print(json.dumps({'output': str(output), 'summary': summary}, indent=2))


if __name__ == '__main__':
    main()
