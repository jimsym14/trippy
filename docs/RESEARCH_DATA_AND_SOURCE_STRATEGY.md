# Trippy — research data and source strategy

**Status:** product and data specification, based on the original Barcelona ChatGPT conversation, the first Trippy-generated prompt, the imported `barcelona_trip_research_2026.json`, and the current Swift prototype.  
**Purpose:** define exactly what information Trippy needs, where it can come from, what the first test did and did not provide, and how ChatGPT and non-AI sources should work together.

## Executive direction

Trippy should be a **research-to-trip workspace**. ChatGPT is useful for broad discovery, synthesis, contextual recommendations and filling a candidate pool. Trippy should make those results dependable and usable by preserving provenance, resolving places, checking deterministic constraints, calculating totals, organizing areas and routes, and keeping every representation connected.

The product should not treat generated prose as the database. Each place, event, price, opening-hours check, image, route, booking task and itinerary stop is a typed record with a stable ID. A record can be displayed in a card, table, map, day plan or cost view without copying its facts into separate blobs.

**Core division of responsibility**

| Work | Best owner | Reason |
|---|---|---|
| Understand a natural-language request; find candidate places, food, events, accommodation areas and useful comparisons | ChatGPT research (manual in MVP; later a permitted API/integration) | Broad web discovery and synthesis are the parts that made the original experience valuable. |
| Confirm exact operating dates, ticket terms, fares and reservation conditions | Official operator, venue, city or transit source | Current operational facts must be grounded in the party that controls them. |
| Geocode and display places; build map views; calculate distance and totals; compare itinerary constraints | Trippy + MapKit and deterministic local logic | These are repeatable transformations and should not depend on model judgement. |
| Normalize output, preserve unknown fields, show evidence, create diffs and render modules | Trippy | This is the app's differentiating product work. |
| Suggest alternatives from the existing pool based on proximity, constraints and user preference | Trippy deterministic ranking; optional model explanation | A transparent ranking over known candidates is more reliable than repeatedly asking a model to invent a new list. |
| Add context, explain trade-offs, compare a new source with the current plan | ChatGPT / future research provider, followed by Trippy diff review | This mirrors the useful iterative work from the source conversation while preserving user control. |

The differentiator is not “AI plans a trip.” It is: **every useful decision is connected to a place, day, map, cost, source and user choice, and the user can change it once.**

## 1. Evidence used for this specification

### Original ChatGPT conversation

The attached `barca` conversation contains 64 messages and documents the real planning workflow. It began with Barcelona, 5–9 December 2026, holiday closures, itinerary and accommodation areas. The user then added three travelers (parents and a 22-year-old), safety comparisons against Omonia, six Booking listings, walk-versus-metro comparisons, a preferred apartment, food/value preferences, holidays and opening hours, events, airport transfer terms, age/student ticket mixes, the TV show *Εικόνες* as an external idea source, and finally asked to compare Montserrat and other day trips with the existing plan.

The value came from **iteration**: later questions corrected assumptions and made the plan more personal. The final product needs to turn those follow-ups into targeted research requests and reviewed changes instead of making the traveler repeat the entire trip context.

The conversation also demonstrates output strengths worth retaining: day-by-day organization, comparison tables, concise recommendations with trade-offs, cost scenarios/calculators, checklists, source links, image-led place cards, maps, and a synthesis of new material with the existing plan. ChatGPT sometimes emitted rich interactive/widget markup in the chat. That markup is presentation-specific and is not a portable input contract for a native SwiftUI app. Trippy must ingest the underlying structured data and recreate the useful interaction natively.

### First Trippy research output

The actual file used for this audit is `/Users/jimsym/Downloads/barcelona_trip_research_2026.json`. It is valid JSON and has `schema_version: "trippy-research-v1"`.

It contains:

- 1 trip context and 1 overview;
- 5 calendar checks;
- 10 places (a mixture of attractions, neighborhoods, food market and a day trip);
- 2 events;
- 5 itinerary dates with 15 total stops;
- 3 map views;
- 4 transport options, 5 ticket options, 6 booking tasks;
- 16 sources, 5 warnings and 5 assumptions.

The file is substantially better than a prose-only answer: it has stable place IDs, source IDs, structured prices and ratings, date checks, a multi-day itinerary, route/map references, costs and booking tasks. But it is not yet the full “ultimate guide” the source conversation elicited, and it does not supply enough verified facts for the intended rich UI.

### Current prototype

The Swift prototype builds a detailed prompt and imports JSON only when it matches `trippy-research-v1` (or the additive alternatives patch). It stores the original research payload and has partial rendering for places, itinerary, maps, checklist, sources and costs. The view code tries to resolve coordinates using MapKit when imported coordinates are absent. That makes the prototype more than a JSON textbox, but it does not yet provide full schema validation, field-level provenance, robust entity linking, image validation/licensing, a complete cost calculator, complete source-to-field evidence, or a general-purpose editable normalized trip database. See `ios/Trippy/TrippyApp.swift`, `docs/PROMPT_RESEARCH_AUDIT.md`, and `docs/PRODUCT_AND_DEVELOPMENT_PLAN.md`.

## 2. What information the app needs

The research should be organized in **areas × information modules**, rather than one long answer or a single undifferentiated pool. “Area” is geographic; “module” is the subject. A trip can contain many areas and each area can have facts, options, routes and source records.

### A. Trip context and constraints

Collect or derive before research:

- destination/city/country and any multi-city legs;
- exact dates, date range, approximate duration, or explicitly unknown dates;
- arrival/departure time windows and known flight/rail details, if useful;
- travelers, ages, student/senior eligibility, children, group size;
- accommodation address/area or candidate links, when supplied;
- trip type and combined vibe (family, friends, couple, solo, work; city, nature, beach, nightlife, culture, slow travel, etc.);
- budget amount, currency, per-person/per-group basis, and inclusions/exclusions;
- walking preference, transit preference, mobility/accessibility constraints;
- cuisine/dietary preferences, allergies, excluded foods, meal pattern;
- must-see/must-do, avoid list, pace, preferred areas, previous choices and rejected suggestions;
- output mode: empty schedule with pools, proposed itinerary, or both.

Unknown must be a real state (`unknown` / `not_provided`), distinct from “no preference” and from false. Do not force the user through questions that do not change the research outcome. If a critical fact is missing, mark it and still return useful partial research.

### B. Geographic area records

Areas are first-class entities, not repeated strings in descriptions:

- stable `area_id`, name, parent area, city/country, polygon or center when available;
- qualitative character, best uses, trade-offs, walkability and transit access;
- relation to the user's stay address and other areas (distance/time, with method);
- safety considerations only when locally supported and carefully scoped (street/time/context; no blanket neighborhood labels);
- linked places, food/drink, events, accommodation candidates and routes;
- source IDs and check date for claims.

Area clustering should drive useful map views and itinerary grouping. It must not silently turn into a claim that all places within a neighborhood share the same safety, price or atmosphere.

### C. Place and activity pool

One canonical `place` entity should support restaurants, cafes, bars/clubs, attractions, museums, markets, parks, beaches, shops, day trips, hotels and other activities. Store category-specific details in typed subrecords or extensions while retaining a stable core.

**Identity and location**

- stable Trippy ID and provider/source IDs;
- canonical name, aliases/local-language name, category and subcategory;
- postal address, area ID, latitude/longitude, coordinate precision and verification method;
- official website, booking URL, phone if available, accessibility/contact details if relevant;
- identity match status (confirmed, likely, ambiguous, not found).

**Decision information**

- concise factual summary and a personalized `why_it_fits` explanation;
- best for, tags, cuisine/meal type, dietary options and allergen caveats;
- rating, platform, review count and checked date, if a permitted source provides them;
- popularity evidence kept separate from model opinion;
- cost amount/range, currency, per-person/per-group basis, taxes/fees, what is included and checked date;
- typical visit duration, best time, reservation need, age/eligibility notes;
- open/closed/unknown for the actual date, with date-specific evidence;
- pros, trade-offs and a comparison basis against nearby alternatives;
- user state: `like`, `maybe`, `not_interested`, scheduled, hidden; these are app-owned and must never be overwritten by an import.

**Images**

- direct image URL only if it resolves to the right image;
- source page URL, creator/owner, license/permission and required attribution;
- caption and alt text;
- media kind (venue exterior, dish, artwork, map/diagram), resolution/aspect ratio, last checked;
- fallback when no usable, attributable image is available.

An AI-generated trip-cover image is decorative. It must not be presented as a photograph of the real venue. Place imagery should be real, correctly identified and legally usable or omitted.

### D. Itinerary and routes

- one record per calendar day, including arrival/departure days;
- optional day segments (morning, lunch, afternoon, evening, night) created only when useful;
- ordered stops referencing canonical `place_id`s;
- start time, duration, free time, meal slot, booking deadline and flexibility;
- transfer leg between stops: mode, distance, duration, fare, accessible/walking notes, source or calculation method;
- reason for order, area cluster, alternative stop(s), weather/closure fallback;
- day-level cost range and assumptions;
- map view IDs derived from actual day/area/route structure.

Changing stop order must update the ordered map route and derived distance/time/cost. A stop can be removed from a day while remaining in its exploration pool. A place in a pool can be scheduled on more than one day only with explicit user intent.

### E. Calendar, openings, events and timed availability

- national, regional and municipal holidays and what they do/do not imply;
- normal weekly opening hours and exceptions for exact trip dates;
- one-off closures, maintenance, seasonal timetables and reservation slot availability;
- festivals, markets, performances, sports and temporary exhibitions with venue/date/time/price;
- date-specific public transport timetables and disruptions;
- last checked timestamp and time zone.

