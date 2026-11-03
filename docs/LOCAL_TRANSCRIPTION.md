# Local audio acquisition and transcription

29/10/2026. User chose local transcription and explicitly requested downloading audio from all 20 discovered videos. No paid API, browser cookies, login, DRM access or geo bypass is used. Acquisition does not establish a reuse license: source rights remain unverified, and no material is automatically published to the shared catalog.

## Creator expansion — 30/10/2026

The new default-creator batch adds 20 successfully downloaded audio files (327.6 source minutes) and reuses four valid original transcripts. Tasos Dousis Parts 1/2 and Happy Traveller Part 2 are included. CPU ASR is complete. The final receipt audit accepts 24/24 videos and 43 extraction chunks were prepared from the curated evidence directory. Original worker attempts/logs remain in `../research-audio/barcelona-creators-transcripts-20261030-cpu`; the final audit supersedes raw attempt failure statuses. Tripment's match is a sponsored 34-second clip; its raw zero-duration cue was excluded with an explicit audit, without fabricating timestamps. The old pilot below remains historical.

`--resume` and repeatable `--reuse-dir` now support successful evidence reuse by audio/model/VTT hashes and quality checks. Failed attempts use separate subdirectories. `--language auto` now uses video-level language declarations/explicit overrides, otherwise auto-detection; creator hints alone do not force the language. The limit can explicitly increase to 100 files. Music/insufficient speech/unsupported language/excessive repetition are excluded from AI preparation. Structured extraction and its Luna-only paid gate are documented in TRANSCRIPT_EXTRACTION.md.

## Actually completed

- Official whisper.cpp release `v1.9.5`, source archive commit `d2a764c`, rebuilt at `.local/asr/build-v1.9.5-relocated` after the workspace move. CPU/Accelerate and Metal backends compile; Metal initialization fails on the downloaded clips, so the batch uses CPU. No system-wide installation.
- Multilingual `ggml-small.bin`, **487,601,967 bytes**, SHA256 verified against official linked Hugging Face model-repository LFS metadata: `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`.
- CPU transcription smoke tests passed on the upstream JFK sample and a downloaded Greek Barcelona clip, producing timestamped VTT/JSON. The Greek sample contains recognition errors; transcripts remain unverified evidence, not place facts.
- `yt-dlp==2026.10.26` installed in the project-local Python environment, dependency in `requirements-sources.txt`.
- Downloaded **20/20 audio files**, **307,821,169 bytes**, approximately **317.2 minutes**, no download failures. Output: `../research-audio/barcelona-pilot-20261029`, with individual content hashes and `progress.json`. Audio paths in the manifest are relative to the manifest so the batch remains usable after moving the workspace.
- External location was approved after the internal disk showed only ~500 MB free and CrucialX9 showed ~469 GB free. Download limits are 250 MB per file, a storage reserve, finite-stream restrictions and no overwrite. Tests cover source identity, storage bounds, preserved batches and partial-failure reporting.

The CPU-only 20-video Barcelona transcription batch completed with status `transcription_incomplete`: 19 evidence JSON files passed structural checks; one long transcript failed because it contained a zero-duration subtitle cue. Several formally completed files still contain music-only or unusable language output. Per-source flags are in `../research-audio/barcelona-transcripts-20261030-cpu/review-audit.json`. The prior Metal attempt failed for all 20 clips and its WAV conversions/logs remain at `../research-audio/barcelona-transcripts-20261029`. No Luna call or shared catalog write occurred.

## Implemented local batch tooling

`trippy.sources.download_audio`: explicit source-ID validated batch, yt-dlp audio-only retrieval, private output directory, checkpoints, hashes, bounded storage/time and rights-unverified status. User-requested downloads are recorded separately from permission/retention review; no blanket legal clearance is inferred.

`trippy.sources.asr`: downloaded-file hash verification, local ffprobe duration check, ffmpeg mono/16-kHz PCM conversion, local whisper.cpp execution, original-language/auto-detect options, VTT/JSON and evidence with exact source identity/timestamps. Defaults to up to 20 files; each source gets a status and failures are retained. Audio longer than two hours is rejected by this pilot. Models are verified before execution. No network/API calls are part of ASR. Generated PCM/log files remain in the batch for review; storage/retention cleanup remains a later explicit operation.

Command used from the project directory (the output directory is exclusive and already exists):

```bash
.venv/bin/python -m trippy.sources.asr \
  --batch ../research-audio/barcelona-pilot-20261029/progress.json \
  --output-dir ../research-audio/barcelona-transcripts-20261030-cpu \
  --language auto --limit 20 --cpu-only
```

Use `--cpu-only` for this workspace until the Metal initialization failure is resolved. Do not rerun this command against the existing output directory. Output directories are exclusive; do not rerun over an existing batch. Rights, transcript accuracy and venue identity/facts remain separate review states. ASR mistakes around Spanish/Catalan names and code switching require candidate review. Timestamped text is evidence, not an independently verified place record.

## Relocating the workspace

The active project root is `/Volumes/CrucialX9/Code_Backup/Trippy/project`; the audio and transcript batches live in the sibling `/Volumes/CrucialX9/Code_Backup/Trippy/research-audio`. The Python launchers were rebased to this location, and whisper.cpp was rebuilt under `.local/asr/build-v1.9.5-relocated`. The previous Metal build is preserved in `.local/asr/build-v1.9.5`.

Validation so far: five download tests and three local-ASR boundary tests passed. The real local Whisper sample test passed. No native UI or remote schema changes were made.
