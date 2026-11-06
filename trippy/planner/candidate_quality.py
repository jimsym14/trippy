"""Deterministic suitability prior for broad-inventory (Overture) catalog rows.

The catalog stores identity and coordinates, not popularity or ratings, so
this score only answers "is this a plausible traveller choice for the
requested category?".  It never becomes a rating, price, opening fact or
recommendation claim, and it is not shown to users as one.

Inputs are fields that the catalog actually stores: source category,
Overture confidence, number of contributing datasets, presence of a website
and distance from the city's evidence-weighted core.
"""
import json
import math

# Which catalog families (and, optionally, which source categories inside
# them) can fill each planner category.  None means "all categories".
FAMILY_SCOPE = {
    'attraction': {'sights': None, 'outdoors': None},
    'museum': {'sights': None},
    'nature': {'outdoors': None},
    'excursion': {'outdoors': None, 'sights': None},
    'food': {'food': None, 'nightlife': {'tapas_bar', 'wine_bar'}},
    'coffee': {'coffee': None},
    'bar': {'nightlife': None},
    'club': {'nightlife': None},
    'shopping': {'shopping': None},
}

# Weights are 0..1. Missing categories use DEFAULT_WEIGHT; EXCLUDED rows are
# never offered for that planner category (they remain in the catalog).
WEIGHTS = {
    'attraction': {
        # Notable places from the free city layer (Wikidata/Wikivoyage).
        'landmark': 1.0, 'activity': 0.4,
        # Overture 'monument' is mostly statues and plaques; landmarks usually
        # arrive through creator endorsements instead.
        'monument': 0.5, 'palace': 0.95, 'castle': 0.9, 'museum': 0.9, 'art_museum': 0.9,
        'history_museum': 0.85, 'modern_art_museum': 0.85, 'contemporary_art_museum': 0.8,
        'science_museum': 0.75, 'civilization_museum': 0.7, 'botanical_garden': 0.75,
        'park': 0.7, 'beach': 0.65, 'aquarium': 0.6, 'zoo': 0.55, 'amusement_park': 0.45,
        'national_park': 0.45, 'hiking_trail': 0.35, 'art_gallery': 0.3,
    },
    'museum': {
        'museum': 1.0, 'art_museum': 1.0, 'history_museum': 0.95, 'modern_art_museum': 0.95,
        'contemporary_art_museum': 0.9, 'science_museum': 0.85, 'civilization_museum': 0.8,
        'palace': 0.7, 'castle': 0.6, 'art_gallery': 0.4,
    },
    'nature': {'park': 1.0, 'botanical_garden': 1.0, 'beach': 0.9, 'national_park': 0.8, 'hiking_trail': 0.7},
    'excursion': {'national_park': 1.0, 'hiking_trail': 0.8, 'castle': 0.7, 'monument': 0.6},
    'food': {
        'tapas_bar': 1.0, 'catalan_restaurant': 1.0, 'spanish_restaurant': 0.9, 'seafood_restaurant': 0.85,
        'mediterranean_restaurant': 0.85, 'basque_restaurant': 0.9, 'wine_bar': 0.7, 'restaurant': 0.6,
        'pizza_restaurant': 0.35, 'burger_restaurant': 0.25, 'hot_dog_restaurant': 0.1,
        'chicken_restaurant': 0.15, 'doner_kebab_restaurant': 0.15, 'buffet_restaurant': 0.2,
        'fast_food_restaurant': 0.05,
    },
    'coffee': {'coffee_shop': 1.0, 'coffee_roastery': 1.0, 'cafe': 0.85, 'bakery': 0.65,
               'breakfast_and_brunch_restaurant': 0.8},
    'bar': {'cocktail_bar': 1.0, 'wine_bar': 0.95, 'tapas_bar': 0.8, 'bar': 0.6, 'beer_bar': 0.6,
            'pub': 0.5, 'piano_bar': 0.6, 'beach_bar': 0.6, 'bar_and_grill_restaurant': 0.3,
            'smoothie_juice_bar': 0.05, 'salad_bar': 0.05, 'hookah_bar': 0.2},
    'club': {'bar': 0.4, 'cocktail_bar': 0.5},
    'shopping': {'shopping': 0.5, 'gift_shop': 0.7, 'antique_store': 0.7, 'second_hand_store': 0.6,
                 'arts_crafts_and_hobby_store': 0.6, 'craft_store': 0.6, 'food_and_beverage_store': 0.6},
}
DEFAULT_WEIGHT = {'attraction': 0.2, 'museum': 0.3, 'nature': 0.4, 'excursion': 0.2, 'food': 0.55,
                  'coffee': 0.5, 'bar': 0.4, 'club': 0.3, 'shopping': 0.25}
