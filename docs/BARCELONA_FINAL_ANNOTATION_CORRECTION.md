# Barcelona manual annotation correction — 1 November 2026

The 136 annotation handoffs proposed for repair, rejection or quarantine were
manually compared with their supplied claims and exact source quotes. This pass
prepared an applied private annotation correction layer, without another Luna
run, network request, catalog mutation or publication.

| Finding within the reviewed 136 slots | Count |
| --- | ---: |
| Confirmed annotation/subject/activity-fit errors | 35 |
| Formatting errors | 3 |
| Unnecessary or overly strict model changes/rejections | 40 |
| Missing taxonomy types or unsuitable taxonomy mappings | 21 |
| Insufficient evidence for the proposed assertion | 19 |
| Scope clarification, preserving the underlying information | 18 |

These categories are disjoint per annotation slot. They count annotations, not
distinct places or independently disproved real-world facts. The 35 errors are
incorrect interpretations, scope or activity tags against the supplied evidence.
Neither the model's 144 source repairs nor its 72 annotation rejections were
treated as a count of confirmed mistakes.

## What changed

| Before | Correction |
| --- | --- |
| Camp Nou `place_type=museum` | Stadium visit context with a museum inside; no whole-stadium museum identity |
| Iberics Antonio `place_type=market` | Cured-meat vendor/stop within a market |
| La Boqueria classified using a Santa Catarina quote | Explicit comparison context, without using another market's evidence for Boqueria |
| A scenic viewpoint tagged `sunset_view` | Unsupported sunset fit removed; the original viewpoint claims remain |
| Seafood/rice restaurant tagged `aperitivo_tapas` | Unsupported tapas fit removed; source meal details remain |
| City or hill tagged as an outdoor venue, park or museum | Geographic context with the named subvenues/features preserved |
| Wine refill at wine shops tagged `local_market` | General source-era shopping advice, without inventing a market or checked shop |
| `food_hall`, `stadium`, `church` forced to `landmark` | Explicit source descriptor in a detail; no new taxonomy type or unsupported substitute |
| Boqueria coffee/breakfast proposal rejected for lacking regular hours | Visit-level recommendation retained; current service, vendor and hours remain unverified |
| Park terrace photography recommendation rejected as non-permanent | Attributed photography discovery descriptor retained |
| Can Vilaro breakfast rejected as merely a general tradition | Named fork-breakfast recommendation retained; tradition ingredients are not a checked venue menu |

The manual dispositions are **51 replacements, 40 retains, 14 context-only,
15 rejected activity/taxonomy assertions and 16 holds**. Replacement can explicitly
move a facet or activity fit into a supported detail without losing its source
claims. A rejected fit does not delete the underlying transcript observation.

34 reviewed items have unchanged claim bindings and qualify for source discovery.
They are candidates for retrieval, not approved planner facts. Current trip dates,
canonical identities, services, entrances, hours and availability remain separate
requirements. All 136 manual decisions bind to the exact original entry and
selected source-claim content hashes; zero manual claim bindings are stale.

## Artifacts and replay

Audit:
`.local/stage3/planner-release-v1/manual-completion-v1/audit-b4f5767535041891/audit.json`.

Final annotation layer:
`.local/stage3/planner-release-v1/manual-completion-v1/e9901a9218c0e656/effective-annotations.json`.

Human-readable before/after report:
`.local/stage3/planner-release-v1/manual-completion-v1/e9901a9218c0e656/correction-report.md`.

```sh
cd /Volumes/CrucialX9/Code_Backup/Trippy/project
.venv/bin/python -m trippy.research.manual_completion --recipe .local/stage3/planner-release-v1/manual-completion-v1/audit-b4f5767535041891/recipe-v2.json
```

Replay is offline and produces the same immutable annotation artifact. Original
AI receipts, reservations and the frozen completion queue remain unchanged.
The 20 previous manual annotation reviews are preserved separately in the output.
The scratch output `b8e4d8e98610430c` is superseded by the artifact above, which
also carries those preserved reviews and the final validation engine binding.

## Limits of this correction

This is the final manual pass for these 136 flagged annotation handoffs. It is
not a full manual certification of all dataset statements. Of the 1,851 newly
reviewed annotation slots, 1,715 were outside this manual pass and remain marked
`manual_review_pending`; their automated proposals are retained without inheriting
manual eligibility. The 20 older manual reviews are additional and preserved.

Source claims were not changed or automatically accepted by this layer: the
recovered source pack remains 1,987 staged active / 41 held, conserving all 2,028
claims. The active manually curated source pack remains 1,781 active / 247 held.
Pending source repairs/ambiguous identities, Moco's conflicting operator addresses,
the three MOOD branch questions and actual planner scenarios remain separate work.
No source or planner release is implied by the annotation correction.

296 unittest tests pass, including stale-input/evidence rejection, visit-level
recommendation retention, explicit cross-kind migration, original-data preservation,
and refusal to reuse an annotation after its current claim changes. Real replay
matches the immutable output. No paid or HTTP calls were made.
