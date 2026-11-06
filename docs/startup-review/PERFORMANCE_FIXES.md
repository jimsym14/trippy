# Map and startup performance fixes — 4 November 2026

The supplied phone timestamps show storage loading in 0.343 seconds, a first marker rebuild in 3.690 seconds, two following rebuilds in about 0.334 seconds each, map readiness at 23.481 seconds, and SVG readiness at 25.337 seconds. These timestamps measure time after app.init, not time spent building, installing or attaching Xcode before app.init.

The counter row's compressed UIStackView width was smaller than its required image widths. The new row uses measured manual frames and aspect-fit icons; it has no Auto Layout constraints to break.

Country-name normalization previously scanned hundreds of localized suffixes on each call. It now indexes by the last word, prepares the locale table away from the main thread, and recognizes ISO suffixes too. On the same Mac interpreter and five equivalent inputs, 5,000 old lookups took 1.867659 seconds and 5,000 indexed lookups took 0.022675 seconds. This microbenchmark excludes initial table construction and does not measure whole-app or phone responsiveness. Grouping checks passed, including Barcelona/Spain/ES aliases.

Trip-derived pins are prepared before mounting the map and updated only when trips change. Marker rebuilding is coalesced over one frame and skipped when its inputs are unchanged; city membership is indexed once per rebuild. Library and inactive workspace view construction are deferred during cold launch.

Search publishes whichever provider finishes first, retains rows through the debounce, cancels stale queries, and gives the Google gateway a six-second request timeout. No full phone search latency measurement was captured.

Native Apple POI selection uses the annotation callback, retains MKMapItemRequest until completion and opens basic name/coordinate information if the lookup fails. Area/POI selections share the search focus/detail path.

The complete original SVG is rendered again with its original timing and viewBox; the short baked loop was removed. SVG readiness no longer holds usable app UI behind the loader. WebKit startup cost remains and is separate from the measured marker stall.

Mobile Dev streamed physical iPhone logs and captured map.ready +3.587s during a normal relaunch of the installed build. This is a warm baseline, not an after-measurement of the latest source changes. CPU attachment failed because of debugger/development-signing access; a new physical-device build was blocked by filesystem/Xcode service restrictions. Latest simulator build and launch succeeded without warnings or errors. The two-minute cold-launch symptom is not yet verified as resolved on the phone.
