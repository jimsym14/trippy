import SwiftUI
import MapKit

struct BeenCameraRequest: Equatable {
    let id = UUID()
    var latitude: Double = 25
    var longitude: Double = 15
    var distance: Double = 78_000_000
}
struct BeenNativeBoundaryLayer {
    let polygons: [MKPolygon]
    let outlines: [MKPolyline]
    init(_ geometry: BeenBoundaryGeometry) {
        polygons = geometry.fills.map { line in
            var coordinates = line.points.map(\.coordinate)
            return MKPolygon(coordinates: &coordinates, count: coordinates.count)
        }
        outlines = geometry.outlines.map { line in
            var coordinates = line.points.map(\.coordinate)
            return MKPolyline(coordinates: &coordinates, count: coordinates.count)
        }
    }
}

// MapKit owns cluster creation, collision detection, and split/merge animations.
// Annotation views use lightweight UIKit drawing, rather than one glass host per city.
struct BeenGlobeMap: UIViewRepresentable {
    let visits: [VisitedPlace]
    let dataRevision: UUID
    let shapes: CountryShapesOverlay?
    let camera: BeenCameraRequest
    let showCities: Bool
    let imagery: Bool
    let globe3D: Bool
    let dark: Bool
    let reduceMotion: Bool
    let onVisit: (VisitedPlace) -> Void
    let onCluster: ([VisitedPlace]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = BeenNativeMapView()
        map.onFirstLayout = { [weak coordinator = context.coordinator, weak map] in
            guard let map else { return }; coordinator?.applyInitialCamera(to: map)
        }
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.cameraZoomRange = .init(minCenterCoordinateDistance: 20_000, maxCenterCoordinateDistance: 120_000_000)
        map.register(BeenMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "been-city")
        map.register(BeenMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "been-cluster")
        map.layoutMargins = UIEdgeInsets(top: 105, left: 12, bottom: 145, right: 12)
        context.coordinator.apply(self, to: map)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.apply(self, to: map) }
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: BeenGlobeMap
        private var visitRevision: UUID?
        private var lastCamera: UUID?
        private var markerStyleKey = ""
        private var styleKey = ""
        private weak var shownShapes: CountryShapesOverlay?
        private var compact = true
        init(_ parent: BeenGlobeMap) { self.parent = parent }
        func apply(_ next: BeenGlobeMap, to map: MKMapView) {
            parent = next
            let style = "\(next.imagery):\(next.dark):\(next.globe3D)"
            if style != styleKey {
                styleKey = style
                map.overrideUserInterfaceStyle = next.dark ? .dark : .light
                if next.imagery {
                    let configuration = MKHybridMapConfiguration(elevationStyle: next.globe3D ? .realistic : .flat)
                    configuration.pointOfInterestFilter = .excludingAll
                    map.preferredConfiguration = configuration
                } else {
                    let configuration = MKStandardMapConfiguration(elevationStyle: next.globe3D ? .realistic : .flat, emphasisStyle: .muted)
                    configuration.pointOfInterestFilter = .excludingAll
                    map.preferredConfiguration = configuration
                }
            }
            if next.dataRevision != visitRevision {
                visitRevision = next.dataRevision
                let existing = map.annotations.compactMap { $0 as? BeenVisitAnnotation }
                let wanted = Set(next.visits.map(\.id))
                map.removeAnnotations(existing.filter { !wanted.contains($0.visit.id) })
                let retained = Dictionary(uniqueKeysWithValues: map.annotations.compactMap { $0 as? BeenVisitAnnotation }.map { ($0.visit.id, $0) })
                for visit in next.visits {
                    if let old = retained[visit.id] {
                        if old.visit.latitude != visit.latitude || old.visit.longitude != visit.longitude {
                            map.removeAnnotation(old); map.addAnnotation(BeenVisitAnnotation(visit))
                        } else { old.visit = visit }
                    } else { map.addAnnotation(BeenVisitAnnotation(visit)) }
                }
            }
            if next.shapes !== shownShapes {
                // Add the new layer before removing the old one, so nothing flashes.
                let old = map.overlays.filter { $0 is CountryShapesOverlay }
                if let shapes = next.shapes { map.addOverlay(shapes, level: .aboveRoads) }
                map.removeOverlays(old.filter { $0 !== next.shapes })
                shownShapes = next.shapes
            }
            updateMarkerStyle(on: map)
            if !map.bounds.isEmpty && lastCamera != next.camera.id {
                let initial = lastCamera == nil
                lastCamera = next.camera.id
                map.setCamera(.init(lookingAtCenter: .init(latitude: next.camera.latitude, longitude: next.camera.longitude), fromDistance: next.camera.distance, pitch: next.globe3D ? 12 : 0, heading: 0), animated: !initial && !next.reduceMotion)
            }
        }
        func applyInitialCamera(to map: MKMapView) {
            if lastCamera == nil && !map.bounds.isEmpty { apply(parent, to: map) }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is BeenVisitAnnotation || annotation is MKClusterAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: annotation is MKClusterAnnotation ? "been-cluster" : "been-city", for: annotation) as! BeenMarkerAnnotationView
            view.clusteringIdentifier = annotation is BeenVisitAnnotation ? "been-visits" : nil
            view.displayPriority = .defaultHigh
            view.collisionMode = .rectangle
            view.canShowCallout = false
            view.configure(compact: compact || !parent.showCities, dark: parent.dark)
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            if let cluster = annotation as? MKClusterAnnotation {
                TrippyHaptics.selection()
                let members = cluster.memberAnnotations.compactMap { $0 as? BeenVisitAnnotation }
                if mapView.camera.centerCoordinateDistance < 35_000 {
                    parent.onCluster(members.map(\.visit))
                } else if members.count > 1 {
                    mapView.showAnnotations(members, animated: !parent.reduceMotion)
                }
            } else if let city = annotation as? BeenVisitAnnotation { TrippyHaptics.selection(); parent.onVisit(city.visit) }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            compact = mapView.region.span.latitudeDelta >= 12
            updateMarkerStyle(on: mapView)
        }
        private func updateMarkerStyle(on map: MKMapView) {
            let key = "\(compact):\(parent.showCities):\(parent.dark)"
            guard key != markerStyleKey else { return }; markerStyleKey = key
            for annotation in map.annotations {
                (map.view(for: annotation) as? BeenMarkerAnnotationView)?.configure(compact: compact || !parent.showCities, dark: parent.dark)
            }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let shapes = overlay as? CountryShapesOverlay { return CountryShapesRenderer(shapes: shapes) }
            let amber = UIColor(red: 0.94, green: 0.66, blue: 0.24, alpha: 1)
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon); renderer.fillColor = amber.withAlphaComponent(parent.dark ? 0.43 : 0.35); return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay); renderer.strokeColor = amber.withAlphaComponent(0.8); renderer.lineWidth = 0.8; renderer.lineJoin = .round; return renderer
        }
    }
}
final class BeenVisitAnnotation: NSObject, MKAnnotation {
    var visit: VisitedPlace
    var coordinate: CLLocationCoordinate2D { visit.coordinate }
    var title: String? { visit.name }
    init(_ visit: VisitedPlace) { self.visit = visit }
}
final class BeenMarkerAnnotationView: MKAnnotationView {
    private let label = UILabel()
    private let bubble = UIView()
    private let dot = UIView()
    private var signature = ""
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(bubble); bubble.addSubview(label); addSubview(dot)
        label.textAlignment = .center
        label.numberOfLines = 1
        bubble.layer.borderWidth = 0.8
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.16
        bubble.layer.shadowRadius = 2
        bubble.layer.shadowOffset = .init(width: 0, height: 1)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); signature = "" }
    func configure(compact: Bool, dark: Bool) {
        let cluster = annotation as? MKClusterAnnotation
        let city = annotation as? BeenVisitAnnotation
        let count = cluster?.memberAnnotations.count ?? 1
        let isBlob = compact || cluster != nil
        let text = isBlob ? count.formatted() : (city?.visit.name ?? "")
        let key = "\(text):\(isBlob):\(dark)"
        guard signature != key else { return }; signature = key
        let amber = UIColor(red: 0.94, green: 0.66, blue: 0.24, alpha: 1)
        label.text = text
        label.font = UIFont(name: "PlusJakartaSans-Bold", size: isBlob ? 12 : 10) ?? .systemFont(ofSize: isBlob ? 12 : 10, weight: .semibold)
        label.textColor = UIColor(red: 0.2, green: 0.15, blue: 0.07, alpha: 1)
        let width = isBlob ? max(29, label.intrinsicContentSize.width + 16) : min(230, label.intrinsicContentSize.width + 20)
        let height: CGFloat = isBlob ? 29 : 25
        frame = CGRect(x: 0, y: 0, width: width, height: isBlob ? height : height + 9)
        bubble.frame = .init(x: 0, y: 0, width: width, height: height)
        bubble.backgroundColor = amber
        bubble.layer.cornerRadius = height / 2
        bubble.layer.borderColor = UIColor.white.withAlphaComponent(dark ? 0.55 : 0.85).cgColor
        bubble.layer.shadowPath = UIBezierPath(roundedRect: bubble.bounds, cornerRadius: height / 2).cgPath
        label.frame = bubble.bounds.insetBy(dx: 6, dy: 0)
        dot.isHidden = isBlob
        dot.frame = .init(x: width / 2 - 2.5, y: height + 4, width: 5, height: 5)
        dot.backgroundColor = amber; dot.layer.cornerRadius = 2.5; dot.layer.borderWidth = 0.7; dot.layer.borderColor = UIColor.white.cgColor
        centerOffset = isBlob ? .zero : .init(x: 0, y: -frame.height / 2)
        accessibilityLabel = cluster != nil ? "\(count) cities. Tap to expand." : "\(city?.visit.name ?? ""), visited"
    }
}

