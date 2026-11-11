import Foundation
import CoreLocation

// MARK: - Read-only plan model
//
// Built from the `trippy-research-v1` document the planner returns. Nothing is
// invented here: unknown prices stay nil and are shown as "to check".

struct GuidePlace: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let description: String
    let why: String
    let address: String?
    let url: URL?
    let coordinate: CLLocationCoordinate2D?
    let priceMin: Double?
    let priceMax: Double?
    let rating: Double?
    let ratingScale: Double?
    let reviewCount: Int?
    let reservationRequired: Bool?
    let tags: [String]
    /// A short reason backed by data (a guide line, fame, rating or "Saved by you"), no model needed.
    var reason = ""
    /// The traveller's own: a pin, a save, a note or a video of theirs brought it into the plan.
    var personal = false
    /// How many videos (theirs or the community's) recommend it.
    var videoCount = 0

    static func == (a: GuidePlace, b: GuidePlace) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var isFood: Bool { ["food", "coffee", "bar", "nightlife"].contains(category) }
    var isSight: Bool { ["attraction", "museum", "sights", "landmark"].contains(category) }
    /// Number of Wikipedia language editions, when the free city layer knows it.
    var fame: Int { tags.compactMap { $0.hasPrefix("notable:") ? Int($0.dropFirst(8)) : nil }.max() ?? 0 }
    var fromVideo: Bool { tags.contains("source_recommended") }
    var fromWikivoyage: Bool { tags.contains("wikivoyage_listed") }

    var symbol: String {
        switch category {
        case "food": "fork.knife"
        case "coffee": "cup.and.saucer"
        case "bar", "nightlife": "wineglass"
        case "museum": "building.columns"
        case "nature", "outdoors": "leaf"
        case "shopping": "bag"
        default: "star"
        }
    }

    var categoryLabel: String {
        switch category {
        case "food": "Food"; case "coffee": "Coffee"; case "bar", "nightlife": "Drinks"; case "museum": "Museum"
        case "nature", "outdoors": "Park"; case "shopping": "Shopping"; default: "Sight"
        }
    }

    /// Short reading text: the first sentence, without the "Wikivoyage:" prefix.
    /// Why to go, when the plan gave a real reason. Stock phrases that only say where the record came from
    /// ("from the local catalog") are not reasons and are dropped.
    var plainWhy: String {
        let stock = ["Από τον τοπικό κατάλογο", "Από τη βιβλιοθήκη σου", "Από την κοινότητα", "Προτείνεται από το Wikivoyage",
                     "Προτείνεται σε ταξιδιωτικό βίντεο", "From the local catalog"]
        for text in [reason, why] where !text.isEmpty && !stock.contains(where: text.hasPrefix) { return text }
        return ""
    }

    var shortDescription: String {
        var text = description
        for prefix in ["Wikivoyage: ", "Wikidata: ", "Σχόλιο δημιουργού: "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        if let end = text.range(of: ". ") { text = String(text[..<end.lowerBound]) + "." }
        return text.count > 160 ? String(text.prefix(157)) + "…" : text
    }
}

struct GuideStop: Identifiable, Hashable {
    var id: String { placeID }
    let placeID: String
    let time: String
    let durationMinutes: Int
    let travelMinutes: Int?
    let alternatives: [String]
    var why = ""
    var tip = ""
    var fromBase = false
    /// Sights visited together with this one (the Arch of Constantine with the Colosseum).
    var includes: [String] = []
}

struct GuideDay: Identifiable, Hashable {
    var id: String { date }
    let index: Int
    let date: String
    let stops: [GuideStop]
    var theme = ""
    var summary = ""
    var areaIDs: [String] = []
}

/// Where the traveller sleeps; every day starts there.
struct GuideBase: Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// A part of the city the planner grouped sights into, with its character.
struct GuideArea: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let placeIDs: [String]
    let plannedIDs: [String]
    let days: [String]
    let importance: Double
    let character: String
    let vibe: String
    let touristy: Int?
    let price: Int?
    let safety: Int?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// What the city's food and nightlife scene is, from its guide, with a few places to start.
