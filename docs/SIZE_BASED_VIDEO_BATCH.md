# Size-based Barcelona video execution

The user authorized a **$5 shared hard cap** for the next batch. The existing
ledger is retained at $1.8657948. Preparation reserves at most $2.7939264 more,
bringing the conservative total ceiling to **$4.6597212**. Reservations are not
invoices. Individual calls and the whole remaining batch are checked against the
cap. The configured cap in the private environment is $5.

## Allocation

Primary extraction uses the existing evidence chunks, each capped at 12,000
transcript characters, with the reviewed v2 extraction instructions. Additional
v3 audits use required per-cue keys and exact source evidence.

| Unique transcript characters | Additional audit calls |
|---:|---:|
| Up to 6,000 | 0 |
| 6,001–14,000 | 1 |
| 14,001–26,000 | 2 |
| More than 26,000 | 3 |

Audit selection spans temporal bands across the video, prioritizing uncited
speech within each band. This is targeted review, not exhaustive auditing of every
scene. Core windows shrink before execution if their individual conservative
reservation would exceed $0.06. If a scene cannot fit that ceiling, the audit is
stopped and reported rather than spending past its allocation.

The prepared batch contains **21 videos, 36 primary calls and up to 29 audits**
(65 new calls). The two finished pilots are reused. One three-cue promotional
transcript is retained for manual review without paid generation. All original
speech remains in each result's evidence inventory, including cues outside
selected additional audit windows.

Per-video allocation:
`.local/stage3/sources/barcelona-size-based-batch-plan.md`.
Immutable execution plan:
`.local/stage3/sources/barcelona-size-based-batch-plan.json`.

## Execution safeguards

`trippy.sources.batch` runs at most two videos concurrently. Each request gets one
attempt. Per-video provider groups have durable request ceilings. Completed raw
receipts and validated caches replay without a new model call. A previously
attempted request without a usable receipt cannot be retried implicitly.
Checkpoints from another plan are rejected. All claims pass the existing evidence
validators; rejected claims and failed responses remain inspectable.

The user explicitly authorized private extraction of these videos. This execution
does not claim the earlier exhaustive semantic quality gate has passed. All
generated outputs remain private research requiring semantic, identity/branch and
current-fact review. No Supabase writes or publication are part of the batch.

Results are saved under `.local/stage3/size-batch-v1/<video-id>/`, with per-video
primary results, audit manifests, caches and final JSON. The batch summary is
`.local/stage3/sources/barcelona-size-based-batch-result.json`.

## Current execution status

The first agent network command was **not launched**: automatic approval review failed with
HTTP 404 “deployment not found” from its own review service. The failure happened
before process creation. The ledger still has 49 prior requests and $1.8657948
reserved; no new batch calls occurred. The user's financial authorization remains
recorded. Execution needs the app approval service repaired or the user to run
the prepared launcher locally:

```bash
sh /Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-size-batch.sh
```

The launcher reads the project's existing private configuration and enforces the
approved cap. It prints per-video progress without printing credentials.

The user subsequently started the launcher locally. New batch requests in the
shared ledger confirm execution is progressing. The original runner printed only
completed-video summaries, so the terminal can stay silent for several minutes.
The updated runner prints video starts, API starts/completions and 20-second
waiting messages on its next launch. The already running process keeps its
original logging; do not start another batch beside it.

To monitor the current run, open a **second Terminal** and run:

```bash
sh /Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/watch-barcelona-size-batch.sh
```

This read-only monitor refreshes every 15 seconds with videos saved, requests
started, responses received, pending receipts and the shared reservation. Ctrl+C
stops the monitor without stopping the batch. A one-time snapshot is available
with `.venv/bin/python -m trippy.sources.batch_status` from the project directory.

### Live costs and sleep protection — 31/10/2026

The dashboard now shows each video's extraction and audit costs separately:
recorded-token estimates, exact conservative reservations, and its planned
ceiling. Missing usage is displayed as `--`, never as zero cost. Estimates use
configured token rates without cache discounts and are not billing invoices.
The live JSON snapshot is written to
`.local/stage3/sources/barcelona-batch-live-status.json`.

Both launchers now use `caffeinate -is`. The read-only watcher was started and
its idle/system sleep assertions verified with `pmset -g assertions`. Keep the
lid open and the Mac on AC power; this does not override lid-closed sleep.

At 00:56 UTC, 3/21 videos were saved, with 16 calls started and 14 receipts.
Shared reservations were $2.4106183; this batch reserved $0.5448235, with
approximately $0.1618 estimated from received usage. Last actual activity was
20:08:14 UTC on 30/10. The two outstanding requests have no receipts; dashboard
refreshes are not evidence of progress. Do not launch another batch until the
original process is confirmed stopped. Existing reservations must be retained.

