# Creator discovery and transcript extraction

Implemented 30/10/2026. Current batch outcomes are recorded in
`IMPLEMENTATION_STATUS.md`; earlier 20-video discovery is a technical pilot.

## Default creators

Both Barcelona profiles reference `configs/source_research/creators.json`.
It includes official channel IDs for Tasos Dousis / Εικόνες, Ευτύχης Μπλέτσας /
Happy Traveller, Tripment, Patrick Guide Barcelona, Happy to Wander,
Spain Revealed, Rick Steves' Europe and Wolters World. Toggle `enabled`, edit
languages or replace verified IDs there. Active profile languages filter these
defaults. CLI previews show the selected seeds without making API requests.

Channel identities were reviewed from official API title/description results
on 30/10/2026. Channel-specific searches use every configured destination name
with relevance and date ordering and bounded pagination. Exact normalized title
destination anchoring excludes Madrid/general Spain results. Descriptions alone
do not prove main destination relevance; manual source input covers such cases.
Public videos of 30 seconds to two hours are eligible; content review determines
whether a short supplies useful research. Source runtime and metadata errors are
explicit coverage gaps. Statistics are dated snapshots of available views,
likes/comments, not venue ratings or proof of trustworthiness. Subscriber counts
and views-per-day ranking are not implemented.

The creator search supplements topic discovery without allowing the topic cap
to silently remove creator seeds. Greek multipart episodes are retained together
up to a 20-video creator cap. English selection is bounded per creator; part/episode
titles rank first, available views break ties. The live batch used four English
videos per creator; CLI default is six. Deferred IDs and pagination limits remain
visible. Search indexing and selected caps cannot establish exhaustive coverage.
This is an initial creator mix, not the final 500-place coverage decision.

```bash
.venv/bin/python -m trippy.sources.creators \
  --profile configs/source_research/barcelona.json \
  --output .local/stage3/sources/new-creator-batch.json --per-creator 4
```

## Final creator batch receipt audit

All **24 selected videos**, across eight creators, have usable timestamped evidence: 20 newly acquired sources plus four reused transcripts. The final audit verifies matching audio/model/VTT hashes and exact segment reconstruction from the raw VTT. Three invalid cues across three videos were excluded without altering their timestamps: Tripment (one zero-duration cue), Happy Traveller Part 2 (one zero-duration cue), and Wolters World’s 5 Things You Will Love & Hate (one cue beyond the audio boundary). Original raw files and exclusion records remain intact. **43 extraction chunks** were prepared, with zero paid calls or catalog writes at preparation time. The subsequent six-chunk live pilot is recorded below. Transcripts remain subject to name/semantic/fact review.

Artifacts: `.local/stage3/sources/barcelona-creators-transcript-final-audit.json`, `.local/stage3/sources/barcelona-creators-extraction-prepared-20261030.json`, and `../research-audio/barcelona-creators-evidence-20261030`. The readable creator selection is `.local/stage3/sources/barcelona-default-creators-selection.md`. The raw worker reports retain initial parsing failures; the final receipt audit supersedes those attempt statuses.

## Local transcripts

The creator batch includes Tasos Dousis Parts 1 and 2 and Happy Traveller's
original Barcelona episode plus Part 2. The original episode and three English
transcripts are reusable. Tripment's available match is a 34-second sponsored
clip, not a full destination guide. Its source note remains separate.

ASR accepts relative audio manifest paths, verifies audio/model hashes, and
preserves VTT, raw Whisper JSON, logs and evidence. `--resume` / `--reuse-dir`
reuse successful evidence only when audio/model/VTT receipts match and quality
screening passes. Failed attempts have separate folders. `--language auto` uses a video-level declared language or explicit override when present; otherwise it detects language. Creator/search hints alone do not force ASR. The completed initial batch used creator hints for known Greek/English episodes; the ambiguous Eat Out clip passed a separate auto-detection check (Greek). CPU is used because Metal
failed on this machine. No ASR API fees. Zero-duration ASR cues can be excluded
with the raw cue retained in the audit; timestamps are never fabricated.
Music/insufficient speech, unsupported detection and excessive repetition block
extraction. Passing these checks does not establish accurate place spelling.

## Extraction contract and execution

