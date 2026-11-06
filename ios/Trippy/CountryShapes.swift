import MapKit
import UIKit

// MARK: - Visited-country layer
//
// One overlay draws every visited country. It carries three precomputed detail
// levels as CGPaths in map points and picks one per tile from the zoom scale, so
// zooming never adds, removes or re-simplifies anything. Fill, outline, heat
// colour and hatching are all drawn by one renderer.

enum CountryFillMode: String, CaseIterable, Identifiable, Codable {
    case visited, heat, continent, recent
    var id: String { rawValue }
    var title: String {
        switch self { case .visited: "Visited"; case .heat: "By cities"; case .continent: "By continent"; case .recent: "By last visit" }
    }
    var symbol: String {
        switch self { case .visited: "checkmark.circle"; case .heat: "flame"; case .continent: "globe.europe.africa"; case .recent: "clock" }
    }
}

struct CountryShapeStyle: Equatable {
    var fill = true
    var outlines = true
    var hatching = false
    var mode: CountryFillMode = .visited
    var dark = false
}

/// Per-country facts the colouring needs.
struct CountryVisitStats: Sendable, Hashable {
    let code: String
    let continent: String
    let cities: Int
    let lastVisit: Date
}

/// Map-point paths for one country at the three detail levels.
final class CountryGeometry: @unchecked Sendable {
    let code: String
    let rect: MKMapRect
    let paths: [CGPath]   // world, regional, local
    init(code: String, rect: MKMapRect, paths: [CGPath]) { self.code = code; self.rect = rect; self.paths = paths }
}

final class CountryShapesOverlay: NSObject, MKOverlay {
    struct Entry {
        let geometry: CountryGeometry
        let fill: CGColor
        let stroke: CGColor
        let hatch: CGColor
    }
    let entries: [Entry]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    let style: CountryShapeStyle

    init(geometries: [CountryGeometry], stats: [String: CountryVisitStats], style: CountryShapeStyle) {
        self.style = style
        let maxCities = max(1, stats.values.map(\.cities).max() ?? 1)
        let newest = stats.values.map(\.lastVisit).max() ?? .now
        let oldest = stats.values.map(\.lastVisit).min() ?? .now
        entries = geometries.map { g in
            let s = stats[g.code]
            let base: UIColor
            var strength: CGFloat = 1
            switch style.mode {
            case .visited: base = CountryPalette.amber
            case .heat:
                base = CountryPalette.heat
                strength = CGFloat(log(1 + Double(s?.cities ?? 1)) / log(1 + Double(maxCities)))
            case .continent: base = CountryPalette.continent(s?.continent ?? "")
            case .recent:
                base = CountryPalette.recent
                let span = max(1, newest.timeIntervalSince(oldest))
                strength = CGFloat(1 - (newest.timeIntervalSince(s?.lastVisit ?? oldest) / span) * 0.75)
            }
            let fillAlpha = (style.dark ? 0.2 : 0.14) + (style.dark ? 0.42 : 0.4) * strength
            return Entry(geometry: g,
                         fill: base.withAlphaComponent(style.fill ? fillAlpha : 0).cgColor,
                         stroke: base.withAlphaComponent(style.dark ? 0.95 : 0.85).cgColor,
                         hatch: (style.dark ? base.lighter : base.darker).withAlphaComponent(0.55 + 0.3 * strength).cgColor)
        }
        let union = geometries.reduce(MKMapRect.null) { $0.union($1.rect) }
        boundingMapRect = union.isNull ? MKMapRect.world : union.insetBy(dx: -2_000, dy: -2_000)
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }

    func intersects(_ mapRect: MKMapRect) -> Bool { mapRect.intersects(boundingMapRect) }
}

enum CountryPalette {
    static let amber = UIColor(red: 0.94, green: 0.66, blue: 0.24, alpha: 1)
    static let heat = UIColor(red: 0.85, green: 0.36, blue: 0.20, alpha: 1)
    static let recent = UIColor(red: 0.29, green: 0.47, blue: 0.63, alpha: 1)
    static func continent(_ name: String) -> UIColor {
        switch name {
        case "Europe": UIColor(red: 0.29, green: 0.47, blue: 0.63, alpha: 1)
        case "Asia": UIColor(red: 0.75, green: 0.38, blue: 0.25, alpha: 1)
        case "Africa": UIColor(red: 0.73, green: 0.52, blue: 0.17, alpha: 1)
        case "North America": UIColor(red: 0.46, green: 0.35, blue: 0.59, alpha: 1)
        case "South America": UIColor(red: 0.29, green: 0.46, blue: 0.38, alpha: 1)
        case "Oceania": UIColor(red: 0.20, green: 0.55, blue: 0.62, alpha: 1)
        default: amber
        }
    }
    /// Heat ramp used by the legend: pale sand to deep clay.
    static let heatRamp: [UIColor] = [UIColor(red: 0.98, green: 0.84, blue: 0.55, alpha: 1), UIColor(red: 0.93, green: 0.6, blue: 0.3, alpha: 1), heat]
}

