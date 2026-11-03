# Barcelona correction process audit — 1 November 2026

The iterations improved source disposition and corrected concrete interpretation
errors. They preserved the stored information. They have not yet demonstrated
better application retrieval or complete personalized plans. No defensible overall
accuracy or product readiness percentage is available.

## Measured before/after

| Measure | Before | After | Meaning |
| --- | ---: | ---: | --- |
| Active source claims | 1,781 | 1,986 | 205 previously held slots admitted after source comparison |
| Held source claims | 247 | 42 | Ambiguity remains visible, including four prior manual holds |
| Source claim occurrences conserved | 2,028 | 2,028 | No stored source slot deleted or invented |
| Editorial admission coverage | 87.82% | 97.93% | +10.11 percentage points; **not truth accuracy** |
| Source record occurrences | 549 | 549 | Records are not unique canonical places |
| Video sources represented | 23 | 23 | This pass did not expand video evidence breadth |
| Full canonical place admissions | 0 | 0 | Source/catalog correspondences are only preliminary links |
| Trip-date verified fields | 0 | 0 | Saved operator evidence does not establish future availability |
| Full itineraries verified | 0 | 0 | Product improvement still needs measurement |

The independent offline audit checked occurrence-key conservation across active
and held claims, unchanged previous record context/claims/decisions, unchanged
annotation originals and decisions, current manual evidence bindings, unchanged
operator/identity inputs, the selected bundle hash, and complete SQLite row parity
with the JSON bundle. These checks passed. They do not establish that every useful
detail in the original full videos was extracted, or validate every source claim
against independent current evidence.

## What improved, and what became harder to retrieve

The source pass accepted 147 repairs, supported 58 originals, and held 38 pending
slots. Concrete semantic improvements include keeping the Hotel Colón Cathedral
view separate from adjacent Sagrada Família advice, treating the sixteen-hour bench
anecdote as historical commentary rather than visit duration, treating 1,200 meters
as length rather than duration, and restoring three matching source cues that AI
had replaced with neighboring cues. These are meaningful corrections, not merely
increases in admission counts.

The 136 manually reviewed annotation handoffs resulted in 51 replacements, 40
retentions, 14 context dispositions, 15 rejections and 16 holds. Original proposals
and provenance survive every disposition. All 1,851 new annotation slots and 20
older manual reviews remain stored. There are also 49 retained unapplied suggestions.

37 reviewed annotations moved from `facet` to `detail`, and three from
`activity_fit` to `detail`. This improves scope accuracy but reduces direct filter
access unless a consumer explicitly retrieves descriptive context. Some moves
reflect missing taxonomy values, such as church, stadium, plaza and food hall;
these should become reviewed typed values when the registry and reader are
integrated. Do not infer these types anew from prose on every request.

427 new upstream AI results carry a discovery-candidate flag. These are proposals,
not 427 approved items. Only 34 new annotations and eight prior reviews are
currently source-discovery eligible. 1,715 new slots remain manually pending,
with current claim bindings; their pending status does not establish that they are
wrong. The new eligible pool includes one `coffee_break`, one `breakfast_out`, one
`local_market` activity fit, and two breakfast meal-context facets. These are
annotation counts, not a city-wide supply of unique verified venues. This audit
does not compare that small pool with all baseline discovery capabilities.

The 35 confirmed annotation/subject/fit errors found in the earlier targeted
manual pass came from a deliberately selected problem set. They cannot be
extrapolated into a percentage of errors across the whole dataset.

## Consumer gap

Inspection of `trippy/planner` found no reader of `active-dataset.json` or the
integrated `dataset.sqlite`. `knowledge.py` builds a separate snapshot from
primary observations and optional identity decisions; its build still emits empty
facets and candidate identities. The activity registry explicitly remains
`draft_not_integrated_with_ui_or_planner`.

The SQLite edition therefore improves storage, reproducibility, traceability and
indexing. It does not by itself establish that application filters retrieve more
useful places. No map/filter or full-plan before/after benchmark was run here;
claiming a product performance gain would be premature.

## Small next completion path

1. Connect one versioned reader to the selected edition, exposing source
   recommendations separately from canonical/current facts. Add reviewed missing
   taxonomy values and exercise coffee, breakfast/brunch and groceries filters.
2. Resolve identities and branch conflicts for the actual candidate shortlist.
   Deterministic matching proposes candidates; primary pages or provider IDs supply
   evidence; manual review handles conflicts such as Moco addresses and MOOD branches.
3. Fetch volatile fields only for selected places and trip dates, with provenance,
   field freshness and explicit unknowns. Places/route providers help addresses,
   coordinates, categories, hours and travel; ticket/table availability requires
   providers that actually expose that capability.
4. Run full personalized scenarios and compare preservation, correct exclusions,
   relevant filter results, schedule feasibility and output detail with `chat.md`.
   Only those measured results can support a product readiness claim.

One command can orchestrate these stages with checkpoints and bounded retries.
One AI correction script cannot guarantee greater than 95% overall correctness.
Luna should extract or propose changes from supplied evidence; deterministic code
should enforce bindings, conservation and eligibility. Conflicting subjects and
unsupported current facts need additional evidence or manual adjudication.
The recorded completion run had `web_search_connected: false` and zero configured
operator API feeds. HTTP fetching of operator pages was separate from Luna;
do not assume that a Luna response searched the web.

No new bulk AI run, paid call, HTTP request, publication or planner gate promotion
was performed for this audit. Existing source corrections are already materialized.

## Reproduce

```sh
.venv/bin/python -m trippy.research.dataset_audit \
  --selection .local/stage3/planner-release-v1/active-dataset.json \
  --recipe .local/stage3/planner-release-v1/integrated-dataset-v1/audit-f83c88d1ff9219b2/recipe.json \
  --output-root .local/stage3/planner-release-v1/process-audit-v1
```

Measured artifact:
`.local/stage3/planner-release-v1/process-audit-v1/ac845b6efe97865e/audit.json`.
This is a read-only verification of the selected dataset; it writes its own audit
artifact and does not repeat paid extraction or modify the selected edition.
