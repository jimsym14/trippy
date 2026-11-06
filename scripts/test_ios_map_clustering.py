#!/usr/bin/env python3
"""Execute the map's real screen clustering algorithm without a Simulator."""
from pathlib import Path
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / 'ios/Trippy/TrippyApp.swift'
CHECKS = r'''
let samePlaceItems = [
    MapPlaceIdentity.Item(id: "save", placeID: "place", googleID: nil, name: "My renamed save", latitude: 41.38, longitude: 2.17, layer: "saved"),
    MapPlaceIdentity.Item(id: "trip-pin", placeID: "place", googleID: "google-1", name: "Coffee", latitude: 41.38, longitude: 2.17, layer: "pin"),
    MapPlaceIdentity.Item(id: "other-provider", placeID: "another-id", googleID: "google-1", name: "Coffee", latitude: 41.380001, longitude: 2.17, layer: "saved")
]
let samePlaceGroups = MapPlaceIdentity.groups(samePlaceItems)
precondition(samePlaceGroups.count == 1 && samePlaceGroups[0][0] == "trip-pin", "A pin takes visual precedence over saved copies")
precondition(Set(samePlaceGroups[0]) == Set(samePlaceItems.map(\.id)), "Deduplicating display must retain every Library filter identity")
precondition(MapPlaceIdentity.groups(Array(samePlaceItems.reversed())) == samePlaceGroups)
let nearPlaces = [MapPlaceIdentity.Item(id: "a", placeID: nil, googleID: nil, name: "Coffee", latitude: 41.38, longitude: 2.17, layer: "pin"), MapPlaceIdentity.Item(id: "b", placeID: nil, googleID: nil, name: "Coffee", latitude: 41.3801, longitude: 2.17, layer: "saved")]
precondition(MapPlaceIdentity.groups(nearPlaces).count == 2, "Nearby different places are not duplicate saves")
let manyDistinctPlaces = (0..<2000).map { MapPlaceIdentity.Item(id: "place-\($0)", placeID: nil, googleID: nil, name: "Place \($0)", latitude: Double($0) / 1000, longitude: 0, layer: "pin") }
precondition(MapPlaceIdentity.groups(manyDistinctPlaces).count == 2000)

func point(_ id: String, _ x: Double, _ y: Double, _ radius: Double = 22) -> MapScreenPoint {
    MapScreenPoint(id: id, point: CGPoint(x: x, y: y), radius: radius)
}
func groups(_ points: [MapScreenPoint]) -> [MapScreenCluster] { MapScreenClustering.groups(points) }
precondition(groups([]).isEmpty)
precondition(groups([point("a", 0, 0)]).first!.memberIDs == ["a"])
precondition(groups([point("a", 0, 0), point("b", 43, 0)]).count == 1, "Overlapping dots must merge")
precondition(groups([point("a", 0, 0), point("b", 44, 0)]).count == 2, "Touching dots have no overlap")
precondition(groups([point("a", 0, 0), point("b", 45, 0)]).count == 2, "Nearby non-overlapping dots must stay separate")
precondition(groups([point("a", 43, 43), point("b", 45, 45)]).count == 1, "Check across grid boundaries")
precondition(groups([point("a", -45, -45), point("b", -43, -43)]).count == 1, "Negative screen coordinates")
let chain = [point("c", 80, 0), point("b", 40, 0), point("a", 0, 0)]
let merged = groups(chain)
precondition(merged.count == 1 && merged[0].memberIDs == ["a", "b", "c"])
precondition(merged[0].center.x == 40 && merged[0].center.y == 0, "Merge moves to the centroid")
precondition(groups(Array(chain.reversed())) == merged, "Input order must not change identity")
precondition(groups([point("a", 0, 0, 0), point("b", 0, 0, 0)]).count == 2, "Detailed pins must remain individually selectable")
precondition(groups([point("a", .nan, 0), point("b", 0, .infinity)]).isEmpty)
let spread = (0..<2000).map { point("id-\($0)", Double($0 % 50) * 50, Double($0 / 50) * 50) }
precondition(groups(spread).count == 2000, "Large spread must retain every marker")
let crowded = (0..<300).map { point("id-\($0)", Double($0 % 10), Double($0 / 10)) }
let dense = groups(crowded)
precondition(dense.count == 1 && dense[0].memberIDs.count == 300, "Cluster count includes every item")
precondition(groups([point("a", 0, 0), point("b", 100, 0)]).count == 2, "Zooming back in splits a merged group")
let ring = (0..<8).map { index in
    let angle = Double(index) * .pi / 4
    return point("ring-\(index)", cos(angle) * 50, sin(angle) * 50)
}
let recentered = groups(ring + [point("center", 0, 0)])
precondition(recentered.count == 1 && recentered[0].memberIDs.count == 9, "Recheck overlaps created by the new cluster centroid")
let smallDots = [point("a", 0, 0, 10), point("b", 21, 0, 10)]
precondition(groups(smallDots).count == 2, "Distant zoom uses the smaller visible dot footprint")
func includes(_ layer: String, saves: Bool = true, pins: Bool = true, trips: Bool = true, category: Bool = true, trip: Bool = true) -> Bool {
    MapLayerVisibility.includes(layer: layer, showSaves: saves, showPins: pins, showTrips: trips, categoryIncluded: category, tripIncluded: trip)
}
precondition(includes("saved", pins: false, trips: false, category: false, trip: false), "Saves remain independent")
precondition(!includes("saved", saves: false))
precondition(!includes("pin", category: false))
precondition(!includes("pin", trip: false))
precondition(includes("trip", pins: false, category: false), "Pin categories must not hide trip places")
precondition(!includes("trip", trips: false) && !includes("trip", trip: false))
for offset in [CGPoint(x: 0.25, y: -0.5), CGPoint(x: 400, y: 300), CGPoint(x: -1200, y: -800)] {
    let panned = chain.map { MapScreenPoint(id: $0.id, point: CGPoint(x: $0.point.x + offset.x, y: $0.point.y + offset.y), radius: $0.radius) }
    precondition(groups(panned).map(\.memberIDs) == merged.map(\.memberIDs), "Panning must preserve cluster membership")
}
precondition(MapMarkerAppearance.at(span: 0.119) == .pill)
precondition(MapMarkerAppearance.at(span: 0.12) == .dot)
precondition(MapMarkerAppearance.at(span: 0.79) == .dot)
precondition(MapMarkerAppearance.at(span: 0.8) == .dot)
precondition(MapMarkerAppearance.at(span: 2.39) == .dot)
precondition(MapMarkerAppearance.at(span: 2.4) == .smallDot)
let terminalSize = MapMarkerAppearance.at(span: 2.4).dotDiameter
for span in [2.4, 8.0, 40.0, 150.0] {
    precondition(MapMarkerAppearance.at(span: span).dotDiameter == terminalSize, "Distant dots must not grow again")
    precondition(MapMarkerAppearance.at(span: span).clusterDiameter == 24, "Distant clusters keep a fixed count bubble")
}
precondition(terminalSize < MapMarkerAppearance.at(span: 0.12).dotDiameter)
precondition(MapClusterAnchor.center([]) == nil)
let anchor = MapClusterAnchor.center([.init(latitude: 10, longitude: 179), .init(latitude: 20, longitude: -179)])!
precondition(anchor.latitude == 15 && abs(anchor.longitude) == 180, "A date-line cluster must stay local")
let unchangedAnchor = MapClusterAnchor.center([.init(latitude: 10, longitude: 179), .init(latitude: 20, longitude: -179)])!
precondition(anchor.latitude == unchangedAnchor.latitude && anchor.longitude == unchangedAnchor.longitude, "Anchors depend on members, never pan pixels")
for height in [0.0, 160.0, 240.0, 400.0, 800.0] {
    let panel = MapSearchPanelLayout.height(available: height, barHeight: 60)
    precondition(panel == max(0, height - 78), "Results panel must leave an 18-point gap below the stationary search row")
}
precondition(MapSearchPanelLayout.offset(drag: 50) == 50)
precondition(MapSearchPanelLayout.offset(drag: -50) == 0, "Upward dragging must not overlap the search bar")
precondition(MapSearchPanelLayout.keyboardOverlap(panelBottom: 844, keyboardTop: nil, panelHeight: 700) == 0)
precondition(MapSearchPanelLayout.keyboardOverlap(panelBottom: 844, keyboardTop: 510, panelHeight: 700) == 334)
precondition(MapSearchPanelLayout.keyboardOverlap(panelBottom: 844, keyboardTop: 900, panelHeight: 700) == 0)
precondition(MapSearchPanelLayout.keyboardOverlap(panelBottom: 844, keyboardTop: 0, panelHeight: 700) == 700)
let stableSearchHeight = MapSearchPanelLayout.height(available: 800, barHeight: 60)
for drag in [0.0, 20, 90, 200, 500] {
    precondition(MapSearchPanelLayout.offset(drag: drag) == drag)
    precondition(MapSearchPanelLayout.height(available: 800, barHeight: 60) == stableSearchHeight, "Dragging translates the panel without reflowing results")
}
precondition(MapSearchPanelLayout.shouldDismiss(translation: 91, predicted: 91))
precondition(MapSearchPanelLayout.shouldDismiss(translation: 21, predicted: 151))
precondition(!MapSearchPanelLayout.shouldDismiss(translation: 20, predicted: 300))
precondition(!MapSearchPanelLayout.shouldDismiss(translation: 60, predicted: 100))
precondition(!MapSearchPanelLayout.shouldDismiss(translation: -100, predicted: -200))
precondition(MapCityLabelStyle.title(city: "Barcelona", countryCode: " es ") == "Barcelona, ES")
precondition(MapCityLabelStyle.title(city: "Barcelona", countryCode: nil) == "Barcelona")
precondition(MapCityLabelStyle.title(city: "Barcelona", countryCode: " ") == "Barcelona")
precondition(MapCityLabelStyle.title(city: "Barcelona, Spain", countryCode: "ES") == "Barcelona, ES", "Do not repeat the country name")
precondition(MapCityFlagStyle.code(" es ") == "ES")
precondition(MapCityFlagStyle.code("Spain") == nil)
precondition(MapCityFlagStyle.code("12") == nil)
precondition(MapCityFlagStyle.flag("ES") == "🇪🇸")
precondition(MapCityFlagStyle.flag("US") == "🇺🇸")
precondition(MapCityFlagStyle.flag("invalid") == "🌐")
precondition(MapCityFlagStyle.minimumSpan > 0.8, "Country grouping follows city dots")
var previousSize: CGFloat = 20
for span in [0.001, 0.12, 0.3, 0.8, 8, 40, 180] {
    let size = MapCityLabelStyle.size(span: span)
    precondition(size >= 11 && size <= 20, "City label must remain visible with a capped size")
    precondition(size <= previousSize, "City font size changes continuously as zoom decreases")
    previousSize = size
}
precondition(MapCityLabelStyle.size(span: 0.001) == 20)
precondition(MapCityLabelStyle.size(span: 180) == 11)
precondition(MapCityGrouping.sameCity("Barcelona, Spain", countryCode: nil, "Barcelona", countryCode: "es"), "Been shares canonical trip/pin/save city identity")
precondition(!MapCityGrouping.sameCity("Barcelona", countryCode: "ES", "Barcelona", countryCode: "VE"), "Been must not badge a foreign homonym")
let legacyCoordinate = Data(#"{"latitude":41.38,"longitude":2.17,"source":"apple","matchedAt":0}"#.utf8)
let decodedCoordinate = try JSONDecoder().decode(StoredPlaceCoordinate.self, from: legacyCoordinate)
precondition(decodedCoordinate.countryCode == nil, "Existing city caches must decode without country metadata")
var countryCoordinate = decodedCoordinate
countryCoordinate.countryCode = "ES"
let roundTrip = try JSONDecoder().decode(StoredPlaceCoordinate.self, from: JSONEncoder().encode(countryCoordinate))
precondition(roundTrip == countryCoordinate, "Cached country metadata must survive persistence")
precondition(MapCityGrouping.key("  BARCELÓNA  ") == MapCityGrouping.key("Barcelona"))
let mixedItems: [(id: String, layer: String, tripID: String?)] = [
    ("city-trip-1", "city", "trip-1"), ("place-1", "trip", "trip-1"), ("place-2", "trip", "trip-1"),
    ("city-trip-2", "city", "trip-2"), ("save-1", "saved", nil), ("save-2", "saved", nil), ("pin-1", "pin", "trip-1")
]
precondition(MapCityGrouping.count(layer: .trips, items: mixedItems) == 2, "Count trips once, not once per research place")
precondition(MapCityGrouping.count(layer: .saves, items: mixedItems) == 2)
precondition(MapCityGrouping.count(layer: .pins, items: mixedItems) == 1)
precondition(MapMarkerLayer.allCases.reduce(0) { $0 + MapCityGrouping.count(layer: $1, items: mixedItems) } == 5, "Combined pin count includes distinct trips plus saves and pins")
let cityGroup = [MapScreenCluster(memberIDs: ["city-anchor:barcelona", "save-1", "pin-1", "foreign-pin"], center: CGPoint(x: 0, y: 0))]
let attached = MapCityGrouping.attachedIDs(city: "Barcelona", anchorID: "city-anchor:barcelona", groups: cityGroup,
    cities: ["save-1": "Barcelona", "pin-1": "BARCELONA", "foreign-pin": "Rome"])
precondition(attached == Set(["save-1", "pin-1"]), "Attach only the city's own items")
precondition(MapCityGrouping.attachedIDs(city: "Rome", anchorID: "city-anchor:rome", groups: cityGroup, cities: [:]).isEmpty)
let tripID = UUID()
let tripFilter = MapLibraryFilter(cities: ["Barcelona"], layer: .trips, memberIDs: ["trip-city"], tripIDs: [tripID])
precondition(tripFilter.matchesTrip(id: tripID, city: "BARCELONA"))
precondition(!tripFilter.matchesTrip(id: tripID, city: "Rome"))
precondition(!tripFilter.matchesTrip(id: UUID(), city: "Barcelona"))
let pinFilter = MapLibraryFilter(cities: ["Barcelona"], layer: .pins, memberIDs: ["trip-pin:1:p"], tripIDs: [tripID])
precondition(pinFilter.matchesMember(id: "trip-pin:1:p", city: "Barcelona"))
precondition(!pinFilter.matchesMember(id: "p", city: "Barcelona"), "Pins and personal saves must not share a filter identity")
precondition(!pinFilter.matchesMember(id: "trip-pin:1:p", city: "Rome"))

func marker(_ id: String, city: String, layer: String, latitude: Double, longitude: Double) -> WorkspaceMapPin {
    WorkspaceMapPin(id: id, city: city, name: city, layer: layer, coordinate: .init(latitude: latitude, longitude: longitude))
}
let cityRecords = [
    marker("trip-bcn", city: "Barcelona, Spain", layer: "city", latitude: 41.38, longitude: 2.17),
    marker("trip-mad", city: "Madrid", layer: "city", latitude: 40.42, longitude: -3.7),
    marker("save-bcn", city: "Barcelona", layer: "saved", latitude: 41.39, longitude: 2.18),
    marker("pin-mad", city: "Madrid", layer: "pin", latitude: 40.43, longitude: -3.71),
    marker("trip-rome", city: "Rome", layer: "city", latitude: 41.9, longitude: 12.5),
    marker("unlocated-country", city: "Unknown", layer: "saved", latitude: 20, longitude: 30)
]
let cityTestAnchors = [
    MapCityAnchor(id: "city-bcn", city: "Barcelona, Spain", coordinate: .init(latitude: 41.38, longitude: 2.17), countryCode: "ES"),
    MapCityAnchor(id: "city-mad", city: "Madrid", coordinate: .init(latitude: 40.42, longitude: -3.7), countryCode: "ES"),
    MapCityAnchor(id: "city-rome", city: "Rome", coordinate: .init(latitude: 41.9, longitude: 12.5), countryCode: "IT")
]
var renderer = MapRenderChecks(mapMarkers: cityRecords, cityAnchors: cityTestAnchors, markerGroups: [],
    visibleRegion: .init(span: .init(latitudeDelta: 0.07)))
precondition(renderer.renderedMarkers.filter(\.isCompactCity).isEmpty)
let closeBarcelona = renderer.renderedMarkers.first { $0.id == "city-bcn" }!
precondition(closeBarcelona.coordinate.latitude == 41.38 && closeBarcelona.coordinate.longitude == 2.17)
precondition(closeBarcelona.members.map(\.id) == ["trip-bcn"], "Unmerged saves stay individual at close zoom")
renderer.visibleRegion = .init(span: .init(latitudeDelta: 8))
precondition(renderer.renderedMarkers.filter(\.isCompactCity).isEmpty, "Detailed city state persists until continental zoom")
renderer.visibleRegion = .init(span: .init(latitudeDelta: 16))
precondition(renderer.renderedMarkers.filter(\.isCompactCity).count == 3, "Nonoverlapping cities in one country retain separate flag pins")
renderer.markerGroups = [.init(memberIDs: ["city-bcn", "city-mad"], center: .init(x: 0, y: 0))]
let cityFlagMarkers = renderer.renderedMarkers
precondition(cityFlagMarkers.filter(\.isCompactCity).count == 3, "Each city keeps its own flag; there is no second country grouping")
let barcelona = cityFlagMarkers.first { MapCityGrouping.key($0.city) == "barcelona" }!
precondition(barcelona.isCompactCity)
precondition(Set(barcelona.members.map(\.id)) == Set(["trip-bcn", "save-bcn"]), "Barcelona and Barcelona, Spain share one city flag")
let madrid = cityFlagMarkers.first { MapCityGrouping.key($0.city) == "madrid" }!
precondition(Set(madrid.members.map(\.id)) == Set(["trip-mad", "pin-mad"]))
let allIDs = cityFlagMarkers.flatMap { $0.members.map(\.id) }
precondition(allIDs.count == cityRecords.count && Set(allIDs).count == allIDs.count, "City merging neither loses nor duplicates records")
renderer.markerGroups = [.init(memberIDs: cityTestAnchors.map(\.id) + cityRecords.map(\.id), center: .init(x: 999, y: -999))]
renderer.visibleRegion = .init(span: .init(latitudeDelta: 160))
let distantBarcelona = renderer.renderedMarkers.first { MapCityGrouping.key($0.city) == "barcelona" }!
precondition(barcelona.coordinate.latitude == distantBarcelona.coordinate.latitude && barcelona.coordinate.longitude == distantBarcelona.coordinate.longitude,
    "A city flag stays at its city even when projected clusters overlap")
renderer.mapMarkers = cityRecords.filter { $0.layer != "saved" }
let withoutSaves = renderer.renderedMarkers.first { MapCityGrouping.key($0.city) == "barcelona" }!
precondition(withoutSaves.members.map(\.id) == ["trip-bcn"], "Filtered saves are omitted from the flag contents")
renderer.mapMarkers = cityRecords.filter { $0.layer != "city" }
precondition(renderer.renderedMarkers.first { MapCityGrouping.key($0.city) == "barcelona" }!.members.map(\.id) == ["save-bcn"],
    "A city's saves remain when Trips is disabled")
renderer.mapMarkers = cityRecords.filter { $0.layer != "pin" }
precondition(renderer.renderedMarkers.first { MapCityGrouping.key($0.city) == "madrid" }!.members.map(\.id) == ["trip-mad"],
    "Pins filter removes pin members without changing the city anchor")
renderer.mapMarkers = cityRecords
renderer.markerGroups = []
renderer.visibleRegion = .init(span: .init(latitudeDelta: 0.7))
precondition(!renderer.renderedMarkers.contains(where: \.isCompactCity), "Zooming back in restores detailed city anchors")
precondition(MapCityGrouping.key("Barcelona Spain") == MapCityGrouping.key("Barcelona, Spain"))
precondition(MapCityGrouping.name("Barcelona, Spain") == "Barcelona")
precondition(MapCityGrouping.countryCode(in: "Barcelona Spain") == "ES")
precondition(pinFilter.matchesMember(id: "trip-pin:1:p", city: "Barcelona, Spain"), "Library city filters share the same canonical identity")

let duplicateCoordinate = CLLocationCoordinate2D(latitude: 41.38, longitude: 2.17)
let duplicateRecords = [
    WorkspaceMapPin(id: "saved-copy", city: "Barcelona", name: "Coffee", layer: "saved", coordinate: duplicateCoordinate, placeID: "same-place"),
    WorkspaceMapPin(id: "pinned-copy", city: "Barcelona", name: "Coffee", layer: "pin", coordinate: duplicateCoordinate, placeID: "same-place")
]
var duplicateRenderer = MapRenderChecks(mapMarkers: duplicateRecords, cityAnchors: [], markerGroups: [], visibleRegion: nil)
precondition(duplicateRenderer.renderedMarkers.count == 1 && duplicateRenderer.renderedMarkers[0].id == "pinned-copy")
precondition(Set(duplicateRenderer.renderedMarkers[0].members.map(\.id)) == Set(duplicateRecords.map(\.id)))
duplicateRenderer.markerGroups = [.init(memberIDs: ["pinned-copy"], center: .init(x: 999, y: -999))]
precondition(duplicateRenderer.renderedMarkers.count == 1 && duplicateRenderer.renderedMarkers[0].coordinate.latitude == duplicateCoordinate.latitude,
    "Cluster screen coordinates never move a single physical location")

let onePinRevision = duplicateRenderer.renderedMarkers[0].contentRevision
let secondPin = WorkspaceMapPin(id: "second-pin", city: "Barcelona", name: "Museum", layer: "pin", coordinate: duplicateCoordinate)
duplicateRenderer.mapMarkers.append(secondPin)
duplicateRenderer.markerGroups = [.init(memberIDs: ["pinned-copy", "second-pin"], center: .init(x: 0, y: 0))]
let twoPinMarker = duplicateRenderer.renderedMarkers[0]
precondition(twoPinMarker.contentRevision != onePinRevision, "Merged annotation content must refresh when membership grows")
precondition(MapPlaceIdentity.groups(twoPinMarker.members.map {
    .init(id: $0.id, placeID: $0.placeID, googleID: $0.googlePlaceID, name: $0.name, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, layer: $0.layer)
}).filter { $0.first != "saved-copy" }.count == 2, "The merged pin count includes both distinct pinned places")

let pinRect = CGRect(x: 7, y: 13, width: 160, height: 44)
let pinPath = CityNameMapPinShape().path(in: pinRect)
var vertices: [CGPoint] = []
var closedContours = 0
pinPath.cgPath.applyWithBlock { element in
    if element.pointee.type == .addLineToPoint { vertices.append(element.pointee.points[0]) }
    if element.pointee.type == .closeSubpath { closedContours += 1 }
}
precondition(closedContours == 1, "The glass pin has one contour without seams or intersecting lobes")
precondition(vertices.contains(CGPoint(x: pinRect.midX, y: pinRect.maxY)), "The geographic tip stays at bottom center")
precondition(vertices.contains(CGPoint(x: pinRect.midX - 7, y: pinRect.maxY - 9)) && vertices.contains(CGPoint(x: pinRect.midX + 7, y: pinRect.maxY - 9)), "The short pointer is symmetric")
precondition(pinPath.boundingRect == pinRect, "The city pin does not exceed its intrinsic name/count footprint")

print("PASS: clustering, pan stability, city attachments, separate layer counts, fixed dots, outlined city-label sizing, cache compatibility, city alias/filter/flag stability, symmetric pin geometry and docked-search drag sizing")
'''

