"""Retrieve the selected editorial edition without promoting proposals into facts."""
from collections import Counter
from pathlib import Path
import json
from trippy.sources.extraction import fingerprint
from research_pipeline import canonical_category


def selected_dataset(root, destination, selection=None):
    # The repository's currently selected edition is Barcelona-only.
    if destination.casefold() not in {'barcelona', 'βαρκελώνη', 'βαρκελωνη'}:
        return {'state': 'not_available', 'version': None, 'candidates': [], 'context': [], 'operational': {}, 'coverage': {}}
    selection = Path(selection) if selection else Path(root)/'.local/stage3/planner-release-v1/active-dataset.json'
    if not selection.is_file():
        return {'state': 'not_available', 'version': None, 'candidates': [], 'context': [], 'operational': {}, 'coverage': {}}
    pointer = json.loads(selection.read_text())
    path = Path(pointer['dataset'])
    if not path.is_absolute(): path = Path(root)/path
    bundle = json.loads(path.read_text())
    if pointer.get('bundle_sha256') != fingerprint(bundle): raise ValueError('Selected dataset hash mismatch')
    from trippy.research.dataset_integration import verify_snapshot
    database = Path(pointer['database'])
    if not database.is_absolute(): database = Path(root)/database
    verify_snapshot(database, bundle)
    candidates, context = [], []
    # All retained quotations are available as source context, with editorial state.
    # Only manually admitted annotations become structured fit facets.
    annotations = {}
    for entry in bundle['annotations']:
        if entry.get('source_discovery_eligible') and entry.get('manual_decision') and entry.get('claim_binding_current'):
            annotations.setdefault(entry['current_record_id'], []).append(entry['effective'])
    for record in bundle['normalized']['drafts']:
        row = {'record_id': record['id'], 'name': record['name'], 'kind': record['kind'],
            'source': record['source'], 'published_at': record.get('published_at'),
            'claims': record['claims'], 'identity_uncertain': record['identity_uncertain'],
            'approved_annotations': annotations.get(record['id'], []),
            'categories': record['categories'], 'category_review_pending': record.get('category_review_pending', True),
            'status': 'editorial_source_context_needs_identity_and_current_checks'}
        (candidates if record['kind']=='venue' else context).append(row)
    return {'state': 'loaded_editorial_only', 'version': pointer['bundle_sha256'],
        'candidates': candidates, 'context': context, 'operational': bundle['operational'],
        'identity_links': bundle['identity_links'],
        'coverage': dict(Counter(canonical_category(c) for r in candidates for c in r['categories'])),
        'planner_ready': False}


def task_context(dataset, task, brief, limit=12):
    categories = set(task.get('categories', []))
    words = {x.casefold() for x in brief['preference_tags']+brief['interests']}
    rows = []
    for r in dataset['candidates']:
        category_match = bool(categories & {canonical_category(c) for c in r['categories']})
        exact = any(t in json.dumps(r['approved_annotations'], ensure_ascii=False).casefold() for t in words)
        if not category_match and not exact: continue
        rows.append((0 if exact else 1, r['name'].casefold(), r['record_id'], r))
    # Keep multiple source occurrences; they are evidence, not duplicate physical venues.
    offset = (task.get('page', 1)-1)*limit
    candidates = [r for *_,r in sorted(rows)[offset:offset+limit]]
    # No arbitrary truncation of an admitted quotation. A bounded shortlist chooses
    # full records and keeps the edition available for subsequent gap tasks.
    subjects = {(p.get('name','').casefold().strip(), (p.get('address') or '').casefold().strip())
                for p in task.get('places', [])}
    operational = {}
    if task['kind'] == 'selected_checks':
        for kind in ('structured_fields', 'prose_proposals'):
            operational[kind] = [r for r in dataset.get('operational', {}).get(kind, [])
                if (r.get('subject_name','').casefold().strip(), (r.get('subject_address') or '').casefold().strip()) in subjects]
    source_context = dataset.get('context', []) if task['kind']=='logistics' else []
    return {'dataset_version': dataset['version'], 'candidates': candidates,
            'practical_source_context': source_context[:limit],
            'practical_source_context_available': len(source_context),
            'matching_editorial_occurrences': len(rows), 'editorial_offset': offset,
            'source_context_count': len(dataset['candidates']),
            'held_claims_excluded': True, 'operational_observations': operational,
            'use': 'Discovery context; dated visits and operator proposals do not prove permanent service or current hours.'}


def inventory_context(root, destination, task, limit=16):
    """Read permitted local Overture inventory; never grant recommendation status."""
    import sqlite3
    from contextlib import closing
    path=Path(root)/'.local/catalog.sqlite'
    if not path.is_file(): return {'state':'not_available','items':[],'version':None}
    city='Barcelona' if destination.casefold() in {'barcelona','βαρκελώνη','βαρκελωνη'} else destination
    families={'food':'food','coffee':'coffee','attraction':'sights','museum':'sights','bar':'nightlife',
              'club':'nightlife','nature':'outdoors','excursion':'outdoors','shopping':'shopping'}
    selected={families[c] for c in task.get('categories',[]) if c in families}
    with closing(sqlite3.connect(path.resolve().as_uri()+'?mode=ro',uri=True)) as db:
        db.row_factory=sqlite3.Row
        columns={r[1] for r in db.execute('PRAGMA table_info(catalog_snapshots)')}
        if not columns: return {'state':'not_available','items':[],'version':None}
        query='''SELECT cs.*, sr.url AS source_url, sr.fetched_at, sp.allowed_fields
            FROM catalog_snapshots cs
            JOIN catalog_versions cv ON cv.id=cs.catalog_version_id
            JOIN geographies g ON g.id=cv.geography_id
            JOIN source_records sr ON sr.id=cs.source_id
            JOIN source_policies sp ON sp.id=sr.policy_id
            JOIN entities e ON e.id=cs.entity_id
            WHERE lower(g.name)=lower(?) AND cv.status='published' AND e.publication_status='published'
            AND sr.owner_id IS NULL AND sr.scope_key='shared' AND sr.publication_status='published'
            AND sp.status='permitted' AND sp.can_retain_raw=1 AND sp.can_use_in_prompt=1
            AND (sr.retention_until IS NULL OR julianday(sr.retention_until)>julianday('now'))
            AND (cs.operating_status IS NULL OR cs.operating_status!='permanently_closed')'''
        params=[city]
        if selected:
            query+=' AND cs.family IN ('+','.join('?' for _ in selected)+')';params+=sorted(selected)
        query+=' ORDER BY cs.shortlist_rank IS NULL, cs.shortlist_rank, cs.entity_id LIMIT ? OFFSET ?';params += [limit, (task.get('page',1)-1)*limit]
        rows=[]
        for record in db.execute(query,params):
            record=dict(record); allowed=set(json.loads(record['allowed_fields']))
            if not {'name','coordinates','category'}<=allowed: continue
            row={k:record[k] for k in ['entity_id','catalog_version_id','name','family','latitude','longitude','source_url','fetched_at']}
            row['address']=record['address'] if 'address' in allowed else None
            row['website_url']=record['website_url'] if 'website' in allowed else None
            row['status']='source_inventory_identity_candidate_not_current_or_recommended'
            rows.append(row)
        return {'state':'available' if rows else 'no_permitted_matches','items':rows,
            'version':rows[0]['catalog_version_id'] if rows else None,
            'attribution':'Overture Maps Foundation; source-specific licenses in retained catalog attribution'}
