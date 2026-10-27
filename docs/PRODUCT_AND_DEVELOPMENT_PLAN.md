# Trip planning app — product and development plan

**Status:** first product specification / implementation baseline  
**Working name:** trippy (temporary prototype wordmark; naming is an open product decision)  
**Language:** Greek-first prototype, with localization designed in from the beginning.

### Decisions confirmed with the product owner

- Audience: detail-oriented travelers who want control without writing many prompts.
- Core result: a day-by-day trip plan with maps, costs, bookings, holidays, attractions, food and nightlife options.
- Research: manual ChatGPT copy/paste first. The user can paste a response and may also upload JSON.
- Research automation: no model call, local model, API key, credential handling or AI backend is implemented in this release. Keep only a provider boundary for a later phase.
- Initial trip creation offers both a quick start and optional detailed setup. Dates may be approximate or unresolved; flights are optional.
- The user chooses an empty itinerary or a suggested itinerary. Pools remain available either way.
- Each pool item has the user states `like`, `maybe`, or `not_interested`; scheduling is a separate action.
- Research requests a large, adaptive selection set based on trip length and preferences. Do not hard-code one universal result count.
- Targeted re-research uses checkboxes plus optional free text and produces a deterministic delta prompt.
- UI direction: Greek-first, warm ivory, soft rounded surfaces, Plus Jakarta Sans, the balloon mark, and warm destination photography. Stage 1 is a photo-led trip carousel, Stage 2 a compact expandable brief, and Stage 3 a photo-hero dashboard.
- Current native flow: trip carousel first; brief and deterministic ChatGPT prompt second; linked dashboard after research JSON is pasted/imported. Keep the screen mobile-first, detailed preferences collapsible, and the output source-linked.
- An individual factual field with no supporting source is shown as `— Δεν βρέθηκε` / `not_found`, never guessed. A place should only enter the suggestion pool when its identity and relevance have evidence; an unconfirmed field does not invalidate every other sourced field on the card.

## 1. Product intent

Help a detail-oriented traveler plan a complete trip with less back-and-forth: collect structured trip preferences, generate a precise research prompt for ChatGPT, import its response, and turn the research into an editable, visual trip workspace.

The product is centered on a trip workspace, not a chat transcript. The user remains in control of choices and itinerary. ChatGPT researches and proposes; the app validates structure, organizes information, calculates derived values, tracks sources and presents the result.

### Product promise

> Plan a trip with confidence: explore a rich set of sourced options, decide what matters to you, and build a practical day-by-day plan in one place.

### Target user

Anyone who wants a thorough, controllable trip plan and finds repeated prompting, long answers and scattered information frustrating. The product should still feel approachable to someone who does not consider themselves an expert planner.

## 2. Product principles

1. **Useful at every level of detail.** Show a concise card first; put deeper facts, caveats, source links and research history behind a clear expansion.
2. **User control.** Research creates options, not commitments. Users can keep, defer, dismiss, schedule, reorder and manually add items.
3. **Evidence before confident claims.** Research facts need sources and checked-at metadata. A requested binary check is `yes`, `no`, or `not_found`; missing evidence must never be silently guessed.
4. **Flexible input, normalized output.** Accept evolving model responses, map recognized fields to a stable internal model, retain unknown fields, and report missing or invalid data without discarding the rest.
5. **One action, modular research.** The user can request a complete research run at once. Internally, prompts and responses are divided into stable modules so large trips do not become a fragile oversized exchange.
6. **Calm, lively visual design.** Rounded, soft, modern surfaces with travel-inspired color and restrained motion. Vibe changes can influence accent colors and illustration, never readability or accessibility.
7. **No false precision.** Estimates are labeled as estimates. Prices, hours, events, holidays and availability are dated and sourced.
8. **One connected trip model.** A place, source, image, price and itinerary stop each have one stable identity. Cards, day plans, maps, booking tasks and cost summaries reference those records instead of keeping separate copies. Editing a stop once updates every view that uses it.
9. **Direct manipulation with a clear fallback.** Reordering by drag updates the itinerary sequence and its map route together. Every drag action also has an accessible move control; the UI never makes dragging the only way to edit.
10. **Visible provenance and ownership.** Every researched value can be traced to its source and check time. Research facts, user choices and app-calculated values are visibly distinct and cannot overwrite one another silently.

