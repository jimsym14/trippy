# Plan redesign and failure audit — 2 November 2026

The screenshots show a research report rendered as a finished itinerary. The failure crosses presentation, navigation, data coverage, identity resolution and release verification. Improving the surfaces alone would leave the traveler without a practical plan.

## Evidence and diagnosis

| Dimension | What failed | Evidence / consequence | Replacement |
|---|---|---|---|
| Product promise | Research coverage was treated as a complete trip | The recovered `Barcelona-latest-audited.json` contains seven places, no coordinates, five empty days and `quality_report.status=partial`. The screenshots contain some scheduled stops, so they are not proven to be this exact unchanged import. | Active overview exposes partial coverage and empty days. It does not claim the plan is ready. |
| Information architecture | Overview, days, places, costs, advice and evidence repeated across views | The old overview contained the report, a full map, costs, calculator, checklist, sources and only then the day links. | Day index first. Daily sequence lives in one view. Report/checklist/evidence use disclosures. |
| Reading order | Greek content appeared right-aligned | `scheduleList` forced `.rightToLeft` to move native reorder grips to the left. Section headers inherited that direction. | Explicit LTR content. Numbered sequence, left-aligned instructions and optional reorder menu actions. |
| Visual hierarchy | Nested cards, very large images and generous rounded surfaces gave metadata the same prominence as activities | A map and unknown-cost card consumed the first screen before the first stop. | Content-driven rows and dividers. One compact route map. No empty map card or empty estimate card. |
| Glass and navigation | Numerous independent floating controls competed with the trip | Selected trip had day chips, layer chips, filters, a peek panel and header pills. | One opaque day/filter/program bar. Selected-trip header controls are opaque; native app navigation remains system navigation. |
| Sheet layout | A custom header lived inside a NavigationStack without using its bar | Screenshots show a large blank top area and detent-dependent behavior. | Plan sheet uses a direct content stack and one large detent; title, tabs and day strip precede the scrollable content. Render confirmation remains pending. |
| Map location | Missing venue coordinates fell through to the map's automatic region | The current workspace did not run `resolvePlaceCoordinates`; the call lived on the older workspace. No destination marker meant the empty map could display an unrelated region. | Coordinate resolution is connected to the active trip/research. Empty day maps become concise missing-point states. |
| Routing | Markers were mistaken for a route experience | `dayMap` only added markers. MKDirections existed separately in the full-screen canvas. | Daily MKDirections geometry with mode-aware requests, cancellation, route caching, camera refitting and calculated preview time. Missing stops break adjacency. |
| Navigation destination | Search chose the first result without identity verification | A branch or loose name match could silently become a stored pin. | Automatic matching requires one exact normalized name within 60 km of the destination; unresolved matches require an explicit address/map preview and selection. This is conservative, not full canonical identity resolution. |
| Stop actions | A map link only searched/displayed a place | It did not request directions. Editing controls were always visible via list edit mode. | Directions open Apple Maps with the scheduled previous stop as origin where located, otherwise current-location navigation. Walking, driving and transit modes are passed through. Reorder/edit/replace/remove live in a contextual menu. |
| Schedule content | Long factual descriptions substituted for what to do next | Repeated holiday caveats and unknown hours obscured the sequence. Empty or un-timed stops were not a meaningful itinerary. | Each row shows number, proposed time, available duration, name, short instruction/reason, directions and known price. Detailed evidence and edits remain expandable. Missing times and date checks stay visible in day issues. |
| Costs | Unknown objects became reassuring filler | `readableValue` returned “Διαθέσιμες λεπτομέρειες” for an empty price object. Unknown totals dominated the cost table even though some tickets had prices. | Numeric/range prices only, explicit bases, real zero retained, partial ranges retained, no invented rollup. Known ticket prices are visible before secondary sections. Missing categories/methodology are disclosed. |
| Trust and interaction | “Κράτα” falsely implied a saved result | The old button only displayed a toast. | Bookmark selection persists through the existing trip reaction store and survives relaunch. Adding checks the underlying place identity to prevent duplicate stops. |
| Personalization | Brief preferences outpaced the connected planner | The recovered pool has only four attractions and three food places. Coverage flags include shopping, excursions, museums and events. Existing release documents acknowledge incomplete planner/provider integration. | UI preserves options, favorites, editing and evidence. Rich personalized coverage still requires the actual retrieval/date-check/planner path; this redesign does not manufacture those results. |
| Language | English day/overview labels and raw research category names leaked into the plan | “Day”, “Overview”, “pool”, “sight” competed with Greek copy. | Greek day strip and category labels; short localized dates; research details retain their source content. |
| Accessibility | Fixed small type, fixed list heights, permanent drag handles and cramped targets | Text expansion could clip the estimated-height activity list; tiny controls made common actions harder. | Scalable Plus Jakarta styles, natural row heights, 44 pt action targets, explicit move buttons and content width constrained to 720 pt. Device/Dynamic Type review remains pending. |
| Engineering/release | Multiple workspace implementations drifted apart | The active route bypassed coordinate work and partial-status UI. Previous docs explicitly recorded missing Simulator validation. | Older selected-day entry delegates to the new day content. Storage and plan projection checks cover the data path; native visual review remains a release requirement. |

