"""Provider-agnostic SearchIntent: structured interpretation of a natural-language trip request.

The intent refines retrieval only. It never rewrites the validated trip brief,
overrides explicit locked stops, excluded place IDs, budget limits, or
any hard constraint the user has already expressed through the brief schema.

Explicit brief constraints always win over inferred intent signals.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
import re
from typing import Optional

from research_pipeline import canonical_category


# --- limits -------------------------------------------------------------------

MAX_VIBE_TAGS = 20
MAX_CATEGORIES = 15
MAX_EXCLUSION_HINTS = 30
MAX_AREA_HINT_LEN = 200
MAX_WALKING_MINUTES = 120

ALLOWED_TRANSPORT = frozenset({'walking', 'transit', 'driving', 'any'})

# Fields that would let the model slip factual venue details through intent.
_FORBIDDEN_FIELDS = frozenset({
    'coordinates', 'latitude', 'longitude', 'place_id', 'place_ids',
    'address', 'price', 'hours', 'opening_hours', 'rating', 'phone',
    'website', 'url', 'name', 'names',
})


# --- data model ---------------------------------------------------------------

@dataclass
class SearchIntent:
    """Validated interpretation of the user's natural-language request.

    All fields are additive signals for retrieval. None of them override
    brief fields — the brief remains the single source of truth for
    explicit user constraints.
    """
    destination: str

    # Categories inferred from the NL request that go beyond the brief's
    # explicit interests.  These EXPAND retrieval; they never shrink it.
    inferred_categories: list = field(default_factory=list)

    # Soft taste/vibe signals ("romantic", "local", "off the beaten path").
    # Advisory only — not used as hard filters.
    vibe_tags: list = field(default_factory=list)

    # Neighborhood or district the user mentioned; None if absent.
    area_hint: Optional[str] = None

    # Maximum preferred walking time between stops in minutes.
    walking_limit_minutes: Optional[int] = None

    # Transport mode preference expressed in the request.
    transport_preference: Optional[str] = None

    # Advisory exclusion hints (e.g. "no fast food").  These are soft signals.
    # They NEVER override brief.excluded_place_ids.
    exclusion_hints: list = field(default_factory=list)

    # Diagnostics — recorded in pipeline_report; never logged as secrets.
    extraction_path: str = 'fallback'       # 'ai_derived' | 'fallback'
    extraction_model: Optional[str] = None  # provider-supplied model name

    # The original text that was parsed (bounded copy, not sent back to iOS).
    raw_request: Optional[str] = None


# --- JSON schema sent to the model --------------------------------------------

INTENT_SCHEMA = {
    'type': 'object',
    'properties': {
        'inferred_categories': {
            'type': 'array',
            'items': {'type': 'string'},
            'maxItems': MAX_CATEGORIES,
        },
        'vibe_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'maxItems': MAX_VIBE_TAGS,
        },
        'area_hint': {'type': ['string', 'null'], 'maxLength': MAX_AREA_HINT_LEN},
        'walking_limit_minutes': {
            'type': ['integer', 'null'],
            'minimum': 0,
            'maximum': MAX_WALKING_MINUTES,
        },
        'transport_preference': {
            'type': ['string', 'null'],
            'enum': sorted(ALLOWED_TRANSPORT) + [None],
        },
        'exclusion_hints': {
            'type': 'array',
            'items': {'type': 'string'},
            'maxItems': MAX_EXCLUSION_HINTS,
        },
    },
    'required': [
        'inferred_categories', 'vibe_tags', 'area_hint',
        'walking_limit_minutes', 'transport_preference', 'exclusion_hints',
    ],
    'additionalProperties': False,
}

# System prompt sent to the model for structured intent extraction.
INTENT_SYSTEM = (
    'You extract structured travel preferences from a natural-language trip request.\n'
    'Return only fields present in the schema. Do not invent place names, addresses,\n'
    'coordinates, prices, opening hours, ratings, or identifiers. Do not propose an\n'
    'itinerary or select specific venues. Infer categories, vibes, area preferences,\n'
    'and transport from explicit user language only. If a preference is not expressed,\n'
    'return null or an empty list. Preserve uncertainty.\n'
)


# --- validation ---------------------------------------------------------------

def validate_intent(raw: dict, brief: dict, *, model_name: str = None) -> SearchIntent:
    """Validate a model-returned intent dict against the schema.

    Raises ValueError on any violation.  The caller should catch and fall back.

    Explicit brief constraints are enforced here:
    - inferred_categories that map to 'other' (unrecognised) are silently dropped.
    - exclusion_hints are stored as advisory strings only.
    - No field from the intent is written back to the brief.
    """
    if not isinstance(raw, dict):
        raise ValueError('Intent must be a JSON object')

    illegal = set(raw.keys()) & _FORBIDDEN_FIELDS
    if illegal:
        raise ValueError('Intent contains forbidden field(s): ' + ', '.join(sorted(illegal)))

    extra = set(raw.keys()) - set(INTENT_SCHEMA['properties'].keys())
    if extra:
        raise ValueError('Intent contains unknown field(s): ' + ', '.join(sorted(extra)))

    # --- inferred_categories --------------------------------------------------
    raw_cats = raw.get('inferred_categories', [])
    if not isinstance(raw_cats, list) or len(raw_cats) > MAX_CATEGORIES:
        raise ValueError('inferred_categories must be a bounded list')
    canonical_cats = []
    for c in raw_cats:
        if not isinstance(c, str) or len(c) > 200:
            raise ValueError('Each inferred category must be a short string')
        cat = canonical_category(c)
        if cat != 'other':
            canonical_cats.append(cat)

    # --- vibe_tags ------------------------------------------------------------
    vibe_tags = raw.get('vibe_tags', [])
    if not isinstance(vibe_tags, list) or len(vibe_tags) > MAX_VIBE_TAGS:
        raise ValueError('vibe_tags must be a bounded list')
    for v in vibe_tags:
        if not isinstance(v, str) or not v.strip() or len(v) > 200:
            raise ValueError('Each vibe tag must be a non-empty short string')

    # --- area_hint ------------------------------------------------------------
    area_hint = raw.get('area_hint')
    if area_hint is not None:
        if not isinstance(area_hint, str) or len(area_hint) > MAX_AREA_HINT_LEN:
            raise ValueError('area_hint must be a short string or null')
        # Reject anything that looks like a decimal coordinate.
        if re.search(r'\d{1,3}\.\d{3,}', area_hint):
            raise ValueError('area_hint must not contain coordinate-like numbers')
        area_hint = area_hint.strip() or None

    # --- walking_limit_minutes ------------------------------------------------
    walking = raw.get('walking_limit_minutes')
    if walking is not None:
        if not isinstance(walking, int) or isinstance(walking, bool):
            raise ValueError('walking_limit_minutes must be an integer or null')
        if not 0 <= walking <= MAX_WALKING_MINUTES:
            raise ValueError(f'walking_limit_minutes must be 0–{MAX_WALKING_MINUTES}')

    # --- transport_preference -------------------------------------------------
    transport = raw.get('transport_preference')
    if transport is not None and transport not in ALLOWED_TRANSPORT:
        raise ValueError(f'transport_preference must be one of {sorted(ALLOWED_TRANSPORT)} or null')

    # --- exclusion_hints ------------------------------------------------------
    exc_hints = raw.get('exclusion_hints', [])
    if not isinstance(exc_hints, list) or len(exc_hints) > MAX_EXCLUSION_HINTS:
        raise ValueError('exclusion_hints must be a bounded list')
    for e in exc_hints:
        if not isinstance(e, str) or not e.strip() or len(e) > 200:
            raise ValueError('Each exclusion hint must be a non-empty short string')

    return SearchIntent(
        destination=brief['destination'],
        inferred_categories=sorted(set(canonical_cats)),
        vibe_tags=[v.strip() for v in vibe_tags],
        area_hint=area_hint,
        walking_limit_minutes=walking,
        transport_preference=transport,
        exclusion_hints=[e.strip() for e in exc_hints],
        extraction_path='ai_derived',
        extraction_model=model_name,
        raw_request=(brief.get('custom_instructions') or '')[:200] or None,
    )


def fallback_intent(brief: dict) -> SearchIntent:
    """Return a no-inference intent derived only from the validated brief.

    Used when no adapter is configured or when extraction fails.
    Records extraction_path='fallback' so the pipeline_report is honest.
    """
    return SearchIntent(
        destination=brief['destination'],
        extraction_path='fallback',
    )


# --- retrieval helpers --------------------------------------------------------

def merge_intent_categories(brief_categories: list, intent: SearchIntent) -> list:
    """Retrieval category list: brief categories PLUS inferred additions.

    Brief categories always appear.  Inferred categories from intent are
    appended when not already present.  The brief is never mutated.
    Explicit brief interests are never removed.
    """
    return sorted(set(brief_categories) | set(intent.inferred_categories))


def intent_enriched_task(task: dict, intent: SearchIntent) -> dict:
    """Return a copy of task with AI-derived retrieval signals attached.

    Only called when extraction_path == 'ai_derived' so callers never
    need to guard against stale intent signals from a failed extraction.
    The task dict itself is not mutated.
    """
    enriched = dict(task)
    if intent.area_hint:
        enriched['area_hint'] = intent.area_hint
    if intent.vibe_tags:
        enriched['vibe_tags'] = list(intent.vibe_tags)
    if intent.transport_preference:
        enriched['transport_preference'] = intent.transport_preference
    if intent.walking_limit_minutes is not None:
        enriched['walking_limit_minutes'] = intent.walking_limit_minutes
    if intent.exclusion_hints:
        enriched['exclusion_hints'] = list(intent.exclusion_hints)
    return enriched



# --- deterministic keyword fallback --------------------------------------------
# A fixed, reviewable vocabulary that lets free-text requests steer retrieval
# when no model is configured or extraction fails. It recognises words only;
# it never names, locates or describes a venue. Matching is accent- and
# case-insensitive. Each theme lists (planner category, keyword stems).
THEMES = {
    'tapas': ('food', ['tapas', 'tapa ', 'pintxo', 'τάπας', 'ταπας']),
    'seafood': ('food', ['seafood', 'paella', 'fish', 'θαλασσιν', 'παέγια', 'παεγια', 'ψάρι', 'ψαρι']),
    'market': ('food', ['market', 'mercat', 'mercado', 'boqueria', 'αγορά', 'αγορα']),
    'gaudi': ('attraction', ['gaudi', 'γκαουντ', 'modernis', 'μοντερνισ']),
    'art': ('museum', ['museum', 'museu', 'gallery', 'μουσει', 'μουσεί', 'τέχνη', 'τεχνη', 'picasso', 'miro']),
    'viewpoint': ('attraction', ['viewpoint', 'mirador', 'sunset', 'panoram', 'θέα', 'θεα ', 'ηλιοβασίλεμα', 'ηλιοβασιλεμα']),
    'beach': ('nature', ['beach', 'platja', 'playa', 'παραλία', 'παραλια', 'θάλασσα', 'θαλασσα']),
    'park': ('nature', ['park', 'garden', 'parc ', 'πάρκο', 'παρκο', 'κήπο', 'κηπο']),
    'vermouth': ('bar', ['vermut', 'vermouth', 'βερμούτ', 'βερμουτ', 'bodega']),
    'wine': ('bar', ['wine', 'cava', 'vino', 'κρασί', 'κρασι']),
    'cocktails': ('bar', ['cocktail', 'κοκτέιλ', 'κοκτειλ']),
    'coffee': ('coffee', ['coffee', 'brunch', 'καφέ', 'καφε', 'μπραντς', 'café', 'cafe']),
}


# Detailed interest IDs the app sends as preference_tags, mapped onto THEMES.
TAG_THEMES = {
    'tapas': 'tapas', 'seafood': 'seafood', 'markets': 'market', 'gaudi': 'gaudi',
    'museums': 'art', 'art_galleries': 'art', 'viewpoints': 'viewpoint', 'beaches': 'beach',
    'parks': 'park', 'wine_bars': 'wine', 'cocktail_bars': 'cocktails', 'specialty_coffee': 'coffee',
    'brunch': 'coffee', 'vermouth': 'vermouth',
}


def tag_themes(tags) -> list:
    """THEMES keys implied by the brief's detailed interests."""
    return sorted({TAG_THEMES[t] for t in tags or [] if t in TAG_THEMES})