final class BeenNativeMapView: MKMapView {
    var onFirstLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        if !bounds.isEmpty { onFirstLayout?(); onFirstLayout = nil }
    }
}

// General-map cities share Been to's native collision and split/merge pipeline.
// These are source snapshots: camera gestures never rebuild their memberships.
struct GeneralMapMarker: Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let city: String
    var name: String = ""
    let countryCode: String?
    let visited: Bool
    let isCity: Bool
    let symbol: String
    let emoji: String?
    let baseMemberIDs: [String]
    let placeMemberIDs: [String]
    let tripIDs: Set<String>
    let pinIDs: Set<String>
    let saveIDs: Set<String>
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    func members(local: Bool) -> [String] { baseMemberIDs + (isCity && local ? [] : placeMemberIDs) }
}
struct GeneralMapMarkerPresentation {
    let cityCount: Int
    let trips: Int
    let pins: Int
    let saves: Int
    let visited: Bool
    let isPoint: Bool
    init(_ markers: [GeneralMapMarker], local: Bool, showVisitedBadges: Bool = true) {
        cityCount = Set(markers.map { $0.city.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) + ":" + ($0.countryCode ?? "").uppercased() }).count
        trips = Set(markers.flatMap { $0.tripIDs }).count
        pins = Set(markers.flatMap { $0.isCity && local ? [] : Array($0.pinIDs) }).count
        saves = Set(markers.flatMap { $0.isCity && local ? [] : Array($0.saveIDs) }).count
        let cityMarkers = markers.filter(\.isCity)
        visited = showVisitedBadges && !cityMarkers.isEmpty && cityMarkers.allSatisfy(\.visited)
        isPoint = markers.count == 1 && markers[0].isCity == false
    }
}
#if DEBUG
// Opt-in, process-local UI fixture. It never writes visits, pins or trips to storage.
enum GeneralMapDebugFixture {
    static let markers: [GeneralMapMarker]? = {
        guard ProcessInfo.processInfo.environment["TRIPPY_GENERAL_MAP_FIXTURE"] == "1" else { return nil }
        let cities: [(String, String, Double, Double)] = [
            ("Barcelona","ES",41.38,2.17),("Madrid","ES",40.42,-3.7),("Valencia","ES",39.47,-0.37),
            ("London","GB",51.5,-0.12),("Paris","FR",48.86,2.35),("Lyon","FR",45.76,4.83),
            ("Rome","IT",41.90,12.5),("Milan","IT",45.46,9.19),("Athens","GR",37.98,23.73),
            ("Thessaloniki","GR",40.63,22.94),("Berlin","DE",52.52,13.4),("Munich","DE",48.14,11.58),
            ("Lisbon","PT",38.72,-9.14),("Porto","PT",41.16,-8.63),("Amsterdam","NL",52.37,4.9),
            ("Vienna","AT",48.21,16.37),("Prague","CZ",50.08,14.44),("Copenhagen","DK",55.68,12.57),
            ("Oslo","NO",59.91,10.75),("Stockholm","SE",59.33,18.07)]
        return cities.enumerated().map { index, city in
            GeneralMapMarker(id: "fixture:" + city.0, latitude: city.2, longitude: city.3, city: city.0,
                countryCode: city.1, visited: true, isCity: true, symbol: "airplane", emoji: nil,
                baseMemberIDs: [], placeMemberIDs: [], tripIDs: index == 0 ? ["trip-1"] : [],
                pinIDs: index == 0 ? ["pin-1", "pin-2"] : [], saveIDs: index == 0 ? ["save-1"] : [])
        }
    }()
}
#else
enum GeneralMapDebugFixture { static let markers: [GeneralMapMarker]? = nil }
#endif

