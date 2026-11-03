# Barcelona planner readiness assessment

31 October 2026. Evidence inventory, manual semantic spot checks and 32 proposed
trip scenarios. This is not a production planner benchmark or independent web
fact check. No additional paid calls or remote catalog writes were made.

## Verdict

31 October update: three measured private correction passes and primary-source
observations are now implemented; see [curation automation](CURATION_AUTOMATION.md).
Those source corrections do not establish canonical publication or successful
execution of the scenarios below. The readiness verdict remains unchanged.

The extracted source pack is useful, but it is not a complete or approved planner
database. It can help discover and explain mainstream Barcelona experiences.
It cannot reliably satisfy all preference combinations, enforce operational
constraints, or establish that a recommendation is current or universally fair.
No credible finite travel database can promise 100% coverage and accuracy.
The product should instead guarantee explicit uncertainty, evidence provenance,
bounded gap research, constraint validation and user control.

The batch and failed-passage recovery are complete. City-data curation,
canonical publication and planner retrieval integration are not complete.
The two recovered files are separate versions; they must replace their originals
in an effective research view, never be appended alongside them.

## Measured inventory

| Inventory | Actual state |
|---|---|
| Latest 21 videos, including recovery replacements | 476 records / 1,566 claim entries |
| Two retained pilot results | 73 records / 460 claim entries |
| Combined effective source pack | 549 records / 2,026 claim entries, 23 videos, seven publisher groups |
| Venue occurrences | 294; not 294 resolved unique venues |
| Explicitly uncertain identities | 297 of all 549 records |
| Records with Overture identity proposals | 90; proposals are not approved matches |
| Exact quote/timestamp/name/rating checks | All 549 retained records passed against original transcript evidence |
| Dedicated dietary / allergy claims | One dietary claim, incorrectly tagged; zero allergy claims |
| Dedicated accessibility claims | Nine; several concern price, security, closure or shoes rather than accessibility |
| Opening-hours claim entries | 14; includes historical observations and general advice, not verified schedules |
| Price claim entries | 38; historical source assertions, not a current complete cost model |
| Five-star ratings | Zero. Unknown must remain unknown |
| Broad local inventory | 41,461 basic entities in local catalog; extracted enrichment has not become an approved release |

The 549 records include cities, districts, routes, dishes, advice, ticket and
transport products. Record count must never be presented as unique place count.
Source publications in the 21-video batch span 2009–2025. Old sources may retain
value for architecture or creator taste; they do not establish current prices,
opening hours, transit fares, tours, availability or operation in 2026.

Field coverage is sparse and sometimes misleading. Of the combined source pack,
696 claim entries use `other`; they can contain useful prose, but are not dependable
typed filters without semantic classification. Thirty-eight historical prices do
not establish budgets for 294 venue occurrences. Six address-dimension entries are
largely relative location descriptions, not six fully resolved street addresses.

## Concrete semantic findings

1. The only `dietary` claim describes adding soda water to vermouth. It provides
   no evidence of vegan, vegetarian, gluten-free, halal or allergy accommodation.
2. `accessibility` includes free basilica entrance, security rules, an amusement
   park's historical closure, and the creator saying espadrilles do not suit him.
   None establishes a step-free route, accessible toilet or wheelchair suitability.
3. Four `clubs` category records are a city, advice, an unnamed marijuana club
   and an uncertain casino location. There are no resolved music-style nightlife
   club options established by those counts. Cannabis-club context must not match
   an ordinary request for a nightclub.
4. Eleven `coffee` records include a dish, districts, a square and a department
   store. Six venue occurrences in that category are not six verified specialty
   cafés. Equivalent Greek and English department-store names may duplicate a place.
5. Literal substring search for `fast food` matches “fork-breakfast food”; searching
   `techno` matches “technology” in Sagrada Família construction. This illustrates
   why keyword hits cannot be counted as supported intent coverage.
6. “Gothic Quarter” supports geography or architecture; it does not establish
   gothic music, fashion or a goth nightclub. Style and location need separate facets.
7. The first-timers recovery adds useful material but also preserves variants such
   as Parkwell / Park Well / Park Guell and multilingual landmark spellings.
   A larger raw candidate pool is not proof of independent choices or diversity.
8. A source assertion that restaurants do not open before noon is not a city-wide
   rule. Such statements must remain attributed general advice and cannot become
   hard scheduling constraints for all restaurants.
9. La Plata details include dishes, atmosphere and historical August closure.
   This is valuable taste/context evidence. The filmed closure cannot determine
   availability for a future selected date.
10. The extra audits selected passages rather than reviewing every cue. Saved
    full transcripts preserve recoverability; they do not establish exhaustive
    actionable-detail retrieval. Unresolved quarantine and audit issues remain.

## Trip scenarios

“Good discovery base” means useful source suggestions, not a fully executable
or independently verified itinerary. “Partial” means some context exists but a
material requested constraint is unsupported. “Gap” means the required evidence
is absent or too weak to claim meaningful coverage. Every scheduled scenario
still requires canonical identities, operational checks and route validation.