`configs/source_research/extraction-prompt-v2.md` is the current versioned prompt; v1 is frozen for historical reproducibility.
`trippy.sources.extraction` generates the strict Pydantic schema and stable
request IDs from prompt/schema/evidence/metadata. It chunks timestamped speech
with overlap and emits prepared requests without any paid model call.

```bash
.venv/bin/python -m trippy.sources.extraction \
  --evidence-dir ../research-audio/barcelona-creators-evidence-20261030 \
  --sources .local/stage3/sources/barcelona-default-creators-20261030.json \
  --output .local/stage3/sources/creator-extraction-prepared.json
```

Mention kinds distinguish venues/chains/districts/cities/dishes/events/routes/
transport products/tickets/advice. All 17 research input dimensions are supported
as category IDs; specific styles, cuisines and subcategories are evidence-backed
claims rather than a restrictive closed list. Each claim separates source factual
assertion, creator opinion and inferred fit. First-hand/second-hand/unknown
experience, stance, sponsorship, multilingual aliases, uncertain identity,
branch, explicit dates and exact citations are preserved. Unsupported information
remains null/absent. Five-star ratings require an explicit platform and numeric
five-point score in the cited speech. Popularity never becomes star ratings.

The validator rejects invalid schemas, uncited entity names, forged segment IDs,
quotes and timestamps, or unsupported ratings. Exact overlap replays and same
source/same branch/same cited occurrence consolidate without dropping claims.
Similar names across sources form a review queue, not automatic identity merges.
Publisher groups avoid counting repeat videos as independent corroboration;
copied videos across channels still need review. Full regional Overture inventory
is searched read-only for name/alias and Greek phonetic lookup proposals, retaining address/coordinates/IDs.
No 500-shortlist restriction. Name matches alone never establish branch identity. Shared candidate IDs link multilingual drafts for review without merging them.
New/unmatched recommendations remain private drafts. Address/official ID/spatial
resolution and current field fact-checking remain review work.

The executable provider is Azure's configured `AZURE_DEPLOYMENT_LUNA` only.
The local paid gate was enabled for the authorized $1 pilot. Execution requires:

- `TRIPPY_ALLOW_PAID_RESEARCH=true` and a finite positive budget amount/currency.
- `TRIPPY_LUNA_INPUT_PER_MILLION` / `TRIPPY_LUNA_OUTPUT_PER_MILLION`, supplied
  as conservative reservation ceilings in that same currency, with a documented pricing basis.
- Configured Azure endpoint/key/API version/Luna deployment.

Use `--execute-luna --catalog .local/catalog.sqlite` with a new output path after
those settings are deliberately configured. There is no Sol fallback. SDK retries
are disabled; the extraction runner permits two validated attempts per chunk,
checks refusals/truncation, caches validated items with persistent quarantine/repair diagnostics, and preserves partial
failures. Durable decimal cost reservations include conservative input/schema
allowances and the output token cap, and remain charged against the local cap on
failures. The ledger bounds this extractor, not all spending in the Azure account.
Never reset/change ledgers to bypass the authorized cap.