final class GeneralMapAnnotation: NSObject, MKAnnotation {
    var marker: GeneralMapMarker
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { marker.city }
    init(_ marker: GeneralMapMarker) { self.marker = marker; coordinate = marker.coordinate }
}
final class GeneralMapController {
    weak var map: MKMapView?
    func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint? { map.map { $0.convert(coordinate, toPointTo: $0) } }
}
struct GeneralMapOverlay {
    enum Kind: Hashable { case countryFill, countryOutline, cityFill, cityOutline, hatch, focusFill, focusOutline, extent, route }
    let overlay: MKOverlay
    let kind: Kind
    static func prepare(_ geometry: BeenBoundaryGeometry, city: Bool, detail: BeenBoundaryDetail) -> [Self] {
        let budget: Int = city ? 112 : (detail == .local ? 176 : detail == .regional ? 72 : 28)
        func coordinates(_ line: GeoBoundaryLine) -> [CLLocationCoordinate2D] {
            let points = line.points.count > budget
                ? GeoBoundaryRepository.simplify(line.points, maximumPoints: budget)
                : line.points
            return points.map(\.coordinate)
        }
        let fills = geometry.fills.compactMap { line -> MKPolygon? in
            var points = coordinates(line)
            guard points.count >= 4 else { return nil }
            return MKPolygon(coordinates: &points, count: points.count)
        }
        let outlines = geometry.outlines.compactMap { line -> MKPolyline? in
            var points = coordinates(line)
            guard points.count >= 2 else { return nil }
            return MKPolyline(coordinates: &points, count: points.count)
        }
        let textures = geometry.textures.compactMap { line -> MKPolyline? in
            var points = coordinates(line)
            guard points.count >= 2 else { return nil }
            return MKPolyline(coordinates: &points, count: points.count)
        }
        var result: [Self] = []
        if !fills.isEmpty { result.append(.init(overlay: MKMultiPolygon(fills), kind: city ? .cityFill : .countryFill)) }
        if !outlines.isEmpty { result.append(.init(overlay: MKMultiPolyline(outlines), kind: city ? .cityOutline : .countryOutline)) }
        if !textures.isEmpty { result.append(.init(overlay: MKMultiPolyline(textures), kind: .hatch)) }
        return result
    }
}
struct GeneralNativeMap: UIViewRepresentable {
    let controller: GeneralMapController
    let markers: [GeneralMapMarker]
    let markerRevision: Int
    let position: MapCameraPosition
    let cameraRequestID: UUID
    let countryShapes: CountryShapesOverlay?
    let cityLayers: [BeenBoundaryDetail: [GeneralMapOverlay]]
    let geometryRevision: Int
    let showVisited: Bool
    let outlines: Bool
    let fill: Bool
    let hatches: Bool
    let detailed: Bool
    let innerCities: Bool
    let showVisitedBadges: Bool
    let showVisitedCityLabels: Bool
    let focusLines: [GeoBoundaryLine]
    let extents: [[CLLocationCoordinate2D]]
    let directions: MKPolyline?
    let extraOverlayKey: String
    let theme: String
    let poiFilter: MKPointOfInterestFilter
    let configurationKey: String
    let traffic: Bool
    let elevation: Bool
    let nativeCards: Bool
    let showLocation: Bool
    let showScale: Bool
    let dark: Bool
    let reduceMotion: Bool
    var onFirstRender: (() -> Void)? = nil
    let onSelection: ([String], Bool) -> Void
    let onApplePlace: (MKMapItem, Bool) -> Void
    let onCameraEnd: (MKCoordinateRegion, MapCamera) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = BeenNativeMapView()
        controller.map = map
        map.delegate = context.coordinator
        map.showsCompass = false
        map.register(GeneralMapMarkerView.self, forAnnotationViewWithReuseIdentifier: "general-city")
        map.register(GeneralMapMarkerView.self, forAnnotationViewWithReuseIdentifier: "general-cluster")
        map.register(VisitedStarView.self, forAnnotationViewWithReuseIdentifier: VisitedStarView.reuse)
        map.layoutMargins = .init(top: 160, left: 16, bottom: 155, right: 16)
        map.onFirstLayout = { [weak map, weak coordinator = context.coordinator] in
            guard let map else { return }; coordinator?.applyCamera(to: map)
        }
        context.coordinator.apply(self, to: map)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.apply(self, to: map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil }
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: GeneralNativeMap
        private var markerRevision: Int?
        private var annotations: [String: GeneralMapAnnotation] = [:]
        private var cameraRequest: UUID?
        private var configuration = ""
        private var overlayKinds: [ObjectIdentifier: GeneralMapOverlay.Kind] = [:]
        private var boundaryOverlays: [MKOverlay] = []
        private var supplementalOverlays: [MKOverlay] = []
        private var boundaryKey = ""
        private weak var shownShapes: CountryShapesOverlay?
        private var supplementalKey = ""
        private var local = false
        private var styleKey = ""
        private var farVisitedMode: Bool?
        private var visitedCityLabelMode: Bool?
        private var didReportFirstRender = false
        private var placeRequest: MKMapItemRequest?
        private var regionSpan: Double = 9
        init(_ parent: GeneralNativeMap) { self.parent = parent }
        func apply(_ next: GeneralNativeMap, to map: MKMapView) {
            parent = next
            if configuration != next.configurationKey {
                configuration = next.configurationKey
                map.overrideUserInterfaceStyle = next.dark ? .dark : .light
                let elevation: MKMapConfiguration.ElevationStyle = next.elevation ? .realistic : .flat
                if next.theme == "Satellite" { map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: elevation) }
                else if next.theme == "Hybrid" {
                    let style = MKHybridMapConfiguration(elevationStyle: elevation)
                    style.pointOfInterestFilter = next.poiFilter; style.showsTraffic = next.traffic
                    map.preferredConfiguration = style
                } else {
                    let style = MKStandardMapConfiguration(elevationStyle: elevation, emphasisStyle: next.theme == "Quiet" ? .muted : .default)
                    style.pointOfInterestFilter = next.poiFilter; style.showsTraffic = next.traffic
                    map.preferredConfiguration = style
                }
                map.selectableMapFeatures = next.nativeCards ? [.pointsOfInterest, .territories] : []
            }
            if map.showsUserLocation != next.showLocation { map.showsUserLocation = next.showLocation }
            map.showsScale = next.showScale
            if markerRevision != next.markerRevision {
                markerRevision = next.markerRevision
                let wanted = Set(next.markers.map(\.id))
                let removed = annotations.keys.filter { !wanted.contains($0) }
                map.removeAnnotations(removed.compactMap { annotations.removeValue(forKey: $0) })
                for marker in next.markers {
                    if let old = annotations[marker.id] {
                        guard old.marker != marker else { continue }
                        old.marker = marker
                        if old.coordinate.latitude != marker.latitude || old.coordinate.longitude != marker.longitude { old.coordinate = marker.coordinate }
                        (map.view(for: old) as? GeneralMapMarkerView)?.configure(
                            local: local, dark: next.dark, showVisitedBadges: next.showVisitedBadges,
                            showVisitedCityLabels: next.showVisitedCityLabels, span: regionSpan, reduceMotion: next.reduceMotion)
                    } else { annotations[marker.id] = GeneralMapAnnotation(marker) }
                }
                syncVisibility(on: map)
                styleKey = ""
                map.removeAnnotations(map.annotations.filter { $0 is VisitedStarAnnotation })
                if next.showVisitedCityLabels {
                    map.addAnnotations(next.markers.filter { $0.isCity && $0.visited && $0.tripIDs.isEmpty && $0.pinIDs.isEmpty && $0.saveIDs.isEmpty }.map { VisitedStarAnnotation(markerID: $0.id, coordinate: $0.coordinate) })
                }
            }
            updateStyle(on: map)
            updateOverlays(on: map)
            applyCamera(to: map)
        }
        func applyCamera(to map: MKMapView) {
            guard !map.bounds.isEmpty, cameraRequest != parent.cameraRequestID else { return }
            let initial = cameraRequest == nil
            cameraRequest = parent.cameraRequestID
            let animate = !initial && !parent.reduceMotion
            #if DEBUG
            let debugSpan = UserDefaults.standard.double(forKey: "TrippyMapSpan")
            if initial, debugSpan > 0 {
                map.setRegion(.init(center: .init(latitude: 42, longitude: 8), span: .init(latitudeDelta: debugSpan, longitudeDelta: debugSpan)), animated: false)
                return
            }
            if initial, GeneralMapDebugFixture.markers != nil {
                map.showAnnotations(Array(annotations.values), animated: false)
                return
            }
            #endif
            if let camera = parent.position.camera {
                map.setCamera(.init(lookingAtCenter: camera.centerCoordinate, fromDistance: camera.distance, pitch: camera.pitch, heading: camera.heading), animated: animate)
            } else if let region = parent.position.region { map.setRegion(region, animated: animate) }
            else if let rect = parent.position.rect { map.setVisibleMapRect(rect, edgePadding: map.layoutMargins, animated: animate) }
            else if !annotations.isEmpty { map.showAnnotations(Array(annotations.values), animated: animate) }
            else { map.setRegion(.init(center: .init(latitude: 40.6, longitude: 22.9), span: .init(latitudeDelta: 9, longitudeDelta: 9)), animated: false) }
        }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered, !didReportFirstRender else { return }
            didReportFirstRender = true
            parent.onFirstRender?()
        }
        private func syncVisibility(on map: MKMapView) {
            let far = parent.showVisitedCityLabels && regionSpan >= 18
            let wanted = annotations.values.filter { annotation in
                let m = annotation.marker
                guard m.isCity || local else { return false }
                // A visited city with nothing else saved is drawn by the star layer far out.
                if far && m.isCity && m.visited && m.tripIDs.isEmpty && m.pinIDs.isEmpty && m.saveIDs.isEmpty { return false }
                return true
            }
            let ids = Set(wanted.map { $0.marker.id })
            let existing = map.annotations.compactMap { $0 as? GeneralMapAnnotation }
            map.removeAnnotations(existing.filter { !ids.contains($0.marker.id) })
            let present = Set(existing.filter { ids.contains($0.marker.id) }.map { $0.marker.id })
            map.addAnnotations(wanted.filter { !present.contains($0.marker.id) })
        }
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is VisitedStarAnnotation {
                let view = map.dequeueReusableAnnotationView(withIdentifier: VisitedStarView.reuse, for: annotation) as! VisitedStarView
                view.setVisible(parent.showVisitedCityLabels && regionSpan >= 18, animated: false)
                return view
            }
            guard annotation is GeneralMapAnnotation || annotation is MKClusterAnnotation else { return nil }
            let view = map.dequeueReusableAnnotationView(withIdentifier: annotation is MKClusterAnnotation ? "general-cluster" : "general-city", for: annotation) as! GeneralMapMarkerView
            let marker = (annotation as? GeneralMapAnnotation)?.marker
            let farVisitedMarker = marker?.visited == true && parent.showVisitedCityLabels && map.region.span.latitudeDelta >= 18
            // Pins and saves never cluster into a city-looking label: they only
            // fold into the city marker once the map is zoomed out past `local`.
            view.clusteringIdentifier = farVisitedMarker || marker?.isCity != true ? nil : "general-cities"
            view.collisionMode = farVisitedMarker ? .none : .rectangle
            view.displayPriority = marker?.isCity == false ? .defaultLow : .defaultHigh
            view.applyZoomScale(Self.zoomScale(span: map.region.span.latitudeDelta))
            view.canShowCallout = false
            view.configure(local: local, dark: parent.dark, showVisitedBadges: parent.showVisitedBadges,
                           showVisitedCityLabels: parent.showVisitedCityLabels, span: map.region.span.latitudeDelta,
                           reduceMotion: parent.reduceMotion)
            return view
        }
        /// New label and cluster views fade in instead of popping.
        func mapView(_ map: MKMapView, didAdd views: [MKAnnotationView]) {
            guard !parent.reduceMotion else { return }
            for view in views where !(view is VisitedStarView) {
                view.alpha = 0
                UIView.animate(withDuration: 0.22, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) { view.alpha = 1 }
            }
        }
        func mapView(_ map: MKMapView, didSelect annotation: MKAnnotation) {
            if let star = annotation as? VisitedStarAnnotation {
                map.deselectAnnotation(star, animated: false)
                parent.onSelection([star.markerID], false)
                return
            }
            if let feature = annotation as? MKMapFeatureAnnotation {
                TrippyPerformance.mark("poi.selected")
                placeRequest?.cancel()
                let request = MKMapItemRequest(mapFeatureAnnotation: feature)
                placeRequest = request
                request.getMapItem { [weak self, weak map] item, error in
                    DispatchQueue.main.async {
                        guard let self, self.placeRequest === request else { return }
                        self.placeRequest = nil
                        let resolved = item ?? MKMapItem(placemark: MKPlacemark(coordinate: feature.coordinate))
                        if resolved.name == nil { resolved.name = feature.title ?? "Selected place" }
                        if error != nil { TrippyPerformance.mark("poi.lookup-fallback") }
                        self.parent.onApplePlace(resolved, feature.featureType == .territory)
                        map?.deselectAnnotation(feature, animated: false)
                    }
                }
                return
            }
            let items = GeneralMapMarkerView.items(annotation)
            guard !items.isEmpty else { return }
            map.deselectAnnotation(annotation, animated: false)
            let presentation = GeneralMapMarkerPresentation(items.map(\.marker), local: local, showVisitedBadges: parent.showVisitedBadges)
            if presentation.cityCount > 1, items.count > 1 { map.showAnnotations(items, animated: !parent.reduceMotion) }
            else { parent.onSelection(items.map { $0.marker.id }, local) }
        }
        /// Labels shrink smoothly as the map zooms far out, so they stop crowding the world view.
        static func zoomScale(span: Double) -> CGFloat {
            guard span > 4 else { return 1 }
            return max(0.66, 1 - CGFloat(log2(span / 4)) * 0.15)
        }
        private var appliedScale: CGFloat = 1
        func mapViewDidChangeVisibleRegion(_ map: MKMapView) {
            let scale = (Self.zoomScale(span: map.region.span.latitudeDelta) * 50).rounded() / 50
            guard scale != appliedScale else { return }
            appliedScale = scale
            for annotation in map.annotations where !(annotation is VisitedStarAnnotation) {
                (map.view(for: annotation) as? GeneralMapMarkerView)?.applyZoomScale(scale)
            }
        }
        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            regionSpan = map.region.span.latitudeDelta
            let nextLocal = map.region.span.latitudeDelta < 0.08
            if nextLocal != local { local = nextLocal; syncVisibility(on: map) }
            updateStyle(on: map)
            updateOverlays(on: map)
            let region = map.region
            let camera = MapCamera(centerCoordinate: map.camera.centerCoordinate, distance: map.camera.centerCoordinateDistance, heading: map.camera.heading, pitch: map.camera.pitch)
            // No SwiftUI mutation from updateUIView/delegate reentrancy.
            DispatchQueue.main.async { [weak self] in self?.parent.onCameraEnd(region, camera) }
        }
        private func updateStyle(on map: MKMapView) {
            let farVisitedMode = parent.showVisitedCityLabels && regionSpan >= 18
            let crossedFarThreshold = self.farVisitedMode.map { $0 != farVisitedMode } ?? false
            self.farVisitedMode = farVisitedMode
            if crossedFarThreshold {
                // Labels and stars cross-fade at the same threshold.
                for annotation in map.annotations where annotation is VisitedStarAnnotation {
                    (map.view(for: annotation) as? VisitedStarView)?.setVisible(farVisitedMode, animated: !parent.reduceMotion)
                }
                let leaving = map.annotations.compactMap { $0 as? GeneralMapAnnotation }.filter { a in
                    let m = a.marker
                    return farVisitedMode && m.isCity && m.visited && m.tripIDs.isEmpty && m.pinIDs.isEmpty && m.saveIDs.isEmpty
                }
                if leaving.isEmpty || parent.reduceMotion { syncVisibility(on: map) }
                else {
                    UIView.animate(withDuration: 0.2, animations: { leaving.forEach { map.view(for: $0)?.alpha = 0 } }) { _ in self.syncVisibility(on: map) }
                }
            }
            let key = "\(local):\(parent.dark):\(parent.markerRevision):\(parent.showVisitedBadges):\(farVisitedMode):\(parent.reduceMotion)"
            guard key != styleKey else { return }; styleKey = key
            for annotation in map.annotations {
                guard let view = map.view(for: annotation) as? GeneralMapMarkerView else { continue }
                let marker = (annotation as? GeneralMapAnnotation)?.marker
                let farVisitedMarker = marker?.visited == true && parent.showVisitedCityLabels && regionSpan >= 18
                view.clusteringIdentifier = farVisitedMarker || marker?.isCity != true ? nil : "general-cities"
                view.collisionMode = farVisitedMarker ? .none : .rectangle
                view.configure(
                    local: local, dark: parent.dark, showVisitedBadges: parent.showVisitedBadges,
                    showVisitedCityLabels: parent.showVisitedCityLabels, span: regionSpan, reduceMotion: parent.reduceMotion)
            }
        }
        private func updateOverlays(on map: MKMapView) {
            let span = map.region.span.latitudeDelta
            let detail = BeenBoundaryDetail.at(span: parent.detailed ? span / 2 : span)
            // Countries: one layer that resolves its own detail while zooming.
            let wantedShapes = parent.showVisited ? parent.countryShapes : nil
            if wantedShapes !== shownShapes {
                let old = map.overlays.filter { $0 is CountryShapesOverlay }
                if let wantedShapes { map.addOverlay(wantedShapes, level: .aboveRoads) }
                map.removeOverlays(old.filter { $0 !== wantedShapes })
                shownShapes = wantedShapes
            }
            // City boundaries only change near the threshold, never per zoom step.
            let nextBoundaryKey = "\(parent.geometryRevision):\(parent.showVisited):\(parent.outlines):\(parent.fill):\(parent.innerCities && span < 2):\(parent.dark)"
            _ = detail
            if nextBoundaryKey != boundaryKey {
                boundaryKey = nextBoundaryKey
                remove(overlays: boundaryOverlays, from: map)
                var layers: [GeneralMapOverlay] = []
                if parent.showVisited {
                    if parent.innerCities && span < 2 { layers += parent.cityLayers[.local] ?? [] }
                    layers = layers.filter {
                        switch $0.kind {
                        case .countryFill, .cityFill: parent.fill
                        case .countryOutline, .cityOutline: parent.outlines
                        case .hatch: parent.hatches
                        default: true
                        }
                    }
                }
                boundaryOverlays = layers.map(\.overlay)
                add(layers, to: map)
            }
            if parent.extraOverlayKey != supplementalKey {
                supplementalKey = parent.extraOverlayKey
                remove(overlays: supplementalOverlays, from: map)
                var layers: [GeneralMapOverlay] = []
                for line in parent.focusLines {
                    var points = line.points.map(\.coordinate)
                    if line.style == .fill, points.count >= 4 { layers.append(.init(overlay: MKPolygon(coordinates: &points, count: points.count), kind: .focusFill)) }
                    else if points.count >= 2 { layers.append(.init(overlay: MKPolyline(coordinates: &points, count: points.count), kind: line.style == .texture ? .hatch : .focusOutline)) }
                }
                for extent in parent.extents where extent.count >= 4 {
                    var points = extent
                    layers.append(.init(overlay: MKPolygon(coordinates: &points, count: points.count), kind: .extent))
                }
                if let route = parent.directions { layers.append(.init(overlay: route, kind: .route)) }
                supplementalOverlays = layers.map(\.overlay)
                add(layers, to: map)
            }
        }
        private func remove(overlays: [MKOverlay], from map: MKMapView) {
            guard !overlays.isEmpty else { return }
            map.removeOverlays(overlays)
            for overlay in overlays { overlayKinds.removeValue(forKey: ObjectIdentifier(overlay)) }
        }
        private func add(_ layers: [GeneralMapOverlay], to map: MKMapView) {
            guard !layers.isEmpty else { return }
            for layer in layers { overlayKinds[ObjectIdentifier(layer.overlay)] = layer.kind }
            map.addOverlays(layers.map(\.overlay), level: .aboveRoads)
        }
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let shapes = overlay as? CountryShapesOverlay { return CountryShapesRenderer(shapes: shapes) }
            if let stars = overlay as? VisitedStarsOverlay { return VisitedStarsRenderer(stars: stars, dark: parent.dark) }
            let kind = overlayKinds[ObjectIdentifier(overlay)] ?? .countryOutline
            let orange = UIColor(red: 0.94, green: 0.66, blue: 0.24, alpha: 1)
            if let multi = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
                let alpha: CGFloat = kind == .cityFill ? 0.16 : (parent.dark ? 0.43 : 0.35)
                renderer.fillColor = orange.withAlphaComponent(alpha)
                return renderer
            }
            if let polygon = overlay as? MKPolygon, kind == .focusFill {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(Sketch.coral).withAlphaComponent(parent.dark ? 0.2 : 0.13)
                return renderer
            }
            if let polyline = overlay as? MKPolyline, kind == .focusOutline {
                let renderer = HaloPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(Sketch.coral)
                renderer.halo = UIColor(Sketch.coral).withAlphaComponent(0.22)
                renderer.lineWidth = 2.4; renderer.lineJoin = .round; renderer.lineCap = .round
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let alpha: CGFloat = kind == .countryFill ? (parent.dark ? 0.43 : 0.35) : kind == .cityFill ? 0.16 : 0.08
                renderer.fillColor = orange.withAlphaComponent(alpha)
                if kind == .extent { renderer.strokeColor = orange.withAlphaComponent(0.6); renderer.lineWidth = 1.5; renderer.lineDashPattern = [6,5] }
                return renderer
            }
            if let multi = overlay as? MKMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
                renderer.strokeColor = orange.withAlphaComponent(kind == .hatch ? 0.45 : 0.8)
                renderer.lineWidth = kind == .cityOutline ? 1.25 : 0.8
                renderer.lineJoin = .round
                return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = orange.withAlphaComponent(kind == .hatch ? 0.45 : 0.8)
            renderer.lineWidth = kind == .route ? 6 : kind == .focusOutline ? 3 : kind == .cityOutline ? 1.25 : 0.8
            renderer.lineJoin = .round
            return renderer
        }
    }
}
final class GeneralMapMarkerView: MKAnnotationView {
    private let bubble = UIView()
    private let label = UILabel()
    private let detailRow = UIView()
    private let dot = UIView()
    private let visitedBadge = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
    private let flagView = UIImageView()
    private let raised = CAGradientLayer()
    private let tail = CAShapeLayer()
    private var signature = ""
    private var previousStarMode: Bool?
    private var chipViews: [UIView] = []
    private var hadContent = false
    static func items(_ annotation: MKAnnotation?) -> [GeneralMapAnnotation] {
        if let city = annotation as? GeneralMapAnnotation { return [city] }
        return (annotation as? MKClusterAnnotation)?.memberAnnotations.compactMap { $0 as? GeneralMapAnnotation } ?? []
    }
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(bubble); bubble.addSubview(label); bubble.addSubview(detailRow); addSubview(dot); bubble.addSubview(flagView); bubble.addSubview(visitedBadge)
        layer.insertSublayer(tail, below: bubble.layer)
        flagView.contentMode = .scaleAspectFill; flagView.clipsToBounds = true
        bubble.layer.insertSublayer(raised, at: 0); raised.isHidden = true
        flagView.layer.borderColor = UIColor.white.cgColor; flagView.layer.borderWidth = 1.5
        label.textAlignment = .center
        visitedBadge.contentMode = .scaleAspectFit
        bubble.layer.borderWidth = 0.8
        bubble.layer.shadowColor = UIColor.black.cgColor; bubble.layer.shadowOpacity = 0.16
        bubble.layer.shadowRadius = 2; bubble.layer.shadowOffset = .init(width: 0, height: 1)
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); signature = ""; previousStarMode = nil; hadContent = false }
    func applyZoomScale(_ scale: CGFloat) {
        let target = scale == 1 ? CGAffineTransform.identity : CGAffineTransform(scaleX: scale, y: scale)
        guard transform != target else { return }
        if window == nil || UIAccessibility.isReduceMotionEnabled { transform = target; return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) { self.transform = target }
    }
    /// Cute filled glyphs for the trip, pin and save counters, drawn on a coloured chip.
    enum CountGlyph: String { case trip, pin, save }
    private static var glyphCache: [String: UIImage] = [:]
    static func glyphImage(_ glyph: CountGlyph, color: UIColor) -> UIImage {
        let key = glyph.rawValue + color.description
        if let cached = glyphCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { r in
            let ctx = r.cgContext
            color.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
            // Soft light on the upper half gives the chip a little gumdrop shine.
            ctx.saveGState(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 16, height: 16)).addClip()
            UIColor.white.withAlphaComponent(0.2).setFill(); UIBezierPath(ovalIn: CGRect(x: -2, y: -8, width: 20, height: 14)).fill()
            ctx.restoreGState()
            UIColor.white.setFill(); UIColor.white.setStroke()
            switch glyph {
            case .trip:
                let handle = UIBezierPath(roundedRect: CGRect(x: 6.1, y: 3.7, width: 3.8, height: 3.6), cornerRadius: 1.4)
                handle.lineWidth = 1.2; handle.stroke()
                UIBezierPath(roundedRect: CGRect(x: 3.6, y: 5.9, width: 8.8, height: 6.4), cornerRadius: 2).fill()
                color.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: CGRect(x: 3.6, y: 8.3, width: 8.8, height: 0.9), cornerRadius: 0.4).fill()
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: 7.2, y: 7.8, width: 1.6, height: 2.1), cornerRadius: 0.8).fill()
            case .pin:
                let drop = UIBezierPath(arcCenter: CGPoint(x: 8, y: 6.6), radius: 3.7, startAngle: .pi * 5 / 6, endAngle: .pi / 6, clockwise: true)
                drop.addLine(to: CGPoint(x: 8, y: 13)); drop.close(); drop.fill()
                color.setFill(); UIBezierPath(ovalIn: CGRect(x: 6.5, y: 5.1, width: 3, height: 3)).fill()
            case .save:
                let heart = UIBezierPath()
                heart.move(to: CGPoint(x: 8, y: 12.7))
                heart.addCurve(to: CGPoint(x: 3.2, y: 7.3), controlPoint1: CGPoint(x: 5.3, y: 11), controlPoint2: CGPoint(x: 3.2, y: 9.4))
                heart.addCurve(to: CGPoint(x: 8, y: 6.2), controlPoint1: CGPoint(x: 3.2, y: 4.5), controlPoint2: CGPoint(x: 6.9, y: 4.2))
                heart.addCurve(to: CGPoint(x: 12.8, y: 7.3), controlPoint1: CGPoint(x: 9.1, y: 4.2), controlPoint2: CGPoint(x: 12.8, y: 4.5))
                heart.addCurve(to: CGPoint(x: 8, y: 12.7), controlPoint1: CGPoint(x: 12.8, y: 9.4), controlPoint2: CGPoint(x: 10.7, y: 11))
                heart.close(); heart.fill()
            }
        }
        glyphCache[key] = image
        return image
    }
    /// Counters and the tick spring in one after another when a label gains them.
    private func popIn() {
        guard !UIAccessibility.isReduceMotionEnabled, window != nil else { return }
        let items = chipViews + (visitedBadge.isHidden ? [] : [visitedBadge])
        for (index, view) in items.enumerated() {
            view.transform = CGAffineTransform(scaleX: 0.3, y: 0.3); view.alpha = 0
            UIView.animate(withDuration: 0.42, delay: 0.04 * Double(index), usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8,
                           options: [.allowUserInteraction]) { view.transform = .identity; view.alpha = 1 }
        }
        bubble.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction]) { self.bubble.transform = .identity }
    }
    func configure(local: Bool, dark: Bool, showVisitedBadges: Bool = true, showVisitedCityLabels: Bool = true, span: Double = 9, reduceMotion: Bool = false) {
        applyZoomScale(GeneralNativeMap.Coordinator.zoomScale(span: span))
        let items = Self.items(annotation).map(\.marker)
        guard let first = items.first else { return }
        let presentation = GeneralMapMarkerPresentation(items, local: local, showVisitedBadges: showVisitedBadges)
        let blob = presentation.cityCount > 1
        let point = presentation.isPoint
        let starMode = false
        let trips = presentation.trips, pins = presentation.pins, saves = presentation.saves
        let flag = first.countryCode.map { code in String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar($0.value + 127397) })) } ?? ""
        let text = starMode ? "★" : blob ? presentation.cityCount.formatted() : point ? (first.emoji.map { $0 + " " } ?? "") + first.name : first.city + (flag.isEmpty ? "" : " " + flag)
        let detailItems: [(String, Int)] = [("airplane", trips), ("mappin", pins), ("heart.fill", saves)].filter { $0.1 > 0 }
        let details = [(trips > 0 ? "\(trips) trips" : ""), (pins > 0 ? "\(pins) pins" : ""), (saves > 0 ? "\(saves) saves" : "")].filter { !$0.isEmpty }.joined(separator: ", ")
        let key = "\(text):\(details):\(point):\(blob):\(dark):\(presentation.visited)"
        guard signature != key else { return }; signature = key
        let orange = UIColor(red: 0.94, green: 0.66, blue: 0.24, alpha: 1)
        let surface = dark ? UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 0.98) : .white
        let ink = dark ? UIColor(white: 0.96, alpha: 1) : UIColor(red: 0.15, green: 0.17, blue: 0.19, alpha: 1)
        let animateTransition = previousStarMode.map { $0 != starMode } ?? false
        previousStarMode = starMode
        let cityLabel = first.isCity && !blob && !starMode && !point
        let update = {
            self.bubble.isHidden = false
            self.detailRow.subviews.forEach { $0.removeFromSuperview() }
            self.tail.isHidden = true
            if cityLabel {
                self.layoutCityLabel(first: first, trips: trips, pins: pins, saves: saves, visited: presentation.visited, dark: dark, details: details)
                return
            }
            self.flagView.isHidden = true
            self.dot.isHidden = blob || starMode
            self.visitedBadge.isHidden = starMode || blob || !presentation.visited || !first.isCity
            self.visitedBadge.tintColor = orange
            self.label.font = UIFont(name: "PlusJakartaSans-Bold", size: blob ? 12 : starMode ? 13 : 10) ?? .systemFont(ofSize: blob ? 12 : 10, weight: .bold)
            self.label.attributedText = nil
            self.label.textAlignment = .center
            self.label.text = text
            self.label.textColor = starMode ? orange : ink
            if point && first.emoji == nil, let icon = UIImage(systemName: first.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)) {
                let attachment = NSTextAttachment()
                attachment.image = icon.withTintColor(ink, renderingMode: .alwaysOriginal)
                attachment.bounds = .init(x: 0, y: -1, width: 10, height: 10)
                let title = NSMutableAttributedString(attachment: attachment)
                title.append(NSAttributedString(string: " " + first.name))
                self.label.attributedText = title
            }
            self.detailRow.isHidden = true
            let badgeWidth: CGFloat = !self.visitedBadge.isHidden ? 15 : 0
            let width = starMode ? 18 : blob ? max(29, self.label.intrinsicContentSize.width + 16) : min(230, self.label.intrinsicContentSize.width + badgeWidth + 16)
            let height: CGFloat = starMode ? 18 : blob ? 29 : 25
            let fixedCityAnchor = first.isCity && !blob
            let annotationHeight: CGFloat = fixedCityAnchor ? 64 : height + (blob ? 0 : 9)
            let bubbleTop = fixedCityAnchor ? (starMode ? (annotationHeight - height) / 2 : annotationHeight / 2 - height - 6) : 0
            self.bounds = .init(x: 0, y: 0, width: width, height: annotationHeight)
            self.bubble.frame = .init(x: 0, y: bubbleTop, width: width, height: height)
            self.bubble.backgroundColor = starMode ? .clear : surface; self.bubble.layer.cornerRadius = height / 2
            // Cluster counts share the raised look of the city labels and buttons.
            self.raised.isHidden = starMode
            self.raised.frame = self.bubble.bounds; self.raised.cornerRadius = height / 2
            self.raised.colors = dark ? [UIColor(red: 0.23, green: 0.22, blue: 0.2, alpha: 1).cgColor, UIColor(red: 0.11, green: 0.11, blue: 0.1, alpha: 1).cgColor]
                                      : [UIColor.white.cgColor, UIColor(red: 0.937, green: 0.922, blue: 0.89, alpha: 1).cgColor]
            self.raised.startPoint = CGPoint(x: 0.3, y: 0); self.raised.endPoint = CGPoint(x: 0.7, y: 1)
            if !starMode { self.bubble.backgroundColor = .clear; self.bubble.layer.shadowRadius = 5; self.bubble.layer.shadowOffset = .init(width: 0, height: 2.5) }
            self.bubble.layer.borderWidth = starMode ? 0 : 0.8
            self.bubble.layer.shadowOpacity = starMode ? 0 : 0.16
            self.bubble.layer.borderColor = UIColor.white.withAlphaComponent(dark ? 0.55 : 0.85).cgColor
            self.bubble.layer.shadowPath = UIBezierPath(roundedRect: self.bubble.bounds, cornerRadius: height / 2).cgPath
            self.visitedBadge.frame = .init(x: 6, y: (height - 12) / 2, width: 12, height: 12)
            self.label.frame = starMode ? self.bubble.bounds : .init(x: 6 + badgeWidth, y: 0, width: max(0, width - 12 - badgeWidth), height: height)
            self.dot.backgroundColor = surface; self.dot.layer.cornerRadius = 2.5
            self.dot.frame = .init(x: width / 2 - 2.5, y: fixedCityAnchor ? annotationHeight / 2 - 2.5 : height + 4, width: 5, height: 5)
            self.dot.layer.borderWidth = 0.7; self.dot.layer.borderColor = UIColor.white.cgColor
            self.centerOffset = blob || fixedCityAnchor ? .zero : .init(x: 0, y: -self.frame.height / 2)
            self.accessibilityLabel = starMode ? "Visited city, \(first.city)" : blob ? "\(presentation.cityCount) cities. Tap to expand." : "\(text), \(details)"
        }
        let animateChange = hadContent && window != nil && !reduceMotion
        hadContent = true
        // Never run a UIView.transition on the annotation view itself: MapKit owns its hierarchy and
        // recycles it, and a transition there trips its `annotation != nil` assertions. Animate our own subviews.
        update()
        if animateChange || (animateTransition && showVisitedCityLabels && !reduceMotion) {
            bubble.alpha = 0.4
            UIView.animate(withDuration: 0.26, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) { self.bubble.alpha = 1 }
            if animateChange { popIn() }
        }
    }

    /// City label: round flag, name, and the traveler's trips, pins and saves there.
    private func layoutCityLabel(first: GeneralMapMarker, trips: Int, pins: Int, saves: Int, visited: Bool, dark: Bool, details: String) {
        let surface = dark ? UIColor(red: 0.133, green: 0.129, blue: 0.118, alpha: 1) : UIColor(red: 1, green: 0.988, blue: 0.965, alpha: 1)
        let ink = dark ? UIColor(red: 0.945, green: 0.925, blue: 0.886, alpha: 1) : UIColor(red: 0.118, green: 0.110, blue: 0.098, alpha: 1)
        let soft = dark ? UIColor(red: 0.725, green: 0.694, blue: 0.643, alpha: 1) : UIColor(red: 0.369, green: 0.345, blue: 0.314, alpha: 1)
        let counters: [(CountGlyph, String, UIColor)] = [
            (.trip, trips > 0 ? "\(trips)" : "", UIColor(red: 0.455, green: 0.384, blue: 0.776, alpha: 1)),
            (.pin, pins > 0 ? "\(pins)" : "", UIColor(red: 0.882, green: 0.471, blue: 0.380, alpha: 1)),
            (.save, saves > 0 ? "\(saves)" : "", UIColor(red: 0.847, green: 0.631, blue: 0.298, alpha: 1)),
        ].filter { !$0.1.isEmpty }
        let hasDetails = !counters.isEmpty
        let flagSize: CGFloat = hasDetails ? 26 : 20
        let height: CGFloat = hasDetails ? 39 : 28
        label.attributedText = nil
        label.text = first.city
        label.textAlignment = .left
        label.font = UIFont(name: "PlusJakartaSans-Bold", size: 12) ?? .systemFont(ofSize: 12, weight: .bold)
        label.textColor = ink
        let nameWidth = ceil(min(150, label.intrinsicContentSize.width))
        var detailWidth: CGFloat = 0
        chipViews = []
        for (icon, value, color) in counters {
            if detailWidth > 0 { detailWidth += 8 }
            // A filled, colored chip with a white glyph reads at a glance, unlike a bare 10pt stroke.
            // Chip and number are both 16pt tall on the same row, so they share one centre line
            // whether one, two or all three counters are shown.
            let image = UIImageView(image: Self.glyphImage(icon, color: color))
            image.frame = .init(x: detailWidth, y: 0, width: 16, height: 16)
            detailRow.addSubview(image)
            let count = UILabel(); count.text = value.trimmingCharacters(in: .whitespaces)
            count.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold); count.textColor = soft
            count.textAlignment = .left
            let w = count.text?.isEmpty == false ? ceil(count.intrinsicContentSize.width) : 0
            count.frame = .init(x: detailWidth + 19, y: 0, width: w, height: 16)
            detailRow.addSubview(count)
            chipViews += [image, count]
            detailWidth += 19 + w
        }
        let textX = 4 + flagSize + 7
        let tickWidth: CGFloat = visited ? 15 : 0   // gold tick sits right after the city name
        let width = textX + max(nameWidth + tickWidth, detailWidth) + 11
        let annotationHeight: CGFloat = 64
        let bubbleTop = annotationHeight / 2 - height - 8
        bounds = .init(x: 0, y: 0, width: width, height: annotationHeight)
        bubble.frame = .init(x: 0, y: bubbleTop, width: width, height: height)
        let radius = height / 2
        bubble.backgroundColor = .clear
        bubble.layer.cornerRadius = radius
        raised.frame = bubble.bounds
        raised.cornerRadius = radius
        raised.colors = dark ? [UIColor(red: 0.23, green: 0.22, blue: 0.2, alpha: 1).cgColor, UIColor(red: 0.11, green: 0.11, blue: 0.1, alpha: 1).cgColor]
                             : [UIColor.white.cgColor, UIColor(red: 0.937, green: 0.922, blue: 0.89, alpha: 1).cgColor]
        raised.startPoint = CGPoint(x: 0.3, y: 0); raised.endPoint = CGPoint(x: 0.7, y: 1)
        raised.isHidden = false
        _ = surface
        bubble.layer.borderWidth = 1
        bubble.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.16) : UIColor.white.withAlphaComponent(0.95)).cgColor
        bubble.layer.shadowOpacity = dark ? 0.45 : 0.2
        bubble.layer.shadowRadius = 6; bubble.layer.shadowOffset = .init(width: 0, height: 3)
        bubble.layer.shadowPath = UIBezierPath(roundedRect: bubble.bounds, cornerRadius: radius).cgPath

        flagView.isHidden = false
        flagView.image = Self.flagImage(first.countryCode)
        flagView.frame = .init(x: 4, y: (height - flagSize) / 2, width: flagSize, height: flagSize)
        flagView.layer.cornerRadius = flagSize / 2
        let nameY: CGFloat = hasDetails ? 3 : 0, nameHeight: CGFloat = hasDetails ? 16 : height
        visitedBadge.isHidden = !visited
        visitedBadge.image = Self.iconImage(.check, color: .white, size: 6.5, weight: 3.6, background: UIColor(red: 0.79, green: 0.59, blue: 0.23, alpha: 1))
        visitedBadge.frame = .init(x: textX + nameWidth + 4, y: nameY + (nameHeight - 10) / 2, width: 10, height: 10)
        visitedBadge.layer.cornerRadius = 5; visitedBadge.clipsToBounds = true
        visitedBadge.layer.borderWidth = 0

        label.frame = .init(x: textX, y: nameY, width: nameWidth, height: nameHeight)
        detailRow.isHidden = !hasDetails
        detailRow.frame = .init(x: textX, y: 20, width: detailWidth, height: 16)

        // Pointer from the label down to the city dot.
        let tip = CGPoint(x: width / 2, y: bubbleTop + height + 5)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: tip.x - 5, y: bubbleTop + height - 0.5)); path.addLine(to: tip); path.addLine(to: CGPoint(x: tip.x + 5, y: bubbleTop + height - 0.5)); path.close()
        tail.path = path.cgPath; tail.isHidden = false
        tail.fillColor = (dark ? UIColor(red: 0.11, green: 0.11, blue: 0.1, alpha: 1) : UIColor(red: 0.937, green: 0.922, blue: 0.89, alpha: 1)).cgColor
        layer.insertSublayer(tail, above: bubble.layer)

        dot.isHidden = false
        dot.backgroundColor = UIColor(Sketch.ink); dot.layer.cornerRadius = 3
        dot.frame = .init(x: width / 2 - 3, y: annotationHeight / 2 - 3, width: 6, height: 6)
        dot.layer.borderWidth = 1.5; dot.layer.borderColor = UIColor.white.cgColor
        centerOffset = .zero
        accessibilityLabel = [first.city, details.isEmpty ? nil : details, visited ? "visited" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    private static var iconCache: [String: UIImage] = [:]
    static func iconImage(_ icon: TrippyIcon, color: UIColor, size: CGFloat, weight: CGFloat = 2.6, background: UIColor? = nil) -> UIImage {
        let key = "\(icon.rawValue)|\(color.description)|\(size)|\(weight)|\(background?.description ?? "")"
        if let cached = iconCache[key] { return cached }
        let box = background == nil ? size : size * 1.5
        let image = UIGraphicsImageRenderer(size: CGSize(width: box, height: box)).image { context in
            if let background { background.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: box, height: box)).fill() }
            let inset = (box - size) / 2
            let path = UIBezierPath(cgPath: icon.path(in: CGRect(x: inset, y: inset, width: size, height: size)).cgPath)
            path.lineWidth = weight * size / 24 * 1.15; path.lineCapStyle = .round; path.lineJoinStyle = .round
            color.setStroke(); path.stroke()
        }
        iconCache[key] = image
        return image
    }

    private static var flagCache: [String: UIImage] = [:]
    /// The emoji flag scaled to fill a square, so it can be cut into a circle.
    static func flagImage(_ countryCode: String?) -> UIImage? {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return nil }
        if let cached = flagCache[code] { return cached }
        let flag = String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar($0.value + 127397) })) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 80)]
        let measured = flag.size(withAttributes: attributes)
        let side: CGFloat = 64
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let ctx = renderer.cgContext
            // Emoji flags have transparent padding; scale up so color reaches the edge.
            ctx.translateBy(x: side / 2, y: side / 2)
            ctx.scaleBy(x: side / (measured.width * 0.46), y: side / (measured.height * 0.40))
            flag.draw(at: CGPoint(x: -measured.width / 2, y: -measured.height / 2), withAttributes: attributes)
        }
        flagCache[code] = image
        return image
    }
}

