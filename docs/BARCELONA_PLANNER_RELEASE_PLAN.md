# Barcelona planner-ready release plan

31 October 2026. This continues the acquisition, transcription, extraction,
recovery and three curation cycles documented in [curation automation](CURATION_AUTOMATION.md).
User authorizes necessary paid inference within the existing **$15 USD total cap**.
Luna remains the paid model; manual primary-source checks resolve ambiguity.

## Budget at start

The shared ledger has 120 requests, **$4.1655221 reserved** and **$1.4360861 in
configured-rate usage estimates** from 116 recorded responses. Four requests lack
complete usage receipts; reservations are retained. These values are not invoices.
Remaining conservative allowance: **$10.8344779**. Configured Azure rates are
$0.30/M input and $1.00/M completion tokens, including non-visible output.
[OpenAI token accounting](https://developers.openai.com/api/docs/guides/token-counting)
explains why completion limits and usage include more than visible response text.

| Task | Additional reservation ceiling | Method |
|---|---:|---|
| Exhaustive retained-claim semantic review | $3 | Luna checks every claim against supplied transcript context; explicit unresolved state |
| Identity resolution | $1 | Luna-assisted aliases/candidate triage, then authoritative branch/location checks |
| Gap evidence and normalization | $3 | Focused source research, small cited normalization requests, manual conflict resolution |
| Scenario evaluation and repair | $1 | Deterministic checks plus bounded Luna critique; no self-certified truth |
| Unallocated recovery allowance | $2.8344779 | Used only after measuring failed/missing work |

Working additional inference estimate: **$1.50–$4**, dependent on unresolved cases.
The eight-dollar planned reservation allowance makes a **$12.1655221 shared ceiling**,
not a promise that completion costs exactly that amount. Every call reserves before
dispatch, uses the existing ledger and retains uncertain reservations on failure.
No ledger reset, hidden retries, stronger-model fallback or blanket video rerun.

## Release work

1. **Semantic review.** Account for all 2,028 retained claim occurrences against
   their original source context. Preserve raw evidence and editorial lineage;
   repair incomplete citation context, wrong dimension, subject, time or negation.
   Unsupported claims stay research-only. Review quarantine separately; rejected
   proposals are accounted for rather than made into places by inference.
2. **Canonical identities.** Resolve multilingual names, branches, chain versus
   venue, programme versus event, museum versus internal room, and entrances.
   Use Overture as candidate inventory, not factual authority for every field.
   Conflicting or unlocated identities cannot be scheduled. Retain valid unnamed
   details as contextual research. New verified venues need not exist in Overture.
3. **Coverage and source checks.** Establish distinct useful alternatives for the
   33 coverage cells and 32 scenario families. Prioritize modern food, coffee,
   nightlife, dietary/access needs and non-central practical options. Primary
   pages support operational fields; independent local/creator sources support
   selection/taste. Do not invent ratings or pad the earlier 500 target.
4. **Planner data contract and retrieval.** Publish a private versioned release
   artifact with separate canonical entities, attributed observations, editorial
   fit facets and field freshness. Retrieval must use supported facets, preserve
   user exclusions and locks, and fall back to broader inventory or targeted
   research for unknown niche/spatial needs. Unknown is not false or a poor rating.
5. **Trip checks and scenario execution.** Verify selected dates, entrances,
   routes, duration estimates, age/eligibility, prices and access chains. Execute
   cases for all scenario families with substantive outputs, not lexical counters.
   Validate multiple alternatives, geography/effort, cost calculations, private
   imports and lock preservation. Unresolved hard constraints cause a visible
   research/check requirement, never a confident schedule.
6. **Freeze a release and record results.** Produce the change manifest, rejected
   and unresolved inventories, field provenance, executed evaluation, usage/cost
   receipts and reproducible city recipe. Release only after actual gates pass.
   Remote publication/UI remain separate deployment stages unless required by the
   planner integration; local review artifacts alone are not a deployed planner.

## Acceptance boundary

Planner-ready means the approved dataset and retrieval/checking behavior support
defined scenario families with no known critical violations, reliable provenance,
useful alternatives and explicit missing-information handling. A single seed cannot
precompute every date, venue change, weather condition or unusual preference.
Historical creator prices and broad opinions never become current operational facts.

The frozen version will not be silently rewritten. New facts are refresh overlays
or a new release; obsolete hours, prices and events still require maintenance.
This is the practical way to avoid repeatedly correcting the same extraction while
keeping future trips accurate. No promise of permanent real-world correctness.

## Automation and progress record

Each stage records input/prompt/schema hashes, individual decisions, exact cited
source IDs, rejected/unresolved output, calls, reservations, observed tokens,
cache reuse, elapsed time and the release gate it affects. Source completeness,
semantic support, identity, freshness, diversity and planner feasibility are measured
separately. Same-source model agreement is not independent fact checking.

Active artifacts live in `.local/stage3/planner-release-v1/`; status and calls are
checkpointed. This document will be updated with completed work and actual costs.

## Execution journal — first release stage

1. Read the existing ledger and effective curation artifacts; preserved the earlier
   $15 cap and 120-request history. No old extraction was rerun.
2. Implemented an exhaustive source-bound semantic reviewer: every claim has a
   unique content-bound key, original cues and neighboring subject context. The
   model can propose supported/repair/unresolved dispositions but cannot approve
   independent truth or current availability. Missing, duplicate, fabricated and
   cross-source dispositions fail validation. Original source quotations are not
   generated by the reviewer.
3. Prepared **82 calls / 2,028 claim occurrences**. Repeated cue context was
   deduplicated without dropping evidence: reservation fell from $3.1796084 to
   **$2.1762563**, below the $3 semantic allocation.
4. Attempted one sandbox pilot. It failed with `APIConnectionError`, returned no
   response and retained **$0.0363857**. Network-enabled launch was then blocked
   before execution by automatic approval service HTTP 404 deployment-not-found.
   This is an approval service failure, not a safety rejection or a second model
   dispatch. Current shared reservation: **$4.2019078**. No additional returned
   token-usage receipt exists; actual billing for the failed connection is unknown.
5. Prepared `.local/stage3/run-barcelona-planner-release.sh`. It keeps the machine
   awake during execution, resumes validated caches, prints 15-second waiting
   heartbeats, saves progress after each call, and rejects duplicate runners.
   An asynchronous request asks the user to start it locally because the agent
   cannot bypass the failed network approval check.
6. Added **eight primary observations** with exact source-specific short-excerpt
   receipts, bringing the private knowledge input to **32 observations**. Subjects
   include Bagués public rooftop versus hotel pool access, Royal 83.3 terrace,
   CELTA weekday work versus weekend music, Jacqueline meat-service certification
   scope, Xerta limited-date kosher dinners, Chabad centre versus shops and its
   dated FAQ, and Maritime Museum entrance/timetable/subvenue rules. These are
   source observations, not eight canonical admissions or verified current bookings.
7. Implemented a versioned private knowledge contract and authenticated
   `/v2/planner/knowledge/search` endpoint (factory injection; not deployed).
   Diagnostic coverage cells never become approved fit facets automatically.
   Historical/conflicting/unknown fields cannot satisfy hard requirements. Snapshot
   readiness metadata cannot bypass incomplete canonical/release gates.
8. Implemented deterministic selected-stop guards for scoped and dated evidence,
   local timezone, exact visit windows, entrances, verified price provenance,
   party costs, route evidence, step-free transfers, unknown access, user locks and
   empty plans. Passing synthetic tests is not an actual Barcelona itinerary.
9. Converted the 32 scenario families into **38 query variants** and executed them
   against the current private knowledge snapshot. All 32 families still require
   evidence or integration; **zero complete itineraries were executed**. This is a
   reproducible baseline rather than a fabricated planner success score.

Current snapshots: `knowledge-source-v2.json`, `scenario-baseline-v1.json`,
`progress-v1.json`, `primary-gap-observations-v1.json`, `primary-gap-receipts-v1.json`,
and the retained original `semantic/prepared.json` / `semantic/status.json` in the active artifact folder.
Canonical identity/entrance admission, source-compared fit facets, deeper diverse
selection, operational checks, runtime research and end-to-end itinerary evaluation
remain open. The dataset is **not planner-ready** and is not remotely published.

Verification at this checkpoint: **225 Python tests pass**, `git diff --check`
passes, and the launcher passes shell syntax validation. These validate the code
and fail-closed behavior; they do not approve the unfinished dataset. No paid
semantic-review response had returned at that checkpoint.

## Execution journal — saved-response recovery and conditional schema

1. The user locally launched the reviewer; request 122 returned 25 decisions,
   then validation stopped on non-null replacement fields on non-repair actions.
   Its 29,771 input / 4,076 completion tokens give **$0.0130073** at configured
   rates. Shared reservation is **$4.2382935**; all 117 recorded receipts total
   **$1.4490934** at configured rates. Neither value is an invoice.
2. Added audited offline recovery before any provider dispatch or `max_calls`
   check. Raw candidate files are immutable. Exact echoes are discarded; differing
   fields on supported decisions become unresolved/research-only proposals.
   Missing/duplicate keys, foreign cues and unresolved promotion still fail.
   Recovered caches are re-derived from their bound raw responses on replay;
   recovery events retain the original suggestions and entry hashes.
3. Recovered the first response with **zero paid calls**: three explicit repair
   proposals, 20 quarantined implicit repairs and two original unresolved claims.
   All 25 are accounted for, but this is not approval of their semantics or facts.
4. Versioned the provider schema to three conditional decision alternatives.
   Supported/unresolved replacement fields must be null; repair fields are required
   and non-null; unresolved scope must be research-only. This prevents the observed
   protocol error in schema-conforming future responses. Invalid responses still
   stop rather than retry automatically. Azure schema acceptance is pending the
   next returned call; no successful v2 paid request has been claimed.
5. Active artifacts are now `semantic-v2/prepared.json` and `semantic-v2/status.json`.
   The previous manifest/raw response/cache remain intact. Explicit migration compares
   the complete input and prompt and records both manifest and candidate hashes.
   The first response is reused, leaving **81 provider calls**. Full v2 preparation
   reservation ceiling is **$2.2161821**, below the $3 task allocation. The same
   request group and shared ledger count prior failed/returned requests toward caps.
6. Compared all first-batch source cues manually as the coding agent. Saved
   `manual-source-review-first-batch-v1.json`: 20 source-supported proposals,
   one repair removing an unsupported physical-force description, four unresolved
   subject/ASR cases. Ambiguous transit products/currency stay research context;
   historical prices and machine-specific rules cannot satisfy current constraints.
   Source-comparison decisions are not independent fact checks and are not yet
   applied to the release. Original data remains unchanged.
7. Attempted one network-enabled resumed call. Automatic approval review returned
   HTTP 404 deployment-not-found **before execution**. No new paid request or
   reservation was made. The agent cannot bypass this approval failure; the user
   can resume the corrected caffeinated launcher locally, without resetting progress.

Recovery/schema/migration tests cover zero-call replay, unchanged raw data, content
binding, tampered cache/input rejection and promotion/evidence guards. Planner
readiness remains false; the release stages above still require substantive work.
Verification after the recovery/schema change: **231 Python tests pass**,
`git diff --check` passes and the launcher passes `zsh -n`.

## Execution journal — partial second response, required keyed slots

The user's next local run reached batch 2 and returned request 123. It contained
21 decisions for 25 inputs, with no duplicate or unknown keys. Four decisions were
omitted; two returned decisions cited context outside their own supplied claim
windows (one discussed house wine under a passport-safety claim). The old whole-
response validator stopped the runner. Connectivity and the budget were working.

Recovery now retains the 19 valid decisions, preserving the immutable raw response.
Four omissions and two invalid evidence decisions receive explicit research-only
quarantine markers with **not-reviewed** approval, original entry hashes and retained
invalid suggestions. These markers do not count as received valid source reviews,
cannot approve planner facts and keep completion false until targeted review occurs.
The runner continues unrelated chunks rather than paying to rerun a complete batch.
Unknown/duplicate identity mappings still reject, as do tampered recovered caches.

Provider schema v3 uses one required object slot per claim ID, rather than a variable
length array; the model supplies no separate inner ID. Every required slot retains
the supported/repair/unresolved field constraints. Original prompt and payload are
unchanged and saved candidates from v2 are adopted by exact input/prompt comparison.
Active root is `semantic-v3`; both earlier roots and ledger history remain preserved.
Full prepared reservation ceiling is $2.3707235, below the $3 task cap, and saved
responses consume no new reservation. **80 provider calls remain**, starting at 3/82.
The v3 schema has not yet been exercised by a returned paid call.

After offline recovery: 50 claims accounted for, 44 returned source reviews, six
missing/invalid reviews queued, zero new API calls. Raw first-call protocol conflicts
and explicit repairs still require substantive release integration/review.
Request 123's configured-rate estimate is $0.0127103; all recorded receipts total
$1.4618037. Shared reserved amount is $4.2737375 / $15. These are not invoices.
The CLI now prints readable progress and failure summaries; detailed keyed queues
remain in `status.json`. No release readiness gate is enabled by recovery.
Verification: **233 tests pass**, `git diff --check` passes, and launcher shell
syntax passes. Offline replay recovered both saved responses without provider calls.

## Execution journal — batch 76 provider timeout

The local v3 run returned batches 3–75 successfully (73 new responses). Batch 76,
request 197, hit the SDK's 120-second `APITimeoutError`. It has no local raw response,
candidate or usage receipt; its $0.0273344 reservation remains. The cache contains
75 completed batches, 1,875 accounted claims, 1,833 received valid source reviews,
four omitted and 38 invalid reviews queued. Source-review actions: 1,497 supported,
191 repair proposals, 187 unresolved. These are not current-fact/canonical approvals.

Only seven batches / 153 input claims remain for this retained-claim pass. Resuming
uses all 75 caches and attempts batch 76 again. It does not repeat video extraction.
Semantic transport now allows 240 seconds at the SDK and 300 seconds at the outer
worker deadline, with 15-second heartbeats, zero SDK retries and existing caps.
Other extraction transport defaults remain 120 seconds. Timeout validation is finite
and bounded; tests assert the semantic override reaches the client with retries off.
Prompt/schema/input fingerprints are unchanged, so saved v3 results stay compatible.

Current shared reservation: $6.4070865 / $15. Current semantic-task reservation:
$2.2415644 / $3. Remaining seven requests reserve $0.1885805 including the new batch
76 attempt, projecting $6.5956670 shared and $2.4301449 task reservations if successful.
All 191 recorded usage receipts give a configured-rate estimate of $2.1682152;
the timeout lacks billing confirmation. No additional AI call was made by this fix.
After the pass, the missing/invalid review queue, repairs, identities, current facts
and planner scenario gates still require completion. Planner readiness remains false.
Verification after the timeout adjustment: **235 tests pass** and `git diff --check`
passes. No paid recovery dispatch was performed by the agent.

## Execution journal — all batches returned and offline targeted dispositions

The user resumed locally; batches 76–82 returned. All 82 source batches are cached,
with 2,028 accounted claims / 1,985 valid received model source reviews. Raw actions
were 1,633 supported, 202 repairs and 193 unresolved; four omitted and 39 invalid
source reviews accounted for the final 43-item targeted queue. The final runner
state `needs_targeted_source_review` was an expected handoff, not a failed request.

Compared all 43 queued items against original source cues and supplied subject
context as the coding agent. Twenty-three were retained as supported, eleven have
minimal repair proposals, and nine remain explicitly unresolved for missing context,
uncertain names or wrong subject. Examples: price-to-food mapping retained; passport
advice kept separate from legal requirements; arrive-at-nine changed from duration
to recommendation; cuttlefish ink corrected from squid ink; folklore kept as folklore;
80 homes / 1952 / Barquino source renderings never normalized into verified history.
Unclear watering, climbed object and unnamed neighborhood remain research-only.
This is source comparison, not independent human gold-standard or current-fact approval.

Implemented reusable offline `trippy.sources.semantic_resolution`: validate every
cache against raw source binding; require exactly one keyed manual disposition for
every queued item; bind worklist, original claim/context and before/after hashes;
reject stale, duplicate, missing and cross-source decisions. The resolver preserves
original raw statuses and data and creates a separate immutable effective artifact.
Replaying the CLI produced identical output with zero paid calls.

Artifacts in `targeted-source-review-v1/`: `bound-worklist.json`, `manual-decisions.json`,
`resolved-source-dispositions.json`. The latter accounts for all 2,028 source
dispositions with zero omitted/invalid reviews pending: **1,656 supported, 213 repair
proposals, 159 unresolved**. Its source-disposition pass is complete; repairs remain
unapplied and planner readiness remains false. Completing an unresolved disposition
does not resolve the underlying venue identity or make its fact safe to schedule.

Prepared `semantic-repair-handoff-v1.json`: 213 repairs and 159 unresolved cases,
each bound to the original entry and comparison cues. Sixty-four receive high
consequence priority based on field type; this is a review prioritization rule,
not a count of confirmed critical errors. Next: adjudicate and materialize corrections,
resolve/retain uncertain subject identity, primary/current evidence, coverage and
executed planner scenarios. Earlier first-batch manual proposals remain a separate
input for the adjudication stage; no manual artifact silently alters the seed.

Financial checkpoint: 204 total requests / 198 returned usage receipts. Shared
reservation **$6.5956670 / $15**, semantic-task reservation **$2.4301449 / $3**.
Recorded configured-rate total **$2.2257446** (about $0.7896585 for the semantic
stage's returned receipts). Failed request reservations remain; estimates are not
invoices. This offline targeted phase cost zero new paid inference.
Verification: **237 tests pass**, `git diff --check` passes and immutable resolver
replay matches. No canonical/Supabase publication or native UI changes were made.

## Execution journal — source adjudication and materialized private version

The user requested the value assessment, remaining use-case gaps and continued
implementation. This phase spends no additional paid inference. The source audit
is a reliability stage, not gap generation or primary/current fact verification.
The earlier 213 repairs are proposals, not 213 confirmed mistakes or lost places.

Implemented `trippy.sources.semantic_materialize` and a reusable recipe at
`configs/source_research/barcelona-source-adjudication-v1.json`. Only explicit
agent source-compared repairs apply; model repair proposals and unresolved claims
remain outside the active source-claim set in a fully preserved held inventory.
Each adjudication binds the original claim/context hash; evidence must be exact
original same-video cues. Preserve source names, ratings, uncertainty flags and
dates; do not merge identities, create coordinates or approve current facts.
The new version has original/corrected claim events, occurrence-ID mapping,
per-claim use scopes and review lineage. No original source pack is overwritten.

Integrated the 25 first-batch and 43 targeted manual source decisions. This resolves
earlier protocol-noise quarantine without another model call and applies 12 source
corrections. Then directly checked 31 pending proposals affecting operational/safety/
access fields: 15 minimal corrections, 12 retained originals and four unresolved.
Retaining original text avoids unnecessary paraphrase and lost nuance (English
winery tours, uncertain butifarra price, Cova Fumada weekend belief). Do not infer
Casa Batllo from Casa Barrio ASR or assign wine-driving advice to Perpenon. Elevator
mention is retained under an observed feature instead of wheelchair accessibility;
noon restaurant advice becomes a general recommendation instead of a citywide
opening rule. Transcript tone alone does not prove whether a dispenser warning is
a joke. Source safety/legal commentary remains attributed, not certified advice.

Current materialized artifact: `adjudicated-source-v1/26a6a88097eb7eeb/`.
It retains all 549 research records and preserves all 2,028 claims between the
active source set and held inventory: **1,715 active source claims** (1,688 retained
supported / 27 applied source repairs), **168 pending repair proposals**, **145
held unresolved claims**. Ninety-nine explicit source adjudications were integrated.
These counts are not unique venues, independently verified facts or planner-ready
options. Categories/fit, canonical identities and current scheduling stay unapproved.

Reproduce offline from the project directory:

```sh
.venv/bin/python -m trippy.sources.semantic_materialize \
  --recipe configs/source_research/barcelona-source-adjudication-v1.json
```

Same inputs replay to the same immutable artifact. Intermediate development
artifacts remain preserved; engine hashes bind versions. Tests verify a model
proposal cannot apply itself, stale/foreign/duplicate manual decisions reject,
held originals remain available, exact source quotations are revalidated and
replay does not spend or overwrite results. **240 tests pass** and diff checks pass.

Dataset work still needs the remaining adjudications and place-level canonicalization,
supported retrieval facets, independent/local gap selection and primary fields.
The prior 32-family/38-query baseline remains a baseline, not an executed itinerary
evaluation: zero full itineraries were validated. Runtime handling of unusual nearby
requests, dates/slots/routes, private user inputs and locked stops still needs
integration. Ratings remain unknown unless an explicit source-bound five-star
score and dated platform evidence is available. Shared reservation remains
$6.5956670 / $15; recorded usage estimate $2.2257446. No new model calls, catalog
writes or remote publication were performed in this source-adjudication phase.

## Execution journal — targeted review complete and unattended proposal queue

Targeted review returned all 313/313 decisions: 50 supported, 150 repair proposals,
113 unresolved, zero missing/invalid slots. These proposals have not yet been
adjudicated into the active source pack. Shared reserved $7.6826339/$15; targeted
task reserved $1.0869669 including two timeout attempts. Lifecycle/customization
scope is refined in PLANNER_DATA_LIFECYCLE.md and ACTIVITY_CUSTOMIZATION_FRAMEWORK.md.

The user requested unattended serial runs while away, with rate-limit waiting,
bounded retries and manual adjudication afterwards, anchored to the chat.md trip
dashboard rather than unlimited catalog work. Implemented the draft 14-activity
registry and new source-only annotation queue: 237 venue/chain occurrences in
60 calls and 213 contextual occurrences in 54 calls; 99 no-active-evidence records
are held for manual work. First pass reserves $1.9191210; additional queue cap $5,
including retries, within the original $15 ledger. Existing provisional pools must
not be cumulatively added to this new priority allocation.

Offline work also prepared 296 lexical identity groups (124 with candidates),
313 content-bound source-review handoffs and chat-derived product acceptance
criteria. No identity approval, manual repair, current-fact certification or UI
deployment occurs automatically. Active queue root unattended-v2; unused earlier
preparation preserved. See BARCELONA_UNATTENDED_RUNS.md for launch/status commands,
stop conditions and remaining manual/integration dependencies.

Verification: 254 Python tests pass, shell syntax and diff checks pass. No new paid
request was dispatched in this preparation turn; actual Azure compatibility of
the annotation schema remains untested until user execution. Local source/adapters,
canonical review, generic map/slot integration and full itinerary execution remain.