def _fold(text):
    import unicodedata
    return ''.join(c for c in unicodedata.normalize('NFD', str(text).casefold())
                   if not unicodedata.combining(c))


def themes_in(text):
    """Return the sorted theme keys whose stems occur in ``text``."""
    folded = ' ' + _fold(text) + ' '
    return sorted(t for t, (_, stems) in THEMES.items() if any(_fold(s) in folded for s in stems))


# Words that carry no instruction of their own once the themes, the area and the stay are understood.
_FILLER = set("""a an and are around as at be both but by can do for from get go good great have i im in into is it its just like
lot lots love loves loving many me more most much my near need nice no not of on or our please really some somewhere stay staying
that the their them there things this to too trip very visit want wants we were what with would you
θελω θελουμε θα να και με σε στο στη στην στα στον για το τα τη την της του των ο η οι ενα μια πολυ πολλα λιγο
μας μου μενουμε διαμονη ταξιδι κοντα αρεσει αρεσουν""".split())


def keywords_cover(text, *, area=None, stay=None, leftover=2):
    """True when the fixed vocabulary read the whole request, so no model is needed to understand it.

    The request minus its theme words, the neighbourhood it names, where the traveller stays and filler words
    must leave at most `leftover` words. "tapas and wine, staying in El Born" is covered; "somewhere quiet to
    propose, she hates crowds" is not, and goes to the model as before."""
    import re
    folded = ' ' + _fold(text) + ' '
    if not themes_in(text):
        return False
    for phrase in filter(None, [area, stay]):
        folded = folded.replace(_fold(phrase), ' ')
    words = [w for w in re.findall(r"[^\W\d_]{3,}", folded) if w not in _FILLER]
    stems = [_fold(stem).strip() for _, group in THEMES.values() for stem in group]
    unread = [w for w in words if not any(stem and (stem in w or w in stem) for stem in stems)]
    return len(unread) <= leftover


def keyword_intent(brief: dict) -> Optional[SearchIntent]:
    """Deterministic intent from custom_instructions, or None when nothing matched."""
    text = (brief.get('custom_instructions') or '').strip()[:4000]
    themes = themes_in(text) if text else []
    if not themes:
        return None
    return SearchIntent(
        destination=brief['destination'],
        inferred_categories=sorted({THEMES[t][0] for t in themes}),
        vibe_tags=themes,
        extraction_path='keyword_fallback',
        raw_request=text[:200],
    )
