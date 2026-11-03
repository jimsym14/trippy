# Extraction quality gate

Implemented 30/10/2026. This stage hardens extraction before the remaining
37 chunks or catalog enrichment. Quality gates are explicit fail-closed checks;
passing schema or quote validation does not prove facts or completeness.

## Evidence and execution

- Prompt v2 is now the preparation default. Frozen v1 is still selectable and
  both versions validate against their own exact prompt/schema/payload
  fingerprints. Existing manifests and caches remain reproducible.
- Validate each mention separately. Invalid mention schemas, unsupported name
  anchors and forged citations cannot discard unrelated valid mentions.
- A quote uniquely matching up to four adjacent original cues is split into
  exact substrings with the original cue IDs/times. Joining those substrings
  must reproduce the original model quote byte-for-byte. Changed words,
  omitted cue IDs, ambiguity and external sources cannot be repaired.
- Validate claims/ratings individually. Preserve quarantine and repairs inside
  the evidence cache, including on replay. A partial valid response is retained
  with a partial-validation diagnostic rather than automatically paying for a
  full re-extraction. Empty unsupported output can still receive bounded retry.
- Durable monetary/request limits, raw completions and usage receipts remain.
  No reset of the existing $1 ledger or Sol fallback.

## Semantic review and coverage

`trippy.sources.quality` accepts a retained report, prepared evidence and a
versioned reference inventory. It checks source receipts, prepared fingerprints,
exact reference name anchors, source/cue identity and required claim dimensions.
Missing targets fail the benchmark. Original source cues are also listed for coverage disposition; uncited cues are exposed for review without assuming they are all actionable. Exhaustive approval requires a reasoned disposition for every cue and target links for actionable cues. Wrong field assignments can have exact
citations and still fail semantic checks; historical dates under opening_hours
are an implemented conservative review signal, not a general semantic detector.

The committed Barcelona reference has 23 targets: critical Greek/English
recommendations and selected practical claims. **It is explicitly not an
exhaustive reference inventory.** Partial sample coverage cannot approve scaling.
This avoids declaring a pipeline complete based on a convenient sample.

Every retained mention requires a content-fingerprinted semantic review before
approval. Review annotations record a reviewer, source comparison method and
rationale. Changing name/claims/citations invalidates the annotation. Bare
approval flags and stale content keys are rejected. A full reference inventory,
100% reference coverage, no unresolved semantic signals and completed semantic
review are all required for `ready_to_scale_extraction`.

For publication, identities and current fact checks are additional gates.
Overture suggestions remain proposals; identical names or shared candidate IDs
cannot automatically establish a branch. Hours, prices and other live fields
are unverified until checked. Review annotations are local review records, not
cryptographic proof that a fact check occurred or a substitute for authoritative
field evidence. The quality module makes no remote writes.

The bulk extraction CLI (`--execute-luna`, more than six chunks) requires
`--quality-report` from the same prompt version with passed benchmark/review
measurements. Bounded pilots remain available for evaluation. All reports remain
private drafts; the tool does not publish to the catalog.

## Organizing the output

Repeated wording with identical dimension/basis/date/citation evidence is grouped
into evidence bundles. All variants remain available: shared evidence does not
prove semantic equivalence. Counts distinguish raw claim records and bundles.
Dish/neighborhood/branch/transport observations have explicit subject draft IDs,
predicates and citations. Their objects are source text, not invented resolved
entity IDs; graph identity and retrieval integration remain separate work.

Description chapters and commercial/self-promotional disclosures retain their
own metadata hash, field/line and exact text. Chapter names may help resolve ASR
spellings, but they are not presented as spoken quotes or verified identities.
Commercial context does not establish paid venue sponsorship.

```bash
.venv/bin/python -m trippy.sources.quality \
  --report .local/stage3/sources/barcelona-luna-quality-v2-result.json \
  --prepared .local/stage3/sources/barcelona-luna-quality-v2-prepared.json \
  --reference configs/source_research/barcelona-pilot-reference-v1.json \
  --output .local/stage3/sources/new-quality-review.json
```

Optional `--annotations` is a JSON mapping from each evidence bundle's
`review_key` to a record such as:

```json
{
  "semantic": "approved",
  "review_method": "manual_source_comparison",
  "reviewer": "reviewer identity",
  "reason": "Source comparison and disposition of ambiguity"
}
```

Identity/current-fact review stays pending unless explicitly reviewed. Do not
bulk-fill approval records or change the reference scope to force a green gate.

## Evaluation boundaries

The regression suite verifies recovery, forged/ambiguous/omitted evidence
rejection, independent schema/claim quarantine, cache persistence, versioned
fingerprints, reference/annotation identity, semantic blockers and bulk gating.
These tests establish implementation behavior, not empirical model accuracy.
The six-call v2 evaluation reuses the same two videos with no automatic retries;
results and exact spending are recorded in IMPLEMENTATION_STATUS.md.

## Latest outcome

Six real v2 calls, no retries: 23/23 critical targets, four quarantined mentions.
Nine explicit editorial decisions correct source-context field/kind errors and
exclude an unclear ASR venue candidate. Final output has 70 private mentions and
220 claim records. Total shared reservation is $0.6355612 of the authorized $1.
The exhaustive semantic/cue coverage gate remains blocked; no bulk extraction or
publication occurred. `trippy.sources.curation` applies reviewer/rationale and
before-content/claim-fingerprint-bound decisions, preserving original records,
quotes, exclusions and identity proposals. It does not perform fact-checking.

Numeric-price diagnostics compare cited digits/simple number words, with decimal normalization. They are conservative review signals, not a general multilingual numerical-entailment evaluator. Unknown or uncertain source-cue dispositions cannot approve bulk execution.
# Completed final pilot coverage audit

The current additive contract and outcomes are in
[TRANSCRIPT_COVERAGE_AUDIT.md](TRANSCRIPT_COVERAGE_AUDIT.md). V3 completed 18
keyed windows from the existing two pilot sources. `--complete-pilot-audit` is a
bounded source-preserving pilot audit, not permission to extract the remaining
videos. Whole-run budget preflight, exact cache fingerprints and request ceilings
remain mandatory. The shared user-authorized cap is $2 for the large-video pilot;
final reservation is $1.8657948.

Raw sample coverage is 29/32; explicit targeted source review reaches 32/32 with
73 draft records and 460 claims. The reference remains non-exhaustive. Complete
cue inventory includes 195 uncertain cues, including 123 exact-evidence fallbacks
for failed model references. Fallback accounting never approves semantic content.
Source-review findings require content-bound resolutions; a zero diagnostic count
does not remove exhaustive semantic, identity/branch or freshness requirements.
Both scale and publication gates therefore remain closed.