## 3. Scope

### First release (manual ChatGPT collaboration)

- Create a trip using quick-start or detailed setup.
- Support fixed dates, a date range, approximate duration and unknown flights.
- Capture travelers, trip style, vibe, interests, budget, food preferences and practical constraints.
- Generate a deterministic, versioned research prompt from trip state and selected modules.
- Copy prompt to clipboard; accept pasted JSON/text and optionally an uploaded JSON file.
- Parse and validate import; preview changes before applying.
- Store places, activities, events, transport, costs, sources, checks and day plans as structured records.
- Explore category pools with filters, map, search and decision states: **Like / Maybe / Not interested**.
- Offer an empty itinerary or a ChatGPT-proposed itinerary.
- Add and move items between days; preserve user choice and warn about conflicts without blocking edits.
- Show booking checklist, cost rollups, source details and update history.
- Re-prompt from checkbox-based change requests and merge only the affected modules after user review.
- Native iOS app built in SwiftUI, designed for iPhone first with iPad adaptation. The home stage fits the device viewport, uses safe-area insets, supports native gestures and has no page-level scrolling.
- Android is outside the first release. Shared product schemas, prompt templates and research contracts should stay platform-neutral so a future Android app can implement the same behavior independently.

### Explicitly out of scope for first release

- Calling an LLM, local model, or AI API from the product.
- Storing or using an AI API key.
- Automatic booking, ticket purchase, flight booking or payments.
- Claiming comprehensive live inventory or guaranteed current prices.
- Building proprietary global place/event/review datasets.
- Android support in the first release.

### Future integration seam (design only)

Define an application boundary such as `ResearchProvider` with operations to generate a research request and return a normalized research result. The first release implements a manual provider flow (copy prompt / paste or upload response). Do not implement an API or local-AI provider now. Keep provider selection, secrets, model invocation and streaming outside the trip domain so a future provider can be added without rewriting cards, itinerary or persistence.

## 4. Primary user journeys

### Three-stage navigation and trip library

1. **Home:** open on a warm ivory canvas with the balloon mark at top left and one clear `+` action at top right. Existing trips appear in one photo-led, swipeable cover carousel; the active card is centered, neighboring covers peek in, and each card shows destination, dates, travelers and a short preference summary. When there are no trips, show one inviting first-trip card. Keep appearance control available without competing with the create action.
2. **Brief:** keep the essential choices visible first: destination/region, dates or duration, trip style, and pace. Put group, traveler count, interests, budget and notes in an expandable preference section. The fixed bottom action opens the generated research prompt. The prompt remains modular and deterministic, and carries the full set of choices.
3. **Research and trip dashboard:** copy the prompt to ChatGPT, paste its JSON response back into the app, then open a destination-photo hero with a rounded information panel. A compact bottom navigation switches between itinerary, map, places and costs. Day cards collapse until opened; verified image, source and coordinate data stay attached to the records that use them.

Use fluid, reduced-motion-aware transitions between these three stages. The home carousel is a starting point for creating and revisiting trips, not a stats dashboard. Use warm editorial destination photos with careful portrait crops, coral/amber accents, forest-green actions, Plus Jakarta Sans, soft rounded surfaces and clear hierarchy. Do not use the previous ASCII banner direction in this current visual system.

### A. Quick-start trip