| # | Barcelona request | Evidence assessment | What is still needed |
|---:|---|---|---|
| 1 | First visit, three days, landmarks and a relaxed pace | Good discovery base | Identity, actual durations, opening dates, ticket slots, route constraints |
| 2 | Gaudí architecture enthusiast, exterior versus paid interior choices | Good discovery base | Current fees/slots, compare effort and value with attributed opinions |
| 3 | Gothic Quarter history and a walking route | Good discovery base | Canonical stops, complete route geometry, walking time and access conditions |
| 4 | Tapas and traditional Catalan dishes | Good discovery base | Resolve ASR venue/dish names, branch, menu and operation; varied areas and prices |
| 5 | Modern popular restaurants and new openings | Gap | Recent independent/local food sources, operational checks, price bands |
| 6 | Specialty coffee, brunch and quiet work cafés | Gap | Named café pool, actual specialty/work evidence, opening times and Wi-Fi rules |
| 7 | Rooftop drinks for a couple at sunset | Partial | Exact named venue, public access/booking, price, sunset and date-specific availability |
| 8 | Techno, goth or student nightlife | Gap | Specific venue/event/music evidence, admission, age limits, schedule and late return |
| 9 | LGBTQ+ nightlife with suitable atmosphere | Gap | Relevant local/community sources and evidence-backed fit without stereotype inference |
| 10 | Cheap fast food near the hotel at 23:00 | Gap | Broad inventory spatial query, correct branches, menu/price, actual late opening |
| 11 | Vegan or vegetarian food for every meal | Gap | Venue-specific menu evidence and enough alternatives along the trip route |
| 12 | Coeliac or serious nut allergy | Gap | Specific current venue statements and unresolved-risk handling; never infer safety |
| 13 | Halal food or kosher meals | Gap | Appropriate current menu/certification/context sources and spatial alternatives |
| 14 | Family with a toddler, stroller and short attention span | Partial | Stroller access, toilets, effort, nap/meal constraints and age suitability |
| 15 | Parents and a 22-year-old, mixed student/senior tickets | Partial | Eligibility and ticket rules per person, age inputs, group costs and mixed-interest balance |
| 16 | Wheelchair user, step-free transit and accessible toilets | Gap | Verified continuous access chain, venue facilities and current lift/transit information |
| 17 | Senior traveler, low walking tolerance and frequent rests | Partial | Terrain/steps, seated options, actual transfers, rest timing and accessibility detail |
| 18 | Rainy-day plan with indoor alternatives | Partial | Weather-aware alternatives by location, slots and verified opening windows |
| 19 | December 5–9, holidays and seasonal events | Gap | Exact calendar, holiday exceptions, official events and trip-specific availability |
| 20 | Summer beach day with safe swimming and shade | Partial | Current conditions, beach facilities, transport, heat exposure and user needs |
| 21 | Montserrat day trip with a gentle walk | Good discovery base | Current transport/tickets, terrain, weather and feasible return time |
| 22 | Girona, coast or small-town excursion instead of Montserrat | Partial | Comparable current transfers, duration, seasonal conditions and deep local options |
| 23 | Serious hiking with an unfamiliar route | Gap | Official route/terrain/conditions, skill constraints, daylight and return logistics |
| 24 | Art/museum trip with free days and temporary exhibitions | Partial | Correct museum types, exhibition dates, free-entry rules, closure and reservation conditions |
| 25 | Football trip, stadium visit and a match | Partial | Current stadium/tour operation, official fixture/date, ticket availability and transport |
| 26 | Shopping for local design, vintage and independent crafts | Partial | Named shops with current offerings; not just markets and shopping streets |
| 27 | Hotel/apartment choice comparing six user links | Gap | User-supplied listings, exact addresses, current quotes, terms and route comparison |
| 28 | Late arrival, airport transfer and dinner after midnight | Partial | Arrival time, real operator schedules/fare rules, correct airport and open options |
| 29 | Solo traveler asking “is this street safe at night?” | Partial | Narrowly scoped supported context; avoid a neighborhood-wide safety verdict |
| 30 | Repeat visitor rejecting all obvious tourist stops | Gap | Independent/local niche discovery with explicit novelty and exclusion handling |
| 31 | Tight per-person budget including transport and tickets | Partial | Structured current costs, inclusions, eligibility and deterministic group calculations |
| 32 | Add a user video/place, lock a stop, then change trip dates | Source material alone cannot establish this behavior | Provenance-aware imports, canonical mapping, lock-preserving trip overlays and revalidation |

The inventory assessment does not execute these scenarios against the app.
The ready/not-ready conclusion follows missing evidence and unresolved fields;
it is not an invented numerical planner accuracy or fairness score.

## Fairness and source bias

Seven creator groups across 23 videos do not provide 23 independent viewpoints.
Multiple videos by the same creator must not multiply authority. The selected
Greek/English creators support the user's source preferences, but are not a
representative survey of Barcelona residents, languages, cuisines, needs or tastes.
The overview-heavy selection favors landmarks, central districts and tourist food.
Sparse evidence elsewhere must be treated as unknown, not poor quality or absence.

