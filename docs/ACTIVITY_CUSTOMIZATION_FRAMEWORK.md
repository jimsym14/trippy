# Optional activities, place capabilities and map filters

Executable proposal preparation is now documented in
[Barcelona unattended runs](BARCELONA_UNATTENDED_RUNS.md). The registry is a draft
configuration; UI/compiler/planner integration remains pending. The unattended
batch produces review proposals against the existing source snapshot, not accepted
bulk enrichment before manual quality gates.

31 October 2026. Requested customization expansion before further Barcelona
enrichment. This specification supplements PLANNER_DATA_LIFECYCLE.md. It does
not mean the registry/compiler, API adapters or SwiftUI controls are implemented.

## Existing code and required changes

The schema already defines preference_templates, discovery_concepts, concept_entities,
trip_preferences, observations and classifications. Reuse this foundation rather
than introduce another unrelated city database. Current SwiftUI interests are
localized string choices; the catalog API mainly filters a single broad family.
Keep the broad family for compatibility, but add evidence-backed multi-valued
capabilities/facets and stable activity identifiers. Preserve raw provider taxonomy.
Audit acquisition coverage for supermarket/grocery/convenience-store categories;
do not assume the earlier regional import contains every practical category.

## One registry, separate meanings

An activity is a trip intent; a capability is what a venue offers; a trip rule is
frequency/timing/strength; a map layer is a view query. Do not put daily frequency,
breakfast-provided-by-stay, or according-to-plan on shared place records.

Versioned registry entries define stable ID, localized labels/aliases, optional
controls, capability predicates, slot mode, compatible time windows, default soft
strength, merge rules, fallback and versioned research instructions. UI labels,
typed query compilation, map layers and AI context use the same definitions. A new
activity using existing primitives should need a registry entry and meaningful
scenario coverage; a new semantic primitive may still require code changes.

Every selection stays optional. City discovery adds relevant suggestions, not
mandatory stops or invented user selections. Unselected activities do not exclude
other categories. Treat free text as a bounded proposal for typed preferences.

## Initial optional choices

| Intent | Lightweight controls | Planning effect |
|---|---|---|
| coffee_break | Occasionally / daily; optional specialty interest | Add a fitting pause near the route; merge with breakfast/brunch where compatible |
| brunch | Once / selected days | Midmorning meal, may replace breakfast or lunch; avoid duplicate meals |
| breakfast_at_stay | Provided / buy supplies / unknown; selected days | Protected morning time at stay; no assumed inclusion in accommodation price |
| breakfast_out | Bakery / café / either; selected days | Nearby morning options along departure route |
| picnic | Optional supplies | Outdoor meal; groceries only if requested, weather checks if supported |
| local_market | Food / browse | Distinguish market visit from a necessary grocery errand |
| sweet_break | Pastry / dessert / ice cream | Optional short pause, merge with compatible coffee venue |
| sunset_view | Rooftop / viewpoint / either | Dated sunset anchor and realistic travel buffer |
| park_pause | Optional | Flexible low-effort rest rather than mandatory attraction |
| beach_pause | Optional | Short relaxation or larger activity depending on duration |
| aperitivo_tapas | Optional | Early evening drink/food experience; respect meal preferences |
| live_music | Optional genre | Venue context plus actual dated event check |
| bookshops_vintage | Books / vintage / either | Nearby discovery stops; not exhaustive shopping research |
| photowalk | Optional | A route style with useful viewpoints; avoid duplicate attraction stops |

Keep the short visible list contextual and put less common options in an expandable
section. Daily is a control on coffee_break, not a separate venue tag or new engine.
Users can keep a stop, swap it or leave it flexible. UI styling remains a later
SwiftUI design stage using the user's selected Wholiver/swiftui-design-skill.

## Typed data and example

Trip intent fields: activity_id, registry_version, frequency, selected_days,
strength, optional preferred_time_window and options. Venue facets may include
place_type={cafe,bakery,restaurant,supermarket,convenience_store,bar},
service={coffee,breakfast,brunch,groceries}, coffee_type, cuisine, experience,
indoor_outdoor, meal context and source-supported atmosphere. Opening windows,
policies and prices remain observations rather than permanent tags.

Typed predicates support any_of/all_of, soft weights and hard exclusions. A bakery
classification alone does not prove seating, coffee service, full breakfast or
coeliac safety. Tags carry evidence IDs, scope, review status and lifecycle class.
Known false, unknown, conflict and verified/supported are distinct. AI confidence
is not an admission threshold by itself.