1. Enter destination and date range or approximate number of days.
2. Choose trip group (family, couple, friends, solo, work, multigenerational, other), plus one or more vibes (beach, culture/museums, nightlife, food, nature, shopping, work, mixed).
3. Add only immediately relevant details; mark unknown items explicitly.
4. Land in a workspace with a completion checklist and actions to refine preferences or generate research.

### B. Detailed setup

Use progressive sections for flights, travelers/age bands, accommodation, mobility, budget, dietary needs, cuisines, nightlife, interests, exclusions and accessibility. The user can skip any section and return later. Ask follow-up questions only when the answer materially changes research or itinerary feasibility.

### C. Research and import

1. User chooses **Empty plan** or **Suggested plan** (either can be changed later).
2. Select research scope: full trip or a targeted refresh. Full research is one user action and uses modular prompt sections.
3. Copy the generated prompt. Show concise instructions for ChatGPT to return strict JSON with no surrounding prose.
4. Paste the response; file upload is an alternate path. Show import progress and a summary of parsed modules.
5. Validate records and source evidence. Display an import preview: new, changed, unchanged, rejected/needs attention. Never overwrite user decisions silently.
6. Apply selected changes and retain an immutable research-run record.

### D. Explore and decide

Browse a large, preference-matched pool per category. The target number is adaptive to trip length, destination, variety and selected preferences; do not hard-code a universal count. Every result has a short card and expandable detail. User states are `like`, `maybe`, `not_interested`, and `scheduled` (scheduled is derived from itinerary membership). Filters include category-specific tags, distance/area, budget band, rating/review count where sourced, popularity, dietary fit, date/time fit and source status.

### E. Build itinerary

Add items from a pool to a day or time block. Support drag/reorder and accessible non-drag controls. Optional route ordering can suggest a more practical sequence. Keep user edits even if the app flags conflicts. Provide clear, non-blocking notices for overlap, opening-hours conflict, excessive density, long travel time or missing time.

### Cross-linked editing behavior

- Use canonical IDs for places, images, sources, prices, itinerary stops and route legs. A stop references a place ID; map markers, image choices and booking/cost rows resolve from that same place record.
- Reordering a stop updates itinerary order, route legs, map line/numbering, time estimates and affected cost summaries in one state change. If the route estimate cannot be recalculated, preserve the order and mark the estimate stale instead of inventing a value.
- Adding/removing a stop updates all relevant map views and totals. A place remains in its category pool when unscheduled; scheduling is a relation, not a duplicate record.
- Changes to a place's selected image update every card, itinerary stop and map preview that uses its canonical image reference. Preserve image attribution and source metadata through the reference.
- Give users direct controls for time, visit duration, quantity and their own budget assumptions. Use compact +/- steppers where increments are meaningful, with a visible unit and undo. Animate changed cards/values with a short carousel or slide transition that respects reduced-motion settings. Do not use +/- to edit a researched ticket price; let the user flag it or request a refresh, and keep any personal estimate in a separate field.
- Keep ownership explicit: researched fact (source-backed), user decision/input, or app-derived value (formula + input references). Imported research may propose a change, but a field-level diff and user acceptance are required before replacing an existing fact or user edit.
- Tapping a displayed fact opens its source/evidence detail at that field. Evidence records identify `record_id`, exact `field_path`, status, `source_ids`, `checked_at` and note. A map route or calculated total exposes its source legs or calculation inputs in the same way.
- Make all operations work with touch, keyboard and screen readers. Provide move up/down controls, focus retention after reorder, announced position changes, and a non-animated reduced-motion path.

### F. Targeted re-prompt

1. Select a trip, day, card or module.
2. Choose change checkboxes (e.g. re-check holiday opening, find more vegan options, add alternatives near a selected location, refresh ticket price, find rainy-day options) and optionally add free text.
3. Generate a deterministic delta prompt that includes stable trip context, target record IDs, requested fields, evidence rules and the same output schema/version.
4. User pastes the model response.
5. Show a diff and impact summary. User accepts or rejects each change/module.
6. Preserve prior values and research run for audit/undo.

