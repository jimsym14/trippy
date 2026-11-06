# General map — native clustering, November 4

The general map now uses `GeneralNativeMap` in `BeenGlobeMap.swift`: the same MKMapView collision, annotation reuse and animated cluster expansion pipeline as the Library Been to globe. City markers and numbered blobs share its orange fill. Lightweight UIKit labels replace per-marker SwiftUI/glass rendering. Workspace maps retain their existing SwiftUI implementation.

Marker snapshots change only when source records or filters change. Stable annotation instances survive pan/zoom; native MapKit handles merge/split placement without a custom SwiftUI screen-projection regrouping pass. Local place visibility changes at the 0.08° latitude-span threshold. Counts deduplicate trips, pins and saves, and local city summaries only include places actually attached by clustering. Pin-over-save display precedence and exact Library member routing remain intact. Explicit camera requests animate without resetting the camera after a user gesture.

Native country/city overlays reuse prepared geometry by revision, zoom detail and filter options. General map camera updates publish only when gestures settle. The Been to filter panel separates City markers and Country layer, with Hatching, Detailed outlines and City boundaries behind a collapsed Map detail disclosure. Visible labels use Been to; persistence keys are unchanged.

Validation:

- Simulator Debug build passed with zero warnings/errors; normal launch and Barcelona → exact trip Library filter checked.
- A process-local Debug fixture with 20 European cities produced orange overlap blobs. Recorded cluster-tap expansion into the five Iberian cities with an animated camera transition in `been-design/general-native-merging.mp4`. Fixture data never writes user storage and is opt-in via `TRIPPY_GENERAL_MAP_FIXTURE=1`.
- Inspected the actual Been to filter panel and its detail disclosure in the simulator.
- Native marker identity/count/routing, legacy clustering, geometry, World Explorer and Library grouping regressions passed. Updated stale legacy tests to use a genuinely close zoom (0.07°) and the existing cross-border blob membership behavior.
- Dense geometry fixture: 5,001 vertices reduced to 63 at world detail. No physical-device FPS or populated outline performance measurement is claimed.

The older sections below describe previous iterations; the native general-map behavior above supersedes their custom grouping and marker descriptions.

---

# General map, city summaries and search

Implemented and refined November 3, 2026 in `ios/Trippy/TrippyApp.swift`.

The general map loads personal saves, trip-saved pins, located research places and itinerary stops. Rendering IDs are scoped to trips while original place IDs remain available for saves and linked notes. City centers are resolved/cached for trip destinations and cities represented by saves or pins.

## Filters and controls

The left-to-right carousel is ** Maps → Trips → Saves → Pins**. Raised pills are 34 points tall, white in light mode and charcoal in dark mode. Enabled pills have a green light; disabled pills are slightly darker with a dimmed light. Carousel shadows reach the screen edges.

Maps contains a padded places toggle, native POI category pills and a clickable theme menu beneath the categories. Trips and Pins have their own filters. Larger glass cards have display titles and cover map controls when expanded. The gear menu retains dark appearance, Google Places settings and fit-to-visible-points; Automatic/Forest/Coral/Amber/Sage glass-tint choices have been removed. Selected navigation colors remain visible in dark mode: sage for Map, coral for Library, and matching pastel colors for workspace sections. Settings, plus, location and zoom buttons use circular raised surfaces. The north-reset indicator and rotation-lock buttons have been removed; native map rotation remains available. The map edges retain a progressively masked ultra-thin blur. Explicit dark shading is removed from both edges; light mode retains only a subtle white tint at the top. The bottom has no added tint in either appearance. Search and map badges use subdued frosted capsules with faint borders instead of highly white-tinted Liquid Glass surfaces; glass elsewhere in the app remains unchanged. Plus/minus zoom uses a 0.3-second smooth animation, with Reduce Motion respected.

## City labels and summaries

Each represented city has a stable annotation at its cached city center, with a fallback to known member coordinates. The city title uses semibold system text with a subtle cartographic halo (white in light mode, dark in dark mode) and contrasting text and cached country abbreviation (for example, “Barcelona, ES”). Its size decreases gradually from 20 to 16 points as the map zooms out and remains present at every zoom stage. Unknown country codes are omitted; existing caches without this optional field remain compatible. This is our map-style replacement: MapKit does not expose the exact placement or independent visibility of its built-in city labels. City display names omit comma-separated country names, so “Barcelona, Spain” with code ES displays as “Barcelona, ES”. The badge/dot row uses a center annotation anchor at the cached geographic coordinate. Its title is drawn above as an overlay and never contributes to the annotation’s measured size; changing title width or zoom cannot shift the pin location. The title sits a few points above the visible badge or dot.

At close zoom, places retain their individual annotations. Screen-overlap clustering determines when places meet a city anchor. Items join that city's summary only if their city matches after case/diacritic normalization; even a screen cluster spanning multiple cities cannot mix their city memberships.

A summary shows a horizontal row of frosted glass **luggage + trip count**, **bookmark + save count**, and **pin + pin count**. Empty types are omitted. Trip counts use distinct trip IDs rather than the number of research places. Saves count personal map records; pins count scoped trip-pin records. Purple, amber and coral distinguish the three types.

At distant zoom (latitude span 2.4° and above), the larger 32-point badges collapse into fixed 12-point colored dots underneath the city title. Tapping a dot reveals the badge row. An upward swipe collapses it; zooming in shows the badges naturally. Floating clusters that have not reached a city anchor also retain separate counts by type.

