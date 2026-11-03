# Measured source-led curation

Updated 31 October 2026. This is the active private Barcelona curation workflow,
after the completed video batch. Quality takes priority over minimizing inference
cost. The existing shared $15 budget and Luna-only preference remain in force;
this local curation recipe makes no paid model requests.

The subsequent [planner release plan](BARCELONA_PLANNER_RELEASE_PLAN.md) extends
this workflow with an exhaustive Luna review, source gap observations, a typed
knowledge interface and deterministic selected-trip guards. Its execution journal
records current progress and the network/approval-service blocker. The original
curation cycles and measurements below remain historical reproducible receipts.

## Actual result

The effective source pack remains **549 records from 23 videos / seven publisher
groups**. These are research occurrences, not 549 unique verified venues.
Baseline: 2,026 claims. Corrected pack: **2,028 claims**, because two bundles were
split; this increase is not two new independently verified facts.

Three successive editorial passes produced **31 content-bound decisions**:
19 initial corrections, nine corrections/evidence additions, and three safety-field corrections.
All retained transcript citations pass exact quote, timing and name checks.
This validates evidence linkage, not exhaustive recall or factual truth.

| Diagnostic | Baseline | Current | Interpretation |
|---|---:|---:|---|
| Accessibility claims | 9 | 1 | Free entry, shoes, security and historical closures separated |
| Dietary claims | 1 | 0 | Diluting vermouth is a drink detail, not a dietary restriction |
| Opening-hours claims | 14 | 2 | Transport, city mealtimes, historical closure and queues separated |
| Ticket claims | 35 | 33 | Personal 14:45 deadline and tour programme are not ticket rules |
| Safety claims | 65 | 62 | Viewpoint features and recommendations do not establish hazards |
| Uncertain-identity records | 297 | 297 | Lexical matching alone clears no transcript identity |

The second pass adds original adjacent cues for interiors/sell-out advice and a
Montserrat queue statement. The latter now identifies the queue to see the
Virgin rather than a general basilica schedule. Original quotes and outputs remain.
The safety pass separates a free viewpoint, a cultural-center recommendation and
an ambiguous Greek request to look carefully at a view from actual safety evidence.

There are **24 reviewed external observations from 21 page URLs** covering coffee,
food, nightlife, core sights and access limitations. Exact source-specific excerpt
checks are in `.local/stage3/sources/barcelona-primary-research-receipts-v2.json`.
Eight web calls included 12 queries, 21 opens, one click and six finds. An opened
JavaScript ticket shell counts as retrieval effort, not verified ticket information.

Read-only matching examined **41,461 catalog snapshots**. Twenty-one observations
have candidates; three do not. Three groups were truncated at 12 candidates.
Nine groups contain a conflicting-address alternative; that is not nine confirmed
real-world source conflicts. Explicit review linked **seven source observations**
to catalog identities and rejected **eleven observation/candidate pairs**.
Coordinates, entrances, transcript aliases, current operation, fit and publication
are still pending. These are source links, not seven planner-ready places.

Three Marks' two schedules, Aguaribay's operator/catalog addresses and alternate
Sagrada Família snapshots remain unresolved. A gift shop sharing the basilica's
address is rejected as its identity. Event programmes, internal museums and
room-specific entrances remain distinct subjects.

## Reproduce the local cycle

Run from the project directory:

```sh
.venv/bin/python -m trippy.sources.curation_pipeline \
  --recipe configs/source_research/barcelona-curation-recipe.json
```

The command validates the effective replacement-version source pack, computes
the baseline, applies corrections, proposes catalog matches, applies reviewed
identity decisions and generates a quality queue. It prints every stage and writes
a timing receipt for each execution. Web discovery and model extraction are
reviewed inputs, not performed by this command.

Two executions of the latest recipe took **1.98 and 1.90 seconds**, producing the same report hash
with **zero paid model requests and zero catalog writes**. Those times measure
local replay, not editorial/source review or total research compute cost.

Current report:
`.local/stage3/curation/barcelona/2e886549029361f9/pipeline-report-f54a6242e1f107a8.json`.
Explicit catalog city/version IDs and engine/input/decision hashes preserve
reproducibility. Identical inputs reuse immutable artifacts.

For another city, provide its effective inputs, original evidence, coverage
profile, observations, editorial decisions and exact catalog geography/version.
Do not copy Barcelona identity decisions: they are bound to source and candidate
fingerprints. Source review and planner integration are not yet unattended.

## Remaining work and iteration rules

The queue contains **980 tasks**: 549 exhaustive source reviews, 398 transcript
identity reviews and 33 intent/runtime contracts. Tasks overlap by record; they
are not 980 errors or API calls. **80 source records** contain critical access,
safety, schedule, ticket or price fields and receive priority. Review inventories
from 22 effective upstream documents remain linked by path/hash; entries may overlap.