## 5. Information architecture

Primary navigation:

- **Trips** — list, create and share trips.
- **Trip overview** — dates/status, budget summary, planning completeness, next actions.
- **Explore** — category pools and map.
- **Itinerary** — day-by-day timeline, day maps and general map.
- **Bookings & costs** — what to reserve, estimated/confirmed spend, ticket/transport options.
- **Research & updates** — prompt history, imported runs, sources, unresolved checks and diffs.

Recommended trip sections (collapsible on mobile): overview, itinerary, explore pools, stay/areas, transport, food & drink, attractions & events, budget, bookings, sources/update log.

## 6. Card and dashboard prototype specification

This describes the eventual trip workspace. The current first screen generates a detailed research prompt and accepts a pasted/uploaded JSON response for structural checks. Full normalization, import review, trip dashboard, cards and interactive maps remain later product steps.

### Card summary (collapsed)

- Name and category.
- One-line fit/reason for recommendation.
- Area and approximate distance or travel time when sourced/calculated.
- Rating plus review count and provider/source label, if available.
- Cost band or amount with currency and freshness label, if sourced.
- A small number of relevant tags (e.g. vegan options, breakfast, museum, live music).
- Like / Maybe / Not interested controls.
- A clear open-details affordance.

Use a hierarchy that keeps the card lively but scannable: identity and fit first, practical context second, decisions third. The prototype uses a compact illustration swatch, but production artwork and every evidence value must be sourced/licensed or clearly marked as a placeholder. Prototype values are labelled as demo/unverified; production cards must not surface a factual value as true without its required evidence.

### Expanded details

- Description and why it matches this trip.
- Address, coordinates, map pin and route options.
- Date-specific opening check as `yes`, `no`, or `not_found`, with checked date and direct source.
- Price/ticket details, currency, per-person basis, conditions and source.
- Rating/popularity facts with review count, provider and checked date.
- Dietary/accessibility/age tags with evidence or explicit unknown status.
- Practical notes, booking link, estimated visit duration and related alternatives.
- Evidence panel: source title, URL, source type, last checked, field(s) supported.

### UI direction

- Warm ivory canvas, the supplied balloon-pin logo, coral/amber accents, forest-green actions and Plus Jakarta Sans.
- Stage 1: small balloon mark, one `+` action, photo-led trip carousel, centered active card and narrow side previews. Cards show destination, dates, people and a compact preference summary.
- Stage 2: a guided brief with destination, dates, trip style and pace visible first. Fold secondary preferences into one clear expandable section. Keep the prompt action fixed at the bottom.
- Stage 3: destination-photo hero with an overlapping rounded details panel, collapsible day cards, and a compact bottom bar for itinerary, map, places and costs.
- Keep cards soft and rounded, selected controls clear, and motion fluid but restrained. Reduce motion when the system preference requests it. Protect text contrast over photographs with a gradient or solid information panel.
- Use generated editorial images only as trip-cover art. For actual venues and maps, display verified image URLs and source-backed coordinates from the imported research; never present generated artwork as evidence.
- Do not make ASCII artwork, Artvee, or Rawpixel runtime dependencies in this visual direction.

## 7. Data and output contract

Use a versioned JSON envelope. The schema should be strict for core identity and flexible for optional/category-specific details.

