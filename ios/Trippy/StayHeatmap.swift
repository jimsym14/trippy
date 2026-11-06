import SwiftUI
import MapKit

// MARK: - Data

/// Counts of OpenStreetMap features per grid cell around a city centre.
/// Built live from Overpass (cached for a month) or bundled for Barcelona.
struct StayGrid: Codable, Sendable {
    let city: String
    let south: Double, west: Double, north: Double, east: Double
    let rows: Int, cols: Int
    let layers: [String: [Int]]
    let places: [Place]
    struct Place: Codable, Sendable, Hashable { let name: String; let lat: Double; let lon: Double }

    func cell(lat: Double, lon: Double) -> Int? {
        let r = Int((north - lat) / (north - south) * Double(rows)), c = Int((lon - west) / (east - west) * Double(cols))
        return (0..<rows).contains(r) && (0..<cols).contains(c) ? r * cols + c : nil
    }
}

/// What a traveler can weigh. Each one is a count we can actually get for any city.
enum StayFactor: String, CaseIterable, Identifiable {
    case sights, food, green, transit, budget, quiet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sights: "Sights"; case .food: "Food & cafés"; case .green: "Parks"
        case .transit: "Metro & trains"; case .budget: "Budget stays"; case .quiet: "Quiet nights"
        }
    }
    var symbol: String {
        switch self {
        case .sights: "building.columns"; case .food: "fork.knife"; case .green: "leaf"
        case .transit: "tram"; case .budget: "eurosign"; case .quiet: "moon.zzz"
        }
    }
    var detail: String {
        switch self {
        case .sights: "Museums, galleries and viewpoints nearby"
        case .food: "Restaurants and cafés within a short walk"
        case .green: "Parks close by"
        case .transit: "Metro, tram and train stops"
        case .budget: "Hostels and guesthouses, a sign of cheaper rooms"
        case .quiet: "Fewer bars and clubs around"
        }
    }
}

/// Smoothed 0…1 scores per cell, and neighbourhoods ranked by them.
struct StayScores {
    let grid: StayGrid
    let values: [Double]      // combined score per cell
    let active: [Bool]        // cells that are part of the city
    let perFactor: [StayFactor: [Double]]

    init(grid: StayGrid, factors: Set<StayFactor>) {
        self.grid = grid
        let n = grid.rows * grid.cols
        func smooth(_ raw: [Int]) -> [Double] {
            var out = [Double](repeating: 0, count: n)
            for r in 0..<grid.rows { for c in 0..<grid.cols {
                var sum = 0.0, weight = 0.0
                for dr in -2...2 { for dc in -2...2 {
                    let rr = r + dr, cc = c + dc
                    guard (0..<grid.rows).contains(rr), (0..<grid.cols).contains(cc) else { continue }
                    let w = exp(-Double(dr * dr + dc * dc) / 2.2)
                    sum += Double(raw[rr * grid.cols + cc]) * w; weight += w
                }}
                out[r * grid.cols + c] = sum / weight
            }}
            return out
        }
        func normalized(_ v: [Double]) -> [Double] {
            let sorted = v.filter { $0 > 0 }.sorted()
            guard let top = sorted.isEmpty ? nil : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], top > 0 else { return v.map { _ in 0 } }
            return v.map { min(1, $0 / top) }
        }
        let zero = [Int](repeating: 0, count: n)
        let food = smooth(grid.layers["food"] ?? zero), night = smooth(grid.layers["night"] ?? zero)
        // A cell belongs to the city when there is everyday life around it.
        let life = normalized(zip(food, night).map(+))
        active = life.map { $0 > 0.06 }
        var per: [StayFactor: [Double]] = [:]
        per[.sights] = normalized(smooth(grid.layers["sights"] ?? zero))
        per[.food] = normalized(food)
        per[.green] = normalized(smooth(grid.layers["green"] ?? zero))
        per[.transit] = normalized(smooth(grid.layers["transit"] ?? zero))
        per[.budget] = normalized(smooth(grid.layers["budget"] ?? zero))
        let nightNorm = normalized(night)
        per[.quiet] = nightNorm.map { 1 - $0 }
        perFactor = per
        let chosen = factors.isEmpty ? Set(StayFactor.allCases) : factors
        let act = active
        values = (0..<n).map { i in
            guard act[i] else { return 0 }
            return chosen.map { per[$0]![i] }.reduce(0, +) / Double(chosen.count)
        }
    }

    struct Ranked: Identifiable { let place: StayGrid.Place; let score: Double; var id: String { place.name } }
    func ranked(limit: Int = 6) -> [Ranked] {
        var seen = Set<String>()
        return grid.places.compactMap { place -> Ranked? in
            guard let i = grid.cell(lat: place.lat, lon: place.lon), active[i], seen.insert(place.name).inserted else { return nil }
            return Ranked(place: place, score: values[i])
        }
        .sorted { $0.score > $1.score }
        .prefix(limit).map { $0 }
    }
    func factorScore(_ factor: StayFactor, at place: StayGrid.Place) -> Double {
        guard let i = grid.cell(lat: place.lat, lon: place.lon) else { return 0 }
        return perFactor[factor]?[i] ?? 0
    }
}

