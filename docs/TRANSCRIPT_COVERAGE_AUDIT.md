# Final transcript retrieval and review design

## Current contract: required per-cue accounting v3

**Completed outcome, 30/10/2026:** all 18 windows returned complete responses.
The raw model pass has 73 mention records / 457 claims and covers **29/32**
selected reference targets. Source review adds three venue-linked claims and
applies 15 content-bound editorial decisions across two passes, yielding
**73 records / 460 claims, 32/32 reference targets, zero known diagnostic
blockers**. The two idiom translations, inferred wine-vessel name, palace/street
attribution errors and missing exact citation support were repaired. Original
claims, target records, quotations and editorial history remain retained.
The manually supported Bar Joan–market relationship is explicit; the model's
La Campana–turrón and route–palace proposals remain preserved. This is a targeted
source comparison, not exhaustive semantic approval or independent fact-checking.

All **859 unique cues** have required keys. The model still proposed unsupported
links for **123 cues**, with only three windows passing every link check unaided.
`retain_unresolved_cues` preserves those cues as exact, cited **uncertain review
issues**, with unchanged raw outputs and repair lineage. The resulting review
inventory accounts for all 859 cues, including **195 uncertain cues** (123 from
this deterministic retention plus 72 originally uncertain). Complete evidence
accounting does not mean complete fact extraction or approved interpretations.
The original failed model ledger remains available separately.

The expanded reference remains non-exhaustive; all 73 records still need complete
semantic review. Fifty-two explicitly mark identity uncertainty; the quality gate
has 61 unresolved venue/route/district identity decisions. Current operational
facts remain unverified. Zero /5 scores were invented. **Scaling and publication
remain closed.** No remaining-video generation or Supabase writes occurred.

The shared conservative reservation finished at **$1.8657948 / $2 USD**. The
complete v3 pass used 18 calls: two already evaluated/cached and 16 new calls.
Including preceding v1/v2 evaluations, this additional-audit stage made 29 calls.
There were no automatic retries or Sol fallback. Reservation is not an invoice;
an older diagnostic usage receipt remains missing.

Current final artifacts in `.local/stage3/sources/`:

- `barcelona-coverage-v3-final-source-fixed.json`: final source-reviewed private draft.
- `barcelona-coverage-v3-final-source-fixed-quality.json`: 32/32 sample gate, no diagnostic blockers, review gates closed.
- `barcelona-coverage-v3-final-review-inventory.json`: complete cue inventory, explicit uncertain evidence and repair lineage.
- `barcelona-coverage-v3-final-prepared.json`: exact live prompt/schema/window manifest.
- `barcelona-coverage-v3-final-result.json`: preserved unedited full model output.
- `barcelona-coverage-v3-final-editorial-decisions.json` and `barcelona-coverage-v3-final-source-fix-decisions.json`: the two editorial passes.

Validation: **183 tests passed**; `git diff --check` passed. These verify code
safeguards, not exhaustive semantic accuracy. Next review must resolve uncertain
source passages, remaining claim interpretations, canonical branches and current
facts before running the other 37 chunks. Finite evidence preservation is the
fallback when extraction cannot confidently resolve a detail.

The current final run uses `coverage-audit-prompt-v3.md`. Each of the 18 disjoint
pilot windows has a generated strict schema with **every core cue as a required
key** in `cue_coverage`. Context keys, omitted keys and duplicated list entries
cannot satisfy the contract. Citation segment IDs and entity target IDs are
restricted to supplied evidence. Validators still check quotations, target
anchoring, evidence references and semantics separately; required keys do not
prove that every assertion was extracted.

Two live v3 tests returned complete responses with every expected core key, no
quarantined proposals and a La Campana–turrón relationship proposal. They still
had nine cue-reference problems across the two windows. The reference benchmark
is 28/32, so semantic/identity/freshness gates remain closed. A Greek idiom rendered
literally as tourists stepping on geese is now a named semantic diagnostic.