Reviewed JSON outputs can also be imported using `--responses-dir` (files named by
chunk ID). They undergo the same validator. No public catalog/Supabase writes or
fact-checking happen automatically. Native UI, adaptive category-gap search and
semantic extraction evals against human annotations are subsequent work. Live
Azure strict JSON-schema compatibility was exercised in the pilot. Structured output guarantees shape, not factual
correctness: [official documentation](https://developers.openai.com/api/docs/guides/structured-outputs).

## Prepared six-call pilot

The approved pilot uses all three chunks of Tasos Dousis Part 1 and all three of
Spain Revealed's EPIC Barcelona Food Tour. It is included in the 43 total calls.
`trippy.sources.pilot` accepts its prepared manifest, checks fingerprints against
the current prompt/schema, and produces a private summary and review queues.
Configuration errors stop the batch after the first rejected request.

Offline preview (already produced):

```bash
.venv/bin/python -m trippy.sources.pilot \
  --prepared .local/stage3/sources/barcelona-luna-six-call-pilot-20261030.json \
  --output .local/stage3/sources/new-pilot-preview.json
```

The live pilot used a $1 USD cap, $0.30/M input and $1.00/M output conservative reservation ceilings, a 16,000 output token cap and low reasoning effort. Six first attempts reserve $0.1783131; retries are separately reserved. Fourteen requests, including two initial diagnostic attempts, reserved **$0.4524889**. This is not actual billing: one initial usage receipt is missing. Pricing evidence is `.local/stage3/sources/luna-pilot-pricing-basis.json`; the official Azure retail page was inspected, including its embedded price attributes and caching prices.

The runner uses `chat.completions.create` with strict JSON schema and retains full responses before parsing/validation. The original SDK beta parser obscured rejected outputs; initial diagnostic failures remain recorded. Cache entries now retain individually validated evidence together with quarantine and deterministic repair receipts; replay preserves partial-review status. Durable group request ceilings prevent unbounded reruns.

## Offline evidence review and quality gate

`trippy.sources.review` validates individual mentions/claims from complete raw responses. It retains a valid mention when another mention or claim fails. IDs/timestamps can be reconstructed only from an unchanged exact quote in the cited cue or one unique existing cue in the same chunk. Ambiguous or invented quotes remain rejected; unsupported entity names and five-star ratings remain quarantined. Retrying a video does not add independent publishers.

```bash
.venv/bin/python -m trippy.sources.review \
  --prepared .local/stage3/sources/barcelona-luna-six-call-pilot-20261030.json \
  --ledger .local/stage3/extraction-budget.sqlite \
  --group barcelona-luna-pilot-20261030 \
  --catalog .local/catalog.sqlite \
  --output .local/stage3/sources/new-evidence-review.json
```

Actual review: **6/6 chunks with complete responses, 64 draft mentions, 55 possible identity groups, 221 citation-valid claim records, 26 quarantined items and 20 citation repairs**. These are draft mentions and claim records, not 64 unique places or 221 unique confirmed facts. Exact citation validation does not establish semantic entailment, correct category, canonical identity or current accuracy.

Targeted spot review found founding dates labeled as opening hours, unresolved generic venue descriptions, ambiguous neighboring-cue attribution and repeated paraphrases across retries. Findings are retained in `barcelona-luna-pilot-semantic-review.json`. Prompt `configs/source_research/extraction-prompt-v2.md` is now the preparation default and was evaluated on the same six chunks. V1 remains frozen and reproducible. New evaluation: 23/23 critical reference targets covered, 71 raw draft mentions, four quarantined mentions. Nine explicit editorial decisions yield 70 private mentions / 220 claim records. See [EXTRACTION_QUALITY_GATE.md](EXTRACTION_QUALITY_GATE.md); complete semantic/cue coverage and identity/current facts still block scaling and publication.

The remaining 37 chunks are deferred until semantic/identity quality is satisfactory. No web research, automatic fact-checking, enrichment publication or Supabase writes occurred. The historical v2 results above were followed by the final additive audit below.

## Final additive audit and check

See [TRANSCRIPT_COVERAGE_AUDIT.md](TRANSCRIPT_COVERAGE_AUDIT.md) for the current
contract and reproducible private artifacts. `trippy.sources.coverage` supports
offline preparation, fingerprint-checked audit manifests, cached replay and
bounded Luna execution. V3 uses 50-cue disjoint cores, neighboring context,
local entity targets, existing-evidence indices and required per-cue JSON keys.

The full 18-window audit of the same two pilots completed. Raw: 73 draft mentions /
457 claims, 29/32 expanded targets. Targeted source review: **73 / 460, 32/32**,
with retained original claims/quotes and 15 explicit editorial decisions. The
sample reference remains non-exhaustive. Source-review findings are content-bound
quality blockers until repaired, including Greek idiom mistranslation and
incorrect attribution. Every original cue remains retrievable as source evidence.

All 859 cue keys are present. Failed reference links for 123 cues become exact
uncertain evidence via `retain_unresolved_cues`, with separate repair receipts.
The complete inventory includes 195 uncertain cues; it does not certify complete
semantic extraction. Canonical identities/current facts and full semantic review
still block the other 37 chunks and publication. Zero /5 scores were invented.

The user authorized up to $2 for this large-video pilot. Shared conservative
reservation ended at **$1.8657948**, without ledger reset. No automatic retries,
Sol fallback, Supabase writes or public enrichment were performed. The final
source-reviewed artifact is `barcelona-coverage-v3-final-source-fixed.json`;
the cue inventory is `barcelona-coverage-v3-final-review-inventory.json`.