```json
{
  "schema_version": "1.0",
  "trip_context": { "destination": "Barcelona", "date_range": {}, "traveler_summary": {} },
  "research_run": { "run_id": "run_...", "created_at": "ISO-8601", "modules": ["places", "itinerary"] },
  "places": [
    {
      "id": "place_...",
      "kind": "restaurant",
      "name": "Example",
      "summary": "...",
      "location": { "address": "...", "latitude": null, "longitude": null, "area": "..." },
      "tags": ["vegan_options", "local_cuisine"],
      "price": { "amount": null, "currency": "EUR", "basis": "per_person", "status": "not_found" },
      "rating": { "value": null, "scale": null, "review_count": null, "provider": null },
      "checks": [{ "type": "opening_on_date", "date": "2026-12-08", "result": "not_found", "checked_at": null, "source_ids": [] }],
      "sources": [{ "id": "src_...", "title": "...", "url": "https://...", "type": "official", "supports": ["opening_on_date"], "checked_at": "ISO-8601" }],
      "visit_duration_minutes": null,
      "booking_url": null,
      "user_decision": "maybe",
      "extensions": {}
    }
  ],
  "itinerary": { "mode": "suggested", "days": [] },
  "costs": [],
  "warnings": []
}
```

### Contract rules

- Core fields and enums are validated; optional fields may be absent or `null`.
- Unknown fields are retained under `extensions` (or an equivalent raw payload) and surfaced to developer logs, not discarded.
- `not_found` is distinct from `no` and from absent/unrequested. For binary checks use `yes | no | not_found`.
- A factual claim that must be sourced includes one or more `source_ids`; source records carry URL, type, checked timestamp and fields supported. If one field lacks evidence, render that field as `— Δεν βρέθηκε`; do not fabricate it or suppress unrelated sourced fields on the card.
- To show a place as a researched recommendation, require evidence for its identity and location plus the basis for relevance. Missing rating, cost or date-specific hours may remain `not_found` without discarding the rest of the card.
- Preserve original raw import and parser/schema version for troubleshooting and future migrations.
- Stable IDs let targeted research update a record instead of duplicating it.
- Do not let model output set user decision, booking status or user-authored itinerary changes unless explicitly requested; those are app/user-owned fields.
- Validate links syntactically and safely; link reachability/content verification is a separate capability and must not be implied by schema validation.
- Partial import is allowed. Invalid records are isolated with readable errors; valid modules remain reviewable.

### Suggested top-level modules

`trip_context`, `calendar_checks`, `accommodation_areas`, `places`, `food_and_drink`, `attractions`, `events`, `transport`, `tickets`, `itinerary`, `map_views`, `costs`, `booking_tasks`, `sources`, `warnings`.

The prompt builder includes selected modules, dynamically derives map views from days/areas/routes without asking for a map count, requests actual image URLs with attribution metadata, and uses not_found for requested facts/assets it cannot evidence.

## 8. Determinism and flexible parsing

Determinism applies to app-owned transformations, not to the model's research judgment:

- Deterministically build prompts from normalized trip state, selected modules, prompt template version and requested delta.
- Store the generated prompt and template version for every run.
- Parse JSON first. If paste includes fenced JSON or surrounding prose, use a bounded extraction fallback and tell the user it was needed.
- Validate with a versioned schema; normalize known synonyms/enums; retain unknown data; report missing/invalid fields.
- Import preview is deterministic: stable ID match, field-level diff, explicit conflict handling.
- User-owned state wins over research output unless user accepts a proposed change.
- Do not auto-invent missing required facts. Set status `not_found`/`unknown` and request targeted research.
- Large full-trip requests can use one user action while the prompt builder emits modular sections and the import accepts partial module responses. This avoids truncation without making the user manage prompt engineering.

## 9. Re-prompt design

Checkbox catalog should be context-sensitive and extensible. Initial examples:

- Refresh/check opening status for selected date.
- Verify a price/ticket/transport pass.
- Find additional options matching selected tags or dietary needs.
- Find alternatives near a selected place or day route.
- Add rainy-day / low-walking / family-friendly options.
- Refresh event availability or schedule.
- Compare a selected option with alternatives.
- Update only selected itinerary/day/module.

Generated delta prompt includes `trip_id`, target IDs, exact requested fields, current values for context, exclusions, date range, source requirements, output schema version and instruction to return only changed/new records plus explicit `not_found` results. It must not implicitly delete records. User sees a field/module diff before merge, with undo.

## 10. What the app can do without AI

