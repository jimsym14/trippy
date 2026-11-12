"""Is this the same place? Deterministic, no model and no lookup.

Plans gather one place from many sources: the city lookup, guides, the traveller's pins and every creator who
named it ("Casa Mila", "Κάζα Μιλά", "La Pedrera - Casa Milà"). Each arrives with its own name and coordinates,
so without this step one sight is scheduled two or three times. The rules here:

- the same Wikidata item (within 2 km) is the same place;
- the same name (accents, Greek script, articles, plurals and the city's name aside) is the same place: food and drink
  only when it is in the same spot (80 m, as branches share names); anything else within 700 m (Montjuïc is a hill,
  La Rambla a street);
- a name that is the other plus only generic words ("Gran Teatre del Liceu", "Mercat de la Boqueria") is the same
  place within 600 m; a name with another distinctive word ("Quim de la Boqueria") is not;
- sights (not food) within 30 m that share a word ("Casa Milà" / "La Pedrera - Casa Milà") are one visit.

Groups are joined transitively, so "La Pedrera" and "Casa Milà" meet through "La Pedrera - Casa Milà".
"""
import re
import unicodedata

from .plan_engine import distance

GREEK = str.maketrans({
    'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i', 'θ': 'th', 'ι': 'i', 'κ': 'c', 'λ': 'l', 'μ': 'm',
    'ν': 'n', 'ξ': 'x', 'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'ς': 's', 'τ': 't', 'υ': 'i', 'φ': 'f', 'χ': 'ch', 'ψ': 'ps', 'ω': 'o',
})
# Greek renders Latin "c"/"k" as κ and the sounds of "s"/"z" loosely: "Κάζα" is "Casa", "Μιλά" is "Mila".
GREEK_PAIRS = (('ntz', 'nz'), ('mp', 'b'), ('nt', 'd'), ('ou', 'u'))

STOP = {'the', 'of', 'and', 'a', 'an', 'la', 'el', 'les', 'los', 'las', 'le', 'lo', 'l', 'de', 'del', 'des', 'du', 'di', 'da',
        'dei', 'della', 'i', 'y', 'e', 'et', 'at', 'in', 'en', 'd', 'to', 'o', 'tou', 'tis', 'ton', 'tin', 'ta', 'to'}
# Words that say what a place is, not which one: they never make two names different, and never alone the same.
GENERIC = {'cathedral', 'catedral', 'church', 'iglesia', 'esglesia', 'chiesa', 'basilica', 'museum', 'museu', 'museo', 'musee',
           'park', 'parc', 'parco', 'parque', 'garden', 'gardens', 'jardi', 'jardin', 'market', 'mercat', 'mercado', 'mercato',
           'square', 'plaza', 'placa', 'piazza', 'place', 'palace', 'palau', 'palacio', 'palazzo', 'theatre', 'theater', 'teatre',
           'teatro', 'gran', 'grand', 'great', 'old', 'new', 'tower', 'torre', 'bridge', 'pont', 'ponte', 'puente', 'castle',
           'castell', 'castillo', 'castello', 'fountain', 'font', 'fuente', 'fontana', 'monument', 'monumento', 'beach', 'platja',
           'playa', 'spiaggia', 'street', 'carrer', 'calle', 'via', 'avenue', 'avinguda', 'national', 'nacional', 'nazionale',
           'royal', 'reial', 'real', 'saint', 'sant', 'santa', 'san', 'st', 'holy', 'santo', 'quarter', 'barri', 'barrio',
           'district', 'hall', 'gallery', 'galeria', 'galleria', 'hospital', 'house', 'casa', 'chapel', 'capella', 'monastery',
           'monestir', 'temple', 'templo', 'tempio', 'magic', 'magica', 'magica', 'view', 'viewpoint', 'mirador'}
# A hill, park or quarter holds buildings: "Montjuïc National Palace" is on Montjuïc, not Montjuïc itself.
BUILDINGS = {'cathedral', 'catedral', 'church', 'iglesia', 'esglesia', 'chiesa', 'basilica', 'museum', 'museu', 'museo', 'musee',
             'palace', 'palau', 'palacio', 'palazzo', 'theatre', 'theater', 'teatre', 'teatro', 'tower', 'torre', 'castle', 'castell',
             'castillo', 'castello', 'fountain', 'font', 'fuente', 'fontana', 'monastery', 'monestir', 'chapel', 'capella', 'temple',
             'templo', 'tempio', 'hall', 'gallery', 'galeria', 'galleria', 'hospital', 'house', 'casa', 'bridge', 'pont', 'ponte',
             'puente', 'monument', 'monumento'}
SIGHTS = {'attraction', 'museum', 'nature', 'shopping', 'excursion', 'other'}
FOOD = {'food', 'coffee', 'bar', 'club', 'nightlife'}


def words(name, city=''):
    """A name as plain words: no accents, Greek written in Latin letters, without articles, plurals or the city's name."""
    text = unicodedata.normalize('NFKD', (name or '').casefold())
    text = ''.join(ch for ch in text if not unicodedata.combining(ch))
    greek = any('\u0370' <= ch <= '\u03ff' for ch in text)
    text = text.translate(GREEK)
    if greek:
        for a, b in GREEK_PAIRS:
            text = text.replace(a, b)
    drop = set(words(city)) if city else set()
    out = []
    for w in re.findall(r'[a-z0-9]+', text):
        if w in STOP or w in drop:
            continue
        if len(w) > 4 and w.endswith('s') and not w.endswith('ss'):
            w = w[:-1]
        out.append(w)
    return out


