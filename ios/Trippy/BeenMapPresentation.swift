import SwiftUI
import MapKit

// Three geometry budgets; camera movement never re-simplifies a country's rings.
enum BeenBoundaryDetail: Int, CaseIterable, Sendable {
    case local, regional, world
    static func at(span: Double) -> Self { span >= 16 ? .world : span >= 2 ? .regional : .local }
    var maximumPoints: Int { switch self { case .local: 480; case .regional: 160; case .world: 64 } }
    var minimumExtent: Double { switch self { case .local: 0; case .regional: 0.008; case .world: 0.08 } }
}
struct BeenBoundaryGeometry: Sendable {
    let fills: [GeoBoundaryLine]
    let outlines: [GeoBoundaryLine]
    let textures: [GeoBoundaryLine]
}
actor BeenBoundaryPreparation {
    static let shared = BeenBoundaryPreparation()
    private var cache: [String: [BeenBoundaryDetail: [GeoBoundaryPoint]]] = [:]
    func prepare(_ lines: [GeoBoundaryLine], city: Bool, includeCountryHatches: Bool = false) -> [BeenBoundaryDetail: BeenBoundaryGeometry] {
        var result: [BeenBoundaryDetail: BeenBoundaryGeometry] = [:]
        for detail in BeenBoundaryDetail.allCases {
            var fills: [GeoBoundaryLine] = [], outlines: [GeoBoundaryLine] = [], textures: [GeoBoundaryLine] = []
            for line in lines {
                // Country hatches are unnecessary; city hatches only resolve at local zoom.
                if line.style == .texture {
                    if (city && detail == .local) || (!city && includeCountryHatches) { textures.append(line) }
                    continue
                }
                if city && detail != .local { continue }
                guard line.points.count >= 4 else { continue }
                let extent = Self.extent(line.points)
                guard extent >= detail.minimumExtent else { continue }
                let key = line.id + ":" + String(line.points.hashValue)
                let points: [GeoBoundaryPoint]
                if let cached = cache[key]?[detail] { points = cached }
                else {
                    points = GeoBoundaryRepository.simplify(line.points, maximumPoints: detail.maximumPoints - 1)
                    cache[key, default: [:]][detail] = points
                }
                guard points.count >= 4 else { continue }
                let prepared = GeoBoundaryLine(id: line.id, points: points, style: line.style)
                if line.style == .fill { fills.append(prepared) } else { outlines.append(prepared) }
            }
            if !city && detail == .world && textures.count > 32 {
                let step = max(1, Int(ceil(Double(textures.count) / 32)))
                textures = stride(from: 0, to: textures.count, by: step).map { textures[$0] }
            }
            result[detail] = .init(fills: fills, outlines: outlines, textures: textures)
        }
        if cache.count > 1_024 { cache.removeAll(keepingCapacity: true) }
        return result
    }
    static func extent(_ points: [GeoBoundaryPoint]) -> Double {
        guard let first = points.first else { return 0 }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for point in points {
            let longitude = first.longitude + (point.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, longitude); maxLon = max(maxLon, longitude)
        }
        return max(maxLat - minLat, (maxLon - minLon) * abs(cos((minLat + maxLat) / 2 * .pi / 180)))
    }
}

