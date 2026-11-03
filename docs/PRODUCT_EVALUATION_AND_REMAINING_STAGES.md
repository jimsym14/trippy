# Product evaluation and remaining stages — 2 November 2026

The next product milestone is a complete itinerary consumed by the actual app,
evaluated against fixed use cases. The source archive is frozen as research input.
No new global database review is required to begin this milestone.

The offline benchmark has now been implemented and executed. Its 32 profiles,
requested outputs, supported input subsets, measured runtime/output, missing
capabilities and future cost assumptions are versioned. It does not call a model
or provider. Current outputs are partial source drafts, not complete travel guides.

Latest measured artifact:
`.local/stage3/planner-release-v1/product-benchmark-v1/fada1d421dbd1389/benchmark.json`.
Human-readable result: the adjacent `report.md`.

## The fixed use-case matrix

| Family | Concrete cases | Important expected behavior |
| --- | --- | --- |
| Party / travel style | Balanced couple, family with children 6/10, parents + adult 22, relaxed couple, solo low budget, friends/evening bars, returning visitor | Pace, suitable activities, group costs, exclusions and useful alternatives |
| Optional routines | Daily coffee, specialty coffee, coffee + brunch, stay breakfast provided, buy supplies, unknown provision, bakery breakfast | Relevant route/stay choices, correct merging, no unnecessary supermarkets, no invented provision |
| Food/access constraints | Vegetarian, vegan, severe nut allergy, wheelchair access, limited walking | Specific preference handling; explicit missing hard evidence; safe alternatives rather than blanket completion |
| Time / modifications | One-day stopover, late arrival, early departure, locked stop/replan, date change | Arrival/departure anchors, local invalidation, correct transfers and unchanged locks |
| Scale / spending | Seven days, fourteen days, higher budget/quality, group of eight | Variety, realistic cost basis, group reservations and bounded request growth |
| Rich guide | Ticketed sights, Montserrat excursion, dated event/live music, detailed Greek guide | Timed anchors, excursion routes, actual dated evidence, useful source tips/dishes/history and coherent panels/tables/maps |

These are 32 profiles. The current consumer executes only supported fields
(`dates`, activity frequency, stay breakfast, broad unresolved hard requirements,
locks, exclusions and a budget value). Party ages, specific diet descriptions,
arrival/departure, geographic fit, ratings, events, excursions and full-day
sightseeing remain explicit missing capabilities. Their profile metadata is not
silently interpreted as implemented functionality.

## Actual measurements

- 160 offline consumer runs: five repetitions of each profile.
- Warm composition plus compact JSON serialization: p50 about **0.99 ms**,
  p95 about **1.15 ms** on this machine, with the dataset already compiled.
- Source compilation CPU p50: approximately **0.19 seconds**.
- These measurements exclude process startup, disk ingestion, actual network
  providers, complete itinerary composition, UI rendering and human review.
- Current output sizes are roughly 7–31 KB for representative cases; they are
  small because full itinerary and media content is still missing.
- **0/32 full profiles are ready.** This is a product capability result, not a
  finding that every source record is wrong.

Examples: the balanced three-day case produces only four draft stops in total;
the fourteen-day case has fourteen coffee stops, not a fourteen-day guide.
Allergy/access cases preserve the unknown constraints and produce no unsupported
optional stops. That is correct uncertainty handling but insufficient trip output.

## Model cost: measured receipts versus projections

The existing project configuration uses **$0.30 input / $1.00 output per million
tokens**. The calculations below use those rates, with no cached-token discount.

The official OpenAI API pricing page was fetched on 2 November 2026 and lists
standard `gpt-6-luna` at $0.10 input / $0.50 output per million tokens:
<https://developers.openai.com/api/docs/pricing>. That is an OpenAI reference,
not an authenticated quote or invoice for this project's Azure deployment.

Historical local receipts contain 563 unique successful model responses,
7,645,486 input tokens and 1,769,171 output tokens, including 147,621 reasoning
tokens already counted inside output. Recalculation at the current configured
rates is **$4.0628168**, before any applicable cache discount. This is an estimate
for all available project extraction/review receipts; billing was not verified.
The earlier **$13.3432175 reserved** amount is conservative dispatch reservation,
not proof that $13.34 was billed. Failed/unknown dispatches can retain reservations.

