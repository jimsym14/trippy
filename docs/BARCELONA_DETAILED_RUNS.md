# Barcelona detailed runs

Next executable work: [Barcelona unattended runs](BARCELONA_UNATTENDED_RUNS.md),
114 bounded source-annotation calls with a $5 additional cap from the same ledger.
Do not add this cap to all earlier provisional pools; it is the next allocation.

Latest checkpoint: targeted run completed all 313 decisions (50 supported, 150
repair proposals, 113 unresolved). Shared reserved $7.6826339/$15; targeted task
$1.0869669/$1.25, including two timeout reservations. Earlier preparation/launch
notes below are historical. Remaining scope is refined in
[Planner data lifecycle](PLANNER_DATA_LIFECYCLE.md): runtime checks are not mandatory
bulk city enrichment campaigns, and new model proposals still require integration.

31 October 2026. Continues the [release journal](BARCELONA_PLANNER_RELEASE_PLAN.md)
under the user's existing shared $15 cap, Luna only. Runs have explicit inputs,
source evidence, budget pools, dependencies and completion gates. No universal
correctness or coverage promise follows from executing a number of calls.

| Work | First execution / input | Additional reservation pool |
|---|---|---:|
| Source adjudication | 313 held claims: 168 proposals and 145 unresolved; 40 calls, up to eight claims each, expanded original transcript context | $1.25 |
| Canonical identities | Branch/alias/parent/entrance verification from reviewed source entities and broad inventory; independent source admission | $1.00 |
| Shared coverage | 17 campaigns for reusable landmark/food/coffee/nightlife/dietary/access/local-selection evidence | $3.00 total |
| Trip and private contracts | 11 selected-trip campaigns, three on-demand campaigns, two private-input campaigns | $1.00 total |
| Scenario execution | Actual retrieval/route/cost/control behavior for 32 families, 38 baseline query variants | $1.00 |

These are pooled additional reservation ceilings, not a fresh allowance per category
or per user. Current shared reservation is $6.5956670; the allocated additional
$7.25 projects $13.8456670, leaving $1.1543330 unallocated within the same $15 cap.
Earlier reservations, including failed calls, remain in the original ledger.
Current returned-usage estimate is $2.2257446 at configured rates, not an invoice.

## First ready run

Recipe: `configs/source_research/barcelona-detailed-runs-v1.json`.
Active prepared output: `.local/stage3/planner-release-v1/targeted-adjudication-ai-v2/`.
All 313 entries bind the upstream claim/context and retain the prior proposal as
untrusted input. Six neighboring cues on each side of original/name/proposed
citations provide larger context. The new provider schema requires every claim's
own slot and restricts evidence IDs to that entry's source cues. Evidence enums are
shared across decision alternatives to avoid duplication, with conservative schema
resource guards checked before dispatch. The first unused preparation remains
preserved in the v1 directory; no model request was dispatched for that version.

Prepared **40 calls**, 5,000 output-token ceiling per call. Full conservative
reservation **$1.0356563**, below the $1.25 task pool. Separate request group
`barcelona-targeted-adjudication-v1` uses the same original shared ledger, not a reset.
Default extraction/review behavior remains compatible. Caffeinate, duplicate-runner
lock, 15-second heartbeat, cache recovery, 240-second provider wait, 300-second worker
deadline and zero hidden SDK retries are retained. Model decisions remain proposals;
expanded-context dispositions are not automatically treated as manual repairs or
canonical/current facts. Downstream adjudication must preserve context lineage.

Run from Terminal:

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-detailed-runs.sh
```

The agent's single-pilot attempt was blocked **before execution** by automatic
approval service HTTP 404 deployment-not-found. This was a review-service failure,
not a finding that the action was unsafe or a failed Luna dispatch. No new request
or reservation was created. Agent execution cannot bypass the approval service;
the local launcher is the available execution path. The new v2 schema is prepared
and locally validated but has not yet received a successful paid provider response.

## Coverage runs and iteration rules

`campaigns-v1/campaigns.json` records 33 distinct coverage jobs linked to all
32 scenario families, with queries, Greek/English discovery controls, primary-source
languages, evidence criteria and scope. These are research work orders; only the
source-adjudication launcher is currently executable as a paid batch. Source
collection, canonical admission and planner integration remain substantive work.

Each coverage job starts with one discovery wave, then at most two targeted waves
for a measured gap under its pooled budget. Never repeat a whole extraction because
a particular field is missing. When a wave adds no useful evidence, change the
source/query rather than spending on an identical rerun. Source counts and lexical
matches cannot certify suitable options or a completed scenario. More sources can
be collected manually; paid inference remains budgeted and explicit.

Reusable city facts are stored once with provenance and freshness. Nearby niche
requests use spatial inventory plus targeted new sources. Slots, events, weather,
transfers and eligibility are selected-trip checks. Hotel quotes, personal source
links, preferences and locked stops are private trip overlays. Do not fabricate
shared-city facts from private inputs or fixture dates.

## New source collection already performed

Opened four operator pages and saved seven branch-scoped observations in
`campaigns-v1/primary-observations-wave1.json`, with short exact excerpts/source-line
receipts. Subjects: three NOMAD branches, two Messié branches, Elvira and Velada.
These are seven observations, not seven independently recommended or canonical
new places. They add specialty-coffee, vegan-food, gluten-free-operator and dark-bar
context without additional Luna inference.

NOMAD's rendered addresses join number/postcode and remain unparsed until identity
verification; no laptop permission is inferred. Messié's gluten-free/cross-
contamination assertions remain operator claims, not independently checked
certification or all-allergen safety. Testimonials never become aggregate stars.
Elvira's dark décor supports aesthetic fit, not goth-music programming; office hours
are separate from bar hours. Velada's gluten-free alternatives do not prove a
dedicated coeliac-safe kitchen. Exact-date availability stays unchecked throughout.

Unplug returned HTTP 403 and Rasoterra HTTP 502 on primary-page access. Their search
hits remain discovery leads; failure to fetch is not evidence of closure or poor
quality. Third-party conflicting café work policies and old certification lists
were not promoted to current primary facts. No blanket dietary/accessibility/rating
approvals, Supabase writes or readiness flags were created.