struct GuideScene: Hashable {
    struct Pick: Identifiable, Hashable {
        var id: String { placeID }
        let placeID: String
        let name: String
        let category: String
        let reason: String
        let planned: Bool
    }
    struct Part: Hashable {
        let text: String
        let picks: [Pick]
    }
    var eat: Part?
    var drink: Part?
    var sourceURL: URL?
    var isEmpty: Bool { eat == nil && drink == nil }
}

struct GuideInfoRow: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let date: String?
    let url: URL?
    let price: Double?
}

struct GuideModel {
    var places: [String: GuidePlace] = [:]
    var days: [GuideDay] = []
    var tickets: [GuideInfoRow] = []
    var transport: [GuideInfoRow] = []
    var calendar: [GuideInfoRow] = []
    var events: [GuideInfoRow] = []
    var bookingTasks: [GuideInfoRow] = []
    var gaps: [String] = []
    var areas: [GuideArea] = []
    var base: GuideBase?
    var scene = GuideScene()

    var orderedPlaces: [GuidePlace] { places.values.sorted { ($0.fame, $0.name) > ($1.fame, $1.name) } }

    init() {}

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func str(_ v: Any?) -> String? { (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        func url(_ v: Any?) -> URL? { str(v).flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil } }
        func list(_ key: String) -> [[String: Any]] { root[key] as? [[String: Any]] ?? [] }

        for p in list("places") {
            guard let id = str(p["id"]), let name = str(p["name"]) else { continue }
            let c = p["coordinates"] as? [String: Any]
            let coordinate = num(c?["latitude"]).flatMap { lat in num(c?["longitude"]).map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
            let price = p["price"] as? [String: Any]
            let rating = p["rating"] as? [String: Any]
            places[id] = GuidePlace(id: id, name: name, category: str(p["category"]) ?? "attraction",
                                    description: str(p["description"]) ?? "", why: str(p["why_recommended"]) ?? "",
                                    address: str(p["address"]), url: url(p["official_url"]), coordinate: coordinate,
                                    priceMin: num(price?["min"]), priceMax: num(price?["max"]),
                                    rating: num(rating?["value"]), ratingScale: num(rating?["scale"]),
                                    reviewCount: num(rating?["review_count"]).map { Int($0) },
                                    reservationRequired: p["reservation_required"] as? Bool, tags: p["tags"] as? [String] ?? [],
                                    reason: str(p["reason"]) ?? "")
            let nodes = p["library_node_ids"] as? [String] ?? []
            places[id]?.personal = (num(p["personal_priority"]) ?? 0) > 50
            places[id]?.videoCount = nodes.filter { $0.hasPrefix("community:") || $0.hasPrefix("video:") }.count
        }
        let itinerary = root["itinerary"] as? [String: Any]
        for (i, d) in ((itinerary?["days"] as? [[String: Any]]) ?? []).enumerated() {
            let stops = ((d["stops"] as? [[String: Any]]) ?? []).compactMap { s -> GuideStop? in
                guard let id = str(s["place_id"]), places[id] != nil else { return nil }
                return GuideStop(placeID: id, time: str(s["time"]) ?? "", durationMinutes: Int(num(s["duration_minutes"]) ?? 60),
                                 travelMinutes: num(s["travel_time_minutes"]).map { Int($0) }, alternatives: s["alternatives"] as? [String] ?? [],
                                 why: str(s["why"]) ?? "", tip: str(s["tip"]) ?? "", fromBase: str(s["travel_from"]) == "base",
                                 includes: (s["includes"] as? [String] ?? []).filter { places[$0] != nil })
            }
            // The engine's placeholder title is not a theme; the notes pass writes real ones.
            let theme = str(d["theme"]).flatMap { ["Η ημέρα σου", "Your day"].contains($0) ? nil : $0 } ?? ""
            days.append(GuideDay(index: i, date: str(d["date"]) ?? "Day \(i + 1)", stops: stops, theme: theme, summary: str(d["summary"]) ?? "",
                                 areaIDs: d["areas"] as? [String] ?? []))
        }
        if let raw = root["scene"] as? [String: Any] {
            func part(_ key: String) -> GuideScene.Part? {
                guard let p = raw[key] as? [String: Any] else { return nil }
                let picks = (p["picks"] as? [[String: Any]] ?? []).compactMap { x -> GuideScene.Pick? in
                    guard let id = str(x["place_id"]), let name = str(x["name"]) else { return nil }
                    return .init(placeID: id, name: name, category: str(x["category"]) ?? "bar", reason: str(x["reason"]) ?? "",
                                 planned: x["planned"] as? Bool ?? false)
                }
                let text = str(p["text"]) ?? ""
                return text.isEmpty && picks.isEmpty ? nil : .init(text: text, picks: picks)
            }
            scene = GuideScene(eat: part("eat"), drink: part("drink"), sourceURL: url(raw["source_url"]))
        }
        if let b = itinerary?["base"] as? [String: Any], let lat = num(b["latitude"]), let lon = num(b["longitude"]) {
            base = GuideBase(name: str(b["name"]) ?? "Your stay", latitude: lat, longitude: lon)
        }
        areas = list("areas").compactMap { a in
            guard let id = str(a["id"]), let lat = num(a["latitude"]), let lon = num(a["longitude"]) else { return nil }
            func score(_ k: String) -> Int? { num(a[k]).map { Int($0) }.flatMap { (1...5).contains($0) ? $0 : nil } }
            return GuideArea(id: id, name: str(a["name"]) ?? "Area", latitude: lat, longitude: lon,
                             placeIDs: a["place_ids"] as? [String] ?? [], plannedIDs: a["planned_place_ids"] as? [String] ?? [],
                             days: a["days"] as? [String] ?? [], importance: num(a["importance"]) ?? 0,
                             character: str(a["character"]) ?? "", vibe: str(a["vibe"]) ?? "",
                             touristy: score("touristy"), price: score("price"), safety: score("safety"))
        }
        tickets = list("ticket_options").enumerated().map { i, t in
            GuideInfoRow(id: str(t["id"]) ?? "ticket-\(i)", title: str(t["name"]) ?? "Ticket", detail: str(t["notes"]) ?? "",
                         date: nil, url: url(t["booking_url"]), price: num(t["price_per_person_eur"]))
        }
        transport = list("transport_options").enumerated().map { i, t in
            let price = t["price"] as? [String: Any]
            return GuideInfoRow(id: str(t["id"]) ?? "transport-\(i)", title: str(t["name"]) ?? "Transport",
                                detail: [str(t["best_for"]), (t["limitations"] as? [String])?.joined(separator: " · ")].compactMap { $0 }.joined(separator: " — "),
                                date: nil, url: url(t["official_url"]), price: num(price?["min"]))
        }
        calendar = list("calendar_checks").enumerated().map { i, c in
            GuideInfoRow(id: "cal-\(i)", title: str(c["status"]) ?? "", detail: str(c["details"]) ?? "", date: str(c["date"]), url: nil, price: nil)
        }
        events = list("events").enumerated().map { i, e in
            GuideInfoRow(id: str(e["id"]) ?? "event-\(i)", title: str(e["name"]) ?? "Event",
                         detail: [str(e["venue"]), str(e["description"])].compactMap { $0 }.joined(separator: " · "),
                         date: [str(e["date_start"]), str(e["date_end"])].compactMap { $0 }.joined(separator: " – ").nilIfEmpty,
                         url: url(e["official_url"]), price: nil)
        }
        bookingTasks = list("booking_tasks").enumerated().map { i, t in
            GuideInfoRow(id: str(t["id"]) ?? "task-\(i)", title: str(t["title"]) ?? str(t["name"]) ?? str(t["task"]) ?? "Booking",
                         detail: str(t["details"]) ?? str(t["notes"]) ?? "", date: str(t["date"]), url: url(t["url"]), price: nil)
        }
        gaps = ((root["quality_report"] as? [String: Any])?["gaps"] as? [String]) ?? []
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - The traveler's edits

struct GuideFare: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var count: Int
}

struct GuideCostLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var amount: Double?
}

struct GuideFlight: Codable, Hashable {
    var outbound = ""      // e.g. "Sat 5 Dec · ATH 16:40 → BCN 18:45 · A3712"
    var inbound = ""
    var stayName = ""
    var stayAddress = ""
    /// Where the stay is, found on the phone from its name; the map and each day start there.
    var stayLatitude: Double? = nil
    var stayLongitude: Double? = nil
    var arrivalTime = ""   // "18:45" — also sent to the planner
    var departureTime = ""
}

enum GuideSection: String, CaseIterable, Codable, Identifiable {
    case glance, map, areas, calendar, days, book, tickets, transport, food, budget, checklist, unknowns
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glance: "Overview"; case .map: "Map"; case .areas: "Areas"; case .calendar: "Holidays"
        case .days: "Day by day"; case .book: "Book ahead"; case .tickets: "Tickets"
        case .transport: "Getting around"; case .food: "Food & nightlife"; case .budget: "Budget"
        case .checklist: "Checklist"; case .unknowns: "Not yet checked"
        }
    }
    var symbol: String {
        switch self {
        case .glance: "rectangle.grid.1x2"; case .map: "map"; case .areas: "square.grid.3x3.square"; case .calendar: "calendar"; case .days: "clock"
        case .book: "bookmark"; case .tickets: "ticket"; case .transport: "tram"; case .food: "fork.knife"
        case .budget: "eurosign.circle"; case .checklist: "checklist"; case .unknowns: "questionmark.circle"
        }
    }
}