- Parse/validate JSON, normalize types/enums, preserve extensions and compute field diffs.
- Calculate dates/day names, duration and user-configured budget totals.
- Track costs by confirmed/estimate, per-person/total, category and currency.
- Detect duplicate IDs/URLs/coordinates, time overlaps, missing itinerary times and impossible date references.
- Derive scheduled state from itinerary membership; support filters, search and sorting.
- Show map pins/routes using a replaceable map adapter.
- Generate deterministic prompt text from templates and checkboxes.
- Manage source records, timestamps, import history, booking checklist and user decisions.
- Provide rules-based itinerary nudges (overlap/density/opening check missing) without making itinerary decisions.

External data is optional and must be evaluated for coverage, terms, quotas, uptime, attribution and cost. OpenStreetMap data is useful, but public OSMF Nominatim and tile services have usage restrictions and are not an unlimited production backend. Use replaceable geocoding/tile/routing providers, cache in line with terms, and show attribution. Events and local opening hours have uneven global coverage; do not claim comprehensive verification from a single API.

## 11. Suggested technical shape (SwiftUI iOS first)

- Native iOS app in SwiftUI, with iPhone as the primary layout and iPad as a secondary adaptive layout. Consider a macOS target after the iPhone workflow is validated.
- Reusable SwiftUI components with design tokens for theme/vibe, cards, filters, map, timeline, badges, source panels and diff preview.
- Domain model separated from SwiftUI views and external providers. Keep prompt JSON schema and imported research records platform-neutral.
- Local-first persistence behind repository interfaces; add export/backup before production. The prototype currently uses `UserDefaults`; production trip libraries should move to a more robust store.
- `ImportParser`, `SchemaValidator`, `PromptBuilder`, `ChangeSetMerger`, `MapProvider`, and future `ResearchProvider` as replaceable boundaries.
- Keep secrets out of browser storage. No AI keys or AI calls in the first release.
- Log parser/template versions and errors without logging sensitive traveler details unnecessarily.

## 12. Development task list

### Phase 0 — Product definition and design system

- [ ] Confirm product name and supported languages for first release.
- [ ] Finalize quick-start fields, optional detail fields and unknown-state behavior.
- [ ] Define trip, traveler, place, source, check, itinerary, cost, booking and research-run entities.
- [ ] Agree JSON schema v1, enums, ID strategy, source-to-claim mapping and partial-import rules.
- [ ] Define canonical record IDs and ownership rules for research facts, user edits and derived values; specify how references survive re-prompt/import.
- [ ] Define prompt template modules, template versioning and deterministic delta format.
- [ ] Produce card states: collapsed, expanded, selected, maybe, dismissed, scheduled, source missing, stale.
- [ ] Produce dashboard and empty/proposed itinerary wireframes.
- [x] Define initial vibe taxonomy and theme tokens; keep group type and activity vibe as separate dimensions.
- [x] Establish the new supplied balloon mark, warm destination-photo language, and light/dark appearance.
- [ ] Validate carousel motion, screen transitions, and light/dark contrast on iPhone and iPad.
- [ ] Define accessibility and reduced-motion requirements.

### Phase 1 — Clickable product prototype