Historical successful-call latency: p50 **13.564 seconds**, p95 **40.943 seconds**;
user-visible first-token checkpoint p50 **0.443 seconds**. These exclude failed
calls, timeouts, backoff and queueing, and do not prove that the app streamed tokens.

### Future per-output estimates

The richer prose scenario assumes one optional guide-synthesis call per three
days, plus 0–3 targeted evidence jobs. Guide calls are capped at 8k output tokens;
long trips repeat common input across chunks rather than using an unlimited call.
These are planning assumptions, not executed model outputs or quality results.

| Use case | Model input/output tokens | Model calls | Optional rich synthesis + evidence USD | Deterministic renderer + evidence only USD |
| --- | ---: | ---: | ---: | ---: |
| One-day stopover | 28k / 6k | 2 | 0.0144 | 0.0056 |
| Balanced three days | 36k / 10k | 2 | 0.0208 | 0.0056 |
| Coffee/brunch or stay/supplies | 48k / 12k | 3 | 0.0264 | 0.0112 |
| Allergy/access scenario | 60k / 14k | 4 | 0.0320 | 0.0168 |
| Detailed five-day guide | 68k / 18k | 4 | 0.0384 | 0.0112 |
| Seven days | 88k / 24k | 5 | 0.0504 | 0.0112 |
| Fourteen days | 152k / 44k | 8 | 0.0896 | 0.0168 |

A local filter/map toggle/reformat should cost **$0 model usage**. An optional
single targeted patch with 8k input and 2k output is **$0.0044** at these rates.
The deterministic-renderer column is the preferred architecture direction:
select/validate/compose in code and reuse source details; call Luna only for
missing evidence or a useful explanation. Less model usage does not itself
prove equivalent prose quality; compare those output variants explicitly.

One rich-synthesis output for each of the 32 profiles totals **$0.9232** in model
estimates, or **$1.1540** with a 25% token allowance. This is not a reservation
calculation or permission to bypass the existing shared ledger ceiling.

Equal mix of those profiles, model-only assumptions:

| New trip outputs | Estimate USD | With 25% token allowance USD |
| ---: | ---: | ---: |
| 100 | 2.885 | 3.60625 |
| 1,000 | 28.85 | 36.0625 |
| 10,000 | 288.50 | 360.625 |

Retries, provider/hosting usage and optional rich media are separate. No paid
model/provider calls were executed for this evaluation.

## Provider and infrastructure costs

The benchmark assumes 10–60 unique place details and 4–56 selected route edges,
depending on trip size. These are a request-budget shape, not counts measured
against a provider. Prefer existing basic inventory, deduplicated selected IDs
and nearby candidates; do not request every city business or an unrestricted
N² route matrix. A provider may bill route-matrix elements rather than HTTP calls.

There is no configured Places/Routes SKU price in this campaign, so an actual
connected total is **unknown**, not $0. The formula is:

```text
total = model tokens
      + billable place/search units × their unit rate
      + billable route units × their unit rate
      + optional media/search units
      + allocated hosting/storage/egress
```

For the three-day assumption (20 place details + 12 route edges), a deliberately
generic provider-rate sensitivity gives:

| Assumed uniform rate per 1,000 units | Provider component | Plus balanced-trip model estimate |
| ---: | ---: | ---: |
| $0 | $0.000 | $0.0208 |
| $1 | $0.032 | $0.0528 |
| $5 | $0.160 | $0.1808 |
| $10 | $0.320 | $0.3408 |

These are sensitivity assumptions, not Google/Apple/other provider quotes.
Native MapKit search already exists in the app; it is not automatically a free
backend place inventory or ratings feed. Use it where appropriate to the actual
client flow. Confirm provider choice/pricing before a connected benchmark.

Storage currently measured locally: basic catalog SQLite ~105 MB, editorial
SQLite ~15.6 MB, compiled discovery SQLite ~13.6 MB, and before/after compile JSON
~18.4 MB. These are local SQLite/file sizes, not PostgreSQL capacity measurements.
Production trips must reference shared dataset versions rather than duplicate
the entire archive into every trip/campaign. Keep media as references with rights
metadata; images/egress need a separate measured capacity budget.

## How full output will be judged

Every profile includes two concrete `expected_output_assertions` in the scenario
manifest. Examples include preserving sightseeing despite missing dietary meal
evidence, not charging child prices for an adult aged 22, respecting a 07:00
departure, and grouping supply shopping without daily duplicates. Proposed
targets are model estimates below $0.05 for typical three-day outputs, below
$0.15 for long fourteen-day outputs, and a typical three-day end-to-end target
of 90 seconds. These are acceptance targets, not measured connected results;
provider/hosting rates remain separate.