## Design alternatives evaluated

1. **Map companion:** keep the map primary and use a very small itinerary peek. Good for exploring; poor for reading a multi-day plan, and repeats the current failure when the dataset lacks coordinates.
2. **Editorial trip guide:** large photos and rich narrative. Good for discovery; creates long scrolls and puts the practical sequence behind imagery.
3. **Warm daily ledger — implemented:** compact day index, ordered daily rows and a small route preview. This serves Trippy's existing minimalism, choices/customization and personalization brief while retaining the map-first app shell.

Tokens follow the existing ivory/forest palette, Plus Jakarta Sans, 8/12/16/20/24 pt spacing, 12 pt decision surfaces, and restrained accents. The signature is the ordered day sequence connected to real route geometry. Decorative imagery is unnecessary in a schedule; venue images appear inside place details only when provided.

## Connected pipeline follow-up

The bridge and CLI now share the resumable staged pipeline described in [COMPLETE_TRIP_PIPELINE.md](COMPLETE_TRIP_PIPELINE.md). The Places tab has search/category/liked filters. Imports reconcile stored stop references by identity, preserving user edits and marking changed schedules for review. App polling persists job capabilities and binds results to the requesting trip. Offline tests and real dataset retrieval passed; no live research, deployment or native rendered review is claimed.

## Actual behavior and limits

- Existing research remains opaque in storage. Favorites, ordering, edits, manual coordinates, checklist and user budget entries retain their existing ownership and serialization.
- Route geometry changes with order, coordinates and transport. No line bridges a missing stop; no line connects separate days. Transit opens in Apple Maps, without a fabricated in-app transit polyline.
- Route time is a present-day MapKit preview, not a forecast, booking guarantee or automatically solved visit schedule. Reordering does not reschedule every suggested arrival time.
- Automatic venue matching is intentionally conservative. A verified research coordinate still takes precedence over the search cache. Trip-switch cancellation prevents old responses from writing into a different trip.
- Unknown coordinate search can fail/offline; the user gets a retryable state and can select a candidate on a map. Source data is not rewritten by selection.
- Known prices are shown with per-person/group/room-night/day bases. No sum of all alternative tickets is presented as the trip's actual total. Eligibility caveats and booking links remain available.
- Missing research needs retrieval, canonical identities, operational checks, routing, duration/pace constraints and cost calculations to become a complete plan. The existing research audit can detect absent fields; it cannot itself create evidence.
- No inference or external publication was performed as part of this redesign.

## Verification

Passed:

- Swift parser check of the production source.
- `python3 scripts/verify_map_models.py`: old-trip migration; opaque research retention; order/edits/coordinates/checklist/budget; rename; saved place and note/share/evidence round-trips.
- `python3 scripts/verify_plan_projection.py`: missing-coordinate route breaks; one-stop/no-leg; day separation; walking/driving override; transit not faked; user-edited order; explicitly selected stop coordinates; null/free/partial/currency price handling.
- iOS Simulator SDK type check using a temporary copy that selects the generic State property wrapper and omits the existing Preview macro. This does not replace a real macro-enabled build.

Blocked by environment:

- `xcodebuild` failed before compilation because workspace arena/log writes and CoreSimulator access were denied. No build approval escalation was requested.
- No native screenshot, device interaction, actual route/search request, dark-mode contrast, Dynamic Type or VoiceOver certification is claimed.

Before release, run the rebuilt app with both the recovered partial Barcelona data and a useful synthetic route fixture. Check short/long Greek names, small/large iPhone, iPad, large text, light/dark, offline retry, explicit candidate selection, edited order, cancellation/trip switching, adding/replacing/deleting, favorites/relaunch, partial costs, and transit handoff. Judge actual screenshots against the supplied six failure screenshots; do not assign visual-review scores before rendering.
