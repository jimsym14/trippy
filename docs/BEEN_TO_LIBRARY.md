# Been to in Library

The redesign is limited to the Library's Been section, renamed **Been to**. The general map's existing filters, city labels, country groups, and visits persistence are preserved. The Library tab picker remains intact.

## Design and working flows

The eleven references in `ui/inspiration/been` informed the map-first composition, warm amber accents, small floating controls, continent carousel, draggable passport, and share cards. The implementation uses Trippy's typography and quieter warm neutral raised surfaces, rather than reproducing the reference app's navigation or branding.

- A bounded native MapKit canvas replaces the globe embedded in the Library's page ScrollView. The initial world camera is applied after layout. Continent chips show system globe icons and focus all six inhabited continents, including ones with no recorded visits.
- A compact glass passport strip expands by dragging its grabber/header or tapping it. Gesture translation is transient; only the final detent is committed. Its expanded view uses compact statistics, timeline/flags/milestone shortcuts, and country/continent/city collections. The expanded card takes the available Library canvas; floating map controls fade away and share becomes available in the card header.
- The summary reports actual countries/regions and cities. The ring represents six inhabited continents; it does not invent a sovereign-country coverage denominator.
- Country collections open city visits; cities open date editing, Apple Maps, and confirmed removal. The timeline supports year groups and oldest-first chronology. Flags and milestones derive from explicit visits. Planned trips do not become visits automatically.
- Add city is a native sheet with an interactive Liquid Glass search field, compact visit date, live Apple address search, and large one-tap result rows. Queries debounce by 300ms; obsolete responses cannot replace the current query. Existing visits are marked and disabled. Empty space is not a ScrollView. Search results scroll above the keyboard. An eight-second request cancellation and retry state prevent an indefinite search spinner.
- Share offers globe and flag card styles and native image/text ShareLinks. Exports render at 3× resolution and show actual totals. The globe artwork is a lightweight orthographic coordinate illustration, not a second live map; it only plots the visible hemisphere. The flags card centers rows and indicates additional countries beyond its nine-flag layout.
- Map appearance offers native standard/satellite cartography, country fill/outlines, and close-zoom city names. Unsupported airports, administrative regions, and social comparison are not presented as empty or fabricated features.

## Clustering and performance

`BeenGlobeMap.swift` uses `MKMapView`'s native annotation clustering for collision detection and merge/split animation. Cities have stable annotation objects; record changes add/remove only the affected annotations. Distant annotations are small amber count blobs; close annotations become compact named city pills. Tapping a cluster uses native annotation fitting. At the closest zoom, a cluster that cannot separate opens its city list.

Map annotations are lightweight UIKit views with cached layout signatures and shadow paths. They do not host SwiftUI or individually render glass. Liquid Glass is reserved for the panel, search, and floating actions; nearby glass controls use a GlassEffectContainer. Native iOS 26 glass has a material fallback for older supported systems.

Visit snapshots rebuild on storage changes. The map coordinator checks revisions rather than sorting/decoding visits during panel drags. Country geometry is fetched without hatches, simplified off the main actor, and converted to cached MKPolygon/MKPolyline layers. Three vertex budgets reuse the existing Been boundary preparation. Overlays change only with source revisions, toggles, or settled zoom-detail thresholds. There is no eager city-boundary loading in Library.

## Verification and limits

Simulator builds and launch checks use XcodeBuildMCP. The passport was expanded through an actual Device Hub drag; the add-city sheet, focused field, keyboard introduction, query typing, and native glass were visually inspected. The Simulator Apple search request did not deliver usable live results during the initial check; the bounded cancellation/retry flow was added in response. Network result selection needs a live-service check.

`test_ios_world_explorer.py` checks persistence, explicit visit semantics, country casing, passport totals, continent filters, missing-country handling, and chronology. Existing boundary and Library grouping/contrast regressions pass.

`render_ios_been_library.py` renders production UI components in light/dark, collapsed/expanded/empty, collections, search, and both share styles. Its backdrop is explicitly a fixture globe. ImageRenderer cannot capture native glass or AppKit text fields: the gallery uses a material fallback and static query text only in those positions. Native material is checked separately in Simulator screenshots. Populated cluster playback and physical-device frame rate have not been measured; native clustering and reduced geometry work should not be described as benchmark results.

The root TrippyScreen deferred/AnyView boundaries remain in place to preserve the previous device startup metadata fix.
