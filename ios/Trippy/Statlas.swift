import Foundation
import SwiftUI
import MapKit

// The documented map endpoint covers the largest cities. Missing cities remain missing.
struct StatlasMapResponse: Decodable, Sendable {
    let points: [StatlasPoint]
}
struct StatlasPoint: Decodable, Sendable {
    let s: String
    let n: String
    let c: String
    let lat: Double
    let lon: Double
    let v: [String: Double?]
    func metric(_ key: String) -> Double? {
        guard let value = v[key] ?? nil, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
struct StatlasSearchResponse: Decodable, Sendable {
    let cities: [StatlasSearchCity]
}
struct StatlasSearchCity: Decodable, Sendable {
    let slug: String
    let name: String
    let country: String
    let metrics: [String: Double?]
}
/// Where the traveler lives, for now the last place the device reported. Prices are compared against this city.
enum HomeCityStore {
    private static let key = "trippy.home.coordinate"
    static func remember(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        UserDefaults.standard.set([coordinate.latitude, coordinate.longitude], forKey: key)
    }
    static var coordinate: CLLocationCoordinate2D? {
        guard let values = UserDefaults.standard.array(forKey: key) as? [Double], values.count == 2 else { return nil }
        let value = CLLocationCoordinate2D(latitude: values[0], longitude: values[1])
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }
}
struct StatlasCityContext: Sendable {
    let name: String
    let country: String
    let safety: Double?
    let cost: Double?
    let bars: Double?
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func match(points: [StatlasPoint], latitude: Double, longitude: Double, countryCode: String?, city: String? = nil) -> Self? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let country = countryCode.flatMap { Locale(identifier: "en_US").localizedString(forRegionCode: $0.uppercased()) }
        let origin = CLLocation(latitude: latitude, longitude: longitude)
        let candidates = points.filter {
            (-90...90).contains($0.lat) && (-180...180).contains($0.lon)
                && (country == nil || normalized($0.c) == normalized(country!))
        }
        let named = candidates.filter { point in
            guard let city else { return false }
            let requested = normalized(city), name = normalized(point.n)
            return (requested == name || requested.hasPrefix(name + ",") || requested.hasPrefix(name + " "))
                && origin.distance(from: CLLocation(latitude: point.lat, longitude: point.lon)) < 30_000
        }
        guard let point = (named.isEmpty ? candidates : named).min(by: {
            origin.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon)) < origin.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lon))
        }), origin.distance(from: CLLocation(latitude: point.lat, longitude: point.lon)) < 30_000 else { return nil }
        let safety = point.metric("safety-index").flatMap { $0 <= 100 ? $0 : nil }
        return .init(name: point.n, country: point.c, safety: safety, cost: point.metric("cost-of-living-index"), bars: point.metric("bars").flatMap { $0 > 0 && $0 < Double(Int.max) ? $0 : nil })
    }
    static func match(cities: [StatlasSearchCity], name: String, countryCode: String?) -> Self? {
        // Search results have no coordinates: never accept a homonym without a country match.
        guard let countryCode, let country = Locale(identifier: "en_US").localizedString(forRegionCode: countryCode.uppercased()),
              let city = cities.first(where: { normalized($0.name) == normalized(name) && normalized($0.country) == normalized(country) }) else { return nil }
        let cost = (city.metrics["cost-of-living-index"] ?? nil).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return .init(name: city.name, country: city.country, safety: (city.metrics["safety-index"] ?? nil).flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }, cost: cost, bars: (city.metrics["bars"] ?? nil).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
    }
}