extension UIColor {
    var darker: UIColor { adjusted(by: -0.22) }
    var lighter: UIColor { adjusted(by: 0.22) }
    private func adjusted(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: min(1, max(0, b + amount)), alpha: a)
    }
}

final class CountryShapesRenderer: MKOverlayRenderer {
    private let shapes: CountryShapesOverlay
    init(shapes: CountryShapesOverlay) { self.shapes = shapes; super.init(overlay: shapes) }

    /// Points on screen per degree of longitude decides which ring set to draw.
    private static func level(for zoomScale: MKZoomScale) -> Int {
        let pointsPerDegree = Double(zoomScale) * MKMapSize.world.width / 360
        return pointsPerDegree < 14 ? 0 : pointsPerDegree < 140 ? 1 : 2
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let style = shapes.style
        let level = Self.level(for: zoomScale)
        let pad = 6 / Double(zoomScale)
        let tile = mapRect.insetBy(dx: -pad, dy: -pad)
        let origin = shapes.boundingMapRect.origin
        context.saveGState()
        context.translateBy(x: -origin.x, y: -origin.y)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for entry in shapes.entries where entry.geometry.rect.intersects(tile) {
            let path = entry.geometry.paths[min(level, entry.geometry.paths.count - 1)]
            if style.fill {
                context.addPath(path)
                context.setFillColor(entry.fill)
                context.fillPath(using: .evenOdd)
            }
            if style.hatching {
                drawHatch(path: path, area: tile.intersection(entry.geometry.rect), zoomScale: zoomScale, color: entry.hatch, in: context)
            }
            if style.outlines {
                context.addPath(path)
                context.setStrokeColor(entry.stroke)
                context.setLineWidth(1.15 / zoomScale)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    /// Pen-like diagonal strokes. Spacing, weight and dashes are fixed in screen
    /// points and anchored to global map coordinates, so tiles meet seamlessly
    /// and the texture looks the same at every zoom.
    private func drawHatch(path: CGPath, area: MKMapRect, zoomScale: MKZoomScale, color: CGColor, in context: CGContext) {
        guard !area.isNull, area.width > 0 else { return }
        let z = Double(zoomScale)
        let spacing = 6.5 / z
        context.saveGState()
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.setStrokeColor(color)
        // Lines y = -x + c run bottom-left to top-right on screen (map y grows down).
        let start = floor((area.minX + area.minY) / spacing) * spacing
        let end = area.maxX + area.maxY
        var c = start
        let period = 30 / z
        while c <= end {
            let index = Int((c / spacing).rounded())
            var noise = UInt64(truncatingIfNeeded: index &* 2_654_435_761)
            noise ^= noise >> 13
            let jitter = Double(noise % 1000) / 1000
            // Endpoints of the line clipped to the area.
            let x0 = max(area.minX, c - area.maxY), x1 = min(area.maxX, c - area.minY)
            if x1 > x0 {
                context.setLineWidth((0.55 + 0.45 * jitter) / zoomScale)
                // Long pen strokes with small gaps; the phase follows global x.
                let dashes: [CGFloat] = [CGFloat(period * (0.62 + 0.25 * jitter)), CGFloat(period * 0.09), CGFloat(period * 0.22), CGFloat(period * 0.07)]
                let total = dashes.reduce(0, +)
                let phase = CGFloat((x0 * 1.4142).truncatingRemainder(dividingBy: Double(total)) + Double(jitter) * Double(total))
                context.setLineDash(phase: phase, lengths: dashes)
                context.move(to: CGPoint(x: x0, y: c - x0))
                context.addLine(to: CGPoint(x: x1, y: c - x1))
                context.strokePath()
            }
            c += spacing
        }
        context.restoreGState()
    }
}

// MARK: - Geometry store

/// Loads each visited country's boundary once, in parallel, and keeps its
/// three detail levels for every map in the app.
actor CountryShapeStore {
    static let shared = CountryShapeStore()
    private var geometries: [String: CountryGeometry] = [:]
    private var missing: Set<String> = []
    /// Vertex budgets per ring for the world, regional and local levels.
    static let budgets = [220, 900, 4_000]

    struct Request: Sendable, Hashable { let code: String; let latitude: Double; let longitude: Double }

    func geometries(for requests: [Request]) async -> (shapes: [CountryGeometry], unavailable: [String]) {
        let pending = requests.filter { geometries[$0.code] == nil && !missing.contains($0.code) }
        await withTaskGroup(of: (String, CountryGeometry?).self) { group in
            for request in pending {
                group.addTask {
                    let lines = try? await GeoBoundaryRepository.shared.boundary(
                        countryISO2: request.code, countryNames: [], placeNames: [], levelID: "country",
                        center: .init(latitude: request.latitude, longitude: request.longitude), includeTexture: false)
                    guard let lines else { return (request.code, nil) }
                    return (request.code, Self.build(code: request.code, lines: lines))
                }
            }
            for await (code, geometry) in group {
                if let geometry { geometries[code] = geometry } else { missing.insert(code) }
            }
        }
        let shapes = requests.compactMap { geometries[$0.code] }
        return (shapes, requests.map(\.code).filter { geometries[$0] == nil })
    }

    func retryMissing() { missing.removeAll() }

    /// Builds the three path levels. Outer rings and holes share one path and are
    /// filled even-odd, so enclaves and lakes stay open.
    static func build(code: String, lines: [GeoBoundaryLine]) -> CountryGeometry? {
        let rings = lines.filter { $0.style == .outline }.map(\.points).filter { $0.count >= 4 }
        guard !rings.isEmpty else { return nil }
        var rect = MKMapRect.null
        var paths: [CGPath] = []
        for (levelIndex, budget) in budgets.enumerated() {
            let path = CGMutablePath()
            let minimumExtent = levelIndex == 0 ? 0.06 : levelIndex == 1 ? 0.006 : 0
            for ring in rings {
                guard BeenBoundaryPreparation.extent(ring) >= minimumExtent else { continue }
                let points = ring.count > budget ? GeoBoundaryRepository.simplify(ring, maximumPoints: budget) : ring
                guard points.count >= 4 else { continue }
                var previous: MKMapPoint?
                for (i, point) in points.enumerated() {
                    var mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, min(85, point.latitude)), longitude: point.longitude))
                    // Keep rings that cross the antimeridian continuous.
                    if let previous {
                        let width = MKMapSize.world.width
                        if mapPoint.x - previous.x > width / 2 { mapPoint.x -= width } else if previous.x - mapPoint.x > width / 2 { mapPoint.x += width }
                    }
                    if i == 0 { path.move(to: CGPoint(x: mapPoint.x, y: mapPoint.y)) } else { path.addLine(to: CGPoint(x: mapPoint.x, y: mapPoint.y)) }
                    if levelIndex == 2 { rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0))) }
                    previous = mapPoint
                }
                path.closeSubpath()
            }
            paths.append(path.copy() ?? path)
        }
        guard !rect.isNull else { return nil }
        return CountryGeometry(code: code, rect: rect, paths: paths)
    }
}