/// A line with a soft wide halo under it, for the selected place's boundary.
final class HaloPolylineRenderer: MKPolylineRenderer {
    var halo: UIColor = .clear
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if path == nil { createPath() }
        if let path {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(10 / zoomScale); context.setLineJoin(.round); context.setLineCap(.round)
            context.setStrokeColor(halo.cgColor); context.strokePath()
            context.restoreGState()
        }
        super.draw(mapRect, zoomScale: zoomScale, in: context)
    }
}

// MARK: - Visited stars (far zoom)

final class VisitedStarAnnotation: NSObject, MKAnnotation {
    let markerID: String
    let coordinate: CLLocationCoordinate2D
    init(markerID: String, coordinate: CLLocationCoordinate2D) { self.markerID = markerID; self.coordinate = coordinate }
}

/// A fixed-size star drawn at screen resolution and centred on its city, so it
/// stays sharp and in place while zooming. It fades with the far-zoom threshold.
final class VisitedStarView: MKAnnotationView {
    static let reuse = "visited-star"
    private static var cache: [Bool: UIImage] = [:]
    private let imageView = UIImageView()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        imageView.frame = bounds; addSubview(imageView)
        collisionMode = .none; displayPriority = .required; clusteringIdentifier = nil; canShowCallout = false
        centerOffset = .zero
        isAccessibilityElement = true; accessibilityLabel = "Visited city"; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        imageView.image = Self.image(dark: traitCollection.userInterfaceStyle == .dark)
    }
    func setVisible(_ visible: Bool, animated: Bool) {
        isUserInteractionEnabled = visible
        let change = { self.alpha = visible ? 1 : 0; self.transform = visible ? .identity : CGAffineTransform(scaleX: 0.6, y: 0.6) }
        if animated { UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: change) }
        else { change() }
    }
    static func image(dark: Bool) -> UIImage {
        if let cached = cache[dark] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { r in
            let ctx = r.cgContext
            let gold = UIColor(red: 0.96, green: 0.72, blue: 0.22, alpha: 1)
            let outer = VisitedStarsRenderer.star(center: CGPoint(x: 9, y: 9), radius: 6.6)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(dark ? 0.6 : 0.28).cgColor)
            ctx.addPath(outer); ctx.setFillColor(UIColor.white.cgColor); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addPath(VisitedStarsRenderer.star(center: CGPoint(x: 9, y: 9.2), radius: 5))
            ctx.saveGState(); ctx.clip()
            let colors = [UIColor(red: 1, green: 0.84, blue: 0.42, alpha: 1).cgColor, gold.cgColor, UIColor(red: 0.82, green: 0.52, blue: 0.1, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 6, y: 3.5), end: CGPoint(x: 12, y: 15), options: [])
            }
            ctx.restoreGState()
            ctx.addPath(outer); ctx.setStrokeColor((dark ? UIColor(white: 0, alpha: 0.6) : UIColor(red: 0.5, green: 0.32, blue: 0.06, alpha: 0.55)).cgColor)
            ctx.setLineWidth(0.8); ctx.strokePath()
        }
        cache[dark] = image
        return image
    }
}