Automatic hard gates: correct identity/branch, no ignored hard constraint, no
changed lock, no schedule overlap under supplied route assumptions, no invented
price/rating/availability, preserved provenance and explicit unknowns.

Manual output rubric: relevance to party, geographical sequence, useful source
details, alternatives and completeness against `chat.md`. Score each 0–2;
target at least 8/10 with no hard failure. No human score has been invented for
the current partial outputs. This rubric compares two future variants:
deterministic structured guide versus optional Luna prose synthesis.

Measure first meaningful output, complete output, p50/p95 end-to-end latency,
timeouts/retries, physical and billable API units, token usage, selected-place
cache reuse, bytes returned, and peak memory. The current 1ms consumer measurement
is not the end-to-end latency target.

First acceptance sequence: full balanced three-day case → targeted correction →
coffee/brunch + stay/supplies cases → run all 32 profiles and report unsupported
niche capabilities without resetting global source curation. Allergy/access
constraints must stay visibly unresolved where providers cannot establish them.

## What remains from the original large stages

| Original stage | What exists | What remains / exit gate |
| --- | --- | --- |
| 0 — Baseline/config | Local configuration and source/provider audit | Recheck actual connected capabilities where enabled |
| 1 — Data model/migrations | Local typed model, migrations, import compatibility | Apply and verify connected DB; migrate actual client state without losing trips |
| 2 — Backend/Auth/jobs | Local `/v2`, ownership/revisions, jobs/budgets with fake-provider checks | Real Supabase login/RLS, provider worker integration, replace legacy bridge path |
| 3 — Catalog/source archive | 41,461 basic entities, conserved video research edition, source reader | Scenario shortlist identity/typed discovery admission; practical gaps only |
| 4 — Preferences/compiler | Research/query configurations and optional-activity prototype | Full trip context: party/ages, pace, history, interests, budget basis, specific diet, shared manual/automatic compiler |
| 5 — Central map search/save | Existing MapKit calls in the app | One catalog-first search/select/save service, exact result/branch, private save/add-to-slot and duplicate handling |
| 6 — Planner/live checks | Source draft, constraint guards, receipts | Full itinerary composer, geographical grouping, route/field adapters, permitted rating snapshots, delta replan and measured connected benchmark |
| 7 — iOS workspace/redesign | Existing app plus written minimal design direction | Actual UI consuming the new contracts, optional setup, Plan/Map/Places/Costs, layers/panels/tables/images, compare/select/lock/undo and progressive/reconnect state |
| 8 — Admin/rollout | Local catalog publishing and backend building blocks | Coverage/source/cost admin, publish/rollback, real connected isolation/capacity checks, deployment configuration and beta verification |

The data-model redesign foundation is already local; do not restart that work.
The visible UI redesign and client integration are still pending. Preserve the
existing minimal direction/layout, but implement real decisions, maps and panels
against one shared output contract before visual polish. Media references need
real assets/attribution; exporting a JSON panel is not completing an image UI.

## Execution order from here

1. **One complete consumer path:** stages 4 + 6, with stage-3 shortlist joins and
   a single provider adapter path. Use the frozen source archive and the 32-case
   specification. Produce a complete three-day output before further database passes.
2. **One real app path:** stages 5 + 7. Brief → generated workspace → map/filter
   → replace a stop → lock/undo → Costs. Redesign uses the same consumer contract.
3. **Connected runtime:** finish stage-1/2 real DB/Auth/RLS/worker verification,
   private state migration and client wiring before a beta. This can progress
   alongside UI work once the consumer contract is fixed.
4. **Rollout:** stage 8, actual deployment/capacity/cost verification, admin and
   rollback. New cities/events/exhaustive enrichment are separate scope after
   the Barcelona pilot, not prerequisites for validating this path.

The next progress claim must cite an actual complete consumer/app flow and its
benchmark. Passing source-retention or synthetic behavior tests alone cannot
close stages 4–7.

## Reproduce the offline baseline

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-product-benchmark.sh
```

The launcher requires `caffeinate -i -s`. It creates a new immutable timing result
because timings naturally vary. It does not reopen source curation or spend the
AI budget. Cost calculations have separate tests for decimals, unknown provider
prices, repeated usage, reasoning-token accounting and long-output chunk limits.