// MARK: - Visited stars (far zoom)

/// Visited cities seen from far away. Drawn as part of the map, so they stay
/// exactly on their city while zooming; only visible at world-scale zoom.
final class VisitedStarsOverlay: NSObject, MKOverlay {
    let points: [MKMapPoint]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    init(_ coordinates: [CLLocationCoordinate2D]) {
        points = coordinates.map(MKMapPoint.init)
        let rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 1, height: 1))) }
        boundingMapRect = rect.isNull ? .world : rect.insetBy(dx: -4_000_000, dy: -4_000_000)
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }
}

final class VisitedStarsRenderer: MKOverlayRenderer {
    private let stars: VisitedStarsOverlay
    private let dark: Bool
    init(stars: VisitedStarsOverlay, dark: Bool) { self.stars = stars; self.dark = dark; super.init(overlay: stars) }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Same threshold as the city labels: about 18° of latitude on screen.
        let pointsPerDegree = Double(zoomScale) * MKMapSize.world.width / 360
        guard pointsPerDegree < 34 else { return }
        let radius = 7.5 / Double(zoomScale)
        let area = mapRect.insetBy(dx: -radius * 2, dy: -radius * 2)
        let origin = stars.boundingMapRect.origin
        let gold = UIColor(red: 0.96, green: 0.72, blue: 0.22, alpha: 1)
        let rim = dark ? UIColor(white: 0.08, alpha: 0.9) : UIColor(red: 0.42, green: 0.27, blue: 0.05, alpha: 0.95)
        context.saveGState()
        context.translateBy(x: -origin.x, y: -origin.y)
        for p in stars.points where area.contains(p) {
            let path = Self.star(center: CGPoint(x: p.x, y: p.y), radius: radius)
            // Soft glow, white halo, gold body, thin dark rim: legible on both map themes.
            context.setShadow(offset: .zero, blur: CGFloat(6 / zoomScale), color: gold.withAlphaComponent(0.7).cgColor)
            context.addPath(path); context.setFillColor(UIColor.white.cgColor); context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.addPath(Self.star(center: CGPoint(x: p.x, y: p.y), radius: radius * 0.78))
            context.setFillColor(gold.cgColor); context.fillPath()
            context.addPath(path); context.setStrokeColor(rim.cgColor); context.setLineWidth(0.9 / zoomScale); context.strokePath()
        }
        context.restoreGState()
    }

    static func star(center: CGPoint, radius: Double) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.46
            let a = Double(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
