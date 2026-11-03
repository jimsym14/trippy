# TikTok share ingestion

The implementation captures inspiration into a private source library. A Save retains concise place references; a Note keeps complete evidence and the same places. Source material remains separate from canonical/current venue facts.

## Native capture and destinations

New `TrippyShare` iOS Share Extension target, embedded in Trippy. Shared App Group:
`group.com.dimitrisymeonidis.trippy`.

The extension supports URLs/text, up to 35 supplied images and one supplied movie. It copies supplied files while the NSItemProvider temporary URL is valid, then atomically commits one immutable envelope. Cancelling/failing does not commit an incomplete envelope. Save destinations:

- General places or a particular trip's places.
- New general/trip Note, or an existing Note in that collection.

The main app exports trip/note target names to the shared container. It reads new envelopes when active, processes them once per capture ID, and keeps its source/notes/place-reference document in Application Support. Notes reference source evidence rather than replacing or duplicating it. Notes can be edited and moved to a trip. In-app link import is also available.

## What runs locally

Every supplied image is processed with accurate Vision OCR, preserving provider order and raw extracted text. Images remain stored for review/reprocessing. Supplied share text is labelled **shared text**, because it is not guaranteed to be the exact post caption. Slideshow OCR issues and missing text remain visible.

The Inbox distinguishes unknown/link-only input, supplied images and supplied video. It does not infer actual media type from a thumbnail or pretend that a saved URL has been read. A supplied movie is retained as `needs_transcript`; no automatic speech transcription is currently connected.

Place references can currently be reviewed/added from evidence. Automatic Luna-generated places and polished long notes are **not yet wired into the client**. The UI never turns missing retrieval into invented place facts.

## Luna extraction and database contract

`trippy/sources/social_ingest.py` provides bounded requests and response validation for an injected Luna provider:

- Preserve every slide/text/transcript block and its origin.
- Split large inputs while retaining every character and parent evidence ID.
- Short place descriptions, detailed note sections and exact source quotes.
- Require every evidence block to be accounted for, including irrelevant blocks.
- Report missing slide count, incomplete slide OCR, missing post caption and missing video transcript explicitly.
- Archive immutable source/extraction revisions and destination bindings per owner in a private SQLite archive.
- Reject fabricated quotes and extraction against a source revision not owned/imported.

Citation validation is not semantic/canonical approval. No place is automatically merged into the active shared catalog. Growing the private evidence archive is implemented; publication/canonical linking is a separate pipeline stage.

## Required integration before end-to-end release

1. Provision the App Group for the app and extension identifiers under the Apple development team. The entitlements/target wiring are present; device signing is unverified.
2. Select/connect a TikTok retrieval provider for link-only shares. TikTok sharing commonly returns only a URL. oEmbed alone does not guarantee all slideshow images, downloadable video or auto-captions. The installed yt-dlp TikTok extractor has video/caption support, but does not establish robust slideshow support or successful retrieval for a particular post.
3. Supply one representative public video and one slideshow URL to test actual acquisition. Neither was supplied during implementation.
4. Connect captions/transcript acquisition (and ASR fallback where necessary), retrieval retries/cache, and the existing budgeted Luna dispatcher to the extraction contract. Comments are optional and not connected.
5. Connect authenticated sync/source archive and reviewed canonical joins. The current client source library is local; the standalone private archive is not an authenticated deployed service.
6. Run full device Share Sheet/OCR/Notes/Places tests. Full Xcode/Simulator access is currently blocked by the session's approval infrastructure failure, not by a source-code type error.

## Checks completed

- Static iOS SDK type checks for main app and extension; temporary State-wrapper aliases avoid sandbox-denied macro subprocesses. Full build/runtime remains pending.
- Xcode project, extension Info.plist and both entitlement plists parse successfully.
- Six Python tests passed: evidence/slide retention, truthful coverage gaps, omitted evidence/fabricated quote rejection, idempotency and immutable revisions, owner boundaries, exact chunk reconstruction, URL/request bounds.
- Existing trip storage regression checks passed. No paid models, transcription APIs, remote database mutations or shared catalog publication were executed.
