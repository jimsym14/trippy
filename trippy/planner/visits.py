"""How long a visit takes, and which sights are really one visit.

Durations come from what a place *is* (its name and kind), not from the
category a traveller filed it under: the Colosseum picked under "museums" is
still a 90-minute visit and Circus Maximus a 20-minute look at a field.

Wikidata says which sights belong together ("part of" / "located in"): the
Sistine Chapel is part of the Apostolic Palace, the Arch of Constantine of the
Colosseum's archaeological park, Trajan's Column stands in Trajan's Forum. The
planner schedules such a group as one stop led by its strongest member.
Everything here is pure and deterministic.
"""
from __future__ import annotations

import math

# (keywords, minutes), first match wins. Keywords are matched on the casefolded name.
GLANCE = ('fontana', 'fountain', 'fuente', 'font ', 'obelisk', 'obelisco', 'column', 'colonna', 'columna', 'statue', 'statua',
          'arch of', 'arco di', 'arc de', 'keyhole', 'buco della', 'steps', 'scalinata', 'escalinata', 'gate', 'porta ', 'portal',
          'walls', 'mura ', 'muralla', 'bridge', 'ponte ', 'pont ', 'puente', 'monument to', 'memorial', 'circus', 'circo ')
SQUARE = ('piazza', 'square', 'plaza', 'plaça', 'place ', 'platz', 'largo ', 'campo de', 'rambla', 'boulevard', 'avenue',
          'street', 'via ', 'calle', 'carrer', 'viewpoint', 'belvedere', 'mirador', 'lookout', 'terrace', 'terrazza')
CHURCH = ('basilica', 'basílica', 'church', 'chiesa', 'iglesia', 'église', 'cathedral', 'cattedrale', 'catedral', 'duomo',
          'chapel', 'cappella', 'capilla', 'parròquia', 'santa ', 'san ', 'santo ', 'saint ', 'st. ', 'sant ', 'temple', 'mosque',
          'synagogue', 'monastery', 'abbey')
RUINS = ('forum', 'foro ', 'palatine', 'palatino', 'colosseum', 'colosseo', 'amphitheatre', 'amphitheater', 'anfiteatro',
         'acropolis', 'agora', 'ruins', 'archaeological', 'baths of', 'terme di', 'catacomb', 'necropolis')
BIG_MUSEUM = ('museums', 'musei', 'museos', 'louvre', 'prado', 'uffizi', 'hermitage', 'british museum', 'rijksmuseum',
              'metropolitan', 'galleria borghese', 'vatican museum')
CASTLE = ('castle', 'castel', 'castillo', 'castell', 'fortress', 'fortezza', 'citadel', 'alcázar', 'alcazar', 'palace', 'palazzo',
          'palau', 'palacio', 'palais', 'villa ', 'casa ', 'tower', 'torre ')
MUSEUM = ('museum', 'museu ', 'museo', 'musée', 'musee', 'gallery', 'galleria', 'galería', 'pinacoteca', 'kunsthalle',
          'fundació', 'fundación', 'foundation', 'aquarium', 'aquàrium', 'acuario')
PARK = ('park', 'parco', 'parque', 'garden', 'giardin', 'jardí', 'jardin', 'botanic', 'zoo', 'beach', 'spiaggia', 'playa', 'platja')


def fame(place):
    return max([int(t.split(':', 1)[1]) for t in place.get('tags', []) if t.startswith('notable:') and t.split(':', 1)[1].isdigit()] or [0])


def minutes(place):
    """Sourced duration, else a sensible estimate by kind."""
    if place.get('average_visit_minutes'): return place['average_visit_minutes']
    name = f" {(place.get('name') or '').casefold()} "
    category = place.get('category')
    if category in {'food', 'coffee', 'bar', 'club', 'excursion', 'shopping'}:
        return {'food': 75, 'coffee': 30, 'bar': 75, 'club': 120, 'excursion': 300, 'shopping': 60}[category]
    famous = fame(place)
    if any(w in name for w in BIG_MUSEUM): return 150 if famous >= 60 else 120
    if any(w in name for w in RUINS): return 90
    if any(w in name for w in SQUARE): return 20
    if any(w in name for w in CHURCH): return 50 if famous >= 100 else 30
    if any(w in name for w in GLANCE): return 15
    if any(w in name for w in MUSEUM): return 105 if famous >= 60 else 90
    if any(w in name for w in PARK): return 60
    if any(w in name for w in CASTLE): return 75 if category == 'museum' or famous >= 40 else 45
    if category == 'museum': return 90
    if category == 'nature': return 60
    return 45