The 33 configurable cells extend the [32 scenarios](BARCELONA_PLANNER_READINESS_AUDIT.md):
17 shared city evidence areas, three on-demand needs, eleven selected-trip checks
and two private planner behaviors. Candidate counts are lexical diagnostics;
an apparent empty Montserrat cell does not establish absent Montserrat knowledge.

1. Compare critical claims with complete source context. Correct subject, time,
   negation and cue completions; retain unresolved details without guessing places.
2. Resolve canonical venue/branch, coordinate/entrance and parent/subvenue/event
   relationships. Review multilingual names and quarantine dispositions explicitly.
3. Expand weak shared areas through varied independent/local discovery, followed
   by primary field checks. Measure distinct suitable options across location,
   price, effort and preferences; quotas and source counts cannot prove quality.
4. Execute planner scenarios after retrieval integration: access chains, dietary
   coverage, mixed-age costs, timing, alternatives, private imports and locks.
5. Promote only passing fields/identities; date and recheck volatile facts.

Reuse stable shared evidence. Check exact slots, availability, eligibility,
prices, lift status and date exceptions for the selected trip. Nearby fast food
and unusual musical tastes require spatial/on-demand discovery. Personal notes,
hotel quotes and locked choices remain private trip overlays.

Each cycle must record supported additions, resolved/rejected identities,
unresolved conflicts, quarantine dispositions, distinct relevant options,
source independence, reviewed sample errors/omissions, provider usage and reuse.
When a pass adds no quality, change source or method rather than repeating
identical paid extraction. A paid run must fit the existing shared budget.

Acceptance means reviewed scoped scenarios pass with supported alternatives,
explicit unknowns and no known critical defects. Universal perfection, exhaustive
niche coverage and 100% fairness cannot be established by counts. **Publication
and complete planner readiness remain false.** No ratings were invented.

Validation: **212 Python tests pass**; real recipe replay produces identical results.

### Exhaustive review response recovery, 31 October 2026

See [release journal](BARCELONA_PLANNER_RELEASE_PLAN.md) for the active continuation.
`semantic_review` v2 uses conditional supported/repair/unresolved schemas. Before
dispatch, it recovers saved candidates without provider calls, preserves raw
responses and records stripped echoes or quarantined implicit edits. Strict keyed
coverage and same-source evidence validation still apply. Cache replay derives
recovery from the bound raw response and rejects edited recovered decisions.
An explicit `--adopt-from` compares full prompt/input before reusing a response
across a versioned schema change; old artifacts and shared reservations remain.
The first 25 claims also have a separate content-bound agent source-comparison
artifact. It is pending release integration, not independent fact approval.
Current whole-suite validation: **231 tests pass**. The remaining 81 model calls,
source/identity/coverage checks and actual planner scenarios remain unfinished.

Follow-up: v3 requires one keyed output slot per input. Partial responses retain
valid decisions and queue omitted or invalid per-claim evidence as not-reviewed
research-only markers. Raw invalid decisions are retained; placeholders cannot
approve semantic facts or make review completion true. Batch progress continues
through unrelated claims; targeted review still needs completion. Two saved calls
were recovered offline; 80 calls remain. **233 tests pass** at this checkpoint.

Final source-pass continuation: all 82 batches returned. Reusable offline
`semantic_resolution` binds manual targeted decisions to the complete worklist,
claim/context and cached raw response lineage. Forty-three queue items received
explicit source dispositions without paid inference; nine remain unresolved
underlying subjects/context. Effective output has 213 repair proposals and 159
unresolved dispositions, all retained for adjudication. No repair is silently applied
and no readiness gate follows from finishing a review count. **237 tests pass**.

### Materialization of adjudicated source claims

`semantic_materialize --recipe configs/source_research/barcelona-source-adjudication-v1.json`
builds a private immutable version from the source pack, bound review dispositions
and explicit manual decisions. Apply only source-compared repairs. Retain supported
originals, hold unresolved claims/model proposals outside active source facts,
preserve before/after evidence and claim counts, and export occurrence mappings and
per-claim scopes. New citations are exact original same-video cues. No source name,
identity, ratings or current-fact approvals are generated. Replaying the recipe is
offline and immutable; stale/foreign/duplicate decisions fail.

Latest measured state: 99 manual adjudications, 27 source repairs applied, 1,715
active source claims, 168 proposals pending and 145 unresolved claims held; all
2,028 claims preserved across active/held inventories. Thirty-one priority proposals
were directly checked: 15 repairs, 12 retained originals, four unresolved. This is
a selected review group, not a global repair-precision or fairness score.
**240 tests pass.** Gap discovery, canonical fields and planner scenarios remain open.
