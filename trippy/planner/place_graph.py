"""Trip-private library graph. Content supplies intent, never operating facts."""
from copy import deepcopy
from urllib.parse import quote, urlsplit
import math

from .planning_contract import empty_batch
from .plan_engine import digest, key
from research_pipeline import canonical_category

KINDS = {'pin', 'save', 'note', 'video', 'prior_trip', 'idea'}
# 'idea': a save the traveller didn't pick in the setup. It competes for open slots with a capped boost
# (plan_engine.idea_bonus), never forced in; picked saves arrive as must-see pins.
WEIGHTS = {'pin': 100, 'save': 90, 'note': 80, 'video': 60, 'prior_trip': 40, 'idea': 30, 'community': 10}


def weight(node):
    """Community knowledge stays far below the traveller's own library, unless they ticked that video for this trip."""
    return WEIGHTS['video'] - 10 if node['kind'] == 'community' and node.get('picked') else WEIGHTS[node['kind']]


def validate_nodes(records):
    if not isinstance(records, list) or len(records) > 300:
        raise ValueError('Library nodes must be a bounded list')
    nodes = deepcopy(records)
    seen = set()
    for node in nodes:
        if not isinstance(node, dict) or set(node) - {'id', 'kind', 'city', 'text', 'url', 'places', 'include'}:
            raise ValueError('Invalid library node')
        for field, limit in [('id', 200), ('city', 160), ('text', 8000)]:
            if not isinstance(node.get(field, ''), str) or len(node.get(field, '')) > limit:
                raise ValueError('Invalid library node '+field)
        if not node.get('id') or node['id'] in seen or node.get('kind') not in KINDS:
            raise ValueError('Library node requires a unique ID and kind')
        seen.add(node['id'])
        if type(node.get('include', True)) is not bool: raise ValueError('Invalid library inclusion')
        url = node.get('url')
        if url is not None:
            if not isinstance(url, str) or len(url) > 2000: raise ValueError('Invalid library URL')
            parsed = urlsplit(url)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError('Library URL requires public HTTPS')
        places = node.get('places', [])
        if not isinstance(places, list) or len(places) > 100: raise ValueError('Invalid library places')
        for p in places:
            if not isinstance(p, dict) or set(p) - {'id', 'name', 'address', 'category', 'latitude', 'longitude', 'provider_id', 'selected'}:
                raise ValueError('Invalid linked place')
            for field, limit in [('id', 200), ('name', 200), ('address', 500), ('category', 200), ('provider_id', 200)]:
                if p.get(field) is not None and (not isinstance(p[field], str) or len(p[field]) > limit):
                    raise ValueError('Invalid linked place '+field)
            if not p.get('name'): raise ValueError('Linked place needs a name')
            if type(p.get('selected', False)) is not bool: raise ValueError('Invalid selected place')
            lat, lon = p.get('latitude'), p.get('longitude')
            if (lat is None) != (lon is None): raise ValueError('Incomplete library coordinates')
            if lat is not None and (type(lat) not in (int, float) or type(lon) not in (int, float)
                    or not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180):
                raise ValueError('Invalid library coordinates')
    return nodes


def library_graph(brief, community_nodes=()):
    """Shared records are injected by server retrieval, never trusted from a client."""
    city = key(brief['destination'])
    nodes = [n for n in brief.get('library_nodes', []) if n.get('include', True) and key(n.get('city', '')) == city]
    nodes += [{**deepcopy(n), 'kind': 'community'} for n in community_nodes
              if n.get('published') is True and key(n.get('city', '')) == city]
    nodes.sort(key=lambda n: (-weight(n), n['id']))
    places, links = {}, []
    for node in nodes:
        for occurrence in node.get('places', []):
            p = deepcopy(occurrence)
            p['category'] = canonical_category(p.get('category') or 'other')
            # Provider branch identity is preferred. Name alone never merges shops.
            identity = ['google', p['provider_id']] if p.get('provider_id') else [city, key(p['name']), key(p.get('address') or ''),
                None if p.get('address') else [p.get('latitude'), p.get('longitude'), p.get('id') or node['id']]]
            pid = 'place-'+digest(identity)[:20]
            selected = p.get('selected', False) and p.get('latitude') is not None
            if pid not in places:
                places[pid] = {**p, 'id': pid, 'selected': selected, 'priority': weight(node), 'node_ids': []}
            elif selected and not places[pid]['selected']:
                places[pid].update(p, id=pid, selected=True)
            places[pid]['node_ids'].append(node['id'])
            links.append({'node_id': node['id'], 'place_id': pid, 'kind': node['kind']})
    return {'version': 'place-graph-v1', 'nodes': nodes, 'places': sorted(places.values(), key=lambda p:p['id']), 'links': links}


