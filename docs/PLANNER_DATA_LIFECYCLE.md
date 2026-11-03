# Planner data lifecycle and reduced Barcelona completion scope

31 October 2026. Refines the remaining work in BARCELONA_DETAILED_RUNS.md and
BARCELONA_PLANNER_RELEASE_PLAN.md. This is an architecture/work-priority decision,
not implementation, provider approval or a planner-ready release.

## Evidence checkpoint

1 November continuation: expanded review is partially integrated, not merely
queued. Seventy manual comparisons yielded 54 retained claims, 12 repairs and four
held ambiguities. The active private pack has 1,781 source claims and 247 held, with
all 2,028 conserved. Assertion scopes and lifecycles are editorial metadata, not
current-field freshness checks. Twenty source-tag reviews also have explicit scopes;
generic traditions and creator visits cannot establish permanent venue service.
Shared reserved is $9.7357103/$15; no paid inference for this integration.
The following paragraph records the earlier pre-integration checkpoint.

The targeted source review has returned all 40 batches: 313 decisions, 50 supported,
150 repair proposals, 113 unresolved; no missing/invalid output slots. These are
model source comparisons, not canonical or operational approvals. New proposals
have not been integrated into the source materializer.

Of the 113 unresolved occurrences, 67 belong to venue records, 19 districts,
15 city records, seven routes, four dishes and one transport product. Original
dimensions include 56 `other`, 12 `recommendation`, seven `subcategory`, six `vibe`,
five each `neighborhood`, `date`, `dishes`, and additional smaller groups. This is
an occurrence inventory, not an assessment of 113 missing real-world facts. A
dimension label alone cannot determine urgency or lifetime.

Shared reservation: $7.6826339/$15. Targeted task reservation: $1.0869669/$1.25,
including the two timeout reservations. No new inference used for this review.

## Store, refresh, or check per trip

| Information | Durable base | Refresh/check behavior |
|---|---|---|
| Canonical identity, aliases, branch/parent relations, source coordinates, timezone, provider IDs | Reviewed versioned entity, with match evidence | Delta updates, relocation/closure signals; ambiguity blocks scheduling |
| Landmark history, architecture, visit modes, attributed creator details | Evidence-backed facts/observations | Historical statements retained; correct demonstrated errors rather than rewrite on a timer |
| Cuisine, specialty coffee, atmosphere, music context, indoor/outdoor, dishes, reasons to choose/avoid | Facets with evidence, scope and editorial status | Refresh changeable venue features on use or source change; distinguish venue aesthetic from dated music programme |
| Duration, effort, approximate spending | Explicit ranges and estimation basis | Inputs for draft composition; never label heuristics as provider-verified durations or exact prices |
| Opening rules, menus, admission policy, ordinary prices, business status | Reusable permitted observations, plus retrieval references | Field-level refresh for relevant candidates; date exceptions resolved for selected stops |
| Stars /5 | Optional platform-specific timestamped snapshot where storage is permitted | Not essential for admission; no invented score, cross-platform aggregate or guarantee of universal free API coverage |
| Ticket slots, table availability, events, temporary exhibitions, service disruption | Source/provider references and dated observations where allowed | Resolve actual trip dates; short-lived cache, recheck before commitment |
| Weather, beach/route conditions | Optional provider capability | Trip-only; weather remains optional/outside MVP per existing agreement |
| Allergy/coeliac, step-free access, age/eligibility | Scope-specific operator statements and access structure | Strong requirements need appropriate current evidence; a freshness timer or AI agreement cannot establish safety |
| Hotel quotes, bookings, private links/notes, excluded and locked stops | Private trip overlay | Never merged into shared city claims; preserve user ownership and locks |

Even durable identity can change. A refresh deadline is a request to check again,
not a claim that the future is guaranteed. Separate observed_at, checked_at,
effective dates, refresh_after, retention_until and evidence status. Reading cache
does not advance checked_at. Fresh is not verified; old is not necessarily false.

## Deterministic composition contract

1. Resolve user input into typed soft preferences, hard constraints, dates, party,
   anchors, exclusions and locks. AI may propose interpretation; user controls and
   schema validation bind the actual request.
2. Retrieve reviewed candidates using structured facets and spatial queries.
   Apply hard exclusions first, then explicit configurable ranking weights,
   diversity/area coverage and stable tie-breaking. Unknown is a separate state.
3. Build a bounded shortlist and obtain only fields needed to decide feasibility.
   Prefer usable shared cache, then permitted structured provider/feed adapters,
   then monitored source parsers. Unstructured extraction produces proposals.
4. Compose an itinerary using time windows, duration ranges, real route inputs,
   meal/pace buffers, budget estimates and locked stops. Draft and validated are
   distinct states. Distance-derived travel estimates remain estimates.
5. Check selected stops and a bounded backup pool for date-specific constraints.
   Provider failure or missing hard evidence yields pending checks or alternatives,
   not an invented result. Replan affected segments rather than regenerate the city.
6. AI supports new/niche discovery, unstructured extraction and explanations.
   It does not override identity, arithmetic, availability, exclusions or locks.

Identical normalized inputs, evidence snapshot and policy version must reproduce
the same candidate ranking/plan decisions. New observations may legitimately change
plans; retain a trip evidence snapshot and require explicit handling of user locks.

## Provider strategy

Overture remains broad candidate inventory, not live authority. MapKit is an
interactive iOS search/directions candidate under the existing app plan; server
coverage, permitted storage, fields and quota need verification before adapter
adoption. Do not assume it supplies all hours, ratings or booking availability.
Use official operator APIs/feeds and authority transit feeds where available.
No universal free provider for every operational field is assumed. Each adapter
needs a capability matrix, terms/retention, timeout, cost cap and failure behavior.
Public endpoints must not be assumed to be free bulk production infrastructure.

Use a shared refresh queue keyed by canonical entity, field, provider and required
date scope. Coalesce concurrent requests, prioritize selected stops and popular
entities, and retain lineage. Refresh by active demand and source delta rather than
rerun transcript extraction for every city. Reuse data only where terms permit it;
private trip facts stay private.

## Actual remaining priorities

1. Integrate 50 supported and review 150 repair proposals with expanded-context
   lineage. Triage 113 unresolved: required identity/constraint versus optional
   historical detail. Do not force all uncertain transcript fragments into facts.
2. Approve useful canonical entities, structured choice facets and source references.
   Fill demonstrated reusable category/area gaps, not every operational field for
   every inventory entity. Neither 500 records nor source counts are acceptance.
3. Implement provider capability/refresh contracts and deterministic retrieval,
   composition, estimates, validation and fallback. Existing evidence.py is only
   a guard layer; fact_usable currently lacks a complete field refresh policy.
4. Execute supported Barcelona itineraries with stale evidence, provider failure,
   niche requests, mixed needs and locks. Measure substantive outcomes, refresh
   reuse, provider/inference cost and unmet constraints.
5. Freeze the reusable release plus the runtime data contracts. Maintain observations
   separately. Supabase deployment and UI are later integration steps.

The 33 campaigns remain a scenario/evidence checklist. The 11 trip-check campaigns
are primarily adapter and runtime evaluation work; three on-demand campaigns need
bounded fallback behavior; two private campaigns need private flows. They are not
16 mandatory bulk city-generation campaigns. The 17 shared campaigns can combine
source collection and only repeat for demonstrated coverage deficits.

Track canonical matching precision, supported distinct alternatives by scenario/
area, unresolved hard constraints, itinerary violations, warm-cache research calls,
cold-cache checks, cache hit/coalescing rate, stale-field handling and cost per plan.
No accuracy percentage follows from source agreement or unit-test count.
