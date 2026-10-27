# trippy for iOS

Native SwiftUI app for iPhone and iPad, targeting iOS 17 or later. Android is not part of this version.

## Open and run

1. Install Xcode from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835).
2. Open `Trippy.xcodeproj` in Xcode.
3. Select the `Trippy` scheme and an iPhone simulator from the device picker.
4. Press **Run** (`⌘R`). For a physical iPhone, select your development team under **Signing & Capabilities** first.

This workspace currently has Swift command line tools but no Xcode or iOS Simulator SDK installed, so the project cannot be built or launched here.

## Current flow

1. **Start:** one photo-led carousel for existing trips, with the balloon mark and a single plus action in the header. Swipe horizontally to browse; tap the centered card to open it. A first-trip card appears when the user has no saved trips. The ivory canvas, logo, Plus Jakarta Sans, and six warm editorial cover images establish the visual language.
2. **Brief:** enter destination, date flexibility or duration, trip style and pace first. Group size, interests, budget and notes are in an expandable preferences section. The app turns every selection into a structured research prompt.
3. **Research and trip dashboard:** copy the prompt to ChatGPT, paste its JSON response back into the app, then browse the photo hero, collapsible itinerary days, place pool, map coordinates, costs, and source links from compact bottom navigation. Imported trip data is stored locally with `UserDefaults`.

The current version uses a manual copy/paste loop. Its research prompt asks for traceable sources and explicit unknown values; the app does not invent missing prices, venue facts, or coordinates. The prompt generation can later be routed through a local model or API without changing the brief model.

## Brand kit

The supplied reference informed the balloon-pin mark, lowercase wordmark, app icon, warm palette, and card styling. Source vectors, generated destination cover art, font files, and design guidance live in `Trippy/Brand/`, `Trippy/Assets.xcassets/`, and `Trippy/Resources/`. Asset-generation prompts are documented in `../docs/ASSET_GENERATION_PROMPTS.md`.
