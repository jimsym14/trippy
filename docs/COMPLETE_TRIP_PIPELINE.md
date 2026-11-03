# Connected trip pipeline — 2 November 2026

The old app bridge used one broad scout call and one Luna response to produce the entire trip document. It could publish a sparse result as completed. The recovered Barcelona audit had seven places, no coordinates and five empty days. The failure was in research coverage, composition, readiness and presentation; the screenshots do not establish that Luna or API latency alone caused it.

The app bridge and command-line runner now use `trippy/planner/pipeline.py`. This is a connected local implementation, not a certification of live travel facts or a production deployment.

## Evidence → focused research → checks → composition → delivery

1. **Preserve the brief.** Dates, travelers, interests, vibes, food and mobility needs, budget scope, stay style, custom instructions, exclusions, explicit locks and prior trip evidence accompany every research stage. Unsupported semantic preferences remain visible in the report. Coffee or nightlife preferences add discovery scope while keeping practical daytime/meal choices available.
2. **Retrieve relevant evidence.** Barcelona's selected editorial bundle is hash-checked against its SQLite snapshot. Held claims are excluded; only current, manually admitted annotations become structured fit context. Quotations remain editorial discovery evidence. Permitted, published, retained, shared Overture records supply identity candidates. Neither dataset becomes verified current availability. Category pages retrieve different bounded groups; practical contextual records accompany logistics. Exact subject/address matches select operator observations for follow-up.
3. **Discover in small batches.** Category tasks target at most six venues per normalization response. A separate logistics task asks for calendar, transport, tickets and events. Task IDs, complete inputs, provider output and failures are persisted. Already discovered name/address pairs discourage duplicate pages.
4. **Normalize a strict evidence graph.** Luna produces typed batches rather than an itinerary or grand total. Local validation rejects missing/unknown fields, malformed references, invalid prices/coordinates and invented source URLs. Coordinate and price claims require field references. Stable identity distinguishes branches and retains existing user IDs on exact normalized name/address matches. Source presence is provenance, not proof that a claim is true.
5. **Draft and check selected choices.** A deterministic engine proposes day sequences. Follow-up groups of four research identities, visit dates, opening windows and hard needs for selected venues and backups, up to 48 candidates. The engine then recomposes. Contradictory primary checks remain pending; later responses cannot silently erase a coordinate, price or opening conflict.
6. **Calculate and validate.** Exclusions and explicit locks, geographic proximity, pace, proposed durations, opening windows and dietary/mobility checks influence scheduling. Route-provider results can be injected; otherwise distance-based estimates are labeled unverified. Final adjacency is checked after sorting. Selected known EUR adult/per-person prices produce a coverage-counted subtotal. Unknown prices remain unknown. Booking-required venues produce pending tasks, never a reservation claim.
7. **Deliver honestly.** The existing `trippy-research-v1` import remains compatible. Coverage and feasibility jointly gate readiness. Missing categories, dates, routes, events, budget coverage and personal-instruction review remain pending. Provider failures stop new dispatch and keep prior evidence. `partial` is a distinct bridge status.
8. **Preserve the traveler's work.** Import rebinds old stop indexes by place identity, keeps user order/removals/amounts/reactions/pins and retains omitted anchors. Fresh proposals append to edited days without undoing deliberate removals. Changed local schedules are marked for timing/route/cost review. Saved job IDs let connection recovery poll the same run; live results are bound to their requesting trip even if another trip is selected.

## Responsibility and remaining limits