def quick(place):
    """A stop that fits between the main ones (a fountain, a square, a small church)."""
    return minutes(place) <= 30


def wikidata_links(place):
    """(own qid, qids of the wholes it belongs to)."""
    own, wholes = None, set()
    for tag in place.get('tags', []):
        if tag.startswith('wd:'): own = tag[3:]
        elif tag.startswith('within:'): wholes.add(tag[7:])
    return own, wholes


def _metres(a, b):
    ca, cb = a['coordinates'], b['coordinates']
    dy = (ca['latitude'] - cb['latitude']) * 111_320
    dx = (ca['longitude'] - cb['longitude']) * 111_320 * math.cos(math.radians(ca['latitude']))
    return math.hypot(dx, dy)


GROUP_METRES = 700


def groups(places, strength):
    """{lead id: [member ids]} for sights that Wikidata links and that stand together.

    Two places join when one is part of the other, or both are part of the same
    whole, and they are within ~700 m (so "part of the seven hills of Rome" never
    joins anything across town). The strongest member leads the visit.
    """
    visits = [p for p in places if p.get('category') in {'attraction', 'museum', 'nature'}]
    links = {p['id']: wikidata_links(p) for p in visits}
    parent = {p['id']: p['id'] for p in visits}

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i

    for i, a in enumerate(visits):
        own_a, wholes_a = links[a['id']]
        for b in visits[i + 1:]:
            own_b, wholes_b = links[b['id']]
            linked = (own_a and own_a in wholes_b) or (own_b and own_b in wholes_a) or (wholes_a & wholes_b)
            if linked and _metres(a, b) < GROUP_METRES:
                parent[root(a['id'])] = root(b['id'])
    # A great museum takes in the chapels and rooms inside it (the Vatican Museums
    # and the Sistine Chapel), which Wikidata files under the palace instead.
    for museum in visits:
        if not any(w in f" {museum['name'].casefold()} " for w in BIG_MUSEUM): continue
        for p in visits:
            name = f" {p['name'].casefold()} "
            if p is not museum and any(w in name for w in INSIDE) and _metres(museum, p) < 500:
                parent[root(p['id'])] = root(museum['id'])
    members = {}
    for p in visits: members.setdefault(root(p['id']), []).append(p)
    result = {}
    for group in members.values():
        if len(group) < 2: continue
        # The longest visit leads (the Vatican Museums, not the chapel inside them).
        group.sort(key=lambda p: (-minutes(p), -strength(p), p['id']))
        result[group[0]['id']] = [p['id'] for p in group[1:]]
    return result


INSIDE = ('chapel', 'cappella', 'capilla', 'chapelle', 'rooms', 'stanze', 'salas', 'gallery of', 'galleria degli')


def group_minutes(lead, members):
    """The lead's own visit, plus a shorter look at each linked sight, to the quarter hour."""
    extra = sum(max(10, minutes(m) // 2) for m in members)
    return min(300, int(math.ceil((minutes(lead) + extra) / 15) * 15))


def closes_by(place, month):
    """Latest end (minutes) for a visit when its hours are unknown.

    Open-air sites (ruins, parks) close around dusk, early in winter; museums and
    palaces by early evening. Churches, squares and fountains stay open, so the
    late afternoon goes to them, as in a real day.
    """
    name = f" {(place.get('name') or '').casefold()} "
    winter = month in (11, 12, 1, 2)
    shoulder = month in (3, 10)
    if any(w in name for w in RUINS) or any(w in name for w in PARK):
        return 990 if winter else 1080 if shoulder else 1170
    if any(w in name for w in GLANCE) or any(w in name for w in SQUARE) or any(w in name for w in CHURCH):
        return 1380
    if place.get('category') == 'museum' or any(w in name for w in BIG_MUSEUM + MUSEUM + CASTLE):
        return 1110
    return 1380