coffee_break daily: produce at most one desired coffee occurrence per selected day,
bounded nearby candidates, and a flexible slot. Merge only when the selected venue
supports the capabilities and the user/time requirements align. Use one canonical
place entity across multiple activities and map layers; retain separate stop
occurrences if the user revisits it at different times.

breakfast_at_stay: provided protects time without inserting another venue. Unknown
does not silently imply provided. Buy supplies permits one convenient shopping
errand, with an option to repeat; do not infer an equipped kitchen or cooking needs.
Do not ask about individual groceries, detailed menus or appliances by default.

## Research instruction example

"Find suitable coffee pauses close to the current day's route or selected anchors.
Prefer places with evidence for the user's selected coffee context. Reuse a
compatible breakfast or brunch stop when it provides coffee; avoid adding a
redundant pause. Return a small bounded set with canonical candidate IDs, supporting
evidence and unknown fields. Preserve other trip interests and locked stops. Do not
search all cafés in the city or infer opening times, atmosphere or service from a
name. If no suitable source-backed choice is found, return an explicit gap."

This is compiled from a reviewed template plus trip context, not bare JSON labels.
Only relevant candidate evidence and unresolved fields are passed to the model.
Source text is untrusted data; models cannot alter allowed tools, policies or budget.

## Map behavior

Layer chips: Plan, Coffee, Breakfast/brunch, Restaurants, Bars, Sights, Groceries;
less common categories under More. Groceries can expand to supermarkets and
minimarkets. A coffee view can offer curated suitable spots and broader café
inventory without pretending every café is equally recommended.

Independent scope control:
- According to plan: scheduled stops plus bounded suitable alternatives near the
  selected day's route/anchors, with alternatives visually distinct from stops.
- All in this area: available catalog/provider matches within the visible map
  area, with pagination/clustering and evidence/selection status. Not all businesses
  worldwide and not a claim of complete city coverage.

Filter changes do not mutate the itinerary or trigger a citywide AI research call.
Use cache first and bounded spatial fetches on explicit search/viewport settling.
Switching layers reuses canonical IDs; membership in several layers is not duplicate
identity. User add/place search remains available for unlisted choices.

## Boundaries and adapters

Deterministic code owns predicate compilation, exclusions, stable ranking, proximity,
frequency, merge/meal rules, schedule feasibility, budgets and user locks. APIs/feeds
provide external observations. Luna proposes structured facets from supplied evidence,
normalizes free text and performs bounded niche discovery/explanations. It does not
certify identity, current facts, route feasibility, accessibility or allergy safety.

Use one adapter interface for bounded place search, place details, routing, hours,
availability/events and source retrieval; each provider advertises actual supported
capabilities. Normalize responses into observations with provider IDs, evidence,
actual fetch time, validity, retention and cost receipts. Unsupported capabilities
return explicit unavailable, not invented values. Do not integrate every provider
at once: local catalog first, MapKit interactive search/directions after terms and
backend-use review, then official source adapters for measured operational gaps.

## Bounded implementation and inference sequence

1. Implement registry and typed intent/capability contracts and semantic compiler.
   Preserve compatibility with old interests/imports; no paid extraction required.
2. Integrate the completed adjudication results, then inspect the regional taxonomy
   and existing evidence for missing practical categories/capabilities.
3. Manually assemble a diverse 20-record reference set (cafés, bakery, mixed-service
   restaurant, groceries, attraction and ambiguous cases). Run one source-bound
   Luna pilot in small batches, with separate reservation from the same $15 ledger.
   Prepare actual token ceilings before dispatch; no new inference authorized by
   this document beyond the user's existing overall scope/cap.
4. Measure factual precision, useful recall, unsupported inferred capabilities,
   missed negation, branch errors and semantic cost. Only after acceptance, enrich
   relevant canonical candidates with available evidence. Missing evidence goes to
   focused source research, not a model memory-generation request.
5. Implement generic map queries and activity-slot/merge primitives once. Test coffee
   daily, provided/unknown breakfast, one grocery errand, brunch replacing a meal,
   multi-layer venue identity, locked stops and empty/provider-failure results.
6. Add adapters only when those end-to-end scenarios demonstrate a specific unmet
   capability. Keep all larger enrichment runs conditional on measured gaps.

No new paid run or UI implementation has been performed in this specification stage.
The present small batches demonstrated protocol reliability (313/313 source slots,
no protocol-recovery events), not measured truth accuracy; 113 unresolved and 150
repair proposals still require careful adjudication. The Azure deployment alias
does not by itself prove which published Luna snapshot serves requests. Capture
returned model/deployment metadata without exposing credentials in future receipts.
