> Library Been has been redesigned as **Been to**. See [BEEN_TO_LIBRARY.md](BEEN_TO_LIBRARY.md) for its native clustering, passport panel, and search/share flows. The map-label refinements below describe the general map.

# World, native Apple controls and city context

Library has a World tab with a native realistic globe, visited-country fills and one country flag/count marker opening its explicitly visited cities. Visits store coordinates, country and date; a planned trip never implies a visit. The general map has an independent Been layer, disabled by default. Country fills use the existing geoBoundaries source with country-prefixed polygon identities. Existing city clustering and trip/pin/save filters are preserved.

## Native Apple Maps only

The Apple Maps pill keeps native POI categories and map styles, and adds traffic, realistic/flat elevation, transit stations, Apple feature cards, map scale and Look Around. Look Around is displayed only when Apple returns an actual scene. Apple cards use native feature selection; the detail accessory is available on iOS 18+, with ordinary native selection on iOS 17.

There are no custom OSM metro, neighborhood or zoning overlays and no new Google pricing gateway. Apple Maps the app offers a transit mode that embedded MapKit does not expose as a selectable map style. Neighborhood names and cartography remain Apple's own, where covered. MapKit does not expose switches for all neighborhood boundaries or zoning data. Searching an Apple sublocality or Google neighborhood can focus that area and open personal feedback, without substituting an administrative boundary for its outline.

## STATLAS

Location panels and neighborhood feedback panels show a separate city-context card. The public JSON API requires no key. Requests use a 24-hour disk/memory cache, coalesce concurrent requests and validate HTTP status and decoded payloads. The map endpoint covers approximately 3,000 large cities, rather than the full city catalog. Matching requires valid coordinates within 30 km and country agreement when a country code is available. The documented city search provides a fallback for exact city/country matches; coordinate-free homonyms are never accepted without a country. Unavailable data remains unavailable.

- Safety is a modeled city estimate from national homicide data adjusted for city size, rather than a measured neighborhood safety rating.
- Cost of living is a modeled city index. It is not a surveyed neighborhood basket or a 1–5 budget score.
- Positive bars counts supply limited mapped nightlife context. Missing/zero coverage is not treated as proof there are no venues.
- No comparable family rating is provided. Incomplete amenity coverage does not become a fabricated score.

The card names the matched city/country, labels modeled/estimated data and links to STATLAS attribution and methodology. API city data does not provide an observation year for these indices, so no year is invented. CC BY 4.0 refers to STATLAS's published compilation; source-specific terms are linked through its sources page.

Optional personal 1–5 neighborhood feedback is stored locally and explicitly separated from sourced city indices. Unrated fields stay empty; invalid scores are filtered and nearby provider aliases can share the same feedback.

## Verification

`test_ios_statlas.py` compiles the production models against captured public Barcelona responses, checking decoding, coordinate/country disambiguation, search-only fallback and missing/invalid coverage. `test_ios_world_explorer.py` checks explicit visits, persistence, country grouping and personal feedback aliases/validation. Existing map, Library and draft regression scripts pass.

Production feedback/city-card components are rendered in light/dark and empty/rated states under `docs/neighborhood-design`. Fixtures are identified as preview data. Simulator compilation succeeds without warnings. The current environment could not resolve STATLAS on a subsequent network attempt; earlier captured HTTP 200 responses were used for reproducible checks. Live map interaction and remote Look Around coverage have not been reverified for this change.

References: [Apple MapStyle](https://developer.apple.com/documentation/mapkit/mapstyle), [Apple Maps app](https://www.apple.com/maps/), [STATLAS API](https://statlas.net/developers), [STATLAS methodology](https://statlas.net/methodology), [STATLAS sources](https://statlas.net/sources).

## Been labels

Both maps use the shared city label. Been text is masked with Apple's native country flag glyph and outlined for map contrast, with one static gold badge before the city name. City summaries own the Been badge when present; otherwise a standalone city label is anchored above the visit coordinate. No badge is added to individual location pins. Canonical city/country matching handles aliases and separates foreign homonyms. Labels use intrinsic single-line width without truncation and scale from 20pt nearby to 11pt at globe zoom. Animated glow, shimmer and visit confetti were removed. `docs/been-design` renders production labels in both appearances and at three zoom levels, including long city names.

## Map pin layout and boundary rendering refinement

Been labels and gold badges remain visible independently of the Been filter, which controls boundary fills/outlines only. The flag cutout now uses heavier type, increased texture contrast and crisp dark/white keylines. All city anchors share a liquid glass pin with the city/country title inside. Cities with no objects have no counter. Compact object summaries show an aggregate count; at nearer zoom the category dot/count or icon/count row is inside the same pin. The geographic anchor is its bottom tip, including when expanded.

`BeenMapPresentation.swift` prepares cached country ring detail on an actor and constructs reusable native map geometry when source data changes. Local/regional/world budgets are 480/160/64 vertices per ring, and subpixel islands are culled at distant zoom. Country hatches are not generated; city geometry is requested/rendered only at local zoom. Visited JSON is decoded only on storage changes. Country fill opacity is increased from 0.055 to 0.18.

Been city boundaries now require a city-name match across the available administrative levels; London also recognizes the official Greater London name. An arbitrary containing borough is no longer substituted. If the provider lacks a matching city boundary, the city surface remains unavailable. Older permissive city caches are bypassed.

The production geometry regression checks strict named scopes, cached LOD, stable IDs, closed rings, island culling and dateline extents. A synthetic 5,001-vertex fixture becomes 63 vertices at far zoom; this is algorithm evidence, not measured device FPS. The native Liquid Glass material is not supported by ImageRenderer, so the city-pin gallery uses a labeled fallback shape while retaining production layout.

## Country overlap groups and Been settings

City pins are shorter and use 11–14pt solid national-color city text; only the ISO abbreviation is masked with the flag. UIKit caches one small flag bitmap per country. Known palettes use readable light/dark national colors; other flags supply a cached dominant saturated hue. Stationary city surfaces use clear native glass without interactive pointer tracking, and category chips avoid nested glass effects. Expanded country lists share a GlassEffectContainer.

Screen-space pin footprints now group overlapping cities only within the same country. Groups use deterministic member IDs and geographical longitude wrapping. One compact flag pin replaces its member annotations; it shows city count, an optional visited badge and up to three category counts. Expanding it shows scrollable member city pins with their existing Library filters, counters and visited state. Panning the map closes the expansion, while scrolling its list does not.

The Been dropdown independently persists country outlines, color fill, crossing lines, detailed geometry, inner city boundaries, standalone Been city pins and gold badges. The master Been switch still controls boundary layers; labels are independent. Disabling standalone Been pins retains cities with visible trips/pins/saves, and the badge preference applies to those cities too. Optional country hatches are capped at 32 paths per country at far zoom.

Tests cover same-country overlap, foreign-country separation, transitive merging, pan/input-order/dateline stability, existing inventory filters and geometry options. Light/dark galleries include country pins with and without objects/badges. Device FPS has not been measured for this refinement.