// Construct native map geometry once when source data changes, rather than in body.
struct BeenBoundaryMapLayer {
    struct Fill: Identifiable { let id: String; let polygon: MapPolygon }
    struct Line: Identifiable { let id: String; let polyline: MapPolyline }
    let fills: [Fill]
    let outlines: [Line]
    let textures: [Line]
    init(_ geometry: BeenBoundaryGeometry) {
        fills = geometry.fills.map { .init(id: $0.id, polygon: MapPolygon(coordinates: $0.points.map(\.coordinate))) }
        outlines = geometry.outlines.map { .init(id: $0.id, polyline: MapPolyline(coordinates: $0.points.map(\.coordinate))) }
        textures = geometry.textures.map { .init(id: $0.id, polyline: MapPolyline(coordinates: $0.points.map(\.coordinate))) }
    }
}
struct BeenBoundaryMapContent: MapContent {
    let layer: BeenBoundaryMapLayer
    let city: Bool
    var showFill = true
    var showOutlines = true
    var showTextures = true
    var body: some MapContent {
        ForEach(showFill ? layer.fills : []) { fill in
            fill.polygon.foregroundStyle((city ? Color.orange : Color.yellow).opacity(city ? 0.12 : 0.18))
        }
        ForEach(showOutlines ? layer.outlines : []) { line in
            line.polyline.stroke((city ? Color.orange : Color.yellow).opacity(city ? 0.62 : 0.72), style: StrokeStyle(lineWidth: city ? 1.25 : 1.8, lineCap: .round, lineJoin: .round))
        }
        ForEach(showTextures ? layer.textures : []) { line in
            line.polyline.stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
    }
}

struct MapCityScreenFootprint {
    let id: String
    let countryCode: String
    let point: CGPoint
    let size: CGSize
    let latitude: Double
    let longitude: Double
    var rect: CGRect { CGRect(x: point.x - size.width / 2 - 3, y: point.y - size.height - 3, width: size.width + 6, height: size.height + 6) }
}
struct MapCountryCityCluster: Identifiable, Equatable {
    let countryCode: String
    let memberIDs: [String]
    let latitude: Double
    let longitude: Double
    var id: String { "country-cities:" + countryCode + ":" + memberIDs.joined(separator: "|") }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
enum MapCountryCityClustering {
    static func groups(_ input: [MapCityScreenFootprint]) -> [MapCountryCityCluster] {
        let items = input.filter { $0.point.x.isFinite && $0.point.y.isFinite }.sorted { $0.id < $1.id }
        guard items.count > 1 else { return [] }
        var unionFind = MapCityFootprintUnionFind(count: items.count)
        let cellSize: CGFloat = 96
        var cells: [MapCityFootprintCell: [Int]] = [:]
        for index in items.indices {
            let rect = items[index].rect
            let minX = Int(floor(rect.minX / cellSize)), maxX = Int(floor(rect.maxX / cellSize))
            let minY = Int(floor(rect.minY / cellSize)), maxY = Int(floor(rect.maxY / cellSize))
            var candidates = Set<Int>()
            for x in minX...maxX { for y in minY...maxY {
                candidates.formUnion(cells[.init(x: x, y: y)] ?? [])
            } }
            for candidate in candidates where rect.intersects(items[candidate].rect) { unionFind.union(index, candidate) }
            for x in minX...maxX { for y in minY...maxY { cells[.init(x: x, y: y), default: []].append(index) } }
        }
        var components: [Int: [MapCityScreenFootprint]] = [:]
        for index in items.indices { components[unionFind.find(index), default: []].append(items[index]) }
        var result: [MapCountryCityCluster] = []
        for members in components.values where members.count > 1 {
            let origin = members[0].longitude
            let longitude = members.reduce(0) { $0 + origin + ($1.longitude - origin + 540).truncatingRemainder(dividingBy: 360) - 180 } / Double(members.count)
            // Merges may contain different countries. The compact face intentionally
            // shows only the number of represented markers, so country identity is
            // not part of the cluster's stable visual identity.
            result.append(.init(countryCode: "", memberIDs: members.map(\.id).sorted(), latitude: members.reduce(0) { $0 + $1.latitude } / Double(members.count), longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180))
        }
        return result.sorted { $0.memberIDs[0] < $1.memberIDs[0] }
    }
}

private struct MapCityFootprintCell: Hashable { let x: Int; let y: Int }
private struct MapCityFootprintUnionFind {
    private var parent: [Int]
    private var rank: [UInt8]
    init(count: Int) { parent = Array(0..<count); rank = Array(repeating: 0, count: count) }
    mutating func find(_ value: Int) -> Int {
        if parent[value] != value { parent[value] = find(parent[value]) }
        return parent[value]
    }
    mutating func union(_ lhs: Int, _ rhs: Int) {
        let left = find(lhs), right = find(rhs)
        guard left != right else { return }
        if rank[left] < rank[right] { parent[left] = right }
        else if rank[left] > rank[right] { parent[right] = left }
        else { parent[right] = left; rank[left] += 1 }
    }
}
