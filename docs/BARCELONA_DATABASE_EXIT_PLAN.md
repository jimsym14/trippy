# Database exit plan — 2 November 2026

Decision: use the selected editorial edition as the frozen research input now.
Do not repeat global video extraction, semantic review or annotation review to
raise a general readiness percentage. Database pilot acceptance is a bounded
consumer evaluation followed by fixes to demonstrated failures. Application UI
and live provider integration are separate deliverables.

## What the history actually shows

At least twelve distinct processing/review stages are identifiable in the saved
artifacts. This count excludes transcript acquisition/extraction, retries,
protocol-version experiments, scratch editions and repeated checkpoint replays.
It is a count of stages, not twelve complete rewrites of the database.

| Stage | Saved work |
| --- | --- |
| 1 | Main semantic campaign: 82 prepared batches for 2,028 claims |
| 2 | Offline source disposition of 43 missing/invalid reviews |
| 3 | 99 manual source adjudications and initial materialization |
| 4 | Targeted semantic campaign: 40 prepared batches for 313 claims |
| 5 | 70 expanded-context manual followup adjudications |
| 6 | Capability/detail campaign: 114 prepared batches |
| 7 | Offline recovery of all 114 responses and annotation quarantine |
| 8 | Completion campaign: 179 fixed AI jobs plus operator fetch/extraction work |
| 9 | Per-item recovery of 243 source slots and 1,826 annotation decisions |
| 10 | 136 manual annotation handoffs reviewed |
| 11 | 243 final manual source dispositions and integrated SQLite edition |
| 12 | Conservation audit, reader/typed migrations, retrieval and draft checks |

Four large AI campaigns revisited overlapping source evidence. The last source
edition conserves all 2,028 slots, with 1,986 active and 42 held. The new reader
exposes 48 admitted annotation items including six typed migrations. Neither
source admission coverage nor the count of passing tests measures usable city
coverage or complete itinerary quality.

## Root causes confirmed in code and outputs

1. We worked on the source archive before establishing one complete consumer
   scenario and a stable acceptance definition. New passes introduced new
   handoffs instead of resolving the main integration dependency.
2. The reader requires manual approval for every admitted source-discovery
   annotation. There are 1,715 manually pending proposals; this does not mean
   1,715 wrong annotations. Applying the same approval gate to exploratory
   recommendations and operational hard constraints creates a discovery bottleneck.
3. The runner does not apply canonical identity decisions to source occurrences.
   It constructs `canonical_id: null`, unknown coordinates and `pin: null`.
   Important readiness flags are hardcoded false; no additional run can clear
   them through better source evidence alone.
4. Places/Routes are not integrated into this Python campaign. The iOS app has
   existing MapKit search uses; that does not supply this campaign's identities
   and routes. Operator fetching supplies observations but no automatic final join.
5. The last demo is coffee/breakfast at La Boqueria at 10:00 on each of three
   synthetic days. It proves optional activity merging, not complete planning.
   It has no route validation or known cost total. The four-query benchmark and
   sixteen behavior cases are useful but too narrow for product acceptance.
6. Several reported category gaps are composition controls rather than missing
   venue classes: breakfast at stay, photowalk and picnic should not each require
   a bespoke place tag. Market visit, grocery shopping and supermarket must also
   be distinguished. Otherwise we create unnecessary research work.

## Bounded completion sequence

### Deliverable A: one real consumer evaluation

Create a fixed Barcelona three-day test trip with a declared stay location,
arrival/departure windows, pace, budget basis, exclusions and optional activities.
Dates can be explicit test dates; do not label them as the user's actual trip.
Use the current archive and existing basic place inventory. Evaluate a complete
day-by-day guide: sights, meals, pauses, transfers, source tips and alternatives.
Classify every failure as missing evidence, identity conflict, consumer exclusion,
composition defect or presentation defect. A zero-result query alone must not
start a city-wide enrichment run.

This requires an actual full-day composer/consumer path; the current coffee-only
draft cannot be promoted into that test by changing a readiness flag.

### Deliverable B: fix only failures that prevent that scenario

- Admit source-bounded provisional recommendations through an explicit discovery
  tier when schema/evidence/subject checks pass; keep proposal and certainty labels.
  They cannot satisfy hard allergy/access/availability constraints.
- Apply canonical/source identity links for the scenario shortlist and preserve
  occurrence lineage. Resolve La Boqueria duplicate references and vendor/market
  relationships without losing the associated source tips.
- Use provider category/area discovery for practical gaps such as supermarkets,
  cafés and brunch. Default relevance is proximity to stay/selected routes, not
  research of every business in Barcelona.
- Add one configured place provider and one route source to the consumer.
  Provider/official pages supply address/category/hours/menu observations. Store
  their scope and timestamps; cache expiry is not a guarantee of future availability.
- Use manual review for conflicts and critical ambiguous shortlist subjects.
  Use Luna for bounded source extraction/ranking explanations where deterministic
  mapping does not suffice. No new general "review everything" prompt.

Existing data is research-ready. Scenario-ready places must have usable identity
and location, relevant typed category/service evidence and enough operational
information for the requested selection. Estimates remain estimates; unknown
information remains visible. No requirement to manually review all proposals.

### Deliverable C: acceptance and stop rule

Run three fixed full scenarios: balanced sightseeing, coffee/brunch preferences,
and breakfast at stay with supplies. Require:

- No lost source provenance, altered locks or ignored hard exclusions.
- Correct market/vendor/branch identity and usable location for selected stops.
- Relevant map layers and plan/all scopes on the consumer output.
- Non-overlapping draft schedules, route estimates with a declared source/mode,
  plausible budget ranges with unknowns and no invented ticket/table availability.
- Source-specific tips, dishes and useful alternatives carried into the guide.
- Attributed provisional recommendations never displayed as verified hard facts.

Use one initial evaluation and one targeted correction/retest cycle as the planned
work. If a case still fails, name the concrete dependency and keep its acceptance
gate open; do not restart bulk database curation. Remaining 42 held claims and
unneeded pending annotations stay outside this acceptance requirement.

The database is accepted for the Barcelona pilot when these scoped consumer checks
pass. Whole-city completeness and remote publication are separate questions.
The app is accepted only after the actual map/filter/panel UI reads the same
consumer output and is visually checked. Do not call JSON export UI completion.

## Ownership and future maintenance

| Component | Responsibility |
| --- | --- |
| Deterministic code | IDs, scopes, typed mappings, exclusions/locks, schedule checks, merging, cache and updates |
| Places/route/operator providers | Geographical and practical observations for shortlisted/selected places |
| Luna | Evidence-bounded extraction and proposals, optional explanations; no connected web search in the current integration |
| Manual adjudication | Conflicting identities/subjects and decisions requiring evidence beyond available provider fields |
| UI consumer | Display the same choices, labels, alternatives, maps and tables with editable selections |

After acceptance, update selected volatile fields when needed and refresh the
source archive only for new evidence or demonstrated errors. Repeated global AI
passes must not be the maintenance strategy. No new paid campaign or API request
was executed to produce this diagnosis.

There is no defensible wall-clock completion promise before the missing consumer
and provider integration is implemented. The finite deliverables above replace
the previous moving "database readiness" target.