def main():
    source = SOURCE.read_text()
    start = source.index('private enum MapPlaceIdentity')
    end = source.index('private enum AppleMapPlaceCategory', start)
    model = source[start:end]
    # UI/library records depend on MapKit and PersonalPlace; the tested algorithms do not.
    record_start = model.index('private struct MapLibraryPin')
    record_end = model.index('private enum MapCityLabelStyle', record_start)
    model = (model[:record_start] + model[record_end:]).replace('private struct ', 'struct ').replace('private enum ', 'enum ')
    coordinate_start = source.index('private struct StoredPlaceCoordinate:')
    coordinate_end = source.index('\n@MainActor', coordinate_start)
    coordinate = source[coordinate_start:coordinate_end]
    coordinate = '\n'.join(line for line in coordinate.splitlines() if 'var coordinate: CLLocationCoordinate2D' not in line)
    coordinate = coordinate.replace('private struct ', 'struct ')
    rendered_start = source.index('private struct MapRenderedMarker:')
    rendered_end = source.index('struct MapCityLabel:', rendered_start)
    rendered = source[rendered_start:rendered_end].replace('private struct ', 'struct ')
    anchor_start = source.index('private struct MapCityAnchor:')
    anchor_end = source.index('private enum MapCityLabelStyle', anchor_start)
    anchor_record = source[anchor_start:anchor_end].replace('private struct ', 'struct ')
    getter_start = source.index('    private var renderedMarkers:')
    getter_end = source.index('    private func refreshMarkerGroups', getter_start)
    getter = source[getter_start:getter_end].replace('private var renderedMarkers: [MapRenderedMarker] { cachedRenderedMarkers }', 'var renderedMarkers: [MapRenderedMarker] { makeRenderedMarkers() }')
    helper_start = source.index('    private func physicalPlaceGroups(')
    helper_end = source.index('    private var visiblePins:', helper_start)
    helper = source[helper_start:helper_end]
    # Minimal MapKit/data input adapters; execute the app's actual rendering getter.
    adapters = r'''
struct CLLocationCoordinate2D { let latitude: Double; let longitude: Double }
struct WorkspaceMapPin { let id: String; let city: String; let name: String; let layer: String; let coordinate: CLLocationCoordinate2D; var placeID: String? = nil; var googlePlaceID: String? = nil }
struct TestSpan { let latitudeDelta: Double }
struct TestRegion { let span: TestSpan }
struct MapRenderChecks {
    var mapMarkers: [WorkspaceMapPin]
    var cityAnchors: [MapCityAnchor]
    var markerGroups: [MapScreenCluster]
    var visibleRegion: TestRegion?
    var visiblePins: [WorkspaceMapPin] { mapMarkers.filter { $0.layer != "city" } }
''' + helper + getter + '\n}\n'
    shape_start = source.index('private struct CityNameMapPinShape:')
    shape_end = source.index('private struct CityNameMapPinGlass:', shape_start)
    shape = source[shape_start:shape_end].replace('private struct ', 'struct ')
    with tempfile.TemporaryDirectory(prefix='trippy-map-tests-', dir='/tmp') as folder:
        folder = Path(folder)
        swift = folder / 'MapChecks.swift'
        swift.write_text('import Foundation\nimport SwiftUI\n' + coordinate + '\n' + model + rendered + anchor_record + adapters + shape + CHECKS)
        binary = folder / 'map-checks'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(PROJECT / '.local/library-design/modules'), str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

if __name__ == '__main__':
    main()