def graph_batch(graph):
    batch = empty_batch()
    by_node = {n['id']: n for n in graph['nodes']}
    for node in graph['nodes']:
        batch['sources'].append({'id': node['id'], 'url': node.get('url') or 'https://trippy.app/library/'+quote(node['id'], safe=''),
            'publisher': 'Η βιβλιοθήκη σου' if node['kind'] != 'community' else 'Κοινότητα',
            'type': 'personal' if node['kind'] != 'community' else 'creator', 'checked_at': None})
    for p in graph['places']:
        texts = [by_node[n].get('text', '') for n in p['node_ids'] if by_node[n].get('text')]
        batch['places'].append({'id':p['id'], 'name':p['name'], 'category':canonical_category(p.get('category') or 'other'),
            'description':'\n'.join(texts)[:8000], 'why_recommended':'Από τη βιβλιοθήκη σου' if p['priority'] > 10 else 'Από την κοινότητα',
            'address':p.get('address'), 'official_url':None, 'source_ids': sorted(set(p['node_ids'])),
            'coordinates':{'latitude':p.get('latitude') if p['selected'] else None,
                           'longitude':p.get('longitude') if p['selected'] else None,
                           'source_ids': sorted(set(p['node_ids'])) if p['selected'] else []},
            'identity_status':'source_matched' if p['selected'] else 'candidate',
            # Community places rank by how many videos recommend them, so the sight five creators chose
            # comes before one nobody else mentioned. The traveller's own places need no score: they lead anyway.
            'tags':([f"quality:{min(96, 64 + 6 * len(set(p['node_ids'])))}", 'source:community']
                    if all(by_node[n]['kind'] == 'community' for n in p['node_ids'])
                    else ['source:idea'] if all(by_node[n]['kind'] in {'idea', 'community'} for n in p['node_ids']) else []), 'price':{'min':None,'max':None,'currency':None,'basis':'unknown'}, 'price_source_ids':[],
            'cuisine':None,'dietary_options':[],'best_for':[],'best_time':None,'reservation_required':None,
            'image_url':None,'image_source_url':None,'image_attribution':None,
            'rating':{'value':None,'scale':None,'platform':None,'review_count':None},
            'average_visit_minutes':None,'duration_basis':'unknown'})
    return batch


def attach_graph(document, graph):
    """Rebind graph edges after canonical batch merging; keep private content private."""
    by_id = {p['id']:p for p in document['places']}
    bindings = {}
    for original in graph['places']:
        matches = [p for p in by_id.values() if key(p['name']) == key(original['name']) and
                   key(p.get('address') or '') == key(original.get('address') or '')]
        # Unaddressed identical names require the exact coordinate, never first match.
        if not original.get('address'):
            matches = [p for p in matches if p['coordinates']['latitude'] == (original.get('latitude') if original['selected'] else None) and
                       p['coordinates']['longitude'] == (original.get('longitude') if original['selected'] else None)]
        if len(matches) == 1:
            target = matches[0]
            bindings[original['id']] = target['id']
            target['personal_priority'] = max(target.get('personal_priority',0), original['priority'])
            target['library_node_ids'] = sorted(set(target.get('library_node_ids', []) + original['node_ids']))
    document['place_graph'] = {**deepcopy(graph), 'visibility':'private',
        'links':[{**link, 'place_id':bindings.get(link['place_id'],link['place_id'])} for link in graph['links']]}
    return document