struct GuideEdits: Codable, Equatable {
    var sections: [GuideSection] = GuideSection.allCases
    var hidden: Set<GuideSection> = []
    var pigment = "clay"
    var flight = GuideFlight()
    var fares: [GuideFare] = []
    /// place IDs per date, when the traveler reordered, added or removed stops.
    var order: [String: [String]] = [:]
    var times: [String: String] = [:]            // "date|placeID" → "HH:MM"
    var notes: [String: String] = [:]            // "date|placeID" → note
    var dayTitles: [String: String] = [:]
    var booked: Set<String> = []
    var prices: [String: [String: Double]] = [:] // placeID → fareID.uuidString → €
    var transportLines: [GuideCostLine] = [GuideCostLine(label: "From the airport"), GuideCostLine(label: "To the airport"),
                                           GuideCostLine(label: "Metro and bus cards")]
    var stayTotal: Double?
    var foodPerPersonDay: Double = 30
    var extras: Double?
    var checklistDone: Set<String> = []
    var customChecklist: [String] = []
    /// Meal and coffee blocks: "date|itemID" → chosen place id ("" = decide later).
    var slotPicks: [String: String] = [:]
    /// Places chosen from the nearby pool that the plan itself didn't include.
    var extraPlaces: [String: GuideSavedPlace] = [:]

