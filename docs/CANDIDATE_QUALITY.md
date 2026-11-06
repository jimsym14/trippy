# Candidate quality for the personal_places planner

5 November 2026. Offline only: no model, network or paid provider is used.

## Problem

The `personal_places` path filled missing categories from `.local/catalog.sqlite`
ordered by `shortlist_rank`, a geographic round-robin, not quality (food rank 1 was
Pizza City, rank 12 Burger King). A three-day "first visit, Gaudí, tapas" request
produced cinemas, a funeral-carriage museum, Citypark Cornellà and walks over two
hours. The video source pack, which holds the actual taste signal, was not used.

## What changed

| Piece | File | Behaviour |
|---|---|---|
| Suitability prior | `trippy/planner/candidate_quality.py` | 0–100 score from category fit, Overture confidence, dataset count, website and distance from the evidence core. Cinemas, theatres, dog parks etc. never fill sightseeing; fast food ranks last. Not a rating. |
| Creator endorsements | `trippy/planner/endorsements.py` | Joins recommended/passing source venues to catalog rows by exact normalized name, compatible family, and either one location or a clearly dominant confidence (≥0.95, margin ≥0.15). Automatic links also need confidence ≥0.8 and an address. Negative stances add nothing. |
| Retrieval | `trippy/planner/travel_provider.py` | Scores every eligible row, collapses same-name duplicates (often mislocated copies), boosts requested themes, and returns a pool spread over ~1 km cells. Endorsed stops carry the YouTube source and a quoted creator remark; coordinates always stay the catalog's. Area hints use neighbourhood polygons where available (below), else address text; never venue names. |
| Scheduler | `trippy/planner/plan_engine.py` (`slot_rank`) | Saved pins and explicit tags still win. The strongest candidate anchors each day; later slots prefer nearby places (8 quality points per km; legs over 2.2 km only when nothing closer fits). |
| Keyword fallback | `trippy/planner/search_intent.py` (`keyword_intent`) | Fixed EN/ES/CA/Greek vocabulary (tapas, Gaudí, market, beach, art …) steers retrieval when no model is configured. Labelled `keyword_fallback`. |
| Stage 2A | `personal_pipeline.py` | Candidate judging is off unless `judge_enabled=True`; no extra paid call from the bridge. |

## Neighbourhood boundaries (any city)

`trippy/catalog/boundaries.py` downloads Overture Divisions areas (locality,
macrohood, neighborhood, microhood) for any city in the catalog. The extent comes
from that city's own catalog rows, so no per-city setup is needed:

```sh
.venv/bin/python -m trippy.catalog.boundaries --city Barcelona   # or --all
```

Output: `.local/boundaries/<city>/areas.geojsonl` plus a manifest (release, assets,
checksum, per-row licences). Only public, non-requester-pays Overture assets are
read. Barcelona: 628 areas, 2 MB, release 2026-10-21.0.

With boundaries present, area hints are point-in-polygon tests (names in any
language, accents and articles ignored, scoped to the city's own polygon).
"Focus on Gràcia" is also detected from free text without a model. Without a
boundary file the provider falls back to address text and reports
`area_match_basis:<category>:<area>:address_text`; with one, `...:boundary`.
Some local names are missing in Overture (e.g. "El Born"); those fall back too.

## Free city layer: Wikidata + Wikivoyage (any city)

`trippy/catalog/city_layer.py` collects, with no paid API or model:

- **Notable places**: Wikipedia geosearch over the city's catalog extent, joined to
  Wikidata for fame (language editions), type, labels, description, coordinates (CC0).
- **Curated listings**: Wikivoyage See/Do/Eat/Drink/Buy from the city article and
  district pages (CC BY-SA 4.0; excerpts keep attribution to the page).

```sh
.venv/bin/python -m trippy.catalog.city_layer --city Barcelona   # or --all
```

Output `.local/city_layer/<city>/`; every HTTP response is cached under
`.local/city_layer/http-cache` so throttled runs resume. Barcelona: 589 Wikidata
items, 542 Wikivoyage listings (~1 MB), 75 requests.

`trippy/planner/city_evidence.py` classifies items by their Wikidata type labels
(no hard-coded IDs; famous "residential building" entries such as Casa Batlló are
kept by fame), links them to catalog rows only for the same kind of place, by
name and ≤150 m, and turns unmatched notable entries into their own candidates
located by the cited Wikidata/Wikivoyage coordinates. Fame (`log2(sitelinks/4)`, ≤4)
and listing bonuses add to the same evidence score as creator videos (cap 5).
Stops say why: video creator, "Προτείνεται από το Wikivoyage", or "Γνωστό σημείο
(N εκδόσεις Wikipedia)".

Result: with creator videos switched off, Barcelona still plans Park Güell + Casa
Vicens, Sagrada Família, the Cathedral, Museu Picasso, Cal Pep and Pinotxo — the
gate's `no-video-evidence-3d` case. That is the baseline other cities get.

## Measure

`.venv/bin/python scripts/planner_quality_gate.py` runs seven fixed Barcelona
requests (one with creator videos disabled), including an area-limited Gràcia case that checks every stop is inside its polygon (also `tests/test_planner_quality_gate.py`). Automatic checks: reproducible,
no unsuitable categories, draft legs ≤ 45 min, grounded coordinates/sources, at least
50% of stops backed by a video, Wikivoyage or Wikidata fame (and 25% by videos where they exist), requested themes present, unknown prices/routes stay
unknown. Current result: 7/7 pass, evidence share 0.88–1.0. The Gràcia case uses a lower endorsed-share threshold (0.1) because the video pack barely covers Gràcia. Usefulness still needs the human 0–2 × 5 rubric.

## Review and limits

- `python -m trippy.planner.endorsements` writes `.local/stage3/endorsement-review.md`.
  17 venues link automatically; all are `unreviewed`. Record decisions in
  `.local/stage3/endorsement-overrides.json` (`reject_entity_ids`, `links`).
- 245 of 294 source venues stay unmatched: Greek/ASR spellings, generic names, or
  names that differ from the catalog's ("Picasso Museum" vs "Museu Picasso de Barcelona"),
  or landmarks absent from the catalog (no Casa Batlló row).
  Those need reviewer links, not fuzzy guessing.
- Overture labels can be wrong (e.g. small venues labelled `art_museum`), and some
  single-source rows are mislocated. "Salvador Dali Museum" needs a human check.
- Cities without a downloaded boundary file still use address text for area hints.
- Opening hours remain unknown: a market counter can still be proposed for dinner,
  flagged `opening_check_pending`.