- [x] Build the SwiftUI three-stage iOS slice with a photo-led trip carousel, structured brief, deterministic research-prompt generation and JSON import. (Build/runtime still needs Xcode validation.)
- [x] Add fixed/flexible/unknown date modes, travel group, combinable vibes, optional flights, progressive preferences and selectable research categories.
- [x] Add research-prompt copy action and strict JSON output contract for the separate ChatGPT research result.
- [x] Add pasted/file JSON syntax and top-level module presence checks for the returned result. (No import/apply pipeline yet.)
- [x] Add walk/transit priority, separate allergy and stay/safety context; adapt map views to daily routes and request sourced direct image URLs.
- [ ] Review questionnaire wording, field order, responsive layout and prompt/output contract with product owner before designing the following screens.
- [x] Build a connected dashboard prototype with expandable trip tree, overview, day itinerary, map preview, option pool, costs, bookings and source drawer; import JSON into a normalized dashboard preview. (Demo content is explicitly unverified; this is not production persistence or schema validation.)
- [x] Prototype linked interactions: reorder/move/remove stops, schedule pool items, update day route preview, field source drawer, budget assumptions and linked image references.
- [x] Add a three-stage trip library, per-trip brief draft storage, post-import dashboard transition, responsive trip carousel and Commons image search with attribution metadata.
- [ ] Design the result import preview and field/module-level apply flow; current prototype only performs structural checks.
- [x] Prototype trip dashboard, pool/card states, itinerary and map workspace; production import review and re-prompt workspaces remain future work.
- [ ] Review prototype with product owner and refine card face/detail hierarchy.
- [ ] Build trip overview with quick-start and detailed setup entry points as production components.
- [ ] Build adaptive card/pool UI with search, filters and Like/Maybe/Not interested.
- [ ] Build card detail panel with source/evidence section and `yes/no/not_found` check display.
- [ ] Build empty/proposed itinerary toggle and add-to-day interaction.
- [ ] Build map/list synchronized selection state (mock coordinates acceptable in prototype).
- [ ] Build shared trip state so a single place/image/source/price record renders consistently in pools, itinerary, maps and cost/booking views.
- [ ] Build drag reorder with map-route/order updates, undo, keyboard/touch move controls and route-estimate stale-state handling.
- [ ] Build field-level source/evidence drill-down, including checked-at status and paths for derived values.
- [ ] Add +/- steppers for user-owned time/duration/quantity/budget assumptions, with units, undo and reduced-motion-aware card transitions; keep researched prices immutable facts.
- [ ] Build checkbox-based change request composer and generated-prompt preview.
- [ ] Build paste response panel, mocked parse summary, import diff and accept/reject actions.
- [ ] Test key flows at mobile and desktop widths with representative trip data.

### Phase 2 — Manual research loop MVP

- [ ] Implement trip state persistence and editable setup.
- [ ] Implement versioned prompt templates and clipboard copy.
- [ ] Implement paste import and optional JSON-file upload.
- [ ] Implement parsing, schema validation, normalization, extension retention and readable errors.
- [ ] Implement import preview, stable-ID matching and field/module-level merge.
- [ ] Keep user-owned state separate from model-owned research fields.
- [ ] Save raw response, prompt, run metadata and applied changes.
- [ ] Implement pool filters, state changes, map pins and itinerary scheduling.
- [ ] Implement cost rollups, booking checklist and source freshness labels.
- [ ] Implement targeted re-prompt templates and merge preview.

### Phase 2 acceptance criteria

- The same normalized trip state, selected modules and template version generate byte-for-byte identical prompt text.
- A full research run is one user action; modular prompt/output sections can be resumed without asking the traveler to reconstruct context.
- A targeted request only updates requested records/fields, preserves user decisions, and cannot delete old records implicitly.
- Each supported binary check is represented as `yes`, `no`, or `not_found`, with date, source IDs and check timestamp where available.
- Pasted JSON and uploaded JSON reach the same validation and preview pipeline.
- Invalid records are isolated; valid records remain available for preview. No import is applied before the user accepts the change preview.
- Field-level differences distinguish new, changed, unchanged, and not-found results.
- The card clearly shows its concise summary before expansion and exposes sources, evidence, update time and practical details after expansion.
- The user can choose an empty or proposed itinerary, keep an independent option pool, and freely schedule/reorder items.
- Reordering a scheduled stop updates the day sequence and every map view that references that day; the same canonical place and image appear in all linked views.
- Every displayed research fact opens its supporting source and last-checked status; derived values show their inputs or calculation rule.
- Touch, keyboard and screen-reader users can perform the same edits as drag users; reduced motion disables nonessential transitions.