actor StatlasRepository {
    static let shared = StatlasRepository()
    private struct CacheEntry: Codable { let savedAt: Date; let data: Data }
    private lazy var bundledPoints: [StatlasPoint] = {
        guard let url = Bundle.main.url(forResource: "statlas-city-snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode(StatlasMapResponse.self, from: data) else { return [] }
        return map.points
    }()
    private var memory: [String: CacheEntry] = [:]
    private var pending: [String: Task<Data, Error>] = [:]
    private let lifetime: TimeInterval = 86_400
    private func data(path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(string: "https://statlas.net" + path)!
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!
        let key = url.absoluteString
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TrippySTATLAS", isDirectory: true)
        let filename = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        let file = folder.appendingPathComponent(filename)
        let cached = memory[key] ?? (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(CacheEntry.self, from: $0) }
        if let cached, Date().timeIntervalSince(cached.savedAt) < lifetime { memory[key] = cached; return cached.data }
        if let task = pending[key] { return try await task.value }
        let task = Task<Data, Error> {
            var request = URLRequest(url: url); request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            // Reject HTML/error bodies before caching.
            if path == "/api/map" { _ = try JSONDecoder().decode(StatlasMapResponse.self, from: data) }
            else { _ = try JSONDecoder().decode(StatlasSearchResponse.self, from: data) }
            return data
        }
        pending[key] = task
        defer { pending[key] = nil }
        let data = try await task.value
        let entry = CacheEntry(savedAt: .now, data: data); memory[key] = entry
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(entry) { try? encoded.write(to: file, options: .atomic) }
        return data
    }
    private lazy var sortedCosts: [Double] = bundledPoints.compactMap { $0.metric("cost-of-living-index") }.sorted()
    /// Share of the ~3,000 listed cities that cost less than this one (0…1).
    func costPercentile(_ value: Double) -> Double? {
        guard !sortedCosts.isEmpty else { return nil }
        let below = sortedCosts.firstIndex { $0 >= value } ?? sortedCosts.count
        return Double(below) / Double(sortedCosts.count)
    }
    /// The listed city nearest the traveler's home position, if it has a cost index.
    func home(latitude: Double, longitude: Double) -> StatlasCityContext? {
        let points = bundledPoints
        let match = StatlasCityContext.match(points: points, latitude: latitude, longitude: longitude, countryCode: nil)
        return match?.cost != nil ? match : nil
    }
    func context(city: String, countryCode: String?, latitude: Double, longitude: Double) async throws -> StatlasCityContext? {
        if let cached = memory["https://statlas.net/api/map?metric=safety-index"], Date().timeIntervalSince(cached.savedAt) < lifetime,
           let map = try? JSONDecoder().decode(StatlasMapResponse.self, from: cached.data),
           let match = StatlasCityContext.match(points: map.points, latitude: latitude, longitude: longitude, countryCode: countryCode, city: city) {
            return match
        }
        // Open-data fallback renders immediately; refresh is coalesced by the actor.
        if let match = StatlasCityContext.match(points: bundledPoints, latitude: latitude, longitude: longitude, countryCode: countryCode, city: city) {
            Task { _ = try? await data(path: "/api/map", query: [.init(name: "metric", value: "safety-index")]) }
            return match
        }
        let mapData = try? await data(path: "/api/map", query: [.init(name: "metric", value: "safety-index")])
        let map = mapData.flatMap { try? JSONDecoder().decode(StatlasMapResponse.self, from: $0) }
        let points = map?.points ?? bundledPoints
        if let match = StatlasCityContext.match(points: points, latitude: latitude, longitude: longitude, countryCode: countryCode, city: city) { return match }
        guard countryCode != nil, !city.isEmpty else { return nil }
        let search = try JSONDecoder().decode(StatlasSearchResponse.self, from: await data(path: "/api/v1/cities", query: [.init(name: "q", value: city), .init(name: "limit", value: "20")]))
        return StatlasCityContext.match(cities: search.cities, name: city, countryCode: countryCode)
    }
}

struct StatlasCityCard: View {
    let city: String
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    @State private var context: StatlasCityContext?
    @State private var facts: CountryFacts?
    @State private var costRank: Double?
    @State private var home: StatlasCityContext?
    @State private var loading = true
    private var requestID: String { "\(city)|\(countryCode ?? "")|\(latitude)|\(longitude)" }
    var body: some View {
        StatlasContextContent(context: context, facts: facts, costRank: costRank, home: home, loading: loading)
            .task(id: requestID) {
                context = nil; facts = nil; costRank = nil; home = nil; loading = true
                let code = countryCode
                async let country: CountryFacts? = { guard let code else { return nil }; return await CityFactsRepository.shared.facts(countryCode: code) }()
                let result = try? await StatlasRepository.shared.context(city: city, countryCode: countryCode, latitude: latitude, longitude: longitude)
                var rank: Double?
                if let cost = result?.cost { rank = await StatlasRepository.shared.costPercentile(cost) }
                let loaded = await country
                var homeCity: StatlasCityContext?
                if let origin = HomeCityStore.coordinate { homeCity = await StatlasRepository.shared.home(latitude: origin.latitude, longitude: origin.longitude) }
                guard !Task.isCancelled else { return }
                context = result; costRank = rank; facts = loaded; home = homeCity; loading = false
            }
    }
}

/// Safety and prices from official sources, with the city's own cost rank when known.
struct StatlasContextContent: View {
    @Environment(\.openURL) private var openURL
    let context: StatlasCityContext?
    let facts: CountryFacts?
    let costRank: Double?
    var home: StatlasCityContext? = nil
    let loading: Bool
    /// Cost of living here against the traveler's own city (their city = 100%), when both are listed.
    private var homeRatio: Double? {
        guard let here = context?.cost, let base = home?.cost, base > 0, here >= 0 else { return nil }
        return here / base
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Good to know").font(Sketch.text(16, "Bold", relativeTo: .headline))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            if let level = facts?.advisoryLevel {
                InsightBar(title: "Safety", value: Double(5 - level) * 25, band: advisoryBand(level),
                           color: level <= 1 ? Sketch.sage : level == 2 ? Sketch.ochre : Sketch.coral, symbol: "shield.lefthalf.filled",
                           valueText: "Level \(level) of 4")
            }
            if let ratio = homeRatio, let home {
                InsightBar(title: "Everyday prices", value: min(100, ratio / 1.3 * 100), band: priceBand(ratio), color: Sketch.clay,
                           symbol: "eurosign.circle", valueText: "\(Int((ratio * 100).rounded()))% of \(home.name)")
            } else if let price = facts?.priceLevel {
                InsightBar(title: "Everyday prices", value: min(100, price / 1.3 * 100), band: priceBand(price), color: Sketch.clay,
                           symbol: "eurosign.circle", valueText: "\(Int((price * 100).rounded()))% of US")
            }
            if let rank = costRank {
                HStack(spacing: 10) {
                    Image(systemName: "building.2").foregroundStyle(Sketch.plum).frame(width: 22)
                    Text(rank >= 0.5 ? "Pricier than \(Int(rank * 100))% of 3,000 cities" : "Cheaper than \(Int((1 - rank) * 100))% of 3,000 cities")
                        .font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                }
            }
            if !loading && facts?.advisoryLevel == nil && facts?.priceLevel == nil && costRank == nil {
                Text("No reliable data for this place yet.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
            }
            if facts?.advisoryLevel != nil || facts?.priceLevel != nil || homeRatio != nil {
                Text("Safety is the US State Department’s advisory for the whole country. " + (homeRatio != nil
                     ? "Prices compare STATLAS cost of living with \(home?.name ?? "your city"), where you are, which counts as 100%."
                     : "Prices are the World Bank’s \(facts?.priceYear ?? "latest") price level, US = 100%."))
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                if let link = facts?.advisoryURL { Button("Read the advisory") { openURL(link) }.accessibilityAddTraits(.isLink) }
                if costRank != nil { Button("City rank: STATLAS") { openURL(URL(string: "https://statlas.net/methodology")!) }.accessibilityAddTraits(.isLink) }
            }
            .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).buttonStyle(.plain).foregroundStyle(Sketch.inkFaint)
        }
        .padding(18).sketchCard(padding: 0)
    }
    private func advisoryBand(_ level: Int) -> String {
        switch level { case 1: "Normal care"; case 2: "Extra caution"; case 3: "Reconsider travel"; default: "Do not travel" }
    }
    private func priceBand(_ v: Double) -> String {
        v >= 1.0 ? "Expensive" : v >= 0.75 ? "Pricey" : v >= 0.5 ? "Moderate" : "Cheap"
    }
}

