import Foundation
import CoreLocation

// MARK: - Weekly opening hours
//
// Two sources: Google (already on planner places at no extra request, or a
// small paid lookup for your own pins) and OpenStreetMap (free, partial).
// "Open now" is worked out on the phone in the place's own time zone.

struct OpeningHours: Codable, Hashable {
    /// One open stretch in the week; days 0 = Sunday … 6 = Saturday, minutes from midnight.
    struct Span: Codable, Hashable {
        var openDay: Int
        var openMinute: Int
        var closeDay: Int
        var closeMinute: Int
    }
    var spans: [Span] = []
    var alwaysOpen = false
    var utcOffsetMinutes: Int?
    var source = "google"

    func isOpen(at date: Date = .now, timeZone: TimeZone? = nil) -> Bool {
        if alwaysOpen { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? utcOffsetMinutes.flatMap { TimeZone(secondsFromGMT: $0 * 60) } ?? .current
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let now = ((parts.weekday ?? 1) - 1) * 1440 + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let week = 7 * 1440
        return spans.contains { span in
            let start = span.openDay * 1440 + span.openMinute
            var end = span.closeDay * 1440 + span.closeMinute
            if end <= start { end += week }
            return (start..<end).contains(now) || (start..<end).contains(now + week)
        }
    }

    /// Google's `periods` (as the planner and the bridge pass them on).
    static func google(_ json: [String: Any]) -> OpeningHours? {
        if json["always_open"] as? Bool == true { return OpeningHours(alwaysOpen: true, utcOffsetMinutes: json["utc_offset_minutes"] as? Int) }
        guard let periods = json["periods"] as? [[String: Any]], !periods.isEmpty else { return nil }
        var spans: [Span] = []
        for period in periods {
            guard let open = period["open"] as? [String: Any], let openDay = open["day"] as? Int else { return nil }
            let openMinute = (open["hour"] as? Int ?? 0) * 60 + (open["minute"] as? Int ?? 0)
            guard let close = period["close"] as? [String: Any], let closeDay = close["day"] as? Int else {
                // Google writes 24/7 as a single open with no close.
                return OpeningHours(alwaysOpen: true, utcOffsetMinutes: json["utc_offset_minutes"] as? Int)
            }
            spans.append(Span(openDay: openDay, openMinute: openMinute, closeDay: closeDay,
                              closeMinute: (close["hour"] as? Int ?? 0) * 60 + (close["minute"] as? Int ?? 0)))
        }
        return OpeningHours(spans: spans, utcOffsetMinutes: json["utc_offset_minutes"] as? Int)
    }

    /// The common part of OpenStreetMap's `opening_hours` syntax:
    /// "Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off", "24/7", "Tu-Su 12:00-15:00,19:00-23:30".
    /// Seasonal or date-specific rules return nil rather than a guess.
    static func osm(_ raw: String) -> OpeningHours? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "24/7" { return OpeningHours(alwaysOpen: true, source: "osm") }
        let names = ["Su": 0, "Mo": 1, "Tu": 2, "We": 3, "Th": 4, "Fr": 5, "Sa": 6]
        var week: [[ClosedRange<Int>]] = Array(repeating: [], count: 7)
        var sawAnyRule = false
        let rules = text.replacingOccurrences(of: "||", with: ";").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for rule in rules where !rule.isEmpty {
            // Date-specific rules ("Dec 24 …", "Apr-Oct …", "week 1-10 …") are exceptions or
            // seasons: skip them and keep the weekly pattern. Anything stranger is unreadable.
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if months.contains(where: { rule.hasPrefix($0) }) || rule.hasPrefix("week") || rule.hasPrefix("easter") { continue }
            if ["\"", "[", "sunrise", "sunset"].contains(where: rule.contains) { return nil }
            var rest = Substring(rule)
            var days = Set(0..<7)
            // Weekday selector: "Mo-Fr,Su" (PH/SH entries are ignored).
            if let first = rest.split(separator: " ").first, first.first?.isLetter == true,
               first.split(separator: ",").allSatisfy({ item in item.split(separator: "-").allSatisfy { names[String($0)] != nil || $0 == "PH" || $0 == "SH" } }) {
                var selected = Set<Int>()
                for item in first.split(separator: ",") {
                    let ends = item.split(separator: "-").compactMap { names[String($0)] }
                    if ends.count == 1 { selected.insert(ends[0]) }
                    else if ends.count == 2 {
                        var d = ends[0]
                        while true { selected.insert(d); if d == ends[1] { break }; d = (d + 1) % 7 }
                    }
                }
                if selected.isEmpty { continue }   // a holiday-only rule
                days = selected
                rest = rest.dropFirst(first.count).drop { $0 == " " }
            }
            let times = rest.trimmingCharacters(in: .whitespaces)
            if times == "off" || times == "closed" { for d in days { week[d] = [] }; sawAnyRule = true; continue }
            var ranges: [ClosedRange<Int>] = []
            for piece in times.split(separator: ",") {
                let ends = piece.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "-24:00").split(separator: "-")
                guard ends.count == 2, let a = minutes(String(ends[0])), var b = minutes(String(ends[1])) else { return nil }
                if b <= a { b += 1440 }          // past midnight
                ranges.append(a...b)
            }
            guard !ranges.isEmpty else { return nil }
            for d in days { week[d] = ranges }   // later rules override earlier ones, as in OSM
            sawAnyRule = true
        }
        guard sawAnyRule else { return nil }
        var spans: [Span] = []
        for (day, ranges) in week.enumerated() {
            for range in ranges {
                spans.append(Span(openDay: day, openMinute: range.lowerBound,
                                  closeDay: (day + range.upperBound / 1440) % 7, closeMinute: range.upperBound % 1440))
            }
        }
        return OpeningHours(spans: spans, source: "osm")
    }

    private static func minutes(_ clock: String) -> Int? {
        let parts = clock.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...48).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