### Phase 3 — Reliability and polish

- [ ] Add schema migration strategy and import/export for trip data.
- [ ] Add conflict/density warnings and rules-based route summaries.
- [ ] Add source review UX, broken-link handling and stale-data policy.
- [ ] Add localization infrastructure and translated UI strings.
- [ ] Complete keyboard/screen-reader/reduced-motion/contrast review.
- [ ] Review privacy, retention, deletion and shared-trip permissions before public launch.
- [ ] Evaluate map/geocoding/routing/event providers against current terms, coverage and costs.
- [ ] Validate on representative destinations, languages and incomplete model responses.

### Phase 4 — Future research automation (not part of current implementation)

- [ ] Define provider capability contract and safe credential boundary.
- [ ] Compare hosted AI, user-supplied API key and local AI approaches.
- [ ] Add consent, cost visibility, rate limits, error handling and provider selection.
- [ ] Reuse the same schema validation, import preview and merge path used by manual mode.

## 13. Product risks and mitigations

| Risk | Mitigation |
|---|---|
| Very large prompt/result is truncated or inconsistent | One-click full run with modular output sections, size-aware prompt, partial import and resume/targeted refresh. |
| Model invents a source or overstates what a source confirms | Field-to-source mapping, explicit evidence instructions, source detail UI and never equate URL presence with verified claim. |
| “Not found” is mistaken for “closed/no” | Separate tri-state badge and explanatory microcopy. |
| Import overwrites user choices | Separate ownership domains, field-level diff, explicit acceptance and undo. |
| Too many cards overwhelm users | Adaptive pools, progressive filters, shortlist states, group-by-category/area and concise card face. |
| Free API becomes unavailable or terms change | Provider interfaces, attribution, caching per terms, usage monitoring and replacement plan. |
| Vibe styling harms clarity/accessibility | Theme tokens change accents/illustration only; maintain contrast and reduced-motion behavior. |
| Budget filters reward low quality | Rank/display quality, reputation, fit and value separately; let user decide tradeoffs. |

## 14. Open decisions for the next planning pass

- Product name and visual identity.
- Initial supported language(s) and first target device priority.
- Whether trips are private-only in v1 or shareable with collaborators.
- Which fields are required to show a card versus shown as `not_found`.
- Exact freshness policy per data type (e.g. event schedule vs. stable address).
- Preferred storage/auth approach once moving from prototype to MVP.
- Whether “large pool” has a user-facing cap with “load more” to keep browsing responsive.

## 15. Design and implementation references

- [Anthropic Frontend Design skill](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md): use subject-specific visual choices, a compact design-token plan, deliberate typography, restrained motion, responsive behavior, keyboard focus, and reduced-motion support. Its critique of generic SaaS-card layouts is especially relevant: rounded UI is requested, but hierarchy, spacing and card types should still vary with their function.
- [Transitions.dev](https://transitions.dev/): motion reference for intentional, responsive transitions. Treat the site as visual inspiration; do not assume its code or assets are reusable without checking their terms.
- [ascii.rest](https://ascii.rest/): candidate source/tooling for the ASCII hero. Keep a curated allowlist of city, coast and nature scenes, include a static fallback, and review the exact package license and dependency behavior before production use.
- [hairline](https://github.com/lucasmarkes/hairline): optional source for pointer-reactive SVG line illustrations. It is not required for the main banner or core task flow; evaluate performance, accessibility, license and fit before adoption.
- [Artvee](https://artvee.com/) and [Rawpixel](https://www.rawpixel.com/search?page=1&path=1522&sort=curated): inspiration/asset discovery only. Verify the rights of each individual image and store approved local assets with attribution metadata; a search page is not a blanket reuse license.

The prototype is intentionally a static, interaction-focused artifact. Its sample ratings, prices, trip facts and map are visibly marked as demo/unverified and must never be treated as research results.