The full v3 audit of the **same two pilot videos** completed: 18 windows,
two reused from cache, 16 new calls, one attempt each. Worst-case shared reservation
is $1.8657948. The user authorized $1.50 normally and up to $2 for large videos;
the configured cap is $2 for this complete pilot audit. The original ledger is
preserved. None of the other videos, public catalog or Supabase records is included.

`--complete-pilot-audit` allows up to 18 keyed windows from at most two existing
pilot sources. Default live evaluations remain limited to six windows. Whole-run
preflight reserves only uncached requests; cache fingerprint checks remain mandatory.
Partial-window evaluations retain the complete original base evidence without
sending all of that evidence to the model again. Original source evidence is
validated before any call.

Current private manifest: `barcelona-coverage-v3-final-prepared.json`.
Preserved live output: `barcelona-coverage-v3-final-result.json`.
The historical v1/v2 results below document the failures that led to this contract.

30/10/2026. This stage adds evidence to existing extraction; it does not regenerate
the catalog, verify current facts, publish records or execute the remaining videos.
Luna remains the only model. Original reports, transcripts and paid receipts are preserved.

## Actual additional-pass evaluation

Six calls were made on the same two pilot videos, one attempt per chunk. Five
returned complete responses. The second Greek chunk exhausted its 16,000-token
completion allowance entirely in reasoning and returned no usable content. Its
raw response and reservation remain recorded; no hidden retry was made.

Current-validator offline replay retains **69 mention records / 294 claims**, versus
70 / 220 before the audit: 74 additional citation-valid claim occurrences, with
the overlapping case variants of Can Ramonet consolidated conservatively.
Uncertain identity remains uncertain. These are neither unique places nor verified facts.
There are 23 accepted review issues, three quarantined proposals and zero accepted
structured relationships. No registry identity was guessed: 20 exact bare-ID
references across the responses were repaired to
`mention:ID`, with individual receipts. Other unknown references remain rejected.

The expanded regression benchmark moves from **26/32 to 27/32**. It is not an
exhaustive recall or accuracy score. Remaining targets are the cathedral warning
indexed as safety, Can Ramonet's wine demonstration, the two La Campana product
associations, and the structured Bar Joan–market association. The warning text and
turrón varieties now exist, but bundling and missing relationships prevent useful
retrieval. None of the five responses passes complete cue accounting: 66 groups
have validation problems, one returned chunk omits a cue, a whole chunk is absent,
and one overlapping cue has conflicting dispositions. The ledger proposes
dispositions for 614 of 859 unique cues; that is not proof their details are captured.

Targeted transcript comparison records 12 content-bound findings. Examples:
palace architecture attached to Las Ramblas; street history attached to the
Gothic Quarter; an expensive-area assertion supported only by “we will see two
things”; and a historical year missing from the selected citations. Exact quotes
alone cannot prevent incorrect subject attribution or unsupported paraphrases.
These findings are preserved rather than silently corrected or treated as approval.

## Revised final run

`coverage-audit-prompt-v2.md` and `prepare_final` implement the revised offline design:

1. Inventory every original cue independently. Use disjoint cores of at most
   50 cues and 12 neighboring context cues on either side. The two pilots produce
   18 windows. Context supports continuity but is never counted as another core.
2. Supply local entity targets, local existing claims and an explicit per-cue
   index of existing evidence references. A compact same-video name index supports
   orientation without making distant entities convenient targets for any fact.
3. Recover missing atomic assertions: products, textures, experiences, architectural
   features, tips, warnings, opinions, negative advice and historical assertions.
   Use separate dimensions and retain original ASR uncertainty. No category is
   filled from memory, and opinions never become /5 platform scores.
4. Check the grammatical subject and visit sequence. Establish venue–product,
   market and itinerary relationships using exact association evidence; preserve
   unresolved links as issues. A nearby place name is insufficient attribution.