    init() {}

    // Decoding tolerates sections added in later versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = GuideEdits()
        var sections = (try? c.decode([String].self, forKey: .sections))?.compactMap(GuideSection.init(rawValue:)) ?? base.sections
        // New sections land where they belong (after the one before them), not at the end.
        for (index, section) in GuideSection.allCases.enumerated() where !sections.contains(section) {
            let previous = index > 0 ? GuideSection.allCases[index - 1] : nil
            let at = previous.flatMap { sections.firstIndex(of: $0) }.map { $0 + 1 } ?? sections.count
            sections.insert(section, at: at)
        }
        self.sections = sections
        hidden = Set((try? c.decode([String].self, forKey: .hidden))?.compactMap(GuideSection.init(rawValue:)) ?? [])
        pigment = (try? c.decode(String.self, forKey: .pigment)) ?? base.pigment
        flight = (try? c.decode(GuideFlight.self, forKey: .flight)) ?? base.flight
        fares = (try? c.decode([GuideFare].self, forKey: .fares)) ?? []
        order = (try? c.decode([String: [String]].self, forKey: .order)) ?? [:]
        times = (try? c.decode([String: String].self, forKey: .times)) ?? [:]
        notes = (try? c.decode([String: String].self, forKey: .notes)) ?? [:]
        dayTitles = (try? c.decode([String: String].self, forKey: .dayTitles)) ?? [:]
        booked = (try? c.decode(Set<String>.self, forKey: .booked)) ?? []
        prices = (try? c.decode([String: [String: Double]].self, forKey: .prices)) ?? [:]
        transportLines = (try? c.decode([GuideCostLine].self, forKey: .transportLines)) ?? base.transportLines
        stayTotal = try? c.decode(Double.self, forKey: .stayTotal)
        foodPerPersonDay = (try? c.decode(Double.self, forKey: .foodPerPersonDay)) ?? base.foodPerPersonDay
        extras = try? c.decode(Double.self, forKey: .extras)
        checklistDone = (try? c.decode(Set<String>.self, forKey: .checklistDone)) ?? []
        customChecklist = (try? c.decode([String].self, forKey: .customChecklist)) ?? []
        slotPicks = (try? c.decode([String: String].self, forKey: .slotPicks)) ?? [:]
        extraPlaces = (try? c.decode([String: GuideSavedPlace].self, forKey: .extraPlaces)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case sections, hidden, pigment, flight, fares, order, times, notes, dayTitles, booked, prices, transportLines
        case stayTotal, foodPerPersonDay, extras, checklistDone, customChecklist, slotPicks, extraPlaces
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sections.map(\.rawValue), forKey: .sections)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        try c.encode(pigment, forKey: .pigment); try c.encode(flight, forKey: .flight); try c.encode(fares, forKey: .fares)
        try c.encode(order, forKey: .order); try c.encode(times, forKey: .times); try c.encode(notes, forKey: .notes)
        try c.encode(dayTitles, forKey: .dayTitles); try c.encode(booked, forKey: .booked); try c.encode(prices, forKey: .prices)
        try c.encode(transportLines, forKey: .transportLines); try c.encodeIfPresent(stayTotal, forKey: .stayTotal)
        try c.encode(foodPerPersonDay, forKey: .foodPerPersonDay); try c.encodeIfPresent(extras, forKey: .extras)
        try c.encode(checklistDone, forKey: .checklistDone); try c.encode(customChecklist, forKey: .customChecklist)
        try c.encode(slotPicks, forKey: .slotPicks); try c.encode(extraPlaces, forKey: .extraPlaces)
    }
}

