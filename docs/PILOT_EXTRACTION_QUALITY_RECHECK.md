# Latest pilot recheck

Historical pre-audit recheck. The subsequent completed additive run is documented
in [TRANSCRIPT_COVERAGE_AUDIT.md](TRANSCRIPT_COVERAGE_AUDIT.md): raw 29/32;
targeted source-reviewed 32/32, 73 draft records / 460 claims. All 859 cues are
preserved, with 195 uncertain review cues. Semantic/identity/current-fact and
publication gates remain closed. The 26/32 findings below explain that work.

30/10/2026. Compared the final v2 editorial artifact with original timestamped
transcript cues and the product's personalized research requirements. This audit
used local evidence only: zero additional model calls or independent web fact
checks. Original results were preserved.

## Verdict

Useful source research with substantially improved main-place coverage, but
incomplete for the intended catalog and personalized planner. The earlier 23/23
benchmark checked 19 main place mentions and four selected claim targets. It did
not establish complete transcript extraction, correct canonical identities,
resolved relationships, current facts or category breadth.

Expanded reference revision 2 adds practical detail and relationship targets:
**26/32 covered; six uncovered**. This is a deliberately selected regression
benchmark, not an overall accuracy or recall percentage. The reference remains
non-exhaustive. The existing quality gates correctly remain closed.

## New evidence of gaps

| Transcript evidence | Latest output | Finding |
|---|---|---|
| Dousis cues 182–189, 18:29–18:57: the cathedral's geese and warning not to approach because they bite | Cathedral has four history/style/recommendation claims, no geese feature or warning; no other retained claim preserves it | Missing visitor detail and safety caveat. These are source assertions requiring factual review, not independently verified advice. |
| Spain Revealed cues 261–263, 24:33–24:53: rustic wine-drinking recommendation and demonstration at Can Ramonet | Restaurant/dish claims preserve food and history, but omit this experience | Lost unusual experience detail. The vessel's ASR name is unclear; preserve the experience and uncertainty rather than invent an official name. |
| Spain Revealed cues 127–132, 11:33–12:04: soft almond turrón and caramelized egg-yolk variety at La Campana | La Campana and the separate turrón entry preserve ingredients/history/season, not those varieties | Missing distinct products useful for tailored food/shopping research. |
| Spain Revealed cues 28–40 establish the market stop and Bar Joan's relation to it | Bar Joan says it is integral to the market, but has no neighborhood/market relationship field identifying Santa Catarina | Context partly survives in prose; the relationship needed for reliable location retrieval remains unresolved. |
| Overlapping Can Ramonet mentions cite the same cue 251 and have the same source, kind, stance, experience and null branch | Two records named `Can Ramonet` and `can Ramonet`, one uncertain and one not | Duplicate occurrence and inconsistent uncertainty remain. Merge decisions must preserve uncertainty and evidence. |
| La Campana says a special drink is unnamed in its chunk; later same-visit footage names `orchata` before moving to another district | Separate drink entry exists, but the venue–drink connection is not reconciled | Cross-chunk context/relationship review is needed. The connection remains a proposal until reviewed. |

The main missing recommendations found during the first audit are now present:
Casa Milà, the Greek Dulcinea recommendation, and La Pinera (ASR name; chapter
metadata suggests LA PINEDA). This is a material improvement.

## What is genuinely working

- Strong examples preserve specific dishes, opinions, atmosphere, crowding,
  historical prices and early-arrival advice. Hofmann's mascarpone croissant,
  Can Paixano's standing/crowding context, and the espadrille shop's quoted
  prices are captured in the expanded reference.
- Source quotes and timestamps are retained. Citation repair, quarantine and
  editorial correction provenance make failures inspectable.
- The output does not fabricate accepted star ratings: zero /5 ratings is
  appropriate for the evidence available in these two videos.
- Non-visit information for Casa Batlló/Sagrada Família is preserved.

These observations do not certify every one of the 220 claim records.

## Product readiness

The final result contains 70 mention records: 43 venues, seven routes, eight
districts, seven dishes, three cities and two advice records. It is not a list
of 70 resolved unique places. Forty-eight records explicitly mark identity
uncertainty; only 13 records have Overture candidate proposals, none confirmed
by this audit. No branch fields are resolved.

Actual category assignments span ten of the 17 supported categories. The two
videos cannot demonstrate coverage for clubs, day trips, museums, tickets,
transport, dietary or family accessibility. Absence is a gap to research, not
permission to invent choices or infer allergy/accessibility safety from menus
or comfortable seating.

There are zero extracted full-address, website, booking, duration, dietary,
allergy, music or accessibility claim dimensions. Videos naturally omit some
of these; selective authoritative enrichment and normalized retrieval are
needed. Overture/MapKit identity information and current verification have
separate roles from editorial recommendations.

Freshness remains unresolved. The English food tour was published in July
2019. Its prices/hours are historical observations. A further example is the
cathedral claim combining a 1280 start, early-20th-century completion and
about 700 years: the source itself contains an apparent numerical
inconsistency. Faithfully quoting a claim does not establish its truth.

Still required: broader transcript coverage and semantic review, original-name
and branch resolution, deduplication, venue–dish/market/route relationships,
normalized niche/style retrieval, category-gap research and selective current
fact checks. Those are concrete remaining pieces; passing Python tests or
matching all main venue names does not replace them.

## Reproducible artifacts

- Reference: `configs/source_research/barcelona-pilot-reference-v2.json`.
- Private audit: `.local/stage3/sources/barcelona-luna-quality-v2-expanded-recheck.json`.
- Source result: `.local/stage3/sources/barcelona-luna-quality-v2-curated-final.json`.

Run the offline quality CLI with the new reference and a new output path to
reproduce the 26/32 result. No original output, budget ledger, public catalog,
Supabase data or native UI was modified in this audit.