Creator preferences are attributed opinions. A popular recommendation is not
objectively best for every traveler, and a video's views are not a star rating.
Sponsorship and tour promotion need their own evidence and handling; absence of
an extracted disclosure does not establish independence. Republishing/copying
relationships also require review. A protected demographic identity must not be
used to guess preferences: use explicit interests and requested accommodations.

Useful fairness controls are source/publisher independence, source recency,
geographic/cost/style alternatives, minority/niche coverage, reviewable ranking
reasons, explicit unknowns and the ability to include/exclude sources or add a
place. User-country defaults must not silently exclude other languages or local
sources. Lack of video coverage must not hide a usable broad-inventory venue.

## What retrieval and research can fill

Retrieval finds existing evidence. A language model can interpret a request,
rank known candidates and explain supported fit. Neither embeddings nor a stronger
model creates missing source evidence. Model memory is not a current fact source.

The 41,461-entry Overture inventory expands name/geographic candidate retrieval,
including practical chains and fast food. It does not establish recommended
quality, dietary safety, music style, ticket eligibility or live opening times.
Unreviewed name-match proposals must not silently supply a pin or a different branch.

Bounded new research can fill gaps when a permitted adapter can access useful
sources, the budget allows it and results pass the same identity/evidence rules.
Some source access may fail or require manual input; availability cannot be
guaranteed. The generic profile/query planner is implemented, but the complete
semantic coverage → gap research → canonical enrichment → personalized planner
loop has not been implemented and verified end to end. Therefore the current
dataset will not automatically fill itself when the user asks a novel question.

## Efficient next steps

1. **Create one effective review view.** Include the 21 latest video versions and
   two retained pilots with source hashes; keep raw outputs immutable. Retain
   quarantine separately, distinguish source occurrences from canonical entities,
   and carry forward audit/review lineage with valid ID mapping.
2. **Repair known semantics and identity.** Review the wrong dietary/accessibility/
   club/dimension tags, anchored quarantined names and ASR aliases. Resolve places
   with Overture, official identity evidence and geographic/branch constraints.
   Preserve unresolved assertions as research-only, never schedule them by guess.
   Use a human-readable change report and revalidate every promoted claim.
3. **Measure useful city coverage, then add targeted reusable evidence.** Count
   resolved, supported choices by category/style/cost/area, not records or keyword
   hits. Prioritize the observed gaps in coffee, modern food, nightlife and common
   dietary/access requirements. Use permitted focused guides/lists/menu or venue
   information before adding whole generic videos. Continue the user's editable
   source/language controls. Do not invent candidates to hit 500.
4. **Implement bounded request-time gap research.** Compile semantic preferences;
   retrieve canonical city evidence and broad local inventory; check constraint
   coverage; perform only missing research. Do the city/place research once where
   reusable, while exact dates, availability and traveler eligibility remain trip
   overlays. Save provenance and validity windows, deduplicate work, cache/reuse
   results, impose request/owner/global caps and expose unsupported requests.
5. **Verify selected operational facts and validate the plan.** Check official
   hours/holiday exceptions, bookable slots, price terms, ages and access for the
   actual dates. Calculate routes, buffers, duration and costs deterministically.
   Never let an estimated or unknown field appear as confirmed; a proposed ticket
   slot is not a reservation. Preserve user locks and return suitable alternatives.
6. **Run a representative planner evaluation before release.** Turn these
   scenarios into reviewed acceptance cases once retrieval/integration exists.
   Measure unsupported claims, wrong identity/branch, dietary/access constraint
   failures, feasible schedules/costs, diversity, user-lock preservation, fallback
   behavior and new-research cost. Missing evidence must cause a visible partial
   result or targeted research, not a confident fabricated recommendation.

The API extraction cost has been low: approximately $0.73 for the size-based
batch and $0.04 for failed-passage recovery at configured token rates, excluding
earlier pilots, source acquisition, compute, integration and review labor. Low
inference cost does not demonstrate low total curation cost or planner readiness.
The four smaller recovery calls successfully replaced two failed large passages;
adaptive chunk/output sizing is worth retaining. Re-running every video or paying
for more same-source audits is not the best next step: it cannot cure source gaps
or independently verify current facts. Reuse valid work and spend on specific gaps.

Before new paid research, produce the normalized review/canonical diff and a
coverage-driven source shortlist with a per-task reservation. The existing $15
authorization remains a hard shared ceiling; increasing a ceiling is not a target
to spend it all. Current audit adds no paid work.

## Release boundary

An internal research prototype can use attributed recommendations provisionally.
A usable planner release needs correct identities, supported constraints, current
checks on selected stops, validated feasible schedules and successful fallback
behavior. It does not require exhaustive pre-generation of every possible niche.
It does require that unknowns remain unknown and that unsupported interests trigger
bounded research or a clear request for user input. That is the practical completion
target; 100% universal fairness/accuracy is not a meaningful attainable gate.

Machine-readable inventory and gates:
`.local/stage3/sources/barcelona-planner-readiness-audit.json`.
