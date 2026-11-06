# Library — November 4 refinement

The Library is presented in English, with an icon beside its masthead and every picker tab. There is no masthead subtitle. Search stays top-right; each tab owns its add action beside its content title. Videos retains all import states and linked-source/note/place actions. Pins and Saves retains city/member filters, customization and ownership-aware deletion.

Trips use Upcoming, Past and Completed banners, country headings, city subheadings and individual trip cards. The nearest travel dates appear first within each section; undated trips remain Upcoming and sort last. End dates determine Past, while an optional persisted `completedAt` records explicit completion independently of research. Older records decode without this field. A context-menu action can restore automatic date-based placement.

Cards use a large single-line title with a bounded scale reduction, raised date/traveler pills and an accented year. Edit/Overview, Complete and confirmed Delete are arranged in a separate action row. An outline distinguishes cards with an overview. Icon/color customization remains on the icon and context menu; brief editing remains available even when an overview exists.

Been to has the title “You have been to”, an orange raised plus, native glass share/layer controls and a map extending behind the bottom navigation. The matching base-color material fade blends the header into the map. Its draggable collection panel stays above navigation. Existing collections, chronology, flags, milestones and sharing are preserved.

Validation: final iPhone 18 Pro Simulator build passed without warnings; clean launch and Library/Been to navigation checked. Production card/section renders inspected in light and dark modes (`docs/library-design/trips-light.png`, `trips-dark.png`). The host regressions cover old-data decoding, explicit completion, date-based phases, proximity sorting, record preservation and palette contrast. Render fixtures are isolated from user storage.

---

## Previous implementation notes

Implemented November 3, 2026. The existing Trips / Pins / Videos / Notes / Inbox tab picker retains its labels, selection behavior and underline. The header and picker now remain above the collection scroll area. Search, add actions, map filters and city filter clearing remain available.

## Design system

The `Library design components` section of `ios/Trippy/TrippyApp.swift` contains Library-only semantic colors, raised/inset surfaces, icon wells, metadata badges, section headings and actionable empty states. The full Library background blends white (light mode) or black (dark mode) into the selected tab’s pigment. A static 128×128 grayscale tile combines ordered Bayer dithering with deterministic grain; the texture is cached once and stays fixed while scrolling. Raised cards retain ivory/charcoal surfaces for readability. Text and subtle borders define hierarchy as well as color, so information does not depend on the accent alone. Rounded system type supports Greek and Dynamic Type; the Library masthead retains Plus Jakarta Sans.

| Collection | Light accent | Dark accent | Content hierarchy |
| --- | --- | --- | --- |
| Trips | Sage `38634F` | `A4CEB9` | Destination group → trip title → dates/travelers → plan availability |
| Pins | Terracotta `99523F` | `EFAB94` | City → place/address/category → personal save or owning trip |
| Videos | Lavender `70588F` | `C5B2E2` | City → media/title → place/note counts → linked note |
| Notes | Amber `7B5A29` | `E3C48B` | City or personal collection → updated date/title → preview → linked sources/trip/places |
| Inbox | Blue `45677E` | `ABCADA` | Pending/review/ready → source/title/city → explanation/status/date |

Cards use directional highlight and shadow, a quiet rim and 24–26-point radii. Raised controls have 44-point minimum touch targets. Metadata badges have explicit text and symbols. Empty/search-filtered states are included for every collection, with existing create/import actions. Collection content is lazy and limited to a 720-point reading width. Trip cards present actual trip metadata rather than unrelated fallback destination photos. Video thumbnails use stored media; unavailable media has a clearly generic play illustration.

## Behavior preserved

- Trip selection, brief editing and deletion context menu.
- Personal saves and trip-owned pins retain distinct record IDs, map focus and ownership-aware removal.
- Apple Maps opening, city scoping and exact map member/trip filters.
- Source details, import links, linked note opening, note creation and editing.
- Video and source details retain the complete original information; collection cards show a readable summary.
- Horizontal city memory cards use the same surfaces and readable dark-mode accents.

## Verification

- PASS: XcodeBuildMCP generic build/run on iPhone 18 Pro Simulator, followed by a final simulator build after the palette adjustment.
- PASS: `python3 scripts/test_ios_library_grouping.py`: executes production grouping; checks case/diacritic normalization, unknown-city grouping, stable identities, no lost/duplicated records, text/badge contrast against both surface endpoints. The strongest gradient and extreme grain pixels are checked too; minimum text contrast is 4.57:1.
- PASS: `python3 scripts/test_ios_map_clustering.py`: existing map and exact Library-filter regression checks.
- PASS: `git diff --check`.
- PASS: rendered and visually inspected production shared SwiftUI components in light and dark modes using the macOS ImageRenderer helper. These are component previews, not screenshots of populated Library tabs: [light](library-design/components-light.png), [dark](library-design/components-dark.png).
- Compiled offline light/dark/large-text/empty previews. Larger-text appearance still needs iOS runtime verification; macOS rendering does not reproduce iOS Dynamic Type sizing reliably.
- The plugin built, installed and launched the actual iOS app, and captured its initial Map screen. Live Library interaction/screenshots were not completed: simulator accessibility session creation timed out, then the simulator was reported shut down. Automatic approval review also rejected opening Device Hub through Computer Use because access to that app was not approved.

The installed SwiftUI UI Patterns, SwiftUI Expert and Create Design System skills were used, along with the Build iOS Apps plugin's XcodeBuildMCP tools. No separate Swift design-canvas tool was available.

Run `python3 scripts/render_ios_library_design.py` on macOS to reproduce the component previews. It extracts the real Library component section from `TrippyApp.swift` and compiles it with `scripts/render_ios_library_design.swift`. The components live in the app’s established compilation unit to avoid missing-type errors when Xcode has not refreshed newly added source-file membership. It only renders offline samples and never reads or mutates the user's saved Library.

## Trip creation and location controls

New Trip opens a transient form above the mounted native tab/map hierarchy, without inserting an empty trip. New-trip actions inside a place sheet wait for that sheet’s dismissal. Naming immediately saves the form; starting research saves an unnamed form with a destination-based name. Form autosave and research retries use the same persistence gate and preserve the same trip ID. Existing unnamed records receive a name on loading without losing their content.

`python3 scripts/test_ios_trip_drafts.py` exercises the production persistence gate and storage: unnamed forms, destination-only forms, naming, rename, retained names after clearing a field, research/retry, form preservation, Codable round trips and idempotent legacy-name migration. These checks use isolated test storage and no research service calls. The simulator compile passes; the reported New Trip crash has not been reproduced in a live simulator/device session.

Long-pressing the current-location control hides the user-location annotation and cancels pending recentering; a tap enables it again and recenters. Location use for explicit directions remains separate. An exclusive gesture prevents a long press from also triggering the tap.
