# Executable Barcelona integration runner

Implemented and checked on 2 November 2026. The design reference is
[BARCELONA_FINISH_SCRIPT_DESIGN.md](BARCELONA_FINISH_SCRIPT_DESIGN.md). This runner
executes private offline integration and optionally bounded explicit operator-page
checks. Its output keeps unfinished identity, provider, itinerary and UI gates visible.

## Run now

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-finish.sh
```

No arguments means `offline`. The runner performs seven checkpointed stages:
audit, compile, retrieval, evidence inventory, application of existing manual
decisions, draft/export, and evaluation. It preserves the selected editorial
edition and previous paid receipts/ledger. No AI or HTTP calls are dispatched.
Running it again checks and reuses the same campaign outputs.

The launcher requires `/usr/bin/caffeinate` and runs the Python process with
`caffeinate -i -s` for its full lifetime. Keep the Mac connected to power and
leave the lid open while it runs. If `caffeinate` is unavailable, it stops before
starting work instead of silently running without the sleep protection.

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-finish.sh status
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-finish.sh resume
```

Default dates are explicitly **synthetic**, 10–12 January 2030. They exercise
coffee/breakfast composition; they are not the user's travel dates or a complete
sightseeing itinerary. For a real trip, supply a JSON file:

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-finish.sh offline --trip /absolute/path/trip.json
```

```json
{
  "synthetic": false,
  "start_date": "2027-04-10",
  "end_date": "2027-04-12",
  "activities": [
    {"id": "coffee_break", "frequency": "daily"},
    {"id": "breakfast_out", "frequency": "daily"}
  ],
  "excluded_ids": [],
  "locks": [],
  "hard_requirements": [],
  "budget_eur": 250
}
```

Dates are illustrative. Supported activity frequency is `once` or `daily`.
Stay breakfast uses `breakfast_at_stay: provided|buy_supplies|unknown`. A selected
`breakfast_at_stay` activity requires that choice. Supply shopping is requested
once, not every day. Unknown provision remains unknown.
Hard requirements supported as unresolved constraints: `dietary`, `allergy`,
`accessibility`. Without applicable evidence they do not admit optional stops.
Locks require stable source ID, day, start_minute and duration_minutes; they are
kept fixed and conflicts are reported. Unknown keys are rejected.

## What the run produces

`finish-v1/latest.json` identifies the campaign under
`.local/stage3/planner-release-v1/finish-v1/`. Each folder contains:

- `report.md`, `status.json`, `evaluate.json`: results, benchmark and remaining gates.
- `compiled-dataset.sqlite`, `compile.json`: a full-lineage source discovery projection.
- `retrieve.json`: before/after results for registry activities and groceries.
- `trip-view.json`, `map-layers.json`: source draft, alternatives, panels and layer data.
- `manual-handoff.json`: shortlisted identity/field questions and category supply gaps.
- `manifest.json`, `queue.sqlite`, stage JSON files and optional receipts: resumable evidence.

The application can load the projection using `trippy.planner.dataset_reader`.
The iOS/UI app has not been wired to this reader by this change. JSON map layers
are exported, not visually rendered or certified as a superior UI.

Source occurrence IDs are not canonical place IDs. We do not merge equal names
or assign operator/catalog coordinates to transcript mentions without a reviewed
join. Map items with unknown coordinates remain list candidates with `pin: null`.

Six manually source-compared, content-hash-bound taxonomy migrations restore
church, stadium, plaza and pastry_shop tags from existing reviewed details.
Original details and quotes remain stored. The original registry is preserved;
the new reader uses registry v2. No mass admission of pending AI annotations occurs.

## Connected operator checks

Optional, not required for the command above:

```sh
.local/stage3/run-barcelona-finish.sh connected --trip trip.json --sources operator-sources.json
```

`operator-sources.json` is an explicit list of shortlisted occurrence/URL pairs:

```json
[
  {"place_id": "source:<id-from-retrieve.json>", "url": "https://official-operator.example/visitor-page"}
]
```

The placeholder is not a real fetch target. Use actual public official URLs and
IDs present in the campaign shortlist. Default sources list is empty. No broad
crawl or automated provider discovery is initiated.

The existing bounded HTTP/JSON-LD adapter saves operator observations. New pages
are not automatically converted into canonical transcript identities or verified
trip fields. Robots/redirect requests and retries count toward the 150-request
ceiling; at most 30 explicit pages and four transient attempts per page.
Operator workers have a 60-second request deadline and 15-second progress messages.
Host cooldowns honor Retry-After across pages and restarts. A cooldown beyond the
execution's wall allowance saves a resumable deferred stage; rerun `resume` later.
Content/access failures become review handoffs instead of repeated AI attempts.

Places, Routes, ticket/table availability adapters and Luna dispatch are **not
enabled in this runner**. Configurations cannot turn on paid calls. Missing
capabilities appear explicitly in evidence/report gates. Adding those integrations
requires actual adapters and provider-specific budgets, not an assumed API call.

## What was verified

- Real selected edition audit and full compiled SQLite/JSON parity.
- Actual interruption after compile, resume and repeated execution with identical outputs.
- Review eligibility, stale claim bindings, migration content hashes, held/proposal retention.
- Coffee frequency, coffee/meal merging, stay breakfast provision/unknown/supplies.
- Hard constraint exclusions, unchanged locks, overlapping windows and unknown prices.
- Checkpoint tampering, provider Retry-After persistence and same-host cooldown.
- Zero paid and HTTP dispatch in offline mode. Provider tests use mocked responses.

The fixed manually reviewed retrieval benchmark contains coffee, breakfast,
brunch and groceries expected sets. It does not establish broad city accuracy.
The 16 synthetic behavior cases exercise invariants and report missing supply;
they are not 16 verified real itineraries. Current brunch/groceries gaps remain
visible. The existing 97.93% measures editorial admission only.

The runner writes explicit gates for audit, narrow retrieval benchmark, activity
behavior, draft windows, selected-trip checks, complete itinerary benchmarking,
UI exports/rendering and publication. A drained queue does not clear them all.
The next handoff should focus on missing shortlist identities/services/providers,
not rerunning every source extraction or every pending annotation.
