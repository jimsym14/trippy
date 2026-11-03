> The November 2 plan sheet and selected-trip controls have been replaced. See [current plan redesign and failure audit](PLAN_REDESIGN_AND_FAILURE_AUDIT.md); the older sheet/shelf description below is historical.

# Map-first iOS workspace

Implemented in `ios/Trippy/TrippyApp.swift`, following the user's November 2 map-first direction. The initial pass preceded the reference files. All five supplied images have now been inspected and a [reference-informed redesign](UI_REFERENCE_REDESIGN.md) has been implemented; rendered app comparison remains pending Simulator access.

## Working connections in the implementation

- Native Map / Library tab bar, with native Liquid Glass on supported iOS versions and opaque accessible fallback for older systems / Reduce Transparency.
- Home map: personal Saved, planned-trip city pins, city-to-Library filter, light/dark appearance, Explore / Quiet / Satellite / Hybrid cartography.
- Library: Trips / Saved, text search, city filter reset, existing brief creation/editing, generated-trip selection, personal-save removal, saved-place map focus.
- Selected trip: distinctive serif user-editable title, subtle metadata pill, Overview / day selection, planned / recommended / Saved toggles, POI category toggles including coffee, brunch, groceries and public transport.
- The detail sheet has compact / medium / large detents. Existing schedule editing, reordering, alternatives, costs per person/group, checklist and source details remain connected. Map pins can open their day; recommendations can be added to the selected day.
- MapKit search uses a debounced cancellable request and exposes actual candidates for user selection. Saving is local and independent from generated research.
- Route requests use actual MKDirections geometry, cache equivalent segments and cancel stale work. Changes in day order, coordinates or preview transport mode invalidate rendered paths. Missing coordinates break a route rather than connecting past the missing stop. No routes connect different days. Walking/driving previews are labelled; unsupported scheduled transport modes are not fabricated.
- Apple supplies basemap landmark illustrations where supported. We do not bundle copies of Apple's landmark artwork.
- `ui/logo-idle.svg` is copied unchanged into the existing bundled Brand folder and rendered locally in a nonpersistent WKWebView. Research loading and search loading reuse it with restrained rings. Animation pauses in inactive scenes / Reduce Motion. It does not make network requests.

## Data retention

The existing `trippy.native.trips.v1` key remains. `customName` is optional so older trips decode. Personal saves and city-coordinate caches use separate versioned keys. Research JSON remains opaque and is not rewritten by renaming or saving places.

`python3 scripts/verify_map_models.py` passed: old-trip decode, encode/decode equality, research preservation, schedule order/edits, coordinates, checklist, budget, rename fallback and personal-save round-trip. It operates on fixtures and never writes production UserDefaults.

A static iOS 17 SDK type check passed using a temporary copy that disambiguates SwiftUI's exported State property wrapper and omits the existing Preview macro. This checks types, but does not replace the normal Xcode macro expansion, full build or runtime validation.

## Remaining UI validation

The sandbox prevented Xcode's workspace/Simulator access. The escalation did not execute: automatic approval infrastructure returned `404 deployment not found`. Full Xcode build, simulator screenshots, actual search/route requests and device interactions are therefore **unverified**.

Once access is restored, validate:

1. Fresh install, empty Library, create brief, back navigation.
2. Existing stored trips, selecting a generated trip, renaming, relaunch retention.
3. Saved search candidate, correct selected branch/location, map focus, relaunch, remove.
4. City pin opens the correct Trips filter; clearing restores the whole Library.
5. Overview/day and each layer/category toggle; no duplicate physical pins.
6. Reorder/delete/add/replace a stop and verify old route disappears, new route renders and day paths stay separate.
7. Missing coordinates, unsupported transport, offline search/routing and cancelled requests.
8. Sheet expansion, nested add/alternative sheets, costs and checklist edits.
9. Light/dark, each map style, Reduce Motion, Reduce Transparency, larger text and small/large iPhone sizes.
10. Supplied screenshot comparison and SVG animation rendering on-device.

The client still uses its existing research/import path. This redesign does not connect the private integrated source database or implement the missing canonical/provider/full-planner stages. Individual-traveler planning controls require their underlying data/pipeline implementation before being exposed.

## Social sharing addition

The user subsequently requested TikTok sharing. The Library now also includes Notes and Inbox. See [capture, OCR and pending provider integration](TIKTOK_SHARE_INGESTION.md).

## Benchmark rerun

Executed the existing runner with caffeinate: 32 profiles, 5 repeats each, 160 offline consumer runs. Report:
`.local/stage3/planner-release-v1/product-benchmark-v1/3592d7c93379e225/report.md`

- Actual external cost: $0.
- Warm p50: 1.052 ms; p95: 1.336 ms. These measure the partial local consumer, excluding UI, MapKit/network and a full planner.
- Full profile acceptance: 0/32 because connected planner capabilities are still missing.

This is a baseline, not a completed end-to-end product benchmark. After UI validation, the next iteration must connect the planner/provider stages and evaluate the 32 expected outputs; re-running offline reviews cannot substitute for that implementation.
