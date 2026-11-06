# Map search, Library actions and planning refinements

Focused map search uses a stronger regular-material surface and rim, with a modest white wash in light mode. Travel-marker glass retains its existing appearance. The search overlay ignores the keyboard safe area; its glass frame extends to the bottom of the viewport. Only panel content receives a keyboard-overlap inset. Keyboard updates stay inside the panel subtree, and the overlap calculation uses the stationary outer viewport so dragging cannot reflow the results.

Saves use hearts in map filters, individual markers, merged counts, save actions and Library badges. Dedicated plus/minus map zoom controls and their implementation were removed; pinch gestures, fitting and cluster expansion remain available.

The Library action is a direct button: plus for Trips and Pins, pencil for Notes, and link for Videos. Pins requests search on the Map tab. Requests are consumed once to avoid reopening search when the map remounts. Library dates use `5/12-9/12 2026`, with explicit same-day, cross-year and flexible-date handling.

Planning uses scoped light/dark colors, raised input surfaces, stable selection pills and charcoal/sage/peach dark-mode roles. Its final step includes a destination card with a map pin, dates and traveler count. Existing deferred screen boundaries and device-signing fixes are preserved.

Verification: production date/draft, map clustering/search-layout and Library/planning contrast checks pass. Planning text/selection/action contrast is at least 4.56:1. Eight light/dark component compositions were rendered with SwiftUI ImageRenderer and inspected (see `planning-design.png`). These galleries use production colors, surfaces, selection controls and destination cards; they are not live phone screenshots. The signed iPhone build launched and remained running through the previous startup crash point. Keyboard interaction and touch visuals still need hands-on phone verification.

## Custom identities and consolidated Videos

Trips and saved places have optional, backwards-compatible `MarkAppearance` metadata. Pins also support an optional user category without changing their base place type. The identity editor offers searchable icon, emoji, flag and symbol pages, preset colors, a custom color picker and automatic/default resets. Cancel leaves stored data unchanged. Trip naming and research retain the existing draft persistence gate; choosing an icon alone cannot create an unnamed trip. Trip and pin icon wells open the editor directly in Library, and map save menus support optional customization before saving. Owner-aware saving preserves the existing trip pin identity when a place is saved again. Custom category filter keys encode the full label so punctuation cannot split filter storage.

Library dates use bold Plus Jakarta Sans, a distinct year capsule and an icon with a bold traveler count. The extra continue-planning label is gone. Trips and Pins use plus as their creation action. City-filter and grouped-city sections show a spaced city/country/flag card; the expanded country map panel also uses clearer city rows and separate count chips.

Inbox was removed from Library. Videos now includes all imported sources and supports All/Pending/Review/Ready filters, per-source state badges and processing progress. Existing sources, retrieval actions, linked notes and places remain in the same storage. Unknown import states stay visible for review. The shared-extension inbox transport remains required for receiving shares.

Validation includes legacy saved-place decoding, identity/category/color round trips, distinct filter keys, all four glyph catalogs, source-state classification and preservation through brief edits. Customization controls and city/date components were rendered in all four glyph modes for light and dark appearance (`customization-design.png`); these are component galleries rather than live phone screenshots.

Final verification after customization and Videos consolidation: Simulator compilation succeeded with zero warnings/errors; the signed build launched on the connected iPhone and remained running without a startup exception. All production-model regression and contrast checks passed. Phone touch/keyboard interaction and live visual inspection were not automated.

## Planning selection, location precedence and deletion

Planning option labels are centered before selection. A leading check fades in as the label moves right with a spring; its measured footprint stays constant, and Reduce Motion disables the animation. Progress segments follow orange, pale orange, yellow and green in step order.

Trips, personal/trip pins, Videos and Notes now have visible trash controls with a confirmation dialog. Video deletion records a persistent tombstone, preventing shared-inbox imports from restoring it, and preserves linked notes and place mentions. Note deletion preserves its place mentions. Deletion clears active detail selections where applicable.

Location details have an independent Pin toggle, alongside Save and Save-to-Trip. Optional stored pin/save flags preserve legacy save behavior and allow either or both states. Map records are deduplicated by stable place identity, Google identifier, or matching name/coordinate; pins take precedence over saved copies. Underlying record IDs remain available for Library filters. Individual places use a compact glass circle without a count, with a small readable name capsule below. Title overlays cannot change the map coordinate. City summaries count distinct winning locations, so a pinned-and-saved place does not show twice.

Validation: the final Simulator build succeeded with no warnings or errors. Production-model draft/persistence/deletion, map clustering/identity/anchor, Library grouping and light/dark contrast checks pass. Planning pills/progress and stored markers were rendered with SwiftUI ImageRenderer and visually inspected in light and dark appearance. Component galleries do not verify live map gestures or deletion interactions on the phone.

The signed iPhone build also launched and remained running past the former startup crash point. Live gesture, keyboard and deletion interactions require hands-on phone verification.

## One map group per city

City names with and without a country suffix share a normalized identity (`Barcelona`, `Barcelona, Spain`, `Barcelona Spain`). Cached city centers use a deterministic lookup. At distant zoom there is one fixed-size liquid-glass flag pin per city, with a city/country label outside. Tapping it opens only the Trips/Pins/Saves icon-and-count row; there is no country-level grouping or nested city list.

At closer zoom, merged city categories share one intrinsic-width row with 8-point gaps. The distant dot state uses equally sized adjacent dots for all visible categories; expansion displays counts for Trips, Pins and Saves. Standalone place labels participate in overlap detection, so name capsules also trigger merging. Existing pin-over-save precedence is preserved. Category filters are applied before grouping, so hidden categories disappear from both flags and rows while remaining categories keep the same city anchor. Hosted content refreshes when membership or the flag/row mode changes.

Validation: Simulator build succeeded without warnings/errors. Production clustering tests cover country-suffixed city aliases, one flag per city, membership preservation, stable anchors, category-filter removal and zoom restoration. Library grouping and light/dark contrast checks also pass. Live map gesture/layout behavior has not been touch-tested on the phone for this refinement.

World globe and source-aware neighborhood exploration are documented in `WORLD_AND_NEIGHBORHOODS.md`. Been starts disabled on the general map; visits remain explicit and separate from planned trips.
