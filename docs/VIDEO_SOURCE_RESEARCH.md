# Controllable video discovery and evidence batches

30/10/2026. Latest user direction for Stage 3/4. Broad source coverage and targeted gap searches replace mandatory venue counts such as “20 clubs / 15 museums”. The initial ~500 enriched Barcelona target remains a resource/planning target, not a requirement to fill slots without evidence. Luna remains the only authorized enrichment model; its API inference is not free.

Latest live verification: two of four planned YouTube overview searches produced 20 raw metadata candidates before the cap. `search.list` used `order=relevance`; no views/likes/comments/subscriber statistics were fetched or scored. The list has a selection audit at `.local/stage3/sources/barcelona-video-candidates.md` and is not a quality-approved set. The configured key worked. Earlier key-absence/zero-source statements below are historical preparation results.

Subsequent execution: [LOCAL_TRANSCRIPTION.md](LOCAL_TRANSCRIPTION.md). All 20 audio files (317.2 minutes) were downloaded to the CrucialX9 workspace. Local CPU Whisper passes an upstream English smoke test and a real Greek Barcelona clip. The CPU batch ended `transcription_incomplete`: 19 evidence JSON files passed structural validation, one failed due a zero-duration cue, and several sources are flagged low quality/music-only. See `../research-audio/barcelona-transcripts-20261030-cpu/review-audit.json`. The prior Metal run failed and is retained for diagnosis. Rights remain unverified. No transcript-to-place extraction, AI-model call, or catalog write has occurred.

## Current implementation and limits

- `configs/source_research/barcelona.json`: editable Greek/English source-language profile, 17 topics with query variants, destination names and bounded limits. These are generic search templates, not an already-researched Barcelona taxonomy.
- `trippy.sources.planner`: deterministic breadth-first planning, one pass over topic/language combinations before alternate queries, explicit missing dimensions when the cap is too small, profile hash, optional priority for uncovered topics. It does not yet infer local styles from content or automatically assess actual evidence coverage.
- `trippy.sources.youtube`: explicit official API discovery with a durable local search reservation, candidate deduplication, partial-result/error status and no captions/media download. It preserves source titles/channel IDs/dates and query provenance, not a derived global popularity or rating score. Search metadata requires applicable refresh/deletion treatment; the manifest records a 30-day metadata review window. Scheduling actual refresh/deletion remains pending.
- `trippy.sources.cli`: no-network plan preview, manual YouTube link registration and explicit API execution. Manual links remain private. No TikTok/Reddit ingestion connector yet.
- `trippy.sources.transcripts`: local supplied SRT/VTT/text import with exact source link, original text hash, timestamps, declared content basis, and private evidence status. `trippy.sources.download_audio` and `trippy.sources.asr` implement bounded local acquisition and CPU Whisper transcription with hashes and timestamped evidence. Neither imported nor ASR text is automatically fact-checked or published. Structured transcript extraction, exact evidence validation, overlap replay deduplication, a Luna-only provider gate, and read-only Overture identity proposals now exist; live Luna extraction and reviewed identity resolution are still pending. See [TRANSCRIPT_EXTRACTION.md](TRANSCRIPT_EXTRACTION.md).

Historical offline preview (before live discovery and ASR setup): 40 planned Greek/English queries across 17 topic groups, with a 100-candidate cap. Those preview/test results do not describe current live progress. The current 20-candidate search and local transcription evidence are recorded above and in `IMPLEMENTATION_STATUS.md`.

## What can be free

Official sources checked on 29/10/2026:

