# Reference-informed SwiftUI redesign — November 2

The five images in `ui/inspiration` were read and visually inspected. This pass uses the cached [Wholiver SwiftUI Design Skill](../.local/skills/swiftui-design-skill/SKILL.md) and the existing Trippy brand. The screenshots inform hierarchy and interaction, rather than supplying copied illustrations or controls.

## Direction chosen

Considered three approaches within the supplied brief: an expansive map with floating controls, a photo-led Library entry, and a permanently expanded itinerary dashboard. Selected the expansive map because the user's entry point is personal Saved and trip cities. The other approaches consume the map area before the user asks for detail.

Reference characteristics retained: bright native cartography, rounded floating search, a distinctive personal trip title, a compact metadata pill, day selection near the bottom, and an upward-opening detail panel. Trippy uses forest/coral, SF Symbols, native Map/Library tabs and a Georgia Bold Italic trip title. The screenshots' flags, emoji markers, profile ring, collaboration, randomize and open-now controls were not copied into unsupported flows.

## Changes implemented

- Home map: one search row and map-options control; a functional new-trip action near the bottom. No large introductory card or permanently visible stack of settings.
- Trip map: compact personal title and metadata at the top. Overview/day selection, planned/recommended/Saved switches and the detail peek move to the bottom.
- Categories and preview transport mode live in a filter sheet. Theme/appearance and fit-all live in the map-options menu.
- Map camera no longer reframes on every category/layer edit. Day selection explicitly refits; route changes still invalidate stale geometry.
- Pin symbols have a compact circular treatment with small itinerary-order badges. Route colors brighten in dark appearance.
- Library uses restrained text navigation, search on request, one contextual add menu, more breathing room and photo-led trip rows. Duplicate Notes/Inbox add actions were removed. Note search includes retained source evidence.
- Brief keeps destination, dates and party in the initial form. Styles, pace, interests, diet, mobility, accommodation, budget and notes expand on request. Service configuration moves to a separate settings sheet. The invented 02/03 progress strip was removed.
- A compact map shelf is implemented for landscape/accessibility text sizes. The filter sheet also contains all layer switches so controls remain available in that layout. The expanded detail panel uses a scope menu rather than another duplicate day strip.
- Search can be dismissed even when empty. Add-to-plan actions are exposed only when a recommendation has a usable ID and the trip has a day; the action names its actual destination day.

## Design review

| Dimension | Code/reference review | Runtime verification |
|---|---|---|
| Context and identity | User-supplied map hierarchy; Trippy palette, symbols and title treatment | Screenshot comparison pending |
| Layout and hierarchy | Reduced top chrome; controls below; progressively disclosed details | Small/large device and sheet interaction pending |
| Typography | Distinct trip-only display type; body/caption hierarchy; scalable fonts | Long-title/Dynamic Type rendering pending |
| Color and surfaces | Semantic light/dark ink; glass in control layer; brighter dark routes | Contrast over actual map imagery pending |
| Motion and interaction | Restrained press/day transitions; Reduce Motion fallback; existing SVG retained | Touch/gesture/loading rendering pending |

No final numerical design score is claimed without rendered app screens.

## Verification and limits

The static iOS 17 SDK check, using a temporary State-wrapper alias to avoid sandbox-denied macro subprocesses, passed. Native persistence regression fixtures passed for old trips, opaque research, order/edits/coordinates/checklist/budget, personal saves and share/note/evidence retention. Syntax and whitespace checks passed.

The attempted full Xcode/Simulator build did not execute: automatic approval infrastructure returned `404 deployment not found`. A full build, screenshots, real MapKit behavior, signing/App Group and device Share Sheet tests remain pending. This pass implements a redesign; it does not certify a tested release or complete the connected planner benchmark.