5. Supply transcript-review feedback bound to the exact base and claim fingerprints.
   The model must re-read evidence, retain conflicting original claims and propose
   corrections for review. Feedback is untrusted data, not replacement truth.
6. Validate schema, exact quotations/times, source/target references and each core
   cue's evidence accounting. Quarantine unsupported proposals; retain raw failures.
   Check overlapping dispositions and preserve prior editorial/review provenance.
7. Compare all cue dispositions and proposed claims against the transcript,
   including context/non-research exclusions. Resolve semantic corrections and
   relations explicitly. Apply the expanded benchmark, then build an exhaustive
   actionable inventory. A model cannot approve its own coverage ledger.
8. Resolve canonical names/branches against suitable identity evidence such as
   Overture/MapKit; independently check sensitive or changeable facts against
   authoritative sources. Historical video prices, hours and safety assertions
   remain source observations until checked. Publication remains a separate gate.

The v2 compact design was prepared and evaluated. The live
CLI accepts a fingerprint-checked `--audit-manifest` and remains limited to six
windows per pilot. `--window-indices` selects representative windows during
offline preparation. Each evaluation has a durable request ceiling, one attempt
per window and whole-run budget preflight. `--prepare-final` is offline only. An 8,000
output-token allowance is a preview assumption, not a validated truncation fix.
First evaluate representative Greek/English windows before running all 18.

## Budget and evidence

The six new calls conservatively reserve **$0.3028665**. The original shared
ledger totals **$0.9384277 / $1 USD**, without reset. This is a reservation ceiling,
not actual invoiced cost; an older diagnostic usage receipt remains missing.
The compact 18-window preview reserves $0.5398902 at an 8,000 output-token cap.
After this first evaluation the user raised the shared cap to **$1.50**, with
**$2 available if needed for large videos**. The configured normal cap is now
$1.50; the existing ledger is preserved. A two-window v2 evaluation was started
under that cap, with 16,000 output tokens to measure actual completion needs.
No Supabase writes, publication or UI changes were made.

Private artifacts in `.local/stage3/sources/`:

- `barcelona-coverage-v1-reviewed-result.json`: current-validator replay and final check queues.
- `barcelona-coverage-v1-quality.json`: expanded 27/32 evaluation.
- `barcelona-coverage-v1-semantic-findings.json`: 12 targeted transcript findings.
- `barcelona-coverage-v2-final-reviewed-prepared.json`: current final prompt, windows and feedback.
- `barcelona-coverage-v2-final-reservation-preview.json`: offline cost ceiling preview.

Earlier prepared variants remain preserved; the v3 manifest above is the current
design. Replays never silently use a changed prompt or base.

```bash
.venv/bin/python -m trippy.sources.coverage \
  --base .local/stage3/sources/barcelona-luna-quality-v2-curated-final.json \
  --extraction .local/stage3/sources/barcelona-luna-quality-v2-prepared.json \
  --replay-cache --output .local/stage3/sources/new-audit-replay.json

.venv/bin/python -m trippy.sources.coverage \
  --base .local/stage3/sources/barcelona-coverage-v1-reviewed-result.json \
  --extraction .local/stage3/sources/barcelona-luna-quality-v2-prepared.json \
  --review-findings .local/stage3/sources/barcelona-coverage-v1-semantic-findings.json \
  --prepare-final --output .local/stage3/sources/new-final-design.json
```

Missing cached responses remain explicit failures in offline replay. New output
paths prevent overwriting prior artifacts. Python tests verify deterministic
safeguards; they do not certify semantic recall or factual accuracy.

OpenAI's [Structured Outputs documentation](https://developers.openai.com/api/docs/guides/structured-outputs)
explicitly distinguishes schema adherence from content correctness and recommends
simpler subtasks when mistakes occur. This is why the final design narrows windows
and requires independent transcript comparison rather than relying on valid JSON.
