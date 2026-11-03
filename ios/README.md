> Plan redesign: [failure audit, replacement UI and verification limits](../docs/PLAN_REDESIGN_AND_FAILURE_AUDIT.md).

> Reference-informed redesign: all five inspiration images have now been inspected. See [new layout and verification status](../docs/UI_REFERENCE_REDESIGN.md).

> November 2 map-first update: the app now implements Map / Library navigation, personal Saved, city filtering, a trip map workspace and the supplied SVG loading emblem. See [implementation and validation status](../docs/MAP_FIRST_UI_IMPLEMENTATION.md). Full Xcode/Simulator validation is pending sandbox access; the older carousel description below documents the prior flow.

# trippy for iOS

Native SwiftUI app for iPhone and iPad, targeting iOS 17 or later. Android is not part of this version.

## Open and run

1. Install Xcode from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835).
2. Open `Trippy.xcodeproj` in Xcode.
3. Select the `Trippy` scheme and an iPhone simulator from the device picker.
4. Press **Run** (`⌘R`). For a physical iPhone, select your development team under **Signing & Capabilities** first.

Baseline verified on 29 October 2026 with Xcode 27.1 and the iOS Simulator 27.1 SDK: the existing app builds successfully for the generic Simulator destination. A build does not certify UI flows; Simulator screenshots and interaction checks follow during UI stages.

## Current flow

1. **Start:** one photo-led carousel for existing trips, with the balloon mark and a single plus action in the header. Swipe horizontally to browse; tap the centered card to open it. A first-trip card appears when the user has no saved trips. The ivory canvas, logo, Plus Jakarta Sans, and six warm editorial cover images establish the visual language.
2. **Brief:** enter destination, date flexibility or duration, trip style and pace first. Group size, interests, budget and notes are in an expandable preferences section. The app turns every selection into a structured research prompt.
3. **Research and trip dashboard:** copy the prompt to ChatGPT, paste its JSON response back into the app, then browse the photo hero, collapsible itinerary days, place pool, map coordinates, costs, and source links from compact bottom navigation. Imported trip data is stored locally with `UserDefaults`.

The current version supports manual copy/paste and an Azure research bridge. The bridge is a legacy shared-state prototype; the staged redesign replaces it with owner-scoped storage/jobs. Manual imports remain supported. Its research prompt asks for traceable sources and explicit unknown values; the app does not invent missing prices, venue facts, or coordinates. The prompt generation can later be routed through a local model or API without changing the brief model.

## Brand kit

The supplied reference informed the balloon-pin mark, lowercase wordmark, app icon, warm palette, and card styling. Source vectors, generated destination cover art, font files, and design guidance live in `Trippy/Brand/`, `Trippy/Assets.xcassets/`, and `Trippy/Resources/`. Asset-generation prompts are documented in `../docs/ASSET_GENERATION_PROMPTS.md`.

## Active implementation

[Autopilot stages](../docs/AUTOPILOT_STAGED_IMPLEMENTATION.md), [verified status](../docs/IMPLEMENTATION_STATUS.md), [frontend-design direction](../docs/UI_DESIGN_DIRECTION.md).
