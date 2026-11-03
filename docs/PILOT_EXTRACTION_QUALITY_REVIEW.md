# Luna pilot: transcript and product comparison

Reviewed 30/10/2026. Scope: the two pilot videos' supplied transcript cues,
retained draft output, quarantine, source metadata and extraction contract.
This is a targeted qualitative audit, not an exhaustive annotated precision/
recall benchmark or verification against the original audio/current venue facts.
No new model calls, web research or catalog writes.

## Verdict

Useful extraction of recommendations, dishes, neighborhood context and source
opinions. Not yet complete or reliable enough to become the curated catalog or
feed an itinerary without review. All six chunks returned complete responses;
that establishes execution coverage, not complete extraction of their contents.
64 mentions / 55 possible identity groups / 221 claim records are not counts of
unique verified places or facts.

## Concrete transcript comparisons

| Source evidence | Retained result | Assessment |
|---|---|---|
| Spain Revealed cues 203–215: crowded standing bar, grilled food, approximately €3, cheap cava | Can Paixano preserves crowding, dishes, historical price and recommendation | Useful detail; 2019 publication means price is not current. |
| Spain Revealed cues 228–250: rustic local atmosphere, seafood/bomba, early arrival, 9 a.m.–3 p.m. kitchen and uncertain weekend exception | `lakova fumada` preserves most of that context, including uncertainty | Good practical extraction, unresolved ASR identity and current hours. |
| Dousis cues 543–548 explicitly say they did not reach Casa Batlló or Sagrada Família in this episode | Retained claims preserve non-visit and experience is unknown | Correctly avoids inventing a first-hand visit. |
| Dousis cues 484–511 describe a substantial Casa Milà visit | Extracted but absent from retained drafts; one response combined cues 484/485 into one quote | Material pipeline recall loss through invalid citation formatting. |
| Spain Revealed cues 145–172 describe `la pinera`; description chapters name LA PINEDA | Extracted in both attempts but absent from retained drafts; quote spans cues 145/146 | Material loss; separate cues and separately sourced chapter identity evidence are needed. Official identity remains unverified. |
| Dousis cues 280–288 recommend the café rendered Τουλτσινέα / Δούλτσινέα and its churros | Greek mention is quarantined for missing original-name anchor | Lost Greek recommendation and potential cross-language corroboration; do not merge with Granja Dulcinea until identity is resolved. |
| Spain Revealed cue 82 says Casa Gispert was founded in 1851 | A retained claim labels this `opening_hours` | Semantically incorrect field, despite an exact supporting quotation. |
| Dousis cue 69 names the market as `λαμποκερία`, followed by `η αγορά της πόλης` in cue 70 | Generic `Αγορά της πόλης` retained without identity uncertainty | Canonical identity is unresolved; generic name should be uncertain. |
| Dousis cue 68 names Palau de la Virreina; cue 69 moves to the market | Retained location claim cites both cues | Entity attribution needs correction/review; adjacent text is not automatically about the same place. |
| Spain Revealed promotes its own tour in speech/description | No retained sponsorship claims | Source commercial/self-promotional relationship needs explicit handling. This does not establish that venues paid for coverage. |

The model detects many important recommendations. Some apparent missing places
were actually detected by Luna and then rejected by local validation. Improving
the prompt alone is insufficient: preserve exact multi-cue citations and audit
retained coverage after validation. Never accept fabricated quotations.

## What exists and what is missing

| Puzzle piece | Current state |
|---|---|
| Controlled creators/languages/source acquisition | Implemented; 24 receipt-audited transcripts, two videos extracted in this pilot. Final editorial/source breadth remains unproven. |
| Transcript evidence and exact traceability | Implemented with quotes, cue timestamps, source hashes and raw responses. ASR name/number accuracy is not verified against audio. |
| Categories and detailed observations | All 17 categories can be represented. Actual pilot uses 12; no clubs/day trips/tickets/family accessibility/other assignments. This is not evidence those topics are absent from Barcelona. |
| Detail fidelity and completeness | Useful but flawed: wrong dimensions, compound assertions, cue attribution and quarantined key recommendations. No complete recall measurement yet. |
| Deduplication | Exact replays consolidate. Paraphrases, Greek/English names and separate occurrences remain; Can Ramonet and translated landmarks demonstrate this. |
| Overture matching | Read-only proposals against the broad inventory exist. Only 13 of 47 venue mentions have candidates; none is confirmed by this audit. Bar Joan has two different addresses; Hofmann has restaurant/pastry branches. Name matching cannot select the right branch. |
| Relationships | No explicit typed venue–dish, venue–district or route–stop relations in the extraction schema. Much context is stored in freeform claim values; structured retrieval still needs integration. |
| Freshness, official facts and ratings | No independent current verification. Zero ratings is appropriate because this pilot provides no accepted explicit platform /5 evidence. Never substitute views or enthusiasm. |
| Source independence and commercial context | Same-channel retries do not add publishers. Self-promotion/affiliation, copied-source relationships and source reliability need further review. |
| Personalized retrieval | Freeform niche claims can be retained. Neighborhood/style/constraint retrieval, normalized tagging, coverage-gap search and preference compiler are not established by this pilot. A mention category is not a complete personalized recommendation. |
| Publication and app flow | No enriched catalog publication, Supabase transfer or native integration from this pilot. Map search/save and user video-link flows remain separate implementation work. |

Retained claim dimension counts include: address 0, website 0, booking 0,
duration 0, accessibility 0, dietary 0, allergies 0, music 0; price 1, queue 1,
opening_hours 4 (three are historical-age/founding misclassifications). Absence
must stay unknown; videos cannot supply every factual/constraint field. It is
not acceptable to fill those fields from model memory.

## Quality gate before scaling

1. Build an annotated reference inventory of actionable places and claims for
   these two videos, with exact cue references. Measure place recall, claim
   fidelity, category correctness and uncertainty rather than output length.
2. Correct anchored names, multi-cue citation formatting and semantic field
   errors, retaining originals. Evaluate candidate prompt v2 on the same sample;
   do not assume its unexecuted changes solve the observed issues.
3. Resolve multilingual identities/branches using original audio where needed,
   chapter metadata as distinct evidence, and authoritative identifiers or
   addresses. Preserve unknowns and conflicts.
4. Normalize useful observations and relationships for retrieval, deduplicate
   paraphrases while preserving source evidence, and record commercial context.
5. Extract the remaining videos, audit category/geographic/niche gaps, then
   obtain current factual checks before selecting/enriching/publishing ~500.

Luna remains the only model. This pilot does not demonstrate a need for Sol;
several failures arise from evidence handling, ASR and schema/retrieval design.