enum GuideEditsStore {
    static func key(_ id: UUID) -> String { "trippy.guide.edits.v1.\(id.uuidString)" }
    static func load(_ id: UUID, travelers: Int) -> GuideEdits {
        var edits = UserDefaults.standard.data(forKey: key(id)).flatMap { try? JSONDecoder().decode(GuideEdits.self, from: $0) } ?? GuideEdits()
        if edits.fares.isEmpty { edits.fares = [GuideFare(name: "Adult", count: max(1, travelers))] }
        return edits
    }
    static func save(_ edits: GuideEdits, id: UUID) {
        if let data = try? JSONEncoder().encode(edits) { UserDefaults.standard.set(data, forKey: key(id)) }
    }
    static func delete(_ id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }
}

// MARK: - Calendar helpers

enum GuideDates {
    static let iso: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func date(_ s: String) -> Date? { iso.date(from: s) }
    static func format(_ s: String, _ pattern: String) -> String {
        guard let d = date(s) else { return s }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: d)
    }
    static func weekday(_ s: String) -> String { format(s, "EEE").uppercased() }
    static func dayNumber(_ s: String) -> String { format(s, "dd") }
    static func short(_ s: String) -> String { format(s, "EEE d MMM") }
    static func long(_ s: String) -> String { format(s, "EEEE d MMMM") }
    static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
    }
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
}

struct GuideHoliday: Identifiable, Hashable {
    var id: String { date + name }
    let date: String
    let name: String
}

/// Public holidays from the free Nager.Date service, by the destination's country.
enum GuideHolidayService {
    static func load(destination: String, dates: [String]) async -> [GuideHoliday]? {
        guard !dates.isEmpty, let placemark = try? await CLGeocoder().geocodeAddressString(destination).first,
              let country = placemark.isoCountryCode else { return nil }
        let region = placemark.administrativeArea.map { "\(country)-\($0.uppercased())" }
        var found: [GuideHoliday] = []
        for year in Set(dates.compactMap { $0.split(separator: "-").first.map(String.init) }) {
            guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(country)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            for row in rows {
                guard let date = row["date"] as? String, dates.contains(date) else { continue }
                let counties = row["counties"] as? [String]
                // Regional holidays only count when they cover this region.
                if let counties, let region, !counties.contains(region) { continue }
                found.append(GuideHoliday(date: date, name: (row["name"] as? String) ?? (row["localName"] as? String) ?? "Public holiday"))
            }
        }
        return found.sorted { $0.date < $1.date }
    }
}