Distinguish: `confirmed_open`, `confirmed_closed`, `likely_open`, `not_found`, `not_checked`, and `not_applicable`. A general holiday calendar cannot prove a specific museum or restaurant is open. Use the controlling venue/operator page for that check.

### F. Accommodation comparison

When user gives candidate links or asks for lodging research:

- exact property/unit identity, provider, address/area, map point;
- dates, guests, room/bed configuration, occupancy and cancellation conditions;
- total price for entire stay, taxes/fees, payment timing, breakfast and included amenities;
- rating/review count/provider/date, verified policy/amenity facts;
- comparison against user priorities (family comfort, walkability, transit, quiet, kitchen, safety context);
- route/time to key clusters and airport;
- source links and confidence, with clear separation between URL parameters and confirmed live availability.

Booking links can encode dates and prices, but parameters are not proof that the current total/availability remains valid. Browser or official provider confirmation is needed for a bookable offer.

### G. Transport and access

- airport-to-stay and return transfer alternatives (metro, train, bus, taxi, shuttle, booked transfer);
- local transit fares, travel cards, age/student/senior eligibility and activation rules;
- route legs for key stops, walk/transit choice, time, fare and accessibility;
- exact timetable/disruption sources where available;
- ticket/pass break-even calculator inputs and result;
- parking, bike/scooter or other modes only if relevant.

The app calculates totals and break-even from explicit fare inputs. An LLM should not be the calculator or silently infer a discount entitlement.

### H. Costs, ticketing and decision tables

Represent each cost with amount, currency, basis, count/quantity, date, source, status and whether it is user-entered, researched, quoted or estimated. Useful rollups:

- per person and whole group;
- lodging, intercity travel, local transport, tickets/activities, food, nightlife, contingency;
- low / expected / high scenario;
- included/excluded items and assumptions;
- estimate versus confirmed / paid / booked;
- sensitivity controls (number of transit trips, meals, ticket eligibility, exchange rate if needed).

Tables should answer real comparisons: accommodations, transit passes, ticket combinations, candidate areas, and alternatives. Avoid tables that merely repeat every card field.

### I. Booking and preparation checklist

- action, related place/event/transport, owner, due date, priority and status;
- cancellation/refund deadline, reservation window, official booking URL;
- traveler-specific evidence (e.g. proof of student status), when relevant;
- completion timestamp and user note.

Checklist labels must be fully readable. Each task should state what to do, why/when, and link to the source/action.

### J. Evidence, freshness and research history

Every fact that could affect a decision should retain:

- source ID, URL, publisher, type and date/time checked;
- exact fields/claims supported by the source;
- source authority tier and directness (official operator, government, map provider, editorial, user input, model synthesis);
- retrieval/match status, confidence basis and known limitations;
- research run, prompt/template version and changed fields;
- older value and new value for accepted updates.

Evidence belongs at field or claim level. A single `source_ids` array on a whole place does not prove that each particular price, rating, schedule and image came from those sources.

## 3. Information source inventory

### Source tiers and suitable roles

| Tier | Examples | Use for | Do not assume |
|---|---|---|---|
| A — controlling/official | venue ticket/hours pages, transit authority, city holiday/event pages, airline/operator, hotel/provider's own offer | opening exceptions, terms, fares, schedules, official events, bookable links | that one page supports claims it does not state; a general official page may not be date-specific |
| B — structured map/dataset | Apple MapKit search, municipal open data, official GTFS, OpenStreetMap extracts | place identity candidates, coordinates, address, mapped features, routes/timetables where feed exists | complete coverage, live opening status, price, rating, reservations or global uniformity |
| C — licensed/attributable media/reference | Wikimedia Commons, Wikidata, Wikipedia | attraction descriptions, entity identifiers, reusable media when license/attribution is verified | that every image is reusable or current; that descriptions prove current operation |
| D — review/editorial/discovery | review platforms, travel publishers, guide sites, local media, programs/YouTube supplied by user | discovery, popularity/reputation signals, context, inspiration | that ratings can be copied freely; that old media gives current prices/hours; that a score is objective |
| E — ChatGPT synthesis | web research report and cited answer | candidate discovery, comparison, tailored interpretation, synthesis and structured candidate pool | that citation formatting itself validates the claim or that model-created fields are facts |
| F — user | user's dates, flight details, hotel links, budget, likes/dislikes, supplied show/video | constraints, decisions and provenance for user-supplied content | external verification of data merely embedded in user-provided URLs |

### Feasible non-AI and free/low-cost inputs