New batch processes enforce a 180-second total request deadline using an
isolated worker. A timeout retains the reservation and never retries
automatically. This safeguard does not affect the already-running old process.

The user subsequently confirmed closing the old task. The launcher now explicitly
permits one recovery attempt each for interrupted primary requests 64 and 65,
in distinct durable recovery groups capped at one request. Old reservations remain;
saved recovery receipts replay, and a missing recovery receipt cannot trigger
another retry. Whole-batch preflight includes these additional reservations under
the unchanged $5 cap. The agent's resume launch was not executed: automatic
approval review again failed with deployment HTTP 404. The prepared launcher must
be run locally or the approval service repaired; no replacement process was started.

The user subsequently raised the shared cap to **$15**. The private `.env`
setting is updated accordingly; the ledger and previous reservations were not
reset. At 01:22 UTC the ledger showed $2.4106183 reserved overall, including
$1.8657948 before the size-based run and $0.5448235 reserved by it so far.

### Completed execution and output review — 31/10/2026 02:21 UTC

All 21 scheduled video outputs and the batch summary are saved. There were 67
request starts including two recovery attempts, and 64 raw receipts. The current
batch has $2.1935 reserved and approximately $0.7321 recorded-token estimated
cost; shared reservations including earlier work total $4.0593 / $15. Dashboard
accounting now includes recovery groups and exposes primary output issues.

Across these 21 outputs: 404 research records, 1,427 claims, 4,819 preserved
transcript cues, and 1,450 cues selected for additional auditing. These are not
404 unique canonical places: 204 records are venue occurrences; other kinds
include districts, advice, dishes, cities and routes. All retained records passed
the existing exact quote/timestamp/name/rating validator against their original
cue inventory. This is structural evidence verification, not independent fact
checking or an exhaustive semantic completeness review.

The top-level `failed_videos: []` does not certify complete extraction. Two
primary chunks failed (Gothic Quarter walking tour: API timeout; first-timers
must-dos: output length limit). Nineteen additional primary chunks retained valid
content while quarantining 33 items for entity-name anchoring. Audits have 72
quarantined proposals, 310 cue dispositions with validation errors, 222 uncertain
cue dispositions and 92 semantic review issues. 216 records have uncertain
identity. No explicit five-star rating was extracted; this must remain unknown.

Semantic spot checks confirmed detailed La Plata dishes and historical closure
context were retained. Other useful unnamed-stop evidence was quarantined,
including a rooftop cafe and unnamed tapas stops. No claim is made that eight
venues can be resolved merely from an eight-bars video title. Category coverage
is uneven (only 7 coffee-category and 4 clubs-category records, not necessarily
unique venues). Source data is useful for private research but is not yet the
approved personalized catalog. Recovery of failed passages, quarantine review,
ASR identity/branch resolution across sources, completeness samples and current
fact checks remain required. No new paid calls or catalog writes were made during
this review. Full diagnostic:
`.local/stage3/sources/barcelona-size-batch-quality-review.json`.

### Targeted failed-passage recovery

User authorized execution of recovery. `trippy.sources.batch_recovery` prepares
four half-sized passages for the two failed primary chunks, with two-cue boundary
overlap, v2 extraction, exact evidence validation, and no automatic retry. Its
additional conservative reservation is $0.1061851 under the shared $15 cap.
Unique bounded recovery groups retain all original reservations. Valid caches and
receipts replay; failed attempts without usable receipts cannot implicitly retry.
Original batch outputs remain unchanged. Separate merged outputs and prior-review
metadata are saved to `.local/stage3/failed-passages-recovery-v1/`; old audit
references require reconciliation before use. A recovered passage means validated
replacement output, not independently verified semantic completeness.

Preparation and offline recovery checks passed. The agent's launch was rejected
before execution by automatic approval review, again with deployment HTTP 404.
No new model requests were made. Local launcher:

```bash
sh /Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/recover-barcelona-failed-passages.sh
```

The launcher includes `caffeinate -is` and request heartbeat output. Recovery
summary will appear at `.local/stage3/failed-passages-recovery-v1/summary.json`.

Recovery completion confirmed: four requests (117–120) returned complete
responses. Both failed passages now have validated replacement output.
First-timers video: 18 → 74 research records, 57 → 152 claim entries.
Gothic Quarter tour: 11 → 27 records, 36 → 80 claim entries.
All retained recovered records again passed transcript quote/timestamp checks.
One Casa Batllo mention remains quarantined for name anchoring; it needs review,
not another blind paid run. Recovery token estimate ~$0.0362; reservation
$0.1061851; shared reservations $4.1655221 / $15. Replacing these two original
versions in a research view yields 476 records / 1,566 claim entries, still not
canonical unique places or fully verified facts. Old batch files remain preserved;
semantic review, identity deduplication, quarantine recovery and current checks
remain pending.