| Area | Implemented | Remaining acceptance work |
|---|---|---|
| UI | Greek-first Program/Places/Costs tabs; day selector; readable rows and disclosures; place search/category/liked filters; price tables; persistent bookmarks; MapKit route previews and directions handoff | Actual native screenshot review, large text, dark mode, VoiceOver and device interaction. No visual quality score is claimed. |
| Models | Small strict research batches; local validation; deterministic schedule/cost ownership; durable stage reuse | Live Luna structured-output compatibility, completeness and evidence correctness on representative briefs. The original failure is not proven to be model capability alone. |
| APIs | No SDK initialization for preview; job-specific polling; atomic busy gate; interrupted jobs recognized; no automatic paid retries | Real Azure agent/SDK calls and routing integration. A submitted POST whose reply is lost before its job ID is saved still needs server-side idempotency before production. |
| Data | Real local editorial and inventory retrieval; exact-branch matching; conflict holds; uncertainty retained | Canonical identity/entrance release, date-specific verification, source freshness and connected Supabase publication. Discovery inventory is not a current-services database. |
| Planning | Deterministic proposals, exclusions, explicit locks, date windows, constraints, pace and known-price arithmetic | Full optimizer, arrival/departure-time accommodation, automated local-edit rescheduling, room/flight quotes, eligibility-aware group totals and fully scheduled events. Arbitrary natural-language instructions require review. |
| Cost controls | Existing shared ledger reused; configured conservative reservations precede web/Luna dispatch; receipts retained | Fixed web reservations are configured allowances, not a proven bound on actual provider invoices. No prices were invented and no ledger was reset. |
| Ownership | Separate UUID job capabilities; preflight exposes no other brief/result; trip-bound app import | Authenticated Supabase owner/RLS service, worker deployment and server-side cancellation/idempotency. The bridge is a prototype service. |
| Recovery | Completed stages reused for identical brief, edition and research date; failed/uncertain stages cannot redispatch automatically | Reviewed explicit retry tooling and cross-date refresh. Closing app progress stops polling, not the server's already authorized work. |

Unknown dates yield discovery and a pending date requirement rather than fabricated calendar dates. Grand cost fields deliberately remain unknown until their scope is covered, so the legacy readiness audit will generally remain partial. A useful synthetic itinerary does not prove a complete real itinerary.

## Reviewable offline evidence

`.local/trip-pipeline/review/barcelona-preview/pipeline-plan.json` records a five-day Barcelona brief with ten initial category/logistics tasks and zero paid calls. `retrieval-preview.json` contains the actual bounded source inputs. The selected edition is `ae14f5109842528d6e19dec65eba49b7d52b15d4f70c0bf49897fe8467d57c57`; 294 editorial venue occurrences are available. The local Overture catalog contains 41,461 snapshots; preview tasks select up to 16 permitted candidates each from catalog version `2a2dbe33-5c17-5f69-b235-4f1dc716f939`. These counts describe availability/retrieval, not unique verified recommendations.

Generate a preview without API clients or paid calls:

```sh
.venv/bin/python run_research.py --brief path/to/brief.json --output-dir .local/trip-pipeline/my-preview
```

Execution is a separate `--execute` invocation and requires the existing paid-enable switch, explicit cap/currency, configured Luna rates/deployment and `TRIPPY_WEB_RESERVATION_PER_CALL`. The shared default ledger remains `.local/stage3/extraction-budget.sqlite`. No live execution or deployment occurred in this work.

## Verification

- 110 Python tests across trip pipeline, research projection, provider evidence, Luna budget adapter, catalog and backend. Tests cover populated synthetic plans, strict sources, conflicts surviving later responses, hard requirements, route failure, unknown locked coordinates, price arithmetic, stage reuse/failure, exact branch IDs, bounded pagination, concurrent job creation, restart and result isolation.
- Native storage and plan projection scripts: legacy Codable migration; order/edit/pin/checklist/budget/note retention; missing-pin route breaks; transport modes; null/free/range prices; import identity migration, removals, retained anchors and repeat import.
- Swift production parser and iOS Simulator SDK type check using a temporary State type alias and removal of the Preview macro block. The production file is unchanged by that workaround.
- A real Xcode/Simulator build and rendered UI review remain unavailable under this environment's existing restrictions. Live calls, route/search responses and externally verified Barcelona plan quality have not been demonstrated.

See [PLAN_REDESIGN_AND_FAILURE_AUDIT.md](PLAN_REDESIGN_AND_FAILURE_AUDIT.md) for the UI failure analysis and [PLANNER_DATA_LIFECYCLE.md](PLANNER_DATA_LIFECYCLE.md) for editorial/canonical evidence ownership.

The 3 November full-screen loading, completion checkpoints and offline previews are documented in [RESEARCH_PROGRESS_REDESIGN.md](RESEARCH_PROGRESS_REDESIGN.md).