actor StayGridRepository {
    static let shared = StayGridRepository()
    private static let rows = 28, halfLat = 0.055
    private static let mirrors = ["https://overpass-api.de/api/interpreter",
                                  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
                                  "https://overpass.kumi.systems/api/interpreter"]
    private static let layers: [(String, String, String)] = [
        ("sights", #"nwr["tourism"~"^(attraction|museum|gallery|viewpoint)$"]"#, "center"),
        ("food", #"node["amenity"~"^(restaurant|cafe)$"]"#, "skel"),
        ("night", #"node["amenity"~"^(bar|pub|nightclub)$"]"#, "skel"),
        ("green", #"way["leisure"="park"]"#, "center"),
        ("transit", #"node["railway"~"^(station|subway_entrance|tram_stop)$"]"#, "skel"),
        ("budget", #"nwr["tourism"~"^(hostel|guest_house)$"]"#, "center"),
        ("hotel", #"nwr["tourism"="hotel"]"#, "center"),
    ]
    private var memory: [String: StayGrid] = [:]

    private func file(_ key: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrippyStayGrid", isDirectory: true).appendingPathComponent(key + ".json")
    }

    func grid(city: String, center: CLLocationCoordinate2D) async throws -> StayGrid {
        let key = city.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        if let grid = memory[key] { return grid }
        if let url = Bundle.main.url(forResource: "stay-grid-" + key, withExtension: "json"),
           let data = try? Data(contentsOf: url), let grid = try? JSONDecoder().decode(StayGrid.self, from: data) {
            memory[key] = grid; return grid
        }
        let cached = file(key)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cached.path), let date = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 30 * 86_400, let data = try? Data(contentsOf: cached),
           let grid = try? JSONDecoder().decode(StayGrid.self, from: data) {
            memory[key] = grid; return grid
        }
        let grid = try await fetch(city: city, center: center)
        memory[key] = grid
        try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(grid).write(to: cached, options: .atomic)
        return grid
    }

    private func fetch(city: String, center: CLLocationCoordinate2D) async throws -> StayGrid {
        let halfLon = Self.halfLat / cos(center.latitude * .pi / 180)
        let s = center.latitude - Self.halfLat, n = center.latitude + Self.halfLat
        let w = center.longitude - halfLon, e = center.longitude + halfLon
        let box = String(format: "%.5f,%.5f,%.5f,%.5f", s, w, n, e)
        var q = "[out:json][timeout:40];"
        for (name, selector, mode) in Self.layers { q += #"make m name="\#(name)";out;\#(selector)(\#(box));out \#(mode) qt;"# }
        q += #"make m name="places";out;node["place"~"^(suburb|neighbourhood|quarter)$"](\#(box));out qt;"#
        var body = URLComponents(); body.queryItems = [URLQueryItem(name: "data", value: q)]
        let payload = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8) ?? Data()
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for mirror in Self.mirrors {
            var request = URLRequest(url: URL(string: mirror)!)
            request.httpMethod = "POST"; request.httpBody = payload; request.timeoutInterval = 60
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("Trippy/0.1 (trip planner prototype)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return try Self.parse(data, city: city, box: (s, w, n, e))
            } catch { lastError = error; if Task.isCancelled { throw error } }
        }
        throw lastError
    }

    private struct Raw: Decodable {
        let elements: [Element]
        struct Element: Decodable {
            let type: String; let lat: Double?; let lon: Double?
            let center: Center?; let tags: [String: String]?
            struct Center: Decodable { let lat: Double; let lon: Double }
        }
    }

    private static func parse(_ data: Data, city: String, box: (Double, Double, Double, Double)) throws -> StayGrid {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let (s, w, n, e) = box, rows = Self.rows, cols = Self.rows
        var layers: [String: [Int]] = Dictionary(uniqueKeysWithValues: Self.layers.map { ($0.0, [Int](repeating: 0, count: rows * cols)) })
        var places: [StayGrid.Place] = [], current = ""
        for el in raw.elements {
            if el.type == "m" { current = el.tags?["name"] ?? ""; continue }
            guard let lat = el.lat ?? el.center?.lat, let lon = el.lon ?? el.center?.lon else { continue }
            if current == "places" {
                if let name = el.tags?["name:en"] ?? el.tags?["name"] { places.append(.init(name: name, lat: lat, lon: lon)) }
                continue
            }
            let r = Int((n - lat) / (n - s) * Double(rows)), c = Int((lon - w) / (e - w) * Double(cols))
            if (0..<rows).contains(r), (0..<cols).contains(c) { layers[current]?[r * cols + c] += 1 }
        }
        guard layers.values.contains(where: { $0.contains { $0 > 0 } }) else { throw URLError(.zeroByteResource) }
        return StayGrid(city: city, south: s, west: w, north: n, east: e, rows: rows, cols: cols, layers: layers, places: places)
    }
}

// MARK: - Screen

struct StayHeatmapView: View {
    let city: String
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grid: StayGrid?
    @State private var failed = false
    @State private var factors: Set<StayFactor> = [.sights, .food, .transit]
    @State private var focus: StayGrid.Place?

    private var scores: StayScores? { grid.map { StayScores(grid: $0, factors: factors) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Where to stay").font(Sketch.display(.title, weight: .bold))
                        Text("Brighter areas have more of what you pick.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(StayFactor.allCases) { factor in
                            let on = factors.contains(factor)
                            Button {
                                withAnimation(.snappy) { if on { factors.remove(factor) } else { factors.insert(factor) } }
                            } label: {
                                Label(factor.title, systemImage: factor.symbol).font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                                    .padding(.horizontal, 12).frame(minHeight: 38)
                                    .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                                    .background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
                            }
                            .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityHint(factor.detail)
                        }
                    }
                    ZStack {
                        if let scores {
                            StayHeatMap(scores: scores, ranked: scores.ranked(), focus: focus)
                        } else {
                            RoundedRectangle(cornerRadius: 22).fill(Sketch.paperDeep)
                            VStack(spacing: 10) {
                                if failed {
                                    Text("Couldn’t load map data. Try again in a minute.").font(Sketch.text(14, relativeTo: .subheadline))
                                    Button("Try again") { failed = false; Task { await load() } }
                                } else {
                                    DoodleView(doodle: .map, tint: Sketch.sage).frame(width: 64, height: 64)
                                    Text("Mapping \(city)’s neighbourhoods…").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                                    Text("The first time takes up to half a minute.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                                }
                            }.padding()
                        }
                    }
                    .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.ink.opacity(0.08)))
                    if let scores {
                        let ranked = scores.ranked()
                        if ranked.isEmpty {
                            Text("No named neighbourhoods here yet.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        } else {
                            Text("BEST MATCHES").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                            VStack(spacing: 10) {
                                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                                    neighbourhoodRow(index + 1, item, scores: scores)
                                }
                            }
                        }
                    }
                    Text("Counts from OpenStreetMap (sights, restaurants, bars, parks, stations, hostels). There is no free street-level safety data for every city, so safety isn’t scored here.")
                        .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
                }
                .padding(20)
            }
            .background(PaperBackground())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func neighbourhoodRow(_ rank: Int, _ item: StayScores.Ranked, scores: StayScores) -> some View {
        Button { withAnimation(.snappy) { focus = item.place } } label: {
            HStack(spacing: 12) {
                Text("\(rank)").font(Sketch.text(15, "Bold", relativeTo: .headline)).frame(width: 34, height: 34).raisedCircle()
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.place.name).font(Sketch.text(15, "SemiBold", relativeTo: .body)).lineLimit(1)
                    HStack(spacing: 10) {
                        ForEach(StayFactor.allCases.filter { factors.isEmpty || factors.contains($0) }) { f in
                            let v = scores.factorScore(f, at: item.place)
                            HStack(spacing: 3) {
                                Image(systemName: f.symbol).font(.system(size: 10, weight: .semibold))
                                Capsule().fill(Sketch.ink.opacity(0.08)).frame(width: 22, height: 4)
                                    .overlay(alignment: .leading) { Capsule().fill(Sketch.sage).frame(width: 22 * max(0.08, v), height: 4) }
                            }
                            .foregroundStyle(Sketch.inkSoft)
                            .accessibilityLabel("\(f.title) \(Int(v * 100)) of 100")
                        }
                    }
                }
                Spacer(minLength: 4)
                Button("Stay here") { onPick(item.place.name); dismiss() }
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).padding(.horizontal, 12).frame(minHeight: 36).raisedCapsule()
                    .buttonStyle(SketchPressStyle())
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(focus == item.place ? Sketch.sage.opacity(0.12) : Sketch.card))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard grid == nil else { return }
        do {
            guard let mark = try await CLGeocoder().geocodeAddressString(city).first, let location = mark.location else { failed = true; return }
            grid = try await StayGridRepository.shared.grid(city: city, center: location.coordinate)
        } catch { if !Task.isCancelled { failed = true } }
    }
}

// MARK: - Map

private final class StayHeatOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: CGImage
    init(grid: StayGrid, image: CGImage) {
        let tl = MKMapPoint(CLLocationCoordinate2D(latitude: grid.north, longitude: grid.west))
        let br = MKMapPoint(CLLocationCoordinate2D(latitude: grid.south, longitude: grid.east))
        boundingMapRect = MKMapRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
        coordinate = CLLocationCoordinate2D(latitude: (grid.north + grid.south) / 2, longitude: (grid.west + grid.east) / 2)
        self.image = image
    }
}

private final class StayHeatRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heat = overlay as? StayHeatOverlay else { return }
        let rect = self.rect(for: heat.boundingMapRect)
        context.interpolationQuality = .high
        // CGContext draws images bottom-up; flip into the overlay's rect.
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(heat.image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

private final class StayLabel: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let rank: Int
    init(_ place: StayGrid.Place, rank: Int) {
        coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon); title = place.name; self.rank = rank
    }
}

private struct StayHeatMap: UIViewRepresentable {
    let scores: StayScores
    let ranked: [StayScores.Ranked]
    let focus: StayGrid.Place?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.showsCompass = false
        let g = scores.grid
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (g.north + g.south) / 2, longitude: (g.west + g.east) / 2),
                                         span: MKCoordinateSpan(latitudeDelta: (g.north - g.south) * 0.8, longitudeDelta: (g.east - g.west) * 0.8)), animated: false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let key = scores.values.map { String(Int($0 * 50)) }.joined()
        if key != context.coordinator.key, let image = Self.image(scores) {
            context.coordinator.key = key
            let old = map.overlays
            map.addOverlay(StayHeatOverlay(grid: scores.grid, image: image), level: .aboveRoads)
            map.removeOverlays(old)
            map.removeAnnotations(map.annotations)
            map.addAnnotations(ranked.enumerated().map { StayLabel($0.element.place, rank: $0.offset + 1) })
        }
        if let focus, focus != context.coordinator.focused {
            context.coordinator.focused = focus
            map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: focus.lat, longitude: focus.lon),
                                             latitudinalMeters: 2_500, longitudinalMeters: 2_500), animated: true)
        }
    }

    /// Upsampled with bilinear interpolation so cells blend into soft areas.
    static func image(_ scores: StayScores) -> CGImage? {
        let g = scores.grid, k = 6
        let w = g.cols * k, h = g.rows * k
        func sample(_ x: Double, _ y: Double) -> (Double, Double) {
            let cx = min(max(x, 0), Double(g.cols - 1)), cy = min(max(y, 0), Double(g.rows - 1))
            let x0 = Int(cx), y0 = Int(cy), x1 = min(x0 + 1, g.cols - 1), y1 = min(y0 + 1, g.rows - 1)
            let fx = cx - Double(x0), fy = cy - Double(y0)
            func v(_ c: Int, _ r: Int) -> (Double, Double) { let i = r * g.cols + c; return (scores.values[i], scores.active[i] ? 1 : 0) }
            let a = v(x0, y0), b = v(x1, y0), c = v(x0, y1), d = v(x1, y1)
            func mix(_ p: Double, _ q: Double, _ t: Double) -> Double { p + (q - p) * t }
            return (mix(mix(a.0, b.0, fx), mix(c.0, d.0, fx), fy), mix(mix(a.1, b.1, fx), mix(c.1, d.1, fx), fy))
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let lo = (r: 0.91, g: 0.73, b: 0.38), hi = (r: 0.29, g: 0.46, b: 0.38)  // ochre → sage
        for y in 0..<h { for x in 0..<w {
            let (raw, mask) = sample((Double(x) + 0.5) / Double(k) - 0.5, (Double(y) + 0.5) / Double(k) - 0.5)
            guard mask > 0.01 else { continue }
            let v = max(0, min(1, raw / max(mask, 0.01)))
            let a = (0.1 + 0.6 * v * v) * mask
            let i = (y * w + x) * 4
            pixels[i] = UInt8((lo.r + (hi.r - lo.r) * v) * a * 255)
            pixels[i + 1] = UInt8((lo.g + (hi.g - lo.g) * v) * a * 255)
            pixels[i + 2] = UInt8((lo.b + (hi.b - lo.b) * v) * a * 255)
            pixels[i + 3] = UInt8(a * 255)
        }}
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var key = ""
        var focused: StayGrid.Place?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            overlay is StayHeatOverlay ? StayHeatRenderer(overlay: overlay) : MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let label = annotation as? StayLabel else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "stay") ?? MKAnnotationView(annotation: label, reuseIdentifier: "stay")
            view.annotation = label
            let text = UILabel()
            text.text = "\(label.rank)  \(label.title ?? "")"
            text.font = UIFont(name: "PlusJakartaSans-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
            text.textColor = UIColor(Sketch.ink)
            text.sizeToFit()
            let pill = UIView(frame: CGRect(x: 0, y: 0, width: text.bounds.width + 20, height: 26))
            pill.backgroundColor = UIColor(Sketch.card)
            pill.layer.cornerRadius = 13
            pill.layer.shadowColor = UIColor.black.cgColor; pill.layer.shadowOpacity = 0.18; pill.layer.shadowRadius = 4; pill.layer.shadowOffset = CGSize(width: 0, height: 2)
            text.center = CGPoint(x: pill.bounds.midX, y: pill.bounds.midY)
            pill.addSubview(text)
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(pill)
            view.frame = pill.frame
            view.centerOffset = .zero
            view.displayPriority = MKFeatureDisplayPriority(rawValue: 1000 - Float(label.rank) * 40)
            view.collisionMode = .rectangle
            return view
        }
    }
}