// MARK: - Looking hours up

struct OpeningHoursQuery: Hashable {
    let key: String
    let name: String
    let latitude: Double
    let longitude: Double
    let googlePlaceID: String?
}

/// Finds hours for map pins: OpenStreetMap first (free; one area request per city,
/// fetched in the background when a trip opens), then Google only for what's left,
/// only when "Open now" is switched on, and capped per lookup. Results stay on the
/// phone for a week; places a source had no hours for aren't asked again for 3 days.
@MainActor final class OpeningHoursStore: ObservableObject {
    static let shared = OpeningHoursStore()
    @Published private(set) var hours: [String: OpeningHours] = [:]
    @Published private(set) var loading = false
    @Published private(set) var revision = 0
    private var osmMisses: [String: Date] = [:]
    private var googleMisses: [String: Date] = [:]
    private var found: [String: Date] = [:]
    private let file: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("opening-hours-v2.json")
    private static let googleCapPerLookup = 30

    private struct Stored: Codable { var hours: [String: OpeningHours]; var found: [String: Date]; var osmMisses: [String: Date]; var googleMisses: [String: Date] }

    init() {
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            let now = Date()
            found = stored.found.filter { now.timeIntervalSince($0.value) < 7 * 86400 }
            hours = stored.hours.filter { found[$0.key] != nil }
            osmMisses = stored.osmMisses.filter { now.timeIntervalSince($0.value) < 3 * 86400 }
            googleMisses = stored.googleMisses.filter { now.timeIntervalSince($0.value) < 3 * 86400 }
        }
    }

    func lookup(_ queries: [OpeningHoursQuery], google useGoogle: Bool, bridgeBaseURL: String = "", token: String = "") async {
        while loading { try? await Task.sleep(for: .milliseconds(300)); if Task.isCancelled { return } }
        loading = true
        defer { loading = false; revision += 1; save() }
        let now = Date()
        let forOSM = queries.filter { hours[$0.key] == nil && osmMisses[$0.key] == nil }
        if !forOSM.isEmpty {
            let answered = await openStreetMap(forOSM)
            for query in forOSM where hours[query.key] == nil && answered.contains(query.key) { osmMisses[query.key] = now }
            revision += 1
        }
        guard useGoogle, !bridgeBaseURL.isEmpty, !token.isEmpty else { return }
        let forGoogle = Array(queries.filter { hours[$0.key] == nil && $0.googlePlaceID != nil && googleMisses[$0.key] == nil }.prefix(Self.googleCapPerLookup))
        for chunk in stride(from: 0, to: forGoogle.count, by: 10).map({ Array(forGoogle.dropFirst($0).prefix(10)) }) {
            if await google(chunk, baseURL: bridgeBaseURL, token: token) {
                for query in chunk where hours[query.key] == nil { googleMisses[query.key] = now }
            }
        }
    }

    private func store(_ key: String, _ value: OpeningHours) { hours[key] = value; found[key] = .now }

    /// Public Overpass servers are often slow; try the main one, then a second.
    private static let overpassServers = ["https://overpass-api.de/api/interpreter", "https://z.overpass-api.de/api/interpreter"]

    /// One bounding-box request per ~10 km area (at most four), matched by name nearby.
    /// Returns the keys whose area answered.
    private func openStreetMap(_ queries: [OpeningHoursQuery]) async -> Set<String> {
        let areas = Dictionary(grouping: queries) { "\(Int(($0.latitude * 10).rounded())):\(Int(($0.longitude * 10).rounded()))" }
        var answered = Set<String>()
        for group in areas.values.sorted(by: { $0.count > $1.count }).prefix(4) {
            let pad = 0.003
            let south = group.map(\.latitude).min()! - pad, north = group.map(\.latitude).max()! + pad
            let west = group.map(\.longitude).min()! - pad, east = group.map(\.longitude).max()! + pad
            let body = String(format: "[out:json][timeout:50];nwr[\"opening_hours\"][\"name\"](%.5f,%.5f,%.5f,%.5f);out tags center;", south, west, north, east)
            guard let elements = await overpass(body) else { continue }
            answered.formUnion(group.map(\.key))
            match(group, elements)
        }
        return answered
    }

    private func overpass(_ body: String) async -> [[String: Any]]? {
        for server in Self.overpassServers {
            guard let url = URL(string: server) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("Trippy/1.0 (iOS travel planner)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ("data=" + (body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)
            if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let elements = root["elements"] as? [[String: Any]] {
                return elements
            }
        }
        return nil
    }

    private func match(_ queries: [OpeningHoursQuery], _ elements: [[String: Any]]) {
        struct Feature { let name: String; let location: CLLocation; let hours: String }
        func folded(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber } }
        let features: [Feature] = elements.compactMap { element in
            guard let tags = element["tags"] as? [String: String], let hours = tags["opening_hours"], let name = tags["name"] else { return nil }
            let center = element["center"] as? [String: Double]
            guard let lat = (element["lat"] as? Double) ?? center?["lat"], let lon = (element["lon"] as? Double) ?? center?["lon"] else { return nil }
            return Feature(name: folded(name), location: CLLocation(latitude: lat, longitude: lon), hours: hours)
        }
        for query in queries {
            let here = CLLocation(latitude: query.latitude, longitude: query.longitude)
            let name = folded(query.name)
            guard name.count >= 3 else { continue }
            // Same name (either contains the other) within 80 m; never a nearest-guess.
            let match = features.filter { feature in
                feature.name.count >= 3 && (feature.name.contains(name) || name.contains(feature.name)) && feature.location.distance(from: here) < 80
            }.min { $0.location.distance(from: here) < $1.location.distance(from: here) }
            if let match, let parsed = OpeningHours.osm(match.hours) { store(query.key, parsed) }
        }
    }

    private func google(_ queries: [OpeningHoursQuery], baseURL: String, token: String) async -> Bool {
        guard var components = URLComponents(string: baseURL + "/api/places/hours") else { return false }
        components.queryItems = [URLQueryItem(name: "ids", value: queries.compactMap(\.googlePlaceID).joined(separator: ","))]
        guard let url = components.url else { return false }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byID = root["hours"] as? [String: [String: Any]] else { return false }
        for query in queries {
            guard let id = query.googlePlaceID, let json = byID[id], let parsed = OpeningHours.google(json) else { continue }
            store(query.key, parsed)
        }
        return true
    }

    private func save() {
        let stored = Stored(hours: hours, found: found, osmMisses: osmMisses, googleMisses: googleMisses)
        if let data = try? JSONEncoder().encode(stored) { try? data.write(to: file, options: .atomic) }
    }
}