EXCLUDED = {
    # Theatres need a dated performance; they belong to events, not sightseeing.
    'attraction': {'theatre_venue', 'movie_theater', 'drive_in_theater', 'home_theater_systems_stores', 'petting_zoo',
                   'dog_park', 'skate_park', 'rv_park', 'beach_volleyball_club', 'beach_equipment_rental'},
    'museum': {'movie_theater', 'drive_in_theater', 'home_theater_systems_stores', 'theatre_venue'},
    'nature': {'dog_park', 'skate_park', 'rv_park', 'beach_volleyball_club', 'beach_equipment_rental'},
    'food': {'restaurant_equipment_and_supply'},
    'coffee': {'coffee_and_tea_supplies', 'internet_cafe'},
    'bar': {'bar_tabac'},
    'shopping': {'grocery_store', 'mobile_phone_store', 'eyewear_store', 'electronics_store',
                 'building_supply_store', 'home_improvement_store', 'computer_store', 'mattress_store',
                 'pet_store', 'convenience_store', 'butcher_shop', 'beauty_supply_store',
                 'camera_and_photography_store', 'bike_store', 'produce_store', 'liquor_store'},
}
# Unendorsed broad-inventory rows below this Overture confidence are too
# likely to be duplicates, closed or mislabelled to schedule.
MIN_CONFIDENCE = 0.6


def category_weight(category, family, source_category):
    scope = FAMILY_SCOPE.get(category, {'sights': None})
    if family not in scope: return None
    allowed = scope[family]
    if allowed is not None and source_category not in allowed: return None
    if source_category in EXCLUDED.get(category, ()): return None
    return WEIGHTS.get(category, {}).get(source_category, DEFAULT_WEIGHT.get(category, 0.3))


def distance_km(lat1, lon1, lat2, lon2):
    r = math.pi / 180
    a = (math.sin((lat2 - lat1) * r / 2) ** 2
         + math.cos(lat1 * r) * math.cos(lat2 * r) * math.sin((lon2 - lon1) * r / 2) ** 2)
    return 6371 * 2 * math.asin(min(1, math.sqrt(a)))


def dataset_count(source_properties):
    try:
        sources = json.loads(source_properties or '{}').get('sources') or []
    except (TypeError, ValueError):
        return 1
    return len({s.get('dataset') for s in sources if isinstance(s, dict)}) or 1


def inventory_score(row, category, core=None, endorsement=0.0):
    """Return a 0..100 score, or None when the row is unsuitable for the category.

    ``row`` needs family, source_category, confidence, latitude, longitude,
    website_url and source_properties.  ``core`` is an optional (lat, lon)
    derived from endorsed source venues; ``endorsement`` is the source-pack
    endorsement strength (see endorsements.py).
    """
    weight = category_weight(category, row['family'], row['source_category'])
    if weight is None: return None
    confidence = float(row['confidence'] or 0)
    if endorsement <= 0 and confidence < MIN_CONFIDENCE: return None
    centrality = 1.0
    if core is not None:
        km = distance_km(core[0], core[1], float(row['latitude']), float(row['longitude']))
        # Full credit within 2.5 km of the evidence core, none beyond 8 km.
        centrality = max(0.0, min(1.0, (8 - km) / 5.5))
    datasets = max(0, min(2, dataset_count(row['source_properties']) - 1))
    base = 50 * weight + 15 * confidence + 5 * datasets + 5 * bool(row["website_url"]) + 20 * centrality
    # Creator endorsements dominate the inventory prior but are bounded so a
    # single noisy mention cannot outweigh every other signal.
    return round(min(100.0, base * 0.6 + min(endorsement, 5.0) * 10), 2)


# Catalog source categories that establish a theme by themselves.
CATEGORY_THEMES = {
    'tapas': {'tapas_bar'}, 'seafood': {'seafood_restaurant'}, 'wine': {'wine_bar'},
    'cocktails': {'cocktail_bar'}, 'beach': {'beach', 'beach_bar'}, 'park': {'park', 'botanical_garden'},
    'art': {'art_museum', 'modern_art_museum', 'contemporary_art_museum', 'art_gallery'},
    'coffee': {'coffee_shop', 'coffee_roastery'},
}
# Themes that a venue's own name can establish ("Mercat de ...", "Bodega ...").
# Others (e.g. "gaudi") need creator evidence: shops called "Gaudí" are not Gaudí.
NAME_THEMES = {'market', 'vermouth', 'viewpoint', 'tapas'}
THEME_BOOST = 12
MAX_THEME_BOOSTS = 2


def row_themes(row, endorsement=None):
    from .search_intent import themes_in
    found = {t for t, cats in CATEGORY_THEMES.items() if row['source_category'] in cats}
    found |= set(themes_in(row['name'])) & NAME_THEMES
    if endorsement:
        found |= set(endorsement.get('themes', []))
    return found


def theme_boost(matched):
    return THEME_BOOST * min(len(matched), MAX_THEME_BOOSTS)