| Provider / method | Trippy use | Strength | Main limit / handling |
|---|---|---|---|
| **Apple MapKit / MKLocalSearch** | Place search, address/coordinate matching, POI display, directions/maps in native iOS | Native integration already used in the Swift prototype; searches addresses and map POIs; consistent Apple Maps experience | Search result is a match candidate, not independent proof of current hours, ratings, price or availability. Keep provider ID/coordinate match and let user resolve ambiguous names. [Apple docs](https://developer.apple.com/documentation/mapkit/mklocalsearch?changes=_8) |
| **City / regional open-data portals** | Official POIs, event listings, facilities, public-space information, sometimes live open datasets | Strong local authority and potentially bulk structured access | Coverage and schemas differ by city. Start with one destination's portal and create a source adapter; do not promise worldwide coverage. |
| **Transit authority APIs and official GTFS** | Schedules, stops, route geometry, service calendars, fare tables where published | Operator-controlled transport data | Every city has different access, licensing and availability; static GTFS does not necessarily include fares or real-time disruption. |
| **OpenStreetMap data** | Secondary POI/address/road network candidate, map overlays or routing input | Broad open geographic data, community maintained | ODbL attribution/share-alike considerations; public community services are not a production SLA. Use an appropriate provider or host extracts for scale. Do not depend on public Nominatim for autocomplete or bulk POI collection; policy restricts heavy/systematic use and sets a 1 request/second maximum. [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/) |
| **Wikidata / Wikipedia / Wikimedia Commons** | Attraction identity, structured metadata, encyclopedic summary and candidate images | Helpful for landmarks and cultural sites; media can have explicit licensing metadata | Not a restaurant/review database. Verify image-level license, attribution and whether it depicts the correct place. |
| **Official venue/restaurant/operator pages** | Hours, closures, ticket details, menu/price, booking, access and event dates | Highest authority for facts the operator controls | Often inconsistent, not machine-readable, and may change. Deep links and checked date should be stored. Automated crawling must respect terms/robots and rate. |
| **User-provided links/files** | Accommodation candidates, guide episodes, flight details, existing ChatGPT research | Directly personalizes investigation and helps avoid generic output | Treat as a lead, not confirmed truth; preserve original link and mark what was independently verified. |
| **Deterministic app calculations** | Distances, route totals where route provider returns legs, group costs, pass break-even, budget scenarios, date/day-of-week, conflict detection | Repeatable, cheap, testable, transparent | Show assumptions and inputs; never use a model to silently calculate or infer exact fare/eligibility. |
| **Weather source** | Forecast when dates are close; climate normals for distant dates if legally and technically appropriate | Useful for alternatives and packing | Free terms may limit commercial use, forecast horizon changes, and forecasts are uncertain. Treat as advisory, show provider/time and do not promise far-future weather. |

“Free” should be recorded as a product constraint, not an architectural assumption. Provider terms, rate limits, attribution rules, coverage and commercial use may change. A provider adapter should be replaceable, and caching/reuse must respect that provider's conditions.

### What we should not promise from free data

- A complete global list of restaurants/bars/clubs with dependable ratings, review counts and current prices.
- Reliable booking availability or live lodging totals from an ordinary map/place API.
- Direct image URLs and reuse rights for every business.
- Current hours from coordinates or a map pin.
- Safety ranking for neighborhoods without credible, appropriately scoped data.
- Live transport disruptions from a static timetable.
- Worldwide event completeness.

For these, ChatGPT can discover and summarize candidates, but Trippy should expose the source and uncertainty, and use official pages or user confirmation for decisions.

## 4. What the first test gives us today

The 10 place records all have a name, category, description, address, price object, rating object, tags, official URL, source IDs (9/10), checked date and coordinate object. This is good initial structure. The file also has date checks, event candidates, transport/ticket options, booking tasks, costs and warnings.

However, the **actual values** leave important UI gaps:

| Requirement | First JSON result | Impact in Trippy | Required change |
|---|---|---|---|
| Maps everywhere | 10/10 coordinates are `null`; all say not independently confirmed | Map has no imported coordinates. The app's MapKit name/address lookup may enrich some records, but that is a separate match step and may fail or choose an ambiguous result. | Prompt asks for coordinates with source/verification; app runs MapKit match and records provider ID/status; user resolves ambiguity. Never treat missing coordinates as verified. |
| Large activity images | `image_url` is null for 10/10 places | No place hero/photo; cards fall back or appear text-heavy. | Ask for specific image URLs/source pages/license metadata only when verified; if not found, app searches an explicitly supported source/provider or shows a designed no-image state. |
| Useful recommendation rationale | All 10 lack `why_recommended`, `best_for`, duration, best time and reservation detail | Card cannot explain fit, compare time/cost trade-offs or support day building well. | Make compact decision fields required; allow `not_found` for factual claims and model-sourced rationale clearly marked as analysis. |
| Ratings/popularity | All 10 `rating` values are null; no popularity field | User explicitly prioritizes reputation and review volume; budget without quality evidence is not sufficient. | Either provide a named licensed provider/source and checked date, or mark unavailable; use editorial/official recognition as a separate qualitative signal. |
| Hours and date-specific availability | `status_on_travel_dates` filled for 5/10; availability warning says tickets not confirmed | The user cannot tell which stops are safe to schedule on which date. | Per-place/per-date checks with official source, status enum, checked timestamp and field-level evidence. Keep general hours separate. |
| Day plan completeness | 5 calendar dates and 5 itinerary day records, 15 stops | Day structure exists, but should be checked against actual arrival/departure times and exact route sequence. | Capture flight arrival/departure windows in the input and audit day count vs nights. Validate that every stop references a place or explicitly represents a non-place activity. |
| Maps and routes | 3 map views; itinerary day schema does not carry consistent `map_view_id` in sample | Map intent is present but relationship contract is incomplete; route movement and map may diverge. | App derives overview and day/segment maps from canonical scheduled place IDs; model's `map_views` are hints, not a second route source of truth. |
| Source traceability | 16 source records, most item records link IDs; one place has no `source_ids`; calendar departure has none | Source section exists, but exact evidence for every price/hour/rating/image is not guaranteed. | Evidence entries attach source IDs to `field_path`; validate references and ensure sources support the asserted field. |
| Events | 2 event records, warnings say not confirmed by official organizer | Useful discovery, not decision-grade. | Store candidate state separately from confirmed event; require organizer/venue source and exact dates before labeling confirmed. |
| Transport/tickets | 4 transit options and 5 ticket options with sources; one limitations field only | Good starting pool, but age/student/senior eligibility, exact fare basis and pass break-even need normalized detail. | Separate eligibility rules, proof requirements, ticket validity, fare units, group size and calculation inputs; calculate comparisons in app. |
| Costs | Summary cost object exists | Useful for overview, but the calculator cannot reliably recalc if costs are not atomic, categorized and tied to assumptions. | Normalize each cost line; distinguish researched amount, estimate, user edit and confirmed spend; app owns formulas. |
| Editing and re-prompting | IDs are available for places, but no field-level diff/evidence contract in this JSON | Updates can overwrite or duplicate information; user choices and model output are not safely separated. | Stable IDs, field ownership, patch modules and previewed before/after changes; never let research overwrite user state. |
| General vs personal material | Context has 3 people and family/interests, but omits some details from the conversation (parents' ages, 22-year-old, exact accommodation candidate and chosen base, flight windows, food budget specifics) | The output may be family-oriented but cannot fully optimize tickets, lodging routes or timing. | User intake needs optional structured ages/eligibility, accommodation candidates/base, flight times and budget inclusions; preserve missing as unknown. |

**Key interpretation:** the initial failure was not only “bad JSON formatting.” The fixture parses and broadly matches the expected schema. The larger gap is **semantic/data completeness and evidence granularity**: valid JSON can still have no map coordinates, no usable images, no ratings, partial operating checks and insufficient links between source and field.

The first file also reports `duration_days: 4` while its itinerary has five dates (5–9 Dec inclusive) and says `nights: 4`. That is a calendar-day versus nights distinction. The imported data includes five dates, so Trippy should derive/validate both values rather than trust one ambiguous count.

## 5. What to change in ChatGPT research

### Preserve what worked

- Research broadly across relevant candidates before proposing a schedule.
- Tailor to group composition, dates, stay location, budget meaning, mobility and preferences.
- Use direct, specific sources and explain meaningful trade-offs.
- Keep a large option pool separate from the proposed schedule so the traveler can choose.
- Compare new inputs (e.g. a video/guide or an excursion) with the current trip and report only useful deltas.
- Return useful partial results instead of filling gaps with speculation.

### Replace the monolithic “do everything” request with a stable research protocol

The prompt should still be one copy action for the user, but its content should clearly define modules and priorities. If it exceeds practical context/output limits, the user can run a targeted follow-up without re-entering the whole brief.

1. **Context capsule:** normalized trip facts plus explicit unknowns, current stay/base, existing choices and user-owned decisions.
2. **Research plan:** ask the model to plan internally, but return no conversational follow-up. It must use the specified web research capability and list actual URLs in the data.
3. **Modules:** calendar/opening checks; areas/stay; places by selected categories; food/drink; attractions/events; transport/tickets; itinerary; costs; booking tasks; media; sources and warnings.
4. **Area-first organization:** each candidate/place references a canonical area; recommended route clusters use those same area IDs.
5. **Candidate pool vs itinerary:** return plenty of qualified options based on trip length and selected interests, but do not schedule every option. Mark whether a place is pool-only, suggested stop or selected by the user (the last one is never model-owned).
6. **Claim-level evidence:** every current or decision-critical fact includes `source_ids`, `checked_at`, status and a short evidence note for the exact claim.
7. **Research status:** distinguish `confirmed`, `secondary_source`, `estimated`, `not_found`, `not_checked`, `conflicting` and `not_applicable`.
8. **No fabricated completeness:** if ratings, images, prices, coordinates or opening status cannot be verified, say so. Do not claim an image URL is direct/reusable unless it was checked.
9. **No pseudo-precision:** compare quality/popularity only when a named source and count/scale exist; separate the model's fit explanation from third-party rating.
10. **Machine contract:** exact `schema_version`, JSON only, consistent IDs, enums, null/empty-list semantics, no duplicate place entities, source references resolvable. Keep narrative prose in explicit fields, not around JSON.

### Improve prompt input design

Keep Stage 2 compact and progressive. Essential destination/date mode first. Put optional but high-value inputs in expandable groups: group/ages; accommodation/base; arrival/departure; budget; pace/mobility; food/dietary; interests and exclusions. “Not decided” is a first-class selection. A checkbox triggers a module; it should not imply that other trip data is absent.

The prompt now asks for an **adaptive pool size** based on trip length, selected categories, destination variety and evidence quality, rather than a fixed 8–12 per category. Direct images, ratings, coordinates, hours, prices, sources, costs and schedules remain research requirements and should be reported as unknown when they cannot be verified.

## 6. What to change in internet/API work

### Use the internet and APIs for verifiable facts and enrichment

1. **MapKit first for native map search and place resolution.** Search by name + city/area/address, compare results and retain the selected provider ID. The app already uses MapKit searches to resolve some missing coordinates. Treat this as identity/geocoding assistance, not a source for every business fact. [MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch?changes=_8)
2. **Official local data adapters next.** For a chosen city, inspect its open-data portal and transit authority. Prefer stable published APIs/feeds for attractions, city facilities, events and transit. Keep one adapter per provider/city as needed, not a generic speculative scraper.
3. **Official site verification for volatile claims.** Where a place is being scheduled on a precise date, check its official hours/tickets/events. If automatic verification is infeasible, display a prominent “verify before booking” state and source link.
4. **Open map data as a fallback/cross-check.** OSM can help with coordinates, tags and geography, but use appropriate data hosting/provider and attribution. Public Nominatim is rate-limited, intended for moderate user-triggered use and explicitly disallows systematic/bulk place searches; do not build the product around bulk calls. [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/)
5. **Images only through a source that supplies identity and rights metadata.** Do not hotlink an arbitrary image URL found by a model. Validate that image can be loaded, identify its source and licensing/attribution, and provide a neutral fallback. A reusable image pool for landmarks is more practical than guaranteeing one image for each restaurant.
6. **Compute in app.** Calendar math, days/nights, cost sums, per-person/group transformations, distance from coordinates, and pass break-even are deterministic. Route duration and fare should be provider results or explicit estimates, never an LLM guess disguised as live data.
7. **Cache and timestamp.** Cache stable entity metadata and respect provider rules. Give volatile fields a refresh time and allow “recheck this” targeted actions.

### Avoid this early

- A global scraping crawler for every restaurant and review platform.
- Public free endpoints used as an unbounded production backend.
- Treating MapKit name match as verified live business hours or review quality.
- Treating any Google/search image URL as permitted image content.
- Building a city-agnostic transit system before one destination's official feed is proven useful.
- Adding an API solely to fill a visually empty card; empty/unknown states are safer than unsupported facts.

## 7. Canonical data and integration model

### Keep source payload and normalized records separately

Store both:

- `raw_research_run`: the exact imported text/file, prompt version, import time, source mode and parse diagnostics;
- normalized entities: trips, areas, places, events, source/evidence records, route legs, itinerary days/stops, cost lines and tasks.

This preserves the original response for audit and allows the normalizer to evolve without losing unknown data. Do not make raw JSON the UI database.

### Minimum reusable entity graph

```text
Trip
 ├─ ResearchRun ── Source ── Evidence(field_path, status, checked_at)
 ├─ Area ── Place ── ImageAsset
 │          ├─ OpeningCheck / Ticket / CostLine
 │          └─ UserDecision
 ├─ ItineraryDay ── Segment ── Stop ── Place
 │                              └─ RouteLeg ── Place
 ├─ MapView ── ordered Place IDs / RouteLeg IDs
 ├─ Event ── Place/Area + date + source evidence
 ├─ BookingTask ── Place/Event/Transport
 └─ BudgetScenario ── CostLine IDs + calculation assumptions
```

App-owned facts (user reaction, manual edits, booking state, stop order) must be separate from research-owned facts. Re-research returns a patch. The app previews a field-level diff and applies only accepted fields. Derived map and calculator views update from the same canonical records.

### Normalization and validation pipeline

1. Preserve pasted/file input unchanged.
2. Parse tolerant wrappers (fences or small preamble) but report that cleanup happened.
3. Identify schema/version; map known aliases to normalized fields; retain unknown properties in raw/extension storage.
4. Validate types, enums, date consistency, ID uniqueness, reference integrity, URL syntax, coordinate ranges and source links.
5. Match place to MapKit/provider candidate; show ambiguous matches for user confirmation.
6. Validate image reachability and rights metadata independently from JSON syntax.
7. Produce an import review: new records, updates, missing/conflicting facts, unsupported fields, and affected map/day/cost views.
8. Apply user-approved changes; do not silently replace user edits or decisions.

Schema validity and fact validity are separate checks. “Valid JSON” only means it can be parsed; it does not mean a place, price, image, coordinate or opening claim has been verified.

## 8. Re-prompt and update model

Every re-prompt needs a target scope and desired operation:

- `refresh` a fact (e.g. ticket price/date-specific opening);
- `find_alternatives` around a selected item, in the same category and reasonable radius;
- `expand_pool` for a category/area;
- `compare` a provided external source/video/property link against current plan;
- `revise_day` while preserving user-pinned stops;
- `recheck_transport` or `recalculate_costs`.

Include relevant context only, existing IDs and reactions, user-pinned items, exact requested fields, date range, source rules, output patch schema and explicit exclusion of already-rejected options. For alternatives, deterministic scoring uses category fit, geographic distance, date compatibility, quality evidence, budget and user preference. The model can explain top matches but must not be the only ranking mechanism and cannot invent candidate data.

The app should show a concise result such as: “3 new options added near this stop; 1 existing price updated; no schedule changes.” Then a before/after comparison and accept/reject controls.

## 9. Delivery plan

### P0 — Define and measure

- Freeze the canonical schema and status enums.
- Turn the Barcelona JSON into a regression fixture and record the audit counts above.
- Capture current parser/render gaps, including missing coordinates/images and date-vs-night mismatch.
- Define user-owned versus research-owned fields.

### P1 — Make manual import genuinely useful

- Accept JSON file and pasted text; show clear parser/schema errors and JSON preview.
- Normalize current schema and aliases; preserve unknown fields.
- Add import preview and partial success; keep raw research run.
- Make source links navigable; expose missing data explicitly.
- Resolve coordinates using MapKit with match confidence and per-place correction.
- Render larger actual images only when safe/usable; graceful designed fallback.
- Connect activity rows to stable place IDs and reorder the itinerary using a stable SwiftUI list mechanism; add explicit move controls; keep map order in sync.
- Add edits for time and personal cost separately from researched amount.
- Add useful checklist and transparent cost calculator from atomic inputs.

### P2 — Evidence and data quality

- Replace record-level source arrays with field-level evidence links.
- Add source authority, checked time, freshness and conflict display.
- Validate exact-date openings, tickets and events against official sources (manual research links first; provider adapters after city-by-city assessment).
- Add image provenance/licensing and image validation.
- Ensure every claim is either evidence-backed, clearly an estimate/opinion, or explicitly not found.

### P3 — Better research iteration

- Add checkbox-driven targeted research prompts by module and scope.
- Add additive/update patches with stable IDs, field-level diffs and review.
- Improve alternatives ranking from nearby known pool; ask for new research only when the current pool is insufficient.
- Add import of external guide/video candidates and compare only material deltas.

### P4 — Selective data integrations

- Prove one data adapter at a time: MapKit identity resolution (already present), one city/open-data source, one transit feed, one licensed image source.
- Log actual coverage, failure rates, attribution, refresh cost and freshness before expanding.
- Keep provider interfaces replaceable; no API credentials embedded in the iOS binary.

### P5 — Optional AI automation

- Keep the research-provider boundary; do not make the manual import path contingent on an API.
- If automatic generation is added, make clear that ChatGPT Go subscription does not include standard API usage; investigate authorized partner allowance-sharing only if Trippy can qualify and the integration is offered. Never ask users to paste ChatGPT passwords, session cookies or personal API credentials into the app.
- Use strict structured output/schema at the provider boundary, but still run the same normalization, evidence and diff pipeline.

## 10. Acceptance criteria for a dependable trip import

- The supplied first-test JSON parses and imports without losing unknown fields or valid modules.
- The import report calls out five itinerary dates versus four nights, does not mislabel nights as days, and does not hide the discrepancy.
- Every place appears in a category/area pool even if its coordinates/image/rating are missing.
- No map pin is placed at guessed coordinates. MapKit matches are identifiable and ambiguous matches are reviewable.
- A map can be shown for all geocoded options and for each day; order reflects the same stop IDs as the itinerary.
- Every price, opening status, rating, event date and image claim can reveal its supporting source and checked date; unsupported values show unknown/unverified.
- A missing image never blocks the card or shows generated art as a real venue photo.
- Reordering, deleting from a day, editing time/cost, liking and disliking are app-owned updates and immediately update all dependent UI.
- Re-research does not duplicate rejected or existing entities and cannot overwrite pinned/user-edited values without approval.
- Budget totals recompute deterministically from editable line items and show units, included categories and assumptions.
- Users can read every checklist item and see its status, due date and relevant action/source.

## 11. Short-term product choice

Keep the first product loop simple:

1. User enters trip constraints and optional high-value details.
2. Trippy generates the tailored research prompt and copies it into ChatGPT.
3. ChatGPT returns one JSON file containing modular areas/categories, candidate pools, itinerary, costs, tasks and source records.
4. Trippy validates, normalizes and enriches what it can deterministically; it reports the gaps.
5. User explores pools, schedules/reorders options, checks maps, edits personal assumptions and reviews costs.
6. User selects a targeted re-prompt; Trippy imports a patch and previews the diff.

This delivers the personalized research that inspired Trippy while making the app responsible for correctness of structure, traceability, connected editing and decision support. The app's trust signal is not maximal data density; it is **honest completeness**: useful detail where supported and visible uncertainty everywhere else.

## 12. Additional live data strategy: places, weather and provenance

### Can Trippy build a large POI database without ChatGPT?

**Partly.** We can retrieve and search many mapped places worldwide without asking ChatGPT to invent names, addresses or coordinates. We cannot get a dependable free global “Google Maps clone” containing current opening hours, high-quality photos, ratings/review counts, popularity and live prices under one open license.

Use a **federated lookup + trip snapshot** model, not a permanent scraped copy of all provider databases:

1. Start with the place candidates returned by ChatGPT or typed by the traveler.
2. Resolve identity through MapKit or a chosen POI provider using name + city/area + address. Store provider identifiers and match status.
3. Search open geodata for additional candidates in the relevant areas/categories, then deduplicate against stable IDs and coordinates.
4. Keep the selected trip's useful records and provenance in Trippy's own schema, subject to the source's license and storage/display terms.
5. Recheck only volatile fields on demand or near the trip date: hours, event date, price, booking status and disruption.

This avoids repeatedly fetching the whole city and lets ChatGPT focus on relevance, family/student suitability, trade-offs and synthesis. POI sources can supply raw discovery; deterministic Trippy ranking can filter/sort by selected category, distance, area, known opening status, budget, user reactions and evidence quality.

| Candidate source | Useful role | Cost / robustness reality | Recommendation |
|---|---|---|---|
| Apple MapKit / Apple Maps | Place matching, POI search, coordinates, native maps and directions | Best first choice for the current iOS app. Search results depend on Apple's coverage and should be treated as candidates. Do not imply that a returned pin proves price, live hours, rating or availability. | Use now for geocoding, resolving imported names and map UI; retain match ID/status. [Apple MapKit](https://developer.apple.com/documentation/mapkit/mklocalsearch?changes=_8) |
| OpenStreetMap regional extracts | Broad POI, road, walking and geographic data; can be indexed locally/server-side | Open data, but coverage/completeness varies by country, city and category. ODbL attribution and database obligations matter. Public Nominatim/Overpass endpoints are not an unlimited app backend. | Good second-source geography and fallback. For product-scale queries use a compliant provider or self-hosted extract/index; disclose OSM attribution. [OSM license](https://www.openstreetmap.org/copyright), [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/) |
| Wikidata / Wikipedia / Wikimedia Commons | Attraction identity, cultural entities, multilingual aliases, descriptions, some coordinates and image candidates | Strongest for notable landmarks and institutions; sparse/inconsistent for current commercial businesses, opening hours, reviews and prices. Media rights are per item. | Enrich landmarks and resolve aliases; don't use as the restaurant/bar backbone. |
| Foursquare Places | Broad commercial POI search/details, with some richer metadata | Current pricing advertises limited free test calls for Pro endpoints, then pay-as-you-go; richer photos/tips/hours can be Premium. This is not a permanently free mass-harvest source. | Consider bounded lookup only after measuring whether it fills MapKit/OSM gaps. Don't make it a required MVP dependency. [Foursquare pricing](https://foursquare.com/pricing/), [Places API](https://foursquare.com/products/places-api/) |
| Google Places | Strong business identity, ratings/reviews signals and place photos | Pay-as-you-go by SKU, field mask and request; published free caps apply per product/SKU, then usage can incur cost. Terms also constrain caching, storage and display. It is not a free exportable database. | Consider only if ratings/popularity materially improve the product and unit economics/terms are acceptable. Never scrape Google Maps pages or clone its ratings dataset. [Google Places pricing and billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing?hl=en), [pricing table](https://developers.google.com/maps/billing-and-pricing/pricing) |
| City tourism/open-data portals | Official museums, attractions, municipal assets, events and sometimes business directories | Can be excellent in a supported destination, but APIs, coverage and licenses are city-specific; no single global feed. | Add destination adapters after prioritizing the first supported cities. |

**Practical decision:** use MapKit + targeted OSM/open-data + ChatGPT for long-tail discovery in the early product. If users show that current ratings/popularity are essential, test a commercial Places source on a bounded number of selected records, with quota caps and cost telemetry. Do not spend requests for every item in a large pool: enrich on selection, scheduling or a limited top-ranked subset.

### Weather and animated hourly backgrounds

Weather is one of the strongest candidates for **non-ChatGPT live data**. Forecast numbers come from a weather provider; Trippy maps those values to visual states (clear, partly cloudy, rain, snow, storm, night) and runs its own lightweight SwiftUI animation. The animation is a UI behavior, not AI generation and not a weather claim by itself.

**Best first fit for the native iPhone app: Apple WeatherKit.** It provides current conditions and up to 10 days of hourly forecasts, including temperature, precipitation and wind. Apple currently includes up to 500,000 API calls/month with Apple Developer Program membership; attribution is required. [WeatherKit](https://developer.apple.com/weatherkit/)

Implementation shape:

- Query only after destination coordinates and trip dates are known.
- Cache by coordinate cell + forecast hour/provider update time; reuse one response across cards, days and the dashboard.
- Request only variables used by the UI and decision support (condition, temperature, precipitation probability/amount, wind, sunrise/sunset as needed).
- Show destination local time and the “forecast updated” timestamp.
- Drive background animation from forecast condition and hour (sun position/night); reduce motion for accessibility and battery.
- Show probability/uncertainty instead of turning rain chance into a definite rainy-day claim.
- For dates outside the forecast window, show no hourly forecast. A seasonal climate normal can be shown separately as a broad planning hint, never as a date-specific forecast.

Open-Meteo is convenient for prototyping, but its public free API is explicitly for non-commercial use, with a daily call limit and no service warranty. It is not a safe permanent free-backend assumption for a commercial or ad-supported Trippy. [Open-Meteo terms](https://open-meteo.com/en/terms), [API overview](https://open-meteo.com/)

**Conclusion:** WeatherKit is the cleanest starting point for this Swift-only app if the Apple Developer membership is already planned. Open-Meteo is useful for personal prototypes or noncommercial experiments. Avoid making a weather request on every screen render.

### Can we use “Google Maps updated tables” or an always-fresh directory?

Not as a free, rights-clear bulk database. Google Places, Foursquare and similar services expose selected fields through metered APIs and may restrict caching, storage, attribution and combining provider data. Their APIs are query services, not permission to export and own the full underlying directory. Use a provider live for an individual result and retain only data its terms permit; keep the provider and freshness label visible.

For open data, Trippy can build **its own curated trip snapshot** from OSM and municipal datasets, but “open” does not mean “verified”: a contributor dataset may be stale, incomplete or wrong. An update timestamp helps users assess freshness, but it is not proof of truth. Separate:

- `retrieved_at`: when Trippy received the record;
- `source_updated_at`: when the source says it changed, if available;
- `checked_at`: when a claim was last confirmed;
- `valid_for`: date/time window for a forecast, ticket, event or opening check;
- `freshness_policy`: how long Trippy considers that field useful before rechecking.

Suggested refresh classes: identity/address rarely; normal hours when the official schedule changes or before travel; date-specific openings/tickets/events nearer the date and on demand; prices/availability at every intentional refresh; weather at provider cadence; user edits never auto-refresh.

### “Blockchain-like” source and history model

Blockchain would not make venue hours, review counts or prices more truthful. It can make a record harder to alter after publication, but it cannot establish that the original source was accurate; a bad claim remains a permanently recorded bad claim. A public chain adds cost, privacy and deletion complications for little value in a personal trip planner.

What Trippy needs is a **provenance ledger / append-only research history**:

- store each imported or fetched claim as a versioned evidence event;
- record the source URL/provider ID, retrieval time, checked time, field path, old/new value and method;
- retain the raw source snapshot or a permitted excerpt/reference when licensing allows;
- never overwrite a prior research value silently; corrections create a new version;
- keep user-authored values and decisions in a separate ownership lane;
- optionally hash canonical snapshots for tamper detection or reproducible debugging, without putting personal trip data on a public blockchain.

This provides the useful “I can see what changed and where it came from” property without a blockchain dependency.

### What these sources remove from ChatGPT's workload

Use data adapters for repeatable retrieval and validation:

- broad POI candidates, coordinates and map placement;
- known entity aliases and duplicate detection;
- transit stops, routes and schedules when an official GTFS feed exists;
- hourly weather inside the forecast window;
- day-of-week/holiday arithmetic, cost sums and pass break-even;
- image URL reachability and source/license metadata checks when the provider exposes them;
- map distances and provider route legs;
- rechecking known official prices/hours where an API or structured feed exists.

Keep ChatGPT focused on contextual reasoning:

- which candidates suit this group and why;
- discovering relevant, unusual or less obvious options;
- evaluating trade-offs, fit and alternatives;
- proposing area/day groupings and a flexible draft schedule;
- interpreting a supplied video/guide or comparing it with the existing trip;
- writing concise explanations from verified material.

Then Trippy resolves and validates claims, calculates, records provenance and presents them. This reduces AI workload without building a large scraping or ranking operation.

## 13. End-to-end information layers and operating modes

### The data layers

| Layer | What it contains | Free/open-first path | Small commercial option | ChatGPT's role |
|---|---|---|---|---|
| **0. Traveler intent** | Destination, dates, party, ages, flight/stay links, budget definition, vibe, food, walking/access, musts/avoids, prior decisions | Entered in Trippy; import links/files | Same | Interpret ambiguous natural language and identify which missing facts materially affect research. |
| **1. Broad discovery** | Candidate attractions, food, bars, shops, day trips, events, areas | OSM/municipal datasets for broad POIs; Wikidata for major landmarks; user/ChatGPT-provided leads | Small number of Google Places or Foursquare searches if open data has holes | Search harder-to-index sources, discover hidden/specific picks, tailor breadth to the party and connect ideas across sources. |
| **2. Entity resolution** | Is this exact venue the same place as this result? Which address/branch? | MapKit search; OSM identifiers; alias/geographic matching | Google Places Place ID or Foursquare ID per selected result | Explain possible ambiguous matches from names/context; never invent identity certainty. |
| **3. Stable geography** | Coordinates, postal address, area, distance, area membership | MapKit; OSM extracts; official geodata | A metered provider for missing matches | Usually no AI needed. Use the resolved coordinates and user context to form useful clusters. |
| **4. Operational truth** | Date-specific open/closed status, hours, tickets, price, reservation rules, events, flight/transfer terms | Official venue/city/operator pages and local open-data feeds | Paid provider only if it offers permitted, current structured fields | Find the exact authoritative page, interpret exceptions and conflicts, explain what remains unconfirmed. The app stores evidence/status, not just the prose answer. |
| **5. Transit and route** | Stops, routes, service calendar, live disruption, walking/transit legs, fare | Official GTFS/GTFS-RT feeds where available; MapKit route services; published fare tables | Routing/transit API for cities without useful open feeds | Decide which routing alternatives matter for this traveler; not the arithmetic or route truth. |
| **6. Weather** | Current/hourly forecast, rain probability, wind, sunrise/sunset | WeatherKit for this iOS app under Apple Developer membership; free noncommercial Open-Meteo for prototype | WeatherKit included monthly allowance then metered tiers; other paid providers if platform changes | No research required. Explain weather impact only when useful; never fabricate forecast details. |
| **7. Reputation and media** | Ratings, review counts, popularity, real photos, rights/attribution | OSM/Wikimedia/Commons and official venue media where reusable; often no review score | Google Places/Foursquare live lookup for a selected subset, subject to costs and display/licence rules | Summarize evidence and discuss fit; cannot create ratings, review counts or image rights. |
| **8. Interpretation and plan** | Fit scores, trade-offs, area/day grouping, suggested schedule and alternatives | Deterministic scoring for constraints, distance, time, budget and reactions | Same; optional model provider for deeper explanations | Main reasoning workload: personalized recommendations, trade-offs, research synthesis, schedule draft and comparison of supplied external material. |
| **9. Derived calculations** | Day/night counts, totals, cost ranges, ticket break-even, time/distance rollups, conflict checks | Local deterministic code | Same | No AI required. Model may explain a result but cannot be the calculator. |
| **10. Trust and audit** | Sources, checked dates, freshness, conflict resolution, update history, confidence state | Append-only local history and direct source URLs | Small backend if sync/monitoring is later required | Help resolve conflicting pages; never decide that a weak source is authoritative without showing why. |
| **11. Experience layer** | Cards, expandable details, maps, tables, checklists, hourly weather artwork | SwiftUI and cached app records | Same | No model required for rendering. |

This separation lets Trippy use data without AI for routine facts while preserving ChatGPT for the work that actually benefited from the repeated conversation.

### Recommended pipelines

#### A. First release: minimal cost, no general backend

1. Capture trip brief and user-provided links locally.
2. Generate a modular research prompt; ChatGPT discovers candidates and returns stable IDs, areas, categories, source links and a draft plan.
3. Parse and validate the import on-device; keep raw response and normalized records.
4. Resolve place identities and missing coordinates with MapKit. Let user confirm ambiguous matches.
5. Use WeatherKit for trip forecasts when dates are within its forecast window; cache one response per destination/time window.
6. Use MapKit maps/routes and local deterministic calculations for day, distance and budget views.
7. Link official pages for volatile facts. Mark unsupported fields `not_found`/`not_checked` rather than making more calls or inventing data.

This is implementable by one developer and does not require a server, secret API keys, high request volume or an AI inference backend.

#### B. Open-data enhancement: local or small hosted index

1. Download a regional OSM extract for each chosen destination rather than issuing thousands of public endpoint requests.
2. Import only relevant categories/areas into a local or small server-side search index; preserve OSM object ID, attribution and source version.
3. Add Wikidata/Wikimedia records for famous cultural attractions, joining via external IDs and coordinates where quality is sufficient.
4. Add an official city dataset or transit GTFS feed only when the first destination has a usable license and feed.
5. Make provider adapters replaceable and display provenance; don't merge incompatible licensing/source fields into a fictional “Trippy verified” source.

This can provide broad POI candidate coverage without ChatGPT, but it will not supply reliable current ratings, photos, opening times or prices for every business.

#### C. Optional, low-volume commercial enrichment

When the traveler has selected a trip and we already have a shortlist, make a **small, deliberate number of lookups** only for the highest-impact records:

- resolve likely matching branches;
- add rating/review count and business photo if the selected provider supports it and its terms allow the planned UI;
- refresh only when the user taps “update” or the trip approaches;
- select only needed fields, set project quotas/budget alerts, log requests per trip, and stop enrichment on quota errors;
- retain only fields and identifiers allowed by the provider; keep an open-data/official-source fallback.

Google Places is not open-source data. It can offer small per-SKU free monthly allowances, but requires billing setup, then charges based on requested fields. More importantly for Trippy: Google Places results and photos have Google attribution/display rules, results shown on a map must use a Google map, and most content cannot be prefetched/cached/stored beyond specific exceptions (place IDs are generally exempt). Therefore **do not combine Google Places-sourced content with the app's Apple Maps view unless the applicable Google terms expressly permit that exact display**. This is not a portable database export. [Google pricing](https://developers.google.com/maps/billing-and-pricing/pricing), [Places policy and attribution](https://developers.google.com/maps/documentation/places/web-service/policies), [Places photos](https://developers.google.com/maps/documentation/places/web-service/place-photos)

If Apple Maps remains the primary map, use MapKit/OSM/official coordinates on that map. If Google ratings/photos are essential, present them in a clearly Google-attributed place detail experience that satisfies Google display terms, or choose another appropriately licensed data provider. Don't silently blend Google content into Apple map pins/cards.

### Information ownership, freshness and confidence

Each displayed datum should have a separate value record, not just a general place confidence badge:

| Value class | Example | Owner | Refresh rule |
|---|---|---|---|
| User fact | arrival time, accommodation choice, vegetarian preference | User | Never overwritten by research. |
| Stable source fact | place name, official address, category | Provider/official source | Refresh on mismatch or periodic maintenance. |
| Volatile source fact | ticket price, opening exception, event availability | Official source/provider | Show checked timestamp; refresh on request and near the relevant date. |
| Forecast | hourly precipitation at destination | Weather provider | Valid only within forecast window and provider update cycle. |
| Model inference | “This fits a family day because…” | ChatGPT/Trippy model | Label as recommendation reasoning, link to factual supports separately. |
| App calculation | 3-person total or transit-pass break-even | Trippy | Recompute immediately from shown inputs; show formula/basis. |

Suggested UI labels: **Officially confirmed**, **Provider data**, **Research finding**, **Estimate**, **Not checked**, **Not found**, **Conflicting sources**. “Verified” must mean Trippy actually checked the supporting evidence, not merely that the model emitted a URL.

### Quality controls that keep usage small

- Deduplicate by provider ID first, then name + address + coordinate proximity; send only unresolved candidates for model judgement.
- Query data only for the current trip's city/area and selected categories, not a whole country.
- Batch or cache requests where terms allow; do not refresh on each view render.
- Enrich shortlisted/scheduled records first, rather than every candidate in the pool.
- Set hard monthly API quotas, alert thresholds and per-trip request budgets before release.
- Use a free/open source as a fallback only if its license, freshness and coverage match the field being shown.
- Measure missing-field rates by provider and city; remove a provider that adds calls but little useful coverage.
- Never scrape websites or map UIs to evade paid API terms.

### Recommended source selection by field

| Field shown to traveler | First source | Backup / optional source | ChatGPT involvement |
|---|---|---|---|
| Place name/address/coordinates | MapKit + official venue page | OSM/local open-data; optional commercial place match | Resolve ambiguity and identify appropriate candidates. |
| Famous landmark summary/aliases | Official venue/museum page | Wikidata/Wikipedia, with source/date | Summarize and contextualize. |
| Restaurant/cafe/bar candidates | OSM/local data + MapKit + user/ChatGPT leads | Limited Foursquare/Google lookup, subject to terms | Discover suitability, hidden options and trade-offs. |
| Rating/review count | Named provider API with current terms | Omit if not available; no substitution by an AI score | Explain differences; never fabricate a numeric rating. |
| Hours/open on travel date | Official venue page or confirmed provider field | Contact/booking page or user check | Find and interpret exact date exceptions; report unknown if unresolved. |
| Ticket price/eligibility | Official ticket operator | Government/tourism page, then note secondary source | Compare family/student/senior rules; app computes totals. |
| Transit schedule/fare | Local transit authority/official GTFS/fare table | MapKit route option or official trip planner | Decide which route options are relevant and explain trade-offs. |
| Weather by hour | WeatherKit | Paid provider or Open-Meteo for noncommercial testing | Not needed for retrieval; optional explanation of itinerary implications. |
| Event date/time | Organizer/venue/city events API | Reputable event listing as candidate only | Discover and compare events; official confirmation required for confirmed label. |
| Image | Official/reusable media with explicit rights | Wikimedia Commons item with license, or licensed Places photo | Find likely candidate, but app/provider must validate source and attribution. |
| Walk/transit totals and budget | Provider route legs + deterministic code | Explicit user estimate where route data missing | Narrative interpretation only. |

### “Reliable” means field-specific, not one global rank

No source is authoritative for everything. The venue controls its opening hours and ticket terms; a transit operator controls its schedule/fare; a weather provider controls its forecast; a map provider resolves its own map identity; a user controls their budget and preference. A source score should therefore be attached to **claim type + date**, not simply to a website/domain. When two sources conflict, preserve both claims, prefer the source with authority over that field, display the conflict and avoid silently selecting the more convenient answer.

## 15. Implementation status and hardcoded-data audit

### Current status in the Swift prototype

The prior calendar-picker, destination-calendar enrichment, 7-day date-card carousel and category-specific preference controls remain specification only. The current brief still has typed arrival/departure text fields and general interests. The output prompt requests calendar checks/events; a separate external calendar/event data pipeline is not implemented. The map has been changed to a full-height MapKit page with a generated title/subtitle/trip sentence overlay. The prompt and task rows now support evidence-based 1–10 urgency semantics.

The current code change adds these **dynamic contracts/behaviors**, without inserting Barcelona data into a Trip:

- generated `booking_tasks` now request destination, task type, evidence-based `urgency_score` (1–10), urgency reason/basis/confidence, deadline, related place/event, URL and source IDs;
- the prompt no longer fixes an 8–12 candidate count per category; it requests an adaptive pool based on the brief and evidence quality;
- `custom_instructions` is passed from the user's notes field into the generated prompt context;
- the output contract now requests generated `map_overview.title`, `subtitle` and `trip_sentence`;
- the Map tab uses a full-height MapKit view with a compact overlay whose text comes from `map_overview` or general trip/research context;
- checklist rows can render a generated urgency score using a generic color/flame scale and show the generated rationale.

These changes are made in `ios/Trippy/TrippyApp.swift`. They have **not been Xcode-built or preview-validated in this update**. The calendar picker/date strip, destination holiday/event provider integration, richer category priorities and UI controls for those priorities are still not implemented. The document's earlier sections describe requirements/architecture, not completed production capabilities.

The generated prompt now has four selectable layers (foundation discovery, date verification, itinerary synthesis, targeted refresh). Later layers include the current imported research as their evidence foundation and return `trippy-research-patch-v2`, which the app merges by stable IDs. The foundation prompt still returns the full `trippy-research-v1` document. All layers repeat the constraints/preferences and date-verification rules so a later agent cannot treat them as optional context. This is a **manual ChatGPT workflow**; no Microsoft Foundry endpoint, credentials, agent, search tool or paid call has been configured in the app.

### What is and is not hardcoded

There is no Barcelona itinerary, Barcelona booking task, fixed research result or Barcelona address seeded into the Swift source. New trips start with a blank destination and research comes from the user brief and imported result.

There are generic, code-defined defaults and templates: default group/vibe/interests, the supported input categories, JSON schema, research rules, urgency color thresholds, and a fixed mapping from a few sample destination names/vibes to decorative trip-cover assets. Those are prototype/UI or template defaults, not facts attached to a Barcelona trip. The hardcoded candidate-count rule was removed from the prompt in this update. If the product owner wants every default category or cover choice configurable, that needs a separate design/configuration layer.

The Barcelona JSON in Downloads was inspected as a user-provided test fixture; it is not bundled into app code as a default trip. A copy imported on a particular device may remain in that device's local `UserDefaults` trip storage, which is user data and separate from source-code hardcoding.

## 14. Calendar-first brief and deeper trip customization

### Date entry: calendar range first, text still allowed

The primary date control should be a **month calendar range picker**. The user taps a start date and then an end date; only a continuous forward range is accepted. The earlier date is always the start. Tapping before the selected start can restart the range, with clear visual feedback. Do not require typing dates.

Keep a secondary “Enter dates instead” path for pasted/typed dates and for accessibility. Parse the dates, validate the order and reflect the resulting range in the calendar. Also retain explicit “Dates flexible” and “Not decided” modes; these are not malformed ranges. Allow a duration preference for flexible trips, but do not pretend it is a selected calendar range.

After destination + date selection, show a small date-strip preview in the brief. Each date can display compact, sourced markers for:

- national, regional or local public holiday;
- known city/seasonal celebration or market;
- confirmed event or event candidate;
- opening-hours exception when discovered;
- forecast availability later, once within range.

Holiday data should not be fetched before the destination/country (and, where relevant, region/city) is known. Holiday markers explain **what the date is**; they do not assert that every venue is closed. Specific closures still require venue-level evidence.

### Output calendar: 7-day carousel

Once the imported research has a resolved destination and trip range, the output shows a horizontal carousel/strip of **up to seven compact date cards at a time**, one card per calendar date in the selected range. For a trip longer than seven days, continue as a horizontally scrollable sequence or seven-day pages with a clear week/page indicator; do not drop days or silently change the trip range. For shorter trips, show only actual dates.

Each small day card should show:

- weekday and numeric date;
- holiday/event/opening exception badges with tap-through details and evidence;
- weather icon/condition only when a valid forecast exists, plus high/low or rain chance if space permits;
- itinerary state (empty, draft stops, confirmed/pinned) and stop count;
- conflict indicator only for something actionable (closed venue scheduled, transfer overlap, overfilled schedule).

Selecting a card opens that date's full day view and map. Do not cram event titles, source URLs or full weather text into the seven-card strip; expose these in a detail sheet or day page. The strip is a day navigator, not a miniature dashboard.

### Calendar data pipeline

1. Resolve destination country and administrative region from the chosen destination. Ask for region/city only if the place can be ambiguous.
2. Populate country holidays from a maintainable holiday dataset/API such as Nager.Date for an initial broad list, or bundle a versioned open dataset when suitable. Keep the source/version and distinguish nationwide from county/region holidays.
3. For supported launch cities, overlay the official city/regional government calendar. That source wins over broad country coverage for local holidays and official municipal events.
4. Verify likely closures from each venue/operator's official hours page for exact travel dates. A holiday lookup is only a warning/lead, not venue opening evidence.
5. Search events independently by the selected date range and destination. Keep results as candidates until organizer, venue, ticketing or official city source confirms date/venue/status.
6. Attach provenance, time zone, retrieval/check time and freshness to every calendar item.

An API such as Nager.Date can reduce manual holiday research and is useful as a **coverage bootstrap**, but should not be described as authoritative proof of local business closures. For launch destinations, prefer government calendars as the authority. Barcelona has a municipal open-data agenda and cultural data API, but each dataset must be inspected for freshness and event-date completeness before reliance. [Barcelona municipal agenda dataset](https://datos.gob.es/es/catalogo/l01080193-listado-de-eventos-diarios-de-la-ciudad-de-barcelona), [Barcelona Cultural Data Observatory](https://barcelonadadescultura.bcn.cat/dades-obertes/?lang=en)

### Events: separate kinds and evidence states

Do not use a single “events” checkbox for every type of date information. Internally use a taxonomy, but present a compact set of understandable user choices:

| User-facing option | Data subclasses/examples | Best discovery/verification path |
|---|---|---|
| **Public holidays & local celebrations** | national/regional/city holidays, saint days, parades, civic celebrations, seasonal lighting | Holiday dataset for discovery; official national/regional/city source to confirm level and date; venue-specific source for closure. |
| **Concerts & live music** | arena concerts, jazz/classical, local gigs, live music venues | Ticketmaster Discovery where covered; venue/promoter/artist page as confirmation. Ticketmaster provides a key-based Discovery API and documents event, attraction and venue search plus default quotas; coverage varies by market. [Ticketmaster Discovery API](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) |
| **Festivals & seasonal markets** | Christmas markets, food festivals, city festivals, parades, temporary installations | Official city/tourism/organizer feed first; ticketing/event API as candidate discovery. |
| **Performing arts** | theatre, dance, opera, comedy, circus, immersive shows | Venue and official ticket calendar; city culture agenda. |
| **Exhibitions & museum programming** | temporary exhibitions, late openings, special tours, workshops | Museum/organizer official pages; cultural city agenda. Keep distinct from permanent collection. |
| **Sport & major public spectacles** | matches, races, public screenings, fountain/light shows | Team/organizer/city/venue official page. Verify seasonal operation and date; do not assume a known attraction runs year-round. |
| **Food, nightlife & community** | tastings, brewery events, club nights, local markets, neighborhood festivals | Venue/organizer pages and local city guides; mark discovery listings as unconfirmed until an authoritative event record exists. |

Each event should have its own ID, type, title, organizer, venue/place ID, start/end in destination local timezone, date precision, ticket/price link, status, source IDs and checked time. An event page or ticket link must remain distinct from a claim that tickets are currently available.

### Further customization without turning the brief into a survey

The user wants more specific research, but the intake should not ask a long list of questions before every trip. Use **progressive disclosure** and three levels:

#### Level 1 — one-tap trip profile

User can pick one or combine a few profiles: first visit, family comfort, culture-heavy, food-led, nightlife, outdoors, slow/local, iconic highlights, budget-conscious, special occasion, work trip. Profiles set sensible starting preferences; user can override every part. These are convenience presets, not demographic assumptions.

#### Level 2 — category priorities (shown for selected categories)

Each enabled category gets one compact priority control with independent axes where needed. Default to “balanced”; expose extra choices on expansion.

**Food & drink**

- value for money / low-cost but well reviewed;
- best-known or most highly regarded;
- local/traditional dishes and neighborhood institutions;
- unusual/creative/“worth a detour”;
- popular/iconic/viral, with tourist-trap tolerance control;
- broad choice pool vs a few strong picks;
- cuisine, meal occasion (breakfast/brunch/lunch/dinner/dessert/late-night), dietary pattern, allergy/excluded ingredients, reservation tolerance, desired distance from base/day route.

**Bars & nightlife**

- craft beer/brewery/pub;
- cocktail/speakeasy;
- wine bar;
- tapas/local tavern;
- live music/jazz;
- club/electronic/dance;
- relaxed conversation vs high-energy;
- age/entry rules, opening nights, dress code, late-night transport and noise tolerance.

**Museums & culture**

- art (classical, modern/contemporary, photography, design/fashion);
- history/archaeology/civilization;
- science/technology/natural history;
- architecture/house museum;
- maritime/industry/transport;
- music/film/pop culture;
- religion/heritage;
- interactive/family-focused;
- permanent collection vs temporary exhibitions;
- ideal visit duration, willingness to queue, audio guide/tour interest, age/student eligibility.

**Attractions & outdoors**

- landmark/architecture/heritage;
- viewpoint/rooftop;
- parks/gardens/beach/coast;
- nature/hiking/day trips;
- market/shopping;
- interactive experience/theme park;
- religious site;
- photo spots;
- accessibility/terrain, weather dependence and transfer tolerance.

**Events**

- holidays/local traditions;
- concerts/live music;
- festivals/markets;
- exhibition/opening;
- theatre/performing arts;
- sports;
- nightlife/food events;
- only events that are confirmed vs include promising candidates;
- willingness to travel outside the center and spend on tickets.

For every category, allow explicit quality/discovery preferences:

- **Selection priority:** best-reviewed, famous/popular, local/traditional, unusual, value, convenient/nearby, or balanced.
- **Pool breadth:** focused shortlist / balanced / explore widely. Derive actual count from duration and category; do not make users choose an arbitrary “top 20” before research.
- **Location:** near accommodation, near each day's route, anywhere in the destination, or willing to day-trip.
- **Evidence threshold:** official/primary sources only for facts; allow reputable secondary discovery but require official confirmation for booking-critical fields.

Do not collapse quality and budget into one slider. Budget is a constraint/scenario; popularity, review quality, local character and novelty are separate preference dimensions. A low-cost selection must still meet the user's minimum quality/evidence bar.

#### Level 3 — custom instructions

Provide one clearly labeled, expandable free-text field: **“Anything else the research should know?”** It accepts user-written details such as:

- “We have tickets for Sagrada Família at 11:00 on Monday; build around it.”
- “My parent cannot walk more than 20 minutes without a break.”
- “Include one excellent inexpensive local dinner, but avoid places famous only from social media.”
- “We saw this YouTube episode; compare its recommendations with our current plan.”
- “Find a brewery for the 22-year-old and a quiet nearby option for my parents.”

Custom instructions should be preserved verbatim in the brief, then shown back as a short interpretation checklist the user can correct. They must not override hard constraints (dates, allergy, accessibility, closed venue) without an explicit warning. Do not let free text secretly change numeric budget, booking status or user-selected decisions.

Add optional “research detail” choices: concise / detailed / exhaustive and show sources for every important factual field by default. This tunes depth and result volume without asking a separate question for each output section.

### Prompt-generation policy for personalization

- Generate a stable, versioned prompt from the normalized brief, selected category taxonomy, priorities, custom instructions and existing trip state.
- Include only enabled categories; include relevant subtypes from user choices.
- Pass budget as amount + basis + inclusions + quality floor, not as a vague “cheap” label.
- Convert preferences into explicit ranking priorities and trade-off instructions (e.g. nearby first, but include one exceptional farther option if justified).
- Ask for separate `fit_reason` and evidence-backed `facts`; never treat “popular” as a fact without provider/source and metric.
- Ask the researcher to avoid follow-up questions; return partial results and explicit unknowns.
- Carry stable IDs, existing like/dislike decisions and pinned stops into re-prompts; preserve the user's current plan.
- Include selected date range and local timezone; ask for date-specific event/holiday/hours checks only inside that range.
- Return the exact machine schema and a compact human-readable completeness summary inside the JSON, not additional unstructured text.

### Calendar and preference acceptance criteria

- The user can choose start/end dates through a month calendar without typing; typed input remains an alternative.
- The picker cannot persist an end date earlier than the start date. Flexible/unknown dates remain separate modes.
- After destination selection, date cells show local/national holidays and candidate events with distinct visual states and source detail.
- Imported output shows all selected dates in day cards, up to seven visible in the carousel at a time; longer ranges remain fully navigable.
- A holiday indicator does not automatically mark a venue closed.
- Users can select concerts, celebrations, markets, exhibitions and other event types independently.
- Category-specific priorities, subcategories and custom instructions change the generated prompt deterministically and can be inspected before copy.
- The brief never requires all customization fields; defaults yield a reasonable prompt, and advanced controls stay optional/collapsible.
- The app separately records hard constraints, preferences, custom notes, researched facts and user decisions.

## 16. Layered research workflow and Microsoft Foundry model plan

### Current app workflow

The prompt sheet now exposes four deliberate layers. Keep the manual copy/paste route available while evaluating the workflow; this code does **not** call Microsoft Foundry or incur model/search charges.

1. **Foundation discovery — full document.** Apply the complete brief, constraints, exclusions, group, vibe, category, budget/quality trade-off and date range. Discover a broad but relevant place/event/transport pool, areas and candidate sources. Return `trippy-research-v1`; mark facts needing exact-date verification instead of asserting they are confirmed.
2. **Date and source verification — patch.** Use stable IDs from the imported foundation. Verify exact local dates and relevant local hours, weekday, national/regional/municipal holidays, special closures, event occurrence, tickets, reservations and transit. Return one date check per relevant entity/date and update only affected facts and booking tasks in `trippy-research-patch-v2`.
3. **Itinerary synthesis — patch.** Build/refresh days from date-checked candidates. Apply every hard constraint and preference again. Check operating window against the proposed day/time, group stops geographically, add realistic transfers/flex time, surface holiday/event effects and make maps from stable IDs. Do not turn an unverified candidate into a confirmed stop.
4. **Targeted refresh — patch.** Re-search only the user-requested scope plus dependent facts (for example: move a day → weekday, holiday, opening, event, tickets, costs, map and affected booking task). Preserve IDs, pinned/user-edited schedule and dislikes; show the merged diff before applying in a production implementation.

The prompt implementation currently embeds the imported JSON as the foundation for layers 2–4 and the importer merges patch-v2 `set`, `replace`, and ID-based `upsert` sections. The import screen still applies the patch immediately; a review/accept diff is a separate needed product task. The model still needs to obey prompts, so the app must validate JSON, date coverage, IDs, source references, coordinates, URLs, and consistency deterministically after every import.

### Every layer must carry the complete trip context

Pass a normalized brief to every agent: all destinations/stops (when present), exact date range or explicitly unknown dates, local timezone, traveler count/ages/group, mobility/accessibility, food/allergies/dietary preferences, selected categories/subcategories, vibe, budget basis, quality floor, geographic scope, travel pace, must/avoid, bookings already held, and verbatim custom instructions. If information conflicts, ask the user only if it blocks research; otherwise preserve the conflict as unresolved and state the assumption. Never silently drop preferences between discovery, verification and synthesis.

For date-specific claims, store `entity_id × local_date × claim_type × status × source_ids × checked_at`. A generic weekly opening-hours claim and a confirmed opening on a particular travel date are different records. Check relevant national, regional and municipal holiday calendars, but verify each venue/event separately. Let code derive weekdays and inclusive date coverage from ISO dates; the model should not be the sole date arithmetic validator. For unknown travel dates, mark date-dependent facts `not_checked` and do not invent a date or urgency deadline.

Booking urgency is likewise keyed by destination, related place/event, local travel date and due date. The prompt asks for a 1–10 score and an evidence-based reason; score 9–10 only for a verified deadline, documented date-specific requirement or evidence of scarce availability. Color/flame rendering is a UI signal, not proof. Keep source, confidence and the distinction between a deadline and a generic early-booking suggestion visible.

### Model recommendation (27 October 2026)

**Best starting default for a Foundry-backed Trippy agent: `gpt-6-luna`; selectively escalate final complex synthesis/conflict resolution to `gpt-6.1-sol`.** Do not use the largest model for every search. Also benchmark `claude-haiku-5-5` as a candidate-extraction/date-record subagent, but keep one model/provider for the first working slice until quality and cost have been measured.

| Model | Recommended Trippy role | Cost/capability implication |
|---|---|---|
| `gpt-6-luna` | Default for narrow search-query planning, candidate extraction/normalization, structured date checks, JSON patch generation and routine updates | OpenAI publishes $0.10/1M input and $0.50/1M output for its API; it describes Luna as its efficient focused/high-volume model. Confirm the actual Foundry SKU/region price in the Azure calculator before deployment. |
| `claude-haiku-5-5` | Optional high-volume subagent for extraction, classification, duplicate detection and well-scoped verification batches | Anthropic lists $0.10/$0.50 per 1M input/output for prompts up to 100K on its own platform, but that is **not a guaranteed Microsoft Foundry rate**. Check Foundry's Hosted-on-Azure offering and region price. Good for bounded tasks; do not assume it is the strongest final planner. |
| `gpt-6.1-sol` | Escalation for difficult preference conflicts, evidence conflicts, dense itinerary synthesis and final audit of a complex trip | Foundry lists $2/$10 per 1M input/output at Global Standard short context—about 20× Luna's published OpenAI API rates. Reserve for one or a few high-value synthesis/audit calls, not every candidate. |
| `gpt-6-astra` | Exceptional fallback only when a measured case fails on Sol | Foundry lists $10/$50 per 1M tokens Global Standard short context; avoid as normal routing. |

Claude Haiku 5.5 is a real Foundry model (not “Haiku 5.5” as a model from OpenAI). Its Foundry hosting/price, APIs, tool compatibility and region must be checked in the catalog. Foundry's built-in general Web Search currently documents Azure OpenAI model support; to use non-OpenAI models, Bing Grounding is a separate option. So for the simplest Foundry web-search implementation, Luna + Foundry Web Search is the cleaner first experiment. The web grounding tool is an extra usage charge, not free; Microsoft's docs also state search data flows outside the Azure compliance boundary. Review terms/privacy and keep sensitive traveler data out of search queries.

### Efficient agent topology

Avoid one autonomous agent doing broad web search, thousands of page reads, planning and final output in one unconstrained run. Use a bounded orchestrator with deterministic stages:

- **0 / Deterministic data adapters:** fetch official/open structured sources first (holiday calendars, public event feeds, official venue pages, map/geocoding, weather, transit where practical). Cache with source timestamp and expiry. Use model-generated queries only to fill coverage gaps. Provider APIs and any search grounding have their own quotas/terms/pricing.
- **1 / Candidate discovery:** batch by destination area × selected category. The agent generates query plans, uses web grounding sparingly, returns candidate records and direct sources. Deduplicate in code by stable identity/coordinate/name aliases; do not ask one call to emit an enormous city-wide database.
- **2 / Verification queue:** code builds tasks only for selected candidates and claims needed by the itinerary. Batch by entity type/source/date window, with explicit limits and retries. Prefer one official source query that covers multiple dates for the same venue; cache the hours page once, but preserve a result for each relevant local date. Parallelize independent venues, not repeated copies of the same query.
- **3 / Deterministic checks:** code validates date range/weekday coverage, ID links, source links, constraints, duplicate candidates, coordinate validity, budget arithmetic, route distance and whether stop time lies inside verified opening time. Reject/flag invalid data; do not spend another model call on arithmetic that code can perform.
- **4 / Model synthesis:** Luna assembles a draft only from passed/qualified records and emits a schema-constrained patch. Escalate to 6.1 Sol only when deterministic conflict/complexity rules or evaluator confidence trigger it. The larger model sees compact evidence and relevant records, not every raw search result.
- **5 / Independent final audit:** small deterministic validators first. If the trip is complex, one Sol pass audits constraints, missing dates, sources, closures, budget and map/day consistency; it may return corrections, never silently overwrite user-owned decisions.

Use strict request budgets per trip: maximum search calls, pages opened, model calls per stage, output tokens, elapsed time and retry count. Stop when coverage/quality targets are met; expose incomplete areas instead of endlessly searching. Reuse cached shared facts across travelers and trips, but expire volatile prices/hours/events appropriately. Keep model and search costs separately itemized.

### How to choose Luna vs Haiku vs Sol with evidence

Run the exact same fixed evaluation set (including the Barcelona JSON regression fixture and cities with different scripts/holiday systems) through Luna, Haiku 5.5 and, for synthesis only, Sol. Measure: verified claim accuracy, date/holiday recall, source authority, unsupported claims, preference satisfaction, candidate diversity/duplicate rate, JSON/ID validity, task urgency calibration, latency, model tokens and search-tool calls. Compare cost per **usable verified trip**, not cost per call. A cheaper model that requires repeated retries or misses closures may cost more overall.

Use Luna as baseline. Add Haiku only if it materially lowers cost at similar pass rate for narrow extraction/verification. Add Sol only for classes where evaluation proves a meaningful uplift in conflict resolution or final plan quality. Re-evaluate model/prices when deployments change. Do not use model-router cost mode until its routing distribution, quality and tool-call costs have been measured on this workload.

### Microsoft Foundry implementation boundary

The current iOS code only generates layered prompts for manual ChatGPT copy/paste. It has **no Foundry API integration**. For a real Foundry agent, put credentials and provider calls behind a small server-side API; never ship an Azure/Foundry key in the iOS bundle. The server owns tool calls, per-trip budget limits, schema validation, caching, prompt/version logs and redacted observability. Keep provider interfaces replaceable: `ResearchProvider` → `searchCandidates`, `verifyDates`, `synthesizePlan`, `refreshScope`; all return the same patch-v2 contract and pass through one validator/merge path. This keeps manual import, Foundry, and a later provider compatible.

For the first automated experiment, deploy one Luna model and the Foundry Web Search tool, make just the foundation and date-verification stages callable, record actual token/search usage, then decide whether to add Haiku or Sol escalation. This avoids building a multi-agent system before evidence shows it saves money or improves accuracy.