def _similar(a, b):
    """One word the same, allowing Greek's s for z and c for k, and a letter's slip in longer words ("guell"/"guel")."""
    if a == b:
        return True
    a2, b2 = a.replace('z', 's').replace('k', 'c'), b.replace('z', 's').replace('k', 'c')
    if a2 == b2:
        return True
    if min(len(a), len(b)) >= 6:
        import difflib
        return difflib.SequenceMatcher(None, a2, b2).ratio() >= 0.85
    return False


def _covered(small, big):
    return all(any(_similar(w, v) for v in big) for w in small)


def name_relation(a, b, city=''):
    """'same', 'generic' (one is the other plus only generic words), 'shared' (a distinctive word in common), or None."""
    wa, wb = words(a, city), words(b, city)
    if not wa or not wb:
        return None
    if _covered(wa, wb) and _covered(wb, wa):
        return 'same'
    small, big = (wa, wb) if len(set(wa)) <= len(set(wb)) else (wb, wa)
    if _covered(small, big):
        extra = [w for w in big if not any(_similar(w, s) for s in small)]
        if all(w in GENERIC for w in extra) and any(w not in GENERIC for w in small):
            return 'generic'
    if any(_similar(x, y) for x in wa for y in wb if x not in GENERIC):
        return 'shared'
    if any(x == y for x in wa for y in wb):
        return 'shared_generic'
    return None


def _wikidata(p):
    return {t for t in p.get('tags', []) if t.startswith('wd:')}


def same_place(a, b, city=''):
    if a['coordinates'].get('latitude') is None or b['coordinates'].get('latitude') is None:
        return False
    metres = distance(a, b)
    if _wikidata(a) & _wikidata(b) and metres <= 2000:
        return True
    # Two different Wikidata items are two places, whatever they are called.
    if _wikidata(a) and _wikidata(b):
        return False
    relation = name_relation(a['name'], b['name'], city)
    food_a, food_b = a.get('category') in FOOD, b.get('category') in FOOD
    if relation == 'same':
        return metres <= (80 if food_a and food_b else 700)
    if relation == 'generic':
        # The longer name adds a building to a place that names none ("Montjuïc" / "Montjuïc National Palace"):
        # a sight on the hill, in the park or the quarter, one visit only when it is the same spot.
        wa, wb = words(a['name'], city), words(b['name'], city)
        small, big = (wa, wb) if len(set(wa)) <= len(set(wb)) else (wb, wa)
        if not BUILDINGS & set(small) and BUILDINGS & set(big):
            return not food_a and not food_b and metres <= 30
        return metres <= (80 if food_a or food_b else 600)
    if relation in {'shared', 'shared_generic'}:
        return not food_a and not food_b and metres <= 30
    return False


def merge_same_places(doc, city='', rank=None):
    """Keep one record per place; the best-identified one (``rank``, lowest first) keeps the others' sources and links."""
    rank = rank or (lambda p: p['id'])
    places = sorted(doc['places'], key=rank)
    parent = list(range(len(places)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(places)):
        for j in range(i + 1, len(places)):
            if root(i) != root(j) and same_place(places[i], places[j], city):
                # The earlier (better) record leads the group.
                a, b = sorted((root(i), root(j)))
                parent[b] = a
    groups = {}
    for i in range(len(places)):
        groups.setdefault(root(i), []).append(places[i])
    kept, moved = [], {}
    for lead_index, members in groups.items():
        lead = places[lead_index]
        for other in members:
            if other is lead:
                continue
            moved[other['id']] = lead['id']
            lead['source_ids'] = sorted(set(lead['source_ids']) | set(other['source_ids']))
            lead['library_node_ids'] = sorted(set(lead.get('library_node_ids', [])) | set(other.get('library_node_ids', [])))
            lead['personal_priority'] = max(lead.get('personal_priority', 0) or 0, other.get('personal_priority', 0) or 0)
            lead['tags'] = sorted(set(lead.get('tags', [])) | {t for t in other.get('tags', []) if t.startswith(('wd:', 'notable:'))})
            for field in ('description', 'why_recommended', 'official_url', 'address'):
                if not lead.get(field) and other.get(field):
                    lead[field] = other[field]
        # The name most sources use is the name people know it by ("Sagrada Familia", not "Basilica and Expiatory
        # Church of the Holy Family"); the best-ranked record's spelling of it wins, so its accents stay.
        counts = {}
        for member in members:
            counts.setdefault(' '.join(words(member['name'], city)), []).append(member)
        top = max(counts.values(), key=lambda group: (len(group), lead in group))
        if len(top) >= 2 and lead not in top:
            # The fullest spelling of it ("Barcelona Cathedral", not "Cathedral").
            lead['name'] = max(top, key=lambda m: len(m['name']))['name']
        kept.append(lead)
    doc['places'] = sorted(kept, key=lambda p: p['id'])
    graph = doc.get('place_graph')
    if moved and isinstance(graph, dict):
        graph['links'] = [{**link, 'place_id': moved.get(link.get('place_id'), link.get('place_id'))} for link in graph.get('links', [])]
    if moved:
        doc['merged_place_ids'] = {**doc.get('merged_place_ids', {}), **moved}
    return doc