At latitude spans of 16° and above (continental view), represented cities become compact flag pins. Same-country cities merge only when their screen footprints overlap, so several cities in one country can remain visible. Each symmetric pin is capped at 27×36 visible points from its first appearance and at every further zoom, inside a separate 44-point touch target. The glass is clipped to the pin silhouette, preventing its visual treatment from enlarging the visible pin. Its country flag sits inside above a combined count of distinct trips plus saves and pins. The surface uses adaptive light/dark Liquid Glass with a restrained neutral tint, with material and Reduce Transparency fallbacks. There are no category or random colors on compact flag pins. The tip is its bottom annotation anchor: individual city pins remain at their city centers, and overlapping city groups anchor at the geographic centroid of their city centers, independent of screen projection or record counts. Unknown country codes retain their individual annotations. A tap expands a compact scrolling card of the represented cities with separate trip/save/pin count buttons; tapping again collapses it. The card grows above the pin, keeping its tip fixed. Counts route to the same exact city/type Library filters. Zooming back in restores the larger city labels and badges.

Badge taps open Library with the selected cities, type and exact member/trip IDs. Saves show personal saved places; Pins show matching trip-saved pins; Trips show matching trips. The filter chip can be cleared. The unfiltered Pins section includes personal saves and trip pins, while social suggestions are omitted from exact map-filtered results. Pin removal and map focus retain the original stored place ID and trip ownership.

Native MapKit annotations move with every pan frame. Screen projection is used only to decide cluster membership; render anchors never chase screen pixels. Membership-preserving translations do not republish clusters. Layout recalculates for zoom, rotation, pitch, filter/data/city-cache changes and final gesture settling.

## Stationary search

The search bar stays at the top. Opening it expands it into the space occupied by settings; the plus remains at the right and rotates 45° into the close control. Closing restores the original width, settings and plus action. The search bar remains stationary while a separate draggable results panel opens below it; there is no search title.

A full-width native Liquid Glass panel (with material/Reduce Transparency fallbacks) rises from and stays docked to the bottom edge, with rounded top corners and an 18-point gap beneath the search row. A grabber, the empty prompt area, header, outer padding and blank list background support downward dragging: a long drag or quick downward flick closes the panel, disables search and dismisses the keyboard; a short drag springs back. Dragging uses global coordinates and translates the panel at its fixed height, avoiding moving-coordinate feedback and repeated content reflow. Its drag state lives in a separate panel subtree, so each finger movement does not rebuild the map. Native interactive Liquid Glass is applied to the touchable panel itself, enabling the iOS 26+ touch highlight; the decorative bottom backing does not handle touches. It contains:

- Apple and Google icons with per-query status lights: green for a successfully used service, red for an unavailable/failed service, neutral while idle/loading.
- A small result count and loading spinner.
- Raised category pills, clipped within the panel with room for their shadows.
- A lazy scrolling list with result rows at least 96 points tall, place/address/category information and existing detail/map-focus actions.
- Loading, empty and error states, cancellation/debouncing, and interactive keyboard dismissal.

The panel height follows the available area below the stationary bar, including keyboard resizing. The map ignores only container safe areas, preserving keyboard avoidance so results scroll above the keyboard. The panel overlay belongs to the outer MapReader viewport, outside the map’s own safe-area inset. Its whole viewport extends through the container’s bottom safe area while preserving keyboard avoidance; only content is clipped. The backdrop ignores both keyboard and container bottom safe areas, so it extends behind the keyboard to the phone’s bottom edge while results remain above the keyboard. Opening search hides the tab and navigation bars; closing restores their normal visibility. The empty-search icon and rounded-font prompt are centered in a non-scrolling draggable area. Result lists continue to scroll, and category-filtered empty lists have scrolling disabled. The Google G asset was downloaded from Google's public branding image at `https://www.gstatic.com/images/branding/googleg/1x/googleg_standard_color_128dp.png`. The research screens retain their existing glass treatment.

## Verification

- PASS: `python3 scripts/test_ios_map_clustering.py` executes the real Swift algorithms. Covers overlap/split behavior, stable identities, 2,000 dispersed markers, 300 crowded markers, screen translations, date-line anchors, fixed dots, city attachment, distinct trip/save/pin counts, exact Library filters, capped city-label sizes/country formatting/flags, backward-compatible coordinate caches, actual country rendering membership (separate countries and nonoverlapping same-country cities, overlap merging/splitting, no lost/duplicated records, exact city expansion, combined counts, fixed pin footprint, symmetric Bézier geometry and centered tip, unknown-country fallback, stable coordinates through zoom), keyboard-sized search layout and drag dismissal thresholds.
- PASS: generic iOS Simulator build with Xcode 27.2, `CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`, DerivedData `/tmp/trippy-map-build`. The frontend option resolves the restricted environment's macro subprocess failure.
- PASS: `git diff --check`; Google glyph verified as a 128×128 RGBA PNG.
- NOT RUN: live Simulator interactions/screenshots and VoiceOver. CoreSimulatorService is inaccessible. Replacement/native city-label interaction, city-row spacing at different zooms, dot reveal/upward collapse, country expansion/collapse, Library navigation, search expansion, bottom docking, drag dismissal, keyboard behavior and final visuals require runtime verification.

The installed SwiftUI UI Patterns, SwiftUI Expert and SwiftUI Liquid Glass skills were applied. A separately callable SwiftUI design-tool plugin was not available.
