# Next execution steps: Barcelona source pilot

30/10/2026. Continue Stage 3. The existing 41,461-record basic inventory is retained; the old technical shortlist is not the generation input. The free source-preparation pilot precedes wider source selection and paid Luna enrichment.

Current creator execution: **24/24 selected video transcripts passed the final audio/model/VTT/segment receipt audit**, covering all eight creator defaults. This includes both Tasos Dousis parts and Happy Traveller Part 2; Tripment remains a sponsored short. **43 Luna extraction chunks are prepared**, with no paid call or catalog write. Raw invalid cues remain audited; source names/facts still need review. See `.local/stage3/sources/barcelona-creators-transcript-final-audit.json` and TRANSCRIPT_EXTRACTION.md.

Historical technical pilot: configured YouTube and Supabase settings passed safe presence/shape checks; read-only DB/Auth health passed, while public app schema/migrations/PostGIS remain uninstalled. Two relevance-ordered YouTube overview queries produced 20 raw candidates; no view/like/comment/subscriber stats were collected. The audit at `.local/stage3/sources/barcelona-video-candidates.md` finds this unsuitable as a final ranked source set. All 20 audio files are downloaded; local CPU ASR ended with 19 evidence JSON outputs and one failure. The quality audit flags unusable language detection, music-only clips, and a Madrid result; do not feed the raw set into place extraction. No AI extraction, remote migration or catalog data transfer occurred.

Latest audio execution: **20/20 audio files downloaded**, 307,821,169 bytes / 317.2 minutes. The current workspace and audio are on CrucialX9; the Python launchers and Whisper build were repaired for this path. The 20-video CPU-only transcription batch ended with 19 evidence JSON files and one timestamp-parse failure; see [actual results](LOCAL_TRANSCRIPTION.md) and the per-video review audit at `../research-audio/barcelona-transcripts-20261030-cpu/review-audit.json`. Metal fails during Whisper backend initialization on these clips. Source rights and transcript accuracy remain unverified.

| Step | Concrete deliverable | Acceptance / dependency |
|---|---|---|
| 3A — Broad source discovery | Eight editable channel-ID creator seeds and a new 24-video batch now supplement the historical pilot. Official metadata includes statistics, exact-title destination checks, multipart search and bounded per-creator selection. | Rank only after reviewing relevance, freshness, content utility, views-per-day/available engagement, and language; metrics now exist for the creator batch; they do not establish recommendation quality. |
| 3B — Small content pilot | 20 audio files downloaded; 19 structurally emitted evidence JSON files, one failed transcript. The review audit flags music-only/low-quality outputs. New creator batch: 20 new audio downloads complete, four valid prior transcripts reusable; CPU ASR complete: final audit 24/24 usable transcripts, 43 prepared extraction chunks. | ASR works locally; source access rights remain unverified. Preserve failures and mark language/recognition uncertainty. Inaccessible or low-quality videos stay explicit gaps. |
| 3C — Place/evidence pilot | Implemented evidence-bound mention schemas/prompt, chunking, validator, overlap dedup, publisher grouping and read-only full-inventory Overture proposals. Run the gated Luna-only provider after configuring the paid cap/rates, then review facts and identities. | Versioned category/schema prompt, deterministic quote/timestamp validator, independent-source aggregation, and per-field provenance. Luna extraction requires a provider/cost cap; no paid calls are enabled. |
| 3D — Coverage expansion | City/source-supported vocabulary, targeted query variants across enabled inputs, deduplicated diverse sources, measured gaps and revised ~500 curated manifest. | Bounded quota/runtime/cost; expand where useful new evidence appears. Optional per-category benchmarks detect holes without forcing arbitrary counts. Source quality and field-level fact checking precede publication. |
| Connected data verification | Complete migration, Auth/RLS/PostGIS and storage checks after schema rollout. | Credentials are configured and read-only health checks pass; public schema is still empty and has no app migration/PostGIS. No remote writes have occurred. |
| 4 — Preferences/compiler | Standard choices, free-text type, contextual prompts, source-language presets and user-link/notes data contract. | Preserved original intent, no category-wide exclusion and owner-scoped private inspiration. |
| 5 — MapKit | Central pin search/private save/add-to-trip and source-link intake integration. | Exact selected match, existing entity reuse, no automatic paid call from Save. |
| 6 — Planner | Bounded retrieval, trip-date checks, routes/budget constraints and sourced /5 snapshots. | User choices/locks preserved; unknown facts visible. |
| 7 — Native UI | Reimagine the current Library → Brief → Workspace layout using Wholiver SwiftUI Design Skill and official Liquid Glass/iOS 27 checks. | Minimal, consistent, intuitive customization; user video links/notes and processing/source previews. |
| 8 — Admin/rollout | Coverage/source/cost review, version publish/rollback, connected integration and deployment preparation. | Concrete reviewed artifacts and applicable deployment authorization. |

## Historical one-time API-key setup (completed for the pilot)

The configured key has already been used for the initial free metadata-discovery pilot. These steps are kept only for future key rotation or another machine:

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select or create a project for Trippy.
2. Open **APIs & Services → Library**, find **YouTube Data API v3**, open it and click **Enable**.
3. Open **APIs & Services → Credentials → Create credentials → API key**.
4. Edit the key. Under **API restrictions**, choose **Restrict key** and select **YouTube Data API v3**, then save. This connector makes backend requests, so browser/HTTP-referrer restrictions are unsuitable. For the local pilot, use no application restriction unless a compatible stable backend-IP restriction is configured.
5. Add `YOUTUBE_API_KEY` to the existing local `.env`, preserving other fields. Do not send the key in chat or commit it.
6. Tell the agent the key is configured. A redacted presence audit precedes the four-query live discovery run; no paid fallback is enabled.

This API key enables search metadata access, not arbitrary public caption downloads. No OAuth client/service account is needed for this search connector. Official setup reference: [YouTube getting started](https://developers.google.com/youtube/v3/getting-started).

Use a Google Cloud project with YouTube Data API v3 enabled and an API key restricted to that API. Create/manage the key through the Google Cloud Credentials interface; do not paste it into chat or commit it. Add only this field to the existing local `.env`, preserving Azure/Supabase settings:

```dotenv
YOUTUBE_API_KEY=your_actual_key
```

The CLI safely reads `.env`; shell environment values override file values, including explicit blanks. It does not execute/source dotenv contents and does not log credentials. `--env-file` selects an alternative local file. No automatic paid API fallback is enabled.

Once configured, the first live command is:

```bash
.venv/bin/python -m trippy.sources.cli \
  --profile configs/source_research/barcelona-pilot.json \
  --execute-youtube \
  --output .local/stage3/sources/barcelona-pilot-discovery.json
```

Output files are exclusive: use a new batch path on repeat. This command only discovers video metadata; it does not download media, transcribe, call Luna, mutate the catalog or deploy. Provider quota and content constraints are documented in [VIDEO_SOURCE_RESEARCH.md](VIDEO_SOURCE_RESEARCH.md).

Historical offline preparation snapshot, superseded by the live pilot above: the preview had four planned queries and no source results; a key audit had not yet found YouTube/DB/Auth credentials. The current project later completed YouTube discovery, read-only DB/Auth checks, audio acquisition, and local ASR setup. Native notes UI and live paid transcript extraction remain pending; extraction tooling is now implemented (TRANSCRIPT_EXTRACTION.md).
