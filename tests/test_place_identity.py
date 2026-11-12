"""One place, one stop: the duplicates seen in a real Barcelona plan (Casa Milà three times on one day,
La Boqueria six times, Sagrada Familia seven times), and the near-misses that must stay apart."""
from trippy.planner.personal_pipeline import one_sight_once
from trippy.planner.place_identity import merge_same_places, name_relation, same_place, words


def place(pid, name, lat, lon, category='attraction', *, tags=(), nodes=(), priority=0, sources=None):
    return {'id': pid, 'name': name, 'category': category, 'coordinates': {'latitude': lat, 'longitude': lon},
            'tags': list(tags), 'library_node_ids': list(nodes), 'personal_priority': priority,
            'source_ids': sources or ['source-' + pid], 'description': '', 'why_recommended': '', 'official_url': None, 'address': None}


CITY = 'Barcelona'


def test_words_fold_accents_greek_articles_plurals_and_the_city():
    assert words('Κάζα Μιλά') == ['caza', 'mila'] and name_relation('Κάζα Μιλά', 'Casa Milà') == 'same'
    assert words('Casa Milà') == ['casa', 'mila']
    assert words('Magic Montjuïc fountains') == ['magic', 'montjuic', 'fountain']
    assert words('Barcelona Cathedral', CITY) == ['cathedral']
    assert words('Montjuïc') == ['montjuic']          # Greek sound rules never touch Latin names


def test_name_relations():
    assert name_relation('Park Güell', 'Park Guell') == 'same'
    assert name_relation('Gran Teatre del Liceu', 'Teatre de Liceu') == 'generic'
    assert name_relation('Mercat de la Boqueria', 'La Boqueria') == 'generic'
    assert name_relation('Quim de la Boqueria', 'La Boqueria') == 'shared'      # a stall in the market, not the market
    assert name_relation('Picasso Museum', 'Moco Museum Barcelona', CITY) == 'shared_generic'


def test_same_place_rules():
    casa = place('a', 'Casa Milà', 41.39528, 2.16167, priority=100)
    greek = place('b', 'Κάζα Μιλά', 41.39540, 2.16176, tags=['wd:Q207870'])
    assert same_place(casa, greek, CITY)
    liceu = place('c', 'Gran Teatre del Liceu', 41.38028, 2.17361, tags=['wd:Q1130050'])
    video = place('d', 'Teatre de Liceu', 41.37614, 2.17089)                        # 513 m off: a creator's rough pin
    assert same_place(liceu, video, CITY)
    rambla_food = place('e', 'la Rambla', 41.38271, 2.17182, 'food')
    rambla = place('f', 'La Rambla', 41.38139, 2.17306)
    assert same_place(rambla_food, rambla, CITY)                                     # a street, 179 m between pins
    # Must stay apart:
    market = place('g', 'La Boqueria', 41.38174, 2.17155, 'food')
    quim = place('h', 'Quim de la Boqueria', 41.38167, 2.17140, 'food')
    assert not same_place(market, quim, CITY)
    hill = place('i', 'Montjuïc', 41.36800, 2.15500)
    palace = place('j', 'Montjuïc National Palace', 41.36850, 2.15340, 'museum')
    assert not same_place(hill, palace, CITY)
    picasso = place('k', 'Picasso Museum', 41.38520, 2.18080, 'museum')
    moco = place('l', 'Moco Museum Barcelona', 41.38490, 2.18130, 'museum')
    assert not same_place(picasso, moco, CITY)                                        # 52 m, only "museum" in common
    branch_a = place('m', 'Cerveceria Catalana', 41.39160, 2.16210, 'food')
    branch_b = place('n', 'Cerveceria Catalana', 41.39400, 2.16450, 'food')
    assert not same_place(branch_a, branch_b, CITY)                                  # two branches, 330 m apart
    assert not same_place(place('o', 'Cathedral', 41.38393, 2.17655, tags=['wd:Q1']),
                          place('p', 'Cathedral', 41.38393, 2.17655, tags=['wd:Q2']), CITY)


def test_merge_keeps_one_record_with_everyones_sources_links_and_the_common_name():
    places = [
        place('lead', 'Basilica and Expiatory Church of the Holy Family', 41.40369, 2.17433, tags=['wd:Q48435'], priority=100),
        place('s1', 'Sagrada Familia', 41.40351, 2.17443),
        place('s2', 'Sagrada Família', 41.40351, 2.17443, nodes=['community:youtube:yflDZCE2nNA']),
        place('s3', 'Sagrada Familia', 41.40351, 2.17443, nodes=['community:youtube:QFCYJYJ0ECk']),
        place('pal', 'Basilica of the Sagrada Familia', 41.40360, 2.17440, 'museum'),
        place('pau', 'Hospital de Sant Pau', 41.41140, 2.17470),
    ]
    doc = {'places': places, 'place_graph': {'links': [{'node_id': 'community:youtube:QFCYJYJ0ECk', 'place_id': 's3'}]}}
    out = merge_same_places(doc, CITY, rank=lambda p: (-p['personal_priority'], p['id']))
    assert sorted(p['id'] for p in out['places']) == ['lead', 'pau']
    lead = next(p for p in out['places'] if p['id'] == 'lead')
    assert lead['name'] == 'Sagrada Familia'
    assert lead['personal_priority'] == 100
    assert set(lead['library_node_ids']) == {'community:youtube:yflDZCE2nNA', 'community:youtube:QFCYJYJ0ECk'}
    assert {'source-s1', 'source-s2', 'source-s3', 'source-pal'} <= set(lead['source_ids'])
    # The phone's "videos say" lines follow the link to the place that stayed.
    assert out['place_graph']['links'][0]['place_id'] == 'lead'
    assert out['merged_place_ids']['s3'] == 'lead'


def test_casa_mila_three_names_meet_through_the_long_one():
    places = [place('a', 'Casa Milà', 41.39528, 2.16167, priority=100),
              place('b', 'Casa Mila', 41.39540, 2.16176, nodes=['community:youtube:BLT8sL9DVsM'], priority=10),
              place('c', 'Κάζα Μιλά', 41.39540, 2.16176, tags=['wd:Q207870'], priority=10),
              place('d', 'La Pedrera', 41.39540, 2.16176, priority=10),
              place('e', 'La Pedrera - Casa Milà', 41.39525, 2.16182, 'museum')]
    doc = one_sight_once({'places': places, 'trip_context': {'destination': CITY}})
    assert len(doc['places']) == 1
    assert doc['places'][0]['personal_priority'] == 100
