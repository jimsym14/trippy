# Barcelona unattended preparation queue

## New runnable three-layer completion queue

Use `run-barcelona-completion.sh`, not the earlier unattended enrichment launcher.
The [completion automation guide](DATASET_COMPLETION_AUTOMATION.md) contains the
single execution command, resume/status commands, budgets, adapter contracts,
outputs and remaining evidence boundaries. It processes pending editorial work,
branch identity candidates and operator field observations. The original active
manual pack and shared budget ledger are preserved.

## Manual integration checkpoint — 1 November

The active editorial source pack is now
`adjudicated-source-v2/df0b348f4558c04c/normalized.json`. Seventy expanded-context
source comparisons produced 54 retained originals, 12 corrections and four held
ambiguities. There are 1,781 active source claims and 247 held; all 2,028 conserved.
243 of the original 313 expanded followup decisions remain untouched. The prior
99 source adjudications are preserved. Source support is not canonical/current
approval. Explicit assertion scopes prevent general traditions, creator biography,
trip mileage and compared venues from becoming exact-venue capabilities.

Twenty reviewed tags are materialized in
`reviewed-annotations-v1/df705c910d749bb6/reviewed-tags.json`. Eight support source
discovery, 12 are contextual or insufficiently cited; none is a planner-approved
capability. 593 facet proposals remain unreviewed, plus the separate 34 quarantined
vocabulary proposals. These are editorial queues, not 627 missing real-world facts.
Annotation claim hashes are rechecked against the current pack; repairs require
new annotation review rather than blind ID remapping.

No new paid calls. Shared reserved remains $9.7357103/$15. **264 tests pass.**
Do not rerun the paid unattended launcher. The following commands are optional
offline replay of the completed work, from `project/`; they do not finish identities,
current facts, UI integration or actual itinerary scenarios:

```sh
.venv/bin/python -m trippy.sources.followup_materialize --recipe configs/source_research/barcelona-expanded-followup-v1.json
.venv/bin/python -m trippy.sources.scoped_annotations --recipe configs/source_research/barcelona-reviewed-tags-v1.json
```

## Latest checkpoint — 1 November: executed and recovered offline

All 114 request batches returned raw candidates. The original runner saved 83
protocol-valid batches and deferred 31: 24 first failures for unsupported closed
facet values and seven first failures for source-accounting mismatch. Nine transient
timeout reservations were retained; total queue reservation $2.0530764, shared
$9.7357103/$15. Returned usage receipts for all 114 completions give a configured
rate estimate $0.5081117, not an invoice. Returned model ID:
gpt-6-luna-2026-09-22. Preparation notes below are historical.

Offline recovery produced all 114 protocol-valid batches/450 records without any
new paid call. It quarantined 34 unsupported-vocabulary facets and reconciled
unrepresented source accounting; original raw candidates and runner status remain
unchanged. The vocabulary was incomplete (e.g. church/stadium), and closed values
were not enforced conditionally in the provider schema. This was partly our
contract design issue, not 31 failed API responses. Do not rerun the old launcher.

Active recovered artifact:
.local/stage3/planner-release-v1/unattended-recovery-v1/9548b94c7a152420/
contains manifest.json, summary.json, annotation-proposals.json,
quarantined-facets.json and manual-tag-audit-v1.json. Counts: 613 facet proposals,
1,075 detail proposals, 149 activity-fit proposals, 227 unrepresented source-claim
occurrences. Counts are neither unique places nor approved factual coverage.

A diagnostic exact-quote audit of 20 service/practical-type facets found eight
source-supported with qualifiers, three visit observations, six general/area
contexts, one compound-venue context and two insufficient citations. This is not
a random sample or whole-dataset accuracy estimate. General granja history does
not confirm coffee service at one exact venue; market/beach bars do not identify
a schedulable cafe/bar; an alias/opening-year citation does not support drinks
service. No canonical/current factual approval follows from offline recovery.

Next work: content-bound source adjudication and semantic tag/subject review,
canonical entities and source references, then focused primary sources for genuine
coffee/brunch/grocery gaps. Future schemas must distinguish entity kind, venue
capability, area amenities and source visit observations, enforce key/value pairs
and leave unknown vocabulary in an extension-proposal channel. Claim-accounting
complements can be calculated by code instead of delegated to the model. Version
future requests; do not change the frozen run or reset its ledger.

31 October 2026. Implements the executable, independent part of the optional
customization proposal work. Product anchor: chat.md, particularly itinerary,
alternative choices, day/general maps, accommodation, cost/ticket/booking panels,
provenance and incremental edits. Historical ChatGPT statements are not admitted
as verified city facts. The full chat is hashed locally, not sent wholesale to Luna.

## Ready launcher

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-unattended.sh
```

Runs serially, with automatic caffeinate, unbuffered progress and appended log.
Keep the laptop lid open, external drive connected and Terminal running. This is
not a persistent OS service and cannot operate through sleep, unmount or shutdown.
Resume by rerunning the same launcher; a duplicate queue lock prevents two copies.

Status from another Terminal:

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/status-barcelona-unattended.sh
```

Live log:

```sh
tail -f /Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/planner-release-v1/unattended-v2/runner.log
```

## Prepared work