struct InsightBar: View {
    let title: String
    let value: Double?
    let band: String
    let color: Color
    let symbol: String
    var valueText: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
                Text(title).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                Spacer()
                Text(band).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(color)
                if let valueText { Text(valueText).font(Sketch.text(13, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Sketch.inkSoft) }
                else if let value { Text(Int(value.rounded()).formatted()).font(Sketch.text(13, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Sketch.inkSoft) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Sketch.ink.opacity(0.07))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(100, max(2, value ?? 0)) / 100))
                }
            }
            .frame(height: 6)
            .padding(.leading, 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(band)\(valueText.map { ", \($0)" } ?? "")")
    }
}

/// Trips, pins, saves and visits the traveler already has in a city.
struct CityHoldingsCard: View {
    let trips: Int
    let pins: Int
    let saves: Int
    let visited: Date?
    var open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Yours here").font(Sketch.text(16, "Bold", relativeTo: .headline))
                Spacer()
                Button("Open in Library", action: open).font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
            }
            HStack(spacing: 8) {
                chip(.suitcase, trips, "trip", "trips", Sketch.plum)
                chip(.pin, pins, "pin", "pins", Sketch.coral)
                chip(.heart, saves, "saved", "saved", Sketch.clay)
            }
            if let visited {
                Label("Been here · \(visited.formatted(.dateTime.month(.wide).year()))", systemImage: "checkmark.seal.fill")
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.ochre)
            }
        }
        .sketchCard(padding: 16)
    }
    @ViewBuilder private func chip(_ icon: TrippyIcon, _ count: Int, _ one: String, _ many: String, _ color: Color) -> some View {
        if count > 0 {
            HStack(spacing: 6) {
                TrippyIconView(icon: icon, size: 14, weight: 2.2).foregroundStyle(color)
                Text("\(count) \(count == 1 ? one : many)").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(color.opacity(0.12)))
        }
    }
}
struct StatlasMetricTile: View {
    let title: String
    let value: Double?
    let suffix: String
    let note: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + suffix } ?? "—")
                .font(.custom("PlusJakartaSans-Bold", size: 24)).monospacedDigit()
            Text(value == nil ? "Not available" : note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).librarySurface(radius: 18, inset: true)
    }
}
struct NativeLookAroundCard: View {
    let latitude: Double
    let longitude: Double
    @State private var scene: MKLookAroundScene?
    var body: some View {
        Group {
            if let scene {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Look Around", systemImage: "binoculars").font(.headline)
                    LookAroundPreview(initialScene: scene).frame(height: 190).clipShape(.rect(cornerRadius: 20))
                }
            }
        }.task(id: "\(latitude)|\(longitude)") {
            scene = nil
            let result = try? await MKLookAroundSceneRequest(coordinate: .init(latitude: latitude, longitude: longitude)).scene
            if !Task.isCancelled { scene = result }
        }
    }
}

struct NativeMapCardsModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.mapFeatureSelectionAccessory(enabled ? .automatic : nil) }
        else { content }
    }
}