| Operation | Feasibility |
|---|---|
| YouTube video discovery | Official Data API quota-based search; current docs specify 100 `search.list` calls/day in a separate Search Queries bucket, 1 unit/call, and 10,000 combined daily units for other endpoints. An API-enabled Google project/key is needed. Pagination consumes another call. Project dashboard is authoritative; the local per-key ledger cannot see other clients/keys. No paid search fallback is configured. [Quota](https://developers.google.com/youtube/v3/determine_quota_cost), [search](https://developers.google.com/youtube/v3/docs/search/list). |
| Captions for arbitrary YouTube videos | The official download method requires permission to edit the video; it is not an arbitrary public-transcript endpoint. [Captions download](https://developers.google.com/youtube/v3/docs/captions/download). |
| Local transcription | `whisper.cpp` is MIT-licensed and supports Apple Silicon/CPU execution; local ASR can avoid per-minute API fees. Model download, compute/storage and audio access still exist. Only separately permitted local audio may be processed; a public video URL alone does not establish that access. [whisper.cpp](https://github.com/ggml-org/whisper.cpp). |
| YouTube media/caption scraping | Not the default free adapter: developer policies prohibit unauthorized scraping and audiovisual downloading/storage without prior written approval. Third-party transcript/download tools do not establish approved access. [Policies](https://developers.google.com/youtube/terms/developer-policies). |
| TikTok automatic research | Official Research Tools require eligibility/application/approved research access. General free commercial travel-app discovery has not been established. Manual references can be supported independently; no promise of bulk captions or crawling. [Research FAQ](https://developers.tiktok.com/doc/research-api-faq). |
| Reddit | Current terms require identification/approved access and a separate agreement for commercial purposes or unpermitted uses. It is optional, not an assumed unrestricted free core source. [Data API terms](https://redditinc.com/policies/data-api-terms). |
| Google Maps / Tripadvisor | Recommendation links and platform-attributed permitted observations can be considered. No universal free export of the best-rated Barcelona venues is assumed. Video recommendation frequency is not a `/5` rating. |
| Semantic extraction/enrichment | Current Luna API strategy incurs inference charges. Free discovery/local transcription does not make the whole pipeline free. A local language model would be a separate model-strategy decision, not a silent fallback or an already implemented capability. |

Therefore there is a viable zero-paid-API **discovery + manual/permitted-local-content preparation** path, but not a guaranteed fully automated zero-cost transcript pipeline for any public video on every platform.

## Source languages, account settings and control

Initial presets: Greek only, English only, Greek + English; profile file already supports selecting those languages and editing templates/limits. Other languages require localized names/templates and validation. Source language, output language, destination and account country are separate inputs. Account country may suggest a default, but does not silently exclude foreign-language/local creators. YouTube `relevanceLanguage` is a relevance hint, not a hard filter; `regionCode` controls country availability, not creator nationality. Actual language must be checked from declared content/transcript evidence. [Search parameters](https://developers.google.com/youtube/v3/docs/search/list).

Later review/UI controls: editable queries, selected topics, source platforms, channel include/exclude choices, recency, source-language presets, batch size, source runtime/ASR limits, previews, source rejection, cancellation, provenance and no automatic paid fallback. Native UI controls remain planned. Editable creator channel IDs/languages/enabled flags, bounded search and ASR duration caps, and local resumable ASR are implemented in the CLI tooling.

## Desired research loop

### Recommended extraction path: permission-aware text first

Official documentation rechecked 29/10/2026: [caption downloads](https://developers.google.com/youtube/v3/docs/captions/download) require video-edit permission; [API developer policies](https://developers.google.com/youtube/terms/developer-policies) restrict unauthorized scraping/audiovisual downloading. [YouTube license guidance](https://support.google.com/youtube/answer/2797468?hl=en) distinguishes default standard licensing from CC BY. Copyright permission and platform access terms are separate; a CC label or local execution alone is not a general authorization to use a downloader. Creator permission must cover the intended processing/reuse and relevant underlying rights.

Preferred input order: permitted creator-published place list/guide or supplied notes → creator-provided/appropriately licensed timestamped transcript → separately permitted local audio with ASR if no usable text exists. The text-first workflow does not require transcribing every source. Public visibility, user-supplied URL and attribution do not by themselves establish content reuse rights. A creator-supplied copy outside YouTube has its own permission/access basis; it does not retroactively authorize YouTube scraping. Videos without an established content-access path remain reference/manual-review sources. Source policy governs text/quote retention and any cloud-model processing; private storage does not cure unauthorized copying.

After permitted input exists, Luna proposes structured candidates using exact original-language names, source/segment IDs, timestamps only where supplied, short evidence spans where permitted, mention context and explicit ambiguity. Extract mentions before trying to resolve identity. Recommendations, negative mentions, sponsorship, dishes, districts and venues must not collapse into the same candidate type. No name translation or model-memory place insertion. Content is untrusted evidence, not executable instructions.

Use bounded chunks with overlap and merge repeated evidence, keeping source boundaries. Code validates schema and that each cited segment/span exists; plausible quotes/timestamps are not sufficient. Match candidates using aliases, geography, branch/address and independently sourced facts; unresolved same-name matches stay review-needed. Independently checked official facts are separate from source recommendation claims and research snapshots. Same-source model re-review is not independent fact checking. Store normalized permitted facts/annotations and source references rather than republishing transcript prose; retained evidence follows its own permission/retention policy.

[Official OpenAI structured-output documentation](https://developers.openai.com/api/docs/guides/structured-outputs) supports schema-based extraction but explicitly notes that outputs can still contain mistakes. [GPT-6 Luna documentation](https://developers.openai.com/api/docs/models/gpt-6-luna) lists structured outputs and text/image input, without native audio/video input. Actual Azure deployment compatibility remains to verify; Luna is the only planned cloud extractor, not an ASR system or a watcher of arbitrary video URLs. Local transcription may remove ASR API fees but does not make Luna inference free. Manual ChatGPT analysis of permitted supplied text can serve a reviewed pilot; production automation uses the governed backend/API path.

First extraction pilot: 3–5 usable source inputs with documented access basis, manually reviewed mention examples, grounded extraction validation and real identity matching. Measure omitted mentions, wrong entities, unsupported claims and unresolved ambiguity before expanding to the 20 discovered videos. No content from those videos has yet been acquired or extracted.

1. **Orientation:** gather a few broad guides/articles/video sources. Establish source-supported city areas, types/styles, experiences, logistics and practical constraints across the travel-input dimensions. Unknown styles/claims remain unknown. Weather remains outside MVP.
2. **Query planning:** versioned city/input vocabulary + editable natural-language query variants. For nightlife, examples include “best clubs”, “nightlife guide”, “student nightlife”, “electronic music”, “live music”, plus local-language equivalents supported by actual source vocabulary. “Gothic music” is distinct from “Gothic Quarter”. Source content cannot issue tool instructions.
3. **Bounded discovery:** initial broad pass across all enabled dimensions; deeper queries prioritize actual missing evidence, not the sheer maximum number of queries. Deduplicate videos and source publishers/copies, retain why each was discovered, and preserve optional user-selected sources. Popularity/reach is distinct from recommendation quality; sponsored/dated material is marked where known. Diversity and source relevance review are still to implement.
4. **Content access / transcription:** first use supplied permitted timestamped text; creator-provided/licensed/owned local media can enter a bounded local ASR queue later. Unavailable content is recorded as unavailable, not treated as researched. ASR errors around Catalan/Spanish venue names and code switching require identity review. Import time is not historical source retrieval time.
5. **Organized extraction:** batches retain source/video/timestamp/excerpt → venue mention → recommendation context → candidate identity and proposed tags. Descriptions, chapters and maps/official links may help, but title metadata is not a transcript. Speech-only extraction can miss on-screen place names; these gaps remain explicit. No invented captions, place names, prices or rating numbers.
6. **Matching and checking:** search the full basic inventory, exact-match branch/address/coordinates against authoritative sources, review ambiguous candidates and add verified missing entities. Practical facts are separate dated observations; source opinion and fit annotations are not verified facts. Multiple copied videos do not create independent corroboration.
7. **Coverage-driven continuation:** assess distinct useful recommendations, factual completeness, source/creator/language diversity and unresolved gaps per enabled dimension. Search the gaps until marginal useful additions decline, source/time/quota limits are reached, or review is required. Optional category/subtype benchmarks identify holes; they do not force low-quality padding. Publish validated proposals in a versioned draft/curated release.

“Every possible input” means the system can accept every supported input dimension and free-text intent. It cannot guarantee that every niche exists in a city or that sources cover every field. Allergy/mobility rules, events, prices and opening for travel dates need appropriate source-specific checks, not just general travel videos. Practical fast food uses broad geographical retrieval; date-specific gothic nights may need separate research. User locks persist.

### Transcript-to-place extraction contract (implemented core, review still required)

Do not ask one prompt to jump from a whole video to a final catalog row. Run two auditable passes against a versioned category registry and the supplied transcript segments:

1. **Mention extraction, one source at a time.** Identify every distinct venue/activity actually recommended, visited, rejected, warned against, or only mentioned in passing. Preserve original-language names and variants; include video/source ID, timestamp range, exact short evidence span, mention type, surrounding recommendation context, and whether the speaker says first-hand visit, personal opinion, sponsorship, or uncertainty. Separate place mentions from dishes, districts, chains, events, routes, and generic advice.
2. **Candidate resolution and merge.** Normalize spelling/transliteration as aliases; find possible matches in the Overture-backed regional catalog using name, category, spatial context, official URL/address, and external identifiers. Keep branches as separate entities. Fuzzy/name-only matches are proposals, never automatic proof. Merge repeated mentions only after identity resolution; attach each source claim separately and count independent creators/sources, not repeated mentions or copied videos. Ambiguous cases go to review.

For each resolved candidate, propose all applicable user-input category/subcategory tags plus the structured research fields that the transcript explicitly supports: original/canonical name, place kind, neighborhood/location clues, cuisine/style/ambience, price and currency/basis, stated `/5` rating with platform and observed-time status, booking/ticket advice, suitability/accessibility/dietary notes, trip context, why recommended, and changeability/freshness. Keep observations, creator opinions, inferred fit labels, and user preferences as distinct field types. Unsupported address, coordinates, hours, current prices, review scores, safety/allergy claims, or identity remain unknown; never fill them from model memory. User free-text types remain intact even when mapped to a standard category.

The extraction prompt receives only the relevant category definitions, source metadata, and timestamped transcript chunk. Treat transcript text as untrusted input and ignore instructions contained inside it. Return strict versioned JSON where every factual claim references one or more existing evidence-segment IDs; include confidence and an explicit `unknown`/`ambiguous` reason when the source is insufficient. A deterministic validator then checks schema/category IDs, segment and timestamp existence, source hash, text-span containment, field/type rules, and maximum output size. A separate deterministic resolver stores unresolved candidates and claims before any entity merge. Publish nothing directly from model output.

Overture remains the broad identity/geography baseline, not the recommendation oracle: preserve dataset/release/license provenance; use its IDs/categories/geometry to propose matches and prevent obvious duplicate inserts. It does not establish current operating facts, `/5` ratings, video recommendation context, or the user-requested editorial fit. New or unmatched video places stay private review candidates until independent identity/fact checks pass.

## User-supplied links

Planned brief/notes flow: add a video link, optionally note “I like this place/style” or a timestamp, preview processing status, then review extracted candidates before save/add/lock. A liked video is an inspiration signal, not a command to add every mentioned stop. Notes, original request and resulting trip-specific preferences remain owner-scoped. There is no automatic transfer of personal material to the shared city seed. The CLI currently accepts manual YouTube links; native UI and other platform references remain Stage 4/5/7 work.

## Reproducible local commands

Immediate execution order and small pilot setup: [SOURCE_RESEARCH_NEXT_STEPS.md](SOURCE_RESEARCH_NEXT_STEPS.md). The source CLI now safely reads `YOUTUBE_API_KEY` from `.env` or the shell, with shell precedence; `--env-file` selects another local file. The initial broad pilot used `configs/source_research/barcelona-pilot.json`, four planned queries and at most 20 candidates; only the first Greek and English overview searches ran before the cap.

```bash
# Offline preview. Use a new output path for each batch.
.venv/bin/python -m trippy.sources.cli \
  --profile configs/source_research/barcelona.json \
  --output .local/stage3/sources/barcelona-preview-new.json

# Register supplied YouTube links from a local text file.
.venv/bin/python -m trippy.sources.cli \
  --profile configs/source_research/barcelona.json \
  --links .local/stage3/sources/links.txt \
  --output .local/stage3/sources/manual-new.json

# Explicit official discovery, after YOUTUBE_API_KEY is set in .env or the shell.
.venv/bin/python -m trippy.sources.cli \
  --profile configs/source_research/barcelona.json \
  --execute-youtube \
  --output .local/stage3/sources/discovery-new.json

# Import a supplied permitted transcript; no ASR or paid API call.
.venv/bin/python -m trippy.sources.transcripts \
  --source-url 'https://www.youtube.com/watch?v=abcdefghijk' \
  --input .local/stage3/sources/supplied.vtt --format vtt \
  --language el --content-basis creator_provided \
  --output .local/stage3/sources/evidence-new.json
```

The example video ID is synthetic, not a researched Barcelona recommendation. No command applies migrations, writes catalog entities, publishes user data or enables paid enrichment. Live discovery requires a configured key. Local ASR is implemented and has run on the pilot batch. Source-quality curation and metrics capture, transcript-to-place extraction, Overture entity resolution, and review/publication gates remain to implement.