| Stage | Input | Calls | First-pass conservative reservation | Task cap including retries |
|---|---:|---:|---:|---:|
| Venue capabilities | 237 source occurrences with active evidence | 60 | $1.0175439 | $3 |
| Context details | 213 other source occurrences with active evidence | 54 | $0.9015771 | $2 |
| Local identity proposals | 296 venue/chain occurrences against 41,461 regional snapshots; 124 with detected candidates | 0 | $0 | $0 |
| Source adjudication handoff | 313 completed targeted decisions and expanded context | 0 | $0 | $0 |
| Product acceptance checklist | Selected chat.md product criteria and retained full-file hash | 0 | $0 | $0 |

114 paid calls prepared, 450 evidence-bearing records. These are not unique places.
99 empty active-source records remain for manual review; the model is not asked to
fill them from memory. Previously held claims and the new 150 repair proposals are
not silently applied to the source pack. After adjudication, affected annotations
may need a focused update. No existing 82- or 40-call review is rerun.

First-pass total reserve $1.9191210. Additional hard queue cap $5, drawn from the
same original $15 ledger. Existing reserved $7.6826339; maximum projected reservation
$12.6826339, leaving $2.3173661 for future work. Failed attempt reservations remain.
Reservations are conservative configured-rate ceilings, not invoices. These
allocations replace bulk shared research as the next work priority; they are not
added on top of every old provisional pool. No new paid call was dispatched in
this preparation turn. An earlier unused preparation under unattended-v1 remains
preserved; active output is unattended-v2 with the same new stage request groups.

## Proposal content and validation

Versioned activity-registry-v1.json defines 14 optional intents, controlled facet
keys/values, detail kinds and map-layer/scope identifiers. It is a draft shared
registry; the UI, predicate compiler and planner merge primitives are still pending.
Source annotations can propose multiple venue capabilities, useful details,
activity fit and field lifetime. Every item has claim IDs from its own source
record; every source claim is represented or explicitly unrepresented. All original
claims and quotes remain available. Provider schema has required keyed record
slots; local validation checks unknown fields, evidence, duplicate annotations,
closed values and claim accounting. Max request: 55 source claims; max schema
17,473 serialized characters at this preparation checkpoint.

This validates protocol and source-ID linkage, not the semantic truth of a tag or
fact. Annotation/value, lifecycle, identity and activity fit require later review.
No canonical identity, exact current opening/price, allergy/access guarantee or
planner readiness is granted automatically.

## Recovery, waiting and stop conditions

Only this new runner enables explicit automatic retries. SDK retries remain zero;
older extraction/semantic launchers retain their no-automatic-retry behavior.

- HTTP 429: honors numeric Retry-After, retry-after-ms or HTTP-date where supplied;
  otherwise exponential backoff starting at 60s. At most eight attempts per chunk.
- HTTP 408/500/502/503/504, API timeout/connection failure and worker deadline:
  bounded backoff starting at 15s; at most three attempts per chunk.
- Backoff base capped at one hour, but a longer explicit provider Retry-After is
  honored subject to the cumulative waiting ceiling. Total deliberate wait budget:
  12 hours, persisted across resumes. Max 100 requests per stage, including errors.
- Provider timeout 120s; child-process wall deadline 180s. Heartbeat every 15s,
  visible waits/checkpoints at most 30s apart. No indefinite provider hang.
- Invalid/partial/refused responses are preserved/deferred for manual review;
  no paid content repair retries. Persistent transient failures are deferred and
  independent chunks/stages continue.
- Authentication, deployment, API-version or schema incompatibility errors stop
  the queue. Budget caps stop/defer before another request. It is impossible to
  promise completion through arbitrary persistent provider failures.
- Saved valid responses are reused. Raw provider completions interrupted before
  local cache save are adopted by ledger group/chunk/request ID without API use.
  A timed-out request may have reached the provider; a retry can cost again, hence
  reservation retention and explicit limits.

## Artifacts and manual follow-up

Root: .local/stage3/planner-release-v1/unattended-v2/

- prepared.json, preview.json/current-preview.json: immutable inputs and budgets.
- status.json, events.jsonl, runner.log: durable progress, retry events and output.
- venue_capabilities/, context_details/: raw candidates and protocol-valid proposals.
- annotation-proposals.json: aggregate saved work, never a published dataset.
- targeted_source_handoff.json: bound decisions for human repair/subject review.
- identity_candidates.json: lexical candidates, no name-only merges.
- product_acceptance.json: output goals and unexecuted planner gates.

After return: source adjudication, semantic tag review, canonical identity admission,
focused source collection, generic map/retrieval/slot integration, actual itinerary
scenarios, and final release remain necessary. Current-source/API fact research
cannot safely be indiscriminately queued without reviewed subjects and source
capabilities. API provider integration and the SwiftUI design stage are code work,
not Luna batch tasks. Do not treat this queue's success as completion of all eight
remaining release stages.

Verification: 254 Python tests pass, including real child-process timeout/hint
transport and mocked retry/cost/cache behavior. Shell syntax passes. No paid
provider response has yet tested this new annotation schema on the user's Azure
deployment; compatibility failures stop rather than repeatedly charge attempts.

## Current checkpoint — 1 November

The later completion queue has now been executed by the user. Its source and
annotation response handoffs were recovered offline per item: 243 source slots,
1,826 validated annotations, 25 quarantined annotations, and 2,028 conserved
claims (1,987 staged active / 41 held). Shared reserved is $13.3432175/$15.
The original active manually curated pack is unchanged. Two source/catalog
branch correspondences are manually reviewed; full identity/current/planner
release remains pending. 290 tests pass. Use the offline recovery command in
[DATASET_COMPLETION_AUTOMATION.md](DATASET_COMPLETION_AUTOMATION.md), rather than
rerunning either paid launcher for content/schema handoffs.
