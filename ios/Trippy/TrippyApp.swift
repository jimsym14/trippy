import SwiftUI
import UIKit
import MapKit
import CoreLocation
import AVFoundation
import UniformTypeIdentifiers
import WebKit
import os
import Security

enum TrippyHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum TrippyPerformance {
    private static let started = ProcessInfo.processInfo.systemUptime
    private static let log = Logger(subsystem: "com.dimitrisymeonidis.trippy", category: "Performance")
    static func mark(_ event: String) {
        log.notice("\(event, privacy: .public) +\(ProcessInfo.processInfo.systemUptime - started, format: .fixed(precision: 3))s")
    }
}

@main
struct TrippyApp: App {
    init() {
        TrippyPerformance.mark("app.init")
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-TrippyCostCalculatorDemo`: open the cost calculator straight away, for screenshots.
            if ProcessInfo.processInfo.arguments.contains("-TrippyCostCalculatorDemo") {
                NavigationStack { CostCalculatorView(baseURL: "") }
            } else if ProcessInfo.processInfo.arguments.contains("-TrippyPlannerAdminDemo") {
                PlannerAdminDemo()
            } else { TrippyStartupHost() }
            #else
            TrippyStartupHost()
            #endif
        }
    }
}

// Paint the launch banner before resolving the full app's view metadata.
// The banner continues the system launch screen (same colour, same mark) and
// animates on the render server, so it keeps moving while the app builds below.
private struct TrippyStartupHost: View {
    @State private var mountApp = false
    @State private var ready = false
    @State private var appReady = false
    @State private var shownLongEnough = false
    @AppStorage("trippy.native.darkMode") private var dark = false
    var body: some View {
        ZStack {
            if mountApp { TrippyScreen { TripFlowView() } }
            if !ready {
                TrippySplash(dark: dark)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                    .zIndex(20)
            }
        }
        .task {
            // Let the banner commit its first frame and start its loops, then
            // build the app behind it.
            try? await Task.sleep(for: .milliseconds(30))
            TrippyPerformance.mark("app.mount")
            mountApp = true
            // Long enough to read as an intro rather than a flash on warm launches.
            try? await Task.sleep(for: .seconds(0.7))
            shownLongEnough = true
            finishIfReady()
            // Never hold a usable app behind the banner.
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trippyAppReady)) { _ in
            appReady = true
            finishIfReady()
        }
    }
    private func finishIfReady() { if appReady && shownLongEnough { dismiss() } }
    private func dismiss() {
        guard !ready else { return }
        TrippyPerformance.mark("splash.dismiss")
        withAnimation(.easeOut(duration: 0.32)) { ready = true }
    }
}

// Keep each screen's concrete view type out of the root navigation metadata.
// On device, resolving the combined type crashed in Swift's metadata decoder.
// The closure also defers building an inactive screen until SwiftUI mounts it.
private struct TrippyScreen: View {
    private let content: () -> AnyView
    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self.content = { AnyView(content()) }
    }
    var body: some View { content() }
}

private enum TripStage: Equatable {
    case library
    case brief
    case workspace
}

private enum ResearchLayer: String, CaseIterable, Identifiable {
    case foundation = "Foundation"
    case dateVerification = "Dates"
    case itinerary = "Plan"
    case targetedRefresh = "Search again"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundation: "1 · Discover"
        case .dateVerification: "2 · Check"
        case .itinerary: "3 · Compose"
        case .targetedRefresh: "4 · Refresh"
        }
    }
    var detail: String {
        switch self {
        case .foundation: "A wide set of candidates, areas and key sources."
        case .dateVerification: "Check every venue and constraint on your exact dates."
        case .itinerary: "Turning confirmed options into realistic days and routes."
        case .targetedRefresh: "A new search only for the fields and changes you ask for."
        }
    }
}

private struct TripBrief: Codable, Equatable {
    var destination = ""
    var startDate = ""
    var endDate = ""
    var dateContext: [String] = []
    var dateIsUnknown = false
    var duration = 4
    var travelers = 2
    var group = "Friends"
    var vibes: Set<String> = ["City"]
    var interests: Set<String> = []
    var preferenceTags: Set<String> = []
    var budget = ""
    var budgetBasis = "per person"
    var budgetIncludes: Set<String> = []
    var notes = ""
    var dietaryNeeds: Set<String> = []
    var mobility: Set<String> = []
    var stayStyle: String = "Boutique / Hotel"
    var excludedLibraryNodeIDs: Set<String> = []
    /// Community videos for this plan: "auto" (whatever fits), "picked" (only the ticked ones) or "off".
    var communityUse = "auto"
    var communityVideos: Set<String> = []
    /// Optional "HH:MM" landing and take-off times; the planner keeps those days light.
    var arrivalTime = ""
    var departureTime = ""
    /// "speedrun" overrides the pace slider; empty means use the slider.
    var paceMode = ""
    /// How the traveler gets there: "plane", "train" or "car".
    var travelMode = "plane"
    var mustSee: [ComposerPlace] = []

    var title: String { destination.isEmpty ? "New trip" : destination }
    var libraryDateSummary: String {
        TripDateLabel.compact(start: startDate, end: endDate, flexible: dateIsUnknown, duration: duration)
    }
    var dateSummary: String {
        if dateIsUnknown { return "Flexible dates" }
        if !startDate.isEmpty || !endDate.isEmpty {
            return [startDate, endDate].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        return "Dates to decide"
    }

    enum CodingKeys: String, CodingKey {
        case destination, startDate, endDate, dateContext, dateIsUnknown, duration, travelers, group, vibes, interests, preferenceTags, budget, budgetBasis, budgetIncludes, notes, dietaryNeeds, mobility, stayStyle, excludedLibraryNodeIDs, communityUse, communityVideos, arrivalTime, departureTime, paceMode, travelMode, mustSee
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        dateContext = try c.decodeIfPresent([String].self, forKey: .dateContext) ?? []
        dateIsUnknown = try c.decodeIfPresent(Bool.self, forKey: .dateIsUnknown) ?? false
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 4
        travelers = try c.decodeIfPresent(Int.self, forKey: .travelers) ?? 2
        group = LegacyText.english(try c.decodeIfPresent(String.self, forKey: .group) ?? "Friends")
        vibes = LegacyText.english(try c.decodeIfPresent(Set<String>.self, forKey: .vibes) ?? ["City"])
        let savedInterests = try c.decodeIfPresent(Set<String>.self, forKey: .interests) ?? []
        var tags = try c.decodeIfPresent(Set<String>.self, forKey: .preferenceTags) ?? []
        let legacyInterestMap: [String: (String, String?)] = [
            "Food": ("food", nil), "Sights": ("sights", nil), "Museums": ("sights", "museums"),
            "Bars": ("nightlife", "bars"), "Clubs": ("nightlife", "clubs"), "Markets": ("shopping", nil),
            "Day trips": ("outdoors", "day_trips"), "Events": ("events", nil), "Vegan": ("food", "vegan_food"),
            "Coffee": ("coffee", nil)
        ]
        var normalizedInterests = Set<String>()
        for value in savedInterests {
            if let (group, tag) = legacyInterestMap[value] {
                normalizedInterests.insert(group)
                if let tag { tags.insert(tag) }
            } else {
                normalizedInterests.insert(value)
            }
        }
        interests = normalizedInterests
        preferenceTags = tags
        budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? ""
        budgetBasis = LegacyText.english(try c.decodeIfPresent(String.self, forKey: .budgetBasis) ?? "per person")
        budgetIncludes = LegacyText.english(try c.decodeIfPresent(Set<String>.self, forKey: .budgetIncludes) ?? [])
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dietaryNeeds = LegacyText.english(try c.decodeIfPresent(Set<String>.self, forKey: .dietaryNeeds) ?? [])
        mobility = LegacyText.english(try c.decodeIfPresent(Set<String>.self, forKey: .mobility) ?? [])
        stayStyle = LegacyText.english(try c.decodeIfPresent(String.self, forKey: .stayStyle) ?? "Boutique / Hotel")
        excludedLibraryNodeIDs = try c.decodeIfPresent(Set<String>.self, forKey: .excludedLibraryNodeIDs) ?? []
        communityUse = try c.decodeIfPresent(String.self, forKey: .communityUse) ?? "auto"
        communityVideos = try c.decodeIfPresent(Set<String>.self, forKey: .communityVideos) ?? []
        arrivalTime = try c.decodeIfPresent(String.self, forKey: .arrivalTime) ?? ""
        departureTime = try c.decodeIfPresent(String.self, forKey: .departureTime) ?? ""
        paceMode = try c.decodeIfPresent(String.self, forKey: .paceMode) ?? ""
        travelMode = try c.decodeIfPresent(String.self, forKey: .travelMode) ?? "plane"
        mustSee = try c.decodeIfPresent([ComposerPlace].self, forKey: .mustSee) ?? []
    }
}

private struct PlanningLibraryPlace {
    let id: String
    let name: String
    var address: String = ""
    var category: String = "other"
    var latitude: Double?
    var longitude: Double?
    var providerID: String?

    init(_ place: PersonalPlace) {
        id = place.id
        name = place.name
        address = place.address
        category = place.categoryTitle
        latitude = place.latitude
        longitude = place.longitude
        providerID = place.googlePlaceID
    }

    init(_ place: LinkedPlaceReference) {
        id = place.id
        name = place.name
        address = place.address
        latitude = place.latitude
        longitude = place.longitude
        providerID = place.googlePlaceID
    }

    init(_ place: SocialPlaceMention) {
        id = place.id.uuidString
        name = place.name
        category = "other"
        latitude = place.latitude
        longitude = place.longitude
    }

    init(_ place: ComposerPlace) {
        id = "must-see:" + place.name
        name = place.name
        address = place.address
        category = place.category
        latitude = place.latitude
        longitude = place.longitude
    }

    init?(research place: [String: Any]) {
        guard let name = place["name"] as? String, !name.isEmpty else { return nil }
        id = place["id"] as? String ?? name
        self.name = name
        address = place["address"] as? String ?? ""
        category = place["category"] as? String ?? "other"
        if let coordinates = place["coordinates"] as? [String: Any] {
            latitude = coordinates["latitude"] as? Double
            longitude = coordinates["longitude"] as? Double
        } else {
            latitude = place["latitude"] as? Double
            longitude = place["longitude"] as? Double
        }
        providerID = place["provider_id"] as? String ?? place["google_place_id"] as? String
    }

    var payload: [String: Any] {
        [
            "id": id, "name": name, "address": address, "category": category,
            "latitude": latitude as Any? ?? NSNull(), "longitude": longitude as Any? ?? NSNull(),
            "provider_id": providerID as Any? ?? NSNull(),
            "selected": latitude != nil && longitude != nil
        ]
    }
}

private struct PlanningLibraryNode: Identifiable {
    let id: String
    let kind: String
    let title: String
    let city: String
    var text = ""
    var url: String?
    var places: [PlanningLibraryPlace] = []
    var include = true

    var kindTitle: String {
        switch kind {
        case "pin": "Pinned place"
        case "save": "Saved place"
        case "note": "Travel note"
        case "video": "Saved video"
        case "prior_trip": "Previous trip"
        default: kind
        }
    }

    var payload: [String: Any] {
        var value: [String: Any] = [
            "id": id, "kind": kind, "city": city, "text": text,
            "places": places.map(\.payload), "include": include
        ]
        if let url { value["url"] = url }
        return value
    }
}

enum LibraryDeletion {
    static func video(_ id: UUID, sources: inout [ImportedSocialSource], notes: inout [TravelNote], deleted: inout Set<UUID>) {
        deleted.insert(id)
        sources.removeAll { $0.id == id }
        for index in notes.indices {
            notes[index].sourceIDs.removeAll { $0 == id }
            notes[index].fromSources?[id.uuidString] = nil
        }
        // A note written only from this video, with nothing of yours in it, goes with it. Pins stay on your map.
        notes.removeAll { $0.kind != nil && $0.fromSources?.isEmpty == true && $0.sourceIDs.isEmpty
            && $0.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    static func note(_ id: UUID, notes: inout [TravelNote], places: inout [SocialPlaceMention]) {
        notes.removeAll { $0.id == id }
        for index in places.indices where places[index].noteID == id { places[index].noteID = nil }
    }
}

enum LibrarySourceStatus: String, CaseIterable, Identifiable {
    case all, pending, review, ready
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "All"; case .pending: "Processing"; case .review: "Review"; case .ready: "Ready" }
    }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .pending: "clock"; case .review: "exclamationmark.circle"; case .ready: "checkmark.circle" }
    }
    static func classify(_ state: String) -> Self {
        switch state { case "ready": .ready; case "needs_retrieval", "needs_transcript", "pending", "queued", "processing": .pending; default: .review }
    }
}

// Personal identity is optional so older trips and saves decode unchanged.
struct MarkAppearance: Codable, Equatable {
    var glyph: String
    var kind: String = "icon"
    var colorHex: String? = nil
    var validColorHex: String? {
        guard let colorHex, colorHex.count == 6, UInt64(colorHex, radix: 16) != nil else { return nil }
        return colorHex.uppercased()
    }
}

struct MarkGlyphChoice: Identifiable {
    let glyph: String
    let title: String
    var id: String { glyph }
}
enum MarkGlyphCatalog {
    static let pages = ["Icons", "Emoji", "Flags", "Symbols"]
    static let colors = ["5B9275", "DA7B67", "B18BCC", "689FC5", "C59D54", "CF719F", "8E9AAB", "688C87"]
    static func flag(_ code: String) -> String {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else { return "🌐" }
        return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
    static func choices(_ page: String) -> [MarkGlyphChoice] {
        if page == "Flags" {
            return Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.map {
                MarkGlyphChoice(glyph: flag($0), title: (Locale(identifier: "en").localizedString(forRegionCode: $0) ?? $0) + " · " + $0)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        if page == "Emoji" {
            return ["🌍", "✈️", "🧳", "🏖️", "🏔️", "🏕️", "🏙️", "🚆", "🚗", "🚲", "⛵️", "🏛️", "🎡", "🎨", "🎭", "🎶", "🎉", "✨", "❤️", "💛", "💜", "💙", "🌿", "🌸", "🌻", "☀️", "🌙", "⭐️", "🍕", "🍜", "🌮", "🍔", "🥐", "☕️", "🍷", "🍸", "🛍️", "📚", "📷", "🏄", "🥾", "🧘", "🐚", "🐈", "🐕", "🦋", "🐬", "🦊"].map { MarkGlyphChoice(glyph: $0, title: $0) }
        }
        if page == "Symbols" {
            return ["♥", "★", "✦", "✧", "✿", "❀", "☀", "☾", "∞", "♫", "♬", "♠", "♣", "♦", "☮", "☯", "⚑", "⚓", "⚡", "✈", "✉", "✓", "✶", "✺", "◆", "●", "▲", "☕", "♜", "♞", "♛", "♟"].map { MarkGlyphChoice(glyph: $0, title: $0) }
        }
        return ["mappin", "mappin.and.ellipse", "suitcase.rolling.fill", "airplane", "globe.europe.africa.fill", "heart.fill", "star.fill", "sparkles", "flag.fill", "leaf.fill", "mountain.2.fill", "water.waves", "sun.max.fill", "moon.stars.fill", "building.2.fill", "building.columns.fill", "camera.fill", "paintpalette.fill", "music.note", "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill", "bag.fill", "cart.fill", "book.fill", "bed.double.fill", "tent.fill", "tram.fill", "car.fill", "bicycle", "sailboat.fill", "figure.walk", "figure.hiking", "pawprint.fill", "gamecontroller.fill", "bolt.fill", "flame.fill", "binoculars.fill", "ticket.fill"].map {
            MarkGlyphChoice(glyph: $0, title: $0.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
        }
    }
    static func categoryKey(_ category: String) -> String { "custom:" + Data(category.utf8).base64EncodedString() }
    static func kind(_ page: String) -> String { page == "Icons" ? "icon" : page == "Symbols" ? "symbol" : page == "Flags" ? "flag" : "emoji" }
}

private enum TripDateLabel {
    static func compact(start: String, end: String, flexible: Bool, duration: Int) -> String {
        if flexible { return "\(duration) days · Flexible" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        func parts(_ value: String) -> (day: String, year: Int)? {
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
            let c = formatter.calendar.dateComponents([.day, .month, .year], from: date)
            guard let day = c.day, let month = c.month, let year = c.year else { return nil }
            return ("\(day)/\(month)", year)
        }
        let a = parts(start), b = parts(end)
        if let a, let b {
            if start == end { return "\(a.day) \(a.year)" }
            if a.year == b.year { return "\(a.day)-\(b.day) \(a.year)" }
            return "\(a.day) \(a.year)-\(b.day) \(b.year)"
        }
        if let a { return "\(a.day) \(a.year)" }
        if let b { return "\(b.day) \(b.year)" }
        return "Dates to decide"
    }
}

private struct TripPreferenceOption: Identifiable {
    let id: String
    let title: String
    let category: String
    let overtureFamilies: [String]
    let videoCategories: [String]
    var children: [TripPreferenceOption] = []
}

private enum TripPreferenceCatalog {
    // These stable IDs map UI choices to Overture's published family taxonomy and
    // the category IDs extracted from the Barcelona video research set.
    static let groups: [TripPreferenceOption] = [
        .init(id: "food", title: "Food & flavors", category: "food", overtureFamilies: ["food"], videoCategories: ["food"], children: [
            .init(id: "tapas", title: "Tapas", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "catalan_food", title: "Catalan food", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "seafood", title: "Seafood", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "street_food", title: "Street food", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "vegan_food", title: "Vegan options", category: "food", overtureFamilies: ["food"], videoCategories: ["food", "dietary"]),
            .init(id: "desserts", title: "Sweets & ice cream", category: "food", overtureFamilies: ["food", "coffee"], videoCategories: ["food", "coffee"])
        ]),
        .init(id: "nightlife", title: "Nightlife", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars", "clubs"], children: [
            .init(id: "bars", title: "Bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "cocktail_bars", title: "Cocktail bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "wine_bars", title: "Wine bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "pubs", title: "Pubs", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "clubs", title: "Clubs", category: "clubs", overtureFamilies: ["nightlife"], videoCategories: ["clubs"]),
            .init(id: "live_music", title: "Live music", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"])
        ]),
        .init(id: "coffee", title: "Coffee & brunch", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee", "food"], children: [
            .init(id: "specialty_coffee", title: "Specialty coffee", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee"]),
            .init(id: "bakeries", title: "Bakeries", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee", "food"]),
            .init(id: "brunch", title: "Brunch", category: "food", overtureFamilies: ["coffee", "food"], videoCategories: ["food", "coffee"])
        ]),
        .init(id: "sights", title: "Sights & culture", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights", "museums"], children: [
            .init(id: "museums", title: "Museums", category: "museums", overtureFamilies: ["sights"], videoCategories: ["museums"]),
            .init(id: "architecture", title: "Architecture", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "gaudi", title: "Gaudí", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "historic_places", title: "Historic sites", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "churches", title: "Churches & basilicas", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "art_galleries", title: "Art galleries", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"])
        ]),
        .init(id: "outdoors", title: "Nature & beach", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"], children: [
            .init(id: "parks", title: "Parks & gardens", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"]),
            .init(id: "beaches", title: "Beaches", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"]),
            .init(id: "viewpoints", title: "Views & sunset", category: "outdoors", overtureFamilies: ["outdoors", "sights"], videoCategories: ["outdoors", "sights"]),
            .init(id: "day_trips", title: "Day trips", category: "day_trips", overtureFamilies: ["outdoors", "transport"], videoCategories: ["day_trips"])
        ]),
        .init(id: "shopping", title: "Markets & small shops", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"], children: [
            .init(id: "markets", title: "Local markets", category: "shopping", overtureFamilies: ["shopping", "food"], videoCategories: ["shopping", "food"]),
            .init(id: "vintage", title: "Vintage & second hand", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"]),
            .init(id: "bookshops", title: "Bookshops", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"]),
            .init(id: "local_design", title: "Local design & crafts", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"])
        ]),
        .init(id: "events", title: "Events & activities", category: "events", overtureFamilies: ["sights", "nightlife", "other"], videoCategories: ["events", "tickets"], children: [
            .init(id: "concerts", title: "Concerts", category: "events", overtureFamilies: ["nightlife"], videoCategories: ["events"]),
            .init(id: "festivals", title: "Festivals", category: "events", overtureFamilies: ["sights", "nightlife"], videoCategories: ["events"]),
            .init(id: "exhibitions", title: "Exhibitions", category: "events", overtureFamilies: ["sights"], videoCategories: ["events", "museums"]),
            .init(id: "sports", title: "Sports events", category: "events", overtureFamilies: ["sights", "outdoors"], videoCategories: ["events"])
        ])
    ]

    static func filters(interests: Set<String>, tags: Set<String>) -> [[String: Any]] {
        groups.flatMap { group in [group] + group.children }
            .filter { interests.contains($0.id) || tags.contains($0.id) }
            .map { option in
                ["id": option.id, "label": option.title, "category": option.category,
                 "overture_families": option.overtureFamilies, "video_categories": option.videoCategories]
            }
    }
}

private struct DestinationHoliday: Identifiable {
    let id = UUID()
    let date: DateComponents  // year, month, day
    let name: String
    let localName: String
    let kind: HolidayKind

    enum HolidayKind: String {
        case publicHoliday = "public_holiday"
        case localCelebration = "local_celebration"
        case festival = "festival"
        case event = "event"

        var symbol: String {
            switch self {
            case .publicHoliday: return "building.columns"
            case .localCelebration: return "sparkles"
            case .festival: return "party.popper"
            case .event: return "calendar.badge.clock"
            }
        }

        var color: Color {
            switch self {
            case .publicHoliday: return Color(hex: "FF685B")
            case .localCelebration: return Color(hex: "FFBE55")
            case .festival: return Color(hex: "A97BFF")
            case .event: return Color(hex: "477461")
            }
        }
    }
}

private struct DestinationSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let query: String
}

@MainActor
private final class DestinationSearchCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var onResults: (([MKLocalSearchCompletion]) -> Void)?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func search(_ query: String, onResults: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onResults = onResults
        completer.queryFragment = query
    }

    func cancel() {
        onResults = nil
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onResults?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onResults?([])
    }
}

private struct PillFlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Item {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (items: [Item], height: CGFloat) {
        var items: [Item] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let rawIdeal = subview.sizeThatFits(.unspecified).width
            let idealWidth = rawIdeal.isFinite ? max(0, rawIdeal) : width
            let itemWidth = min(idealWidth, width)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let itemHeight = size.height.isFinite ? max(0, size.height) : 0
            items.append(Item(index: index, origin: CGPoint(x: x, y: y), size: CGSize(width: itemWidth, height: itemHeight)))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, itemHeight)
        }
        return (items, items.isEmpty ? 0 : y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }.filter(\.isFinite)
        let idealWidth = max(0, idealWidths.max() ?? 0)
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(0, proposedWidth ?? idealWidth)
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width.isFinite ? max(0, bounds.width) : 0
        for item in arrange(subviews, width: width).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                      anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
    }
}

// One value keeps the two endpoints consistent during a SwiftUI transaction.
private struct TripCalendarSelection: Equatable {
    private(set) var start: Date?
    private(set) var end: Date?

    func selecting(_ date: Date, calendar: Calendar = .current) -> Self {
        if start == nil || end != nil {
            return Self(start: date, end: nil)
        }
        guard let start else { return Self(start: date, end: nil) }
        // Comparing civil components does not resolve a midnight interval.
        // A later time on the arrival day still starts a new selection.
        let tapped = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let arrival = calendar.dateComponents([.era, .year, .month, .day], from: start)
        let tappedDay = (tapped.era ?? 0, tapped.year ?? 0, tapped.month ?? 0, tapped.day ?? 0)
        let arrivalDay = (arrival.era ?? 0, arrival.year ?? 0, arrival.month ?? 0, arrival.day ?? 0)
        return tappedDay <= arrivalDay ? Self(start: date, end: nil) : Self(start: start, end: date)
    }

    var nights: Int { nightCount(calendar: .current) }

    func nightCount(calendar: Calendar) -> Int {
        guard let start, let end, end > start,
              let first = calendar.ordinality(of: .day, in: .era, for: start),
              let last = calendar.ordinality(of: .day, in: .era, for: end),
              last > first else { return 0 }
        // Count civil days, including DST transitions. This avoids the date
        // interval DateComponents calculation on the second-selection path.
        return last - first
    }
}

// Draft dates belong to the sheet. A day tap must not invalidate the entire
// TripFlowView (maps, form, storage observers and all its sheet builders).
private struct TripCalendarSheet: View {
    let destination: String
    let calendarHolidays: [DestinationHoliday]
    let isLoadingHolidays: Bool
    let holidayStatus: String
    let onYearChange: (Date) -> Void
    let onApply: (Date, Date, Int) -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var planning: PlanningColors { PlanningColors(scheme: scheme) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: TripCalendarSelection
    @State private var calendarDisplayedMonth: Date

    init(destination: String, start: Date?, end: Date?, holidays: [DestinationHoliday],
         isLoading: Bool, status: String, onYearChange: @escaping (Date) -> Void,
         onApply: @escaping (Date, Date, Int) -> Void, onCancel: @escaping () -> Void) {
        self.destination = destination
        self.calendarHolidays = holidays
        self.isLoadingHolidays = isLoading
        self.holidayStatus = status
        self.onYearChange = onYearChange
        self.onApply = onApply
        self.onCancel = onCancel
        _selection = State(initialValue: TripCalendarSelection(start: start, end: end))
        _calendarDisplayedMonth = State(initialValue: start ?? Date())
    }

    private var calendarRangeStart: Date? { selection.start }
    private var calendarRangeEnd: Date? { selection.end }
    private var calendarNightCount: Int { selection.nights }

    var body: some View {
        VStack(spacing: 0) {
            calendarContent
            calendarFooter
        }
        .background(planning.canvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { NSLog("[TrippyCalendar selection-v3] opened") }
        .onChange(of: selection) { _, _ in
            NSLog("[TrippyCalendar selection-v3] selection observed after view update")
        }
        .onChange(of: calendarDisplayedMonth) { old, new in
            if Calendar.current.component(.year, from: old) != Calendar.current.component(.year, from: new) {
                onYearChange(new)
            }
        }
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trip dates")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .foregroundStyle(planning.ink)
                    Text(destination)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundStyle(planning.secondaryInk)
                }
                HStack(spacing: 12) {
                    calendarSelectionLabel("ARRIVAL", date: calendarRangeStart, active: calendarRangeStart == nil)
                    Image(systemName: "arrow.right").foregroundStyle(planning.secondaryInk)
                    calendarSelectionLabel("DEPARTURE", date: calendarRangeEnd, active: calendarRangeStart != nil && calendarRangeEnd == nil)
                }
                .padding(15)
                .planningSurface(radius: 18, raised: true)

                VStack(spacing: 16) {
                    HStack {
                        calendarMonthArrow(-1)
                        Spacer(minLength: 8)
                        Text(calendarDisplayedMonth, format: .dateTime.month(.wide).year())
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundStyle(planning.ink)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        calendarMonthArrow(1)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(calendarWeekdayLabels.enumerated()), id: \.offset) { _, weekday in
                            Text(weekday.prefix(2))
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(planning.secondaryInk)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // A month has at most six rows. Eager rows keep the sheet's
                    // layout stable when the range changes during an animation.
                    let days = daysForDisplayedMonth()
                    VStack(spacing: 6) {
                        ForEach(0..<((days.count + 6) / 7), id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { column in
                                    let index = row * 7 + column
                                    if index < days.count, let day = days[index] {
                                        calendarDayButton(day)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity).frame(height: 44)
                                    }
                                }
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: selection)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendarDisplayedMonth)
                }
                .padding(15)
                .planningSurface(radius: 22, raised: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if isLoadingHolidays { ProgressView().tint(planning.brand).controlSize(.small) }
                        else { Image(systemName: "calendar.badge.clock").foregroundStyle(planning.brand) }
                        Text(isLoadingHolidays ? "Loading holidays…" : "In the calendar")
                            .font(.custom("PlusJakartaSans-Bold", size: 13))
                            .foregroundStyle(planning.ink)
                    }
                    ForEach(holidaysForDisplayedMonth) { holiday in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(holiday.date.day ?? 0)")
                                .font(.custom("PlusJakartaSans-Bold", size: 12))
                                .foregroundStyle(holiday.kind.color)
                                .frame(width: 30, height: 30)
                                .background(holiday.kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(holiday.localName)
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                                    .foregroundStyle(planning.ink)
                                Text(holiday.name)
                                    .font(.custom("PlusJakartaSans-Regular", size: 10))
                                    .foregroundStyle(planning.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: holiday.kind.symbol).foregroundStyle(holiday.kind.color)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !isLoadingHolidays && holidaysForDisplayedMonth.isEmpty {
                        Text(calendarHolidays.isEmpty ? holidayStatus : "No holidays this month.")
                            .font(.custom("PlusJakartaSans-Regular", size: 12))
                            .foregroundStyle(planning.secondaryInk)
                    }
                    if !calendarHolidays.isEmpty {
                        Link("Holiday source: Nager.Date", destination: URL(string: "https://date.nager.at")!)
                            .font(.custom("PlusJakartaSans-SemiBold", size: 10))
                            .foregroundStyle(planning.brand)
                    }
                    Text("Holidays don't always mean closures. Local events are checked while planning.")
                        .font(.custom("PlusJakartaSans-Regular", size: 10))
                        .foregroundStyle(planning.secondaryInk)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .planningSurface(radius: 18, raised: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var calendarFooter: some View {
            VStack(spacing: 12) {
                Text(verbatim: calendarSelectionSummary)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    .foregroundStyle(planning.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 20)
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                        .foregroundStyle(planning.ink)
                        .frame(width: 90, height: 48)
                        .background(planning.surface, in: Capsule())
                    Button {
                        guard let start = selection.start, let end = selection.end,
                              selection.nights > 0 else { return }
                        NSLog("[TrippyCalendar selection-v3] applying selection")
                        onApply(start, end, selection.nights)
                    } label: {
                        Text("Apply dates")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                            .foregroundStyle(planning.inverseInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(planning.brand, in: Capsule())
                    }
                    .disabled(calendarNightCount < 1)
                    .opacity(calendarNightCount < 1 ? 0.45 : 1)
                }
                .buttonStyle(QuietPressStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(planning.canvas)
            // Day selection animates only the grid, never sheet safe-area layout.
            .transaction { $0.animation = nil }
    }

    private var calendarSelectionSummary: String {
        guard selection.start != nil else { return "Choose arrival date" }
        guard selection.end != nil else { return "Now choose departure" }
        let nights = selection.nights
        return "\(nights) nights · \(nights + 1) days"
    }

    private func calendarSelectionLabel(_ title: String, date: Date?, active: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.custom("PlusJakartaSans-SemiBold", size: 9))
                .tracking(1)
                .foregroundStyle(active ? planning.brand : planning.secondaryInk)
            if let date {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.custom("PlusJakartaSans-Bold", size: 16))
                    .foregroundStyle(planning.ink)
            } else {
                Text("Choose")
                    .font(.custom("PlusJakartaSans-Bold", size: 16))
                    .foregroundStyle(active ? planning.brand : planning.secondaryInk)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 68)
        .padding(.vertical, 10)
        .background(active ? planning.brand.opacity(0.06) : planning.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? planning.brand.opacity(0.3) : planning.secondaryInk.opacity(0.12), lineWidth: 1))
    }

    private func calendarMonthArrow(_ direction: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                calendarDisplayedMonth = Calendar.current.date(byAdding: .month, value: direction, to: calendarDisplayedMonth) ?? calendarDisplayedMonth
            }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(planning.ink)
                .frame(width: 44, height: 44)
                .background(planning.canvas, in: Circle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(direction < 0 ? "Previous month" : "Next month")
    }

    private var calendarWeekdayLabels: [String] {
        let calendar = Calendar.current
        let labels = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(labels[first...] + labels[..<first])
    }

    private var holidaysForDisplayedMonth: [DestinationHoliday] {
        let components = Calendar.current.dateComponents([.year, .month], from: calendarDisplayedMonth)
        return calendarHolidays.filter {
            $0.date.year == components.year && $0.date.month == components.month
        }.sorted { ($0.date.day ?? 0) < ($1.date.day ?? 0) }
    }

    private func calendarDayButton(_ date: Date) -> some View {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let isStart = calendarRangeStart.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
        let isEnd = calendarRangeEnd.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
        let isInRange: Bool = {
            guard let start = calendarRangeStart, let end = calendarRangeEnd else { return false }
            return (date > start || isStart) && (date < end || isEnd)
        }()
        let holiday = calendarHolidays.first {
            $0.date.year == components.year && $0.date.month == components.month && $0.date.day == components.day
        }
        return Button {
            let choosingReturn = selection.start != nil && selection.end == nil
            NSLog("[TrippyCalendar selection-v3] tap begin: %@", choosingReturn ? "return" : "arrival")
            let currentSelection = selection
            let nextSelection = currentSelection.selecting(date)
            NSLog("[TrippyCalendar selection-v3] next selection calculated")
            selection = nextSelection
            NSLog("[TrippyCalendar selection-v3] tap state committed")
        } label: {
            VStack(spacing: 2) {
                Text("\(components.day ?? 0)")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                    .foregroundStyle(isStart || isEnd ? planning.inverseInk : planning.ink)
                Circle()
                    .fill(holiday?.kind.color ?? Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isStart || isEnd ? planning.brand :
                    (isInRange ? planning.brand.opacity(0.12) : Color.clear),
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(holiday.map { "\(components.day ?? 0), \($0.localName)" } ?? "\(components.day ?? 0)")
    }

    private func daysForDisplayedMonth() -> [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: calendarDisplayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday else { return [] }
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0
        return Array(repeating: nil, count: leading) + (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }.map { Optional($0) }
    }

}

private struct HolidayLocation {
    let query: String
    let countryCode: String
    let regionCode: String?
    let displayName: String
}

private struct PublicHolidayResponse: Decodable {
    let date: String
    let localName: String
    let name: String
    let global: Bool
    let counties: [String]?
    let types: [String]
}

private struct ResearchOperation: Identifiable {
    let step: Int
    var detail: String
    var id: Int { step }
    var title: String {
        switch step {
        case 1: "Connection"
        case 2: "Discover"
        case 3: "Check options"
        case 4: "Building the plan"
        default: "Save"
        }
    }
    var symbol: String {
        switch step {
        case 1: "network"
        case 2: "globe.europe.africa"
        case 3: "checkmark.shield"
        case 4: "map"
        default: "tray.and.arrow.down"
        }
    }
    static let planned = [
        ResearchOperation(step: 1, detail: "Connecting to the planning service."),
        ResearchOperation(step: 2, detail: "Finding places that suit you."),
        ResearchOperation(step: 3, detail: "Checking dates, hours and needs."),
        ResearchOperation(step: 4, detail: "Organizing days, routes and costs."),
        ResearchOperation(step: 5, detail: "Your plan and edits are kept.")
    ]
    static func completedPhases(_ values: [Int]) -> Set<Int> {
        Set(values.filter { (2...4).contains($0) })
    }
    static func phase(serverStep: String, task: String) -> Int? {
        if serverStep == "searching_web" || serverStep == "synthesizing_patch" {
            return task.hasPrefix("selected-checks-") ? 3 : 2
        }
        if serverStep == "composing" { return task == "source_based_draft" ? 2 : 4 }
        return nil
    }
}

private enum ResearchRequestStage: String {
    case preflight, start, status
}

private enum ResearchRequestError: Error, Equatable {
    case missingJob
    case httpStatus(Int, ResearchRequestStage)
    case invalidResponse(ResearchRequestStage)
    case configurationUnavailable([String])

    var requiresNewJob: Bool { self == .missingJob }
    var message: String {
        switch self {
        case .missingJob:
            return "The service can no longer find this request, usually after a restart or update. You can start again; your saved plan and edits are kept."
        case .configurationUnavailable:
            return "The planning service isn't fully set up. Its settings need checking before a new plan."
        case .httpStatus(let status, _):
            if [408, 429, 500, 502, 503, 504].contains(status) {
                return "The planning service is unavailable right now. Your request is kept; check its status again shortly."
            }
            if status == 401 || status == 403 { return "The service refused access. The app's connection to it needs checking." }
            if status == 422 { return "The service didn't accept the trip details. Check the destination and dates." }
            return "The service returned an error. Its connection or version needs checking."
        case .invalidResponse:
            return "The service replied without a valid plan. Its version needs checking; your request is kept."
        }
    }
    var diagnostic: String {
        switch self {
        case .missingJob: "status: HTTP 404, job_not_found"
        case .httpStatus(let status, let stage): "\(stage.rawValue): HTTP \(status)"
        case .invalidResponse(let stage): "\(stage.rawValue): invalid_response"
        case .configurationUnavailable(let fields): "preflight: configuration_required\n" + fields.joined(separator: "\n")
        }
    }
}

private enum ResearchTransport {
    static func checkedJSON(_ data: Data, response: URLResponse, stage: ResearchRequestStage, checkResearchReadiness: Bool = true) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else { throw ResearchRequestError.invalidResponse(stage) }
        if stage == .status && http.statusCode == 404 { throw ResearchRequestError.missingJob }
        let accepted = stage == .start ? [200, 202] : [200]
        guard accepted.contains(http.statusCode) else { throw ResearchRequestError.httpStatus(http.statusCode, stage) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResearchRequestError.invalidResponse(stage)
        }
        if stage == .preflight && checkResearchReadiness && object["research_ready"] as? Bool == false {
            let fields = (object["configuration_issues"] as? [String] ?? []).filter {
                !$0.isEmpty && $0.count <= 80 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
            }
            throw ResearchRequestError.configurationUnavailable(fields)
        }
        return object
    }
    static func shouldRetryStatus(_ error: Error) -> Bool {
        if case ResearchRequestError.httpStatus(let code, .status) = error {
            return [408, 429, 500, 502, 503, 504].contains(code)
        }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
    }
    // Only read-only polling is retried. A research POST is dispatched once.
    static func status(url: URL,
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        pause: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> [String: Any] {
        let delays: [Double] = [2, 4, 8]
        for attempt in 0...delays.count {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 60
            do {
                let (data, response) = try await transport(request)
                return try checkedJSON(data, response: response, stage: .status)
            } catch {
                guard shouldRetryStatus(error), attempt < delays.count else { throw error }
                try await pause(delays[attempt])
            }
        }
        throw ResearchRequestError.invalidResponse(.status)
    }
}

private enum ResearchDiagnostics {
    static func phaseStates(_ root: [String: Any]) -> [Int: String] {
        let report = root["pipeline_report"] as? [String: Any] ?? [:]
        let diagnostics = root["diagnostics"] as? [String: Any] ?? [:]
        let raw = report["phase_states"] as? [String: String] ?? diagnostics["phase_states"] as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard ["2", "3", "4"].contains(key), let phase = Int(key), ["completed", "failed", "skipped", "empty"].contains(value) else { return nil }
            return (phase, value)
        })
    }
    static func phaseDetail(_ state: String?) -> String? {
        switch state {
        case "failed": "Failed · see support details"
        case "skipped": "Skipped · see plan details"
        case "empty": "No stops came out of planning"
        default: nil
        }
    }
    static func identifier(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 120,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.$[]".contains($0)) }) else { return nil }
        return text
    }
    static func summary(_ root: [String: Any]) -> String? {
        let report = root["pipeline_report"] as? [String: Any] ?? [:]
        let diagnostics = root["diagnostics"] as? [String: Any] ?? report["diagnostics"] as? [String: Any] ?? [:]
        guard !report.isEmpty || !diagnostics.isEmpty else { return nil }
        var lines: [String] = []
        if let support = identifier(root["support_id"] ?? report["support_id"]) { lines.append("Support ID: " + support) }
        if let build = identifier(root["build_commit"] ?? report["build_commit"]) { lines.append("Build: " + build) }
        if let count = diagnostics["completed_provider_stages"] as? Int { lines.append("Completed steps: \(count)") }
        if let count = diagnostics["place_count"] as? Int ?? report["places_researched"] as? Int { lines.append("Options: \(count)") }
        if let count = diagnostics["scheduled_stops"] as? Int ?? report["scheduled_stops"] as? Int { lines.append("Stops: \(count)") }
        if let elapsed = diagnostics["elapsed_seconds"] as? Double, elapsed.isFinite, (0...86400).contains(elapsed) { lines.append("Duration: \(Int(elapsed)) s") }
        for (phase, state) in phaseStates(root).sorted(by: { $0.key < $1.key }) { lines.append("Step \(phase): \(state)") }
        let failures = report["failed_stages"] as? [[String: Any]] ?? []
        if let failure = diagnostics["last_failure"] as? [String: Any] ?? failures.first {
            lines.append("Failed:")
            for key in ["task", "stage", "code", "error_type", "field_path", "parameter", "reason"] {
                if let value = identifier(failure[key]) { lines.append("\(key): \(value)") }
            }
            if let status = failure["http_status"] as? Int, (100...599).contains(status) { lines.append("HTTP: \(status)") }
        }
        for event in (diagnostics["events"] as? [[String: Any]] ?? []).suffix(12) {
            let parts = ["event", "task", "stage", "reason"].compactMap { identifier(event[$0]) }
            if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    static func hasPlaces(_ root: [String: Any]) -> Bool {
        !(root["places"] as? [[String: Any]] ?? []).isEmpty
    }
}

private struct Trip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var brief: TripBrief
    var research: String? = nil
    var researchJobID: String? = nil
    var researchBridgeURL: String? = nil
    mutating func forgetResearchJob(matching id: String) {
        guard researchJobID == id else { return }
        researchJobID = nil
        researchBridgeURL = nil
    }
    var updatedAt = Date()
    var scheduleOrderByDate: [String: [String]]? = nil
    var reactionsByItemID: [String: String]? = nil
    var mapCoordinatesByPlaceID: [String: StoredPlaceCoordinate]? = nil
    var scheduleEditsByItemID: [String: ScheduleItemEdit]? = nil
    var checklistDoneIDs: Set<String>? = nil
    var budgetEntries: [TripBudgetEntry]? = nil
    var customName: String? = nil
    var appearance: MarkAppearance? = nil
    var savedPins: [PersonalPlace]? = nil
    var completedAt: Date? = nil
    var title: String { customName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? TripDraftPersistence.defaultName(for: brief) }

}

// Calendar dates are compared at midnight; explicit completion is independent of research.
private enum LibraryTripPhase: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming", completed = "Completed"
    var id: String { rawValue }
    static func date(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = Calendar.current.date(from: components),
              Calendar.current.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }
    static func phase(_ trip: Trip, today: Date = .now) -> Self {
        if trip.completedAt != nil { return .completed }
        guard !trip.brief.dateIsUnknown, let end = date(trip.brief.endDate) ?? date(trip.brief.startDate) else { return .upcoming }
        return end < Calendar.current.startOfDay(for: today) ? .completed : .upcoming
    }
    static func lastDateHasPassed(_ trip: Trip, today: Date = .now) -> Bool {
        guard !trip.brief.dateIsUnknown, let end = date(trip.brief.endDate) ?? date(trip.brief.startDate) else { return false }
        return end < Calendar.current.startOfDay(for: today)
    }
    static func sorted(_ values: [Trip], today: Date = .now) -> [Trip] {
        let midnight = Calendar.current.startOfDay(for: today)
        func proximity(_ trip: Trip) -> TimeInterval {
            guard !trip.brief.dateIsUnknown else { return .infinity }
            let start = date(trip.brief.startDate), end = date(trip.brief.endDate)
            guard let relevant = (end.map { $0 < midnight } ?? false) ? (end ?? start) : (start ?? end) else { return .infinity }
            return abs(relevant.timeIntervalSince(midnight))
        }
        return values.sorted {
            let a = proximity($0), b = proximity($1)
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }
}

// One persistence gate for naming, autosave, and research creation.
private enum TripDraftPersistence {
    @discardableResult
    static func save(trips: inout [Trip], activeID: UUID?, brief: TripBrief,
                     name: String, researchStarted: Bool) -> UUID? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let activeID, let index = trips.firstIndex(where: { $0.id == activeID }) {
            trips[index].brief = brief
            if !cleanName.isEmpty { trips[index].customName = cleanName }
            if trips[index].customName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil {
                trips[index].customName = defaultName(for: brief)
            }
            trips[index].updatedAt = .now
            return activeID
        }
        guard !cleanName.isEmpty || researchStarted else { return nil }
        var trip = Trip(brief: brief)
        trip.customName = cleanName.isEmpty ? defaultName(for: brief) : cleanName
        trips.insert(trip, at: 0)
        return trip.id
    }
    static func defaultName(for brief: TripBrief) -> String {
        let destination = brief.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return destination.isEmpty ? "My trip" : "Trip · " + destination
    }
}

private struct ScheduleItemEdit: Codable, Equatable {
    var time: String? = nil
    var costPerPerson: String? = nil
}

private struct TripBudgetEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New expense"
    var amount: String = ""
    var basis: String = "group"
}

private struct StoredPlaceCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let source: String
    let matchedAt: Date
    var countryCode: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

@MainActor
private final class CurrentLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var failureMessage: String?

    private let manager = CLLocationManager()
    private var requestPending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        failureMessage = nil
        requestPending = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            requestPending = false
            failureMessage = "Turn on Location access for Trippy in iPhone Settings."
        @unknown default:
            requestPending = false
            failureMessage = "Current location isn't available."
        }
    }

    func cancelCurrentLocation() {
        requestPending = false
        manager.stopUpdatingLocation()
        failureMessage = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard requestPending else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            requestPending = false
            failureMessage = "Turn on Location access for Trippy in iPhone Settings."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requestPending else { return }
        requestPending = false
        guard let freshLocation = locations.last, freshLocation.horizontalAccuracy >= 0 else {
            failureMessage = "The iPhone didn't return a valid location. Try again shortly."
            return
        }
        location = freshLocation
        failureMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requestPending else { return }
        requestPending = false
        failureMessage = "Couldn't get your location. Check GPS and try again."
    }
}

// Stored stop indexes belong to one research document. Rebind them by place,
// preserving user choices before replacing that document.
private enum PlanImportReconciliation {
    static func apply(_ incoming: [String: Any], to trip: inout Trip) -> [String: Any] {
        guard let data = trip.research?.data(using: .utf8),
              let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return incoming }
        func days(_ root: [String: Any]) -> [[String: Any]] {
            (root["itinerary"] as? [String: Any])?["days"] as? [[String: Any]] ?? []
        }
        func stops(_ day: [String: Any]) -> [[String: Any]] {
            (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
        }
        func date(_ day: [String: Any], _ index: Int) -> String { day["date"] as? String ?? "day-\(index + 1)" }
        var result = incoming
        var newDays = days(incoming)
        var places = incoming["places"] as? [[String: Any]] ?? []
        let oldPlaces = old["places"] as? [[String: Any]] ?? []
        var retainedIDs = Set<String>()
        var mapping: [String: String] = [:]
        var pending: [[String: Any]] = []
        for (oldIndex, oldDay) in days(old).enumerated() {
            let key = date(oldDay, oldIndex)
            let oldStops = stops(oldDay)
            let oldIDs = oldStops.indices.map { "stop|\(key)|\($0)" }
            let order = trip.scheduleOrderByDate?[key]
            let edited = oldIDs.filter { trip.scheduleEditsByItemID?[$0] != nil || trip.reactionsByItemID?[$0] != nil || trip.mapCoordinatesByPlaceID?[$0] != nil }
            guard order != nil || !edited.isEmpty else { continue }
            let newIndex: Int
            if let index = newDays.enumerated().first(where: { date($0.element, $0.offset) == key })?.offset { newIndex = index }
            else { newIndex = newDays.count; newDays.append(["date": key, "stops": []]) }
            var newStops = stops(newDays[newIndex])
            var claimed = Set<Int>()
            // Only referenced old stops need migration. Anonymous anchors retain their
            // old contents and are explicitly pending rather than binding by index.
            for id in Set((order ?? []) + edited).sorted() where id.hasPrefix("stop|") {
                guard let oldStopIndex = Int(id.split(separator: "|").last ?? ""), oldStops.indices.contains(oldStopIndex) else { continue }
                let oldStop = oldStops[oldStopIndex]
                let placeID = oldStop["place_id"] as? String
                let target: Int
                if let placeID, let index = newStops.indices.first(where: { !claimed.contains($0) && newStops[$0]["place_id"] as? String == placeID }) { target = index }
                else {
                    target = newStops.count
                    var retained = oldStop
                    retained["retained_user_anchor"] = true
                    newStops.append(retained)
                    if let placeID { retainedIDs.insert(placeID) }
                }
                claimed.insert(target)
                mapping[id] = "stop|\(key)|\(target)"
            }
            if let order {
                var rebound = order.map { mapping[$0] ?? $0 }
                for id in order where id.hasPrefix("place|") { retainedIDs.insert(String(id.dropFirst(6))) }
                let selectedPlaces = Set(rebound.compactMap { id -> String? in
                    if id.hasPrefix("place|") { return String(id.dropFirst(6)) }
                    guard let i = Int(id.split(separator: "|").last ?? ""), newStops.indices.contains(i) else { return nil }
                    return newStops[i]["place_id"] as? String
                })
                let previousPlaces = Set(oldStops.compactMap { $0["place_id"] as? String })
                // Append fresh proposals, while preserving deliberate removals.
                for i in newStops.indices {
                    guard let pid = newStops[i]["place_id"] as? String,
                          !selectedPlaces.contains(pid), !previousPlaces.contains(pid) else { continue }
                    rebound.append("stop|\(key)|\(i)")
                }
                trip.scheduleOrderByDate?[key] = rebound
            }
            newDays[newIndex].removeValue(forKey: "activities")
            newDays[newIndex].removeValue(forKey: "items")
            newDays[newIndex]["stops"] = newStops
            pending.append(["code": "local_schedule_needs_review", "date": key])
        }
        let oldEdits = trip.scheduleEditsByItemID ?? [:]
        trip.scheduleEditsByItemID = Dictionary(oldEdits.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let oldReactions = trip.reactionsByItemID ?? [:]
        trip.reactionsByItemID = Dictionary(oldReactions.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let oldPins = trip.mapCoordinatesByPlaceID ?? [:]
        trip.mapCoordinatesByPlaceID = Dictionary(oldPins.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        // Preserve saved place references even when a research pass omits them.
        retainedIDs.formUnion(oldReactions.keys.filter { $0.hasPrefix("place|") }.map { String($0.dropFirst(6)) })
        retainedIDs.formUnion((trip.mapCoordinatesByPlaceID ?? [:]).keys.filter { !$0.hasPrefix("stop|") })
        for place in oldPlaces {
            guard let id = place["id"] as? String, retainedIDs.contains(id), !places.contains(where: { $0["id"] as? String == id }) else { continue }
            var retained = place; retained["retained_from_previous_research"] = true; places.append(retained)
        }
        if !pending.isEmpty {
            var itinerary = result["itinerary"] as? [String: Any] ?? [:]
            itinerary["days"] = newDays; result["itinerary"] = itinerary
            var validation = result["plan_validation"] as? [String: Any] ?? [:]
            validation["pending"] = (validation["pending"] as? [[String: Any]] ?? []) + pending
            validation["status"] = "partial"; result["plan_validation"] = validation
            result["delivery_status"] = "partial"
        }
        result["places"] = places
        if places.count > (incoming["places"] as? [[String: Any]] ?? []).count {
            let sources = incoming["sources"] as? [[String: Any]] ?? []
            result["sources"] = sources + (old["sources"] as? [[String: Any]] ?? []).filter { row in
                !sources.contains { $0["id"] as? String == row["id"] as? String }
            }
        }
        return result
    }
}

private enum TripStorage {
    static let key = "trippy.native.trips.v1"

    static func load() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let trips = try? JSONDecoder().decode([Trip].self, from: data) else { return [] }
        let namedTrips = trips.map { trip in
            var named = trip
            if named.customName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil {
                named.customName = named.brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "My trip"
            }
            return named
        }
        if namedTrips != trips { save(namedTrips) }
        return namedTrips
    }

    static func save(_ trips: [Trip]) {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum BridgeTokenStore {
    private static let service = "com.dimitrisymeonidis.trippy.bridge"
    private static let account = "places-access-token"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    static func save(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var entry = query
        entry[kSecValueData as String] = Data(value.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(entry as CFDictionary, nil)
    }
}

private enum PlacesConnectionState {
    case idle
    case checking
    case connected
    case missingToken
    case rejectedToken
    case missingGoogleKey
    case rateLimited
    case gatewayError(String)
    case googleError(String)
}

private struct TripFlowStoredState: @unchecked Sendable {
    let bridgeToken: String
    let trips: [Trip]
    let savedPlaces: [PersonalPlace]
    let cityCoordinates: [String: StoredPlaceCoordinate]
    let socialLibrary: SocialLibraryDocument

    static func load() -> Self {
        .init(bridgeToken: BridgeTokenStore.load(), trips: TripStorage.load(),
              savedPlaces: PersonalPlaceStorage.load(), cityCoordinates: PersonalPlaceStorage.loadCities(),
              socialLibrary: SocialLibraryStore.load())
    }
}

private extension Notification.Name {
    static let trippyAppReady = Notification.Name("trippy.app-ready")
    static let trippyInitialGeneralMapDidRender = Notification.Name("trippy.initial-general-map-did-render")
}

private struct PlacesGatewayHealthResponse: Decodable {
    let gateway: String?
    let googlePlaces: String?
    let error: String?
    let errorCode: String?
    let message: String?
}

private struct GuideCoverID: Identifiable { let id: UUID }
private struct JourneySheet: Identifiable { let id = UUID(); let draft: JourneyDraft }

private struct TripFlowView: View {
    private var planning: PlanningColors { PlanningColors(scheme: darkMode ? .dark : .light) }
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @AppStorage("trippy.bridgeHost") private var bridgeHost = "https://trippy-research-89fm.onrender.com/"
    @State private var didBootstrap = false
    @State private var hasRenderedInitialMap = false
    @State private var initialMapDidRender = false
    @State private var bridgeToken = ""
    @State private var showOnboarding = OnboardingStore.shouldShow
    @State private var showAccountHub = false
    @State private var showWelcome = false
    @Namespace private var libraryTabSpace
    @State private var tripGreeting: TripGreeting?
    @State private var trips: [Trip] = []
    @State private var cachedGeneralTripPins: [WorkspaceMapPin] = []
    @State private var rootTab = "map"
    @AppStorage("trippy.native.deletedSourceIDs.v1") private var deletedSourceStorage = ""
    private var deletedSourceIDs: Set<UUID> { Set(deletedSourceStorage.split(separator: "|").compactMap { UUID(uuidString: String($0)) }) }
    @State private var librarySection = "Trips"
    @State private var libraryHasMounted = false
    @State private var worldAddRequest: UUID?
    @State private var videoStatusFilter: LibrarySourceStatus = .all
    @State private var mapSearchRequestID: UUID?
    @State private var tripMapSearchRequestID: UUID?
    @AppStorage("trippy.native.map.showApplePlaces") private var tripShowsApplePlaces = true
    @State private var libraryMapFilter: MapLibraryFilter?
    @State private var libraryCity: String?
    @State private var libraryQuery = ""
    @State private var librarySearchVisible = false
    @State private var selectedLibraryPinTypes = Set<String>()
    @State private var expandedTripPhases: Set<String> = ["Upcoming", "Completed"]
    @State private var collapsedLibraryPinSections = Set<String>()
    @State private var showTripMapFilters = false
    @State private var focusedSavedPlaceID: String?
    @State private var savedPlaces: [PersonalPlace] = []
    @State private var cityCoordinates: [String: StoredPlaceCoordinate] = [:]
    @State private var showTripDetails = false
    @State private var detailsDetent: PresentationDetent = .height(116)
    @State private var showRenameTrip = false
    @State private var tripNameDraft = ""
    @State private var tripAppearanceDraft: MarkAppearance?
    @State private var showTripIdentity = false
    @State private var tripIdentityTarget: UUID?
    @State private var editingLibraryPin: MapLibraryPin?
    @State private var routePreviewMode = "walking"
    @State private var selectedMapDay: Int?
    @State private var mapLayers: Set<String> = ["planned", "recommended", "saved"]
    @State private var mapCategories = Set(MapPlaceCategory.allCases)

    @State private var brief = TripBrief()
    @State private var activeTripID: UUID?
    @State private var selectedCard = 0
    @State private var selectedScrollID: Int? = 0
    @State private var stage: TripStage = .library
    @State private var mapShowsWorkspace = false
    @State private var briefStep = 0
    @State private var briefProgress: CGFloat = 0
    @State private var cardDrag: CGFloat = 0
    @State private var briefReveal: CGFloat = 0
    @State private var isRevealingBrief = false
    @State private var gestureTripID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var interfaceTypeSize
    @Environment(\.scenePhase) private var appScenePhase
    @State private var socialSources: [ImportedSocialSource] = []
    @State private var socialPlaces: [SocialPlaceMention] = []
    @State private var travelNotes: [TravelNote] = []
    /// Your take per real place (PlaceKey) and what every user said (by Google place ID).
    @State private var placeTakes: [String: PlaceTake] = [:]
    @State private var placeCommunity: [String: PlaceCommunity] = [:]
    @State private var takeSendTasks: [String: Task<Void, Never>] = [:]
    @State private var selectedSocialSource: ImportedSocialSource?
    /// A community video opened from the Library's Community tab.
    @State private var openCommunityVideo: CommunityVideoKey?
    @State private var mapDirectionsActive = false
    /// The Videos tab shows your own videos or everyone's (Community).
    @State private var videosCommunity = false
    @Namespace private var videosScopeSpace
    @State private var selectedTravelNoteID: UUID?
    /// The place whose sheet is open (Library): everything linked to it in one place.
    @State private var atlasPlaceKey: String?
    /// Indexed community videos for the trip being planned (the "Videos about <city>" choice in the trip form).
    @State private var planSources: CommunityPlanSources?
    @State private var planSourcesLoading = false
    /// The city whose transit lines and tickets are open (trip map → Getting around).
    @State private var transitRequest: TransitRequest?
    @State private var processingShares = false
    @State private var runningSocialExtractions = false
    @State private var shareSummary: ShareSummary?
    @AppStorage("trippy.shareSummary.lastSeen") private var shareSummaryLastSeen: Double = 0
    @AppStorage("trippy.shareSummary.enabled") private var shareSummaryEnabled = true
    @State private var importSourceURL = ""
    @State private var showImportLink = false
    @State private var showAddSocialPlace = false
    @State private var socialPlaceName = ""
    @State private var socialPlaceSummary = ""
    @State private var socialEvidenceID = ""
    @State private var socialPlaceSourceID: UUID?
    @State private var socialPlaceCity = ""
    @State private var importLinkError: String?
    @State private var importText = ""
    @State private var importError: String?
    @State private var toast: String?
    @State private var showPromptSheet = false
    @State private var showResearchFileImporter = false
    @State private var pace = 0.35
    @State private var selectedRegion = "Europe"
    @State private var workspaceTab = "Plan"
    @State private var planPlaceQuery = ""
    @State private var planPlaceCategory: MapPlaceCategory? = nil
    @State private var planLikedOnly = false
    @State private var showBridgeSettings = false
    @State private var showPlacesSettings = false
    @State private var placesConnectionState: PlacesConnectionState = .idle
    @State private var expandedDayIndices: Set<Int> = []
    @State private var expandedScheduleItemIDs: Set<String> = []
    @State private var expandedPlanPlaceIDs: Set<String> = []
    @State private var locatingPlanItemID: String?
    @State private var selectedScheduleDayIndex: Int? = nil
    @State private var activeScheduleDate: String?
    @State private var alternativesForItemID: String?
    @State private var resolvedCoordinates: [String: CLLocationCoordinate2D] = [:]
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var isResolvingCoordinates = false
    @State private var pendingPrompt: String?
    @State private var selectedResearchLayer: ResearchLayer = .foundation
    @State private var isResearching = false
    @State private var showLiveResearchSheet = false
    @State private var completedResearchSteps: Set<Int> = []
    @State private var researchNeedsServiceUpdate = false
    @State private var researchOpenSettingsAfterDismiss = false
    @State private var researchSaved = false
    @State private var researchPartial = false
    @State private var researchDestination = ""
    @State private var researchResultTripID: UUID?
    @State private var liveResearchStep = 1
    @State private var liveResearchError: String? = nil
    @State private var liveResearchDiagnostic: String? = nil
    @State private var researchNeedsNewRequest = false
    @State private var researchPhaseStates: [Int: String] = [:]
    @State private var planningLive = PlanningLive()
    @State private var liveResearchTask: Task<Void, Never>? = nil
    @State private var calendarDisplayedMonth = Date()
    @State private var destinationSuggestions: [DestinationSuggestion] = []
    @State private var destinationSearchTask: Task<Void, Never>?
    @State private var destinationCompleter = DestinationSearchCompleter()
    @State private var destinationConfirmedQuery = ""
    @FocusState private var destinationFieldFocused: Bool
    @State private var showCalendarPicker = false
    @State private var calendarHolidays: [DestinationHoliday] = []
    @State private var isLoadingHolidays = false
    @State private var holidayStatus = "Choose a destination to load holidays."
    @State private var resolvedDestination = ""
    @State private var holidayCache: [String: [DestinationHoliday]] = [:]
    @State private var resolvedHolidayLocation: HolidayLocation?
    @State private var holidayTask: Task<Void, Never>?
    @State private var researchOperations: [ResearchOperation] = []
    @State private var recoverableResearch: [String: Any]?
    @State private var recoveryContext: [String: Any] = [:]
    @State private var showComposer = false
    @State private var composerSeed = ComposerResult()
    @State private var showWhereNext = false
    @State private var journeySheet: JourneySheet?
    @State private var savedJourneys = JourneyStore.load()
    @State private var showLegacyDetails = false
    @State private var guideTripID: UUID?

    private var prompt: String {
        pendingPrompt ?? ResearchPrompt.make(
            layer: selectedResearchLayer,
            brief: brief,
            existingResearch: activeTrip?.research,
            selectedRegion: selectedRegion,
            pace: pace < 0.34 ? "relaxed" : (pace > 0.66 ? "intense" : "balanced")
        )
    }
    private var activeTrip: Trip? { trips.first(where: { $0.id == activeTripID }) }
    private var rootNavigationTint: Color {
        if darkMode { return rootTab == "library" ? Color(hex: "F18D79") : Color(hex: "A4CEB9") }
        return rootTab == "library" ? Color(hex: "E96A55") : Color(hex: "477461")
    }
    private var workspaceNavigationTint: Color {
        if darkMode {
            switch workspaceTab {
            case "Map": return Color(hex: "A4CEB9")
            case "Places": return Color(hex: "F18D79")
            case "Costs": return Color(hex: "E5BC75")
            default: return Color(hex: "B2A9E9")
            }
        }
        switch workspaceTab {
        case "Map": return Color(hex: "477461")
        case "Places": return Color(hex: "D86B60")
        case "Costs": return Color(hex: "C28A32")
        default: return Color(hex: "6C6CC5")
        }
    }
    private var bridgeBaseURL: String {
        let endpoint = bridgeHost.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint.lowercased().hasPrefix("https://") || endpoint.lowercased().hasPrefix("http://") {
            return endpoint
        }
        return "http://\(endpoint):8080"
    }

    var body: some View {
        ZStack {
            if didBootstrap {
                appContent
                    .fullScreenCover(isPresented: $showOnboarding) { OnboardingFlow { showOnboarding = false } }
                    .background {
                        Color.clear.fullScreenCover(isPresented: $showWelcome) { WelcomeAfterSignIn { showWelcome = false } }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .accountSignedIn)) { _ in
                        // During first-launch setup the tour comes at its end anyway.
                        guard !showOnboarding else { return }
                        showAccountHub = false
                        Task { try? await Task.sleep(for: .milliseconds(700)); showWelcome = true }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .replayOnboarding)) { _ in
                        UserDefaults.standard.removeObject(forKey: "trippy.onboarding.v1.done")
                        showAccountHub = false
                        Task { try? await Task.sleep(for: .milliseconds(600)); showOnboarding = true }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .accountDataApplied)) { _ in
                        // An account's things just landed on this phone: show them.
                        let stored = TripFlowStoredState.load()
                        trips = stored.trips; savedPlaces = stored.savedPlaces; cityCoordinates = stored.cityCoordinates
                        socialSources = stored.socialLibrary.sources; socialPlaces = stored.socialLibrary.places; travelNotes = stored.socialLibrary.notes
                        placeTakes = stored.socialLibrary.takes ?? [:]
                        cachedGeneralTripPins = makeGeneralTripPins()
                    }
                    .sheet(isPresented: $showAccountHub) {
                        AccountHub(onConnections: {
                            Task { try? await Task.sleep(for: .milliseconds(450)); showPlacesSettings = true }
                        })
                    }
                    .overlay(alignment: .top) {
                        if let tripGreeting { TripGreetingBanner(greeting: tripGreeting) { self.tripGreeting = nil }.padding(.top, 54) }
                    }
                    .sheet(item: $shareSummary, onDismiss: { shareSummaryLastSeen = Date.now.timeIntervalSince1970 }) { summary in
                        ShareSummarySheet(summary: summary, onDone: { shareSummary = nil },
                                          onOpenStudio: { shareSummary = nil; librarySection = "Videos"; rootTab = "library" },
                                          onStopShowing: { shareSummaryEnabled = false; shareSummary = nil })
                    }
            }
            // Preserve the SVG web view while stored data and MapKit become ready.
        }
        .task {
            Task.detached(priority: .utility) { MapCityGrouping.prewarm() }
            #if DEBUG
            GlobeTapProbe.runIfAsked()
            #endif
            TrippyPerformance.mark("storage.begin")
            let stored = await Task.detached(priority: .userInitiated) { TripFlowStoredState.load() }.value
            TrippyPerformance.mark("storage.end")
            bridgeToken = stored.bridgeToken
            trips = stored.trips
            savedPlaces = stored.savedPlaces
            cityCoordinates = stored.cityCoordinates
            socialSources = stored.socialLibrary.sources
            socialPlaces = stored.socialLibrary.places
            travelNotes = stored.socialLibrary.notes
            placeTakes = stored.socialLibrary.takes ?? [:]
            if let demo = StudioDemo.load() {
                socialSources = demo.sources; socialPlaces = demo.places
                for tipPost in demo.sources where !(tipPost.tips ?? []).isEmpty { upsertTipsNote(tipPost) }
                if let first = demo.places.first {
                    placeTakes[PlaceKey.of(googlePlaceID: first.googlePlaceID, name: first.name, city: first.city)] =
                        PlaceTake(been: true, gotIn: "waited", tags: ["value_for_money", "traditional"])
                }
                rootTab = "library"; librarySection = "Videos"
                if StudioDemo.opensDetail { Task { try? await Task.sleep(for: .seconds(1.5)); selectedSocialSource = demo.sources.first } }
            }
            backfillGuideNotes()
            cachedGeneralTripPins = makeGeneralTripPins()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TrippyDirectionsDemo") { rootTab = "map" }
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-TrippyLibrarySection"), index + 1 < ProcessInfo.processInfo.arguments.count {
                rootTab = "library"; librarySection = ProcessInfo.processInfo.arguments[index + 1]; libraryHasMounted = true
            }
            // `-TrippyTransitDemo Athens` opens Getting around for that city (3 days, 2 travellers).
            if let city = UserDefaults.standard.string(forKey: "TrippyTransitDemo") {
                Task { try? await Task.sleep(for: .seconds(1.5)); transitRequest = TransitRequest(city: city, coordinate: nil, days: 3, travelers: 2) }
            }
            // Opens the place sheet (no taps in the simulator): the first place with a take, else the first place.
            if ProcessInfo.processInfo.arguments.contains("-TrippyAtlasPlace") {
                Task { try? await Task.sleep(for: .seconds(1.5)); let atlas = libraryAtlas; atlasPlaceKey = (atlas.places.first { $0.take != nil } ?? atlas.places.first)?.id }
            }
            #endif
            if CommunityDemo.browse != nil || GuidesDemo.browse != nil {
                rootTab = "library"; librarySection = "Videos"; videosCommunity = true; libraryHasMounted = true
                if let video = CommunityDemo.video, ProcessInfo.processInfo.arguments.contains("-TrippyCommunityDetail") {
                    Task { try? await Task.sleep(for: .seconds(1.2)); openCommunityVideo = CommunityVideoKey(id: video.key) }
                }
            }
            TrippyPerformance.mark("pins.prepared")
            // Counts for the admin dashboard (no trip contents), at most every 6 hours.
            let reportTrips = trips.count, planned = trips.filter { $0.research != nil }.count
            let saved = savedPlaces.filter(\.isSaved).count, videos = socialSources.count
            Task.detached(priority: .background) { [bridgeBaseURL, bridgeToken] in
                await TrippyInstall.reportIfDue(baseURL: bridgeBaseURL, token: bridgeToken, trips: reportTrips, plannedTrips: planned,
                                                savedPlaces: saved, videos: videos)
            }
            withAnimation(.easeOut(duration: 0.22)) { didBootstrap = true }
            if !showOnboarding && !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-Trippy") }) {
                Task { await openCurrentTrip() }
            }
            #if DEBUG
            // Screenshot checks: `-TrippyStartScreen library|guide|composer`.
            // `-TrippyImportResearch <path> [-TrippyImportStay Trastevere]`: load a planner result as the first trip.
            if let path = UserDefaults.standard.string(forKey: "TrippyImportResearch"), let json = try? String(contentsOfFile: path, encoding: .utf8),
               let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                let days = ((root["itinerary"] as? [String: Any])?["days"] as? [[String: Any]]) ?? []
                var imported = TripBrief()
                imported.destination = (root["map_overview"] as? [String: Any])?["title"] as? String ?? "Rome"
                imported.startDate = days.first?["date"] as? String ?? ""; imported.endDate = days.last?["date"] as? String ?? ""
                imported.duration = max(days.count, 1); imported.travelers = 6
                var trip = Trip(brief: imported); trip.research = json; trip.customName = imported.destination + " · imported"
                trips.removeAll { $0.customName == trip.customName }; trips.insert(trip, at: 0)
                if let stay = UserDefaults.standard.string(forKey: "TrippyImportStay"), let base = (root["itinerary"] as? [String: Any])?["base"] as? [String: Any] {
                    var edits = GuideEditsStore.load(trip.id, travelers: 6)
                    edits.flight.stayName = stay
                    edits.flight.stayLatitude = (base["latitude"] as? NSNumber)?.doubleValue; edits.flight.stayLongitude = (base["longitude"] as? NSNumber)?.doubleValue
                    GuideEditsStore.save(edits, id: trip.id)
                }
            }
            switch UserDefaults.standard.string(forKey: "TrippyStartScreen") {
            case "library": rootTab = "library"; libraryHasMounted = true
            case "guide": rootTab = "library"; libraryHasMounted = true
                if let trip = trips.first(where: { $0.research != nil }) { activeTripID = trip.id; guideTripID = trip.id }
            case "composer": openComposer(for: nil)
            case "wherenext": rootTab = "library"; libraryHasMounted = true; showWhereNext = true
            case "journey": // `-TrippyStartScreen journey [-TrippyJourneyMode car]`: a sample route from Athens
                rootTab = "library"; libraryHasMounted = true
                var sample = JourneyDraft()
                sample.mode = JourneyMode(rawValue: UserDefaults.standard.string(forKey: "TrippyJourneyMode") ?? "") ?? .train
                sample.origin = DestinationCatalog.named("Athens").map(JourneyPoint.init)
                sample.stops = ["Vienna", "Rome", "Florence", "Munich", "Venice"].compactMap { DestinationCatalog.named($0) }.map { JourneyStop(place: JourneyPoint($0)) }
                sample.stops = JourneyEngine.allocate(nights: 10, to: sample.stops)
                journeySheet = JourneySheet(draft: sample)
            case "trip": // `-TrippyStartScreen trip [-TrippyTripSpan 0.02]`
                if let trip = trips.first(where: { $0.research != nil }) {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(2)); selectMapTrip(trip) }
                }
            case "been": rootTab = "library"; libraryHasMounted = true; librarySection = "World"
            case "pins": rootTab = "library"; libraryHasMounted = true; librarySection = "Pins"
            case "account": Task { @MainActor in try? await Task.sleep(for: .seconds(1.5)); showAccountHub = true }
            case "research": brief.destination = PlanningLive.demo == nil ? "Barcelona" : "Rome"; liveResearchStep = 2; isResearching = true
                researchOperations = [ResearchOperation(step: 1, detail: "Connected")]
                if let demo = PlanningLive.demo {
                    planningLive = demo; researchDestination = "Rome"
                    if demo.finished { isResearching = false; researchSaved = true }
                    if demo.notesStatus == "failed" { researchPartial = true }
                }
                showLiveResearchSheet = true
            default: break
            }
            #endif
        }
        .task {
            guard !hasRenderedInitialMap else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) { hasRenderedInitialMap = true }
        }
        .task(id: hasRenderedInitialMap) {
            guard hasRenderedInitialMap else { return }
            TrippyPerformance.mark("map.ready")
            NotificationCenter.default.post(name: .trippyAppReady, object: nil)
            syncShareTargets()
            await importSharedSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trippyInitialGeneralMapDidRender)) { _ in
            initialMapDidRender = true
            guard !hasRenderedInitialMap else { return }
            withAnimation(.easeOut(duration: 0.24)) { hasRenderedInitialMap = true }
        }
    }

    // Resolve only the selected screen's opaque type during cold launch.
    private var selectedMapScreen: AnyView {
        if mapShowsWorkspace { return AnyView(tripMapWorkspace) }
        return AnyView(personalMapHome)
    }
    /// The floating bottom bar's height above the safe area (58-point controls + 6 below).
    static let tabBarHeight: CGFloat = 64
    private var profileButton: some View {
        Button { showAccountHub = true } label: {
            ProfileAvatar(size: 44).padding(3).background(Circle().fill(Sketch.card).shadow(color: .black.opacity(0.12), radius: 12, y: 5))
        }
        .buttonStyle(QuietPressStyle()).accessibilityLabel("Account and settings")
    }
    private var libraryTabScreen: AnyView {
        if libraryHasMounted || rootTab == "library" { return AnyView(modernLibrary) }
        return AnyView(Color.clear)
    }
    private var appContent: some View {
        ZStack {
            AppPalette.canvas.ignoresSafeArea()
            // Keep the native tab/map hierarchy mounted while the draft opens.
            // This avoids tearing down MapKit and native menus during presentation.
            TabView(selection: $rootTab) {
                TrippyScreen { selectedMapScreen }
                    .tag("map")
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Self.tabBarHeight) }
                TrippyScreen { libraryTabScreen }
                    .tag("library")
                    .toolbar(.hidden, for: .tabBar)
                    // Exactly the floating chrome (bar + section dial), so the last card scrolls fully clear of it.
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: Self.tabBarHeight + LibraryWheel.height) }
            }
            .tint(rootNavigationTint)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .allowsHitTesting(stage != .brief)
            .accessibilityHidden(stage == .brief)
            .accessibilityLabel("Navigation")
            .environment(\.locale, Locale(identifier: "en"))
            .onPreferenceChange(DirectionsActiveKey.self) { active in
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { mapDirectionsActive = active }
            }
            if stage != .brief && !(rootTab == "map" && mapDirectionsActive) {
                VStack(spacing: 0) {
                    if rootTab == "library" {
                        LibraryWheel(items: librarySections, selection: libraryWheelSelection, tint: Sketch.ink)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TrippyTabBar(selection: $rootTab, action: bottomBarAction, leading: rootTab == "library" ? AnyView(profileButton) : nil)
                }
                .background(alignment: .bottom) {
                    // A paper fade under the dial and bar keeps them readable over busy cards.
                    if rootTab == "library" && librarySection != "World" {
                        LinearGradient(stops: [.init(color: Sketch.paper.opacity(0), location: 0), .init(color: Sketch.paper.opacity(0.88), location: 0.45),
                                               .init(color: Sketch.paper.opacity(0.97), location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.tabBarHeight + LibraryWheel.height + 60)
                            .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: rootTab)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.keyboard)
                .zIndex(0.5)
            }
            if stage == .brief {
                TrippyScreen { briefScreen }
                    .background(planning.canvas.ignoresSafeArea())
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.inverseInk)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(AppPalette.ink, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .onChange(of: brief.destination) { _, destination in
            if !brief.dateContext.isEmpty { brief.dateContext = [] }
            if destination.trimmingCharacters(in: .whitespacesAndNewlines) != destinationConfirmedQuery {
                searchDestinations(destination)
            } else {
                destinationSuggestions = []
            }
            resolvedHolidayLocation = nil
            resolvedDestination = ""
            calendarHolidays = []
            loadHolidays(for: destination, debounce: true)
        }
        .onChange(of: stage) { _, new in
            if new == .brief { briefStep = 0; showTripDetails = false; loadHolidays(for: brief.destination) }
            if new == .workspace { mapShowsWorkspace = true; rootTab = "map"; selectedMapDay = nil }
            if new == .library { mapShowsWorkspace = false }

        }
        .onChange(of: appScenePhase) { _, phase in
            if phase == .background {
                // Background time for the upload; the account always has this phone's latest.
                let task = UIApplication.shared.beginBackgroundTask(withName: "account-backup")
                Task { await AccountData.backupIfJoined(minimumInterval: 0); UIApplication.shared.endBackgroundTask(task) }
            } else if phase == .active {
                Task { await AccountData.backupIfJoined() }
            }
            if phase == .active && hasRenderedInitialMap { Task { await importSharedSources() } }
        }
        .onChange(of: rootTab) { _, tab in if tab == "library" { libraryHasMounted = true } }
        .onChange(of: trips) { _, _ in cachedGeneralTripPins = makeGeneralTripPins(); syncShareTargets() }
        .onChange(of: socialSources) { _, _ in persistSocialLibrary() }
        .onChange(of: socialPlaces) { _, _ in persistSocialLibrary() }
        .onChange(of: travelNotes) { _, _ in persistSocialLibrary(); syncShareTargets() }
        .onChange(of: placeTakes) { _, _ in persistSocialLibrary() }
        .onChange(of: bridgeToken) { _, value in BridgeTokenStore.save(value) }
        .sheet(item: $selectedSocialSource) { source in TrippyScreen { socialSourceDetail(source) } }
        .sheet(item: $openCommunityVideo) { item in
            NavigationStack {
                CommunityVideoDetailView(key: item.id, baseURL: bridgeBaseURL, token: bridgeToken, preview: CommunityDemo.video, actions: communityActions)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { openCommunityVideo = nil } } }
            }
        }
        .sheet(isPresented: Binding(get: { selectedTravelNoteID != nil }, set: { if !$0 { selectedTravelNoteID = nil } })) {
            TrippyScreen { if let id = selectedTravelNoteID { travelNoteDetail(id) } }
        }
        .sheet(isPresented: Binding(get: { atlasPlaceKey != nil }, set: { if !$0 { atlasPlaceKey = nil } })) {
            TrippyScreen {
                let atlas = libraryAtlas
                if let place = atlas.place(atlasPlaceKey) { AtlasPlaceSheet(place: place, atlas: atlas, actions: atlasActions) }
            }
        }
        .sheet(item: $transitRequest) { request in
            TransitSheet(request: request, baseURL: bridgeBaseURL, token: bridgeToken, preview: TransitDemo.answer)
                .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        }
        .sheet(isPresented: $showImportLink) { TrippyScreen { importLinkSheet } }
        .sheet(isPresented: $showTripIdentity) { TrippyScreen { tripIdentityEditor } }
        .sheet(item: $editingLibraryPin) { record in TrippyScreen { libraryPinIdentityEditor(record) } }
        .onChange(of: rootTab) { _, tab in if tab == "library" { showTripDetails = false; showTripMapFilters = false } }
        .onChange(of: savedPlaces) { _, places in PersonalPlaceStorage.save(places) }
        .alert("Trip name", isPresented: $showRenameTrip) {
            TextField("Your trip's name", text: $tripNameDraft)
            Button("Save") {
                saveDraft()

            }
            Button("Cancel", role: .cancel) { }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .animation(reduceMotion ? nil : .spring(response: 0.68, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.48, dampingFraction: 0.78), value: selectedCard)
        .sheet(isPresented: $showPromptSheet) { TrippyScreen { promptSheet } }
        .sheet(isPresented: $showBridgeSettings) { TrippyScreen { bridgeSettingsSheet } }
        .sheet(isPresented: $showPlacesSettings) { TrippyScreen { placesSettingsSheet } }
        .fullScreenCover(isPresented: $showLiveResearchSheet, onDismiss: {
            if researchOpenSettingsAfterDismiss {
                researchOpenSettingsAfterDismiss = false
                showBridgeSettings = true
            }
        }) { TrippyScreen { liveResearchSheet } }
        .sheet(isPresented: $showCalendarPicker) { TrippyScreen { calendarPickerSheet } }
        .fullScreenCover(item: Binding(get: { guideTripID.map(GuideCoverID.init) }, set: { guideTripID = $0?.id })) { cover in
            guideCover(cover.id)
        }
        .fullScreenCover(isPresented: $showWhereNext) {
            WhereNextView(onClose: { showWhereNext = false },
                          onPlanTrip: { pick, query in
                              showWhereNext = false
                              Task { @MainActor in try? await Task.sleep(for: .milliseconds(450)); openComposer(for: pick, query: query) }
                          },
                          onPlanJourney: { draft in
                              showWhereNext = false
                              Task { @MainActor in try? await Task.sleep(for: .milliseconds(450)); journeySheet = JourneySheet(draft: draft) }
                          })
        }
        .sheet(item: $journeySheet) { sheet in
            JourneyBuilderView(draft: sheet.draft, onCancel: { journeySheet = nil }, onCreate: createJourney)
                .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        }
        .sheet(isPresented: $showComposer) {
            TripComposerView(result: composerSeed, onCancel: { showComposer = false }, onSubmit: submitComposer,
                             onDetailed: {
                                 showComposer = false
                                 if activeTripID != nil { openBrief() } else {
                                     Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); startDetailedTrip() }
                                 }
                             })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "Check the JSON and try again.") }
        .fileImporter(isPresented: $showResearchFileImporter, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    importText = try String(contentsOf: url, encoding: .utf8)
                    importResearch()
                    if importError == nil { showPromptSheet = false }
                } catch {
                    importError = "Couldn't read the file. Try a UTF-8 .json file."
                }
            case .failure:
                importError = "Couldn't select the file."
            }
        }
    }

    private var library: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .firstTextBaseline) {
                    Text("These are your trips")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .tracking(-0.7)
                        .foregroundStyle(AppPalette.ink)
                    Spacer()
                    Text(tripCountLabel)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                carousel(size: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 11) {
                    pageIndicator
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text(cardDrag > 30 ? "Tap the bin to delete" : "↑ Edit · ↓ Delete")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                    }
                    .foregroundStyle(AppPalette.secondaryInk)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background {
                        if #available(iOS 26.0, *) {
                            Capsule().fill(.ultraThinMaterial)
                        } else {
                            Capsule().fill(AppPalette.surface.opacity(0.82))
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.bottom, 18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(AppPalette.canvas)
            .safeAreaPadding(.top, 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var topBar: some View {
        HStack {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 38)
                .accessibilityLabel("trippy")
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { darkMode.toggle() }
            } label: {
                Image(systemName: darkMode ? "sun.max" : "moon")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 40, height: 40)
                    .modifier(AdaptiveGlassControl(shape: .circle))
            }
            .accessibilityLabel(darkMode ? "Light appearance" : "Dark appearance")
            if !trips.isEmpty {
                Button {
                    startNewTrip()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 42, height: 42)
                        .modifier(AdaptiveGlassControl(shape: .circle))
                }
                .accessibilityLabel("New trip")
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
    }

    private var tripCountLabel: String { "\(trips.count) \(trips.count == 1 ? "ταξίδι" : "ταξίδια")" }

    private func carousel(size: CGSize) -> some View {
        let cardWidth = min(size.width * 0.76, 330)
        let cardHeight = min(size.height * 0.72, cardWidth * 1.34)
        // Global coordinates do not change when the carousel moves under the finger.
        let cardGesture = DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard stage == .library, !isRevealingBrief, !trips.isEmpty,
                      gestureTripID != nil || abs(value.translation.height) > abs(value.translation.width) * 1.25 else { return }
                if gestureTripID == nil, trips.indices.contains(selectedCard) {
                    let trip = trips[selectedCard]
                    gestureTripID = trip.id
                    activeTripID = trip.id
                    brief = trip.brief
                }
                let vertical = value.translation.height
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if vertical < 0 {
                        cardDrag = 0
                        briefReveal = min(1, -vertical / max(size.height, 1))
                    } else {
                        briefReveal = 0
                        cardDrag = min(160, vertical * 0.8)
                    }
                }
            }
            .onEnded { value in
                guard !isRevealingBrief, gestureTripID != nil else { return }
                let upward = -value.translation.height
                let predicted = -value.predictedEndTranslation.height
                if upward > size.height * 0.22 || (upward > 65 && predicted > size.height * 0.45) {
                    finishBriefReveal()
                } else {
                    withAnimation(.smooth(duration: 0.38, extraBounce: 0)) {
                        briefReveal = 0
                        cardDrag = value.translation.height > 65 ? 100 : 0
                    }
                    gestureTripID = nil
                }
            }

        return Group {
            if trips.isEmpty {
                Button {
                    startNewTrip()
                } label: {
                    VStack(spacing: 18) {
                        Image(systemName: "plus")
                            .font(.system(size: 31, weight: .light))
                            .foregroundStyle(AppPalette.brand)
                            .frame(width: 88, height: 88)
                            .background(AppPalette.surface, in: Circle())
                            .modifier(AdaptiveGlassControl(shape: .circle))
                        Text("New trip")
                            .font(.custom("PlusJakartaSans-Bold", size: 16))
                            .foregroundStyle(AppPalette.ink)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel("Create a new trip")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                            ZStack(alignment: .top) {
                                if index == selectedCard && cardDrag > 0 {
                                    Button(role: .destructive) { deleteTrip(trip.id) } label: {
                                        Label("Delete trip", systemImage: "trash.fill")
                                            .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 20)
                                            .frame(height: 52)
                                            .background(Color(hex: "C94B43"), in: Capsule())
                                    }
                                    .buttonStyle(QuietPressStyle())
                                    .opacity(min(1, cardDrag / 70))
                                    .offset(y: -12)
                                    .accessibilityLabel("Delete \(trip.title)")
                                }
                                tripCard(trip, width: cardWidth, height: cardHeight, isActive: index == selectedCard)
                                    .offset(y: index == selectedCard ? cardDrag : 0)
                            }
                                .frame(width: cardWidth, height: cardHeight)
                                .id(index)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.91)
                                        .opacity(phase.isIdentity ? 1 : 0.70)
                                        .offset(y: phase.isIdentity ? 0 : 12)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedScrollID, anchor: .center)
                .onChange(of: selectedScrollID) { _, value in
                    if let value {
                        selectedCard = value
                        cardDrag = 0
                        gestureTripID = nil
                    }
                }
                .safeAreaPadding(.horizontal, max(0, (size.width - cardWidth) / 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(cardGesture)
    }

    @ViewBuilder
    private func tripCard(_ trip: Trip, width: CGFloat, height: CGFloat, isActive: Bool) -> some View {
        VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        TripCover(vibe: trip.brief.vibes.first ?? "City", destination: trip.brief.destination)
                            .frame(height: height * 0.73)
                        LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                            .frame(height: height * 0.73)
                        if trip.research != nil {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(.black.opacity(0.25), in: Capsule())
                                .padding(14)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trip.title)
                                .font(.custom("PlusJakartaSans-ExtraBold", size: 19))
                                .tracking(-0.5)
                                .foregroundStyle(AppPalette.ink)
                                .lineLimit(1)
                            Spacer()

                        }
                        Text(trip.brief.dateIsUnknown ? "\(trip.brief.duration) days · Flexible" : trip.brief.dateSummary)
                            .font(.custom("PlusJakartaSans-Regular", size: 11))
                            .foregroundStyle(AppPalette.secondaryInk)
                        HStack(spacing: 6) {
                            HStack(spacing: -5) {
                                ForEach(0..<min(trip.brief.travelers, 3), id: \.self) { _ in
                                    Circle().fill(AppPalette.avatarColors[trip.brief.travelers % AppPalette.avatarColors.count])
                                        .frame(width: 17, height: 17)
                                        .overlay(Circle().stroke(AppPalette.surface, lineWidth: 1.5))
                                }
                            }
                            Text("\(trip.brief.travelers) travelers")
                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                            Text("·")
                            Text(trip.brief.group)
                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                            Spacer()
                        }
                        Text(trip.brief.vibes.sorted().joined(separator: " · "))
                            .font(.custom("PlusJakartaSans-Medium", size: 10))
                            .foregroundStyle(AppPalette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 11)
                    .padding(.bottom, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(AppPalette.surface)
                }
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Button { editTrip(trip) } label: { Label("Edit request", systemImage: "pencil") }
                        Button(role: .destructive) { deleteTrip(trip.id) } label: { Label("Delete trip", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.35), in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Options for \(trip.title)")
                    .padding(12)
                }
                .shadow(color: AppPalette.ink.opacity(isActive ? 0.15 : 0.09), radius: isActive ? 22 : 14, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 25))
            .onTapGesture {
                guard cardDrag == 0, briefReveal == 0, !isRevealingBrief else { return }
                activeTripID = trip.id
                brief = trip.brief
                withAnimation { stage = trip.research == nil ? .brief : .workspace }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Open trip") {
                activeTripID = trip.id
                brief = trip.brief
                stage = trip.research == nil ? .brief : .workspace
            }
            .accessibilityAction(named: "Edit request") { editTrip(trip) }
            .accessibilityAction(named: "Delete trip") { deleteTrip(trip.id) }
    }

    private var pageIndicator: some View {
        Group {
            if trips.isEmpty {
                EmptyView()
            } else if trips.count <= 8 {
                HStack(spacing: 5) {
                    ForEach(trips.indices, id: \.self) { index in
                        Capsule().fill(index == selectedCard ? AppPalette.ink : Color(hex: "E8C8B9"))
                            .frame(width: index == selectedCard ? 18 : 6, height: 6)
                    }
                }
            } else {
                Text("\(selectedCard + 1) / \(trips.count)")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .accessibilityLabel(trips.isEmpty ? "No trips" : "Trip \(selectedCard + 1) of \(trips.count)")
    }

    private var briefScreen: some View {
        VStack(spacing: 0) {
            HStack {
                stageHeader(title: "", back: activeTrip?.research == nil ? .library : .workspace)
                Menu {
                    Button("Import plan", systemImage: "doc.badge.arrow.up") { pendingPrompt = nil; showPromptSheet = true }
                    Button("Planning connection", systemImage: "network") { showBridgeSettings = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.padding(.trailing, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(briefStep == 0 ? "Let's plan the trip" : briefStepTitles[briefStep])
                            .font(.custom("PlusJakartaSans-ExtraBold", size: 29))
                            .tracking(-0.9)
                            .foregroundStyle(planning.ink)
                        Text(briefStepSubtitles[briefStep])
                            .font(.custom("PlusJakartaSans-Regular", size: 14))
                            .foregroundStyle(planning.secondaryInk)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("STEP \(briefStep + 1) OF 4")
                                .font(.custom("PlusJakartaSans-Bold", size: 10))
                                .tracking(1.2)
                                .foregroundStyle(planning.secondaryInk)
                            Spacer()
                            Text(briefStepTitles[briefStep])
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(planning.brand)
                        }
                        HStack(spacing: 5) {
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index <= briefStep ? planning.progress(index) : planning.secondaryInk.opacity(0.14))
                                    .frame(height: 4)
                            }
                        }
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: briefStep)
                    }

                    if briefStep == 0 {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Trip name")
                                HStack(spacing: 10) {
                                    Button { tripIdentityTarget = activeTripID; showTripIdentity = true } label: {
                                        MarkIconWell(appearance: tripAppearanceDraft, fallback: "suitcase.rolling.fill", tone: .trips, size: 44)
                                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Trip icon and color")
                                    TextField("What will you call the trip?", text: $tripNameDraft)
                                        .font(.custom("PlusJakartaSans-Medium", size: 15))
                                        .textInputAutocapitalization(.sentences)
                                        .submitLabel(.done)
                                }.padding(.horizontal, 15).frame(minHeight: 52)
                                    .planningSurface(radius: 16, raised: true)
                                Text(activeTripID == nil ? "Saved once you name it or start planning." : "Your trip is saved.")
                                    .font(.caption).foregroundStyle(planning.secondaryInk)
                            }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Where to?")
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(planning.ink)
                            TextField("City or country", text: $brief.destination)
                                .focused($destinationFieldFocused)
                                .font(.custom("PlusJakartaSans-Medium", size: 15))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    destinationSearchTask?.cancel()
                                    destinationSuggestions = []
                                    loadHolidays(for: brief.destination)
                                }
                            if !brief.destination.isEmpty {
                                Button { brief.destination = "" } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(planning.secondaryInk) }
                            }
                        }
                        .padding(.horizontal, 15).frame(height: 52)
                        .planningSurface(radius: 16, raised: true)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(planning.border, lineWidth: 0.8))
                        if !destinationSuggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(destinationSuggestions) { suggestion in
                                    Button {
                                        destinationSearchTask?.cancel()
                                        destinationCompleter.cancel()
                                        destinationSuggestions = []
                                        destinationConfirmedQuery = suggestion.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                        brief.destination = suggestion.query
                                        brief.dateContext = []
                                        loadHolidays(for: suggestion.query)
                                    } label: {
                                        HStack(spacing: 11) {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(planning.brand)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.title)
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                                                    .foregroundStyle(planning.ink)
                                                Text(suggestion.subtitle)
                                                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                    .foregroundStyle(planning.secondaryInk)
                                            }
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(QuietPressStyle())
                                    if suggestion.id != destinationSuggestions.last?.id {
                                        Divider().overlay(planning.border).padding(.leading, 34)
                                    }
                                }
                            }
                            .padding(.horizontal, 13)
                            .planningSurface(radius: 16, raised: true)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(planning.border, lineWidth: 0.8))
                        }
                        if !brief.destination.isEmpty {
                            HStack(spacing: 8) {
                                if isLoadingHolidays { ProgressView().controlSize(.small).tint(planning.brand) }
                                else { Image(systemName: resolvedDestination.isEmpty ? "globe" : "checkmark.circle.fill").foregroundStyle(planning.brand) }
                                Text(resolvedDestination.isEmpty ? holidayStatus : resolvedDestination)
                                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                                    .foregroundStyle(planning.secondaryInk)
                                Spacer()
                                Button("Confirm") { loadHolidays(for: brief.destination) }
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                    .foregroundStyle(planning.brand)
                                    .frame(minHeight: 44)
                            }
                        }
                        PillFlowLayout {
                            ForEach(["Europe", "Asia", "Americas", "Anywhere"], id: \.self) { region in
                                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { selectedRegion = region } } label: { choicePill(region, selected: selectedRegion == region) }
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selectedRegion)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("When?")
                        PillFlowLayout {
                            Button { withAnimation { brief.dateIsUnknown = false } } label: { choicePill("Fixed", selected: !brief.dateIsUnknown) }
                            Button { withAnimation { brief.dateIsUnknown = true } } label: { choicePill("Flexible", selected: brief.dateIsUnknown) }
                            Button { withAnimation { brief.dateIsUnknown = true; brief.startDate = ""; brief.endDate = ""; brief.dateContext = [] } } label: { choicePill("Not sure", selected: brief.dateIsUnknown && brief.startDate.isEmpty) }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: brief.dateIsUnknown)
                        if !brief.dateIsUnknown {
                            Button {
                                destinationFieldFocused = false
                                calendarDisplayedMonth = parseISODate(brief.startDate) ?? Date()
                                loadHolidays(for: brief.destination)
                                showCalendarPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(planning.brand.opacity(0.08))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "calendar")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(planning.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        if brief.startDate.isEmpty && brief.endDate.isEmpty {
                                            Text("Choose dates")
                                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                                .foregroundStyle(planning.ink)
                                            Text("Tap for a calendar with holidays")
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(planning.secondaryInk)
                                        } else {
                                            Text("\(brief.startDate) — \(brief.endDate)")
                                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                                .foregroundStyle(planning.ink)
                                            let nights = calendarNightCount
                                            Text(nights > 0 ? "\(nights) nights · \(nights + 1) days" : "Tap to change")
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(planning.secondaryInk)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(planning.secondaryInk)
                                }
                                .padding(14)
                                .planningSurface(radius: 16, raised: true)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(planning.border, lineWidth: 0.8))
                            }
                            .buttonStyle(QuietPressStyle())
                            if !brief.dateContext.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label("On your dates", systemImage: "calendar.badge.clock")
                                        .font(.custom("PlusJakartaSans-Bold", size: 12))
                                        .foregroundStyle(planning.ink)
                                    ForEach(Array(brief.dateContext.prefix(3).enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "sparkle")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(planning.brand)
                                                .padding(.top, 2)
                                            Text(item)
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(planning.secondaryInk)
                                        }
                                    }
                                    if brief.dateContext.count > 3 {
                                        Text("+\(brief.dateContext.count - 3) more")
                                            .font(.custom("PlusJakartaSans-Medium", size: 10))
                                            .foregroundStyle(planning.secondaryInk)
                                    }
                                    Text("These go to the planner as calendar context; opening hours are checked per venue.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 10))
                                        .foregroundStyle(planning.secondaryInk)
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .planningSurface(radius: 15, raised: true)
                            }
                        }
                        if brief.dateIsUnknown {
                            HStack {
                                Text("Duration").font(.custom("PlusJakartaSans-Medium", size: 13))
                                Spacer()
                                counter(value: $brief.duration, range: 1...30, suffix: "d")
                            }
                            .padding(13).planningSurface(radius: 15, raised: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Who's traveling?")
                        PillFlowLayout {
                            ForEach(["Solo", "Couple", "Friends", "Family", "Work"], id: \.self) { group in
                                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.group = group } } label: { choicePill(group, selected: brief.group == group) }
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: brief.group)
                        HStack {
                            Text("Travelers").font(.custom("PlusJakartaSans-Medium", size: 13))
                            Spacer()
                            counter(value: $brief.travelers, range: 1...20, suffix: "")
                        }
                        .padding(13).background(planning.canvas, in: RoundedRectangle(cornerRadius: 15))
                    }
                        }
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    if briefStep == 1 { preferencesStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                    if briefStep == 2 { budgetStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                    if briefStep == 3 { finalBriefStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
                briefStepFooter
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(planning.ink)
        .tint(planning.brand)
        .background(planning.canvas)
        .onChange(of: brief) { _, _ in saveDraft() }
        .onChange(of: tripNameDraft) { _, _ in saveDraft() }
        .onChange(of: tripAppearanceDraft) { _, _ in saveDraft() }
    }

    private var briefStepTitles: [String] {
        ["Basics", "Preferences", "Cost", "Notes & planning"]
    }

    private var briefStepSubtitles: [String] {
        [
            "City, dates and who's coming first.",
            "Pick what fits; details open as you choose.",
            "Optionally set a budget and what it covers.",
            "Add your own notes and choose how to plan."
        ]
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("What feel do you want?")
                PillFlowLayout {
                    ForEach(["City", "Nature", "Beach", "Culture"], id: \.self) { vibe in
                        let selected = brief.vibes.contains(vibe)
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                                if selected { brief.vibes.remove(vibe) } else { brief.vibes.insert(vibe) }
                            }
                        } label: { choicePill(vibe, selected: selected).scaleEffect(selected ? 1.025 : 1) }
                            .buttonStyle(QuietPressStyle())
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.36, dampingFraction: 0.78), value: brief.vibes)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("What do you want to do?")
                Text(destinationPreferenceSummary)
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(planning.secondaryInk)
                PillFlowLayout(spacing: 8) {
                    ForEach(TripPreferenceCatalog.groups) { group in
                        let selected = brief.interests.contains(group.id)
                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                if selected {
                                    brief.interests.remove(group.id)
                                    brief.preferenceTags.subtract(group.children.map(\.id))
                                } else {
                                    brief.interests.insert(group.id)
                                }
                            }
                        } label: {
                            choicePill(group.title, selected: selected)
                                .scaleEffect(selected ? 1.025 : 1)
                        }
                        .buttonStyle(QuietPressStyle())
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: brief.interests)
            }

            ForEach(TripPreferenceCatalog.groups.filter { brief.interests.contains($0.id) && !$0.children.isEmpty }) { group in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.custom("PlusJakartaSans-Bold", size: 13))
                            .foregroundStyle(planning.ink)
                    }
                    PillFlowLayout(spacing: 8) {
                        ForEach(group.children) { option in
                            let selected = brief.preferenceTags.contains(option.id)
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                                    if selected { brief.preferenceTags.remove(option.id) }
                                    else { brief.preferenceTags.insert(option.id) }
                                }
                            } label: {
                                choicePill(option.title, selected: selected)
                                    .scaleEffect(selected ? 1.035 : 1)
                            }
                            .buttonStyle(QuietPressStyle())
                            .transition(.scale(scale: 0.84).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: brief.preferenceTags)
                }
                .padding(14)
                .planningSurface(radius: 17, raised: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Pace")
                HStack(spacing: 10) {
                    Text("Relaxed").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(planning.secondaryInk)
                    Slider(value: $pace, in: 0...1).tint(planning.accent)
                    Text("Full days").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(planning.secondaryInk)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Diet & allergies")
                chipGrid(options: ["Vegan", "Vegetarian", "Gluten-free", "Halal", "Nut-free", "Lactose-free"], selection: $brief.dietaryNeeds)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Mobility & access")
                chipGrid(options: ["Walkable", "Accessible", "Stroller", "Step-free"], selection: $brief.mobility)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Where do you want to stay?")
                PillFlowLayout {
                    ForEach(["Boutique / Hotel", "Apartment / Airbnb", "Hostal", "Value for Money"], id: \.self) { style in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.stayStyle = style }
                        } label: { choicePill(style, selected: brief.stayStyle == style) }
                            .buttonStyle(QuietPressStyle())
                    }
                }
            }
        }
        .padding(16)
        .planningSurface(radius: 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: brief.interests)
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("What's your budget?")
                HStack(spacing: 8) {
                    ForEach(["per person", "for everyone"], id: \.self) { basis in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.budgetBasis = basis }
                        } label: {
                            choicePill(basis == "per person" ? "Per person" : "Total for the group", selected: brief.budgetBasis == basis)
                        }
                        .buttonStyle(QuietPressStyle())
                    }
                }
                inputField("Optional maximum", placeholder: "e.g. €800", text: $brief.budget)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("What should it include?")
                Text("Choose what your amount covers. Leave it empty for separate estimates.")
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(planning.secondaryInk)
                chipGrid(options: ["Stay", "Getting into the city", "Getting around the city", "Food", "Tickets & activities"], selection: $brief.budgetIncludes)
            }
        }
        .padding(16)
        .planningSurface(radius: 20)
    }

    private var planningLibraryNodes: [PlanningLibraryNode] {
        let destination = MapCityGrouping.key(LibraryGrouping.cityTitle(brief.destination))
        func matches(_ city: String?) -> Bool {
            guard let city, !city.isEmpty else { return false }
            return MapCityGrouping.key(LibraryGrouping.cityTitle(city)) == destination
        }
        var nodes: [PlanningLibraryNode] = []
        let pins = savedPlaces.filter { matches($0.city) && ($0.isPinned || $0.isSaved) }
            + (activeTrip?.savedPins ?? []).filter { matches($0.city) }
        for place in pins {
            let kind = place.isPinned ? "pin" : "save"
            nodes.append(PlanningLibraryNode(id: "\(kind):\(place.id)", kind: kind, title: place.name,
                city: brief.destination, places: [PlanningLibraryPlace(place)]))
        }
        // Must-see places from the composer are scheduled like pins.
        for place in brief.mustSee {
            nodes.append(PlanningLibraryNode(id: "pin:must-see:\(place.name)", kind: "pin", title: place.name,
                city: brief.destination, places: [PlanningLibraryPlace(place)]))
        }
        for note in travelNotes where note.tripID == activeTripID && activeTripID != nil || (note.tripID == nil && matches(note.city)) {
            var places = (note.linkedPlaces ?? []).map { PlanningLibraryPlace($0) }
            places += pins.filter { (note.linkedPlaceIDs ?? []).contains($0.id) }.map { PlanningLibraryPlace($0) }
            nodes.append(PlanningLibraryNode(id: "note:\(note.id.uuidString)", kind: "note", title: note.title,
                city: brief.destination, text: String(note.userText.prefix(8000)), places: places))
        }
        for source in socialSources {
            let mentions = socialPlaces.filter { $0.sourceID == source.id &&
                (($0.tripID == activeTripID && activeTripID != nil) || ($0.tripID == nil && matches($0.city))) }
            guard !mentions.isEmpty || matches(source.city) || (source.envelope.destination.tripID == activeTripID && activeTripID != nil) else { continue }
            nodes.append(PlanningLibraryNode(id: "video:\(source.id.uuidString)", kind: "video",
                title: source.displayTitle ?? "Saved video", city: brief.destination,
                text: String(source.evidence.map(\.text).joined(separator: "\n").prefix(8000)),
                url: source.envelope.sourceURL, places: mentions.map { PlanningLibraryPlace($0) }))
        }
        // Reuse completed useful plans as context, preserving their source trip.
        for trip in trips where trip.id != activeTripID && matches(trip.brief.destination) {
            guard let raw = trip.research, let data = raw.data(using: .utf8),
                  let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  doc["delivery_status"] as? String == "ready", let places = doc["places"] as? [[String: Any]] else { continue }
            nodes.append(PlanningLibraryNode(id: "trip:\(trip.id.uuidString)", kind: "prior_trip", title: trip.title,
                city: brief.destination, places: Array(places.compactMap { PlanningLibraryPlace(research: $0) }.prefix(100))))
        }
        var seen = Set<String>()
        return Array(nodes.filter { seen.insert($0.id).inserted }.prefix(300)).map { node in
            var value = node
            value.include = !brief.excludedLibraryNodeIDs.contains(node.id)
            return value
        }
    }

    private var planningLibrarySelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Start a trip")
            Text("Your pins, saves, videos and notes for this city come first. Choose what to use.")
                .font(.custom("PlusJakartaSans-Regular", size: 12, relativeTo: .subheadline))
                .foregroundStyle(planning.secondaryInk)
            if planningLibraryNodes.isEmpty {
                Label("Save places or add a note, or start with new suggestions.", systemImage: "bookmark")
                    .font(.subheadline).foregroundStyle(planning.secondaryInk)
            } else {
                DisclosureGroup("Your library · \(planningLibraryNodes.filter(\.include).count) items") {
                    ForEach(planningLibraryNodes) { node in
                        Toggle(isOn: Binding(get: { !brief.excludedLibraryNodeIDs.contains(node.id) }, set: { selected in
                            if selected { brief.excludedLibraryNodeIDs.remove(node.id) }
                            else { brief.excludedLibraryNodeIDs.insert(node.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(node.title).font(.subheadline)
                                Text(node.kindTitle).font(.caption).foregroundStyle(planning.secondaryInk)
                            }
                        }
                        .tint(planning.brand).padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(14).planningSurface(radius: 17, raised: true)
    }

    /// Which indexed videos (TikTok and YouTube, read once for everyone) may add places to this plan.
    private var planningCommunitySelection: some View {
        let videos = planSources?.videos ?? []
        let picked = brief.communityVideos.intersection(videos.map(\.key))
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Videos about \(MapCityGrouping.name(brief.destination))")
            Text(videos.isEmpty ? (planSourcesLoading ? "Looking up what is already indexed for this city…" : "No indexed videos for this city yet. Share one and it helps every later plan.")
                 : "\(videos.count) indexed \(videos.count == 1 ? "video knows" : "videos know") \(planSources?.places ?? 0) places here. They add ideas below your own library and cost nothing to use.")
                .font(.custom("PlusJakartaSans-Regular", size: 12, relativeTo: .subheadline)).foregroundStyle(planning.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !videos.isEmpty {
                PillFlowLayout {
                    ForEach([("auto", "Use what fits"), ("picked", "Let me pick"), ("off", "Don’t use")], id: \.0) { value, title in
                        Button { TrippyHaptics.selection(); withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.communityUse = value } } label: {
                            choicePill(title, selected: brief.communityUse == value)
                        }
                    }
                }
                if brief.communityUse == "picked" {
                    VStack(spacing: 0) {
                        ForEach(videos) { video in
                            Toggle(isOn: Binding(get: { brief.communityVideos.contains(video.key) }, set: { on in
                                if on { brief.communityVideos.insert(video.key) } else { brief.communityVideos.remove(video.key) }
                            })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(video.title).font(.custom("PlusJakartaSans-SemiBold", size: 13, relativeTo: .subheadline)).lineLimit(2)
                                    Text("\(video.platform == "youtube" ? "YouTube" : "TikTok")\(video.author.map { " · " + $0 } ?? "") · \(video.usable) \(video.usable == 1 ? "place" : "places")")
                                        .font(.caption).foregroundStyle(planning.secondaryInk).lineLimit(1)
                                    if !video.topPlaces.isEmpty {
                                        Text(video.topPlaces.joined(separator: " · ")).font(.caption2).foregroundStyle(planning.secondaryInk).lineLimit(1)
                                    }
                                }
                            }
                            .tint(planning.brand).padding(.vertical, 7)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    Text(picked.isEmpty ? "Tick the videos to use. With none ticked, the plan uses only your library and fresh suggestions."
                         : "\(picked.count) ticked. Everything they recommend is considered, ranked just below your own videos.")
                        .font(.caption).foregroundStyle(planning.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14).planningSurface(radius: 17, raised: true)
        .task(id: brief.destination) {
            let city = brief.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !city.isEmpty, !bridgeToken.isEmpty else { planSources = nil; return }
            planSourcesLoading = true
            planSources = try? await CommunityVideosClient.planSources(city: city, baseURL: bridgeBaseURL, token: bridgeToken)
            planSourcesLoading = false
        }
    }

    private var finalBriefStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlanningDestinationCard(destination: brief.destination, dates: brief.libraryDateSummary, travelers: brief.travelers)
            planningLibrarySelection
            planningCommunitySelection
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Anything else?")
                Text("Limits, favorites, things to avoid, or anything that makes the trip yours.")
                    .font(.custom("PlusJakartaSans-Regular", size: 12))
                    .foregroundStyle(planning.secondaryInk)
            }
            TextField("Write it your way…", text: $brief.notes, axis: .vertical)
                .font(.custom("PlusJakartaSans-Regular", size: 14))
                .lineLimit(5...9)
                .padding(15)
                .planningSurface(radius: 17, raised: true)
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(planning.border, lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("How should we plan?")
                Button { startLiveResearch() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isResearching ? "Your plan is on its way…" : "Create my plan")
                                .font(.custom("PlusJakartaSans-Bold", size: 14))
                            Text("Your picks, plus new places")
                                .font(.custom("PlusJakartaSans-Regular", size: 10))
                                .opacity(0.84)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(planning.inverseInk)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(planning.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(QuietPressStyle())
                .disabled(isResearching || brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    selectedResearchLayer = .foundation
                    pendingPrompt = nil
                    showPromptSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(planning.canvas, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Manual planning")
                                .font(.custom("PlusJakartaSans-Bold", size: 14))
                                .foregroundStyle(planning.ink)
                            Text("Copy the prompt or import your own JSON")
                                .font(.custom("PlusJakartaSans-Regular", size: 10))
                                .foregroundStyle(planning.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(planning.brand)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .planningSurface(radius: 18, raised: true)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(planning.border, lineWidth: 0.8))
                }
                .buttonStyle(QuietPressStyle())
                .disabled(isResearching)
            }
        }
        .padding(16)
        .planningSurface(radius: 20)
    }

    private var briefStepFooter: some View {
        VStack(spacing: 10) {
            if briefStep < 3 {
                Button {
                    guard briefStep != 0 || !brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) { briefStep += 1 }
                } label: {
                    HStack {
                        Spacer()
                        Text(briefStep == 0 ? "Continue to preferences" : "Continue")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(planning.inverseInk)
                    .frame(height: 52)
                    .background(planning.brand, in: Capsule())
                }
                .buttonStyle(QuietPressStyle())
                .disabled(briefStep == 0 && brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(briefStep == 0 && brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)
            } else {
                Button {
                    pendingPrompt = nil
                    showPromptSheet = true
                } label: {
                    Label("Import a plan you already have", systemImage: "doc.badge.arrow.up")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                        .foregroundStyle(planning.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isResearching)
            }
            if briefStep > 0 {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { briefStep -= 1 }
                } label: {
                    Text("Back")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                        .foregroundStyle(planning.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(QuietPressStyle())
            }
        }
    }

    private var destinationPreferenceSummary: String {
        if brief.destination.localizedCaseInsensitiveContains("barcelona") || brief.destination.localizedCaseInsensitiveContains("βαρκελών") {
            return "Barcelona · options from the place catalog and travel-video themes."
        }
        return "Your choices steer the search toward local places and relevant travel sources."
    }

    private var promptSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Ready to plan")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .foregroundStyle(planning.ink)
                    Text("Copy the prompt into ChatGPT. When it finishes, paste the JSON reply here.")
                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                        .foregroundStyle(planning.secondaryInk)
                    if pendingPrompt == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Plan depth")
                                .font(.custom("PlusJakartaSans-Bold", size: 13))
                                .foregroundStyle(planning.ink)
                            ForEach(ResearchLayer.allCases) { layer in
                                Button { selectedResearchLayer = layer } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selectedResearchLayer == layer ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(selectedResearchLayer == layer ? planning.brand : planning.secondaryInk)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(layer.title).font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(planning.ink)
                                            Text(layer.detail).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(planning.secondaryInk).fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedResearchLayer == layer ? planning.brand.opacity(0.08) : planning.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selectedResearchLayer == layer ? planning.brand.opacity(0.32) : planning.ink.opacity(0.05), lineWidth: 1))
                                }.buttonStyle(QuietPressStyle())
                            }
                        }
                    }
                    Text(prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .planningSurface(radius: 18, raised: true)
                    Button { copyPrompt() } label: {
                        Label("Copy prompt", systemImage: "doc.on.doc")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(planning.brand, in: Capsule()).foregroundStyle(planning.inverseInk)
                    }
                    Button { showResearchFileImporter = true } label: {
                        Label("Import JSON file", systemImage: "doc.badge.arrow.up")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(planning.surface, in: Capsule()).foregroundStyle(planning.ink)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reply from ChatGPT").font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(planning.ink)
                        TextEditor(text: $importText)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 160)
                            .padding(8)
                            .planningSurface(radius: 16, raised: true)
                            .overlay(alignment: .topLeading) {
                                if importText.isEmpty {
                                    Text("Paste the JSON here…").font(.caption).foregroundStyle(planning.secondaryInk.opacity(0.7)).padding(.horizontal, 13).padding(.vertical, 17).allowsHitTesting(false)
                                }
                            }
                    }
                    Button {
                        importResearch()
                        if importError == nil { showPromptSheet = false }
                    } label: {
                        Text("Open trip").font(.custom("PlusJakartaSans-Bold", size: 15))
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color(hex: "FF6B5D"), in: Capsule()).foregroundStyle(planning.inverseInk)
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(importText.isEmpty ? 0.48 : 1)
                }
                .padding(22)
            }
            .background(planning.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showPromptSheet = false }.foregroundStyle(planning.brand)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func dateInput(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.custom("PlusJakartaSans-SemiBold", size: 10)).foregroundStyle(planning.secondaryInk)
            TextField("DD / MM", text: text).font(.custom("PlusJakartaSans-Medium", size: 13))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .planningSurface(radius: 15, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(planning.border, lineWidth: 0.8))
    }

    private func choicePill(_ title: String, selected: Bool) -> some View {
        PlanningChoicePill(title: title, selected: selected)
    }

    private func counter(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 10) {
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                Image(systemName: "minus").font(.caption.weight(.bold)).foregroundStyle(planning.ink).frame(width: 44, height: 44).planningSurface(radius: 22, raised: true)
            }
            Text("\(value.wrappedValue) \(suffix)").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(planning.ink).frame(minWidth: 42)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(planning.ink).frame(width: 44, height: 44).planningSurface(radius: 22, raised: true)
            }
        }
    }

    private func vibeIcon(_ vibe: String) -> String {
        switch vibe {
        case "City": return "building.2"
        case "Nature": return "mountain.2"
        case "Beach": return "water.waves"
        default: return "building.columns"
        }
    }

    private var workspace: some View {
        TabView(selection: $workspaceTab) {
            ForEach(["Plan", "Map", "Places", "Costs"], id: \.self) { tab in
                Group {
                    if tab == "Plan" {
                        scheduleList
                    } else if tab == "Map" {
                        fullScreenMap
                    } else {
                        ScrollView { workspacePage(tab) }
                    }
                }.background(AppPalette.canvas)
                .tag(tab)
                .tabItem {
                    Label {
                        Text(tab)
                    } icon: {
                        Image(systemName: workspaceSymbol(tab, selected: workspaceTab == tab))
                            .symbolEffect(.bounce, value: workspaceTab == tab)
                    }
                }
            }
        }
        .tint(workspaceNavigationTint)
        .background(AppPalette.canvas)
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let itemID = alternativesForItemID { alternativesSheet(itemID: itemID) }
        }
        .task { await resolvePlaceCoordinates() }
    }

    private var scheduleList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !showTripDetails { scheduleDayPicker }
                if let index = selectedScheduleDayIndex, dayRecords.indices.contains(index) {
                    planDayContent(dayRecords[index], index: index)
                } else { overviewDashboard }
            }
            .padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(AppPalette.canvas)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func planDayContent(_ day: [String: Any], index: Int) -> some View {
        let date = scheduleDateKey(day, index: index)
        let ids = scheduleIDs(day, index: index)
        let points = mapPoints(for: day, index: index)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recordValue(day, keys: ["theme"]) ?? "Your day").font(PlanType.title)
                Text("\(planDate(recordValue(day, keys: ["date"]) ?? "")) · \(ids.count) stops · suggested")
                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if !ids.isEmpty {
                PlanRouteMap(points: points, legs: planRouteLegs(day, index: index),
                             fallback: destinationCoordinate, missingCount: ids.count - points.count)
                    .id("\(activeTripID?.uuidString ?? ""):\(index)")
                if !dayIssues(day, index: index).isEmpty {
                    DisclosureGroup("Needs a check · \(dayIssues(day, index: index).count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(dayIssues(day, index: index), id: \.self) { Text($0).font(PlanType.detail) }
                            Button("Search places on the map") { Task { await resolvePlaceCoordinates() } }
                                .frame(minHeight: 44).disabled(isResolvingCoordinates)
                        }.padding(.top, 12)
                    }.font(PlanType.detail).tint(AppPalette.ink)
                }
                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { order, itemID in
                        scheduleRow(itemID: itemID, date: date, day: day)
                        if order < ids.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
            } else {
                Text("No stops suggested for this day.")
                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
            }
            Button { activeScheduleDate = date } label: {
                Label("Add stop", systemImage: "plus").font(PlanType.heading)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(AppPalette.inverseInk).background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(QuietPressStyle())
            if costAmount(day["estimated_day_cost_per_person_eur"]) != "—" { dayCostSummary(day) }
            if let alternative = recordValue(day, keys: ["alternative"]) {
                DisclosureGroup("Day alternative") { Text(alternative).font(PlanType.body).padding(.top, 12) }
                    .font(PlanType.detail).tint(AppPalette.ink)
            }
            if let flexibility = recordValue(day, keys: ["flex_time"]) {
                DisclosureGroup("Free time") { Text(flexibility).font(PlanType.body).padding(.top, 12) }
                    .font(PlanType.detail).tint(AppPalette.ink)
            }
        }.foregroundStyle(AppPalette.ink)
    }

    private func planDate(_ value: String) -> String {
        guard let date = parseISODate(value) else { return value.isEmpty ? "Flexible day" : value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "el_GR")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private func dayIssues(_ day: [String: Any], index: Int) -> [String] {
        let ids = scheduleIDs(day, index: index)
        let checks = records(["date_checks"])
        let date = recordValue(day, keys: ["date"]) ?? ""
        var issues: [String] = []
        for id in ids {
            let place = scheduledPlace(id, day: day)
            let stop = scheduledStop(id, day: day) ?? [:]
            let title = place.flatMap(recordTitle) ?? activityTitle(stop)
            if planCoordinate(id, day: day) == nil {
                issues.append("\(title): exact location missing for directions.")
            }
            if activeTrip?.scheduleEditsByItemID?[id]?.time?.nonEmpty == nil && recordValue(stop, keys: ["time", "start_time"]) == nil {
                issues.append("\(title): no visit time suggested.")
            }
            let placeID = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? recordValue(stop, keys: ["place_id"])
            let check = checks.first { recordValue($0, keys: ["entity_id"]) == placeID && recordValue($0, keys: ["local_date"]) == date }
            if recordValue(check, keys: ["status"]) != "confirmed" {
                issues.append("\(title): \(recordValue(check, keys: ["status"]) == "closed" ? "αναφέρεται κλειστό — διάλεξε άλλη στάση." : "το ωράριο και η διαθεσιμότητα της ημέρας χρειάζονται επιβεβαίωση.")")
            }
        }
        let pending = (researchRoot["plan_validation"] as? [String: Any])?["pending"] as? [[String: Any]] ?? []
        for item in pending where recordValue(item, keys: ["date"]) == date || item["date"] == nil {
            let messages = ["route_preview_required": "Travel needs a check on the map.",
                "time_or_route_conflict": "Times or travel clash; change the order or a time.",
                "hard_requirement_pending": "One of your requirements isn't confirmed.",
                "custom_instructions_need_review": "Check that your personal notes are covered.",
                "local_schedule_needs_review": "Your edits were kept; recheck times, travel and costs.",
                "selected_category_unscheduled": "A chosen category isn't in any day yet.",
                "event_time_and_location_need_review": "Events need an exact place and time before joining the plan.",
                "budget_coverage_pending": "Known prices aren't enough yet to check the total budget."]
            if let code = recordValue(item, keys: ["code"]), let message = messages[code], !issues.contains(message) { issues.append(message) }
        }
        return issues
    }

    private func planRouteLegs(_ day: [String: Any], index: Int) -> [TripRouteLeg] {
        let ids = scheduleIDs(day, index: index)
        guard ids.count > 1 else { return [] }
        return (1..<ids.count).compactMap { order in
            guard let from = planCoordinate(ids[order - 1], day: day), let to = planCoordinate(ids[order], day: day) else { return nil }
            let mode = recordValue(scheduledStop(ids[order], day: day), keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
            guard mode == nil || ["walk", "walking", "foot", "drive", "driving", "car"].contains(mode!) else { return nil }
            return TripRouteLeg(id: "\(ids[order - 1]):\(ids[order])", day: index, from: from, to: to,
                                walking: mode == nil ? routePreviewMode == "walking" : ["walk", "walking", "foot"].contains(mode!))
        }
    }

    private func planCoordinate(_ id: String, day: [String: Any]) -> CLLocationCoordinate2D? {
        scheduledPlace(id, day: day).flatMap(placeCoordinate) ?? scheduledStop(id, day: day).flatMap(coordinateFromRecord) ?? resolvedCoordinates[id] ?? activeTrip?.mapCoordinatesByPlaceID?[id]?.coordinate
    }

    private func openPlanDirections(_ id: String, day: [String: Any]) {
        let stop = scheduledStop(id, day: day) ?? [:]
        let name = scheduledPlace(id, day: day).flatMap(recordTitle) ?? activityTitle(stop)
        guard let coordinate = planCoordinate(id, day: day) else {
            var components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: "\(name), \(brief.destination)")]
            if let url = components.url { UIApplication.shared.open(url) }
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate)); item.name = name
        let mode = recordValue(stop, keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
        let driving = ["drive", "driving", "car"].contains(mode ?? routePreviewMode)
        let transit = ["transit", "metro", "bus", "train", "public_transport"].contains(mode ?? "")
        let dayIndex = dayRecords.enumerated().first { $0.element["date"] as? String == day["date"] as? String }?.offset ?? selectedScheduleDayIndex ?? 0
        let ids = scheduleIDs(day, index: dayIndex)
        var items = [item]
        if let order = ids.firstIndex(of: id), order > 0, let from = planCoordinate(ids[order - 1], day: day) {
            let origin = MKMapItem(placemark: MKPlacemark(coordinate: from))
            origin.name = scheduledPlace(ids[order - 1], day: day).flatMap(recordTitle) ?? "Previous stop"
            items.insert(origin, at: 0)
        }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: transit ? MKLaunchOptionsDirectionsModeTransit : (driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking)])
    }

    private var scheduleDayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                scheduleTab("Whole trip", subtitle: "", selected: selectedScheduleDayIndex == nil) { selectedScheduleDayIndex = nil; selectedMapDay = nil }
                ForEach(dayRecords.indices, id: \.self) { index in
                    scheduleTab("Day \(index + 1)", subtitle: "", selected: selectedScheduleDayIndex == index) { selectedScheduleDayIndex = index; selectedMapDay = index }
                }
            }
        }.scrollIndicators(.hidden)
    }
    private func scheduleTab(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PlanType.detail).foregroundStyle(selected ? AppPalette.inverseInk : AppPalette.ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(selected ? AppPalette.brand : AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var overviewDashboard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your trip").font(PlanType.title)
                Text("\(dayRecords.count) days · \(placeRecords.count) options").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if let quality = researchRoot["quality_report"] as? [String: Any], recordValue(quality, keys: ["status"]) != "ready" {
                DisclosureGroup("The plan needs more detail") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(quality["gaps"] as? [String] ?? [], id: \.self) { Text($0).font(PlanType.body) }
                    }.padding(.top, 12)
                }.font(PlanType.detail)
            }
            if let diagnostics = ResearchDiagnostics.summary(researchRoot) {
                DisclosureGroup("Plan and support details") {
                    Text(diagnostics).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding(.top, 12)
                    Button("Copy details") { UIPasteboard.general.string = diagnostics }
                        .font(PlanType.detail).padding(.top, 8)
                }.font(PlanType.detail)
            }
            if dayRecords.isEmpty { Text("No day plan yet. Available options are under Places.").font(PlanType.body) }
            VStack(spacing: 0) {
                ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                    Button { selectedScheduleDayIndex = index; selectedMapDay = index } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Text(String(index + 1)).font(PlanType.heading).frame(width: 32, height: 32)
                                .background(AppPalette.brand.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recordValue(day, keys: ["theme"]) ?? "Day \(index + 1)").font(PlanType.heading)
                                Text("\(planDate(recordValue(day, keys: ["date"]) ?? "")) · \(scheduleIDs(day, index: index).count) stops")
                                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                                if scheduleIDs(day, index: index).isEmpty { Text("Needs a plan").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                                else if !dayIssues(day, index: index).isEmpty { Text("Needs a check").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).padding(.top, 8)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 16).contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle())
                    if index < dayRecords.count - 1 { Divider() }
                }
            }
            DisclosureGroup("Summary and seasonal tips") {
                VStack(alignment: .leading, spacing: 16) {
                    Text(overviewText).font(PlanType.body)
                    ForEach((researchRoot["overview"] as? [String: Any])?["seasonal_notes"] as? [String] ?? [], id: \.self) {
                        Text($0).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.padding(.top, 16)
            }.font(PlanType.heading)
            DisclosureGroup("To do before the trip") { checklistContent.padding(.top, 16) }.font(PlanType.heading)
        }.foregroundStyle(AppPalette.ink).tint(AppPalette.ink)
    }

    private func selectedDayPage(_ index: Int) -> some View {
        planDayContent(dayRecords[index], index: index)
    }

    private func dayMap(points: [ResearchMapPoint], title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "map").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                Spacer()
                Text("Apple Maps · 3D where available").font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.secondaryInk)
            }
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                ForEach(points) { point in Marker(point.title, coordinate: point.coordinate).tint(AppPalette.brand) }
                if points.isEmpty, let destinationCoordinate {
                    Marker(brief.destination.isEmpty ? "Destination" : brief.destination, coordinate: destinationCoordinate).tint(AppPalette.accent)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
            .overlay(alignment: .bottomLeading) {
                if points.isEmpty {
                    Text(destinationCoordinate == nil ? "Stops appear once their locations are found." : "Showing the destination; stops appear once confirmed.")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7).background(.regularMaterial, in: Capsule()).padding(9)
                }
            }
            .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }.padding(11).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dayCostSummary(_ day: [String: Any]) -> some View {
        HStack {
            Text("Estimate / person").font(PlanType.detail)
            Spacer()
            Text(costAmount(day["estimated_day_cost_per_person_eur"])).font(PlanType.heading)
        }.foregroundStyle(AppPalette.ink)
    }

    private var tripHero: some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(vibe: brief.vibes.first ?? "City", destination: brief.destination)
                .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(brief.title).font(.custom("PlusJakartaSans-ExtraBold", size: 22)).foregroundStyle(.white)
                Text("\(brief.dateSummary) · \(brief.travelers) travelers · \(brief.group)")
                    .font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(.white.opacity(0.9))
            }.padding(14)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    private func workspaceSymbol(_ tab: String, selected: Bool = false) -> String {
        switch tab {
        case "Map": return selected ? "map.fill" : "map"
        case "Places": return selected ? "bookmark.fill" : "bookmark"
        case "Costs": return selected ? "eurosign.circle.fill" : "eurosign.circle"
        default: return selected ? "list.bullet.rectangle.fill" : "list.bullet"
        }
    }

    private func workspacePage(_ tab: String) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            ZStack(alignment: .bottom) {
                TripCover(vibe: brief.vibes.first ?? "City", destination: brief.destination)
                    .frame(height: 285)
                LinearGradient(colors: [.black.opacity(0.05), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(brief.title)
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .tracking(-0.7)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(brief.dateSummary)
                        Text("·")
                        Text("\(brief.travelers) travelers")
                        Text("·")
                        Text(brief.group)
                    }
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(AppPalette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17).padding(.vertical, 14)
                .background(AppPalette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 21, topTrailingRadius: 21, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .overlay(alignment: .top) {
                HStack {
                    Button { withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) { stage = .library } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppPalette.ink).frame(width: 40, height: 40)
                            .modifier(AdaptiveGlassControl(shape: .circle))
                    }
                    Spacer()
                    Button { withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) { stage = .brief } } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppPalette.ink).frame(width: 40, height: 40)
                            .modifier(AdaptiveGlassControl(shape: .circle))
                    }
                    .accessibilityLabel("Edit request")
                }
                .padding(15)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let quality = researchRoot["quality_report"] as? [String: Any],
               quality["status"] as? String == "partial" {
                DisclosureGroup {
                    ForEach(Array((quality["gaps"] as? [String] ?? []).enumerated()), id: \.offset) { _, gap in
                        Text(gap)
                            .font(.custom("PlusJakartaSans-Regular", size: 11))
                            .foregroundStyle(AppPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } label: {
                    Label("The plan has gaps", systemImage: "exclamationmark.circle")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                        .foregroundStyle(AppPalette.ink)
                }
                .padding(14)
                .background(AppPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            switch tab {
            case "Map":
                mapContent
            case "Places":
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your options").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                        Spacer()
                        Text("\(placeRecords.count) options").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    ForEach(Array(placeRecords.enumerated()), id: \.offset) { index, place in placeCard(place, index: index) }
                    if placeRecords.isEmpty { emptyResearchMessage }
                }
            case "Costs":
                VStack(alignment: .leading, spacing: 13) {
                    Text("Costs and bookings").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                    metricCard("€\(budgetTotal(for: "person").formatted(.number.precision(.fractionLength(0...2))))", label: "Total per person · your entries", symbol: "eurosign.circle")
                    analyticalCostTable
                    infoPanel("Tickets and bookings", symbol: "ticket") { ticketContent }
                    infoPanel("Getting around", symbol: "tram") { transportContent }
                    infoPanel("Holidays and hours", symbol: "calendar") { calendarContent }
                    budgetCalculator
                    checklistContent
                    sourcesSection
                }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your plan").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                        Spacer()
                        Text("\(dayRecords.count) days").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    if dayRecords.isEmpty {
                        dashboardSection("Plan summary", symbol: "sparkles") {
                            Text(overviewText).font(.custom("PlusJakartaSans-Regular", size: 13)).foregroundStyle(AppPalette.secondaryInk)
                            emptyResearchMessage
                        }
                    }
                    ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                        scheduleDay(day, index: index)
                    }
                    if !dayRecords.isEmpty { checklistContent; sourcesSection }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
    }

    private var fullScreenMap: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                    ForEach(mapPoints) { point in
                        let order = plannedMapLabels[point.id]
                        Marker(order.map { "\($0) · \(point.title)" } ?? point.title, coordinate: point.coordinate)
                            .tint(AppPalette.brand)
                    }
                    if mapPoints.isEmpty, let destinationCoordinate {
                        Marker(brief.destination, coordinate: destinationCoordinate).tint(AppPalette.accent)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea(edges: .top)

                VStack(alignment: .leading, spacing: 5) {
                    Text(mapHeaderTitle)
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 22))
                        .tracking(-0.5)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text(mapHeaderSubtitle)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .lineLimit(1)
                    Text(mapTripSentence)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 15, y: 7)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(AppPalette.canvas)
        }
    }

    private var mapHeaderTitle: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        return recordValue(mapOverview, keys: ["title"]) ?? brief.destination
    }

    private var mapHeaderSubtitle: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        return recordValue(mapOverview, keys: ["subtitle"]) ?? brief.dateSummary
    }

    private var mapTripSentence: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        if let sentence = recordValue(mapOverview, keys: ["trip_sentence", "summary"]), !sentence.isEmpty { return sentence }
        return overviewText
    }

    private var mapContent: some View {
        dayMap(points: mapPoints.map { point in
            let order = plannedMapLabels[point.id]
            return ResearchMapPoint(id: point.id, title: order.map { "\($0) · \(point.title)" } ?? point.title, latitude: point.latitude, longitude: point.longitude)
        }, title: "Whole trip · \(mapPoints.count) places")
    }

    private var emptyResearchMessage: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("The plan doesn't include this section.")
                .font(.custom("PlusJakartaSans-SemiBold", size: 13)).foregroundStyle(AppPalette.ink)
            Text("You can create a new prompt from the request and import an updated result.")
                .font(.custom("PlusJakartaSans-Regular", size: 12)).foregroundStyle(AppPalette.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var sourcesSection: some View {
        dashboardSection("Sources and updates", symbol: "link") {
            ForEach(Array(sourceRecords.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordTitle(source) ?? recordValue(source, keys: ["name", "url"]) ?? "Source")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
                    if let url = recordValue(source, keys: ["url", "source_url", "source_page_url"]), let link = URL(string: url) {
                        Link(url, destination: link).font(.custom("PlusJakartaSans-Regular", size: 11)).lineLimit(1)
                    }
                    if let checked = recordValue(source, keys: ["checked_at", "last_verified", "updated_at"]) {
                        Text("Checked: \(checked)").font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }
            if sourceRecords.isEmpty { Text("No source list in the reply.").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
        }
    }

    private func scheduleDay(_ day: [String: Any], index: Int) -> some View {
        let date = scheduleDateKey(day, index: index)
        let ids = scheduleIDs(day, index: index)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dayTitle(day, index: index)).font(.custom("PlusJakartaSans-Bold", size: 15)).foregroundStyle(AppPalette.ink)
                    Text(recordValue(day, keys: ["theme"]) ?? "Free day")
                        .font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                Button { activeScheduleDate = date } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppPalette.ink).frame(width: 36, height: 36)
                        .background(Color(hex: "FFE0D2"), in: Circle())
                }
                .accessibilityLabel("Add a stop to \(dayTitle(day, index: index))")
            }
            .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 8)

            if ids.isEmpty {
                Button { activeScheduleDate = date } label: {
                    Label("Add places from the options", systemImage: "plus.circle")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.brand)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                }.buttonStyle(QuietPressStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(ids, id: \.self) { itemID in
                        scheduleRow(itemID: itemID, date: date, day: day)
                            .draggable(itemID)
                            .dropDestination(for: String.self) { dragged, _ in
                                guard let source = dragged.first else { return false }
                                moveScheduleItem(source, before: itemID, date: date, day: day, index: index)
                                return true
                            }
                        if itemID != ids.last { Divider().padding(.leading, 42) }
                    }
                }
            }
            if let alternative = recordValue(day, keys: ["alternative"]), !alternative.isEmpty {
                Text(alternative).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    .padding(.horizontal, 13).padding(.vertical, 10)
            }
        }
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color(hex: "E9DDD2"), lineWidth: 0.7))
    }

    private func scheduleRow(itemID: String, date: String, day: [String: Any]) -> some View {
        let stop = scheduledStop(itemID, day: day) ?? [:]
        let place = scheduledPlace(itemID, day: day)
        let edit = activeTrip?.scheduleEditsByItemID?[itemID]
        let name = place.flatMap(recordTitle) ?? activityTitle(stop)
        let index = dayRecords.firstIndex { scheduleDateKey($0, index: 0) == date } ?? 0
        let ids = scheduleIDs(day, index: index)
        let order = ids.firstIndex(of: itemID) ?? 0
        let expanded = expandedScheduleItemIDs.contains(itemID)
        let time = edit?.time?.nonEmpty ?? recordValue(stop, keys: ["time", "start_time"]) ?? "No time"
        let duration = recordValue(stop, keys: ["duration_minutes"]) ?? place.flatMap { recordValue($0, keys: ["average_visit_minutes"]) }
        return HStack(alignment: .top, spacing: 12) {
            Text(String(order + 1)).font(PlanType.detail).foregroundStyle(AppPalette.brand)
                .frame(width: 32, height: 32).background(AppPalette.brand.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(duration.map { "\(time) · \($0) min" } ?? time).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        Text(name).font(PlanType.heading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button(expanded ? "Close details" : "Details and editing", systemImage: "pencil") {
                            if expanded { expandedScheduleItemIDs.remove(itemID) } else { expandedScheduleItemIDs.insert(itemID) }
                        }
                        Button("See other options", systemImage: "arrow.triangle.swap") { alternativesForItemID = itemID }
                        Button("Move up", systemImage: "arrow.up") { movePlanStop(itemID, day: day, index: index, offset: -1) }.disabled(order == 0)
                        Button("Move down", systemImage: "arrow.down") { movePlanStop(itemID, day: day, index: index, offset: 1) }.disabled(order == ids.count - 1)
                        Button("Remove stop", systemImage: "trash", role: .destructive) { removeScheduleItem(itemID, date: date, day: day) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(name)")
                }
                if let instruction = recordValue(stop, keys: ["instructions", "notes", "description"])
                    ?? place.flatMap({ recordValue($0, keys: ["why_recommended", "description"]) }) {
                    Text(instruction).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk).lineLimit(expanded ? nil : 3)
                }
                HStack(spacing: 16) {
                    Button { if planCoordinate(itemID, day: day) == nil { locatingPlanItemID = itemID } else { openPlanDirections(itemID, day: day) } } label: {
                        Label(planCoordinate(itemID, day: day) == nil ? "Choose a place" : "Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(PlanType.detail).frame(minHeight: 44)
                    }.buttonStyle(QuietPressStyle())
                    if let amount = edit?.costPerPerson?.nonEmpty ?? recordValue(stop, keys: ["estimated_cost_per_person_eur"]) {
                        Text("€\(amount) / person").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                    } else if let place, priceLabel(place) != "Price unconfirmed" {
                        Text(priceLabel(place)).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Suggested visit · booking confirmed separately.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        editField("Time", text: scheduleEditBinding(itemID, field: .time), prompt: "09:30")
                        editField("Your estimate / person (€)", text: scheduleEditBinding(itemID, field: .cost), prompt: "—", keyboard: .decimalPad)
                        if let address = place.flatMap({ recordValue($0, keys: ["address", "area"]) }) { Text(address).font(PlanType.body) }
                        if let place { activityInsights(place) }
                        if let url = place.flatMap({ recordValue($0, keys: ["official_url", "source_url", "url"]) }).flatMap(URL.init(string:)) {
                            Link("Official site", destination: url).font(PlanType.detail).frame(minHeight: 44)
                        }
                    }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.foregroundStyle(AppPalette.ink).padding(.vertical, 16)
    }

    private func movePlanStop(_ id: String, day: [String: Any], index: Int, offset: Int) {
        var ids = scheduleIDs(day, index: index)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + offset) else { return }
        ids.swapAt(from, from + offset)
        setScheduleOrder(ids, date: scheduleDateKey(day, index: index))
    }

    private func activityInsights(_ place: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if priceLabel(place) != "Price unconfirmed" { Text("Price: \(priceLabel(place))").font(PlanType.body) }
            else { Text("Price not confirmed.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
            if ratingLabel(place) != "—" { Text("Rating: \(ratingLabel(place))").font(PlanType.body) }
            if let duration = recordValue(place, keys: ["average_visit_minutes"]) { Text("Visit length: \(duration) min").font(PlanType.body) }
            if let reservation = recordValue(place, keys: ["reservation_required"]) { Text("Booking: \(reservation)").font(PlanType.body) }
            if let best = recordValue(place, keys: ["best_time"]) { Text("Suggested time: \(best)").font(PlanType.body) }
            if let dietary = place["dietary_options"] as? [String], !dietary.isEmpty { Text(dietary.joined(separator: " · ")).font(PlanType.body) }
            if let bestFor = place["best_for"] as? [String], !bestFor.isEmpty { Text("Good for: \(bestFor.joined(separator: " · "))").font(PlanType.body) }
            if let popularity = recordValue(place, keys: ["popularity"]) { Text(popularity).font(PlanType.body) }
            if let tags = place["tags"] as? [String], !tags.isEmpty {
                DisclosureGroup("Features") { Text(tags.joined(separator: " · ")).font(PlanType.body).padding(.top, 12) }.font(PlanType.detail)
            }
            let ids = Set(place["source_ids"] as? [String] ?? [])
            let sources = sourceRecords.filter { recordValue($0, keys: ["id"]).map(ids.contains) ?? false }
            if !sources.isEmpty {
                DisclosureGroup("Sources for this place") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                            if let url = recordValue(source, keys: ["url"]).flatMap(URL.init(string:)) {
                                Link(recordValue(source, keys: ["publisher", "title"]) ?? url.host ?? "Source", destination: url).font(PlanType.detail).frame(minHeight: 44)
                            }
                        }
                    }.padding(.top, 12)
                }.font(PlanType.detail)
            }
            if let checked = recordValue(place, keys: ["checked_at", "last_verified"]) { Text("Checked: \(planDate(checked))").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
        }
    }

    private enum ScheduleEditField { case time, cost }
    private func scheduleEditBinding(_ id: String, field: ScheduleEditField) -> Binding<String> {
        Binding(get: {
            let edit = activeTrip?.scheduleEditsByItemID?[id]
            switch field { case .time: return edit?.time ?? ""; case .cost: return edit?.costPerPerson ?? "" }
        }, set: { value in
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
            var edits = trips[index].scheduleEditsByItemID ?? [:]
            var edit = edits[id] ?? ScheduleItemEdit()
            switch field { case .time: edit.time = value; case .cost: edit.costPerPerson = value }
            edits[id] = edit; trips[index].scheduleEditsByItemID = edits; trips[index].updatedAt = .now; TripStorage.save(trips)
        })
    }
    private func editField(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            TextField(prompt, text: text).font(PlanType.body).keyboardType(keyboard)
                .frame(minHeight: 44).padding(.horizontal, 12).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 10))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var analyticalCostTable: some View {
        let costs = researchRoot["costs"] as? [String: Any] ?? [:]
        let rows: [(String, String, String)] = [
            ("Trip", costAmount(costs["per_person_estimate"]), "per person"),
            ("Trip", costAmount(costs["group_estimate"]), "group"),
            ("Stay", costAmount((costs["lodging_estimate"] as? [String: Any])?["group_total_eur"]), "group"),
            ("Stay", costAmount((costs["lodging_estimate"] as? [String: Any])?["per_room_per_night_eur"]), "room / night"),
            ("Transport and sights", costAmount((costs["transport_and_attractions_subtotal"] as? [String: Any])?["per_person_eur"]), "per person"),
            ("Food", costAmount((costs["food_estimate"] as? [String: Any])?["per_person_per_day_eur"]), "per person / day")
        ]
        return VStack(alignment: .leading, spacing: 16) {
            Text("Your budget").font(PlanType.title)
            ForEach(Array(rows.filter { $0.1 != "—" }.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) { Text(row.0).font(PlanType.heading); Text(row.2).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                    Spacer(); Text(row.1).font(PlanType.heading)
                }
            }
            if rows.allSatisfy({ $0.1 == "—" }) {
                Text("No total estimate yet. See known ticket prices below or add your own expenses.")
                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
            }
            if let subtotal = costs["known_scheduled_price_subtotal"] as? [String: Any], costAmount(subtotal) != "—" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Known stop prices: \(costAmount(subtotal))").font(PlanType.heading)
                    Text("Adult example · not the total trip cost.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                }
            }
            DisclosureGroup("What's included and what's missing") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.filter { $0.1 == "—" }.enumerated()), id: \.offset) { _, row in Text("\(row.0) (\(row.2)): no estimate found.").font(PlanType.body) }
                    if let methodology = recordValue(costs, keys: ["methodology"]) { Text(methodology).font(PlanType.body) }
                }.padding(.top, 12)
            }.font(PlanType.detail)
        }.foregroundStyle(AppPalette.ink).tint(AppPalette.ink)
    }

    private func costAmount(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        if let object = value as? [String: Any] {
            let currency = recordValue(object, keys: ["currency"]) ?? "EUR"
            let symbol = currency == "EUR" ? "€" : "\(currency) "
            let minimum = numericValue(object, keys: ["min"])
            let maximum = numericValue(object, keys: ["max"])
            if let minimum, let maximum { return minimum == maximum ? "\(symbol)\(planNumber(minimum))" : "\(symbol)\(planNumber(minimum))–\(maximum.formatted())" }
            if let minimum { return "from \(symbol)\(planNumber(minimum))" }
            if let maximum { return "up to \(symbol)\(planNumber(maximum))" }
            for key in ["per_person_eur", "per_person_per_day_eur", "group_total_eur"] {
                if let amount = numericValue(object, keys: [key]) { return "\(symbol)\(planNumber(amount))" }
            }
            return "—"
        }
        if let number = value as? NSNumber { return "€\(planNumber(number.doubleValue))" }
        if let text = value as? String, let amount = Double(text.replacingOccurrences(of: ",", with: ".")), amount.isFinite { return "€\(planNumber(amount))" }
        return "—"
    }
    private func planNumber(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func budgetTotal(for basis: String) -> Double {
        (activeTrip?.budgetEntries ?? []).filter { $0.basis == basis }
            .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }.reduce(0, +)
    }
    private var budgetCalculator: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Trip calculator", systemImage: "plus.forwardslash.minus")
                .font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            Text("Track your own amounts, per person or for the group.")
                .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Expense").font(.caption.weight(.semibold)); Spacer(); Text("Amount (€)").font(.caption.weight(.semibold)) }
                .foregroundStyle(AppPalette.secondaryInk)
            ForEach(activeTrip?.budgetEntries ?? []) { entry in
                HStack(spacing: 8) {
                    TextField("Category", text: budgetEntryBinding(entry.id, field: .title))
                        .font(.system(size: 12, weight: .medium))
                    TextField("0", text: budgetEntryBinding(entry.id, field: .amount)).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(width: 88).font(.system(size: 12, weight: .semibold))
                    Menu {
                        Button("Per person") { setBudgetBasis(entry.id, basis: "person") }
                        Button("Group") { setBudgetBasis(entry.id, basis: "group") }
                    } label: {
                        Text(entry.basis == "person" ? "/ person" : "group").font(.system(size: 9, weight: .semibold)).foregroundStyle(AppPalette.brand)
                    }
                    Button(role: .destructive) { updateBudgetEntries { $0.removeAll { $0.id == entry.id } } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(AppPalette.secondaryInk)
                    }.buttonStyle(QuietPressStyle())
                }.padding(10).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
            Button { updateBudgetEntries { $0.append(TripBudgetEntry()) } } label: {
                Label("Add expense", systemImage: "plus").font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.brand)
            }.buttonStyle(QuietPressStyle())
            HStack { Text("Per person"); Spacer(); Text("€\(budgetTotal(for: "person").formatted(.number.precision(.fractionLength(2))))").fontWeight(.bold) }
                .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink).padding(.top, 3)
            HStack { Text("For the whole group"); Spacer(); Text("€\(budgetTotal(for: "group").formatted(.number.precision(.fractionLength(2))))").fontWeight(.bold) }
                .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
            Text("Your entries stay separate from the plan's estimates.")
                .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
        }
    }
    private enum BudgetEditField: Equatable { case title, amount }
    private func budgetEntryBinding(_ id: UUID, field: BudgetEditField) -> Binding<String> {
        Binding(get: {
            (activeTrip?.budgetEntries ?? []).first(where: { $0.id == id }).map { field == .title ? $0.title : $0.amount } ?? ""
        }, set: { value in
            updateBudgetEntries { entries in
                guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
                if field == .title { entries[index].title = value } else { entries[index].amount = value }
            }
        })
    }
    private func updateBudgetEntries(_ mutation: (inout [TripBudgetEntry]) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var entries = trips[index].budgetEntries ?? []
        mutation(&entries); trips[index].budgetEntries = entries; trips[index].updatedAt = .now; TripStorage.save(trips)
    }
    private func setBudgetBasis(_ id: UUID, basis: String) {
        updateBudgetEntries { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].basis = basis
        }
    }
    private var ticketContent: some View {
        let tickets = records(["ticket_options", "tickets", "booking_options"])
        return VStack(alignment: .leading, spacing: 16) {
            if tickets.isEmpty { Text("No ticket prices found.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(tickets.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(recordTitle(item) ?? "Option \(index + 1)").font(PlanType.heading)
                    if costAmount(item["price_per_person_eur"]) != "—" { Text("\(costAmount(item["price_per_person_eur"])) / person").font(PlanType.body) }
                    if costAmount(item["group_price_eur"]) != "—" { Text("\(costAmount(item["group_price_eur"])) for the group").font(PlanType.body) }
                    if let notes = recordValue(item, keys: ["notes", "description"]) { Text(notes).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
                    if let url = recordValue(item, keys: ["booking_url", "official_url"]).flatMap(URL.init(string:)) {
                        Link("Official booking", destination: url).font(PlanType.detail).frame(minHeight: 44)
                    }
                    Divider()
                }
            }
        }.foregroundStyle(AppPalette.ink)
    }
    private var transportContent: some View {
        let options = records(["transport_options", "transport"])
        return VStack(alignment: .leading, spacing: 8) {
            if options.isEmpty { Text("No transport options.").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                VStack(alignment: .leading, spacing: 6) {
                    Text(recordTitle(option) ?? "Option \(index + 1)").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                    HStack { Text(recordValue(option, keys: ["best_for"]) ?? "Good for"); Spacer(); Text(priceLabel(option)) }
                        .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    if let checked = recordValue(option, keys: ["checked_at"]) { Text("Checked \(checked)").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk) }
                    if let url = recordValue(option, keys: ["official_url", "url"]).flatMap(URL.init(string:)) { Link("Official information", destination: url).font(.system(size: 10, weight: .semibold)) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var calendarContent: some View {
        let checks = records(["calendar_checks", "holiday_checks", "opening_hours_checks"])
        let dateChecks = records(["date_checks"])
        return VStack(alignment: .leading, spacing: 8) {
            if checks.isEmpty && dateChecks.isEmpty { Text("Holiday, venue and opening-hour checks aren't included.").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(AppPalette.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(recordValue(check, keys: ["date"]) ?? "Ημερομηνία μη διαθέσιμη") · \(recordValue(check, keys: ["name", "day", "title"]) ?? "Έλεγχος \(index + 1)")")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.ink)
                        Text("\(recordValue(check, keys: ["status"]) ?? "Not confirmed") · \(recordValue(check, keys: ["details", "note"]) ?? "Χωρίς επιπλέον λεπτομέρειες")")
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
            ForEach(Array(dateChecks.enumerated()), id: \.offset) { index, check in
                let entityID = recordValue(check, keys: ["entity_id", "place_id", "event_id"])
                let entity = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == entityID })
                let name = entity.flatMap { recordValue($0, keys: ["name", "title"]) } ?? recordValue(check, keys: ["entity_name"]) ?? "Venue or event \(index + 1)"
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: recordValue(check, keys: ["status"]) == "confirmed" ? "checkmark.seal" : "questionmark.circle")
                        .foregroundStyle(recordValue(check, keys: ["status"]) == "confirmed" ? Color(hex: "477461") : Color(hex: "D88A27"))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(recordValue(check, keys: ["local_date", "date"]) ?? "Ημερομηνία άγνωστη") · \(name)")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.ink)
                        let details = [recordValue(check, keys: ["status"]), recordValue(check, keys: ["opening_status"]), recordValue(check, keys: ["holiday_or_event"]), recordValue(check, keys: ["ticket_status"]), recordValue(check, keys: ["reservation_status"]), recordValue(check, keys: ["details", "note"])].compactMap { $0 }.filter { !$0.isEmpty }
                        Text(details.isEmpty ? "No verification details." : details.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        if let checked = recordValue(check, keys: ["checked_at"]) { Text("Checked \(checked)").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk) }
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }
    private var checklistContent: some View {
        let tasks = records(["booking_tasks", "checklist", "things_to_book"])
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Before you go", systemImage: "checklist").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                Spacer()
                Text("\((activeTrip?.checklistDoneIDs ?? []).count) / \(tasks.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(AppPalette.brand)
            }
            if tasks.isEmpty {
                Text("No booking tasks in the plan.").font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                    let id = recordValue(task, keys: ["id", "task_id"]) ?? "task-\(index)-\(recordValue(task, keys: ["task", "title"]) ?? "")"
                    let done = (activeTrip?.checklistDoneIDs ?? []).contains(id)
                    VStack(alignment: .leading, spacing: 6) {
                        Button { toggleChecklist(id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19)).foregroundStyle(done ? AppPalette.brand : AppPalette.secondaryInk).padding(.top, 1)
                                Text(recordValue(task, keys: ["task", "title", "name"]) ?? "Task \(index + 1)")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(done ? AppPalette.secondaryInk : AppPalette.ink)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(QuietPressStyle())
                        HStack(spacing: 8) {
                            if let priority = recordValue(task, keys: ["priority"]) {
                                Text(priority.uppercased()).font(.system(size: 8, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(Color(hex: "FFE7D9"), in: Capsule()).foregroundStyle(AppPalette.brand)
                            }
                            if let urgency = recordValue(task, keys: ["urgency_score"]).flatMap(Int.init), (1...10).contains(urgency) {
                                let urgencyColor = urgency >= 8 ? Color(hex: "D94A38") : (urgency >= 5 ? Color(hex: "D88A27") : Color(hex: "527968"))
                                HStack(spacing: 2) {
                                    ForEach(0..<min(3, max(1, Int(ceil(Double(urgency) / 3.4)))), id: \.self) { _ in
                                        Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                                    }
                                    Text("\(urgency)/10").font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                                }
                                .foregroundStyle(urgencyColor)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(urgencyColor.opacity(0.10), in: Capsule())
                                .accessibilityLabel("Urgency \(urgency) of 10")
                            }
                            if let due = recordValue(task, keys: ["due_date", "deadline"]) {
                                Label(due, systemImage: "calendar").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            if let url = recordValue(task, keys: ["url", "booking_url"]).flatMap(URL.init(string:)) {
                                Link(destination: url) { Label("Open booking", systemImage: "arrow.up.right").font(.system(size: 9, weight: .semibold)) }
                                    .lineLimit(1)
                            }
                        }
                        if let reason = recordValue(task, keys: ["urgency_reason"]), !reason.isEmpty {
                            Text(reason).font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
            if let warnings = researchRoot["warnings"] as? [Any], !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Plan notes").font(.system(size: 10, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                    ForEach(Array(warnings.prefix(8).enumerated()), id: \.offset) { _, warning in
                        Label(warningText(warning), systemImage: "exclamationmark.circle")
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 4)
            }
        }.padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
    private func toggleChecklist(_ id: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var done = trips[index].checklistDoneIDs ?? []
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        trips[index].checklistDoneIDs = done; trips[index].updatedAt = .now; TripStorage.save(trips)
    }

    private func reactionButton(_ symbol: String, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? AppPalette.brand : AppPalette.secondaryInk.opacity(0.72))
                .frame(width: 24, height: 22)
        }.buttonStyle(QuietPressStyle()).accessibilityLabel(label)
    }

    private func addToDaySheet(date: String) -> some View {
        NavigationStack {
            List {
                ForEach(Array(placeRecords.enumerated()), id: \.offset) { index, place in
                    Button { addPlaceToDay(place, date: date); activeScheduleDate = nil } label: {
                        HStack(spacing: 12) {
                            Image(systemName: MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "").symbol)
                                .font(.title3).foregroundStyle(AppPalette.brand).frame(width: 32, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recordTitle(place) ?? "Option \(index + 1)").font(PlanType.heading).foregroundStyle(AppPalette.ink)
                                Text("\(recordValue(place, keys: ["category", "type"]) ?? "Πρόταση") · \(ratingLabel(place))")
                                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(AppPalette.brand)
                        }.padding(.vertical, 3)
                    }.listRowBackground(AppPalette.surface)
                }
            }
            .scrollContentBackground(.hidden).background(AppPalette.canvas)
            .navigationTitle("Add to day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { activeScheduleDate = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func alternativesSheet(itemID: String) -> some View {
        let currentDay = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(itemID) }?.element ?? [:]
        let current = scheduledPlace(itemID, day: currentDay)
        let ranked = alternativePlaces(for: itemID)
        return NavigationStack {
            List {
                if let current {
                    Section("Replaces") { Text(recordTitle(current) ?? "Current stop").foregroundStyle(AppPalette.secondaryInk) }
                }
                Section("Other options") {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { index, place in
                        Button {
                            replaceScheduleItem(itemID, with: place)
                            alternativesForItemID = nil
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "").symbol)
                                .font(.title3).foregroundStyle(AppPalette.brand).frame(width: 32, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recordTitle(place) ?? "Option").font(PlanType.heading).foregroundStyle(AppPalette.ink)
                                    Text(alternativeReason(place, for: current)).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                                    Text("\(priceLabel(place)) · \(ratingLabel(place))").font(PlanType.detail).foregroundStyle(AppPalette.brand)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.swap").foregroundStyle(AppPalette.brand)
                            }.padding(.vertical, 3)
                        }.listRowBackground(AppPalette.surface)
                    }
                    if ranked.isEmpty { Text("No other options available. Ask ChatGPT to widen the search for this category and area.").font(.footnote).foregroundStyle(AppPalette.secondaryInk) }
                }
                Section {
                    Button {
                        openAlternativeResearch(itemID)
                    } label: {
                        Label("Find more options", systemImage: "magnifyingglass")
                            .font(PlanType.heading).foregroundStyle(AppPalette.brand)
                    }
                } footer: {
                    Text("A focused prompt will be created. Its answer adds options without replacing the plan.")
                }
            }
            .scrollContentBackground(.hidden).background(AppPalette.canvas)
            .navigationTitle("Alternatives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { alternativesForItemID = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func dayActivities(_ day: [String: Any]) -> [[String: Any]] {
        (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
    }
    private func scheduleDateKey(_ day: [String: Any], index: Int) -> String {
        recordValue(day, keys: ["date"]) ?? "day-\(index + 1)"
    }
    private func scheduleIDs(_ day: [String: Any], index: Int) -> [String] {
        let date = scheduleDateKey(day, index: index)
        if let saved = activeTrip?.scheduleOrderByDate?[date] { return saved }
        return dayActivities(day).indices.map { "stop|\(date)|\($0)" }
    }
    private func scheduledStop(_ id: String, day: [String: Any]) -> [String: Any]? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "stop", let index = Int(parts[2]) else { return nil }
        let stops = dayActivities(day)
        return stops.indices.contains(index) ? stops[index] : nil
    }
    private func scheduledPlace(_ id: String, day: [String: Any]) -> [String: Any]? {
        if id.hasPrefix("place|") {
            let placeID = String(id.dropFirst("place|".count))
            return placeRecords.first { recordValue($0, keys: ["id", "place_id"]) == placeID }
        }
        guard let placeID = scheduledStop(id, day: day).flatMap({ recordValue($0, keys: ["place_id"]) }) else { return nil }
        return placeRecords.first { recordValue($0, keys: ["id", "place_id"]) == placeID }
    }
    private func setScheduleOrder(_ order: [String], date: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var orders = trips[index].scheduleOrderByDate ?? [:]
        orders[date] = order
        trips[index].scheduleOrderByDate = orders
        trips[index].updatedAt = .now
        TripStorage.save(trips)
    }
    private func addPlaceToDay(_ place: [String: Any], date: String) {
        guard let placeID = recordValue(place, keys: ["id", "place_id"]),
              let located = dayRecords.enumerated().first(where: { scheduleDateKey($0.element, index: $0.offset) == date }) else { return }
        let current = scheduleIDs(located.element, index: located.offset)
        let id = "place|\(placeID)"
        guard !current.contains(id), !current.contains(where: { scheduledPlace($0, day: located.element).flatMap { recordValue($0, keys: ["id", "place_id"]) } == placeID }) else { showToast("This place is already in the day"); return }
        setScheduleOrder(current + [id], date: date)
    }
    private func removeScheduleItem(_ itemID: String, date: String, day: [String: Any]) {
        guard let located = dayRecords.enumerated().first(where: { scheduleDateKey($0.element, index: $0.offset) == date }) else { return }
        setScheduleOrder(scheduleIDs(day, index: located.offset).filter { $0 != itemID }, date: date)
    }
    private func moveScheduleItem(_ source: String, before target: String, date: String, day: [String: Any], index: Int) {
        var ids = scheduleIDs(day, index: index)
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target), from != to else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            ids.remove(at: from)
            let insertionIndex = ids.firstIndex(of: target) ?? min(to, ids.count)
            ids.insert(source, at: insertionIndex)
            setScheduleOrder(ids, date: date)
        }
    }
    private func setReaction(_ reaction: String, for itemID: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var reactions = trips[index].reactionsByItemID ?? [:]
        let newValue = reactions[itemID] == reaction ? nil : reaction
        reactions[itemID] = newValue
        if let day = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) })?.element,
           let placeID = scheduledPlace(itemID, day: day).flatMap({ recordValue($0, keys: ["id", "place_id"]) }) {
            reactions["place|\(placeID)"] = newValue
        }
        trips[index].reactionsByItemID = reactions
        trips[index].updatedAt = .now
        TripStorage.save(trips)
    }
    private func replaceScheduleItem(_ itemID: String, with place: [String: Any]) {
        guard let newID = recordValue(place, keys: ["id", "place_id"]),
              let located = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) }) else { return }
        let day = located.element
        let index = located.offset
        guard let position = scheduleIDs(day, index: index).firstIndex(of: itemID) else { return }
        let date = scheduleDateKey(day, index: index)
        var order = scheduleIDs(day, index: index)
        order[position] = "place|\(newID)"
        setScheduleOrder(order, date: date)
    }
    private func alternativePlaces(for itemID: String) -> [[String: Any]] {
        let day = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(itemID) }?.element ?? [:]
        let current = scheduledPlace(itemID, day: day)
        let currentID = current.flatMap { recordValue($0, keys: ["id", "place_id"]) }
        let currentCategory = current.flatMap { recordValue($0, keys: ["category", "type", "kind"]) }
        let currentTags = Set(current?["tags"] as? [String] ?? [])
        let origin = currentID.flatMap { resolvedCoordinates[$0] } ?? current.flatMap(placeCoordinate)
        let scheduledIDs = Set(dayRecords.enumerated().flatMap { index, day in
            scheduleIDs(day, index: index).compactMap { id in
                scheduledPlace(id, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) }
            }
        })
        return placeRecords.filter { recordValue($0, keys: ["id", "place_id"]) != currentID }
            .sorted { lhs, rhs in
                let lhsID = recordValue(lhs, keys: ["id", "place_id"]).map { "place|\($0)" }
                let rhsID = recordValue(rhs, keys: ["id", "place_id"]).map { "place|\($0)" }
                return alternativeScore(lhs, category: currentCategory, tags: currentTags, origin: origin) + reactionScore(lhsID) > alternativeScore(rhs, category: currentCategory, tags: currentTags, origin: origin) + reactionScore(rhsID)
            }
            .filter { place in
                guard let id = recordValue(place, keys: ["id", "place_id"]) else { return false }
                return !scheduledIDs.contains(id) || id == currentID
            }
    }
    private func alternativeScore(_ place: [String: Any], category: String?, tags: Set<String>, origin: CLLocationCoordinate2D?) -> Double {
        var score = 0.0
        let candidateCategory = recordValue(place, keys: ["category", "type", "kind"]) ?? ""
        if !candidateCategory.isEmpty, let category,
           candidateCategory.localizedCaseInsensitiveContains(category) || category.localizedCaseInsensitiveContains(candidateCategory) { score += 8 }
        let candidateTags = Set(place["tags"] as? [String] ?? [])
        score += Double(candidateTags.intersection(tags).count) * 2.5
        if let origin, let coordinate = placeCoordinate(place) {
            let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            score += max(0, 8 - meters / 1500)
        }
        if let rating = place["rating"] as? [String: Any], let value = rating["value"] as? NSNumber { score += value.doubleValue }
        if let reviews = place["rating"] as? [String: Any], let count = reviews["review_count"] as? NSNumber { score += min(3, log10(max(1, count.doubleValue))) }
        return score
    }
    private func reactionScore(_ itemID: String?) -> Double {
        guard let itemID else { return 0 }
        switch activeTrip?.reactionsByItemID?[itemID] {
        case "like": return 5
        case "dislike": return -12
        default: return 0
        }
    }
    private func alternativeReason(_ place: [String: Any], for current: [String: Any]?) -> String {
        if let current, let origin = placeCoordinate(current), let coordinate = placeCoordinate(place) {
            let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance < 1000 { return "\(Int(distance.rounded())) m from the current stop" }
            if distance < 10_000 { return "\(String(format: "%.1f", distance / 1000)) km from the current stop" }
        }
        if let currentCategory = current.flatMap({ recordValue($0, keys: ["category", "type", "kind"]) }),
           let category = recordValue(place, keys: ["category", "type", "kind"]), category == currentCategory { return "Same category · fits the plan" }
        if let currentArea = current.flatMap({ recordValue($0, keys: ["area", "neighborhood", "address"]) }),
           let area = recordValue(place, keys: ["area", "neighborhood", "address"]), currentArea == area { return "Nearby · similar option" }
        return recordValue(place, keys: ["category", "type", "kind"]) ?? "Related option"
    }
    private func placeCoordinate(_ place: [String: Any]) -> CLLocationCoordinate2D? {
        let id = recordValue(place, keys: ["id", "place_id"])
        // Fresh coordinates in the research must replace a stale search cache.
        if let coordinate = coordinateFromRecord(place) { return coordinate }
        if let id, let resolved = resolvedCoordinates[id], CLLocationCoordinate2DIsValid(resolved) { return resolved }
        if let id, let stored = activeTrip?.mapCoordinatesByPlaceID?[id], CLLocationCoordinate2DIsValid(stored.coordinate) { return stored.coordinate }
        return nil
    }

    private func dayCard(_ day: [String: Any], index: Int) -> some View {
        let isExpanded = expandedDayIndices.contains(index)
        let activities = (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    if isExpanded { expandedDayIndices.remove(index) }
                    else { expandedDayIndices.insert(index) }
                }
            } label: {
                HStack(spacing: 11) {
                    TripCover(vibe: brief.vibes.first ?? "City", destination: brief.destination)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayTitle(day, index: index))
                            .font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                        Text(recordSummary(day))
                            .font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
            }
            .buttonStyle(QuietPressStyle())
            if isExpanded && !activities.isEmpty {
                Divider().overlay(Color(hex: "EADFD5")).padding(.horizontal, 12)
                VStack(spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.offset) { _, activity in
                        HStack(alignment: .top, spacing: 10) {
                            Text(recordValue(activity, keys: ["time", "start_time"]) ?? "·")
                                .font(.custom("PlusJakartaSans-Bold", size: 10)).foregroundStyle(AppPalette.accent).frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activityTitle(activity)).font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
                                Text(recordSummary(activity)).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "plus").font(.caption.weight(.medium)).foregroundStyle(AppPalette.secondaryInk)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                    }
                }
            }
        }
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color(hex: "E9DDD2"), lineWidth: 0.7))
    }

    private func placeCard(_ place: [String: Any], index: Int) -> some View {
        let id = recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)"
        let expanded = expandedPlanPlaceIDs.contains(id)
        let saved = activeTrip?.reactionsByItemID?["place|\(id)"] == "like"
        let category = MapPlaceCategory.classify(recordValue(place, keys: ["category", "type", "kind"]) ?? "")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                let coordinate = placeCoordinate(place)
                PlacePhoto(name: recordTitle(place) ?? "", latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                           sight: !["food", "coffee", "bar", "nightlife"].contains(recordValue(place, keys: ["category"]) ?? ""),
                           symbol: category.symbol, tint: AppPalette.brand)
                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    if expanded { expandedPlanPlaceIDs.remove(id) } else { expandedPlanPlaceIDs.insert(id) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recordTitle(place) ?? "Option \(index + 1)").font(PlanType.heading)
                        Text(category.rawValue).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        if let reason = recordValue(place, keys: ["why_recommended"]) { Text(reason).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk).lineLimit(expanded ? nil : 2) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityHint("Opens details and adds to the plan")
                Button { setReaction("like", for: "place|\(id)") } label: {
                    Image(systemName: saved ? "heart.fill" : "heart").frame(width: 44, height: 44)
                }.buttonStyle(QuietPressStyle()).accessibilityLabel(saved ? "Remove from favorites" : "Keep this option")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageURL = recordValue(place, keys: ["image_url", "photo_url"]) {
                        PlaceImage(title: recordTitle(place) ?? "", imageURL: imageURL).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                        if let attribution = recordValue(place, keys: ["image_attribution"]) { Text(attribution).font(PlanType.detail) }
                    }
                    Text(recordSummary(place)).font(PlanType.body)
                    activityInsights(place)
                    if let url = recordValue(place, keys: ["official_url", "source_url", "url"]).flatMap(URL.init(string:)) {
                        Link("Official site", destination: url).font(PlanType.detail).frame(minHeight: 44)
                    }
                    if !dayRecords.isEmpty {
                        Menu {
                            ForEach(dayRecords.indices, id: \.self) { dayIndex in
                                Button("Day \(dayIndex + 1) · \(planDate(recordValue(dayRecords[dayIndex], keys: ["date"]) ?? ""))") {
                                    addPlaceToDay(place, date: scheduleDateKey(dayRecords[dayIndex], index: dayIndex))
                                }
                            }
                        } label: { Label("Add to a day", systemImage: "plus").font(PlanType.heading).frame(minHeight: 44) }
                    }
                }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Divider()
        }.foregroundStyle(AppPalette.ink)
    }

    @ViewBuilder private func stageHeader(title: String, back: TripStage) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation { stage = back } } label: {
                Image(systemName: "arrow.left").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.ink).frame(width: 42, height: 42)
                    .modifier(AdaptiveGlassControl(shape: .circle))
            }
            if !title.isEmpty {
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(AppPalette.ink).lineLimit(1)
            }
            Spacer()
            if back == .library && stage != .brief {
                Button { withAnimation { darkMode.toggle() } } label: {
                    Image(systemName: darkMode ? "sun.max" : "moon").foregroundStyle(AppPalette.ink).frame(width: 42, height: 42).modifier(AdaptiveGlassControl(shape: .circle))
                }
            }
        }
        .padding(.horizontal, 20).frame(height: 50)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(planning.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputField(_ title: String, placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(planning.secondaryInk)
            TextField(placeholder, text: text, axis: axis)
                .font(.body).foregroundStyle(planning.ink).padding(14).planningSurface(radius: 15, raised: true)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipGrid(options: [String], selection: Binding<Set<String>>) -> some View {
        PillFlowLayout {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue.contains(option)
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        if selected { selection.wrappedValue.remove(option) }
                        else { selection.wrappedValue.insert(option) }
                    }
                } label: {
                    choicePill(option, selected: selected)
                        .scaleEffect(selected ? 1.035 : 1)
                }
                .buttonStyle(QuietPressStyle())
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: selection.wrappedValue)
    }

    private func dashboardSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12, content: content).padding(.top, 10)
        } label: {
            Label(title, systemImage: symbol).font(.headline.weight(.semibold)).foregroundStyle(AppPalette.ink)
        }
        .tint(AppPalette.accent)
        .padding(16)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func infoPanel<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func metricCard(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent)
                        Text(value).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(AppPalette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func createTrip(from initialBrief: TripBrief = TripBrief()) {
        activeTripID = TripDraftPersistence.save(trips: &trips, activeID: activeTripID,
                                                 brief: initialBrief, name: tripNameDraft, researchStarted: true)
        if let index = trips.firstIndex(where: { $0.id == activeTripID }) { trips[index].appearance = tripAppearanceDraft }
        TripStorage.save(trips)
    }

    private func startNewTrip() {
        guard stage != .brief, !isResearching else { return }
        openComposer(for: nil)
    }

    /// The detailed step-by-step brief, kept for travelers who want every option.
    private func startDetailedTrip() {
        guard stage != .brief, !isResearching else { return }
        destinationSearchTask?.cancel(); destinationCompleter.cancel(); holidayTask?.cancel()
        destinationSuggestions = []; destinationConfirmedQuery = ""
        activeTripID = nil; tripNameDraft = ""; tripAppearanceDraft = nil; brief = TripBrief()
        briefStep = 0; pendingPrompt = nil
        resolvedCoordinates = [:]; destinationCoordinate = nil
        selectedMapDay = nil; selectedScheduleDayIndex = nil
        activeScheduleDate = nil; alternativesForItemID = nil; showTripDetails = false
        // Present on the next main-loop turn, after a Menu has dismissed.
        Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { stage = .brief }
        }
    }

    private func editTrip(_ trip: Trip) {
        activeTripID = trip.id
        brief = trip.brief
        tripNameDraft = trip.title
        cardDrag = 0
        openBrief()
    }

    private func deleteTrip(_ id: UUID) {
        guard trips.contains(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            trips.removeAll { $0.id == id }
            cardDrag = 0
            briefReveal = 0
            gestureTripID = nil
            selectedCard = min(selectedCard, max(0, trips.count - 1))
            selectedScrollID = trips.isEmpty ? nil : selectedCard
            if activeTripID == id {
                activeTripID = nil; brief = TripBrief(); stage = .library
                showTripDetails = false; resolvedCoordinates = [:]; destinationCoordinate = nil
            }
        }
        TripStorage.save(trips)
    }

    private func finishBriefReveal() {
        TrippyHaptics.selection()
        isRevealingBrief = true
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.42, extraBounce: 0)
        withAnimation(animation, completionCriteria: .removed) {
            briefReveal = 1
            cardDrag = 0
        } completion: {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // The same brief is already in its final position; only enable interaction.
                stage = .brief
                briefReveal = 0
                gestureTripID = nil
                isRevealingBrief = false
            }
        }
    }

    private func openBrief() {
        tripNameDraft = activeTrip?.title ?? ""
        tripAppearanceDraft = activeTrip?.appearance
        briefStep = 0
        withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) { stage = .brief }
    }

    private func saveDraft() {
        guard let id = TripDraftPersistence.save(trips: &trips, activeID: activeTripID,
                                                 brief: brief, name: tripNameDraft, researchStarted: false) else { return }
        activeTripID = id
        if let index = trips.firstIndex(where: { $0.id == id }) { trips[index].appearance = tripAppearanceDraft }
        TripStorage.save(trips)
    }

    private func copyPrompt() {
        UIPasteboard.general.string = prompt
        showToast("Prompt copied")
    }

    private func openAlternativeResearch(_ itemID: String) {
        guard let located = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) }) else { return }
        let place = scheduledPlace(itemID, day: located.element)
        let stop = scheduledStop(itemID, day: located.element)
        let activity = stop.flatMap { recordValue($0, keys: ["activity", "title", "name"]) }
        pendingPrompt = ResearchPrompt.makeAlternatives(
            brief: brief,
            currentPlace: place,
            activity: activity,
            placePool: placeRecords,
            reactions: activeTrip?.reactionsByItemID ?? [:],
            selectedRegion: selectedRegion
        )
        alternativesForItemID = nil
        showPromptSheet = true
    }

    private func importResearch() {
        guard let (source, parsedObject) = Self.parseResearchJSON(importText) else {
            importError = "No valid JSON object found. Paste the whole reply or import the .json file ChatGPT created."
            return
        }
        var object = parsedObject
        var sourceToStore = source
        if object["schema_version"] as? String == "trippy-research-patch-v2" {
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }),
                  let existing = trips[index].research,
                  let existingData = existing.data(using: .utf8),
                  var merged = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                importError = "Import the base plan JSON before checking or updating it."
                return
            }
            for (key, value) in object["set"] as? [String: Any] ?? [:] { merged[key] = value }
            for (key, value) in object["replace"] as? [String: Any] ?? [:] { merged[key] = value }
            for (key, incomingRows) in object["upsert"] as? [String: [[String: Any]]] ?? [:] {
                var rows = merged[key] as? [[String: Any]] ?? []
                for incoming in incomingRows {
                    guard let id = recordValue(incoming, keys: ["id", "place_id", "event_id", "task_id"]) else { continue }
                    if let index = rows.firstIndex(where: { recordValue($0, keys: ["id", "place_id", "event_id", "task_id"]) == id }) {
                        rows[index].merge(incoming) { _, new in new }
                    } else {
                        rows.append(incoming)
                    }
                }
                merged[key] = rows
            }
            let newWarnings = object["warnings"] as? [[String: Any]] ?? []
            if !newWarnings.isEmpty { merged["warnings"] = (merged["warnings"] as? [[String: Any]] ?? []) + newWarnings }
            object = merged
            guard let mergedData = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
                  let mergedString = String(data: mergedData, encoding: .utf8) else {
                importError = "The update couldn't be merged with the existing plan."
                return
            }
            sourceToStore = mergedString
        } else if object["schema_version"] as? String == "trippy-research-patch-v1" {
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }),
                  let existing = trips[index].research,
                  let existingData = existing.data(using: .utf8),
                  var merged = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                importError = "The result adds options, but there's no earlier plan to extend."
                return
            }
            for (patchKey, targetKey) in [("add_places", "places"), ("add_sources", "sources")] {
                let existingRows = merged[targetKey] as? [[String: Any]] ?? []
                let newRows = object[patchKey] as? [[String: Any]] ?? []
                var seen = Set(existingRows.compactMap { recordValue($0, keys: ["id", "place_id"]) })
                merged[targetKey] = existingRows + newRows.filter { row in
                    guard let id = recordValue(row, keys: ["id", "place_id"]) else { return false }
                    return seen.insert(id).inserted
                }
            }
            let oldWarnings = merged["warnings"] as? [[String: Any]] ?? []
            let newWarnings = object["warnings"] as? [[String: Any]] ?? []
            merged["warnings"] = oldWarnings + newWarnings
            object = merged
            guard let mergedData = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
                  let mergedString = String(data: mergedData, encoding: .utf8) else {
                importError = "Couldn't merge the new options with the existing plan."
                return
            }
            sourceToStore = mergedString
        } else if object["schema_version"] == nil || object["schema_version"] as? String != "trippy-research-v1" {
            importError = "The file is valid JSON but doesn't match the Trippy format."
            return
        }
        if activeTripID == nil { createTrip(from: brief) }
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        object = PlanImportReconciliation.apply(object, to: &trips[index])
        guard let reconciledData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let reconciledSource = String(data: reconciledData, encoding: .utf8) else {
            importError = "Couldn't keep your edits during import."
            return
        }
        sourceToStore = reconciledSource
        trips[index].research = sourceToStore
        trips[index].brief = brief
        trips[index].updatedAt = .now
        TripStorage.save(trips)
        pendingPrompt = nil
        withAnimation { stage = .workspace }
    }

    private func startLiveResearch() {
        guard !isResearching, !brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activeTripID == nil { createTrip(from: brief) }
        guard let requestedTripID = activeTripID, let requestedTripIndex = trips.firstIndex(where: { $0.id == requestedTripID }) else { return }
        let researchBaseURL = trips[requestedTripIndex].researchBridgeURL ?? bridgeBaseURL
        let resumableJobID = trips[requestedTripIndex].researchJobID
        if resumableJobID == nil { trips[requestedTripIndex].brief = brief; TripStorage.save(trips) }
        completedResearchSteps = []
        researchNeedsServiceUpdate = false
        researchSaved = false
        researchPartial = false
        researchDestination = brief.destination
        researchResultTripID = requestedTripID
        isResearching = true
        liveResearchError = nil
        liveResearchDiagnostic = nil
        researchNeedsNewRequest = false
        researchPhaseStates = [:]
        recoverableResearch = nil
        liveResearchStep = 1
        researchOperations = [ResearchOperation(step: 1, detail: "Connecting to the planning service…")]
        planningLive = PlanningLive(startedAt: .now, libraryItems: planningLibraryNodes.filter(\.include).count,
                                    tripDays: max(brief.duration, 1), travelers: brief.travelers)
        showLiveResearchSheet = true

        let briefContext: [String: Any] = [
            "planning_strategy": "personal_places",
            "library_nodes": planningLibraryNodes.map(\.payload),
            "community": ["use": brief.communityUse, "videos": brief.communityUse == "picked" ? brief.communityVideos.sorted() : []] as [String: Any],
            "destination": brief.destination,
            "date_range": [
                "arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                "dates_unknown": brief.dateIsUnknown,
                "duration_days": brief.duration,
                "arrival_time": brief.arrivalTime.isEmpty ? NSNull() : brief.arrivalTime as Any,
                "departure_time": brief.departureTime.isEmpty ? NSNull() : brief.departureTime as Any
            ] as [String: Any],
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget": brief.budget,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "dietary_needs": brief.dietaryNeeds.sorted(),
            "mobility_requirements": brief.mobility.sorted(),
            "stay_style": brief.stayStyle,
            "custom_instructions": brief.notes,
            "existing_places": Array(placeRecords.prefix(150)),
            "existing_sources": Array(sourceRecords.prefix(150)),
            "excluded_place_ids": (activeTrip?.reactionsByItemID ?? [:]).compactMap { key, value in
                value == "dislike" && key.hasPrefix("place|") ? String(key.dropFirst(6)) : nil
            },
            "pace": brief.paceMode.isEmpty ? (pace < 0.34 ? "relaxed" : (pace > 0.66 ? "intense" : "balanced")) : brief.paceMode,
            "arrival_mode": brief.travelMode
        ]

        liveResearchTask = Task {
            var requestStage = ResearchRequestStage.preflight
            var activeJobID = resumableJobID
            do {
                // Check compatibility before starting either paid AI request.
                guard let preflightURL = URL(string: "\(researchBaseURL)/api/status?strategy=personal_places") else { throw URLError(.badURL) }
                var preflight = URLRequest(url: preflightURL, cachePolicy: .reloadIgnoringLocalCacheData)
                preflight.timeoutInterval = 60
                let (statusData, preflightResponse) = try await URLSession.shared.data(for: preflight)
                try Task.checkCancellation()
                let status = try ResearchTransport.checkedJSON(statusData, response: preflightResponse, stage: .preflight, checkResearchReadiness: resumableJobID == nil)
                guard (status["api_version"] as? Int ?? 0) >= 3,
                      (status["research_contract_version"] as? Int ?? 0) >= 4,
                      status["result_schema"] as? String == "trippy-research-v1",
                      resumableJobID != nil || (status["planning_strategies"] as? [String] ?? []).contains("personal_places") else {
                    await MainActor.run {
                        researchNeedsServiceUpdate = true
                        if status["step"] as? String == "completed", let result = status["result"] as? [String: Any] {
                            recoverableResearch = result
                            recoveryContext = status["request_context"] as? [String: Any] ?? briefContext
                            researchOperations = []
                            liveResearchError = "The service needs an update. You can recover the existing plan without planning again."
                        } else {
                            liveResearchError = "The service doesn't have the new planner yet. Nothing started and nothing was charged."
                        }
                        isResearching = false
                    }
                    return
                }
                await MainActor.run {
                    completedResearchSteps.insert(1)
                    recordResearchOperation(2, detail: resumableJobID == nil ? "Finding options for your trip…" : "Recovering the saved plan…")
                }
                let jobID: String
                requestStage = .start
                if let existingJobID = resumableJobID { jobID = existingJobID }
                else {
                guard let url = URL(string: "\(researchBaseURL)/api/research") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(bridgeToken)", forHTTPHeaderField: "Authorization")
                request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
                if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
                // Every day starts from the stay: send it as the plan's base.
                var body = briefContext
                if let base = await planningBase(destination: brief.destination) { body["base"] = base }
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                let (startData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 409 {
                    await MainActor.run {
                        liveResearchError = "A plan is already running on the service. Wait for it to finish and try again."
                        liveResearchDiagnostic = "start: HTTP 409, research_already_running"
                        isResearching = false
                    }
                    return
                }

                // Plans cost credits: no account, or this month's free plans used, gets a clear next step.
                if let http = response as? HTTPURLResponse, [401, 429].contains(http.statusCode),
                   let code = (try? JSONSerialization.jsonObject(with: startData) as? [String: Any])?["error"] as? String,
                   ["account_required", "access_token_required", "credits_used"].contains(code) {
                    await MainActor.run {
                        liveResearchError = code != "credits_used"
                            ? "Plans need a free Trippy account. Sign in from Settings → Account, then try again."
                            : "You’ve used this month’s free plans. They renew on the 1st."
                        liveResearchDiagnostic = "start: HTTP \(http.statusCode), \(code)"
                        isResearching = false
                    }
                    return
                }

                let started = try ResearchTransport.checkedJSON(startData, response: response, stage: .start)
                guard
                      let createdJobID = started["job_id"] as? String, UUID(uuidString: createdJobID) != nil else {
                    throw URLError(.cannotParseResponse)
                }
                jobID = createdJobID
                activeJobID = createdJobID
                await MainActor.run {
                    if let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                        trips[index].researchJobID = jobID; trips[index].researchBridgeURL = researchBaseURL
                        TripStorage.save(trips)
                    }
                }
                }
                requestStage = .status
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1.5))
                    guard let statusURL = URL(string: "\(researchBaseURL)/api/status?job_id=\(jobID)") else { throw URLError(.badURL) }
                    let json = try await ResearchTransport.status(url: statusURL)
                    try Task.checkCancellation()

                    let isRunning = json["is_running"] as? Bool ?? false
                    let step = json["step"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    let result = json["result"] as? [String: Any]
                    let currentTask = json["current_task"] as? String ?? ""
                    let completedPhases = json["completed_research_phases"] as? [Int] ?? []
                    let serverErrorCode = json["error_code"] as? String ?? "research_failed"

                    await MainActor.run {
                        completedResearchSteps = ResearchOperation.completedPhases(completedPhases).union([1])
                        researchPhaseStates = ResearchDiagnostics.phaseStates(json)
                        planningLive.absorb(status: json)
                        if let phase = ResearchOperation.phase(serverStep: step, task: currentTask) {
                            recordResearchOperation(phase, detail: msg)
                        }
                        else if !isRunning && (step == "completed" || step == "partial") {
                            researchPartial = step == "partial"
                            recordResearchOperation(5, detail: "Saving your plan…")
                            if let result {
                                finishLiveResearch(result, context: briefContext, targetTripID: requestedTripID)
                            } else {
                                liveResearchError = "The service finished without a valid result. Try again."
                                isResearching = false
                            }
                        } else if step == "error" || step == "interrupted" {
                            if let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                                trips[index].forgetResearchJob(matching: jobID)
                                TripStorage.save(trips)
                            }
                            researchNeedsNewRequest = true
                            liveResearchError = step == "interrupted" ? "Planning stopped on the service. You can start again; your saved plan and edits are kept." : (msg.isEmpty ? "The service couldn't finish planning. You can start a new request." : msg)
                            if serverErrorCode.count < 100 && serverErrorCode.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_") }) {
                                liveResearchDiagnostic = "status: " + serverErrorCode + "\n" + (ResearchDiagnostics.summary(json) ?? "")
                            }
                            isResearching = false
                        }
                    }

                    if !isRunning && (step == "completed" || step == "partial") { break }
                    if step == "error" || step == "interrupted" { break }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let failure = error as? ResearchRequestError {
                        liveResearchError = failure.message
                        liveResearchDiagnostic = failure.diagnostic
                        if failure.requiresNewJob, let activeJobID,
                           let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                            trips[index].forgetResearchJob(matching: activeJobID)
                            TripStorage.save(trips)
                            researchNeedsNewRequest = true
                        }
                    } else {
                        let code = (error as? URLError)?.code.rawValue ?? (error as NSError).code
                        liveResearchDiagnostic = "\(requestStage.rawValue): \(type(of: error)), code \(code)"
                        if (error as? URLError)?.code == .notConnectedToInternet {
                            liveResearchError = "No internet connection. A plan already started keeps running on the service; try again when you're online."
                        } else {
                            liveResearchError = "The service timed out or the connection dropped. Planning may still be running; check its status again."
                        }
                    }
                    isResearching = false
                }
            }
        }
    }

    private func cancelLiveResearch() {
        liveResearchTask?.cancel()
        liveResearchTask = nil
        isResearching = false
        showLiveResearchSheet = false
    }

    // The old bridge returns a self-contained candidate pool in a patch envelope.
    // Recover it only in the live pipeline; manual update patches still require a foundation.
    private static func foundationFromLiveResult(_ result: [String: Any], context: [String: Any]) -> [String: Any] {
        guard result["schema_version"] as? String == "trippy-research-patch-v2" else { return result }
        var foundation: [String: Any] = [
            "schema_version": "trippy-research-v1", "trip_context": context,
            "overview": [:], "map_overview": [:], "calendar_checks": [], "date_checks": [],
            "places": [], "events": [], "itinerary": ["days": []], "map_views": [],
            "transport_options": [], "ticket_options": [], "costs": [:], "booking_tasks": [],
            "sources": [], "warnings": [], "assumptions": []
        ]
        for section in ["set", "replace", "upsert"] {
            for (key, value) in result[section] as? [String: Any] ?? [:] where key != "schema_version" {
                foundation[key] = value
            }
        }
        var tripContext = foundation["trip_context"] as? [String: Any] ?? context
        if let destination = foundation["destination"] as? String { tripContext["destination"] = destination }
        foundation["trip_context"] = tripContext
        var warnings = result["warnings"] as? [[String: Any]] ?? []
        warnings.append(["id": "legacy-bridge-recovery", "severity": "info", "message": "Recovered the existing result without a new search. It only includes what the service returned; no extra plan was created."])
        foundation["warnings"] = warnings
        return foundation
    }

    private func finishLiveResearch(_ result: [String: Any], context: [String: Any], recover: Bool = false, targetTripID: UUID? = nil) {
        let document = recover ? Self.foundationFromLiveResult(result, context: context) : result
        liveResearchDiagnostic = ResearchDiagnostics.summary(document)
        researchPhaseStates = ResearchDiagnostics.phaseStates(document)
        guard ResearchDiagnostics.hasPlaces(document) else {
            completedResearchSteps.remove(4)
            researchPhaseStates[4] = "empty"
            liveResearchError = "No plan was created: the search returned no options. Your previous plan and edits are kept."
            isResearching = false
            researchNeedsNewRequest = true
            if let index = trips.firstIndex(where: { $0.id == (targetTripID ?? activeTripID) }) {
                trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil
                TripStorage.save(trips)
            }
            return
        }
        completedResearchSteps = ResearchOperation.completedPhases((document["pipeline_report"] as? [String: Any])?["completed_research_phases"] as? [Int] ?? []).union(recover ? [] : [1])
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              let text = String(data: data, encoding: .utf8) else {
            liveResearchError = "The result couldn't be read."
            isResearching = false
            return
        }
        if recover, let destination = (document["trip_context"] as? [String: Any])?["destination"] as? String {
            brief.destination = destination
        }
        if let targetTripID, targetTripID != activeTripID {
            guard let index = trips.firstIndex(where: { $0.id == targetTripID }) else {
                liveResearchError = "The trip for this plan was removed."; isResearching = false; return
            }
            let reconciled = PlanImportReconciliation.apply(document, to: &trips[index])
            guard let data = try? JSONSerialization.data(withJSONObject: reconciled), let stored = String(data: data, encoding: .utf8) else {
                liveResearchError = "The result couldn't be saved."; isResearching = false; return
            }
            trips[index].research = stored; trips[index].updatedAt = .now
            trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil
            TripStorage.save(trips); isResearching = false; liveResearchError = nil
            researchSaved = true; researchPartial = reconciled["delivery_status"] as? String != "ready"
            completedResearchSteps.insert(5)
            return
        }
        importText = text
        importError = nil
        importResearch()
        isResearching = false
        if let error = importError {
            liveResearchError = error
            importError = nil
        } else {
            if let index = trips.firstIndex(where: { $0.id == (targetTripID ?? activeTripID) }) {
                trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil; TripStorage.save(trips)
            }
            recoverableResearch = nil
            liveResearchError = nil
            if recover { recordResearchOperation(5, detail: "The result was recovered and saved.") }
            researchSaved = true
            let storedData = activeTrip?.research?.data(using: .utf8)
            let storedDocument = storedData.flatMap { data -> [String: Any]? in
                try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            researchPartial = storedDocument?["delivery_status"] as? String != "ready"
            completedResearchSteps.insert(5)
        }
    }

    private func recordResearchOperation(_ step: Int, detail: String) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)) {
            liveResearchStep = step
            if let index = researchOperations.firstIndex(where: { $0.step == step }) {
                researchOperations[index].detail = detail
            } else {
                researchOperations.append(ResearchOperation(step: step, detail: detail))
            }
        }
    }

    private var liveResearchSheet: some View {
        ResearchProgressScreen(
            destination: researchDestination,
            operations: researchOperations,
            currentStep: liveResearchStep,
            completedSteps: completedResearchSteps,
            running: isResearching,
            saved: researchSaved,
            partial: researchPartial,
            error: liveResearchError,
            needsServiceUpdate: researchNeedsServiceUpdate,
            canRecover: recoverableResearch != nil,
            resuming: trips.first(where: { $0.id == researchResultTripID })?.researchJobID != nil,
            needsNewRequest: researchNeedsNewRequest,
            diagnostic: liveResearchDiagnostic,
            phaseStates: researchPhaseStates,
            live: planningLive,
            onClose: { cancelLiveResearch() },
            onRetry: { startLiveResearch() },
            onSettings: { researchOpenSettingsAfterDismiss = true; cancelLiveResearch() },
            onRecover: {
                if let result = recoverableResearch { finishLiveResearch(result, context: recoveryContext, recover: true) }
            },
            onOpenPlan: {
                cancelLiveResearch()
                if let id = researchResultTripID, let trip = trips.first(where: { $0.id == id }) { selectMapTrip(trip) }
                showTripDetails = true
            }
        )
    }

    private var calendarNightCount: Int {
        TripCalendarSelection(start: parseISODate(brief.startDate), end: parseISODate(brief.endDate)).nights
    }

    private func holidayContext(start: Date, end: Date, holidays: [DestinationHoliday]) -> [String] {
        let firstDay = isoDate(start)
        let lastDay = isoDate(end)
        guard lastDay > firstDay else { return [] }
        return holidays.compactMap { holiday -> (date: String, text: String)? in
            guard let year = holiday.date.year,
                  let month = holiday.date.month,
                  let day = holiday.date.day,
                  (1...12).contains(month), (1...31).contains(day) else { return nil }
            let holidayDate = String(format: "%04d-%02d-%02d", year, month, day)
            guard holidayDate >= firstDay, holidayDate <= lastDay else { return nil }
            let kind = holiday.kind == .publicHoliday ? "national holiday" : "local holiday"
            return (holidayDate, "\(holidayDate) · \(holiday.localName) (\(holiday.name), \(kind))")
        }
        .sorted { $0.date < $1.date }
        .map(\.text)
    }

    private var calendarPickerSheet: some View {
        TripCalendarSheet(
            destination: resolvedDestination.isEmpty ? brief.title : resolvedDestination,
            start: parseISODate(brief.startDate), end: parseISODate(brief.endDate),
            holidays: calendarHolidays, isLoading: isLoadingHolidays, status: holidayStatus,
            onYearChange: { month in
                calendarDisplayedMonth = month
                loadHolidays(for: brief.destination)
            },
            onApply: { start, end, nights in
                var updatedBrief = brief
                updatedBrief.startDate = isoDate(start)
                updatedBrief.endDate = isoDate(end)
                updatedBrief.dateIsUnknown = false
                updatedBrief.duration = nights + 1
                updatedBrief.dateContext = holidayContext(start: start, end: end, holidays: calendarHolidays)
                brief = updatedBrief
                showCalendarPicker = false
            },
            onCancel: { showCalendarPicker = false }
        )
    }

    private func searchDestinations(_ text: String) {
        destinationSearchTask?.cancel()
        destinationCompleter.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            destinationSuggestions = []
            return
        }
        destinationSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            destinationCompleter.search(query) { [query] completions in
                guard brief.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(query) == .orderedSame else { return }
                var seen = Set<String>()
                destinationSuggestions = completions.compactMap { completion in
                    let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    let fullQuery = [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                    let key = fullQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    guard seen.insert(key).inserted else { return nil }
                    return DestinationSuggestion(id: key, title: title, subtitle: subtitle, query: fullQuery)
                }.prefix(8).map { $0 }
            }
        }
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private func loadHolidays(for destination: String, debounce: Bool = false) {
        holidayTask?.cancel()
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            calendarHolidays = []
            isLoadingHolidays = false
            holidayStatus = "Choose a destination to load holidays."
            return
        }
        let year = Calendar.current.component(.year, from: calendarDisplayedMonth)
        isLoadingHolidays = true
        holidayStatus = "Looking up destination and holidays…"
        holidayTask = Task { @MainActor in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(900)) }
                try Task.checkCancellation()
                let location: HolidayLocation
                if let cachedLocation = resolvedHolidayLocation, cachedLocation.query == query {
                    location = cachedLocation
                } else {
                    let placemarks = try await CLGeocoder().geocodeAddressString(query)
                    try Task.checkCancellation()
                    guard let placemark = placemarks.first, let country = placemark.isoCountryCode else {
                        holidayStatus = "Destination not recognized. Try a city and country."
                        isLoadingHolidays = false
                        return
                    }
                    let region = placemark.administrativeArea?.uppercased()
                    location = HolidayLocation(query: query, countryCode: country, regionCode: region.map { "\(country)-\($0)" },
                                               displayName: [placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", "))
                    resolvedHolidayLocation = location
                }
                resolvedDestination = location.displayName
                let cacheKey = "\(location.countryCode)|\(location.regionCode ?? "")|\(year)"
                if let cached = holidayCache[cacheKey] {
                    calendarHolidays = cached
                    holidayStatus = cached.isEmpty ? "No holidays found for this destination." : "Holidays loaded."
                    isLoadingHolidays = false
                    return
                }
                guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(location.countryCode)") else { return }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 204 || http.statusCode == 404 {
                    holidayCache[cacheKey] = []
                    calendarHolidays = []
                    holidayStatus = "No holiday data for this country. You can still pick dates."
                    isLoadingHolidays = false
                    return
                }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                let entries = try JSONDecoder().decode([PublicHolidayResponse].self, from: data)
                let holidays = entries.filter { entry in
                    entry.types.contains("Public") && (entry.global || location.regionCode.map { entry.counties?.contains($0) == true } == true)
                }.compactMap { entry -> DestinationHoliday? in
                    guard let date = parseISODate(entry.date) else { return nil }
                    return DestinationHoliday(date: Calendar.current.dateComponents([.year, .month, .day], from: date),
                                              name: entry.name, localName: entry.localName,
                                              kind: entry.global ? .publicHoliday : .localCelebration)
                }
                holidayCache[cacheKey] = holidays
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { calendarHolidays = holidays }
                holidayStatus = holidays.isEmpty ? "No holidays found for this destination." : "Holidays loaded."
                isLoadingHolidays = false
            } catch {
                guard !Task.isCancelled else { return }
                calendarHolidays = []
                isLoadingHolidays = false
                holidayStatus = "Holidays aren't available right now. You can still pick dates."
            }
        }
    }

    private static func parseResearchJSON(_ input: String) -> (String, [String: Any])? {
        var text = input.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let firstLineEnd = text.firstIndex(of: "\n")
            if let firstLineEnd, let closing = text.range(of: "```", options: .backwards), closing.lowerBound > firstLineEnd {
                text = String(text[text.index(after: firstLineEnd)..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0 { end = text.index(after: index); break }
            }
        }
        guard let end else { return nil }
        let json = String(text[start..<end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json, object)
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { withAnimation { toast = nil } } }
    }

    private var researchRoot: [String: Any] {
        guard let raw = activeTrip?.research, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private var placeRecords: [[String: Any]] {
        let keys = ["places", "place_options", "restaurants", "attractions", "bars", "clubs", "museums"]
        var seen = Set<String>()
        return keys.flatMap { key -> [[String: Any]] in
            if let values = researchRoot[key] as? [[String: Any]] { return values }
            if let object = researchRoot[key] as? [String: Any], let values = object["items"] as? [[String: Any]] { return values }
            return []
        }.filter { place in
            let identity = (recordValue(place, keys: ["id", "place_id"]) ?? recordTitle(place) ?? UUID().uuidString).lowercased()
            return seen.insert(identity).inserted
        }
    }
    private var dayRecords: [[String: Any]] {
        if let itinerary = researchRoot["itinerary"] as? [String: Any],
           let days = itinerary["days"] as? [[String: Any]] { return days }
        if let days = records(["days", "day_plans"]).first { return days["days"] as? [[String: Any]] ?? [days] }
        return []
    }
    private var sourceRecords: [[String: Any]] { records(["sources", "references"]) }
    /// The stay: what the traveller typed (located on the phone), else the plan's own base.
    var tripBase: GuideBase? {
        if let id = activeTripID {
            let flight = GuideEditsStore.load(id, travelers: brief.travelers).flight
            if let lat = flight.stayLatitude, let lon = flight.stayLongitude, !flight.stayName.isEmpty {
                return GuideBase(name: flight.stayName, latitude: lat, longitude: lon)
            }
        }
        guard let base = (researchRoot["itinerary"] as? [String: Any])?["base"] as? [String: Any],
              let lat = (base["latitude"] as? NSNumber)?.doubleValue, let lon = (base["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return GuideBase(name: base["name"] as? String ?? "Your stay", latitude: lat, longitude: lon)
    }
    private var mapPoints: [ResearchMapPoint] {
        let places = placeRecords.enumerated().compactMap { index, place -> ResearchMapPoint? in
            guard let coordinate = placeCoordinate(place), (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else { return nil }
            return ResearchMapPoint(id: recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)", title: recordTitle(place) ?? "Place", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let knownIDs = Set(places.map(\.id))
        let itineraryStops = dayRecords.enumerated().flatMap { dayIndex, day in
            scheduleIDs(day, index: dayIndex).enumerated().compactMap { stopIndex, itemID -> ResearchMapPoint? in
                guard let stop = scheduledStop(itemID, day: day), let coordinate = coordinateFromRecord(stop) else { return nil }
                let placeID = recordValue(stop, keys: ["place_id"])
                let id = placeID ?? itemID
                guard !knownIDs.contains(id) else { return nil }
                return ResearchMapPoint(id: id, title: "\(dayIndex + 1).\(stopIndex + 1) · \(recordValue(stop, keys: ["activity", "name", "title"]) ?? "Stop")", latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
        var seen = Set<String>()
        return (places + itineraryStops).filter { seen.insert($0.id).inserted }
    }
    private var plannedMapLabels: [String: String] {
        var labels: [String: String] = [:]
        for (dayIndex, day) in dayRecords.enumerated() {
            for (stopIndex, itemID) in scheduleIDs(day, index: dayIndex).enumerated() {
                guard let place = scheduledPlace(itemID, day: day),
                      let placeID = recordValue(place, keys: ["id", "place_id"]) else { continue }
                labels[placeID] = "\(dayIndex + 1).\(stopIndex + 1)"
            }
        }
        return labels
    }
    private func mapPoints(for day: [String: Any], index: Int) -> [ResearchMapPoint] {
        scheduleIDs(day, index: index).enumerated().compactMap { stopIndex, itemID in
            let place = scheduledPlace(itemID, day: day)
            let stop = scheduledStop(itemID, day: day)
            guard let coordinate = planCoordinate(itemID, day: day) else { return nil }
            let id = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID
            let title = place.flatMap(recordTitle) ?? stop.flatMap { recordValue($0, keys: ["activity", "name", "title"]) } ?? "Stop"
            return ResearchMapPoint(id: id, title: "\(stopIndex + 1) · \(title)", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
    private func coordinateFromRecord(_ record: [String: Any]) -> CLLocationCoordinate2D? {
        let raw = record["coordinates"] as? [String: Any] ?? record["location"] as? [String: Any] ?? record
        guard let lat = numericValue(raw, keys: ["latitude", "lat"]), let lon = numericValue(raw, keys: ["longitude", "lng", "lon"]), (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private func resolvePlaceCoordinates() async {
        let tripID = activeTripID
        let destination = brief.destination
        let places = placeRecords
        isResolvingCoordinates = true
        defer { if activeTripID == tripID { isResolvingCoordinates = false } }
        func current() -> Bool { !Task.isCancelled && activeTripID == tripID && brief.destination == destination }
        if destinationCoordinate == nil, !destination.isEmpty {
            destinationCoordinate = cityCoordinates[destination]?.coordinate
            if destinationCoordinate == nil {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = destination
                let search = MKLocalSearch(request: request)
                let response = try? await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
                guard current() else { return }
                destinationCoordinate = response?.mapItems.first?.placemark.coordinate
            }
        }
        guard current() else { return }
        for (id, stored) in activeTrip?.mapCoordinatesByPlaceID ?? [:] { resolvedCoordinates[id] = stored.coordinate }
        for place in places {
            guard current() else { return }
            guard placeCoordinate(place) == nil, let id = recordValue(place, keys: ["id", "place_id"]), let name = recordTitle(place) else { continue }
            let address = recordValue(place, keys: ["address", "area", "neighborhood"])
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = [name, address, destination].compactMap { $0 }.joined(separator: ", ")
            if let center = destinationCoordinate { request.region = .init(center: center, span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4)) }
            let search = MKLocalSearch(request: request)
            let response = try? await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
            guard current() else { return }
            // Auto-locate only an unambiguous exact venue name near the destination.
            // Multiple branches and loose search matches require a user's pin selection.
            let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = response?.mapItems.filter { item in
                guard let center = destinationCoordinate,
                      item.name?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return false }
                return CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)) < 60000
            } ?? []
            if matches.count == 1, let item = matches.first {
                resolvedCoordinates[id] = item.placemark.coordinate
                storeResolvedCoordinate(id: id, coordinate: item.placemark.coordinate)
            }
        }
    }
    private func storeResolvedCoordinate(id: String, coordinate: CLLocationCoordinate2D) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var coordinates = trips[index].mapCoordinatesByPlaceID ?? [:]
        coordinates[id] = StoredPlaceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, source: "Apple Maps", matchedAt: .now)
        trips[index].mapCoordinatesByPlaceID = coordinates
        TripStorage.save(trips)
    }
    private func numericValue(_ record: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = record[key] as? NSNumber { return value.doubleValue }
            if let value = record[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }
    private var overviewText: String { recordValue(researchRoot["overview"], keys: ["summary", "description", "text"]) ?? (researchRoot["overview"] as? String) ?? "Plan imported. Open the sections to see what's there." }
    private var costSummary: String {
        guard let value = researchRoot["costs"] ?? researchRoot["cost_summary"] else { return "No cost summary found." }
        let fields: [(String, String)] = [
            ("Per person", "per_person_estimate"), ("For the group", "group_estimate"),
            ("Stay", "lodging_estimate"), ("Transport and sights", "transport_and_attractions_subtotal"),
            ("Food", "food_estimate")
        ]
        guard let object = value as? [String: Any] else { return readableValue(value) }
        let rows = fields.compactMap { title, key -> String? in
            guard let amount = object[key] else { return nil }
            return "\(title): \(readableValue(amount))"
        }
        return rows.isEmpty ? readableValue(value) : rows.joined(separator: "\n")
    }

    private func records(_ keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = researchRoot[key] as? [[String: Any]] { return array }
            if let object = researchRoot[key] as? [String: Any], let nested = object["items"] as? [[String: Any]] { return nested }
        }
        return []
    }

    private func recordTitle(_ record: [String: Any]) -> String? { recordValue(record, keys: ["name", "title", "label", "date"]) }
    private func recordSummary(_ record: [String: Any]) -> String {
        recordValue(record, keys: ["description", "summary", "theme", "notes", "address", "area", "time", "details", "activity"]) ?? "Details are in the imported plan."
    }
    private func recordValue(_ record: Any?, keys: [String]) -> String? {
        guard let dictionary = record as? [String: Any] else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if let value = dictionary[key], !(value is NSNull), !(value is [String: Any]), !(value is [Any]) { return String(describing: value) }
        }
        return nil
    }
    private func dayTitle(_ day: [String: Any], index: Int) -> String {
        let date = recordValue(day, keys: ["date"])
        let weekday = recordValue(day, keys: ["day_name", "weekday"])
        let prefix = weekday ?? "Day \(index + 1)"
        return [prefix, date].compactMap { $0 }.joined(separator: " · ")
    }
    private func activityTitle(_ activity: [String: Any]) -> String {
        if let activityName = recordValue(activity, keys: ["activity", "name", "title"]) { return activityName }
        if let placeID = recordValue(activity, keys: ["place_id"]),
           let place = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == placeID }),
           let name = recordTitle(place) { return name }
        return "Stop"
    }
    private func ratingLabel(_ place: [String: Any]) -> String {
        guard let rating = place["rating"] as? [String: Any],
              let value = numericValue(rating, keys: ["value"]), (0...5).contains(value),
              numericValue(rating, keys: ["scale", "out_of"]) ?? 5 == 5 else { return "—" }
        let platform = recordValue(rating, keys: ["platform"])
        let count = recordValue(rating, keys: ["review_count"]).map { "\($0) reviews" }
        return ["\(planNumber(value))/5", platform, count].compactMap { $0 }.joined(separator: " · ")
    }
    private func priceLabel(_ place: [String: Any]) -> String {
        if let price = place["price"] as? [String: Any] {
            let amount = costAmount(price)
            return amount == "—" ? "Price unconfirmed" : amount
        }
        return recordValue(place, keys: ["price", "cost", "price_range"]) ?? "Price unconfirmed"
    }
    private func warningText(_ item: Any) -> String {
        if let text = item as? String { return text }
        return recordValue(item, keys: ["message", "text", "warning", "title"]) ?? readableValue(item)
    }
    private func readableValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if value is NSNull { return "Not confirmed" }
        if let array = value as? [Any] { return array.map(readableValue).joined(separator: ", ") }
        if let object = value as? [String: Any] {
            let preferred = ["min", "max", "currency", "per_person_per_day_eur", "group_total_eur", "note", "basis", "includes", "excludes"]
            let ordered = preferred.compactMap { key -> String? in
                guard let item = object[key], !(item is NSNull) else { return nil }
                return "\(key): \(readableValue(item))"
            }
            return ordered.isEmpty ? "Available details" : ordered.joined(separator: " · ")
        }
        return String(describing: value)
    }
}

private struct ResearchMapPoint: Identifiable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private struct PlaceImage: View {
    let title: String
    let imageURL: String?
    @State private var wikipediaImageURL: URL?
    @State private var explicitImageFailed = false

    private var explicitURL: URL? { imageURL.flatMap(URL.init(string:)) }
    private var displayedURL: URL? { explicitImageFailed ? wikipediaImageURL : (explicitURL ?? wikipediaImageURL) }
    private var wikipediaArticleURL: URL? {
        guard let slug = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(slug)")
    }

    var body: some View {
        ZStack {
            if let displayedURL {
                AsyncImage(url: displayedURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder.task {
                            if explicitURL != nil && !explicitImageFailed {
                                explicitImageFailed = true
                                await loadWikipediaImage()
                            }
                        }
                    } else {
                        placeholder.overlay { ProgressView().tint(AppPalette.brand) }
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: title) { if explicitURL == nil { await loadWikipediaImage() } }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "FFE0D2"), Color(hex: "F4BD78"), Color(hex: "9BBFB0")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "sparkles")
                .font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.9))
        }
    }

    @MainActor private func loadWikipediaImage() async {
        guard wikipediaImageURL == nil,
              let slug = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)") else { return }
        var request = URLRequest(url: url)
        request.setValue("TrippyTravelPlanner/1.0 (iOS; image attribution: Wikimedia/Wikipedia)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(WikipediaPageSummary.self, from: data),
              let thumbnail = response.thumbnail?.source else { return }
        wikipediaImageURL = thumbnail
    }
}

private struct WikipediaPageSummary: Decodable {
    struct Thumbnail: Decodable { let source: URL? }
    let thumbnail: Thumbnail?
}

private struct TripCover: View {
    let vibe: String
    let destination: String

    private var assetName: String {
        let value = destination.lowercased()
        if value.contains("santorini") { return "TripSantorini" }
        if value.contains("tokyo") || value.contains("kyoto") || value.contains("ιαπων") { return "TripKyoto" }
        if value.contains("lisbon") || value.contains("lisboa") { return "TripLisbon" }
        if value.contains("bali") { return "TripBali" }
        if value.contains("rome") || value.contains("ρωμ") { return "TripRome" }
        if value.contains("new york") || value.contains("νέα υόρκη") { return "TripNewYork" }
        switch vibe {
        case "Sea", "Beach": return "TripSantorini"
        case "Nature", "Hiking": return "TripBali"
        case "Culture": return "TripKyoto"
        default: return "TripLisbon"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct BrandWordmark: View {
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    var size: CGFloat = 23

    var body: some View {
        Image(darkMode ? "BrandWordmarkDark" : "BrandWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: size * 6.3, height: size * 2.22)
            .accessibilityLabel("trippy")
    }
}

enum AppPalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.07, green: 0.12, blue: 0.10, alpha: 1) : UIColor(red: 0.976, green: 0.957, blue: 0.929, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.20, blue: 0.17, alpha: 1) : UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1) : UIColor(red: 0.06, green: 0.16, blue: 0.12, alpha: 1)
    })
    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.73, green: 0.80, blue: 0.76, alpha: 1) : UIColor(red: 0.38, green: 0.40, blue: 0.39, alpha: 1)
    })
    static let inverseInk = Color.white
    static let brand = Color(hex: "102A22")
    static let accent = Color(hex: "FF685B")
    static let art = Color(hex: "FFBE55")
    static let avatarColors: [Color] = [Color(hex: "FF685B"), Color(hex: "FFBE55"), Color(hex: "FFCDBD"), Color(hex: "477461")]
}

private struct AdaptiveGlassControl: ViewModifier {
    enum ShapeKind {
        case circle
        case capsule
        case rounded
    }

    let shape: ShapeKind
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("trippy.native.glassTint") private var glassTint = "auto"

    private var selectedGlassTint: Color? {
        switch glassTint {
        case "forest": return Color(hex: "477461")
        case "coral": return AppPalette.accent
        case "amber": return AppPalette.art
        case "sage": return Color(hex: "AFC9B9")
        default: return nil
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            let baseTint = colorScheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.82)
            let surfaceTint = colorScheme == .dark ? baseTint : (selectedGlassTint ?? baseTint)
            let glass = Glass.regular.tint(surfaceTint).interactive()
            switch shape {
            case .circle:
                content.glassEffect(glass, in: Circle())
            case .capsule:
                content.glassEffect(glass, in: Capsule())
            case .rounded:
                content.glassEffect(glass, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
        } else {
            let isDark = colorScheme == .dark
            let tint = isDark ? Color.black : (selectedGlassTint ?? Color.white)
            let fillOpacity = reduceTransparency ? 0.96 : (isDark ? 0.76 : 0.78)
            switch shape {
            case .circle:
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .background(tint.opacity(fillOpacity), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(isDark ? 0.24 : 0.78), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            case .capsule:
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(tint.opacity(fillOpacity), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(isDark ? 0.24 : 0.78), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            case .rounded:
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .background(tint.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.white.opacity(isDark ? 0.24 : 0.78), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            }
        }
    }
}

private enum ResearchPrompt {
    static func make(layer: ResearchLayer, brief: TripBrief, existingResearch: String?, selectedRegion: String, pace: String) -> String {
        if layer == .foundation {
            return make(from: brief) + """


            ΣΤΑΘΕΡΟ ΠΛΑΙΣΙΟ ΓΙΑ ΚΑΘΕ ΕΡΕΥΝΗΤΙΚΟ ΒΗΜΑ
            Εφάρμοσε όλους τους περιορισμούς, προτιμήσεις και custom_instructions του brief σε κάθε αναζήτηση, κατάταξη, επιλογή πηγής, έλεγχο ημερομηνίας και πρόταση προγράμματος. Δεν είναι διακοσμητικά metadata. Αν υπάρχει σύγκρουση, κράτησε πρώτα ρητούς περιορισμούς/αποκλεισμούς, μετά τις δηλωμένες προτιμήσεις και τέλος τις δικές σου υποθέσεις. Κατέγραψε unresolved_conflicts και assumptions αντί να επινοείς απάντηση.
            Προτιμώμενη περιοχή: \(selectedRegion). Ρυθμός: \(pace).

            FOUNDATION / ΕΠΙΠΕΔΟ 1 — ΕΥΡΕΙΑ ΑΝΑΚΑΛΥΨΗ
            Δημιούργησε πρώτα ευρύ αλλά σχετικό foundation pool για τον/τους προορισμούς, τις περιοχές, τις κατηγορίες και το προφίλ ταξιδιού. Για κάθε υποψήφιο κατέγραψε γιατί ταιριάζει, ποια προτίμηση ικανοποιεί, βασική θέση/περιοχή, πηγή, και ποια facts πρέπει να επαληθευτούν αργότερα. Απόφυγε διπλότυπα και αδύναμες επιλογές. Μην επινοήσεις ότι είναι ανοιχτό/διαθέσιμο σε ημερομηνία που δεν έχει ελεγχθεί.
            Δημιούργησε εσωτερικό work matrix destination × area × selected category, κάλυψε τις περιοχές με ξεχωριστά discovery batches και έπειτα ένωσε/αφαίρεσε διπλότυπα. Κράτησε ποικιλία (κλασικά, highly-rated/popular, local, distinctive και value-for-quality επιλογές όπου ταιριάζουν στις προτιμήσεις), όχι πολλά αντίγραφα του ίδιου τύπου.
            Ακόμη και σε αυτό το επίπεδο, χρησιμοποίησε γνωστές ημερομηνίες ταξιδιού για να αποκλείσεις προφανείς ασυμβατότητες και να σημειώσεις τι απαιτεί ακριβή έλεγχο. Μην παρουσιάσεις το foundation ως τελικό επιβεβαιωμένο πρόγραμμα.
            Επέστρεψε πλήρες trippy-research-v1 JSON. Για κάθε claim βάλε πηγή/checked_at ή σαφές unknown/status. Το επόμενο επίπεδο θα κάνει ημερολογιακή επαλήθευση πάνω σε αυτά τα ids.
            """
        }

        let briefContext: [String: Any] = [
            "destination": brief.destination.isEmpty ? NSNull() : brief.destination as Any,
            "date_range": ["arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                           "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                           "dates_unknown": brief.dateIsUnknown,
                           "duration_days": brief.duration],
            "date_calendar_context": brief.dateContext,
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(), "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "custom_instructions": brief.notes.isEmpty ? NSNull() : brief.notes as Any,
            "preferred_region": selectedRegion, "pace": pace
        ]
        let contextData = (try? JSONSerialization.data(withJSONObject: briefContext, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"
        let foundationJSON = existingResearch ?? "Δεν έχει εισαχθεί foundation JSON ακόμη. Μην προσποιηθείς ότι υπάρχει· ζήτησε πρώτα το Επίπεδο 1."
        let globalRules = """
        ΚΑΘΟΛΙΚΟΙ ΚΑΝΟΝΕΣ — ΙΣΧΥΟΥΝ ΓΙΑ ΚΑΘΕ ΕΡΩΤΗΜΑ ΚΑΙ ΚΑΘΕ ΠΕΔΙΟ
        1. Εφάρμοσε σε κάθε αναζήτηση όλες τις παρακάτω πληροφορίες: destination, ακριβές date range, traveler count/group, vibes, selected interests, budget ως πλαίσιο, preferred area, pace και custom_instructions. Μην αγνοήσεις περιορισμό επειδή δεν επαναλαμβάνεται σε κάθε εγγραφή.
        2. Για κάθε μέρος ή event που προτείνεις/διατηρείς, έλεγξε καταλληλότητα στις ακριβείς τοπικές ημερομηνίες που σχετίζονται με το πρόγραμμα. Χρησιμοποίησε επίσημες πηγές για αργίες, ειδικό ωράριο, εβδομαδιαία κλεισίματα, προσωρινές διακοπές, απαιτούμενη κράτηση, εισιτήρια, event dates και μεταφορές. Μια γενική πληροφορία «συνήθως ανοικτό» δεν αποδεικνύει λειτουργία συγκεκριμένη ημερομηνία.
        3. Έλεγξε αργίες και τοπικές γιορτές ανά χώρα/περιοχή/δήμο και ανά ημερομηνία. Μην συμπεραίνεις ότι όλα κλείνουν ή ανοίγουν λόγω αργίας· επαλήθευσε κάθε σχετικό χώρο ξεχωριστά. Τα events απαιτούν ημερομηνία, venue και επίσημη/διοργανωτική πηγή για status confirmed. Διαχώρισε confirmed, candidate, not_found και not_checked.
        4. Πρόσθεσε calendar_checks ανά ημερομηνία και date_checks ανά σχετικό place/event, με local_date, status, τι ακριβώς ελέγχθηκε, source_ids και checked_at. Μην αφήνεις έλλειψη δεδομένων να μετατραπεί σε θετική υπόθεση.
        5. Για κρατήσεις, tasks και urgency αξιολόγησε κάθε destination × ημερομηνία/ημερομηνίες × συγκεκριμένο αντικείμενο. Συμπερίλαβε ακριβή deadline μόνο αν επιβεβαιώνεται. Urgency 9–10 μόνο με επίσημη προθεσμία, πραγματική date-specific απαίτηση ή τεκμηριωμένη περιορισμένη διαθεσιμότητα· διαφορετικά χαμηλότερο score και σαφής χαρακτηρισμός ως planning recommendation.
        6. Διατήρησε distinctions: confirmed price vs estimate, official vs secondary source, date-specific vs general fact, user constraint vs model inference. Ποτέ μη μαντεύεις. Αν δεν βρίσκεις, γράψε not_found/not_checked και τι αναζήτηση έκανες.
        7. Πριν από output, έλεγξε consistency: τοπική ζώνη ώρας, inclusive ημέρες vs διανυκτερεύσεις, ημέρα εβδομάδας, όλες οι ημερομηνίες του range, source/id references, constraints και αποκλεισμούς.
        8. Οργάνωσε εσωτερικά την εργασία σε batches destination × area × selected category. Κάνε πρώτα ευρείες αναζητήσεις ανά περιοχή/κατηγορία, μετά στοχευμένο verification ανά candidate και ημερομηνία. Παράλληλοποίησε μόνο ανεξάρτητα batches, επαναχρησιμοποίησε την ίδια επίσημη πηγή για πολλές ημερομηνίες όταν καλύπτει όλες, κάνε deduplication ανά stable identity και κράτα coverage/gaps ανά batch. Μην επαναλαμβάνεις το ίδιο query για κάθε μέρα ή κάθε πεδίο.
        9. Μην κάνεις crawl όλο τον ιστό. Διάλεξε σχετικές περιοχές και ποικιλία υποψηφίων ανά ενεργή κατηγορία με εύρος προσαρμοσμένο στη διάρκεια και στα διαθέσιμα στοιχεία. Δώσε προτεραιότητα σε direct official/provider sources και χρησιμοποίησε γενική αναζήτηση για discovery ή gap-filling.
        """

        let layerInstructions: String
        switch layer {
        case .foundation:
            layerInstructions = ""
        case .dateVerification:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 2 — ΕΠΑΛΗΘΕΥΣΗ FOUNDATION ΑΝΑ ΗΜΕΡΟΜΗΝΙΑ
            Πάρε το παρακάτω foundation ως σύνολο υπαρχόντων candidates και όχι ως αληθές εκ προοιμίου. Μην ξανακάνεις γενική αναζήτηση από την αρχή. Για κάθε place/event του pool, επαλήθευσε τα facts που αλλάζουν με ημερομηνία και όσα κρίσιμα πεδία λείπουν (official URL, διεύθυνση, coords, ticket/price, image/source όπου είναι ανακτήσιμα). Έλεγξε κάθε σχετική ημερομηνία του range: αργίες, τοπικά events, ειδικά ωράρια, κλεισίματα, απαιτήσεις προκράτησης και μεταφορές. Σύνδεσε κάθε αποτέλεσμα με υπάρχον stable id. Πρόσθεσε νέα επιλογή μόνο αν το foundation έχει ουσιαστικό κενό.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2: set για ενημερώσεις overview/map_overview αν χρειάζεται, upsert για places/events/sources/booking_tasks, replace για calendar_checks, date_checks και warnings. Μην αλλάξεις user-owned δεδομένα και μη διαγράψεις records. Κάθε ενημερωμένο fact να έχει source_ids και checked_at. Για κάθε booking task αξιολόγησε destination + related item + due date/ημερομηνία ταξιδιού.
            """
        case .itinerary:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 3 — ΗΜΕΡΗΣΙΑ ΣΥΝΘΕΣΗ ΜΕ ΕΛΕΓΜΕΝΑ ΔΕΔΟΜΕΝΑ
            Σύνθεσε πρόγραμμα μόνο αφού λάβεις υπόψη date_checks/calendar_checks του foundation. Σε κάθε μέρα, έλεγξε ότι κάθε stop ταιριάζει στην ομάδα, τα vibes, τα must/avoid, διατροφή, budget και ρυθμό. Επιβεβαίωσε ότι ο χώρος λειτουργεί τη συγκεκριμένη ημέρα και ώρα· μην τοποθετείς κλειστό/μη επιβεβαιωμένο χώρο σαν βέβαιο. Ομαδοποίησε γεωγραφικά stops, υπολόγισε ρεαλιστικούς χρόνους μετακίνησης, κενά/γεύματα και ευέλικτη εναλλακτική. Δείξε αργίες/events στο σωστό day και προσαρμόζεις πλάνο μόνο με πηγές. Κράτησε σταθερά ids και σύνδεσε stops με map_views.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2: replace itinerary, map_views και calendar_checks μόνο αν τα επανέλεγξες· set overview/map_overview/costs· upsert booking_tasks και sources. Μη ξαναγράψεις places ή άσχετα στοιχεία. Δήλωσε κενά/αντιφάσεις στα warnings.
            """
        case .targetedRefresh:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 4 — ΣΤΟΧΕΥΜΕΝΗ ΕΠΑΝΑΝΑΖΗΤΗΣΗ
            Διάβασε τις custom_instructions ως αίτημα αλλαγής και εντόπισε το μικρότερο σωστό scope. Εφάρμοσε και πάλι όλους τους global περιορισμούς και ακριβείς ημερομηνίες. Έλεγξε ξανά μόνο τα facts που επηρεάζονται, μαζί με εξαρτήσεις τους (π.χ. αλλαγή ημερομηνίας → weekday/αργία/ωράριο/event/εισιτήριο/task/map/day cost). Διατήρησε pinned/user-edited πρόγραμμα και IDs. Μην επαναφέρεις disliked επιλογές. Επισήμανε conflicts και δώσε reason/source.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2 με μόνο τα αλλαγμένα πεδία: set, replace και upsert. Μην αντικαταστήσεις ολόκληρο το foundation. Αν δεν επαληθεύεται αλλαγή, διατήρησε παλιά τιμή και πρόσθεσε warning με status not_found/not_checked.
            """
        }

        let researchJSON = foundationJSON
        return """
        Είσαι ερευνητής ταξιδιών και επιμελητής τεκμηριωμένων δεδομένων για το Trippy. Αυτό είναι σταδιακή έρευνα: ενημέρωσε το foundation χωρίς να χάνεις προέλευση ή αβεβαιότητα.

        TRIP BRIEF — ΟΙ ΠΡΟΤΙΜΗΣΕΙΣ ΚΑΙ ΠΕΡΙΟΡΙΣΜΟΙ ΕΙΝΑΙ ΔΕΣΜΕΥΤΙΚΟΙ
        \(contextJSON)

        \(globalRules)

        \(layerInstructions)

        ΥΠΑΡΧΟΝ FOUNDATION / SOURCE OF TRUTH ΓΙΑ ΤΑ ΗΔΗ ΓΝΩΣΤΑ (JSON)
        \(researchJSON)

        ΣΥΜΒΟΛΑΙΟ PATCH
        Για patch-v2 επέστρεψε ακριβώς:
        {"schema_version":"trippy-research-patch-v2","set":{},"replace":{},"upsert":{"places":[],"events":[],"sources":[],"booking_tasks":[]},"warnings":[]}
        `set` περιέχει top-level αντικείμενα για merge/replace (π.χ. costs, map_overview). `replace` περιέχει ολόκληρες λίστες/αντικείμενα που υπολογίστηκαν ξανά (π.χ. calendar_checks, date_checks, itinerary, map_views). `upsert` κάνει merge με βάση stable id και κρατάει άγνωστα υπάρχοντα fields. Χρησιμοποίησε μόνο keys του ζητούμενου επιπέδου. Μην στείλεις άδειες λίστες για να σβήσεις δεδομένα εκτός αν το επίπεδο ζητά ρητά replace.
        Κάθε date_check: {"id":"place-id|YYYY-MM-DD","entity_id":"stable-id","entity_type":"place|event|transport","local_date":"YYYY-MM-DD","status":"confirmed|closed|candidate|not_found|not_checked","opening_status":null,"holiday_or_event":null,"ticket_status":null,"reservation_status":null,"details":"","source_ids":[],"checked_at":"YYYY-MM-DD"}.
        Κάθε booking_task: {"id":"stable-id","destination":"","local_date":null,"related_place_id":null,"event_id":null,"type":"booking|ticket|transport|document|check|reminder","urgency_score":1,"urgency_reason":"","urgency_basis":"official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional","urgency_confidence":"high|medium|low","due_date":null,"task":"","url":null,"source_ids":[],"status":""}.
        Επέστρεψε μόνο έγκυρο JSON, χωρίς markdown ή πρόλογο. Έλεγξε ότι οι ημερομηνίες, τα stable ids, οι πηγές και οι εφαρμοσμένοι περιορισμοί είναι συνεπή. Αν δεν υπάρχει Foundation JSON για επίπεδα 2–4, σταμάτησε και ζήτησε πρώτα το επίπεδο 1.
        """
    }

    static func make(from brief: TripBrief) -> String {
        let context: [String: Any] = [
            "destination": brief.destination.isEmpty ? NSNull() : brief.destination as Any,
            "dates": ["arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                      "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                      "unknown": brief.dateIsUnknown,
                      "duration_days": brief.duration],
            "date_calendar_context": brief.dateContext,
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "dietary_needs": brief.dietaryNeeds.sorted(),
            "mobility_requirements": brief.mobility.sorted(),
            "stay_style": brief.stayStyle,
            "custom_instructions": brief.notes.isEmpty ? NSNull() : brief.notes as Any
        ]
        let data = (try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        Είσαι ερευνητής ταξιδιών που τεκμηριώνει κάθε χρήσιμη πληροφορία. Κάνε τρέχουσα έρευνα στον ιστό για το ταξίδι παρακάτω. Το Trippy εισάγει το αποτέλεσμα αυτόματα, οπότε προτεραιότητα έχουν η ακρίβεια, η πληρότητα και η αυστηρή συμβατότητα δεδομένων.

        ΤΑΞΙΔΙΩΤΙΚΟ BRIEF
        \(json)

        ΚΑΝΟΝΕΣ ΕΡΕΥΝΑΣ ΚΑΙ ΠΟΙΟΤΗΤΑΣ
        - Προτίμησε επίσημες πηγές χώρων, συγκοινωνιών, διοργανωτών και δήμων για ωράρια, κλεισίματα, εισιτήρια και δρομολόγια.
        - Κατάταξε τα μέρη πρώτα με βάση ποιότητα, φήμη και συνάφεια με το ταξίδι. Χρησιμοποίησε το budget ως πλαίσιο· μην προτείνεις χαμηλής ποιότητας επιλογές μόνο επειδή είναι φθηνές.
        - Αναζήτησε ευρύ pool χωριστά από το προτεινόμενο πρόγραμμα. Προσάρμοσε τον αριθμό επιλογών στη διάρκεια, στις επιλεγμένες κατηγορίες, στην ποικιλία του προορισμού και στην ποιότητα των διαθέσιμων τεκμηρίων. Μην χρησιμοποιείς σταθερό στόχο ανά κατηγορία, μην συμπληρώνεις με αδύναμες προτάσεις και μην ερευνάς κατηγορίες που ο χρήστης δεν επέλεξε.
        - Σεβάσου τις custom_instructions και τις επιλεγμένες προτιμήσεις. Ερμήνευσε budget, ποιότητα/φήμη, δημοτικότητα, τοπικότητα, πρωτοτυπία και εγγύτητα ως ξεχωριστές διαστάσεις. Μην υποθέτεις ότι το φθηνότερο είναι καλύτερο ή ότι ένα υψηλό rating αποδεικνύει καταλληλότητα.
        - Για κάθε μέρος αναζήτησε απευθείας λειτουργικό URL εικόνας που αντιστοιχεί στο συγκεκριμένο μέρος (κατά προτίμηση επίσημη σελίδα/πηγή ή Wikimedia/Wikipedia με σχετική εικόνα). Αν δεν επιβεβαιώνεται άμεσο image URL, βάλε null· μην βάζεις URL αναζήτησης ή γενική εικόνα πόλης. Πρόσθεσε image_source_url και image_attribution αν είναι διαθέσιμα.
        - Για κάθε μέρος δώσε σταθερό μοναδικό id, category, name, description, address, coordinates {latitude, longitude, status}, price {min, max, currency, basis}, rating {value, platform, review_count}, tags, image_url, official_url, source_ids, checked_at και status_on_travel_dates. Βάλε null στα επιμέρους άγνωστα πεδία και εξήγησε την αβεβαιότητα στο status.
        - Η περιγραφή κάθε μέρους πρέπει να είναι χρήσιμη για απόφαση, όχι διαφημιστική: εξήγησε συγκεκριμένα γιατί ταιριάζει ή δεν ταιριάζει στο group, ποιότητα/δημοτικότητα, εμπειρία και trade-offs έναντι κοντινών επιλογών. Πρόσθεσε why_recommended, best_for, cuisine, dietary_options, popularity, average_visit_minutes, best_time και reservation_required ως δομημένα πεδία όπου τεκμηριώνονται. Συμπερίλαβε πλήθος/πλατφόρμα αξιολογήσεων και σύγκρινε αξία με ποιότητα, όχι μόνο τιμή.
        - Για πληροφορίες που είναι ανακτήσιμες από επίσημες σελίδες ή δημόσιες καταχωρίσεις (εικόνες, διεύθυνση, συντεταγμένες, ratings/review counts), κάνε στοχευμένη αναζήτηση ανά μέρος. Μην αφήνεις πεδία κενά πριν δοκιμάσεις σχετική αναζήτηση. Μην επινοήσεις τιμή, βαθμολογία, πλήθος κριτικών, συντεταγμένες, ωράριο, URL εικόνας, κράτηση ή κατάσταση λειτουργίας. Μη χρησιμοποιείς null για να κρύψεις ότι δεν έγινε έλεγχος: γράψε καθαρά τι δεν επιβεβαιώθηκε.
        - Ξεχώρισε ημερολογιακές ημέρες από διανυκτερεύσεις. Με συγκεκριμένες ημερομηνίες, υπολόγισε duration_days ως πλήθος ημερομηνιών μαζί με άφιξη και αναχώρηση και nights ως διαφορά ημερομηνιών· μην αντιγράψεις ασύμβατες τιμές από το brief. Το itinerary.days να έχει ακριβώς μία εγγραφή ανά ημερομηνία από άφιξη έως αναχώρηση, με ημερομηνία ISO, αριθμό ημέρας, theme, stops, alternative, flex_time και estimated_day_cost_per_person_eur. Στις ημέρες άφιξης/αναχώρησης λάβε υπόψη άγνωστες ώρες πτήσης και μην υπερφορτώνεις το πρόγραμμα.
        - Κάθε stop να έχει time, place_id (ή null αν δεν είναι συγκεκριμένο μέρος), activity, travel_time_minutes, estimated_cost_per_person_eur και source_ids. Μην αλλάζεις τα ids μεταξύ places, highlights, stops, map_views και booking_tasks.
        - Κάθε itinerary day να έχει map_view_id και κάθε map_view να αντιστοιχεί σε συγκεκριμένη ημέρα ή θεματική διαδρομή με place_ids στην ίδια σειρά με το πρόγραμμα. Το app δημιουργεί ημερήσιο χάρτη από τις συντεταγμένες των stops.
        - Κράτησε ώρα, κόστος ανά άτομο, place_id και source_ids σε ξεχωριστά πεδία ανά stop, όχι μόνο σε περιγραφικό κείμενο. Βάλε σαφή βάση κόστους ή null όταν δεν τεκμηριώνεται.
        - Δημιούργησε booking_tasks μόνο για ενέργειες που είναι πραγματικά χρήσιμες ή αναγκαίες για αυτόν τον προορισμό και τις συγκεκριμένες ημερομηνίες. Για κάθε task δώσε σταθερό id, destination, related place_id ή event_id, τύπο (booking|ticket|transport|document|check|reminder), due_date/deadline αν τεκμηριώνεται, official URL, status, urgency_score ακέραιο 1–10, urgency_reason, urgency_basis (official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional), urgency_confidence (high|medium|low) και source_ids. Το 10 σημαίνει τεκμηριωμένη άμεση ανάγκη/κίνδυνο να χαθεί κρίσιμη διαθεσιμότητα· μην αποδίδεις υψηλό score επειδή απλώς «καλό είναι να κλείσετε νωρίς». Αν δεν βρέθηκε τεκμήριο για scarcity/deadline, βάλε χαμηλότερη βαθμολογία, εξήγησε ότι είναι σύσταση και μην επινοείς προθεσμία. Ξεχώρισε τις πραγματικά κρίσιμες ενέργειες από προαιρετικές υπενθυμίσεις.
        - Παράγαγε map_overview με title, subtitle και μία σύντομη trip_sentence για το πάνω overlay της σελίδας χάρτη. Να είναι συγκεκριμένα στον προορισμό και στο ταξίδι, αλλά να μην περιέχουν μη τεκμηριωμένα πραγματολογικά claims. Το app θα χρησιμοποιήσει αυτά τα πεδία δυναμικά, όχι κείμενο προορισμού hardcoded.
        - Για το date range επέστρεψε calendar_checks ανά σχετική ημερομηνία για αργίες/τοπικές γιορτές/ωράρια και events ως χωριστές εγγραφές με κατηγορία (concert, festival, public_holiday, local_celebration, exhibition, performing_arts, sport, seasonal_market, nightlife, other), ακριβείς τοπικές ημερομηνίες/ώρες όταν είναι διαθέσιμες, venue/place_id, status, source_ids και checked_at. Δημόσια αργία δεν σημαίνει αυτομάτως ότι ένας χώρος είναι κλειστός. Ξεχώρισε confirmed από candidate/not_found.
        - Οι κάρτες places να έχουν τεκμηριωμένα tags για κουζίνα/διατροφή, τύπο γεύματος ή δραστηριότητας, δημοτικότητα και καταλληλότητα για την ομάδα. Μην κρύβεις κρίσιμα στοιχεία μόνο στο description.
        - Σύνδεσε places ↔ itinerary stops ↔ ημερήσιους χάρτες ↔ ticket_options ↔ booking_tasks ↔ sources με σταθερά ids. Κάθε ωράριο/τιμή να έχει source_ids και checked_at.
        - Έλεγξε αργίες, εβδομαδιαία κλεισίματα και ειδικά ωράρια για κάθε ημερομηνία ταξιδιού από επίσημη πηγή. Δήλωσε σαφώς αν το κλείσιμο/ωράριο επιβεβαιώθηκε, δεν επιβεβαιώθηκε ή δεν βρέθηκε.
        - Οι ημερομηνίες και οι προτιμήσεις ισχύουν σε ΟΛΟ το research: για κάθε υποψήφιο place/event/transport, εφάρμοσε τους περιορισμούς του brief και έλεγξε ό,τι εξαρτάται από τις συγκεκριμένες ημερομηνίες. Παράγαγε date_checks με ένα record ανά σχετικό entity και local_date, ώστε αργίες, weekday, ωράριο, closure, event, εισιτήριο και δυνατότητα κράτησης να μην κρύβονται σε γενικές περιγραφές. Μην ισχυριστείς date-specific availability χωρίς πηγή.
        - Συμπερίλαβε κόστη ανά άτομο και ομάδα, νόμισμα, βάση υπολογισμού, τι περιλαμβάνουν/εξαιρούν και σαφή διάκριση επιβεβαιωμένων τιμών από εκτιμήσεις.
        - Κάθε source_ids πρέπει να υπάρχει στο sources και κάθε place_id να υπάρχει στο places. Κάθε source να έχει id, url, publisher, type, checked_at και supports. Προτίμησε άμεσες σελίδες πηγών, όχι αρχικές σελίδες ή γενικά αποτελέσματα αναζήτησης.

        ΑΠΑΙΤΟΥΜΕΝΟ ΣΥΜΒΟΛΑΙΟ ΕΞΟΔΟΥ
        Επέστρεψε ένα μόνο JSON object με όλα τα παρακάτω top-level keys και ακριβώς αυτό το schema_version:
        {"schema_version":"trippy-research-v1","trip_context":{},"overview":{"summary":"","seasonal_notes":[],"recommended_highlights":[{"place_id":"","reason":"","source_ids":[]}]},"map_overview":{"title":"","subtitle":"","trip_sentence":""},"calendar_checks":[{"id":"","date":"YYYY-MM-DD","day":"","status":"","details":"","source_ids":[]}],"date_checks":[{"id":"place-id|YYYY-MM-DD","entity_id":"","entity_type":"place|event|transport","local_date":"YYYY-MM-DD","status":"confirmed|closed|candidate|not_found|not_checked","opening_status":null,"holiday_or_event":null,"ticket_status":null,"reservation_status":null,"details":"","source_ids":[],"checked_at":"YYYY-MM-DD"}],"places":[{"id":"","category":"","name":"","description":"","why_recommended":"","best_for":[],"cuisine":null,"dietary_options":[],"popularity":null,"average_visit_minutes":null,"best_time":null,"reservation_required":null,"address":null,"coordinates":{"latitude":null,"longitude":null,"status":""},"price":{"min":null,"max":null,"currency":null,"basis":""},"rating":{"value":null,"platform":null,"review_count":null},"tags":[],"image_url":null,"image_source_url":null,"image_attribution":null,"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","status_on_travel_dates":""}],"events":[{"id":"","name":"","category":"","date_start":null,"date_end":null,"venue":null,"description":"","price":{"min":null,"max":null,"currency":null},"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","confidence":""}],"itinerary":{"days":[{"date":"YYYY-MM-DD","day":1,"theme":"","map_view_id":null,"stops":[{"time":null,"place_id":null,"activity":"","travel_time_minutes":null,"estimated_cost_per_person_eur":null,"source_ids":[]}],"alternative":"","flex_time":"","estimated_day_cost_per_person_eur":{"min":null,"max":null}}]},"map_views":[{"id":"","title":"","date":null,"place_ids":[],"map_url":null,"note":""}],"transport_options":[{"id":"","name":"","best_for":"","price":{"min":null,"max":null,"currency":null,"basis":""},"group_cost_estimate_eur":{"min":null,"max":null},"limitations":[],"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD"}],"ticket_options":[{"id":"","name":"","price_per_person_eur":null,"group_price_eur":null,"booking_url":null,"notes":"","source_ids":[]}],"costs":{"currency":"EUR","methodology":"","per_person_estimate":{"min":null,"max":null,"includes":[],"excludes":[]},"group_estimate":{"min":null,"max":null,"currency":"EUR","includes":[],"excludes":[]},"lodging_estimate":{"per_room_per_night_eur":null,"group_total_eur":null,"note":""},"transport_and_attractions_subtotal":{"per_person_eur":null,"group_eur":null,"basis":""},"food_estimate":{"per_person_per_day_eur":null,"group_total_eur":null,"basis":""}},"booking_tasks":[{"id":"","destination":"","local_date":null,"type":"booking|ticket|transport|document|check|reminder","urgency_score":1,"urgency_reason":"","urgency_basis":"official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional","urgency_confidence":"high|medium|low","due_date":null,"task":"","place_id":null,"event_id":null,"url":null,"source_ids":[],"status":""}],"sources":[{"id":"S01","url":"","publisher":"","type":"","checked_at":"YYYY-MM-DD","supports":[]}],"warnings":[{"id":"W01","severity":"","message":""}],"assumptions":[]}

        ΜΟΡΦΟΠΟΙΗΣΗ ΚΑΙ ΤΕΛΙΚΟΣ ΕΛΕΓΧΟΣ
        - Μην χρησιμοποιήσεις markdown fences, σχόλια, trailing commas, NaN ή Infinity. Χρησιμοποίησε μόνο διπλά εισαγωγικά σε keys/strings και null για άγνωστες τιμές.
        - Μην παραλείψεις top-level keys. Για λίστα χωρίς αποτελέσματα επέστρεψε []. Για άγνωστα scalar fields επέστρεψε null.
        - Πριν την τελική απάντηση, έλεγξε ότι το JSON γίνεται parse, τα ids/πηγές συνδέονται, οι ημερομηνίες και τα πλήθη ημερών συμφωνούν και το αποτέλεσμα δεν είναι κομμένο.
        - Η απάντηση πρέπει να είναι όλο το JSON από το πρώτο { έως το τελευταίο }, χωρίς πρόλογο ή επίλογο. Αν η διεπαφή υποστηρίζει δημιουργία αρχείου, επισύναψε και αρχείο `trippy-research.json` με ακριβώς το ίδιο JSON. Μην αντικαταστήσεις το JSON κείμενο με σύνοψη ή μόνο με αρχείο.
        """
    }

    static func makeAlternatives(brief: TripBrief, currentPlace: [String: Any]?, activity: String?, placePool: [[String: Any]], reactions: [String: String], selectedRegion: String) -> String {
        func value(_ record: [String: Any], _ keys: [String]) -> String? {
            for key in keys {
                if let text = record[key] as? String, !text.isEmpty { return text }
                if let item = record[key], !(item is NSNull), !(item is [String: Any]), !(item is [Any]) { return String(describing: item) }
            }
            return nil
        }
        func jsonString(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        }
        let current: [String: Any] = [
            "activity": activity as Any? ?? NSNull(),
            "place": currentPlace.map { place in
                ["id": value(place, ["id", "place_id"]) as Any? ?? NSNull(),
                 "name": value(place, ["name", "title", "label"]) as Any? ?? NSNull(),
                 "category": value(place, ["category", "type", "kind"]) as Any? ?? NSNull(),
                 "description": value(place, ["description", "summary", "notes"]) as Any? ?? "",
                 "address": value(place, ["address", "area", "neighborhood"]) as Any? ?? NSNull(),
                 "tags": place["tags"] as? [String] ?? [],
                 "rating": place["rating"] ?? NSNull(),
                 "coordinates": place["coordinates"] ?? NSNull()] as [String: Any]
            } ?? NSNull(),
            "destination": brief.destination,
            "date_range": [brief.startDate, brief.endDate],
            "group": brief.group,
            "budget": brief.budget as Any? ?? NSNull(),
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "preferred_region": selectedRegion
        ]
        let pool = placePool.map { place -> [String: Any] in
            let id = value(place, ["id", "place_id"])
            return ["id": id as Any? ?? NSNull(),
             "name": value(place, ["name", "title", "label"]) as Any? ?? NSNull(),
             "category": value(place, ["category", "type", "kind"]) as Any? ?? NSNull(),
             "address": value(place, ["address", "area", "neighborhood"]) as Any? ?? NSNull(),
             "tags": place["tags"] as? [String] ?? [],
             "rating": place["rating"] ?? NSNull(),
             "user_reaction": id.flatMap { reactions["place|\($0)"] } as Any? ?? NSNull()]
        }
        return """
        Κάνε στοχευμένη, ενημερωμένη έρευνα για κοντινές εναλλακτικές στο ταξίδι. Μην ξαναγράψεις ή αντικαταστήσεις το πρόγραμμα. Το Trippy θα συγχωνεύσει το patch στο υπάρχον pool και θα κρατήσει το πρόγραμμα και τις αλλαγές του χρήστη.

        ΠΛΑΙΣΙΟ ΚΑΙ ΣΤΑΣΗ ΠΡΟΣ ΑΝΤΙΚΑΤΑΣΤΑΣΗ
        \(jsonString(current))

        ΗΔΗ ΥΠΑΡΧΟΝ POOL — ΜΗΝ ΕΠΑΝΑΛΑΒΕΙΣ ΑΥΤΑ ΤΑ IDS Ή ΤΑ ΙΔΙΑ ΜΕΡΗ
        \(jsonString(pool))

        ΒΡΕΣ 8 ΝΕΕΣ ΕΠΙΛΟΓΕΣ ΤΗΣ ΙΔΙΑΣ ΚΑΤΗΓΟΡΙΑΣ, ΠΡΟΤΙΜΗΣΕ ΣΕΙΡΑ:
        1. Απόσταση έως περίπου 2 km από την τρέχουσα στάση, αν υπάρχουν επαληθεύσιμες τοποθεσίες.
        2. Ίδια γειτονιά/περιοχή, ίδιο είδος εμπειρίας και συμβατότητα με το group, vibe, dietary needs και budget.
        3. Αν δεν υπάρχουν αρκετές κοντινές επιλογές, διεύρυνε την ακτίνα με σαφή αναφορά στην απόσταση.
        Κατάταξε με βάση φήμη, ποιότητα, rating και πλήθος κριτικών· το budget είναι φίλτρο/πλαίσιο, όχι υποκατάστατο ποιότητας. Σεβάσου τις προηγούμενες αντιδράσεις στο pool: μην επαναφέρεις επιλογή με user_reaction "dislike".

        ΕΠΑΛΗΘΕΥΣΗ
        Για κάθε καινούργιο μέρος έλεγξε επίσημη σελίδα, διεύθυνση, συντεταγμένες, εικόνα και τιμή/ratings όπου γίνεται. Κατέγραψε άμεσο URL εικόνας μόνο αν οδηγεί σε εικόνα αυτού του μέρους, μαζί με image_source_url και image_attribution. Μη μαντεύεις: βάλε null και εξήγησε το κενό. Σύνδεσε κάθε ισχυρισμό με source id και βάλε checked_at.

        ΕΠΕΣΤΡΕΨΕ ΜΟΝΟ ΕΝΑ ΕΓΚΥΡΟ JSON OBJECT PATCH, ΧΩΡΙΣ MARKDOWN:
        {"schema_version":"trippy-research-patch-v1","add_places":[{"id":"unique_stable_id","category":"","name":"","description":"","address":null,"coordinates":{"latitude":null,"longitude":null,"status":""},"price":{"min":null,"max":null,"currency":null,"basis":""},"rating":{"value":null,"platform":null,"review_count":null},"tags":[],"image_url":null,"image_source_url":null,"image_attribution":null,"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","status_on_travel_dates":""}],"add_sources":[{"id":"S-new-01","url":"","publisher":"","type":"","checked_at":"YYYY-MM-DD","supports":[]}],"warnings":[]}
        Το add_places να έχει μόνο νέα μέρη. Κάθε source_ids πρέπει να υπάρχει σε add_sources ή στις ήδη υπάρχουσες πηγές. Έλεγξε ότι το JSON γίνεται parse και μην προσθέτεις πρόλογο/επίλογο.
        """
    }
}

#Preview {
    TripFlowView()
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Map-first navigation
private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum MapPlaceCategory: String, CaseIterable, Codable, Identifiable {
    case sights = "Sights", restaurants = "Food", coffee = "Coffee"
    case brunch = "Brunch", bars = "Bars", groceries = "Groceries", metro = "Metro", other = "Other"
    case streetFood = "Street food", burgers = "Burger", seafood = "Seafood", vegan = "Vegan"
    case shopping = "Shopping", touristShops = "Local shops", parks = "Parks", clubs = "Clubs"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sights: return "building.columns"
        case .restaurants, .streetFood, .burgers, .seafood, .vegan: return "fork.knife"
        case .coffee: return "cup.and.saucer"
        case .brunch: return "sun.horizon"
        case .bars: return "wineglass"
        case .shopping: return "bag"
        case .touristShops: return "storefront"
        case .parks: return "leaf"
        case .clubs: return "music.note"
        case .groceries: return "basket"
        case .metro: return "tram"
        case .other: return "mappin"
        }
    }
    var tint: Color {
        switch self {
        case .sights: return Color(hex: "E88752")
        case .restaurants, .streetFood, .burgers, .seafood, .vegan: return Color(hex: "E56C52")
        case .coffee, .brunch: return Color(hex: "A96D45")
        case .bars, .clubs: return Color(hex: "B16E62")
        case .groceries: return Color(hex: "7E9A69")
        case .metro: return Color(hex: "718A83")
        case .shopping, .touristShops: return Color(hex: "D4A34F")
        case .parks: return Color(hex: "6F9B70")
        case .other: return AppPalette.brand
        }
    }
    static func classify(_ text: String) -> Self {
        let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if ["street food", "streetfood"].contains(where: text.contains) { return .streetFood }
        if ["burger"].contains(where: text.contains) { return .burgers }
        if ["seafood", "fish", "θαλασσι"].contains(where: text.contains) { return .seafood }
        if ["vegan", "plant based"].contains(where: text.contains) { return .vegan }
        if ["brunch", "breakfast", "πρωιν"].contains(where: text.contains) { return .brunch }
        if ["cafe", "coffee", "καφε"].contains(where: text.contains) { return .coffee }
        if ["club", "nightclub", "night life"].contains(where: text.contains) { return .clubs }
        if ["park", "garden", "πάρκ", "κηπ"].contains(where: text.contains) { return .parks }
        if ["souvenir", "tourist shop", "gift shop"].contains(where: text.contains) { return .touristShops }
        if ["shopping", "mall", "clothing", "retail"].contains(where: text.contains) { return .shopping }
        if ["bar", "pub", "nightlife", "μπαρ"].contains(where: text.contains) { return .bars }
        if ["grocery", "supermarket", "supplies", "προμηθ"].contains(where: text.contains) { return .groceries }
        if ["metro", "subway", "transit", "μετρο"].contains(where: text.contains) { return .metro }
        if ["restaurant", "food", "dining", "εστια", "φαγη"].contains(where: text.contains) { return .restaurants }
        if ["sight", "museum", "landmark", "attraction", "αξιοθ", "μουσει"].contains(where: text.contains) { return .sights }
        return .other
    }
}

private enum SearchPlaceKind: String, Codable { case area, attraction, place }

private enum MapSearchFilter: String, CaseIterable, Identifiable {
    case all, places, cities, food, cafes, sights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .places: "Places"
        case .cities: "Cities & areas"
        case .food: "Food"
        case .cafes: "Cafés"
        case .sights: "Sights"
        }
    }
    func includes(_ place: PersonalPlace) -> Bool {
        switch self {
        case .all: true
        case .places: place.searchKind != .area
        case .cities: place.searchKind == .area
        case .food: [.restaurants, .streetFood, .burgers, .seafood, .vegan, .brunch].contains(place.category)
        case .cafes: place.category == .coffee
        case .sights: place.category == .sights || place.searchKind == .attraction
        }
    }
}

private struct GooglePlacePhoto: Decodable, Identifiable {
    let name: String
    let authorAttributions: [GooglePlaceAttribution]?
    let googleMapsURL: String?
    var id: String { name }
}
private struct GooglePlaceAttribution: Decodable, Identifiable {
    let displayName: String
    let uri: String?
    let photoUri: String?
    var id: String { uri ?? displayName }
}
private struct GooglePlaceReview: Decodable, Identifiable {
    let rating: Double?
    let text: String
    let relativeTime: String
    let authorName: String
    let authorURL: String?
    let authorPhotoURL: String?
    let googleMapsURL: String?
    let visitDate: GooglePlaceVisitDate?
    var id: String { googleMapsURL ?? "\(authorName)-\(relativeTime)" }
}
private struct GooglePlaceVisitDate: Decodable {
    let year: Int?
    let month: Int?
}
private struct GooglePlaceDetails: Decodable {
    let placeID: String
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let primaryType: String
    let rating: Double?
    let reviewCount: Int?
    let openNow: Bool?
    let openingHours: [String]
    let phoneNumber: String?
    let websiteURL: String?
    let googleMapsURL: String?
    let summary: String
    let photos: [GooglePlacePhoto]
    let reviews: [GooglePlaceReview]
}
private struct GooglePlaceSearchResponse: Decodable {
    struct Place: Decodable, Identifiable {
        let placeID: String
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let primaryType: String
        let isArea: Bool?
        let boundaryLevel: String?
        let types: [String]?
        let city: String?
        let countryCode: String?
        let latitudeSpan: Double?
        let longitudeSpan: Double?
        var id: String { placeID }
    }
    let places: [Place]
}
private struct GooglePlacesRequestError: Decodable {
    let errorCode: String?
    let message: String?
    let error: String?
}

private struct PersonalPlace: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var city: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: MapPlaceCategory
    var searchKind: SearchPlaceKind? = nil
    var boundaryCountryCode: String? = nil
    var searchLatitudeSpan: Double? = nil
    var searchLongitudeSpan: Double? = nil
    var boundaryLevel: String? = nil
    var searchTypes: [String]? = nil
    var phoneNumber: String? = nil
    var websiteURL: String? = nil
    var googlePlaceID: String? = nil
    var savedAt = Date()
    var appearance: MarkAppearance? = nil
    var customCategory: String? = nil
    var pinned: Bool? = nil
    var saved: Bool? = nil
    /// Videos that brought this place in. A place mentioned by three videos is still one pin.
    var sourceIDs: [UUID]? = nil
    var isPinned: Bool { pinned == true }
    var isSaved: Bool { saved != false }
    var categoryTitle: String { customCategory?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? category.rawValue }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private enum PersonalPlaceStorage {
    static let key = "trippy.native.personalPlaces.v1"
    static let citiesKey = "trippy.native.cityCoordinates.v1"
    static func load() -> [PersonalPlace] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PersonalPlace].self, from: data)) ?? []
    }
    static func save(_ places: [PersonalPlace]) {
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func loadCities() -> [String: StoredPlaceCoordinate] {
        guard let data = UserDefaults.standard.data(forKey: citiesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: StoredPlaceCoordinate].self, from: data)) ?? [:]
    }
    static func saveCities(_ values: [String: StoredPlaceCoordinate]) {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: citiesKey) }
    }
}

private struct MapTripChoice: Identifiable {
    let id: UUID
    let title: String
    var appearance: MarkAppearance? = nil
}
private struct MapNoteChoice: Identifiable {
    let id: UUID
    let title: String
    let tripID: UUID?
}
private struct TikTokPlaceCluster: Identifiable {
    let id: String
    let title: String
    let city: String
    let mentions: [SocialPlaceMention]
}

private struct WorkspaceMapPin: Identifiable {
    var id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    var layer: String
    let category: MapPlaceCategory
    var city: String = ""
    var address: String = ""
    var badge: String?
    var searchKind: SearchPlaceKind = .place
    var boundaryCountryCode: String? = nil
    var searchLatitudeSpan: Double? = nil
    var searchLongitudeSpan: Double? = nil
    var boundaryLevel: String? = nil
    var phoneNumber: String? = nil
    var websiteURL: String? = nil
    var googlePlaceID: String? = nil
    var tripID: UUID? = nil
    var placeID: String? = nil
    var appearance: MarkAppearance? = nil
    var customCategory: String? = nil
    /// Weekly hours when the plan already knows them (Google, via the planner).
    var openingHours: OpeningHours? = nil
    var personalPlace: PersonalPlace {
        PersonalPlace(id: placeID ?? id, name: name, city: city, address: address,
                      latitude: coordinate.latitude, longitude: coordinate.longitude, category: category,
                      searchKind: searchKind, boundaryCountryCode: boundaryCountryCode,
                      searchLatitudeSpan: searchLatitudeSpan, searchLongitudeSpan: searchLongitudeSpan,
                      boundaryLevel: boundaryLevel,
                      phoneNumber: phoneNumber, websiteURL: websiteURL, googlePlaceID: googlePlaceID, appearance: appearance, customCategory: customCategory)
    }
}

private struct MapPlaceLevel: Identifiable, Equatable {
    let id: String
    let title: String
    let minimumSpan: CLLocationDegrees
    let fontSize: CGFloat
}

struct GeoBoundaryPoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum GeoBoundaryLineStyle: String, Codable, Sendable {
    case outline
    case fill
    case texture
}

struct GeoBoundaryLine: Codable, Identifiable, Sendable {
    let id: String
    let points: [GeoBoundaryPoint]
    let style: GeoBoundaryLineStyle
}

private struct GeoBoundaryMetadata: Decodable {
    let boundaryISO: String?
    let boundaryName: String?
    let boundaryType: String?
    let simplifiedGeometryGeoJSON: String?
}

actor GeoBoundaryRepository {
    static let shared = GeoBoundaryRepository()
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TrippyGeoBoundaries", isDirectory: true)
    private var catalog: [GeoBoundaryMetadata]?
    private var renderedCache: [String: [GeoBoundaryLine]] = [:]

    func boundary(countryISO2: String?, countryNames: [String], placeNames: [String], levelID: String,
                  center: GeoBoundaryPoint, includeTexture: Bool = true, requireNameMatch: Bool = false) async throws -> [GeoBoundaryLine]? {
        var countryKey = countryNames.map(Self.normalized).filter { !$0.isEmpty }
        if let countryISO2 {
            let englishName = Locale(identifier: "en").localizedString(forRegionCode: countryISO2)
            if let englishName { countryKey.append(Self.normalized(englishName)) }
            countryKey += Self.countryAliases[countryISO2, default: []].map(Self.normalized)
        }
        guard !countryKey.isEmpty else { return nil }

        let countries = try await countryCatalog()
        guard let country = countries.first(where: {
            guard let name = $0.boundaryName else { return false }
            return countryKey.contains(Self.normalized(name))
        }), let iso3 = country.boundaryISO else { return nil }

        var names = placeNames.map(Self.normalized).filter { !$0.isEmpty }
        if requireNameMatch && countryISO2?.uppercased() == "GB" && names.contains("london") { names.append("greater london") }
        let cellKey = "\(Int((center.latitude * 40).rounded()))_\(Int((center.longitude * 40).rounded()))"
        let shapeVersion = requireNameMatch ? "v5_named" : "v3"
        let cacheKey = levelID == "country" && !includeTexture ? "v6_\(iso3)_country_solid" : "\(shapeVersion)_\(iso3)_\(levelID)_\(cellKey)_\(names.sorted().joined(separator: "_"))"
        if let cached = renderedCache[cacheKey] { return cached }
        if let data = cachedData(named: "shape_\(cacheKey).json"),
           let lines = try? JSONDecoder().decode([GeoBoundaryLine].self, from: data) {
            renderedCache[cacheKey] = lines
            return lines
        }

        for adminLevel in Self.adminLevels(for: levelID) {
            try Task.checkCancellation()
            let metadataURL = URL(string: "https://www.geoboundaries.org/api/current/gbOpen/\(iso3)/ADM\(adminLevel)/")!
            guard let metadataData = try? await data(from: metadataURL, cacheName: "metadata_\(iso3)_ADM\(adminLevel).json"),
                  let metadata = Self.decodeMetadata(metadataData),
                  let geoJSONURL = metadata.simplifiedGeometryGeoJSON.flatMap(URL.init(string:)),
                  let geoJSON = try? await data(from: geoJSONURL, cacheName: "geojson_\(iso3)_ADM\(adminLevel).json"),
                  let lines = Self.matchingBoundary(in: geoJSON, names: names, center: center, includeTexture: includeTexture, requireNameMatch: requireNameMatch) else { continue }

            renderedCache[cacheKey] = lines
            if let encoded = try? JSONEncoder().encode(lines) { write(encoded, named: "shape_\(cacheKey).json") }
            return lines
        }
        return nil
    }

    private func countryCatalog() async throws -> [GeoBoundaryMetadata] {
        if let catalog { return catalog }
        let url = URL(string: "https://www.geoboundaries.org/api/current/gbOpen/ALL/ADM0/")!
        let data = try await data(from: url, cacheName: "catalog_ADM0.json")
        let values = Self.decodeMetadataList(data)
        guard !values.isEmpty else { throw URLError(.cannotDecodeContentData) }
        catalog = values
        return values
    }

    private static let countryAliases: [String: [String]] = [
        "US": ["United States of America"], "GB": ["UK"], "RU": ["Russian Federation"],
        "KR": ["South Korea", "Korea, Republic of"], "KP": ["North Korea", "Korea, Democratic People's Republic of"],
        "VN": ["Viet Nam"], "IR": ["Iran, Islamic Republic of"], "SY": ["Syrian Arab Republic"],
        "BO": ["Bolivia, Plurinational State of"], "VE": ["Venezuela, Bolivarian Republic of"],
        "TZ": ["United Republic of Tanzania"], "MD": ["Republic of Moldova"], "CZ": ["Czech Republic"],
        "CI": ["Cote d'Ivoire"], "MK": ["Macedonia"], "PS": ["State of Palestine"],
        "LA": ["Lao People's Democratic Republic"], "BN": ["Brunei Darussalam"],
        "FM": ["Federated States of Micronesia"], "CD": ["Democratic Republic of the Congo"],
        "CG": ["Republic of the Congo"]
    ]

    private func data(from url: URL, cacheName: String) async throws -> Data {
        if let data = cachedData(named: cacheName) { return data }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 25)
        request.setValue("Trippy iOS map boundaries", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        write(data, named: cacheName)
        return data
    }

    private func cachedData(named name: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(name))
    }

    private func write(_ data: Data, named name: String) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
        } catch { /* The in-memory result remains usable when the cache is unavailable. */ }
    }

    private static func decodeMetadata(_ data: Data) -> GeoBoundaryMetadata? {
        if let item = try? JSONDecoder().decode(GeoBoundaryMetadata.self, from: data) { return item }
        return decodeMetadataList(data).first
    }

    private static func decodeMetadataList(_ data: Data) -> [GeoBoundaryMetadata] {
        if let list = try? JSONDecoder().decode([GeoBoundaryMetadata].self, from: data) { return list }
        if let item = try? JSONDecoder().decode(GeoBoundaryMetadata.self, from: data) { return [item] }
        return []
    }

    private static func adminLevels(for levelID: String) -> [Int] {
        switch levelID {
        case "country": return [0]
        case "region": return [1, 2]
        case "district": return [2, 1]
        case "city": return [3, 2, 1]
        case "area": return [3, 2]
        default: return []
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func matchingBoundary(in data: Data, names: [String], center: GeoBoundaryPoint, includeTexture: Bool = true, requireNameMatch: Bool = false) -> [GeoBoundaryLine]? {
        guard let collection = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = collection["features"] as? [[String: Any]] else { return nil }
        var containing: [(nameMatches: Bool, lines: [GeoBoundaryLine])] = []
        for (featureIndex, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }
            let props = feature["properties"] as? [String: Any] ?? [:]
            let shapeName = (props["shapeName"] as? String).map(normalized) ?? ""
            let nameMatches = !shapeName.isEmpty && names.contains(shapeName)
            let polygons = polygonRings(type: type, coordinates: coordinates)
            guard !polygons.isEmpty,
                  polygons.contains(where: { polygonContains(center, rings: $0) }) else { continue }
            let lines = linesFor(polygons: polygons, featureIndex: featureIndex, includeTexture: includeTexture)
            if !lines.isEmpty {
                containing.append((nameMatches, lines))
                if nameMatches { return lines }
            }
        }
        return requireNameMatch ? nil : containing.first?.lines
    }

    private static func linesFor(polygons: [[[GeoBoundaryPoint]]], featureIndex: Int, includeTexture: Bool) -> [GeoBoundaryLine] {
        var result: [GeoBoundaryLine] = []
        let texturedPolygons = Set(polygons.indices.sorted {
            polygonExtentArea(polygons[$0]) > polygonExtentArea(polygons[$1])
        }.prefix(24))
        for (polygonIndex, polygon) in polygons.enumerated() {
            for (ringIndex, ring) in polygon.enumerated() {
                let points = simplify(ring, maximumPoints: 5_000)
                guard points.count >= 4 else { continue }
                if ringIndex == 0 {
                    result.append(GeoBoundaryLine(id: "\(featureIndex)-\(polygonIndex)-fill", points: points, style: .fill))
                }
                result.append(GeoBoundaryLine(id: "\(featureIndex)-\(polygonIndex)-\(ringIndex)-outline", points: points, style: .outline))
            }
            if includeTexture && texturedPolygons.contains(polygonIndex) {
                result += textureLines(in: polygon, featureIndex: featureIndex, polygonIndex: polygonIndex)
            }
        }
        return result
    }

    private static func polygonExtentArea(_ rings: [[GeoBoundaryPoint]]) -> Double {
        guard let points = rings.first, !points.isEmpty else { return 0 }
        let latitudes = points.map(\.latitude), longitudes = points.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else { return 0 }
        return (maxLatitude - minLatitude) * (maxLongitude - minLongitude)
    }

    private static func textureLines(in polygon: [[GeoBoundaryPoint]], featureIndex: Int, polygonIndex: Int) -> [GeoBoundaryLine] {
        guard let outer = polygon.first, outer.count >= 4 else { return [] }
        let points = simplify(outer)
        let latitudeValues = points.map(\.latitude)
        let longitudeValues = points.map(\.longitude)
        guard let minLatitude = latitudeValues.min(), let maxLatitude = latitudeValues.max(),
              let minLongitude = longitudeValues.min(), let maxLongitude = longitudeValues.max() else { return [] }
        let meanLatitude = (minLatitude + maxLatitude) / 2 * .pi / 180
        let longitudeScale = max(0.08, abs(cos(meanLatitude)))
        let minX = minLongitude * longitudeScale, maxX = maxLongitude * longitudeScale
        let minY = minLatitude, maxY = maxLatitude
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return [] }
        let spacing = span / 17
        var lines: [GeoBoundaryLine] = []
        var offset = minX - maxY
        let endOffset = maxX - minY
        var lineIndex = 0
        while offset <= endOffset {
            let endpoints = diagonalEndpoints(offset: offset, minX: minX, maxX: maxX, minY: minY, maxY: maxY, longitudeScale: longitudeScale)
            if let start = endpoints.first, let end = endpoints.last, start != end {
                for (segmentIndex, segment) in clippedSegments(from: start, to: end, polygon: polygon, longitudeScale: longitudeScale).enumerated() {
                    lines.append(GeoBoundaryLine(
                        id: "\(featureIndex)-\(polygonIndex)-hatch-\(lineIndex)-\(segmentIndex)",
                        points: segment,
                        style: .texture
                    ))
                }
            }
            offset += spacing
            lineIndex += 1
        }
        return lines
    }

    private static func diagonalEndpoints(offset: Double, minX: Double, maxX: Double, minY: Double, maxY: Double,
                                          longitudeScale: Double) -> [GeoBoundaryPoint] {
        var endpoints: [GeoBoundaryPoint] = []
        func add(x: Double, y: Double) {
            guard x >= minX - 1e-10, x <= maxX + 1e-10, y >= minY - 1e-10, y <= maxY + 1e-10 else { return }
            let point = GeoBoundaryPoint(latitude: y, longitude: x / longitudeScale)
            if !endpoints.contains(where: { abs($0.latitude - point.latitude) < 1e-9 && abs($0.longitude - point.longitude) < 1e-9 }) {
                endpoints.append(point)
            }
        }
        add(x: offset + minY, y: minY)
        add(x: offset + maxY, y: maxY)
        add(x: minX, y: minX - offset)
        add(x: maxX, y: maxX - offset)
        guard endpoints.count >= 2 else { return [] }
        return Array(endpoints.prefix(2))
    }

    private static func clippedSegments(from start: GeoBoundaryPoint, to end: GeoBoundaryPoint,
                                        polygon: [[GeoBoundaryPoint]], longitudeScale: Double) -> [[GeoBoundaryPoint]] {
        var cuts = [0.0, 1.0]
        for ring in polygon {
            guard ring.count > 1 else { continue }
            for index in ring.indices {
                let a = ring[index]
                let b = ring[(index + 1) % ring.count]
                if let t = intersectionParameter(start, end, a, b, longitudeScale: longitudeScale) { cuts.append(t) }
            }
        }
        cuts.sort()
        var uniqueCuts: [Double] = []
        for cut in cuts where uniqueCuts.last.map({ abs($0 - cut) > 1e-7 }) ?? true { uniqueCuts.append(cut) }
        guard uniqueCuts.count > 1 else { return [] }
        var segments: [[GeoBoundaryPoint]] = []
        for index in 0..<(uniqueCuts.count - 1) {
            let lower = uniqueCuts[index], upper = uniqueCuts[index + 1]
            guard upper - lower > 1e-7 else { continue }
            let midpoint = interpolate(start, end, (lower + upper) / 2)
            guard polygonContains(midpoint, rings: polygon) else { continue }
            segments.append([interpolate(start, end, lower), interpolate(start, end, upper)])
        }
        return segments
    }

    private static func intersectionParameter(_ start: GeoBoundaryPoint, _ end: GeoBoundaryPoint,
                                              _ edgeStart: GeoBoundaryPoint, _ edgeEnd: GeoBoundaryPoint,
                                              longitudeScale: Double) -> Double? {
        let rx = (end.longitude - start.longitude) * longitudeScale
        let ry = end.latitude - start.latitude
        let sx = (edgeEnd.longitude - edgeStart.longitude) * longitudeScale
        let sy = edgeEnd.latitude - edgeStart.latitude
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 1e-12 else { return nil }
        let qx = (edgeStart.longitude - start.longitude) * longitudeScale
        let qy = edgeStart.latitude - start.latitude
        let t = (qx * sy - qy * sx) / denominator
        let u = (qx * ry - qy * rx) / denominator
        return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : nil
    }

    private static func interpolate(_ start: GeoBoundaryPoint, _ end: GeoBoundaryPoint, _ fraction: Double) -> GeoBoundaryPoint {
        GeoBoundaryPoint(latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                         longitude: start.longitude + (end.longitude - start.longitude) * fraction)
    }

    private static func polygonRings(type: String, coordinates: Any) -> [[[GeoBoundaryPoint]]] {
        func rings(_ raw: Any) -> [[GeoBoundaryPoint]] {
            guard let values = raw as? [Any] else { return [] }
            return values.compactMap { rawRing in
                guard let positions = rawRing as? [Any] else { return nil }
                let points = positions.compactMap { position -> GeoBoundaryPoint? in
                    guard let pair = position as? [NSNumber], pair.count >= 2 else { return nil }
                    return GeoBoundaryPoint(latitude: pair[1].doubleValue, longitude: pair[0].doubleValue)
                }
                return points.count >= 4 ? points : nil
            }
        }
        switch type {
        case "Polygon": return [rings(coordinates)].filter { !$0.isEmpty }
        case "MultiPolygon":
            guard let polygons = coordinates as? [Any] else { return [] }
            return polygons.map(rings).filter { !$0.isEmpty }
        default: return []
        }
    }

    private static func polygonContains(_ point: GeoBoundaryPoint, rings: [[GeoBoundaryPoint]]) -> Bool {
        guard let outer = rings.first, pointInRing(point, ring: outer) else { return false }
        return !rings.dropFirst().contains(where: { pointInRing(point, ring: $0) })
    }

    private static func pointInRing(_ point: GeoBoundaryPoint, ring: [GeoBoundaryPoint]) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index], b = ring[previous]
            let crosses = (a.latitude > point.latitude) != (b.latitude > point.latitude)
            if crosses {
                let longitude = (b.longitude - a.longitude) * (point.latitude - a.latitude) /
                    (b.latitude - a.latitude) + a.longitude
                if point.longitude < longitude { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    static func simplify(_ closedRing: [GeoBoundaryPoint], maximumPoints: Int = 480) -> [GeoBoundaryPoint] {
        var ring = closedRing
        if ring.count > 1, ring.first == ring.last { ring.removeLast() }
        guard ring.count > maximumPoints else { return ring + (ring.first.map { [$0] } ?? []) }
        let anchor = ring[0]
        let farthest = ring.indices.dropFirst().max { lhs, rhs in
            squaredDistance(ring[lhs], anchor) < squaredDistance(ring[rhs], anchor)
        } ?? ring.count / 2
        let firstPath = Array(ring[0...farthest])
        let secondPath = Array(ring[farthest...]) + [ring[0]]
        var tolerance = 0.00005
        var result = ring
        while result.count > maximumPoints && tolerance < 8 {
            let first = ramerDouglasPeucker(firstPath, tolerance: tolerance)
            let second = ramerDouglasPeucker(secondPath, tolerance: tolerance)
            result = first + Array(second.dropFirst())
            tolerance *= 2
        }
        if result.first != result.last, let first = result.first { result.append(first) }
        return result
    }

    private static func ramerDouglasPeucker(_ points: [GeoBoundaryPoint], tolerance: Double) -> [GeoBoundaryPoint] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = tolerance
            var farthestIndex: Int?
            for index in (start + 1)..<end {
                let distance = segmentDistance(points[index], from: points[start], to: points[end])
                if distance > farthest { farthest = distance; farthestIndex = index }
            }
            if let farthestIndex {
                keep[farthestIndex] = true
                stack.append((start, farthestIndex)); stack.append((farthestIndex, end))
            }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func segmentDistance(_ point: GeoBoundaryPoint, from start: GeoBoundaryPoint, to end: GeoBoundaryPoint) -> Double {
        let meanLatitude = (start.latitude + end.latitude + point.latitude) / 3 * .pi / 180
        let scale = cos(meanLatitude)
        let px = point.longitude * scale, py = point.latitude
        let ax = start.longitude * scale, ay = start.latitude
        let bx = end.longitude * scale, by = end.latitude
        let dx = bx - ax, dy = by - ay
        let length = dx * dx + dy * dy
        let fraction = length == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
        return hypot(px - (ax + fraction * dx), py - (ay + fraction * dy))
    }

    private static func squaredDistance(_ lhs: GeoBoundaryPoint, _ rhs: GeoBoundaryPoint) -> Double {
        let latitudeScale = cos((lhs.latitude + rhs.latitude) / 2 * .pi / 180)
        let dx = (lhs.longitude - rhs.longitude) * latitudeScale
        let dy = lhs.latitude - rhs.latitude
        return dx * dx + dy * dy
    }
}

private struct PinCelebrationView: View {
    let emoji: String
    @State private var burst = false
    private let colors: [Color] = [Color(hex: "E56C52"), Color(hex: "E7B45C"), Color(hex: "83A477"), Color(hex: "E99B79")]
    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2 + 8)
                for index in 0..<18 {
                    let angle = Double(index) * (.pi * 2 / 18)
                    let distance = burst ? 48.0 : 2.0
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                    let rect = CGRect(x: point.x - 3, y: point.y - 5, width: 6, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[index % colors.count].opacity(burst ? 0.0 : 0.95)))
                }
            }
            Text(emoji).font(.system(size: 38)).scaleEffect(burst ? 1.15 : 0.42).offset(y: 8)
        }
        .frame(width: 160, height: 92)
        .onAppear { withAnimation(.easeOut(duration: 0.72)) { burst = true } }
    }
}

private struct SearchMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.43), control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.74), control2: CGPoint(x: rect.minX, y: rect.height * 0.64))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.height * 0.4), radius: rect.width * 0.42, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.height * 0.64), control2: CGPoint(x: rect.width * 0.72, y: rect.height * 0.74))
        path.closeSubpath()
        return path
    }
}
private struct SearchMapPinView: View {
    let category: MapPlaceCategory
    var body: some View {
        ZStack {
            SearchMapPinShape().fill(LinearGradient(colors: [category.tint.opacity(0.88), category.tint, category.tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
            SearchMapPinShape().stroke(.white.opacity(0.92), lineWidth: 1.4)
            Circle().fill(.white.opacity(0.22)).frame(width: 17, height: 8).blur(radius: 2).offset(x: -5, y: -12)
            Image(systemName: category.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).offset(y: -4)
        }
        .frame(width: 42, height: 56)
        .shadow(color: category.tint.opacity(0.38), radius: 8, y: 5)
        .overlay(alignment: .topLeading) { Circle().fill(.white.opacity(0.82)).frame(width: 6, height: 6).blur(radius: 1).offset(x: 12, y: 9) }
        .frame(width: 48, height: 60).contentShape(Rectangle())
    }
}

private struct TripRouteLeg: Identifiable {
    let id: String
    let day: Int
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let walking: Bool
}

private extension TripFlowView {
    func linkedPlaceReference(_ place: PersonalPlace) -> LinkedPlaceReference {
        LinkedPlaceReference(id: place.id, name: place.name, address: place.address,
                             latitude: place.latitude, longitude: place.longitude,
                             googlePlaceID: place.googlePlaceID)
    }
    var tripCities: [String] {
        let names = trips.map { $0.brief.destination } + savedPlaces.map(\.city) + trips.flatMap { ($0.savedPins ?? []).map(\.city) }
        return Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    var cityTaskID: String { tripCities.joined(separator: "|") }
    var personalMapHome: some View {
        TrippyMapCanvas(
            pins: savedPlaces.flatMap(personalPlaceMarkers) + generalTripPins,
            cityPins: trips.compactMap { trip in
                let city = trip.brief.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let coordinate = cityCoordinates[city]?.coordinate else { return nil }
                return WorkspaceMapPin(id: "trip-city:\(trip.id)", name: city, coordinate: coordinate,
                                       layer: "city", category: .other, city: city, badge: "1", tripID: trip.id, appearance: trip.appearance)
            },
            routes: [], savedPlaces: $savedPlaces, destination: "", fallback: HomeProfileStore.load()?.coordinate,
            categories: Set(MapPlaceCategory.allCases),
            placesBaseURL: bridgeBaseURL, placesAccessToken: bridgeToken,
            onPlacesSettings: { showAccountHub = true },
            onCity: { city in libraryMapFilter = nil; libraryCity = city; librarySection = "Trips"; rootTab = "library" },
            onCityLayer: { filter in
                libraryMapFilter = filter
                libraryCity = filter.cities.count == 1 ? filter.cities.first : nil
                librarySection = filter.layer == .trips ? "Trips" : "Pins"
                libraryQuery = ""; rootTab = "library"
            }, cityCenters: cityCoordinates, focusPlaceID: focusedSavedPlaceID,
            searchRequestID: mapSearchRequestID, onSearchRequestHandled: { mapSearchRequestID = nil },
            onNewTrip: { startNewTrip() },
            onCreateNote: { place, tripID in
                let id = UUID(); let linked = linkedPlaceReference(place); travelNotes.insert(TravelNote(id: id, title: place.name, tripID: tripID, sourceIDs: [], userText: place.address, updatedAt: .now, linkedPlaceIDs: [place.id], linkedPlaces: [linked]), at: 0); selectedTravelNoteID = id
            }, noteChoices: travelNotes.map { MapNoteChoice(id: $0.id, title: $0.title, tripID: $0.tripID) },
            onAddToNote: { place, noteID in
                guard let index = travelNotes.firstIndex(where: { $0.id == noteID }) else { return }
                let detail = [place.name, place.address].filter { !$0.isEmpty }.joined(separator: " · ")
                if !travelNotes[index].userText.localizedCaseInsensitiveContains(place.name) { travelNotes[index].userText += (travelNotes[index].userText.isEmpty ? "" : "\n") + detail }
                var linked = travelNotes[index].linkedPlaceIDs ?? []; if !linked.contains(place.id) { linked.append(place.id) }; travelNotes[index].linkedPlaceIDs = linked
                var references = travelNotes[index].linkedPlaces ?? []; let reference = linkedPlaceReference(place)
                if !references.contains(where: { $0.id == reference.id }) { references.append(reference) }; travelNotes[index].linkedPlaces = references
                travelNotes[index].updatedAt = .now; selectedTravelNoteID = noteID
            }, tripChoices: trips.map { MapTripChoice(id: $0.id, title: $0.title, appearance: $0.appearance) },
            socialSources: socialSources, socialPlaces: socialPlaces, travelNotes: travelNotes,
            onSaveTripPin: { tripID, place in
                guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
                var pins = trips[index].savedPins ?? []; if let pinIndex = pins.firstIndex(where: { $0.id == place.id }) { pins[pinIndex] = place } else { pins.append(place) }
                trips[index].savedPins = pins; trips[index].updatedAt = .now; TripStorage.save(trips)
            }
        ) {
            EmptyView()
        }
        .task(id: cityTaskID) {
            var resolvedCoordinates = cityCoordinates
            for city in tripCities where resolvedCoordinates[city] == nil || resolvedCoordinates[city]?.countryCode == nil {
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = city
                request.resultTypes = .address
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled, let item = response.mapItems.first else { continue }
                    let coordinate = item.placemark.coordinate
                    resolvedCoordinates[city] = StoredPlaceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, source: "Apple Maps city search", matchedAt: .now, countryCode: item.placemark.isoCountryCode)
                } catch { /* Unlocated cities remain accessible through Library. */ }
            }
            guard !Task.isCancelled, resolvedCoordinates != cityCoordinates else { return }
            cityCoordinates = resolvedCoordinates
            PersonalPlaceStorage.saveCities(cityCoordinates)
        }
        .environment(\.locale, Locale(identifier: "en"))
    }
    // Read every trip directly; the general map must not depend on the active workspace/day.
    var generalTripPins: [WorkspaceMapPin] { cachedGeneralTripPins }
    private func makeGeneralTripPins() -> [WorkspaceMapPin] {
        trips.flatMap { trip -> [WorkspaceMapPin] in
            var result = (trip.savedPins ?? []).map { place -> WorkspaceMapPin in
                var pin = personalPin(place)
                pin.id = "trip-pin:\(trip.id):\(place.id)"
                pin.layer = "pin"
                pin.tripID = trip.id
                pin.placeID = place.id
                return pin
            }
            guard let data = trip.research?.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return result }
            let keys = ["places", "place_options", "restaurants", "attractions", "bars", "clubs", "museums"]
            var records = keys.flatMap { key -> [[String: Any]] in
                root[key] as? [[String: Any]] ?? (root[key] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            }
            let days = (root["itinerary"] as? [String: Any])?["days"] as? [[String: Any]] ?? root["days"] as? [[String: Any]] ?? []
            records += days.flatMap { $0["stops"] as? [[String: Any]] ?? [] }
            var seen = Set((trip.savedPins ?? []).map(\.id))
            for (index, record) in records.enumerated() {
                let id = recordValue(record, keys: ["place_id", "id"]) ?? "record-\(index)"
                guard !seen.contains(id),
                      let coordinate = coordinateFromRecord(record) ?? trip.mapCoordinatesByPlaceID?[id]?.coordinate else { continue }
                seen.insert(id)
                result.append(WorkspaceMapPin(id: "trip-place:\(trip.id):\(id)",
                    name: recordValue(record, keys: ["name", "title", "activity"]) ?? "Stop",
                    coordinate: coordinate, layer: "trip", category: .classify(recordValue(record, keys: ["category", "type", "kind"]) ?? ""),
                    city: trip.brief.destination, address: recordValue(record, keys: ["address"]) ?? "",
                    tripID: trip.id, placeID: id))
            }
            return result
        }
    }
    var appearanceButton: some View {
        Button { darkMode.toggle() } label: {
            Image(systemName: darkMode ? "sun.max" : "moon").frame(width: 44, height: 44)
        }.accessibilityLabel(darkMode ? "Light appearance" : "Dark appearance")
    }
    func personalPin(_ place: PersonalPlace) -> WorkspaceMapPin {
        WorkspaceMapPin(id: place.id, name: place.name, coordinate: place.coordinate, layer: "saved", category: place.category, city: place.city, address: place.address, searchKind: place.searchKind ?? .place, boundaryCountryCode: place.boundaryCountryCode, searchLatitudeSpan: place.searchLatitudeSpan, searchLongitudeSpan: place.searchLongitudeSpan, phoneNumber: place.phoneNumber, websiteURL: place.websiteURL, googlePlaceID: place.googlePlaceID, appearance: place.appearance, customCategory: place.customCategory)
    }
    private func personalPlaceMarkers(_ place: PersonalPlace) -> [WorkspaceMapPin] {
        var result: [WorkspaceMapPin] = []
        if place.isSaved { result.append(personalPin(place)) }
        if place.isPinned {
            var pin = personalPin(place)
            pin.id = "personal-pin:" + place.id; pin.placeID = place.id; pin.layer = "pin"
            result.append(pin)
        }
        return result
    }
    var filteredLibraryTrips: [Trip] {
        trips.filter { trip in
            (libraryMapFilter?.matchesTrip(id: trip.id, city: trip.brief.destination) ?? true) &&
            (libraryCity == nil || MapCityGrouping.key(trip.brief.destination) == MapCityGrouping.key(libraryCity!)) &&
            (libraryQuery.isEmpty || "\(trip.title) \(trip.brief.destination)".localizedCaseInsensitiveContains(libraryQuery))
        }
    }
    var librarySearchPrompt: String {
        switch librarySection {
        case "Videos" where videosCommunity: return "Search places, creators, titles"
        case "Notes": return "Search notes"
        case "Videos": return "Search videos"
        case "Pins": return "Search places, notes, videos"
        default: return "Search trips"
        }
    }
    private var libraryTone: LibraryTone {
        switch librarySection {
        case "World": .notes
        case "Community": .videos
        default: LibraryTone(rawValue: librarySection.lowercased()) ?? .trips
        }
    }
    private var libraryScheme: ColorScheme { darkMode ? .dark : .light }
    private var libraryInk: Color { LibraryColors.ink(libraryScheme) }
    private var libraryMuted: Color { LibraryColors.secondary(libraryScheme) }
    private var libraryAccent: Color { libraryTone.color(libraryScheme) }
    private var libraryCollectionTitle: String {
        switch librarySection {
        case "Pins": "Your places"
        case "Videos": videosCommunity ? "Community" : "Your videos"
        case "World": "Been to"
        case "Notes": "Your notes"
        default: "Your trips"
        }
    }
    private func libraryTabSymbol(_ section: String) -> String {
        switch section {
        case "Trips": "airplane"
        case "Pins": "mappin.and.ellipse"
        case "Videos": "play.rectangle.fill"
        case "Community": "person.3.fill"
        case "Notes": "note.text"
        default: "globe.europe.africa.fill"
        }
    }
    var modernLibrary: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if librarySection == "World" {
                    TrippyScreen { WorldGlobeView(addRequestID: worldAddRequest) }
                } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        libraryFilterChip
                        HStack(spacing: 12) {
                            Text(librarySection == "Trips" ? "Your trips" : libraryCollectionTitle)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: videosCommunity)
                                .font(Sketch.display(.title, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if librarySection == "Pins" { libraryPinFilterMenu }
                            librarySearchButton
                        }.padding(.bottom, 4)
                        if librarySection == "Videos" { videosScopePicker }
                        if librarySearchVisible || !libraryQuery.isEmpty { librarySearchField }
                        TrippyScreen { libraryCollectionContent }
                    }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
                        .frame(maxWidth: 720).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                // Room for the floating bar and section dial, so the last card scrolls fully clear of them.
                .contentMargins(.bottom, Self.tabBarHeight + LibraryWheel.height, for: .scrollContent)
                .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-TrippyLibraryBottom") ? .bottom : .top)
                }
            }.background {
                if librarySection == "World" { BeenPalette.base(libraryScheme).ignoresSafeArea() }
                else { PaperBackground() }
            }.foregroundStyle(libraryInk)
                .toolbar(.hidden, for: .navigationBar)
        }.tint(libraryAccent).environment(\.locale, Locale(identifier: "en"))
    }
    /// Library sections on the dial above the tab bar.
    var librarySections: [LibraryWheel.Item] {
        ["Trips", "Pins", "Videos", "Notes", "Been to"].map { section in
            LibraryWheel.Item(id: section == "Been to" ? "World" : section, title: section, symbol: libraryTabSymbol(section))
        }
    }
    private var libraryWheelSelection: Binding<String> {
        Binding(get: { librarySection }, set: { section in
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
                libraryMapFilter = nil; librarySection = section; libraryQuery = ""; librarySearchVisible = false
            }
        })
    }
    /// "Your videos | Community" at the top of the Videos tab.
    private var videosScopePicker: some View {
        HStack(spacing: 4) {
            ForEach([false, true], id: \.self) { community in
                let on = videosCommunity == community
                Button {
                    TrippyHaptics.selection()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { videosCommunity = community; libraryQuery = "" }
                } label: {
                    Label(community ? "Community" : "Your videos", systemImage: community ? "person.3.fill" : "play.rectangle.fill")
                        .font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(on ? Sketch.paper : AppPalette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background { if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "videosScope", in: videosScopeSpace) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3))
    }
    private var libraryPinFilterMenu: some View {
                        Menu {
                            if !selectedLibraryPinTypes.isEmpty {
                                Button("Clear type filters", systemImage: "xmark.circle") { selectedLibraryPinTypes.removeAll() }
                                Divider()
                            }
                            ForEach(libraryPinTypeChoices, id: \.self) { type in
                                Button {
                                    if selectedLibraryPinTypes.contains(type) { selectedLibraryPinTypes.remove(type) }
                                    else { selectedLibraryPinTypes.insert(type) }
                                } label: {
                                    Label(type, systemImage: selectedLibraryPinTypes.contains(type) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        } label: {
                            Image(systemName: selectedLibraryPinTypes.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 18, weight: .medium)).foregroundStyle(libraryAccent)
                                .frame(width: 44, height: 44).librarySurface(radius: 22)
                        }.accessibilityLabel("Filter pins by type")
    }
    /// Your sections as pills, the same language as the bottom bar: the open one is an ink
    /// capsule with its name, the others are quiet icons with names.
    private var libraryTabs: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(["Trips", "Pins", "Videos", "Notes", "Been to"], id: \.self) { section in
                    let selection = section == "Been to" ? "World" : section
                    let selected = librarySection == selection
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) {
                            libraryMapFilter = nil; librarySection = selection; libraryQuery = ""; librarySearchVisible = false
                        }
                        withAnimation { proxy.scrollTo(section, anchor: .center) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: libraryTabSymbol(section)).symbolVariant(selected ? .fill : .none)
                                .symbolEffect(.bounce.up.byLayer, value: selected)
                            Text(section)
                        }
                        .font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Sketch.paper : AppPalette.secondaryInk)
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .background { if selected { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "libraryTab", in: libraryTabSpace) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(QuietPressStyle()).id(section)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3))
        }
        .scrollIndicators(.hidden)
        }
    }
    private func libraryCountryCode(_ city: String) -> String? {
        let key = MapCityGrouping.key(LibraryGrouping.cityTitle(city))
        return cityCoordinates.first { MapCityGrouping.key(LibraryGrouping.cityTitle($0.key)) == key }?.value.countryCode
            ?? savedPlaces.first { MapCityGrouping.key(LibraryGrouping.cityTitle($0.city)) == key }?.boundaryCountryCode
    }
    private var libraryHasSingleCity: Bool { libraryCity != nil || libraryMapFilter?.cities.count == 1 }
    private func libraryCityHeading(_ city: String, count: Int, tone: LibraryTone) -> some View {
        LibraryCityHeading(city: city, countryCode: libraryCountryCode(city), count: count, tone: tone)
    }
    @ViewBuilder private var libraryFilterChip: some View {
        if let filter = libraryMapFilter {
            let cityTitle = filter.cities.count == 1 ? filter.cities.first! : "\(filter.cities.count) cities"
            let count = filter.layer == .trips ? filteredLibraryTrips.count : libraryMapPins.count
            HStack(spacing: 8) {
                Image(systemName: filter.layer.symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(libraryTone.color(libraryScheme))
                if filter.cities.count == 1, let code = libraryCountryCode(cityTitle) {
                    Text(MarkGlyphCatalog.flag(code)).font(.system(size: 11))
                }
                Text(cityTitle).font(.custom("PlusJakartaSans-SemiBold", size: 11)).lineLimit(1)
                Circle().fill(libraryMuted.opacity(0.45)).frame(width: 3, height: 3)
                Text(filter.layer.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(libraryMuted).lineLimit(1)
                Text(count.formatted()).font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(libraryTone.color(libraryScheme))
                Spacer(minLength: 2)
                Button { libraryMapFilter = nil; libraryCity = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 20, height: 20)
                        .contentShape(Circle())
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Clear map filter")
            }
            .foregroundStyle(libraryInk).padding(.leading, 10).padding(.trailing, 4)
            .frame(height: 26).background(Capsule().fill(LibraryColors.surface(libraryScheme).opacity(0.86)))
            .overlay(Capsule().strokeBorder(libraryTone.color(libraryScheme).opacity(0.16), lineWidth: 0.8))
            .accessibilityElement(children: .contain)
        } else if let city = libraryCity {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold)).foregroundStyle(libraryTone.color(libraryScheme))
                if let code = libraryCountryCode(city) { Text(MarkGlyphCatalog.flag(code)).font(.system(size: 11)) }
                Text(city).font(.custom("PlusJakartaSans-SemiBold", size: 11)).lineLimit(1)
                Spacer(minLength: 2)
                Button { libraryCity = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 20, height: 20)
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Clear city filter")
            }
            .foregroundStyle(libraryInk).padding(.leading, 10).padding(.trailing, 4)
            .frame(height: 26).background(Capsule().fill(LibraryColors.surface(libraryScheme).opacity(0.86)))
            .overlay(Capsule().strokeBorder(libraryTone.color(libraryScheme).opacity(0.16), lineWidth: 0.8))
        }
    }
    @ViewBuilder private var libraryCollectionContent: some View {
        switch librarySection {
        case "Trips": libraryTripsCollection
        case "Pins":
            atlasPlacesLibrary
        case "Videos" where !videosCommunity: videoLibrary
        case "Videos":
            CommunityBrowseContent(baseURL: bridgeBaseURL, token: bridgeToken, initialCity: libraryCity, query: libraryQuery,
                                   preview: CommunityDemo.browse) { openCommunityVideo = CommunityVideoKey(id: $0) }
        case "Notes": atlasNotesLibrary
        case "World": WorldGlobeView(addRequestID: worldAddRequest)
        default: EmptyView()
        }
    }
    private var libraryTripsCollection: some View {
        let values = LibraryTripPhase.sorted(filteredLibraryTrips)
        return VStack(alignment: .leading, spacing: 24) {
            TripShelfView(trips: values.map(shelfTrip), onOpen: openShelfTrip,
                          onEdit: { id in if let trip = trips.first(where: { $0.id == id }) { openComposer(for: trip) } },
                          onIdentity: { id in tripIdentityTarget = id; showTripIdentity = true },
                          onComplete: completeLibraryTrip, onDelete: deleteTrip, onNew: startNewTrip,
                          journeys: JourneyStore.pruned(savedJourneys, keeping: Set(trips.map(\.id))),
                          onWhereNext: { showWhereNext = true }, onJourney: { journeySheet = JourneySheet(draft: JourneyDraft()) })
            if let city = libraryCity { socialPlaceVideoCarousel(city: city) }
        }
    }
    private func shelfTrip(_ trip: Trip) -> ShelfTrip {
        let code = libraryCountryCode(trip.brief.destination) ?? MapCityGrouping.countryCode(in: trip.brief.destination)
        var stops = 0, days = trip.brief.dateIsUnknown ? trip.brief.duration : 0
        if let research = trip.research, let data = research.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let planDays = (root["itinerary"] as? [String: Any])?["days"] as? [[String: Any]] {
            days = planDays.count
            stops = planDays.reduce(0) { $0 + (($1["stops"] as? [Any])?.count ?? 0) }
        } else if let s = LibraryTripPhase.date(trip.brief.startDate), let e = LibraryTripPhase.date(trip.brief.endDate) {
            days = (Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        }
        return ShelfTrip(id: trip.id, title: trip.title, city: MapCityGrouping.name(trip.brief.destination),
                         flag: code.map(MarkGlyphCatalog.flag), startDate: trip.brief.dateIsUnknown ? "" : trip.brief.startDate,
                         endDate: trip.brief.dateIsUnknown ? "" : trip.brief.endDate, travelers: trip.brief.travelers,
                         hasPlan: trip.research?.nonEmpty != nil, completed: LibraryTripPhase.phase(trip) == .completed,
                         colorHex: trip.appearance?.validColorHex, emoji: trip.appearance?.kind == "emoji" ? trip.appearance?.glyph : nil,
                         stops: stops, days: days)
    }
    private func openShelfTrip(_ id: UUID) {
        guard let trip = trips.first(where: { $0.id == id }) else { return }
        if trip.research?.nonEmpty == nil { openComposer(for: trip); return }
        activeTripID = trip.id; brief = trip.brief
        guideTripID = trip.id
    }
    @ViewBuilder private func guideCover(_ id: UUID) -> some View {
        if let trip = trips.first(where: { $0.id == id }), let research = trip.research?.nonEmpty {
            TripGuideView(input: GuideInput(tripID: trip.id, title: trip.title, destination: trip.brief.destination,
                                            startDate: trip.brief.startDate, endDate: trip.brief.endDate,
                                            travelers: trip.brief.travelers, research: research, travelMode: trip.brief.travelMode,
                                            bridgeURL: bridgeBaseURL, bridgeToken: bridgeToken),
                          onClose: { guideTripID = nil },
                          onOpenDetails: { showLegacyDetails = true },
                          onEditBrief: { guideTripID = nil; Task { @MainActor in try? await Task.sleep(for: .milliseconds(450)); openComposer(for: trip) } },
                          onShowMap: { guideTripID = nil; selectMapTrip(trip) })
                .sheet(isPresented: $showLegacyDetails) { legacyTripDetailPanel }
        }
    }
    private func openComposer(for trip: Trip?) {
        var seed = ComposerResult()
        if let trip {
            activeTripID = trip.id; brief = trip.brief; tripNameDraft = trip.title
            seed.destination = trip.brief.destination; seed.startDate = trip.brief.startDate; seed.endDate = trip.brief.endDate
            seed.flexible = trip.brief.dateIsUnknown; seed.duration = trip.brief.duration; seed.travelers = trip.brief.travelers
            seed.group = trip.brief.group; seed.message = trip.brief.notes; seed.budget = trip.brief.budget
            seed.arrivalTime = trip.brief.arrivalTime; seed.departureTime = trip.brief.departureTime
            seed.name = trip.customName ?? ""
            seed.tags = trip.brief.preferenceTags; seed.interests = trip.brief.interests
            seed.budgetBasis = trip.brief.budgetBasis == "group" ? "group" : "per person"
            seed.travelMode = trip.brief.travelMode; seed.mustSee = trip.brief.mustSee
            seed.pace = trip.brief.paceMode.isEmpty ? nil : trip.brief.paceMode
            seed.look = ShelfLookStore.load()[trip.id.uuidString]
        } else {
            activeTripID = nil; brief = TripBrief(); tripNameDraft = ""; tripAppearanceDraft = nil
        }
        composerSeed = seed
        showComposer = true
    }
    /// A "Where next?" pick as a new trip request, ready to adjust.
    private func openComposer(for pick: Recommendation, query: WhereNextQuery) {
        var seed = ComposerResult()
        seed.destination = pick.destination.planName
        seed.flexible = true; seed.duration = query.days
        seed.travelers = query.travelers; seed.group = query.travelers == 1 ? "Solo" : query.travelers == 2 ? "Couple" : "Friends"
        seed.travelMode = (pick.leg?.mode ?? query.mode ?? .plane).rawValue
        seed.interests = Set(TasteProfile.load().strongest(pick.destination, boosted: query.wants).prefix(3).compactMap(\.interest))
        if let budget = query.budget { seed.budget = String(budget) }
        activeTripID = nil; brief = TripBrief(); tripNameDraft = ""; tripAppearanceDraft = nil
        composerSeed = seed
        showComposer = true
    }
    /// One trip per stop, back to back, grouped as a journey. The first stop's plan starts right away;
    /// the others wait as drafts with everything filled in.
    private func createJourney(_ draft: JourneyDraft) {
        journeySheet = nil
        guard draft.stops.count > 1 else { return }
        let cities = draft.stops.map(\.place.name)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? (cities.prefix(2).joined(separator: " → ") + (cities.count > 2 ? " +\(cities.count - 2)" : ""))
        let dates = draft.dates
        var created: [Trip] = []
        for (index, stop) in draft.stops.enumerated() {
            var next = TripBrief()
            next.destination = stop.place.name
            next.startDate = GuideDates.iso.string(from: dates[index].start); next.endDate = GuideDates.iso.string(from: dates[index].end)
            next.duration = stop.nights + 1
            next.travelers = draft.travelers; next.group = draft.travelers == 1 ? "Solo" : draft.travelers == 2 ? "Couple" : draft.group
            next.interests = draft.interests.isEmpty ? ["sights", "food"] : draft.interests
            next.travelMode = draft.mode.rawValue
            let before = index == 0 ? draft.origin?.name : cities[index - 1]
            let after = index == cities.count - 1 ? (draft.origin?.name) : cities[index + 1]
            next.notes = (["Stop \(index + 1) of \(cities.count) on a journey: \(cities.joined(separator: ", "))"]
                + [before.map { "Arriving from \($0) \(draft.mode.verb) on the first day" }, after.map { "Leaving for \($0) on the last day" }].compactMap { $0 })
                .joined(separator: ". ")
            var trip = Trip(brief: next)
            trip.customName = stop.place.name
            created.append(trip)
        }
        trips.insert(contentsOf: created, at: 0)
        TripStorage.save(trips)
        JourneyStore.add(SavedJourney(name: name, mode: draft.mode, origin: draft.origin?.name, tripIDs: created.map(\.id), cities: cities,
                                      startDate: GuideDates.iso.string(from: draft.startDate), endDate: GuideDates.iso.string(from: draft.endDate)))
        savedJourneys = JourneyStore.load()
        rootTab = "library"; libraryHasMounted = true; librarySection = "Trips"
        guard let first = created.first, !isResearching else { return }
        activeTripID = first.id; brief = first.brief; tripNameDraft = first.title
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(500)); startLiveResearch() }
    }
    private func submitComposer(_ result: ComposerResult) {
        showComposer = false
        var next = activeTrip?.brief ?? TripBrief()
        next.destination = result.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        next.dateIsUnknown = result.flexible
        next.startDate = result.flexible ? "" : result.startDate
        next.endDate = result.flexible ? "" : result.endDate
        next.duration = result.duration
        next.travelers = result.travelers
        next.group = result.group
        next.interests = result.interests.isEmpty ? ["sights", "food"] : result.interests
        next.notes = result.message
        next.budget = result.budget
        next.arrivalTime = result.arrivalTime
        next.departureTime = result.departureTime
        next.preferenceTags = result.tags
        next.budgetBasis = result.budgetBasis
        next.travelMode = result.travelMode
        next.mustSee = result.mustSee
        next.paceMode = result.pace == "speedrun" ? "speedrun" : ""
        if let pace = result.pace { self.pace = pace == "relaxed" ? 0.1 : pace == "balanced" ? 0.5 : 0.9 }
        brief = next
        if let id = activeTripID, let index = trips.firstIndex(where: { $0.id == id }) {
            trips[index].brief = next; trips[index].research = nil; trips[index].researchJobID = nil; TripStorage.save(trips)
        }
        // The guide shows flights and stay from the first open, and the stay is the plan's base.
        if let id = activeTripID {
            var edits = GuideEditsStore.load(id, travelers: next.travelers)
            if !result.arrivalTime.isEmpty { edits.flight.arrivalTime = result.arrivalTime }
            if !result.departureTime.isEmpty { edits.flight.departureTime = result.departureTime }
            if !result.stay.isEmpty && edits.flight.stayName != result.stay {
                edits.flight.stayName = result.stay; edits.flight.stayLatitude = nil; edits.flight.stayLongitude = nil
            }
            GuideEditsStore.save(edits, id: id)
        }
        startLiveResearch()
        let chosenName = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosenName.isEmpty, let id = activeTripID, let index = trips.firstIndex(where: { $0.id == id }) {
            trips[index].customName = chosenName; TripStorage.save(trips)
        }
        // The card look picked while creating the trip.
        if let look = result.look, let id = activeTripID {
            var looks = ShelfLookStore.load(); looks[id.uuidString] = look; ShelfLookStore.save(looks)
        }
    }
    /// The trip's stay (typed in the composer or in "Flights and stay") as a point:
    /// stored coordinates when known, otherwise found on the phone from its name.
    private func planningBase(destination: String) async -> [String: Any]? {
        guard let id = activeTripID else { return nil }
        var edits = GuideEditsStore.load(id, travelers: brief.travelers)
        let name = edits.flight.stayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if edits.flight.stayLatitude == nil {
            let query = name.localizedCaseInsensitiveContains(destination) ? name : "\(name), \(destination)"
            if let found = try? await CLGeocoder().geocodeAddressString(query).first?.location?.coordinate {
                edits.flight.stayLatitude = found.latitude; edits.flight.stayLongitude = found.longitude
                GuideEditsStore.save(edits, id: id)
            }
        }
        guard let lat = edits.flight.stayLatitude, let lon = edits.flight.stayLongitude else { return nil }
        return ["name": name, "latitude": lat, "longitude": lon,
                "address": edits.flight.stayAddress.isEmpty ? NSNull() : edits.flight.stayAddress as Any]
    }
    private func completeLibraryTrip(_ id: UUID) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { trips[index].completedAt = .now; trips[index].updatedAt = .now }
        TripStorage.save(trips)
    }
    private var libraryAddSymbol: String {
        switch librarySection {
        case "Trips": "plus"
        case "Notes": "square.and.pencil"
        case "Videos": "link"
        default: "plus"
        }
    }
    private var libraryAddTitle: String {
        switch librarySection {
        case "Trips": "New trip"
        case "Notes": "New note"
        case "World": "Add a visit"
        case "Videos": "Add a video"
        default: "Add a place"
        }
    }
    /// What the floating bottom button does on the current Library page.
    func performLibraryAdd() {
        switch librarySection {
        case "Trips": startNewTrip()
        case "World": worldAddRequest = UUID()
        case "Videos": showImportLink = true
        case "Notes":
            let id = UUID()
            travelNotes.insert(TravelNote(id: id, title: "New note", tripID: nil, sourceIDs: [], userText: "", updatedAt: .now), at: 0)
            selectedTravelNoteID = id
        default:
            activeTripID = nil; stage = .library; rootTab = "map"
            mapSearchRequestID = UUID()
        }
    }
    /// Bottom-bar action for the visible page: Map and Library trips make a trip; other Library pages add their own thing.
    var bottomBarAction: TabBarAction? {
        guard rootTab == "library" else { return nil }
        switch librarySection {
        case "Trips": return .newTrip { startNewTrip() }
        case "Pins": return TabBarAction(id: "pin", label: "Add a pin", symbol: nil, run: performLibraryAdd)
        case "Videos": return TabBarAction(id: "link", label: "Add a video link", symbol: "link", run: performLibraryAdd)
        case "Notes": return TabBarAction(id: "note", label: "New note", symbol: nil, run: performLibraryAdd)
        default: return TabBarAction(id: "visit", label: "Add a visit", symbol: nil, run: performLibraryAdd)
        }
    }
    var librarySearchButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { librarySearchVisible.toggle() }
        } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold))
                .symbolEffect(.bounce, value: librarySearchVisible)
                .foregroundStyle(librarySearchVisible ? libraryAccent : Sketch.ink).frame(width: 44, height: 44).raisedCircle()
        }.buttonStyle(QuietPressStyle()).accessibilityLabel(librarySearchPrompt)
    }
    /// The field wipes up into place under the title and drops away when closed.
    var librarySearchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(libraryAccent)
            TextField(librarySearchPrompt, text: $libraryQuery).font(.body).submitLabel(.search)
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { libraryQuery = ""; librarySearchVisible = false }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(libraryMuted).frame(width: 44, height: 44)
            }.accessibilityLabel("Close search")
        }.padding(.leading, 16).padding(.trailing, 4).frame(minHeight: 52).librarySurface(radius: 26, inset: true)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                removal: .move(edge: .bottom).combined(with: .opacity)))
    }
    func libraryTripRow(_ trip: Trip) -> some View {
        let overview = trip.research?.nonEmpty != nil
        let city = MapCityGrouping.name(trip.brief.destination)
        let countryCode = libraryCountryCode(trip.brief.destination) ?? MapCityGrouping.countryCode(in: trip.brief.destination)
        let canArchive = LibraryTripPhase.phase(trip) == .upcoming
        let tripAccent = trip.appearance?.validColorHex.map(LibraryColors.hex) ?? libraryAccent
        let facts = trip.brief.libraryDateSummary
            .replacingOccurrences(of: "days · Flexible", with: "days · Flexible")
            .replacingOccurrences(of: "Dates to decide", with: "Dates to decide")
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 13) {
                Button { tripIdentityTarget = trip.id; showTripIdentity = true } label: {
                    MarkIconWell(appearance: trip.appearance, fallback: "airplane", tone: .trips, size: 54)
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Customize \(trip.title)")
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(countryCode.map(MarkGlyphCatalog.flag) ?? "🌍").accessibilityHidden(true)
                        Text(city.isEmpty ? "DESTINATION TO DECIDE" : city.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.75)
                            .foregroundStyle(tripAccent).lineLimit(1)
                    }
                    Button { selectMapTrip(trip) } label: {
                        Text(trip.title).font(.custom("PlusJakartaSans-ExtraBold", size: 22, relativeTo: .title2))
                            .tracking(-0.6).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(libraryInk).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(QuietPressStyle())
                }
            }
            LibraryTripFacts(dates: facts, travelers: trip.brief.travelers, accent: tripAccent)
            HStack(spacing: 8) {
                Button { selectMapTrip(trip) } label: {
                    Label(overview ? "Overview" : "Edit", systemImage: overview ? "map" : "square.and.pencil")
                        .font(.system(size: 12, weight: .bold)).padding(.horizontal, 13).frame(height: 40)
                        .foregroundStyle(tripAccent).background(tripAccent.opacity(libraryScheme == .dark ? 0.18 : 0.1), in: Capsule())
                }.buttonStyle(QuietPressStyle())
                if canArchive {
                    Button { completeLibraryTrip(trip.id) } label: {
                        Label("Complete", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 40).foregroundStyle(libraryMuted)
                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Complete trip")
                } else {
                    Label("Completed", systemImage: "checkmark.seal.fill").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tripAccent)
                }
                Spacer(minLength: 0)
                LibraryDeleteButton(title: trip.title) { deleteTrip(trip.id) }
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [tripAccent.opacity(libraryScheme == .dark ? 0.18 : 0.09), LibraryColors.surface(libraryScheme)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(tripAccent.opacity(libraryScheme == .dark ? 0.12 : 0.08))
                            .frame(width: 92, height: 92).blur(radius: 22).offset(x: 20, y: -24).allowsHitTesting(false)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tripAccent.opacity(libraryScheme == .dark ? 0.2 : 0.13), lineWidth: 1))
            .shadow(color: tripAccent.opacity(libraryScheme == .dark ? 0.08 : 0.055), radius: 12, x: 0, y: 5)
            .contextMenu {
                Button("Icon & color", systemImage: "paintpalette") { tripIdentityTarget = trip.id; showTripIdentity = true }
                Button("Edit trip", systemImage: "square.and.pencil") { editTrip(trip) }
                if canArchive { Button("Archive trip", systemImage: "archivebox") { completeLibraryTrip(trip.id) } }
                else if trip.completedAt != nil && !LibraryTripPhase.lastDateHasPassed(trip) {
                    Button("Move to Upcoming", systemImage: "arrow.uturn.backward") {
                    if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index].completedAt = nil; TripStorage.save(trips) }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteTrip(trip.id) }
            }
    }
    private var tripIdentityEditor: some View {
        let trip = trips.first { $0.id == tripIdentityTarget }
        return MarkIdentityEditor(title: "Customize trip", name: trip?.title ?? tripNameDraft,
            appearance: tripIdentityTarget == nil ? tripAppearanceDraft : trip?.appearance, defaultSymbol: "suitcase.rolling.fill", tone: .trips,
            allowsEmptyName: trip == nil) { name, appearance, _ in
                if let trip, let index = trips.firstIndex(where: { $0.id == trip.id }) {
                    if !name.isEmpty { trips[index].customName = name }
                    trips[index].appearance = appearance; trips[index].updatedAt = .now
                    TripStorage.save(trips)
                    if activeTripID == trip.id && stage == .brief { tripNameDraft = trips[index].title; tripAppearanceDraft = appearance }
                } else {
                    tripNameDraft = name; tripAppearanceDraft = appearance; saveDraft()
                }
            }
    }
    private func libraryPinIdentityEditor(_ record: MapLibraryPin) -> some View {
        MarkIdentityEditor(title: "Customize pin", name: record.place.name, appearance: record.place.appearance,
            defaultSymbol: record.tripID == nil && !record.place.isPinned ? "heart.fill" : "mappin", tone: .pins,
            category: record.place.customCategory, allowsCategory: true) { name, appearance, category in
                var place = record.place
                place.name = name; place.appearance = appearance; place.customCategory = category
                if let tripID = record.tripID, let index = trips.firstIndex(where: { $0.id == tripID }),
                   let pinIndex = trips[index].savedPins?.firstIndex(where: { $0.id == place.id }) {
                    trips[index].savedPins?[pinIndex] = place; trips[index].updatedAt = .now; TripStorage.save(trips)
                } else if let index = savedPlaces.firstIndex(where: { $0.id == place.id }) { savedPlaces[index] = place }
            }
    }
    private var librarySaveRecords: [MapLibraryPin] {
        savedPlaces.filter(\.isSaved).map { MapLibraryPin(id: $0.id, place: $0, tripID: nil, tripTitle: nil, kind: .save) }
    }
    private var libraryPinRecords: [MapLibraryPin] {
        let personal = savedPlaces.filter(\.isPinned).map {
            MapLibraryPin(id: "personal-pin:" + $0.id, place: $0, tripID: nil, tripTitle: nil, kind: .pin)
        }
        let fromTrips = trips.flatMap { trip in
            (trip.savedPins ?? []).map {
                MapLibraryPin(id: "trip-pin:\(trip.id):\($0.id)", place: $0, tripID: trip.id, tripTitle: trip.title, kind: .pin)
            }
        }
        return personal + fromTrips
    }
    private var libraryPinTypeChoices: [String] {
        Array(Set(libraryPinRecords.map { $0.place.categoryTitle })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    private func filteredLibraryPinRecords(_ records: [MapLibraryPin]) -> [MapLibraryPin] {
        records.filter { record in
            let place = record.place
            let matchesType = record.kind == .save || selectedLibraryPinTypes.isEmpty || selectedLibraryPinTypes.contains(place.categoryTitle)
            return matchesType
                && (libraryMapFilter?.matchesMember(id: record.id, city: place.city) ?? true)
                && (libraryCity == nil || MapCityGrouping.key(place.city) == MapCityGrouping.key(libraryCity!))
                && (libraryQuery.isEmpty || "\(place.name) \(place.city) \(place.categoryTitle)".localizedCaseInsensitiveContains(libraryQuery))
        }
    }
    private var libraryMapPins: [MapLibraryPin] {
        if let filter = libraryMapFilter {
            return filteredLibraryPinRecords(filter.layer == .saves ? librarySaveRecords : libraryPinRecords)
        }
        return filteredLibraryPinRecords(librarySaveRecords + libraryPinRecords)
    }
    // MARK: Library atlas (one index behind Pins, Videos and Notes)
    var libraryAtlas: LibraryAtlas {
        func pin(_ place: PersonalPlace, _ trip: Trip?) -> AtlasPin {
            AtlasPin(recordID: trip.map { "trip-pin:\($0.id):\(place.id)" } ?? (place.isSaved ? place.id : "personal-pin:" + place.id),
                     placeID: place.id, name: place.name, city: place.city, address: place.address, category: place.categoryTitle,
                     symbol: place.category.symbol, tint: place.category.tint, glyph: place.appearance, googlePlaceID: place.googlePlaceID,
                     countryCode: place.boundaryCountryCode, latitude: place.latitude, longitude: place.longitude,
                     mustDo: trip == nil ? place.isSaved : place.saved == true, tripID: trip?.id, tripTitle: trip?.title,
                     sourceIDs: place.sourceIDs ?? [], savedAt: place.savedAt)
        }
        let pins = savedPlaces.map { pin($0, nil) } + trips.flatMap { trip in (trip.savedPins ?? []).map { pin($0, trip) } }
        let videos = socialSources.map { source in
            AtlasVideo(id: source.id, title: studioTitle(source), author: source.envelope.tiktok?.authorHandle, cover: studioCover(source),
                       city: cityForSource(source), isTips: source.isTips, tripID: source.envelope.destination.tripID)
        }
        return LibraryAtlas(pins: pins, mentions: socialPlaces, videos: videos, notes: travelNotes, takes: placeTakes,
                            trips: trips.map { AtlasTrip(id: $0.id, title: $0.title, city: $0.brief.destination) },
                            mentionCity: cityForMention) { text in
            let category = MapPlaceCategory(rawValue: text) ?? MapPlaceCategory.classify(text)
            return (category.symbol, category.tint, category.rawValue)
        }
    }
    /// Lines and tickets for the trip's city, sized to its days and travellers.
    func openTransit() {
        let city = brief.destination
        let known = destinationCoordinate ?? cityCoordinates[city].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        transitRequest = TransitRequest(city: city, coordinate: known, days: max(1, brief.duration), travelers: max(1, brief.travelers))
    }
    /// A link tapped inside the place sheet: close the sheet first, then go there.
    private func afterPlaceSheet(_ run: @escaping () -> Void) {
        guard atlasPlaceKey != nil else { run(); return }
        atlasPlaceKey = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: run)
    }
    var atlasActions: AtlasActions {
        AtlasActions(
            showOnMap: { place in
                atlasPlaceKey = nil; showTripDetails = false; activeTripID = nil; stage = .library
                focusedSavedPlaceID = (place.pins.first { $0.tripID == nil } ?? place.pins.first)?.recordID; rootTab = "map"
            },
            toggleMustDo: { place in
                for pin in place.pins {
                    if let tripID = pin.tripID {
                        guard !place.pins.contains(where: { $0.tripID == nil }), let trip = trips.firstIndex(where: { $0.id == tripID }),
                              let index = trips[trip].savedPins?.firstIndex(where: { $0.id == pin.placeID }) else { continue }
                        trips[trip].savedPins?[index].saved = !place.mustDo; trips[trip].savedPins?[index].pinned = true
                        trips[trip].updatedAt = .now; TripStorage.save(trips)
                    } else if let index = savedPlaces.firstIndex(where: { $0.id == pin.placeID }) {
                        // Taking the heart off keeps the place as a plain pin.
                        savedPlaces[index].saved = !place.mustDo; savedPlaces[index].pinned = true
                    }
                }
            },
            putOnMap: { place in
                guard let mention = socialPlaces.first(where: { place.mentionIDs.contains($0.id) && $0.latitude != nil }),
                      let latitude = mention.latitude, let longitude = mention.longitude else { return }
                let category = MapPlaceCategory(rawValue: mention.category ?? "") ?? MapPlaceCategory.classify(mention.category ?? "")
                pinFromVideo(mention, latitude: latitude, longitude: longitude, category: category, tripID: mention.tripID, mustDo: false)
                TrippyHaptics.success()
            },
            openVideo: { id in afterPlaceSheet { selectedSocialSource = socialSources.first { $0.id == id } } },
            openNote: { id in afterPlaceSheet { selectedTravelNoteID = id } },
            writeNote: { place in afterPlaceSheet { openPlaceNote(key: place.takeKey, name: place.name, city: place.city.nonEmpty, tripID: place.trips.first?.id) } },
            openTrip: { id in atlasPlaceKey = nil; if let trip = trips.first(where: { $0.id == id }) { selectMapTrip(trip) } },
            customize: { place in
                guard let pin = place.pins.first(where: { $0.tripID == nil }) ?? place.pins.first else { return }
                let stored = pin.tripID.flatMap { id in trips.first { $0.id == id }?.savedPins?.first { $0.id == pin.placeID } }
                    ?? savedPlaces.first { $0.id == pin.placeID }
                guard let stored else { return }
                afterPlaceSheet { editingLibraryPin = MapLibraryPin(id: pin.recordID, place: stored, tripID: pin.tripID, tripTitle: pin.tripTitle, kind: pin.mustDo ? .save : .pin) }
            },
            remove: { place in
                atlasPlaceKey = nil
                if place.isOnMap {
                    // Off the map everywhere it is kept; what the videos said about it stays with the videos.
                    savedPlaces.removeAll { stored in place.pins.contains { $0.tripID == nil && $0.placeID == stored.id } }
                    for pin in place.pins {
                        guard let tripID = pin.tripID, let trip = trips.firstIndex(where: { $0.id == tripID }) else { continue }
                        trips[trip].savedPins?.removeAll { $0.id == pin.placeID }; trips[trip].updatedAt = .now
                    }
                    if place.pins.contains(where: { $0.tripID != nil }) { TripStorage.save(trips) }
                } else { place.mentionIDs.forEach(deleteSocialPlace) }
            },
            deleteNote: { deleteLibraryNote($0) },
            newNote: {
                let id = UUID(); travelNotes.insert(TravelNote(id: id, title: "New note", tripID: nil, sourceIDs: [], userText: "", updatedAt: .now), at: 0)
                selectedTravelNoteID = id
            },
            findPlace: { activeTripID = nil; stage = .library; rootTab = "map" },
            openPlace: { atlasPlaceKey = $0 },
            take: { takeBinding($0) },
            appendNote: { place, text in appendToPlaceNote(key: place.takeKey, name: place.name, city: place.city.nonEmpty, tripID: place.trips.first?.id, text: text) },
            flag: { libraryCountryCode($0).map(MarkGlyphCatalog.flag) })
    }
    /// Pins tab: every place once, whatever brought it in.
    var atlasPlacesLibrary: some View {
        let atlas = libraryAtlas
        let places = atlas.places.filter { place in
            (selectedLibraryPinTypes.isEmpty || selectedLibraryPinTypes.contains(place.category))
                && (libraryMapFilter.map { filter in place.pins.contains { filter.matchesMember(id: $0.recordID, city: $0.city) || filter.matchesMember(id: "personal-pin:" + $0.placeID, city: $0.city) } } ?? true)
                && (libraryCity == nil || MapCityGrouping.key(place.city) == MapCityGrouping.key(libraryCity!))
                && (libraryQuery.isEmpty || place.search.localizedCaseInsensitiveContains(libraryQuery))
        }
        return AtlasPlacesView(atlas: atlas, places: places, singleCity: libraryHasSingleCity, actions: atlasActions)
    }
    /// Notes tab: each note with what it is about and where it came from.
    var atlasNotesLibrary: some View {
        let atlas = libraryAtlas
        let known = Dictionary(atlas.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return AtlasNotesView(atlas: atlas, notes: filteredLibraryNotes.compactMap { known[$0.id] }, actions: atlasActions)
    }
    private func deleteLibraryPin(_ record: MapLibraryPin) {
        if let tripID = record.tripID, let index = trips.firstIndex(where: { $0.id == tripID }) {
            trips[index].savedPins?.removeAll { $0.id == record.place.id }
            trips[index].updatedAt = .now; TripStorage.save(trips)
        } else if let index = savedPlaces.firstIndex(where: { $0.id == record.place.id }) {
            if record.kind == .save { savedPlaces[index].saved = false }
            else { savedPlaces[index].pinned = false }
            if !savedPlaces[index].isPinned && !savedPlaces[index].isSaved { savedPlaces.remove(at: index) }
        }
    }
    private func deleteLibraryVideo(_ id: UUID) {
        var deleted = deletedSourceIDs
        LibraryDeletion.video(id, sources: &socialSources, notes: &travelNotes, deleted: &deleted)
        deletedSourceStorage = deleted.map(\.uuidString).sorted().joined(separator: "|")
        if selectedSocialSource?.id == id { selectedSocialSource = nil }
        if let root = SharedInbox.root { try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true)) }
        persistSocialLibrary()
    }
    private func deleteLibraryNote(_ id: UUID) {
        LibraryDeletion.note(id, notes: &travelNotes, places: &socialPlaces)
        if selectedTravelNoteID == id { selectedTravelNoteID = nil }
        persistSocialLibrary(); syncShareTargets()
    }
    private func deleteSocialPlace(_ id: UUID) {
        socialPlaces.removeAll { $0.id == id }
        for index in socialSources.indices { socialSources[index].linkedPlaceIDs?.removeAll { $0 == id } }
        for index in travelNotes.indices where travelNotes[index].placeMentionID == id { travelNotes[index].placeMentionID = nil }
        persistSocialLibrary()
    }
    private func openSocialPlace(_ place: SocialPlaceMention) {
        if let source = socialSources.first(where: { $0.id == place.sourceID }) { selectedSocialSource = source }
        else if let id = place.noteID, travelNotes.contains(where: { $0.id == id }) { selectedTravelNoteID = id }
        else {
            let id = UUID()
            travelNotes.insert(TravelNote(id: id, title: place.name, tripID: place.tripID, sourceIDs: [],
                userText: place.summary, updatedAt: .now, placeMentionID: place.id, city: place.city), at: 0)
            if let index = socialPlaces.firstIndex(where: { $0.id == place.id }) { socialPlaces[index].noteID = id }
            selectedTravelNoteID = id
        }
    }
    /// On a trip right now (today is within its dates, and you're there or location is off):
    /// open its map with a greeting instead of the general map.
    func openCurrentTrip() async {
        let today = GuideDates.parse(Date.now)
        guard let trip = trips.first(where: { trip in
            trip.research != nil && !trip.brief.startDate.isEmpty && !trip.brief.endDate.isEmpty
                && trip.brief.startDate <= today && today <= trip.brief.endDate
        }) else { return }
        let city = trip.brief.destination
        var target = cityCoordinates[city].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if target == nil { target = try? await CLGeocoder().geocodeAddressString(city).first?.location?.coordinate }
        let manager = CLLocationManager()
        let allowed = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
        if allowed, let here = manager.location, let target,
           here.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) > 80_000 { return }
        try? await Task.sleep(for: .seconds(1.2))
        selectMapTrip(trip)
        let day = (GuideDates.daysBetween(trip.brief.startDate, today) ?? 0) + 1
        let total = (GuideDates.daysBetween(trip.brief.startDate, trip.brief.endDate) ?? 0) + 1
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            tripGreeting = TripGreeting(city: city, day: day, total: total)
        }
    }

    func selectMapTrip(_ trip: Trip) {
        activeScheduleDate = nil; alternativesForItemID = nil
        selectedScheduleDayIndex = nil; selectedMapDay = nil
        workspaceTab = "Plan"
        showTripDetails = false
        resolvedCoordinates = [:]
        destinationCoordinate = nil
        activeTripID = trip.id
        brief = trip.brief
        for (id, stored) in trip.mapCoordinatesByPlaceID ?? [:] { resolvedCoordinates[id] = stored.coordinate }
        rootTab = "map"
        if trip.research == nil { openBrief() } else { stage = .workspace }
    }
    func workspacePin(itemID: String, day: [String: Any], dayIndex: Int, stopIndex: Int) -> WorkspaceMapPin? {
        let place = scheduledPlace(itemID, day: day)
        let stop = scheduledStop(itemID, day: day)
        guard let coordinate = planCoordinate(itemID, day: day) else { return nil }
        let name = place.flatMap(recordTitle) ?? stop.map(activityTitle) ?? "Stop"
        let category = MapPlaceCategory.classify(recordValue(place ?? stop ?? [:], keys: ["category", "type", "kind"]) ?? "")
        return WorkspaceMapPin(id: place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID,
                               name: name, coordinate: coordinate, layer: "planned", category: category,
                               city: brief.destination, address: recordValue(place ?? [:], keys: ["address"]) ?? "",
                               badge: "\(dayIndex + 1).\(stopIndex + 1)",
                               googlePlaceID: place.flatMap(recordGoogleID), openingHours: place.flatMap(recordHours))
    }
    /// The Google place id the planner found this place through ("google-<id>" source).
    func recordGoogleID(_ place: [String: Any]) -> String? {
        (place["source_ids"] as? [String])?.first { $0.hasPrefix("google-") }.map { String($0.dropFirst(7)) }
    }
    func recordHours(_ place: [String: Any]) -> OpeningHours? {
        (place["opening_hours"] as? [String: Any]).flatMap(OpeningHours.google)
    }
    var tripWorkspacePins: [WorkspaceMapPin] {
        var result: [WorkspaceMapPin] = []
        var plannedIDs = Set<String>()
        for (dayIndex, day) in dayRecords.enumerated() {
            for (stopIndex, itemID) in scheduleIDs(day, index: dayIndex).enumerated() {
                let id = scheduledPlace(itemID, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID
                plannedIDs.insert(id)
                if selectedMapDay == nil || selectedMapDay == dayIndex,
                   let pin = workspacePin(itemID: itemID, day: day, dayIndex: dayIndex, stopIndex: stopIndex) { result.append(pin) }
            }
        }
        for (index, place) in placeRecords.enumerated() {
            let id = recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)"
            guard !plannedIDs.contains(id), let coordinate = placeCoordinate(place) else { continue }
            result.append(WorkspaceMapPin(id: id, name: recordTitle(place) ?? "Place", coordinate: coordinate, layer: "recommended",
                                          category: .classify(recordValue(place, keys: ["category", "type", "kind"]) ?? ""), city: brief.destination,
                                          address: recordValue(place, keys: ["address"]) ?? "",
                                          googlePlaceID: recordGoogleID(place), openingHours: recordHours(place)))
        }
        let center = cityCoordinates[brief.destination]?.coordinate ?? result.first?.coordinate
        result += savedPlaces.filter { place in
            if place.city.localizedCaseInsensitiveCompare(brief.destination) == .orderedSame { return true }
            guard let center else { return false }
            return CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 60000
        }.map(personalPin)
        // One physical place can belong to several layers; choose the visible layer, then deduplicate.
        var seen = Set<String>()
        var visible: [WorkspaceMapPin] = []
        for pin in result where mapLayers.contains(pin.layer) && mapCategories.contains(pin.category) {
            guard seen.insert(pin.id).inserted else { continue }
            let duplicate = visible.contains { existing in
                existing.name.localizedCaseInsensitiveCompare(pin.name) == .orderedSame &&
                CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)) < 30
            }
            if !duplicate { visible.append(pin) }
        }
        return visible
    }
    var workspaceRouteLegs: [TripRouteLeg] {
        guard mapLayers.contains("planned") else { return [] }
        var legs: [TripRouteLeg] = []
        let base = tripBase
        for (dayIndex, day) in dayRecords.enumerated() where selectedMapDay == nil || selectedMapDay == dayIndex {
            // Each day leaves from the stay.
            if let base, let firstID = scheduleIDs(day, index: dayIndex).first,
               let first = workspacePin(itemID: firstID, day: day, dayIndex: dayIndex, stopIndex: 0) {
                legs.append(TripRouteLeg(id: "\(activeTripID?.uuidString ?? ""):\(dayIndex):base:\(firstID)", day: dayIndex,
                                         from: base.coordinate, to: first.coordinate, walking: routePreviewMode == "walking"))
            }
            let ids = scheduleIDs(day, index: dayIndex)
            guard ids.count > 1 else { continue }
            for index in 1..<ids.count {
                // A missing coordinate breaks the route. Never join over an unlocated stop.
                guard let from = workspacePin(itemID: ids[index - 1], day: day, dayIndex: dayIndex, stopIndex: index - 1),
                      let to = workspacePin(itemID: ids[index], day: day, dayIndex: dayIndex, stopIndex: index) else { continue }
                let mode = recordValue(scheduledStop(ids[index], day: day) ?? [:], keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
                guard mode == nil || ["walk", "walking", "foot", "drive", "driving", "car"].contains(mode!) else { continue }
                legs.append(TripRouteLeg(id: "\(activeTripID?.uuidString ?? ""):\(dayIndex):\(ids[index - 1]):\(ids[index])", day: dayIndex, from: from.coordinate, to: to.coordinate, walking: mode == nil ? routePreviewMode == "walking" : ["walk", "walking", "foot"].contains(mode!)))
            }
        }
        return legs
    }
    var tripMapWorkspace: some View {
        TrippyMapCanvas(pins: tripWorkspacePins + (trips.first(where: { $0.id == activeTripID })?.savedPins ?? []).map(personalPin), cityPins: [], routes: workspaceRouteLegs,
                        savedPlaces: $savedPlaces, destination: brief.destination,
                        fallback: cityCoordinates[brief.destination]?.coordinate, categories: mapCategories,
                        placesBaseURL: bridgeBaseURL, placesAccessToken: bridgeToken,
                        onPlacesSettings: { showAccountHub = true }, onCity: { _ in }, onPlanPin: { pin in
            if pin.layer == "recommended", let place = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == pin.id }), !dayRecords.isEmpty {
                let index = selectedMapDay ?? 0
                if dayRecords.indices.contains(index) { addPlaceToDay(place, date: scheduleDateKey(dayRecords[index], index: index)) }
            }
            if pin.layer == "planned" {
                let dayIndex = dayRecords.enumerated().first { dayIndex, day in
                    scheduleIDs(day, index: dayIndex).contains { itemID in
                        (scheduledPlace(itemID, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID) == pin.id
                    }
                }?.offset
                selectedMapDay = dayIndex; selectedScheduleDayIndex = dayIndex
            }
            detailsDetent = .large; showTripDetails = true
        },
                        searchRequestID: tripMapSearchRequestID, onSearchRequestHandled: { tripMapSearchRequestID = nil },
                        base: tripBase,
                        onNewTrip: { startNewTrip() }, onCreateNote: { place, tripID in
                            let id = UUID(); let linked = linkedPlaceReference(place); travelNotes.insert(TravelNote(id: id, title: place.name, tripID: tripID, sourceIDs: [], userText: place.address, updatedAt: .now, linkedPlaceIDs: [place.id], linkedPlaces: [linked]), at: 0); selectedTravelNoteID = id
                        }, noteChoices: travelNotes.map { MapNoteChoice(id: $0.id, title: $0.title, tripID: $0.tripID) },
                        onAddToNote: { place, noteID in
                            guard let index = travelNotes.firstIndex(where: { $0.id == noteID }) else { return }
                            let detail = [place.name, place.address].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !travelNotes[index].userText.localizedCaseInsensitiveContains(place.name) { travelNotes[index].userText += (travelNotes[index].userText.isEmpty ? "" : "\n") + detail }
                            var linked = travelNotes[index].linkedPlaceIDs ?? []; if !linked.contains(place.id) { linked.append(place.id) }; travelNotes[index].linkedPlaceIDs = linked
                            var references = travelNotes[index].linkedPlaces ?? []; let reference = linkedPlaceReference(place)
                            if !references.contains(where: { $0.id == reference.id }) { references.append(reference) }; travelNotes[index].linkedPlaces = references
                            travelNotes[index].updatedAt = .now; selectedTravelNoteID = noteID
                        }, tripChoices: trips.filter { $0.id == activeTripID }.map { MapTripChoice(id: $0.id, title: $0.title, appearance: $0.appearance) },
                        socialSources: socialSources, socialPlaces: socialPlaces, travelNotes: travelNotes,
                        onSaveTripPin: { tripID, place in
                            guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
                            var pins = trips[index].savedPins ?? []; if let pinIndex = pins.firstIndex(where: { $0.id == place.id }) { pins[pinIndex] = place } else { pins.append(place) }
                            trips[index].savedPins = pins; trips[index].updatedAt = .now; TripStorage.save(trips)
                        }, selectionKey: "\(activeTripID?.uuidString ?? ""):\(selectedMapDay.map(String.init) ?? "overview")",
                        schedulablePlaceIDs: dayRecords.isEmpty ? [] : Set(placeRecords.compactMap { recordValue($0, keys: ["id", "place_id"]) }),
                        planDayTitle: "Day \((selectedMapDay ?? 0) + 1)") {
            tripMapHeader
        }
        .task(id: "\(activeTripID?.uuidString ?? ""):\(activeTrip?.research?.hashValue ?? 0)") { await resolvePlaceCoordinates() }
        .safeAreaInset(edge: .bottom, spacing: 12) { tripMapShelf }
        .sheet(isPresented: $showTripMapFilters) { tripMapFilterSheet }
        .sheet(isPresented: $showTripDetails) { tripDetailPanel }
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let id = alternativesForItemID { alternativesSheet(itemID: id) }
        }
    }
    /// "9–13 Jan · 5 days · 6 travellers", falling back to the brief's own wording.
    var tripMetaLine: String {
        let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd"
        var parts: [String] = []
        if let start = parse.date(from: brief.startDate) {
            let end = parse.date(from: brief.endDate) ?? start
            let calendar = Calendar.current
            let day = DateFormatter(); day.locale = Locale(identifier: "en_GB"); day.setLocalizedDateFormatFromTemplate("d")
            let dayMonth = DateFormatter(); dayMonth.locale = Locale(identifier: "en_GB"); dayMonth.setLocalizedDateFormatFromTemplate("d MMM")
            if calendar.isDate(start, inSameDayAs: end) { parts.append(dayMonth.string(from: start)) }
            else if calendar.isDate(start, equalTo: end, toGranularity: .month) { parts.append("\(day.string(from: start))–\(dayMonth.string(from: end))") }
            else { parts.append("\(dayMonth.string(from: start)) – \(dayMonth.string(from: end))") }
            let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
            parts.append(days == 1 ? "1 day" : "\(days) days")
        } else { parts.append(brief.dateSummary) }
        parts.append(brief.travelers == 1 ? "Solo" : "\(brief.travelers) travellers")
        return parts.joined(separator: " · ")
    }
    var tripMapHeader: some View {
        HStack(spacing: 6) {
            Button { stage = .library; activeTripID = nil; rootTab = "map" } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }.buttonStyle(QuietPressStyle()).accessibilityLabel("Close trip")
            VStack(alignment: .leading, spacing: 1) {
                Text(activeTrip?.title ?? brief.title)
                    .font(.custom("Georgia-BoldItalic", size: 21, relativeTo: .title3)).tracking(-0.4)
                    .lineLimit(1).minimumScaleFactor(0.75)
                if verticalSizeClass != .compact {
                    Text(tripMetaLine).font(.custom("PlusJakartaSans-Medium", size: 12, relativeTo: .caption))
                        .foregroundStyle(AppPalette.secondaryInk).lineLimit(1).minimumScaleFactor(0.85)
                }
            }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button { tripMapSearchRequestID = UUID() } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }.buttonStyle(QuietPressStyle()).accessibilityLabel("Search the map")
            Menu {
                Button("Getting around", systemImage: "tram.fill") { openTransit() }
                Button("Map layers", systemImage: "square.3.layers.3d") { showTripMapFilters = true }
                Toggle(isOn: $tripShowsApplePlaces) { Label("Apple Maps places", systemImage: "apple.logo") }
                Button(darkMode ? "Light map" : "Dark map", systemImage: darkMode ? "sun.max" : "moon") { darkMode.toggle() }
                Divider()
                Button("Trip name", systemImage: "pencil") { tripNameDraft = activeTrip?.title ?? brief.title; showRenameTrip = true }
                Button("Edit request", systemImage: "slider.horizontal.3") { openBrief() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }.accessibilityLabel("Trip options")
        }
        .foregroundStyle(AppPalette.ink)
        .padding(.horizontal, 4).padding(.vertical, 4)
        .background(Sketch.card.opacity(0.97), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.9), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
    private func tripDayChip(_ index: Int?) -> some View {
        let selected = selectedMapDay == index
        let color = index.map { TripDayPalette.color($0, dark: darkMode) } ?? AppPalette.ink
        var date: String? = nil
        if let index, dayRecords.indices.contains(index), let raw = recordValue(dayRecords[index], keys: ["date"]) {
            let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd"
            let short = DateFormatter(); short.locale = Locale(identifier: "en_GB"); short.setLocalizedDateFormatFromTemplate("EEE d")
            date = parse.date(from: raw).map(short.string(from:))
        }
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selectedMapDay = index; selectedScheduleDayIndex = index }
        } label: {
            HStack(spacing: 6) {
                if index != nil {
                    Circle().fill(selected ? Color.white.opacity(0.9) : color).frame(width: 7, height: 7)
                }
                Text(index.map { "Day \($0 + 1)" } ?? "All days").font(.custom("PlusJakartaSans-Bold", size: 13, relativeTo: .subheadline))
                if let date {
                    Text(date).font(.custom("PlusJakartaSans-Medium", size: 12, relativeTo: .caption))
                        .opacity(selected ? 0.85 : 0.6)
                }
            }
            .lineLimit(1).fixedSize()
            .foregroundStyle(selected ? (index == nil ? AppPalette.inverseInk : .white) : AppPalette.ink)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(selected ? color : Sketch.paperDeep.opacity(0.7), in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(QuietPressStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder var tripMapShelf: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tripDayChip(nil).id(-1)
                        ForEach(dayRecords.indices, id: \.self) { index in tripDayChip(index).id(index) }
                    }.padding(.leading, 2)
                }
                .onChange(of: selectedMapDay) { _, day in
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(day ?? -1, anchor: .center) }
                }
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            Button { selectedScheduleDayIndex = selectedMapDay; detailsDetent = .large; showTripDetails = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet").font(.system(size: 13, weight: .bold))
                    Text("Plan").font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                }
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(AppPalette.inverseInk).background(AppPalette.brand, in: Capsule())
            }.buttonStyle(QuietPressStyle()).accessibilityLabel(selectedMapDay.map { "Plan for day \($0 + 1)" } ?? "Whole plan")
        }
        .padding(6)
        .background(Sketch.card.opacity(0.97), in: Capsule())
        .overlay(Capsule().strokeBorder(Sketch.rule.opacity(0.9), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: 720)
    }

    var tripPeekSummary: String {
        if let index = selectedMapDay, dayRecords.indices.contains(index) {
            return "\(scheduleIDs(dayRecords[index], index: index).count) stops · Plan and details"
        }
        if dayRecords.isEmpty { return "Plan, places and costs" }
        return "\(dayRecords.count) days · Plan, places and costs"
    }
    var tripMapFilterSheet: some View {
        NavigationStack {
            Form {
                Section("Map content") {
                    ForEach(["planned", "recommended", "saved"], id: \.self) { layer in
                        Toggle(layer == "planned" ? "Plan" : (layer == "recommended" ? "Suggestions" : "Pins"), isOn: Binding(get: { mapLayers.contains(layer) }, set: { on in
                            if on { mapLayers.insert(layer) } else { mapLayers.remove(layer) }
                        }))
                    }
                }
                Section("Categories") {
                    ForEach(MapPlaceCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { mapCategories.contains(category) }, set: { on in
                            if on { mapCategories.insert(category) } else { mapCategories.remove(category) }
                        })) { Label(category.rawValue, systemImage: category.symbol) }
                    }
                }
                Section("Route preview") {
                    Picker("Transit", selection: $routePreviewMode) {
                        Text("Walking").tag("walking"); Text("Driving").tag("driving")
                    }.pickerStyle(.segmented)
                    Text("Only used when the plan doesn't set transport already.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Show all categories") { mapCategories = Set(MapPlaceCategory.allCases) }
                }
            }.tint(AppPalette.brand).navigationTitle("Your map").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTripMapFilters = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    func mapDayButton(_ title: String, index: Int?) -> some View {
        Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selectedMapDay = index; selectedScheduleDayIndex = index } } label: {
            VStack(spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let index, dayRecords.indices.contains(index), let date = recordValue(dayRecords[index], keys: ["date"]) {
                    Text(date).font(.caption2).opacity(0.75)
                }
            }.foregroundStyle(selectedMapDay == index ? AppPalette.inverseInk : AppPalette.ink)
                .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 44)
                .modifier(SelectedMapChip(selected: selectedMapDay == index))
        }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(selectedMapDay == index ? .isSelected : [])
    }
    func mapLayerButton(_ title: String, symbol: String, layer: String) -> some View {
        Button { if mapLayers.contains(layer) { mapLayers.remove(layer) } else { mapLayers.insert(layer) } } label: {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).labelStyle(.titleOnly)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(mapLayers.contains(layer) ? AppPalette.ink : AppPalette.secondaryInk)
                .opacity(mapLayers.contains(layer) ? 1 : 0.65)
                .modifier(AdaptiveGlassControl(shape: .capsule))
                .overlay(alignment: .bottom) {
                    if mapLayers.contains(layer) { Circle().fill(AppPalette.ink).frame(width: 4, height: 4).padding(.bottom, 5) }
                }
        }.buttonStyle(QuietPressStyle()).accessibilityValue(mapLayers.contains(layer) ? "On" : "Off")
    }
    var filteredPlanPlaces: [[String: Any]] {
        placeRecords.filter { place in
            let id = recordValue(place, keys: ["id", "place_id"]) ?? ""
            let text = ["name", "description", "address", "cuisine"].compactMap { place[$0] as? String }.joined(separator: " ")
            return (planPlaceQuery.isEmpty || text.localizedCaseInsensitiveContains(planPlaceQuery))
                && (planPlaceCategory == nil || MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "") == planPlaceCategory)
                && (!planLikedOnly || activeTrip?.reactionsByItemID?["place|\(id)"] == "like")
        }
    }
    var planPlaceFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppPalette.secondaryInk)
                TextField("Name, area or cuisine", text: $planPlaceQuery).font(PlanType.body)
                    .autocorrectionDisabled()
            }.padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("All") { planPlaceCategory = nil }
                        .buttonStyle(.bordered).tint(planPlaceCategory == nil ? AppPalette.brand : AppPalette.secondaryInk)
                    ForEach(MapPlaceCategory.allCases.filter { category in
                        placeRecords.contains { MapPlaceCategory.classify(recordValue($0, keys: ["category", "type"]) ?? "") == category }
                    }) { category in
                        Button(category.rawValue) { planPlaceCategory = planPlaceCategory == category ? nil : category }
                            .buttonStyle(.bordered).tint(planPlaceCategory == category ? AppPalette.brand : AppPalette.secondaryInk)
                    }
                }
            }
            Toggle("Only liked", isOn: $planLikedOnly).font(PlanType.detail).tint(AppPalette.brand)
        }
    }
    @ViewBuilder var tripPanelContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if workspaceTab == "Places" {
                Text("Options for you").font(PlanType.title)
                Text("\(placeRecords.count) places · keep the ones you like or add them to a day.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                planPlaceFilters
                Text("\(filteredPlanPlaces.count) results").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                ForEach(Array(filteredPlanPlaces.enumerated()), id: \.offset) { index, place in placeCard(place, index: index) }
                if placeRecords.isEmpty { emptyResearchMessage }
                else if filteredPlanPlaces.isEmpty { Text("No places match these filters.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
            } else {
                analyticalCostTable
                VStack(alignment: .leading, spacing: 16) { Text("Tickets and bookings").font(PlanType.heading); ticketContent }
                DisclosureGroup("Getting around") { transportContent.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Your expenses") { budgetCalculator.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Hours and holidays") { calendarContent.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Plan sources") { sourcesSection.padding(.top, 16) }.font(PlanType.heading)
            }
        }.tint(AppPalette.ink).padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
    }

    @ViewBuilder var tripDetailPanel: some View {
        if let trip = activeTrip, let research = trip.research?.nonEmpty {
            TripGuideView(input: GuideInput(tripID: trip.id, title: trip.title, destination: trip.brief.destination,
                                            startDate: trip.brief.startDate, endDate: trip.brief.endDate,
                                            travelers: trip.brief.travelers, research: research, travelMode: trip.brief.travelMode,
                                            bridgeURL: bridgeBaseURL, bridgeToken: bridgeToken),
                          onClose: { showTripDetails = false },
                          onOpenDetails: { showLegacyDetails = true },
                          onEditBrief: { showTripDetails = false; openComposer(for: trip) })
                .id(trip.id.uuidString + String(research.count))
                .presentationDetents([.large])
                .sheet(isPresented: $showLegacyDetails) { legacyTripDetailPanel }
        } else {
            legacyTripDetailPanel
        }
    }

    var legacyTripDetailPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(activeTrip?.title ?? brief.title).font(PlanType.heading).lineLimit(1)
                Spacer()
                Button { showTripDetails = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close plan")
            }.padding(.horizontal, 20).padding(.top, 8)
            HStack(spacing: 0) {
                ForEach(["Plan", "Places", "Costs"], id: \.self) { tab in
                    Button { workspaceTab = tab } label: {
                        VStack(spacing: 8) {
                            Text(tab).font(PlanType.detail).frame(maxWidth: .infinity, minHeight: 36)
                            Rectangle().fill(workspaceTab == tab ? AppPalette.brand : .clear).frame(height: 2)
                        }.contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(workspaceTab == tab ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
            Divider()
            if workspaceTab == "Plan" {
                scheduleDayPicker.padding(.horizontal, 20).padding(.vertical, 12)
                scheduleList
            } else { ScrollView { tripPanelContent } }
        }
        .foregroundStyle(AppPalette.ink).background(AppPalette.canvas)
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.large], selection: $detailsDetent)
        .presentationDragIndicator(.visible)
        .onChange(of: selectedScheduleDayIndex) { _, day in selectedMapDay = day }
        .sheet(isPresented: Binding(get: { locatingPlanItemID != nil }, set: { if !$0 { locatingPlanItemID = nil } })) {
            if let id = locatingPlanItemID {
                let day = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(id) }?.element ?? [:]
                let place = scheduledPlace(id, day: day)
                let name = place.flatMap(recordTitle) ?? scheduledStop(id, day: day).map(activityTitle) ?? ""
                PlanLocationPicker(name: name, destination: brief.destination, center: destinationCoordinate) { coordinate in
                    let key = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? id
                    resolvedCoordinates[key] = coordinate
                    storeResolvedCoordinate(id: key, coordinate: coordinate)
                    locatingPlanItemID = nil
                }
            }
        }
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let id = alternativesForItemID { alternativesSheet(itemID: id) }
        }
    }


}

// Screen coordinates come from MapProxy, so rotation, pitch and wrapped longitudes
// use Apple's actual projection rather than latitude buckets.
private enum MapPlaceIdentity {
    struct Item {
        let id: String
        let placeID: String?
        let googleID: String?
        let name: String
        let latitude: Double
        let longitude: Double
        let layer: String
    }
    static func groups(_ items: [Item]) -> [[String]] {
        guard !items.isEmpty else { return [] }
        var parents = Array(items.indices)
        func root(_ i: Int) -> Int {
            var value = i
            while parents[value] != value { value = parents[value] }
            return value
        }
        var indexByKey: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            var keys = ["id:" + (item.placeID ?? item.id)]
            if let googleID = item.googleID, !googleID.isEmpty { keys.append("google:" + googleID) }
            let name = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if !name.isEmpty, item.latitude.isFinite, item.longitude.isFinite {
                keys.append("point:\(name):\((item.latitude * 100_000).rounded()):\((item.longitude * 100_000).rounded())")
            }
            for key in keys {
                if let other = indexByKey[key] { parents[root(index)] = root(other) }
                else { indexByKey[key] = index }
            }
        }
        let buckets = Dictionary(grouping: items.indices, by: root)
        func priority(_ item: Item) -> Int { item.layer == "pin" ? 2 : item.layer == "saved" ? 1 : 0 }
        return buckets.values.map { indices in
            indices.sorted {
                let a = items[$0], b = items[$1]
                return priority(a) == priority(b) ? a.id < b.id : priority(a) > priority(b)
            }.map { items[$0].id }
        }.sorted { $0[0] < $1[0] }
    }
}

private enum MapLayerVisibility {
    static func includes(layer: String, showSaves: Bool, showPins: Bool, showTrips: Bool,
                         categoryIncluded: Bool, tripIncluded: Bool) -> Bool {
        switch layer {
        case "saved": showSaves
        case "pin": showPins && categoryIncluded && tripIncluded
        default: showTrips && tripIncluded
        }
    }
}
private struct MapScreenPoint {
    let id: String
    let point: CGPoint
    let radius: CGFloat
}
private struct MapScreenCluster: Equatable {
    let memberIDs: [String]
    let center: CGPoint
    var id: String { memberIDs[0] }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memberIDs == rhs.memberIDs && lhs.center.x == rhs.center.x && lhs.center.y == rhs.center.y
    }
}
/// One place for how the collapsed place panel and the camera agree on what is visible.
private enum MapPanelFraming {
    static let placeHeight: CGFloat = 232
    static let areaHeight: CGFloat = 200
    static let topClutter: CGFloat = 130   // search bar and filters above the map
    static let areaFit = 2.1               // area spans ~half the visible band, so the whole outline shows
    /// Fraction of the screen height to move the camera centre south so the target sits mid-way in the visible band.
    static func visibleCenterShift(isArea: Bool) -> Double {
        let screen = max(600, UIScreen.main.bounds.height)
        let panel = isArea ? areaHeight : placeHeight
        return Double(max(0, (panel - topClutter) / 2) / screen)
    }
}
private enum MapSearchPanelLayout {
    static let topGap: CGFloat = 18
    static func height(available: CGFloat, barHeight: CGFloat) -> CGFloat {
        max(0, available - barHeight - topGap)
    }
    static func keyboardOverlap(panelBottom: CGFloat, keyboardTop: CGFloat?, panelHeight: CGFloat) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return min(panelHeight, max(0, panelBottom - keyboardTop))
    }
    static func offset(drag: CGFloat) -> CGFloat { max(0, drag) }
    static func shouldDismiss(translation: CGFloat, predicted: CGFloat) -> Bool {
        translation > 90 || (translation > 20 && predicted > 150)
    }
}
private enum MapSearchProviderStatus {
    case idle, loading, used, unavailable
    var label: String {
        switch self { case .idle: "waiting"; case .loading: "search"; case .used: "used"; case .unavailable: "not used" }
    }
}
private enum MapMarkerLayer: String, CaseIterable, Identifiable {
    case trips = "Trips", saves = "Saves", pins = "Pins"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .trips: "suitcase.rolling.fill"; case .saves: "heart.fill"; case .pins: "mappin" }
    }
    static func forLayer(_ layer: String) -> Self {
        switch layer { case "saved": .saves; case "pin": .pins; default: .trips }
    }
}
private enum MapCityGrouping {
    static func sameCity(_ first: String, countryCode firstCode: String?, _ second: String, countryCode secondCode: String?) -> Bool {
        guard key(first) == key(second) else { return false }
        let a = MapCityFlagStyle.code(firstCode ?? countryCode(in: first))
        let b = MapCityFlagStyle.code(secondCode ?? countryCode(in: second))
        return a == nil || b == nil || a == b
    }
    private static let countrySuffixes: [(name: String, code: String)] = {
        let locales = [Locale(identifier: "en_US"), Locale(identifier: "el_GR"), Locale.current]
        return Locale.Region.isoRegions.flatMap { region -> [(name: String, code: String)] in
            guard region.identifier.count == 2 else { return [] }
            return locales.compactMap { locale in
                locale.localizedString(forRegionCode: region.identifier).map { (name: $0, code: region.identifier) }
            }
        }.sorted { $0.name.count > $1.name.count }
    }()
    private static let suffixIndex: [String: [(name: String, code: String)]] = {
        let suffixes = countrySuffixes.map { (name: $0.name.lowercased(), code: $0.code) }
            + Locale.Region.isoRegions.filter { $0.identifier.count == 2 }.map { (name: $0.identifier.lowercased(), code: $0.identifier) }
        return Dictionary(grouping: suffixes, by: { lastWord($0.name) })
    }()
    private static func lastWord(_ value: String) -> String {
        String(value.split(whereSeparator: { " ,·|\t\n".contains($0) }).last ?? "")
    }
    static func prewarm() { _ = suffixIndex.count }
    static func name(_ city: String) -> String {
        let value = city.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = matchingCountrySuffix(in: value) {
            let trimmed = String(value.dropLast(suffix.name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,·|\t\n"))
            return trimmed
        }
        return value
    }
    static func key(_ city: String) -> String {
        name(city).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func countryCode(in city: String) -> String? {
        matchingCountrySuffix(in: city)?.code
    }
    private static func matchingCountrySuffix(in city: String) -> (name: String, code: String)? {
        let value = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (suffixIndex[lastWord(value)] ?? []).first { suffix in
            let name = suffix.name
            return [" ", ",", "·", "|"].contains { separator in
                value.hasSuffix(separator + name)
            }
        }
    }
    static func attachedIDs(city: String, anchorID: String, groups: [MapScreenCluster], cities: [String: String]) -> Set<String> {
        guard let group = groups.first(where: { $0.memberIDs.contains(anchorID) }) else { return [] }
        return Set(group.memberIDs.filter { $0 != anchorID && key(cities[$0] ?? "") == key(city) })
    }
    static func count(layer: MapMarkerLayer, items: [(id: String, layer: String, tripID: String?)]) -> Int {
        let matching = items.filter { MapMarkerLayer.forLayer($0.layer) == layer }
        return Set(matching.map { layer == .trips ? ($0.tripID ?? $0.id) : $0.id }).count
    }
}
private struct MapLibraryFilter {
    let cities: Set<String>
    let layer: MapMarkerLayer
    let memberIDs: Set<String>
    let tripIDs: Set<UUID>
    private func includesCity(_ city: String) -> Bool {
        cities.isEmpty || cities.contains { MapCityGrouping.key($0) == MapCityGrouping.key(city) }
    }
    func matchesTrip(id: UUID, city: String) -> Bool {
        layer == .trips && tripIDs.contains(id) && includesCity(city)
    }
    func matchesMember(id: String, city: String) -> Bool {
        layer != .trips && memberIDs.contains(id) && includesCity(city)
    }
}
private struct MapPinIdentityRequest: Identifiable {
    let pin: WorkspaceMapPin
    let tripID: UUID?
    var pinAsPrimary: Bool = false
    var id: String { pin.id }
}
private enum LibraryPinKind: Equatable { case save, pin }
private struct MapLibraryPin: Identifiable {
    let id: String
    let place: PersonalPlace
    let tripID: UUID?
    let tripTitle: String?
    let kind: LibraryPinKind
}
private struct MapCityAnchor: Identifiable {
    let id: String
    let city: String
    let coordinate: CLLocationCoordinate2D
    let countryCode: String?
}
private enum MapCityLabelStyle {
    static func size(span: Double) -> CGFloat {
        max(11, min(20, 20 - CGFloat(log2(max(0.12, span) / 0.12)) * 0.9))
    }
    static func title(city: String, countryCode: String?) -> String {
        let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let name = MapCityGrouping.name(city)
        return code.isEmpty ? name : "\(name), \(code)"
    }
}
private enum MapCityFlagStyle {
    static let minimumSpan = 16.0
    static func code(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.unicodeScalars.count == 2, code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return code
    }
    static func flag(_ code: String) -> String {
        guard let code = self.code(code) else { return "🌐" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar($0.value + 127397) }))
    }
}
private enum MapMarkerAppearance {
    case pill, dot, smallDot
    static func at(span: Double) -> Self {
        if span < 0.12 { return .pill }
        if span < 2.4 { return .dot }
        return .smallDot
    }
    var dotDiameter: CGFloat { self == .smallDot ? 12 : 16 }
    var clusterDiameter: CGFloat { self == .smallDot ? 24 : 28 }
    var collisionRadius: CGFloat { self == .smallDot ? 8 : 11 }
}
private struct MapClusterAnchor {
    let latitude: Double
    let longitude: Double
    static func center(_ points: [Self]) -> Self? {
        guard let first = points.first else { return nil }
        let latitude = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let longitude = points.reduce(0) { partial, point in
            partial + first.longitude + (point.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        } / Double(points.count)
        return Self(latitude: latitude, longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
}
private enum MapScreenClustering {
    static func groups(_ input: [MapScreenPoint], clusterRadius: CGFloat = 19) -> [MapScreenCluster] {
        var result = connectedGroups(input)
        let radii = Dictionary(input.map { ($0.id, $0.radius) }, uniquingKeysWith: max)
        while result.count > 1 {
            let byID = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let centers = result.map { cluster in
                MapScreenPoint(id: cluster.id, point: cluster.center,
                    radius: cluster.memberIDs.count > 1 ? clusterRadius : (radii[cluster.id] ?? 0))
            }
            let merged = connectedGroups(centers)
            guard merged.count < result.count else { break }
            result = merged.map { cluster in
                let old = cluster.memberIDs.compactMap { byID[$0] }
                let ids = old.flatMap(\.memberIDs).sorted()
                return MapScreenCluster(memberIDs: ids, center: CGPoint(
                    x: old.reduce(0) { $0 + $1.center.x * CGFloat($1.memberIDs.count) } / CGFloat(ids.count),
                    y: old.reduce(0) { $0 + $1.center.y * CGFloat($1.memberIDs.count) } / CGFloat(ids.count)))
            }
        }
        return result.sorted { $0.id < $1.id }
    }
    private static func connectedGroups(_ input: [MapScreenPoint]) -> [MapScreenCluster] {
        let points = input.filter { $0.point.x.isFinite && $0.point.y.isFinite }.sorted { $0.id < $1.id }
        guard !points.isEmpty else { return [] }
        let cellSize = max(1, (points.map(\.radius).max() ?? 0) * 2)
        var parents = Array(points.indices)
        func root(_ index: Int) -> Int {
            var value = index
            while parents[value] != value { value = parents[value] }
            return value
        }
        struct Cell: Hashable { let x: Int; let y: Int }
        var cells: [Cell: [Int]] = [:]
        for (index, item) in points.enumerated() {
            let x = Int(floor(item.point.x / cellSize)), y = Int(floor(item.point.y / cellSize))
            if item.radius > 0 {
                for dx in -1...1 { for dy in -1...1 {
                    for other in cells[Cell(x: x + dx, y: y + dy), default: []] where points[other].radius > 0 {
                        let threshold = item.radius + points[other].radius
                        let distance = hypot(item.point.x - points[other].point.x, item.point.y - points[other].point.y)
                        if distance < threshold {
                            let a = root(index), b = root(other)
                            parents[max(a, b)] = min(a, b)
                        }
                    }
                } }
            }
            cells[Cell(x: x, y: y), default: []].append(index)
        }
        var components: [Int: [Int]] = [:]
        for index in points.indices { components[root(index), default: []].append(index) }
        return components.values.map { members in
            MapScreenCluster(memberIDs: members.map { points[$0].id },
                center: CGPoint(x: members.reduce(0) { $0 + points[$1].point.x } / CGFloat(members.count),
                                y: members.reduce(0) { $0 + points[$1].point.y } / CGFloat(members.count)))
        }.sorted { $0.id < $1.id }
    }
}
/// One-tap "show only" filters for the map: they narrow both your own pins and Apple's places.
private enum MapQuickFilter: String, CaseIterable, Identifiable {
    case food, coffee, bars, clubs, sights, museums, parks, beaches, brunch, streetFood, vegan, markets, shopping, stay, transit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sights: "Sights"; case .museums: "Museums"; case .food: "Food"; case .coffee: "Coffee"
        case .bars: "Bars"; case .clubs: "Clubs"; case .parks: "Parks"; case .shopping: "Shops"
        case .beaches: "Beaches"; case .brunch: "Brunch"; case .streetFood: "Street food"; case .vegan: "Vegan"
        case .markets: "Markets"; case .stay: "Stay"; case .transit: "Transit"
        }
    }
    var symbol: String {
        switch self {
        case .sights: "building.columns.fill"; case .museums: "paintpalette.fill"; case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"; case .bars: "wineglass.fill"; case .clubs: "music.note"
        case .parks: "leaf.fill"; case .shopping: "bag.fill"; case .beaches: "beach.umbrella.fill"
        case .brunch: "sun.horizon.fill"; case .streetFood: "takeoutbag.and.cup.and.straw.fill"; case .vegan: "carrot.fill"
        case .markets: "basket.fill"; case .stay: "bed.double.fill"; case .transit: "tram.fill"
        }
    }
    var tint: Color {
        switch self {
        case .sights, .museums: Color(hex: "E88752"); case .food, .streetFood: Color(hex: "E56C52"); case .coffee, .brunch: Color(hex: "A96D45")
        case .bars, .clubs: Color(hex: "B16E62"); case .parks, .vegan: Color(hex: "6F9A6A"); case .shopping, .markets: Color(hex: "C99A45")
        case .beaches: Color(hex: "3E8DB5"); case .stay: Color(hex: "7462C6"); case .transit: Color(hex: "718A83")
        }
    }
    var appleCategories: [MKPointOfInterestCategory] {
        switch self {
        case .sights:
            if #available(iOS 18.0, *) { return [.landmark, .castle, .nationalMonument, .fortress, .theater] }
            return [.theater, .stadium]
        case .museums: return [.museum]
        case .food: return [.restaurant, .bakery, .foodMarket]
        case .coffee: return [.cafe]
        case .bars: return [.brewery, .winery, .nightlife]
        case .clubs: return [.nightlife]
        case .parks: return [.park, .nationalPark]
        case .shopping: return [.store]
        case .beaches: return [.beach]
        case .brunch: return [.cafe, .bakery]
        case .streetFood, .vegan: return [.restaurant]
        case .markets: return [.foodMarket]
        case .stay: return [.hotel]
        case .transit: return [.publicTransport]
        }
    }
    private static let beachWords = ["beach", "playa", "platja", "spiaggia", "plage", "praia", "παραλία", "παραλια"]
    private static let museumWords = ["museum", "museo", "musée", "musee", "museu", "μουσείο", "μουσειο", "gallery", "galleria", "galerie", "pinacoteca"]
    func includes(_ pin: WorkspaceMapPin) -> Bool {
        let isMuseum = Self.museumWords.contains { pin.name.lowercased().contains($0) }
        switch self {
        case .sights: return pin.category == .sights && !isMuseum
        case .museums: return pin.category == .sights && isMuseum
        case .food: return [.restaurants, .streetFood, .burgers, .seafood, .vegan, .brunch].contains(pin.category)
        case .coffee: return pin.category == .coffee || pin.category == .brunch
        case .bars: return pin.category == .bars
        case .clubs: return pin.category == .clubs
        case .parks: return pin.category == .parks && !Self.beachWords.contains { pin.name.lowercased().contains($0) }
        case .shopping: return [.shopping, .touristShops].contains(pin.category)
        case .beaches: return Self.beachWords.contains { pin.name.lowercased().contains($0) }
        case .brunch: return pin.category == .brunch
        case .streetFood: return [.streetFood, .burgers].contains(pin.category)
        case .vegan: return pin.category == .vegan
        case .markets: return pin.category == .groceries
        case .stay: return false   // your pins have no lodging category; this filters Apple's hotels
        case .transit: return pin.category == .metro
        }
    }
    static func decode(_ raw: String) -> Set<MapQuickFilter> { Set(raw.split(separator: "|").compactMap { MapQuickFilter(rawValue: String($0)) }) }
}

/// A small ready-to-press toggle on the map.
private struct MapQuickChip: View {
    let title: String
    let symbol: String
    let tint: Color
    let on: Bool
    var count: Int? = nil
    /// Layer switches are on by default: they stay light and dim when off. Filters fill when chosen.
    var layerSwitch = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var filled: Bool { on && !layerSwitch }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: layerSwitch && !on ? "eye.slash" : symbol).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(filled ? .white : (layerSwitch && !on ? AppPalette.secondaryInk : tint))
                Text(title).font(.custom("PlusJakartaSans-Bold", size: 13, relativeTo: .footnote))
                if let count, count > 0 { Text("\(count)").font(.custom("PlusJakartaSans-Bold", size: 11, relativeTo: .caption2)).opacity(0.7).monospacedDigit() }
            }
            .lineLimit(1).fixedSize()
            .foregroundStyle(filled ? Color.white : (layerSwitch && !on ? AppPalette.secondaryInk : AppPalette.ink))
            .strikethrough(layerSwitch && !on, color: AppPalette.secondaryInk)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Sketch.card.opacity(layerSwitch && !on ? 0.7 : (scheme == .dark ? 0.92 : 0.95))), in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.clear : Sketch.rule, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private enum AppleMapPlaceCategory: String, CaseIterable, Identifiable {
    case food = "Food", coffee = "Coffee", nightlife = "Bars", shopping = "Shops"
    case sights = "Sights", nature = "Nature", lodging = "Stay", transport = "Getting around"
    case health = "Health", services = "Services", education = "Education", sport = "Sports", other = "Other"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer"
        case .nightlife: "wineglass"
        case .shopping: "bag"
        case .sights: "building.columns"
        case .nature: "leaf"
        case .lodging: "bed.double"
        case .transport: "tram"
        case .health: "cross.case"
        case .services: "building.2"
        case .education: "graduationcap"
        case .sport: "sportscourt"
        case .other: "mappin"
        }
    }
    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .food: [.restaurant, .bakery, .foodMarket]
        case .coffee: [.cafe]
        case .nightlife: [.nightlife, .brewery, .winery]
        case .shopping: [.store]
        case .sights: [.museum, .theater, .aquarium, .zoo, .amusementPark]
        case .nature: [.park, .nationalPark, .beach]
        case .lodging: [.hotel, .campground]
        case .transport: [.airport, .publicTransport, .parking, .gasStation, .carRental, .evCharger]
        case .health: [.hospital, .pharmacy]
        case .services: [.bank, .atm, .police, .postOffice, .fireStation, .laundry, .restroom]
        case .education: [.school, .university, .library]
        case .sport: [.stadium, .fitnessCenter]
        case .other: []
        }
    }
}

private struct MapTripExtent: Identifiable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
}

private struct MapRenderedMarker: Identifiable {
    let id: String
    let members: [WorkspaceMapPin]
    let coordinate: CLLocationCoordinate2D
    var city: String = ""
    var countryCode: String? = nil
    var isCitySummary = false
    var isCompactCity = false
    // Refresh hosted annotation content when a stable geographic group gains
    // members, without changing its map identity or coordinate during a pan.
    var contentRevision: String {
        members.map { "\($0.id):\($0.layer)" }.sorted().joined(separator: "|")
    }
}

struct MapCityLabel: View {
    let city: String
    let countryCode: String?
    let span: Double
    var isVisited = false
    @Environment(\.colorScheme) private var scheme
    private var code: String? { MapCityFlagStyle.code(countryCode ?? MapCityGrouping.countryCode(in: city)) }
    private var size: CGFloat { min(14, MapCityLabelStyle.size(span: span)) }
    var body: some View {
        HStack(spacing: 5) {
            MapFlagBadge(countryCode: code, size: size + 3, visited: isVisited)
            Text(MapCityGrouping.name(city))
                .font(.custom("PlusJakartaSans-Bold", size: size)).tracking(-0.15)
                .foregroundStyle(CountryLabelColor.color(code, dark: scheme == .dark))
                .shadow(color: scheme == .dark ? .black.opacity(0.7) : .white.opacity(0.9), radius: 1.5)
        }
        .lineLimit(1).fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MapCityLabelStyle.title(city: city, countryCode: code) + (isVisited ? ", visited" : ""))
    }
}
@MainActor private enum CountryLabelColor {
    static func color(_ code: String?, dark: Bool) -> Color {
        let palette: (String, String)
        switch code?.uppercased() {
        case "ES", "DE", "SE": palette = ("8B5700", "FFD27B")
        case "PL", "PT", "JP", "NO": palette = ("9E293F", "FFA5AE")
        case "HU", "BG", "IT": palette = ("28654B", "9CDCB5")
        case "NL": palette = ("A44813", "FFBB8A")
        case "GB", "GR", "FR", "US", "UA": palette = ("254A87", "ABC9FF")
        default:
            #if canImport(UIKit)
            if let code = MapCityFlagStyle.code(code) { return CountryFlagTextureCache.color(code, dark: dark) }
            #endif
            palette = ("285C65", "ACDCE4")
        }
        return Color(hex: dark ? palette.1 : palette.0)
    }
}
private struct CountryFlagTextTexture: View {
    let countryCode: String
    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: CountryFlagTextureCache.image(countryCode)).resizable().interpolation(.medium)
        #else
        Canvas { context, size in
            let flag = context.resolve(Text(MapCityFlagStyle.flag(countryCode)).font(.system(size: 100)))
            let bounds = flag.measure(in: CGSize(width: 200, height: 200))
            guard bounds.width > 0, bounds.height > 0 else { return }
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: size.width / (bounds.width * 0.85), y: size.height / (bounds.height * 0.65))
            context.draw(flag, at: .zero, anchor: .center)
        }
        #endif
    }
}
#if canImport(UIKit)
@MainActor private enum CountryFlagTextureCache {
    private static var images: [String: UIImage] = [:]
    private static var hues: [String: CGFloat] = [:]
    static func image(_ code: String) -> UIImage {
        if let image = images[code] { return image }
        let flag = MapCityFlagStyle.flag(code) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 100)]
        let bounds = flag.size(withAttributes: attributes)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 64), format: format).image { renderer in
            let context = renderer.cgContext
            context.translateBy(x: 48, y: 32)
            context.scaleBy(x: 96 / (bounds.width * 0.85), y: 64 / (bounds.height * 0.65))
            flag.draw(at: CGPoint(x: -bounds.width / 2, y: -bounds.height / 2), withAttributes: attributes)
        }
        images[code] = image
        return image
    }
    static func color(_ code: String, dark: Bool) -> Color {
        let hue: CGFloat
        if let cached = hues[code] { hue = cached }
        else {
            var buckets = Array(repeating: 0.0, count: 24)
            var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
            if let image = image(code).cgImage {
                pixels.withUnsafeMutableBytes { bytes in
                    if let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
                    }
                }
                for pixel in stride(from: 0, to: pixels.count, by: 4) where pixels[pixel + 3] > 200 {
                    let color = UIColor(red: CGFloat(pixels[pixel]) / 255, green: CGFloat(pixels[pixel + 1]) / 255, blue: CGFloat(pixels[pixel + 2]) / 255, alpha: 1)
                    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
                    color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
                    if s > 0.3 && b > 0.2 { buckets[min(23, Int(h * 24))] += Double(s) }
                }
            }
            let dominant = buckets.indices.max { buckets[$0] < buckets[$1] } ?? 12
            hue = buckets[dominant] > 0 ? (CGFloat(dominant) + 0.5) / 24 : 0.52
            hues[code] = hue
        }
        return Color(UIColor(hue: hue, saturation: dark ? 0.4 : 0.68, brightness: dark ? 0.95 : 0.42, alpha: 1))
    }

}
#endif

// Static labels keep dense maps cheap: no material capture, flag masks, or per-pin glass.
struct LightweightMapCityLabel: View {
    let city: String?
    let countryCode: String?
    let count: Int
    let hasTrip: Bool
    let visited: Bool
    let span: Double
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 5) {
            if visited { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(hex: "D4A342")) }
            if let city { Text(city).fontWeight(.bold).lineLimit(1).fixedSize() }
            if hasTrip { Image(systemName: "airplane").font(.system(size: 10, weight: .bold)) }
            if let countryCode { Text(MarkGlyphCatalog.flag(countryCode)) }
            if count > 0 { Text(count.formatted()).fontWeight(.bold).monospacedDigit() }
        }.font(.system(size: span < 0.1 ? 14 : span < 4 ? 12 : 10, weight: .semibold, design: .rounded))
            .foregroundStyle(scheme == .dark ? Color.white : Color(hex: "24272B"))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(scheme == .dark ? Color(hex: "24272B") : Color(hex: "F7F6F2"), in: Capsule())
            .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.13), lineWidth: 0.75))
    }
}

/// City marker on the general map: round flag, name, and what the traveler keeps there.
private struct LightweightMapCityMarkerLabel: View {
    let city: String
    let countryCode: String?
    let trips: Int
    let saves: Int
    let pins: Int
    let visited: Bool
    @Environment(\.colorScheme) private var scheme
    private var hasCounters: Bool { trips > 0 || saves > 0 || pins > 0 }
    private var surface: Color { scheme == .dark ? Color(hex: "22211E") : Color(hex: "FFFCF6") }
    var body: some View {
        HStack(spacing: 7) {
            MapFlagBadge(countryCode: countryCode, size: hasCounters ? 24 : 18, visited: visited)
            VStack(alignment: .leading, spacing: 1) {
                Text(MapCityGrouping.name(city))
                    .font(.custom("PlusJakartaSans-Bold", size: 12)).tracking(-0.15).lineLimit(1)
                    .foregroundStyle(scheme == .dark ? Color(hex: "F1ECE2") : Color(hex: "1E1C19"))
                if hasCounters {
                    HStack(spacing: 8) {
                        if trips > 0 { counter(.suitcase, trips, Sketch.plum) }
                        if pins > 0 { counter(.pin, pins, Sketch.coral) }
                        if saves > 0 { counter(.heart, saves, Sketch.clay) }
                    }
                }
            }
        }
        .padding(.leading, 4).padding(.trailing, 11).padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: hasCounters ? 14 : 13, style: .continuous).fill(surface)
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.14), radius: 5, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: hasCounters ? 14 : 13, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07), lineWidth: 0.75)
        }
        .overlay(alignment: .bottom) { MapCityMarkerTail().fill(surface).frame(width: 10, height: 5).offset(y: 4.5) }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([city, trips > 0 ? "\(trips) trips" : nil, pins > 0 ? "\(pins) pins" : nil,
                             saves > 0 ? "\(saves) saves" : nil, visited ? "visited" : nil].compactMap { $0 }.joined(separator: ", "))
    }
    private func counter(_ icon: TrippyIcon, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            TrippyIconView(icon: icon, size: 10, weight: 2.6).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(scheme == .dark ? Color(hex: "B9B1A4") : Color(hex: "5E5850"))
        }
    }
}

/// A country flag cut into a circle with a white ring; a small gold check marks visited places.
struct MapFlagBadge: View {
    let countryCode: String?
    var size: CGFloat = 20
    var visited = false
    var body: some View {
        ZStack {
            if let code = MapCityFlagStyle.code(countryCode) {
                CountryFlagTextTexture(countryCode: code).scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
            } else {
                Circle().fill(Sketch.sky.opacity(0.2))
                TrippyIconView(icon: .map, size: size * 0.55, weight: 2).foregroundStyle(Sketch.sky)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
        .overlay(alignment: .bottomTrailing) {
            if visited {
                TrippyIconView(icon: .check, size: size * 0.36, weight: 3.4).foregroundStyle(.white)
                    .frame(width: size * 0.48, height: size * 0.48)
                    .background(Circle().fill(Color(hex: "C9973A")))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    .offset(x: size * 0.12, y: size * 0.08)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MapCityMarkerTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct CityNameMapPinFace: View {
    let city: String
    let countryCode: String?
    let count: Int?
    let span: Double
    let visited: Bool
    var body: some View {
        CityMapPinSurface(city: city, countryCode: countryCode, count: count, span: span, visited: visited) { EmptyView() }
    }
}
struct CityMapPinSurface<Footer: View>: View {
    let city: String
    let countryCode: String?
    let count: Int?
    let span: Double
    let visited: Bool
    var onHeaderTap: (() -> Void)? = nil
    @ViewBuilder let footer: Footer
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 2) {
            if let onHeaderTap {
                Button(action: onHeaderTap) { header }.buttonStyle(QuietPressStyle())
            } else { header }
            footer
        }.padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 13)
            .fixedSize(horizontal: true, vertical: true)
            .modifier(CityNameMapPinGlass())
    }
    private var header: some View {
        HStack(spacing: 8) {
                MapCityLabel(city: city, countryCode: countryCode, span: span, isVisited: visited)
                if let count, count > 0 {
                    Text(count.formatted()).font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(scheme == .dark ? .white : Color(hex: "24322D"))
                        .padding(.leading, 8).overlay(alignment: .leading) {
                            Rectangle().fill(.primary.opacity(0.2)).frame(width: 0.5, height: 12)
                        }
                }
            }
    }
}
struct CountryCityClusterFace: View {
    let countryCode: String
    let cityCount: Int
    let visited: Bool
    let counts: [Int]
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if visited { Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "E2BB50")) }
                Text(MapCityFlagStyle.flag(countryCode)).font(.system(size: 22))
                Text(cityCount.formatted()).font(.system(size: 9, weight: .bold)).monospacedDigit()
                    .padding(3).background(.primary.opacity(0.12), in: Circle())
            }
            HStack(spacing: 3) {
                ForEach(Array(counts.enumerated()).filter { $0.element > 0 }.map(\.offset), id: \.self) { index in
                    Label(counts[index].formatted(), systemImage: ["suitcase.rolling.fill", "heart.fill", "mappin"][index])
                        .font(.system(size: 8, weight: .bold)).padding(3)
                        .background([Color.purple, .pink, .orange][index].opacity(0.22), in: Capsule())
                }
            }
        }.padding(.horizontal, 7).padding(.top, 5).padding(.bottom, 13)
            .fixedSize().modifier(CityNameMapPinGlass())
    }
}
private struct MapCityGlassCollection: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) { GlassEffectContainer(spacing: 8) { content } }
        else { content }
    }
}
private struct CityNameMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bodyBottom = rect.maxY - 9
        let radius = min(14, max(0, min(rect.width, rect.height - 9) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: bodyBottom), control: CGPoint(x: rect.maxX, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.midX + 7, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 7, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bodyBottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: bodyBottom - radius), control: CGPoint(x: rect.minX, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
private struct CityNameMapPinGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = CityNameMapPinShape()
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.clear.tint(scheme == .dark ? .black.opacity(0.2) : .white.opacity(0.16)), in: shape)
        } else {
            content.background {
                if reduceTransparency { shape.fill(scheme == .dark ? Color(hex: "252E2B") : Color(hex: "E9EEE9")) }
                else { shape.fill(.regularMaterial) }
            }.overlay(shape.stroke(.white.opacity(scheme == .dark ? 0.22 : 0.5), lineWidth: 0.7))
        }
    }
}

#Preview("Map city label sizes") {
    VStack(spacing: 24) {
        MapCityLabel(city: "Barcelona", countryCode: "ES", span: 0.03)
        MapCityLabel(city: "Barcelona", countryCode: "ES", span: 1.2)
        MapCityLabel(city: "Barcelona", countryCode: "ES", span: 80)
    }.padding(32).background(Color(hex: "E4E9D5"))
}

// White/charcoal surfaces with a lit upper edge keep the app's warm palette,
// while giving filters a tactile raised shape in either appearance.
private struct MapFilterPill: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let expandable: Bool
    let expanded: Bool
    let toggle: () -> Void
    let expand: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    Text(title).font(.custom("PlusJakartaSans-Bold", size: 12))
                    Circle().fill(enabled ? Color(hex: "64A87B") : Color(hex: "BC514A").opacity(0.24)).frame(width: 6, height: 6)
                        .shadow(color: enabled ? Color(hex: "64A87B").opacity(0.5) : .clear, radius: 3)
                }.padding(.leading, 13).padding(.trailing, expandable ? 8 : 13).frame(height: 34)
                    .contentShape(Capsule())
            }.accessibilityLabel(title).accessibilityValue(enabled ? "On" : "Off")
            if expandable {
                Rectangle().fill((isDark ? Color.white : Color.black).opacity(0.15)).frame(width: 1, height: 16)
                Button(action: expand) {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0)).frame(width: 32, height: 34)
                        .contentShape(Rectangle())
                }.accessibilityLabel("\(expanded ? "Close" : "Options") \(title)")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
        }
        .foregroundStyle(isDark ? Color.white : Color(hex: "252A26"))
        .background {
            Capsule().fill(LinearGradient(colors: isDark
                ? (enabled ? [Color(hex: "424942"), Color(hex: "1C221E")] : [Color(hex: "303831"), Color(hex: "151C17")])
                : (enabled ? [.white, Color(hex: "EDEEE9")] : [Color(hex: "E8EAE4"), Color(hex: "DADDD5")]),
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(isDark ? 0.32 : 0.96), .black.opacity(0.13)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(enabled ? 0.14 : 0.09), radius: 4, x: 1, y: 3)
        .shadow(color: .white.opacity(isDark ? 0.08 : 0.55), radius: 3, x: -2, y: -2)
        .buttonStyle(QuietPressStyle())
    }
}
private struct MapRaisedCircle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .background(Circle().fill(LinearGradient(colors: dark ? [Color(hex: "424942"), Color(hex: "1B221D")] : [.white, Color(hex: "EAEEE7")], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.3 : 0.96), .black.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.26 : 0.16), radius: 6, x: 2, y: 4)
            .shadow(color: .white.opacity(dark ? 0.05 : 0.6), radius: 3, x: -2, y: -2)
    }
}
private struct MapFilterPanelSurface: ViewModifier {
    let beenTo: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder func body(content: Content) -> some View {
        if beenTo {
            if reduceTransparency { content.background(BeenPalette.base(scheme), in: RoundedRectangle(cornerRadius: 28)) }
            else if #available(iOS 26, *) { content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28)) }
            else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)) }
        } else { content.modifier(MapGlassPanel()) }
    }
}
private struct MapGlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .background((colorScheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.74)), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.28 : 0.88), .white.opacity(colorScheme == .dark ? 0.08 : 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 22, y: 10)
    }
}

private struct MapFrostedCapsule: ViewModifier {
    var focused = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Capsule().fill(colorScheme == .dark ? Color(hex: "252E2B") : Color(hex: "E9EEE9"))
                } else {
                    Capsule().fill(focused ? .regularMaterial : .ultraThinMaterial)
                        .overlay(Capsule().fill(.white.opacity(focused ? (colorScheme == .dark ? 0.06 : 0.24) : 0)))
                }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.5 : (colorScheme == .dark ? 0.13 : 0.22)), lineWidth: focused ? 1 : 0.7))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}

private struct MapDotGlass: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.7)), in: .circle)
        } else {
            content.background(.thinMaterial, in: Circle()).background(tint.opacity(0.3), in: Circle())
        }
    }
}

private struct MapDockedSearchSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 30)
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                // Attach interactive glass to the whole touchable panel, rather
                // than to a hit-testing-disabled decorative background.
                content.glassEffect(.regular.tint(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.08)).interactive(), in: shape)
            } else if reduceTransparency {
                content.background(shape.fill(colorScheme == .dark ? Color(hex: "252E2B") : Color(hex: "E9EEE9")))
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        }
        .background {
            // Extend the backing below the keyboard without changing content layout.
            shape.fill(.ultraThinMaterial).opacity(reduceTransparency ? 1 : 0.35)
                .ignoresSafeArea(.all, edges: .bottom).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.10), radius: 16, y: -3)
    }
}

// Drag updates stay inside this subtree instead of rebuilding the map each frame.
private struct MapSearchPanelContainer<Panel: View>: View {
    let availableHeight: CGFloat
    let viewportBottom: CGFloat
    let barHeight: CGFloat
    let onClose: () -> Void
    @ViewBuilder let panel: (AnyGesture<DragGesture.Value>) -> Panel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var keyboardTop: CGFloat?
    private func updateKeyboard(_ notification: Notification) {
        guard let rect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let frame = window.map { $0.convert(rect, from: $0.screen.coordinateSpace) } ?? rect
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardTop = frame.minY }
    }
    private var dismissGesture: AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragOffset = MapSearchPanelLayout.offset(drag: value.translation.height) }
            }
            .onEnded { value in
                if MapSearchPanelLayout.shouldDismiss(translation: value.translation.height, predicted: value.predictedEndTranslation.height) {
                    TrippyHaptics.selection()
                    onClose()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
                }
            })
    }
    var body: some View {
        let drag = dismissGesture
        GeometryReader { geometry in
            let height = MapSearchPanelLayout.height(available: availableHeight, barHeight: barHeight)
            let overlap = MapSearchPanelLayout.keyboardOverlap(panelBottom: viewportBottom,
                                                               keyboardTop: keyboardTop, panelHeight: height)
            VStack(spacing: 0) {
                Capsule().fill(AppPalette.secondaryInk.opacity(0.32)).frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity).frame(height: 26).contentShape(Rectangle())
                    .gesture(drag)
                    .accessibilityLabel("Close search by dragging")
                    .accessibilityAction(named: "Close", onClose)
                panel(drag).padding(.horizontal, 16).padding(.top, 4)
                    .padding(.bottom, max(overlap, geometry.safeAreaInsets.bottom) + 12)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.frame(height: height)
        }
        .frame(height: MapSearchPanelLayout.height(available: availableHeight, barHeight: barHeight))
        .background { Color.clear.contentShape(Rectangle()).gesture(drag) }
        .modifier(MapDockedSearchSurface())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification), perform: updateKeyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardTop = nil }
        }
        .offset(y: MapSearchPanelLayout.offset(drag: dragOffset))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// Shared map controls keep Apple cartography and landmark artwork intact.
private struct TrippyMapCanvas<Header: View>: View {
    let pins: [WorkspaceMapPin]
    let cityPins: [WorkspaceMapPin]
    let routes: [TripRouteLeg]
    @Binding var savedPlaces: [PersonalPlace]
    let destination: String
    let fallback: CLLocationCoordinate2D?
    let categories: Set<MapPlaceCategory>
    let placesBaseURL: String
    let placesAccessToken: String
    var onPlacesSettings: (() -> Void)? = nil
    let onCity: (String) -> Void
    var onCityLayer: ((MapLibraryFilter) -> Void)? = nil
    var cityCenters: [String: StoredPlaceCoordinate] = [:]
    var onPlanPin: ((WorkspaceMapPin) -> Void)? = nil
    var focusPlaceID: String? = nil
    var searchRequestID: UUID? = nil
    var onSearchRequestHandled: (() -> Void)? = nil
    var base: GuideBase? = nil
    var onNewTrip: (() -> Void)? = nil
    var onCreateNote: ((PersonalPlace, UUID?) -> Void)? = nil
    var noteChoices: [MapNoteChoice] = []
    var onAddToNote: ((PersonalPlace, UUID) -> Void)? = nil
    var tripChoices: [MapTripChoice] = []
    var socialSources: [ImportedSocialSource] = []
    var socialPlaces: [SocialPlaceMention] = []
    var travelNotes: [TravelNote] = []
    var onSaveTripPin: ((UUID, PersonalPlace) -> Void)? = nil
    var selectionKey: String = ""
    var schedulablePlaceIDs: Set<String> = []
    var planDayTitle: String = "Day 1"
    @ViewBuilder let header: () -> Header
    @AppStorage("trippy.native.mapTheme") private var theme = "Explore"
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var placeTypeSize
    @AppStorage("trippy.native.glassTint") private var glassTint = "auto"
    @AppStorage("trippy.native.map.locationEnabled") private var currentLocationEnabled = true
    @AppStorage("trippy.native.map.showApplePlaces") private var showApplePlaces = true
    @AppStorage("trippy.native.map.showTrips") private var showTrips = true
    @AppStorage("trippy.native.map.showSaves") private var showSaves = true
    @AppStorage("trippy.native.map.showPins") private var showPins = true
    @AppStorage("trippy.native.map.showVisited") private var showVisited = false
    @AppStorage("trippy.native.map.quickFilters") private var quickFilterStorage = ""
    @AppStorage("trippy.native.map.openNow") private var openNowOnly = false
    @AppStorage("trippy.native.map.filtersOpen") private var filtersOpen = false
    @ObservedObject private var hoursStore = OpeningHoursStore.shared
    @AppStorage("trippy.native.map.trip.showSuggestions") private var tripShowsSuggestions = true
    @AppStorage("trippy.native.map.been.outlines") private var beenOutlines = true
    @AppStorage("trippy.native.map.been.fill") private var beenFill = true
    @AppStorage("trippy.native.map.been.hatches") private var beenHatches = false
    @AppStorage("trippy.native.map.been.detailed") private var beenDetailed = false
    @AppStorage("trippy.native.map.been.innerCities") private var beenInnerCities = true
    @AppStorage("trippy.native.map.been.cityPins") private var beenCityPins = true
    @AppStorage("trippy.native.map.been.badges") private var beenBadges = true
    @AppStorage("trippy.native.map.been.zoomLabels") private var beenZoomLabels = true
    @AppStorage("trippy.native.visitedPlaces.v1") private var visitedStorage = "[]"
    @State private var visitedPlaces: [VisitedPlace] = []
    @AppStorage("trippy.native.map.showTraffic") private var showTraffic = false
    @AppStorage("trippy.native.map.realisticElevation") private var realisticElevation = true
    @AppStorage("trippy.native.map.showTransitStations") private var showTransitStations = true
    @AppStorage("trippy.native.map.nativePlaceCards") private var nativePlaceCards = true
    @AppStorage("trippy.native.map.showScale") private var showScale = false
    @AppStorage("trippy.native.map.lookAround") private var showLookAround = true
    @State private var nativeMapSelection: MapFeature?
    @State private var selectedNeighborhood: NeighborhoodPlace?
    @State private var visitedBoundaryLayers: [BeenBoundaryDetail: BeenBoundaryMapLayer] = [:]
    @State private var visitedCityLayers: [BeenBoundaryDetail: BeenBoundaryMapLayer] = [:]
    @AppStorage("trippy.native.map.hiddenTrips") private var hiddenTrips = ""
    @AppStorage("trippy.native.map.tripExtents") private var tripExtents = ""
    @AppStorage("trippy.native.map.hiddenPinCategories") private var hiddenPinCategories = ""
    @AppStorage("trippy.native.map.hiddenAppleCategories") private var hiddenAppleCategories = ""
    @State private var expandedMapSummaries = Set<String>()
    @State private var expandedMapCities = Set<String>()
    @State private var countryCityClusters: [MapCountryCityCluster] = []
    @State private var expandedMapFilter: String?
    @State private var expandedFilterTrip: UUID?
    @State private var pendingClusterPin: WorkspaceMapPin?
    @State private var selectedClusterPins: [WorkspaceMapPin] = []
    @State private var generalMapController = GeneralMapController()
    @State private var generalMarkers: [GeneralMapMarker] = []
    @State private var generalRefreshTask: Task<Void, Never>?
    @State private var lastGeneralInputKey = ""
    @State private var generalMarkerRevision = 0
    @State private var generalMembers: [String: WorkspaceMapPin] = [:]
    @State private var nativeCameraRequestID = UUID()
    @State private var generalCountryGeometries: [CountryGeometry] = []
    @State private var generalCountryShapes: CountryShapesOverlay?
    @AppStorage("trippy.native.map.been.fillMode") private var beenFillMode = CountryFillMode.visited.rawValue
    @State private var generalCityLayers: [BeenBoundaryDetail: [GeneralMapOverlay]] = [:]
    @State private var generalGeometryRevision = 0
    @State private var nativeCitySelection: MapRenderedMarker?
    @State private var pendingNativeCityInfo: MapRenderedMarker?
    @State private var cachedRenderedMarkers: [MapRenderedMarker] = []
    @State private var cachedStandaloneBeenCities: [VisitedPlace] = []
    @State private var markerGroups: [MapScreenCluster] = []
    @State private var labeledMarkerIDs: Set<String> = []
    @State private var markerViewport: CGSize = .zero
    @State private var hasFittedMap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleCamera: MapCamera?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapPlaceBoundaryLines: [GeoBoundaryLine] = []
    @State private var areaHighlightOpacity = 0.0
    @State private var directionsFallbackItem: MKMapItem?
    @State private var topControlsHeight: CGFloat = 110
    @State private var customPinRequest: MapPinIdentityRequest?
    @State private var showMapSearch = false
    @State private var appleSearchStatus: MapSearchProviderStatus = .idle
    @State private var googleSearchStatus: MapSearchProviderStatus = .idle
    @State private var query = ""
    @State private var searchResults: [PersonalPlace] = []
    @State private var searchFilter: MapSearchFilter = .all
    @State private var searching = false
    @State private var searchError: String?
    @State private var searchSourceNotice: String?
    @AppStorage("trippy.native.map.recentSearches") private var recentSearchStorage = ""
    @State private var selectedPin: WorkspaceMapPin?
    /// Community videos (TikTok + YouTube) that mention the open shop.
    @State private var placeVideos: [CommunityPlaceVideo] = []
    @State private var selectedSearchPlace: WorkspaceMapPin?
    @State private var focusedMapPinID: String?
    @State private var selectedPinCategory: MapPlaceCategory?
    @State private var celebrationEmoji: String?
    @State private var pendingPlacePanelAction: (() -> Void)?
    @State private var googlePlaceDetails: GooglePlaceDetails?
    @State private var photoViewerIndex: Int?
    @State private var placePanelDetent: PresentationDetent = .height(MapPanelFraming.placeHeight)
    @State private var resolvedGooglePlaceIDs: [String: String] = [:]
    @State private var loadingGoogleDetails = false
    @State private var googleDetailsError: String?
    @State private var appleMapItem: MKMapItem?
    @State private var appleCardItem: MKMapItem?
    @State private var kitPlaceID: String?
    @State private var pendingPlanPin: WorkspaceMapPin?
    @State private var renderedRoutes: [String: MKRoute] = [:]
    @State private var routeCache: [String: MKRoute] = [:]
    @State private var routing = false
    @State private var failedRoutes = 0
    @State private var directionsRoute: MKRoute?
    @State private var showDirections = false
    @State private var calculatingDirections = false
    @State private var directionsError: String?
    @State private var locationError: String?
    @State private var lastMapHapticZoomBand = -1
    @State private var centerWhenLocationArrives = false
    @State private var pendingDirectionsPin: WorkspaceMapPin?
    /// Directions mode: opened only from a place's Directions button; the map's chrome changes until it is closed.
    @StateObject private var directions = DirectionsModel()
    @State private var directionsActive = false
    @State private var directionsPicker: DirectionsPickerTarget?
    @StateObject private var locationService = CurrentLocationService()
    @FocusState private var searchFocused: Bool
    private var homeCategories: Set<MapPlaceCategory> {
        get { Set(MapPlaceCategory.allCases.filter { !hiddenPinCategories.split(separator: "|").contains(Substring($0.rawValue)) }) }
        nonmutating set { hiddenPinCategories = MapPlaceCategory.allCases.filter { !newValue.contains($0) }.map(\.rawValue).joined(separator: "|") }
    }
    private var effectiveCategories: Set<MapPlaceCategory> { destination.isEmpty ? homeCategories : categories }
    private var appleCategories: Set<AppleMapPlaceCategory> {
        Set(AppleMapPlaceCategory.allCases.filter { !hiddenAppleCategories.split(separator: "|").contains(Substring($0.rawValue)) })
    }
    private func tripIsVisible(_ id: UUID?) -> Bool {
        guard let id else { return true }
        return !hiddenTrips.split(separator: "|").contains(Substring(id.uuidString))
    }
    private var customPinCategories: [String] { Array(Set(pins.compactMap(\.customCategory))).sorted() }
    private func physicalPlaceGroups(_ values: [WorkspaceMapPin]) -> [[WorkspaceMapPin]] {
        let index = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return MapPlaceIdentity.groups(values.map {
            .init(id: $0.id, placeID: $0.placeID, googleID: $0.googlePlaceID, name: $0.name,
                  latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, layer: $0.layer)
        }).map { $0.compactMap { index[$0] } }
    }
    private var physicalPinGroups: [[WorkspaceMapPin]] { physicalPlaceGroups(visiblePins) }
    private var quickFilters: Set<MapQuickFilter> { MapQuickFilter.decode(quickFilterStorage) }
    /// Empty means everything; otherwise a pin shows when any chosen filter covers it.
    private func quickAllows(_ pin: WorkspaceMapPin) -> Bool {
        guard pin.layer != "city" else { return true }
        // "Open now" hides what is known to be closed; unknown hours stay (dimmed in a trip).
        if openNowOnly, openState(pin) == false { return false }
        let chosen = quickFilters
        return chosen.isEmpty || chosen.contains { $0.includes(pin) }
    }
    /// true open, false closed, nil unknown.
    private func openState(_ pin: WorkspaceMapPin) -> Bool? {
        guard let hours = pin.openingHours ?? hoursStore.hours[pin.id] else { return nil }
        return hours.isOpen()
    }
    private var hoursQueries: [OpeningHoursQuery] {
        // Only what's on screen (or near the trip), never every pin you own.
        let region = visibleRegion
        return pins.filter { pin in
            guard pin.layer != "city", pin.openingHours == nil else { return false }
            guard let region else { return !destination.isEmpty }
            return abs(pin.coordinate.latitude - region.center.latitude) < region.span.latitudeDelta * 0.6
                && abs(pin.coordinate.longitude - region.center.longitude) < region.span.longitudeDelta * 0.6
        }.prefix(120).map {
            OpeningHoursQuery(key: $0.id, name: $0.name, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                              googlePlaceID: $0.googlePlaceID)
        }
    }
    private func toggleQuick(_ filter: MapQuickFilter) {
        var chosen = quickFilters
        if chosen.contains(filter) { chosen.remove(filter) } else { chosen.insert(filter) }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            quickFilterStorage = MapQuickFilter.allCases.filter(chosen.contains).map(\.rawValue).joined(separator: "|")
        }
    }
    private var visiblePins: [WorkspaceMapPin] {
        pins.filter { pin in
            guard quickAllows(pin) else { return false }
            guard destination.isEmpty else {
                if pin.layer == "recommended" && !tripShowsSuggestions { return false }
                if (pin.layer == "saved" && !showSaves) || (pin.layer == "pin" && !showPins) { return false }
                return categories.contains(pin.category)
            }
            if let custom = pin.customCategory, hiddenPinCategories.split(separator: "|").contains(Substring(MarkGlyphCatalog.categoryKey(custom))) { return false }
            return MapLayerVisibility.includes(layer: pin.layer, showSaves: showSaves, showPins: showPins,
                showTrips: showTrips, categoryIncluded: homeCategories.contains(pin.category), tripIncluded: tripIsVisible(pin.tripID))
        }
    }
    private var visibleCityPins: [WorkspaceMapPin] {
        cityPins.filter { !destination.isEmpty || (showTrips && tripIsVisible($0.tripID)) }
    }
    private var mapMarkers: [WorkspaceMapPin] {
        var seen = Set<String>()
        return (visiblePins + visibleCityPins).filter { seen.insert($0.id).inserted }
    }
    private var markerFilterKey: String {
        "\(pointTaskID):\(quickFilterStorage):\(openNowOnly):\(hoursStore.revision):\(tripShowsSuggestions):\(showTrips):\(showSaves):\(showPins):\(hiddenTrips):\(hiddenPinCategories):\(categories.map(\.rawValue).sorted()):\(visitedStorage):\(beenCityPins):\(beenBadges)"
    }
    private var displayedSearchResults: [PersonalPlace] { searchResults.filter { searchFilter.includes($0) } }
    private var routeTaskID: String {
        routes.map { "\($0.id):\($0.from.latitude),\($0.from.longitude):\($0.to.latitude),\($0.to.longitude):\($0.walking)" }.joined(separator: "|")
    }
    private var pointTaskID: String {
        let places = pins.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude):\($0.city):\($0.layer):\($0.category.rawValue)" }
        let cities = cityPins.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }
        let centers = cityCenters.keys.sorted().map { key in
            "\(key):\(cityCenters[key]!.latitude):\(cityCenters[key]!.longitude):\(cityCenters[key]!.countryCode ?? "")"
        }
        return (places + cities + centers).joined(separator: "|")
    }
    private var poiCategories: [MKPointOfInterestCategory] {
        appleCategories.flatMap(\.categories)
    }
    private var quickPOICategories: [MKPointOfInterestCategory] { Array(Set(quickFilters.flatMap(\.appleCategories))) }
    private var mapStyle: MapStyle {
        let interests: PointOfInterestCategories
        if !showApplePlaces || openNowOnly { interests = .excludingAll }
        else if !quickFilters.isEmpty { interests = .including(quickPOICategories) }
        else if appleCategories.count == AppleMapPlaceCategory.allCases.count { interests = showTransitStations ? .all : .excluding([.publicTransport]) }
        else if appleCategories.contains(.other) {
            interests = .excluding(AppleMapPlaceCategory.allCases.filter { !appleCategories.contains($0) }.flatMap(\.categories) + (showTransitStations ? [] : [.publicTransport]))
        } else { interests = .including(poiCategories.filter { showTransitStations || $0 != .publicTransport }) }
        let elevation: MapStyle.Elevation = realisticElevation ? .realistic : .flat
        switch theme {
        case "Satellite": return .imagery(elevation: elevation)
        case "Hybrid": return .hybrid(elevation: elevation, pointsOfInterest: interests, showsTraffic: showTraffic)
        default: return .standard(elevation: elevation, emphasis: theme == "Quiet" ? .muted : .automatic, pointsOfInterest: interests, showsTraffic: showTraffic)
        }
    }
    private var visitedTaskKey: String {
        showVisited && (beenOutlines || beenFill || beenHatches)
            ? visitedPlaces.map { "\($0.id):\($0.latitude):\($0.longitude)" }.sorted().joined(separator: "|") + ":\(destination.isEmpty)"
            : "off"
    }
    private var visitedBoundaryDetail: BeenBoundaryDetail {
        let span = visibleRegion?.span.latitudeDelta ?? 16
        // Detailed borders resolve closer in; a continental view still has a vertex budget.
        return .at(span: beenDetailed ? span / 2 : span)
    }
    private var visitedCityTaskKey: String {
        guard showVisited && beenInnerCities && (beenOutlines || beenFill || beenHatches) && (visibleRegion?.span.latitudeDelta ?? 16) < 2 else { return "off" }
        return visitedTaskKey + ":viewport:" + visibleVisitedCities.map(\.id).sorted().joined(separator: "|")
    }
    private var visibleVisitedCities: [VisitedPlace] {
        guard let region = visibleRegion else { return [] }
        return mapVisitedPlaces.filter {
            let longitude = abs(($0.longitude - region.center.longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
            return abs($0.latitude - region.center.latitude) < region.span.latitudeDelta * 0.7 && longitude < region.span.longitudeDelta * 0.7
        }
    }
    private var mapVisitedPlaces: [VisitedPlace] {
        visitedPlaces.reduce(into: []) { result, place in
            if !result.contains(where: { MapCityGrouping.sameCity($0.name, countryCode: $0.countryCode, place.name, countryCode: place.countryCode) }) { result.append(place) }
        }
    }
    private func hasVisitedCity(_ city: String, countryCode: String?) -> Bool {
        visitedPlaces.contains { MapCityGrouping.sameCity(city, countryCode: countryCode, $0.name, countryCode: $0.countryCode) }
    }
    private func labelCountryCode(_ marker: MapRenderedMarker) -> String? {
        marker.countryCode ?? MapCityGrouping.countryCode(in: marker.city)
            ?? visitedPlaces.first(where: { MapCityGrouping.sameCity(marker.city, countryCode: marker.countryCode, $0.name, countryCode: $0.countryCode) })?.countryCode
    }
    private func beenCityID(_ place: VisitedPlace) -> String { "been-city:" + place.id }
    private var clusteredCityIDs: Set<String> { Set(countryCityClusters.flatMap(\.memberIDs)) }
    private var visibleCityRenderMarkers: [MapRenderedMarker] {
        let hidden = clusteredCityIDs
        return renderedMarkers.filter { !hidden.contains($0.id) }
    }
    private var unclusteredBeenCities: [VisitedPlace] {
        let hidden = clusteredCityIDs
        return standaloneBeenCities.filter { !hidden.contains(beenCityID($0)) }
    }
    private var standaloneBeenCities: [VisitedPlace] { cachedStandaloneBeenCities }
    private func makeStandaloneBeenCities(renderedMarkers sourceMarkers: [MapRenderedMarker]? = nil) -> [VisitedPlace] {
        // Inside a trip the map is about this trip; "been there" city badges stay on the home map.
        guard beenCityPins, destination.isEmpty else { return [] }
        let summaries = (sourceMarkers ?? renderedMarkers).filter(\.isCitySummary)
        return mapVisitedPlaces.filter { place in
            !summaries.contains { MapCityGrouping.sameCity($0.city, countryCode: $0.countryCode, place.name, countryCode: place.countryCode) }
        }
    }
    @MapContentBuilder private var explorationMapContent: some MapContent {
        if showVisited {
            if let layer = visitedBoundaryLayers[visitedBoundaryDetail] { BeenBoundaryMapContent(layer: layer, city: false, showFill: beenFill, showOutlines: beenOutlines, showTextures: beenHatches) }
            if beenInnerCities && (visibleRegion?.span.latitudeDelta ?? 16) < 2, let layer = visitedCityLayers[.local] { BeenBoundaryMapContent(layer: layer, city: true, showFill: beenFill, showOutlines: beenOutlines, showTextures: beenHatches) }
        }
            ForEach(unclusteredBeenCities) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    Button { onCity(place.name) } label: {
                        LightweightMapCityLabel(city: MapCityGrouping.name(place.name), countryCode: place.countryCode, count: 0, hasTrip: false, visited: beenBadges,
                                           span: visibleRegion?.span.latitudeDelta ?? 0).contentShape(Rectangle())
                    }.buttonStyle(QuietPressStyle())
                }.annotationTitles(.hidden)
            }
    }
    /// Country shapes come from the shared store (parallel, cached). Style changes
    /// only recolour the existing geometry; they never refetch or re-simplify.
    @MainActor private func loadVisitedBoundaries() async {
        guard showVisited && (beenOutlines || beenFill || beenHatches) else {
            visitedBoundaryLayers = [:]; generalCountryGeometries = []; generalCountryShapes = nil
            return
        }
        let byCountry = Dictionary(grouping: visitedPlaces.filter { $0.countryCode != nil }, by: { $0.countryCode!.uppercased() })
        let requests = byCountry.map { code, visits in CountryShapeStore.Request(code: code, latitude: visits[0].latitude, longitude: visits[0].longitude) }
        let result = await CountryShapeStore.shared.geometries(for: requests.sorted { $0.code < $1.code })
        guard !Task.isCancelled else { return }
        generalCountryGeometries = result.shapes
        rebuildGeneralCountryShapes()
        // The trip workspace's SwiftUI map still uses the older content layers.
        if !destination.isEmpty {
            var countryLines: [GeoBoundaryLine] = []
            for code in byCountry.keys.sorted() {
                guard let place = byCountry[code]?.first else { continue }
                let value = try? await GeoBoundaryRepository.shared.boundary(countryISO2: code, countryNames: [], placeNames: [], levelID: "country", center: .init(latitude: place.latitude, longitude: place.longitude), includeTexture: false)
                countryLines += (value ?? []).map { GeoBoundaryLine(id: "visited-country:\(code):" + $0.id, points: $0.points, style: $0.style) }
            }
            let prepared = await BeenBoundaryPreparation.shared.prepare(countryLines, city: false)
            guard !Task.isCancelled else { return }
            visitedBoundaryLayers = prepared.mapValues(BeenBoundaryMapLayer.init)
        }
    }
    private var boundaryTaskKey: String { visitedTaskKey + "|" + countryStyleKey }
    private var countryStyleKey: String { "\(beenFill):\(beenOutlines):\(beenHatches):\(beenFillMode):\(colorScheme == .dark)" }
    private func rebuildGeneralCountryShapes() {
        guard !generalCountryGeometries.isEmpty else { generalCountryShapes = nil; return }
        let stats = Dictionary(grouping: visitedPlaces.filter { $0.countryCode != nil }, by: { $0.countryCode!.uppercased() }).mapValues { visits in
            CountryVisitStats(code: visits[0].countryCode!.uppercased(), continent: WorldContinentCatalog.name(for: visits[0].countryCode),
                              cities: visits.filter { !$0.isCountry }.count, lastVisit: visits.compactMap(\.when).max() ?? visits.map(\.visitedAt).max() ?? .now)
        }
        generalCountryShapes = CountryShapesOverlay(geometries: generalCountryGeometries, stats: stats, style: CountryShapeStyle(
            fill: beenFill, outlines: beenOutlines, hatching: beenHatches, mode: CountryFillMode(rawValue: beenFillMode) ?? .visited, dark: colorScheme == .dark))
    }
    @MainActor private func loadVisitedCityBoundaries() async {
        guard showVisited && beenInnerCities && (beenOutlines || beenFill || beenHatches) && (visibleRegion?.span.latitudeDelta ?? 16) < 2 else {
            visitedCityLayers = [:]
            if !generalCityLayers.isEmpty { generalCityLayers = [:]; generalGeometryRevision += 1 }
            return
        }
        var cityLines: [GeoBoundaryLine] = []
        for place in visibleVisitedCities {
            guard let code = place.countryCode ?? MapCityGrouping.countryCode(in: place.name) else { continue }
            let value = try? await GeoBoundaryRepository.shared.boundary(countryISO2: code, countryNames: [], placeNames: [MapCityGrouping.name(place.name)], levelID: "city", center: .init(latitude: place.latitude, longitude: place.longitude), requireNameMatch: true)
            guard !Task.isCancelled else { return }
            cityLines += (value ?? []).map { GeoBoundaryLine(id: "visited-city:\(place.id):" + $0.id, points: $0.points, style: $0.style) }
        }
        let prepared = await BeenBoundaryPreparation.shared.prepare(cityLines, city: true)
        guard !Task.isCancelled else { return }
        visitedCityLayers = prepared.mapValues(BeenBoundaryMapLayer.init)
        generalCityLayers = Dictionary(uniqueKeysWithValues: prepared.map { detail, geometry in
            (detail, GeneralMapOverlay.prepare(geometry, city: true, detail: detail))
        })
        generalGeometryRevision += 1
    }
    private func pinIconTint(_ color: Color) -> Color {
        guard colorScheme == .dark else { return color }
        let source = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard source.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        let lift: CGFloat = 0.4
        return Color(red: red + (1 - red) * lift,
                     green: green + (1 - green) * lift,
                     blue: blue + (1 - blue) * lift,
                     opacity: alpha)
    }
    var body: some View {
        MapReader { mapProxy in
        Group {
        if destination.isEmpty {
            nativeGeneralMap.task {
                guard PlacePanelDemo.enabled, selectedPin == nil else { return }
                try? await Task.sleep(for: .seconds(2)); presentPlace(PlacePanelDemo.pin)
            }
        }
        else {
        Map(position: $position, interactionModes: .all, selection: nativePlaceCards ? $nativeMapSelection : .constant(nil)) {
            if currentLocationEnabled { UserAnnotation() }
            explorationMapContent
            ForEach(countryCityClusters) { cluster in
                Annotation(cluster.countryCode, coordinate: cluster.coordinate, anchor: .bottom) {
                    countryCityClusterView(cluster)
                }.annotationTitles(.hidden)
            }
            ForEach(mapPlaceBoundaryLines) { line in
                switch line.style {
                case .fill:
                    MapPolygon(coordinates: line.points.map(\.coordinate))
                        .foregroundStyle(Color(hex: "F28C28").opacity(0.045 + 0.04 * areaHighlightOpacity))
                case .texture:
                    MapPolyline(coordinates: line.points.map(\.coordinate))
                        .stroke(Color(hex: "F28C28").opacity(0.10 + 0.12 * areaHighlightOpacity), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                case .outline:
                    MapPolyline(coordinates: line.points.map(\.coordinate))
                        .stroke(Color(hex: "F28C28").opacity(0.8 + 0.2 * areaHighlightOpacity), style: StrokeStyle(lineWidth: 3 + 1.2 * areaHighlightOpacity, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(visibleTripExtents) { extent in
                MapPolygon(coordinates: extent.coordinates).foregroundStyle(AppPalette.brand.opacity(0.06))
                MapPolyline(coordinates: extent.coordinates + [extent.coordinates[0]])
                    .stroke(AppPalette.brand.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            ForEach(visibleCityRenderMarkers) { marker in
                Annotation(marker.isCitySummary ? MapCityLabelStyle.title(city: marker.city, countryCode: marker.countryCode ?? MapCityGrouping.countryCode(in: marker.city)) : (marker.members.first?.name ?? "Places"), coordinate: marker.coordinate,
                           anchor: marker.isCitySummary ? .bottom : .center) {
                    renderedMarkerView(marker)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))

                }.annotationTitles(.hidden)
            }
            if let place = selectedSearchPlace, place.searchKind != .area,
               physicalPlaceGroups(mapMarkers.filter { $0.layer != "city" } + [place]).first(where: { $0.contains { $0.id == place.id } })?.count == 1 {
                Annotation(place.name, coordinate: place.coordinate) { pinButton(place) }
                    .annotationTitles(.automatic)
            }
            if let base {
                Annotation(base.name, coordinate: base.coordinate, anchor: .bottom) { BasePin() }
                    .annotationTitles(.automatic)
            } else if destination.isEmpty, let home = HomeProfileStore.load(), home.city != nil, let point = home.coordinate {
                // Where you live, from onboarding or Settings.
                Annotation("Home", coordinate: point, anchor: .bottom) { HomePin() }
                    .annotationTitles(.automatic)
            }
            ForEach(routes) { leg in
                if let route = renderedRoutes[routeKey(leg)] {
                    if leg.id.contains(":base:") {
                        // The way from the stay to the day's first stop: lighter, dotted.
                        MapPolyline(route.polyline).stroke(routeColor(leg.day).opacity(0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [1, 8]))
                    } else {
                        MapPolyline(route.polyline).stroke(routeColor(leg.day).opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if let directionsRoute {
                MapPolyline(directionsRoute.polyline)
                    .stroke(Color(hex: "F28C28"), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        }
        }
        .mapStyle(mapStyle)
        .modifier(NativeMapCardsModifier(enabled: nativePlaceCards))
        .mapControls { if showScale { MapScaleView() } }
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { markerViewport = geometry.size; refreshMarkerGroups(proxy: mapProxy) }
                    .onChange(of: geometry.size) { _, size in markerViewport = size }
            }
        }
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
            handleMapTap(at: tap.location, proxy: mapProxy)
        })
        .overlay(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
                .overlay {
                    if colorScheme == .light { Color.white.opacity(0.08) }
                }
                .mask(LinearGradient(stops: [
                    .init(color: .white.opacity(0.94), location: 0),
                    .init(color: .white.opacity(0.78), location: 0.3),
                    .init(color: .white.opacity(0.34), location: 0.72),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(height: destination.isEmpty || showMapSearch ? 250 : 150).allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.52), location: 0.32),
                    .init(color: .white.opacity(0.94), location: 0.7),
                    .init(color: .white, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(height: 158)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            // MapKit moves stable annotations while dragging. Derived layout is
            // refreshed once onEnd, avoiding full MapContent rebuilds per frame.
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            guard !destination.isEmpty else { return }
            visibleRegion = context.region
            visibleCamera = context.camera
            refreshMarkerGroups(proxy: mapProxy, span: context.region.span.latitudeDelta)
        }
        .onChange(of: visitedStorage, initial: true) { _, value in visitedPlaces = VisitedPlace.decode(value) }
        .onChange(of: visitedPlaces) { _, _ in refreshMarkerGroups(proxy: mapProxy) }
        .task(id: boundaryTaskKey) {
            await loadVisitedBoundaries()
        }
        .task(id: visitedCityTaskKey) { await loadVisitedCityBoundaries() }
        .sheet(item: $selectedNeighborhood) { place in TrippyScreen { NeighborhoodDetailView(place: place) } }
        .onChange(of: markerAppearance) { _, appearance in
            if appearance != .smallDot { expandedMapSummaries = [] }
        }
        .onChange(of: markerFilterKey) { _, _ in refreshMarkerGroups(proxy: mapProxy) }
        .task(id: openNowOnly ? "hours:\(Int((visibleRegion?.center.latitude ?? 0) * 10)):\(Int((visibleRegion?.center.longitude ?? 0) * 10)):\(pins.count / 40)" : "hours:off") {
            // Look hours up only while "Open now" is on, for what's in view.
            guard openNowOnly else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // OpenStreetMap only: Google hours may not be stored or used to filter a map (EEA terms).
            await hoursStore.lookup(hoursQueries, google: false)
        }
        .task(id: destination.isEmpty ? "prefetch:off" : "prefetch:\(pointTaskID.hashValue)") {
            // Inside a trip, fetch free OpenStreetMap hours in the background so
            // "Open now" answers instantly later. Google is only used on demand.
            guard !destination.isEmpty else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let queries = pins.filter { $0.layer != "city" && $0.openingHours == nil }.prefix(150).map {
                OpeningHoursQuery(key: $0.id, name: $0.name, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, googlePlaceID: $0.googlePlaceID)
            }
            await hoursStore.lookup(Array(queries), google: false)
        }
        .onChange(of: selectedSearchPlace?.id) { _, _ in if destination.isEmpty { refreshGeneralMarkers() } }
        .onChange(of: markerViewport) { _, _ in refreshMarkerGroups(proxy: mapProxy) }
        .onChange(of: locationService.location?.timestamp) { _, _ in locationDidUpdate() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TrippyDirectionsDemo") && destination.isEmpty {
                try? await Task.sleep(for: .seconds(1.5))
                directions.from = .place(name: "Syntagma Square", coordinate: .init(latitude: 37.9755, longitude: 23.7348))
                directions.to = .place(name: "Acropolis Museum", coordinate: .init(latitude: 37.9685, longitude: 23.7285))
                directions.transport = .walk
                withAnimation { directionsActive = true }
            }
            #endif
        }
        .onChange(of: locationService.failureMessage) { _, message in
            guard let message else { return }
            if pendingDirectionsPin != nil {
                pendingDirectionsPin = nil
                directionsError = message
            } else {
                centerWhenLocationArrives = false
                locationError = message
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .modifier(DirectionsLayer(apply: directionsLayer))
        .safeAreaInset(edge: .top, spacing: 12) { mapTopChrome }
        .sheet(isPresented: Binding(get: { !selectedClusterPins.isEmpty }, set: { if !$0 { selectedClusterPins = [] } }), onDismiss: {
            if let pin = pendingClusterPin { pendingClusterPin = nil; focusPin(pin) }
        }) {
            NavigationStack {
                List(selectedClusterPins) { pin in
                    Button {
                        selectedClusterPins = []
                        if pin.layer == "city" { onCity(pin.name) }
                        else { pendingClusterPin = pin }
                    } label: {
                        Label(pin.layer == "city" ? (tripChoices.first { $0.id == pin.tripID }?.title ?? pin.name) : pin.name,
                              systemImage: pin.layer == "city" ? "suitcase.rolling" : pin.category.symbol)
                            .foregroundStyle(AppPalette.ink).frame(minHeight: 44)
                    }
                }.navigationTitle("Places at this location").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedClusterPins = [] } } }
            }.presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottomLeading) {
            if routing || failedRoutes > 0 {
                Label(routing ? "Updating routes…" : "\(failedRoutes) routes unavailable", systemImage: routing ? "arrow.trianglehead.2.clockwise.rotate.90" : "exclamationmark.circle")
                    .font(.caption).padding(12).background(.regularMaterial, in: Capsule()).padding(16).padding(.trailing, 72)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showMapSearch && !directionsActive {
                VStack(spacing: 12) {
                    Button(action: centerOnCurrentPosition) {
                        Image(systemName: currentLocationEnabled ? "location.fill" : "location.slash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(currentLocationEnabled ? AppPalette.ink : AppPalette.secondaryInk)
                            .frame(width: 50, height: 50)
                            .modifier(MapRaisedCircle())
                    }
                            .buttonStyle(QuietPressStyle())
                            .contentShape(Circle())
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.55).exclusively(before: TapGesture()).onEnded { action in
                                switch action {
                                case .first: disableCurrentLocation()
                                case .second: centerOnCurrentPosition()
                                }
                            })
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(currentLocationEnabled ? "Center on current location" : "Enable current location")
                            .accessibilityHint("Press and hold to turn off")
                            .accessibilityAction { centerOnCurrentPosition() }
                            .accessibilityAction(named: "Turn off location") { disableCurrentLocation() }
                    Button(action: fitMap) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(width: 38, height: 38)
                            .modifier(MapRaisedCircle())
                    }
                    .buttonStyle(QuietPressStyle())
                    .accessibilityLabel("Show all places")
                }
                .padding(.trailing, 16)
                .padding(.bottom, destination.isEmpty ? (!homeFiltersVisible ? 18 : (filtersOpen ? 262 : 76)) : 52)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: filtersOpen)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: homeFiltersVisible)
            }
        }
        .overlay(alignment: .bottom) {
            // Home map: filters and Open now appear once you're in a city, centred above the bar.
            if destination.isEmpty && !showMapSearch && homeFiltersVisible && !directionsActive {
                filterDrawer(layers: false, opensUp: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .frame(maxWidth: 720)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Draw expanded cards after the map controls so they cover those controls.
        .overlay(alignment: .topLeading) {
            if !showMapSearch, let panel = expandedMapFilter {
                mapFilterPanel(panel)
                    .frame(maxHeight: max(0, markerViewport.height - topControlsHeight - 24), alignment: .top)
                    .padding(.horizontal, 16)
                    .padding(.top, topControlsHeight + 12)
                    .frame(maxWidth: 752, alignment: .leading)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: showMapSearch) { _, presented in
            if !presented { searchFocused = false }
        }
        .task(id: routeTaskID) { await updateRoutes() }
        .task(id: retainedPlaceReferences.map { "\($0["placeID"] ?? ""):\($0["source"] ?? "")" }.joined(separator: "|")) {
            await retainGoogleReferences(retainedPlaceReferences)
        }
        .onChange(of: pointTaskID, initial: true) { old, new in
            if !hasFittedMap && (!pins.isEmpty || !cityPins.isEmpty) { fitMap(); hasFittedMap = true }
        }
        .onChange(of: searchRequestID, initial: true) { _, request in
            guard request != nil else { return }
            query = ""; openMapSearch(); onSearchRequestHandled?()
        }
        .onChange(of: selectionKey) { _, _ in fitMap() }
        .onChange(of: focusPlaceID, initial: true) { _, id in
            if let pin = pins.first(where: { $0.id == id }) {
                nativeCameraRequestID = UUID(); position = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            }
        }
        .sheet(item: $customPinRequest) { request in
            TrippyScreen { customPinIdentityEditor(request) }
        }
        .sheet(item: $selectedPin, onDismiss: {
            selectedSearchPlace = nil
            focusedMapPinID = nil
            mapPlaceBoundaryLines = []
            areaHighlightOpacity = 0
            googlePlaceDetails = nil
            resolvedGooglePlaceIDs = [:]
            googleDetailsError = nil
            query = ""
            searchResults = []
            if let pin = pendingPlanPin { pendingPlanPin = nil; onPlanPin?(pin) }
            if let action = pendingPlacePanelAction { pendingPlacePanelAction = nil; action() }
        }) { pin in selectedPlacePanel(pin) }
        .sheet(isPresented: $showDirections) {
            if let directionsRoute { RouteStepsSheet(route: directionsRoute) }
        }
        .alert("No route in the app", isPresented: Binding(
            get: { directionsError != nil },
            set: { if !$0 { directionsError = nil } }
        )) {
            if let item = directionsFallbackItem {
                Button("Open in Apple Maps") {
                    directionsFallbackItem = nil; directionsError = nil
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                }
            }
            Button("OK", role: .cancel) { directionsError = nil; directionsFallbackItem = nil }
        } message: {
            Text(directionsError ?? "Try again shortly.")
        }
        .alert("Location unavailable", isPresented: Binding(
            get: { locationError != nil },
            set: { if !$0 { locationError = nil } }
        )) {
            Button("OK", role: .cancel) { locationError = nil }
        } message: {
            Text(locationError ?? "Check location access and try again.")
        }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay { mapSearchOverlay.ignoresSafeArea(.all, edges: .bottom) }
        .toolbar(showMapSearch ? .hidden : .automatic, for: .tabBar, .navigationBar)
    }
    private var visibleTripExtents: [MapTripExtent] {
        guard destination.isEmpty, showTrips else { return [] }
        return tripChoices.compactMap { trip in
            guard tripIsVisible(trip.id), tripExtents.split(separator: "|").contains(Substring(trip.id.uuidString)) else { return nil }
            // This is the extent of known trip places, not an invented city boundary.
            let points = pins.filter { $0.tripID == trip.id }.map(\.coordinate)
            guard let first = points.first else { return nil }
            let lats = points.map(\.latitude)
            // Unwrap around the first point to keep date-line trips local.
            let lons = points.map { point -> Double in
                let delta = (point.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
                return first.longitude + delta
            }
            let bottom = max(-85, lats.min()! - 0.003), top = min(85, lats.max()! + 0.003)
            let left = lons.min()! - 0.003, right = lons.max()! + 0.003
            func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
                .init(latitude: lat, longitude: (lon + 540).truncatingRemainder(dividingBy: 360) - 180)
            }
            return MapTripExtent(id: trip.id, coordinates: [coordinate(bottom, left), coordinate(top, left), coordinate(top, right), coordinate(bottom, right)])
        }
    }
    private func membershipBinding(_ id: String, in storage: Binding<String>, inverted: Bool = false) -> Binding<Bool> {
        Binding(get: {
            let included = storage.wrappedValue.split(separator: "|").contains(Substring(id))
            return inverted ? !included : included
        }, set: { enabled in
            var values = Set(storage.wrappedValue.split(separator: "|").map(String.init))
            if enabled != inverted { values.insert(id) } else { values.remove(id) }
            storage.wrappedValue = values.sorted().joined(separator: "|")
        })
    }
    private var mapFilterCarousel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    filterPill("Maps", symbol: "apple.logo", enabled: $showApplePlaces, panel: "apple")
                    filterPill("Trips", symbol: "suitcase.rolling.fill", enabled: $showTrips, panel: "trips")
                    filterPill("Saves", symbol: "heart.fill", enabled: $showSaves)
                    filterPill("Pins", symbol: "mappin", enabled: $showPins, panel: "pins")
                    filterPill("Been to", symbol: "checkmark.seal.fill", enabled: $showVisited, panel: "been")
                }.padding(.top, 12).padding(.bottom, 4)
            }.scrollIndicators(.hidden).defaultScrollAnchor(.leading)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollClipDisabled()
                .padding(.horizontal, -20)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
    }
    private var activeFilterCount: Int { quickFilters.count + (openNowOnly ? 1 : 0) }
    /// A folded filter drawer: one small button, and when open a card of toggles in a
    /// two-row carousel. Inside a trip it also switches suggestions and your saves/pins.
    /// City zoom: shops, cafés and sights are what's on screen, so filtering them makes sense.
    private var homeFiltersVisible: Bool { (visibleRegion?.span.latitudeDelta ?? 1) < 0.3 }
    /// Open now, as its own pill beside Filters on the home map.
    private var openNowPill: some View {
        Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { openNowOnly.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: hoursStore.loading && openNowOnly ? "hourglass" : "clock.fill").font(.system(size: 12, weight: .bold))
                Text("Open now").font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
            }
            .foregroundStyle(openNowOnly ? .white : AppPalette.ink)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(openNowOnly ? Color(hex: "3F8F5F") : Sketch.card.opacity(0.97), in: Capsule())
            .overlay(Capsule().strokeBorder(openNowOnly ? .clear : Sketch.rule, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("Open now").accessibilityAddTraits(openNowOnly ? .isSelected : [])
    }
    private func filterDrawer(layers: Bool, opensUp: Bool) -> some View {
        VStack(alignment: opensUp ? .center : .leading, spacing: 8) {
            if opensUp && filtersOpen { filterCard(layers: layers).transition(.move(edge: .bottom).combined(with: .opacity)) }
            HStack(spacing: 8) {
                if opensUp { Spacer(minLength: 0) }
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { filtersOpen.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .bold))
                        Text("Filters").font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)").font(.custom("PlusJakartaSans-Bold", size: 11, relativeTo: .caption2)).monospacedDigit()
                                .foregroundStyle(AppPalette.inverseInk).frame(minWidth: 18, minHeight: 18)
                                .background(AppPalette.brand, in: Capsule())
                        }
                        Image(systemName: (filtersOpen == opensUp) ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    .foregroundStyle(AppPalette.ink)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Sketch.card.opacity(0.97), in: Capsule())
                    .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .frame(minHeight: 44).contentShape(Capsule())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel("Filters")
                .accessibilityValue(activeFilterCount > 0 ? "\(activeFilterCount) on" : "None on")
                .accessibilityHint(filtersOpen ? "Hides the filters" : "Shows the filters")
                if opensUp { openNowPill }
                // While folded, what's on stays visible as a short summary.
                if !opensUp && !filtersOpen && activeFilterCount > 0 {
                    Text(activeFilterSummary).font(.custom("PlusJakartaSans-SemiBold", size: 12, relativeTo: .caption))
                        .foregroundStyle(AppPalette.ink).lineLimit(1)
                        .padding(.horizontal, 10).frame(minHeight: 30)
                        .background(Sketch.card.opacity(0.9), in: Capsule())
                    Button { clearFilters() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                            .frame(width: 30, height: 30).background(Sketch.card.opacity(0.9), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Clear filters")
                }
                Spacer(minLength: 0)
            }
            if !opensUp && filtersOpen { filterCard(layers: layers).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
    private func quickChip(_ filter: MapQuickFilter, chosen: Set<MapQuickFilter>, counts: Bool) -> some View {
        MapQuickChip(title: filter.title, symbol: filter.symbol, tint: filter.tint, on: chosen.contains(filter),
                     count: counts ? pins.filter { $0.layer != "city" && filter.includes($0) }.count : nil) { toggleQuick(filter) }
    }
    private var activeFilterSummary: String {
        ((openNowOnly ? ["Open now"] : []) + MapQuickFilter.allCases.filter(quickFilters.contains).map(\.title)).joined(separator: " · ")
    }
    private func clearFilters() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { quickFilterStorage = ""; openNowOnly = false }
    }
    private func filterCard(layers: Bool) -> some View {
        let chosen = quickFilters
        return VStack(alignment: .leading, spacing: 10) {
            if layers {
                HStack(spacing: 6) {
                    MapQuickChip(title: "Suggestions", symbol: "sparkles", tint: Color(hex: "CE6651"), on: tripShowsSuggestions, layerSwitch: true) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { tripShowsSuggestions.toggle() }
                    }
                    MapQuickChip(title: "Saved", symbol: "heart.fill", tint: AppPalette.accent, on: showSaves, layerSwitch: true) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { showSaves.toggle() }
                    }
                    MapQuickChip(title: "Pins", symbol: "mappin", tint: Color(hex: "E17861"), on: showPins, layerSwitch: true) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { showPins.toggle() }
                    }
                }
            }
            // Two rows that scroll together: eating and drinking on top, things to see below.
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if layers {
                        MapQuickChip(title: "Open now", symbol: hoursStore.loading && openNowOnly ? "hourglass" : "clock.fill",
                                     tint: Color(hex: "3F8F5F"), on: openNowOnly,
                                     count: openNowOnly ? pins.filter { $0.layer != "city" && openState($0) == true }.count : nil) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { openNowOnly.toggle() }
                        }
                        }
                        ForEach([MapQuickFilter.food, .coffee, .bars, .clubs, .brunch, .streetFood, .vegan, .markets]) { quickChip($0, chosen: chosen, counts: layers) }
                    }
                    HStack(spacing: 6) {
                        ForEach([MapQuickFilter.sights, .museums, .parks, .beaches, .shopping, .stay, .transit]) { quickChip($0, chosen: chosen, counts: layers) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .padding(.horizontal, -12)
            HStack {
                Spacer(minLength: 6)
                if activeFilterCount > 0 || !tripShowsSuggestions || !showSaves || !showPins {
                    Button("Reset") {
                        clearFilters()
                        if layers { tripShowsSuggestions = true; showSaves = true; showPins = true }
                    }
                    .font(.custom("PlusJakartaSans-Bold", size: 13, relativeTo: .footnote)).foregroundStyle(AppPalette.brand)
                    .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
        .background(Sketch.card.opacity(0.97), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
    }
    private func filterPill(_ title: String, symbol: String, enabled: Binding<Bool>, panel: String? = nil) -> some View {
        MapFilterPill(title: title, symbol: symbol, enabled: enabled.wrappedValue,
                      expandable: panel != nil, expanded: expandedMapFilter == panel,
                      toggle: { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { enabled.wrappedValue.toggle() } },
                      expand: { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expandedMapFilter = expandedMapFilter == panel ? nil : panel } })
    }
    private func mapFilterPanel(_ panel: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(panel == "trips" ? "These are your trips" : panel == "apple" ? "Map settings" : panel == "been" ? "Been to" : "Your pins",
                    systemImage: panel == "been" ? "globe.europe.africa.fill" : panel == "apple" ? "apple.logo" : panel == "trips" ? "airplane" : "mappin")
                    .foregroundStyle(panel == "been" ? BeenPalette.accent(colorScheme) : AppPalette.ink)
                    .font(.custom("PlusJakartaSans-ExtraBold", size: 23, relativeTo: .title2)).tracking(-0.5)
                Spacer()
                Button { withAnimation(reduceMotion ? nil : .snappy) { expandedMapFilter = nil } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel("Close filters")
            }
            if panel == "apple" {
                Toggle("Places on map", isOn: $showApplePlaces)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 15))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(.white.opacity(darkMode ? 0.04 : 0.25), in: RoundedRectangle(cornerRadius: 18))
            }
            ScrollView {
                if panel == "trips" {
                    VStack(spacing: 8) {
                        if tripChoices.isEmpty { Text("Your trips will appear here.").font(.subheadline) }
                        ForEach(tripChoices) { trip in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Button {
                                        withAnimation(reduceMotion ? nil : .snappy) { expandedFilterTrip = expandedFilterTrip == trip.id ? nil : trip.id }
                                    } label: {
                                        HStack {
                                            MarkGlyphView(appearance: trip.appearance, fallback: "suitcase.rolling", tint: AppPalette.ink, size: 18)
                                            Text(trip.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            Spacer()
                                            Image(systemName: expandedFilterTrip == trip.id ? "chevron.up" : "chevron.down").font(.caption)
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Trip options for \(trip.title)")
                                    Toggle("Show \(trip.title)", isOn: membershipBinding(trip.id.uuidString, in: $hiddenTrips, inverted: true))
                                        .labelsHidden().disabled(!showTrips)
                                }
                                if expandedFilterTrip == trip.id {
                                    Toggle("Trip area", isOn: membershipBinding(trip.id.uuidString, in: $tripExtents))
                                        .font(.subheadline).disabled(!showTrips || !tripIsVisible(trip.id) || !pins.contains { $0.tripID == trip.id })
                                    Text("Outline around the places in this trip.")
                                        .font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                    Button("Focus on trip", systemImage: "arrow.up.left.and.arrow.down.right") {
                                        showTrips = true
                                        membershipBinding(trip.id.uuidString, in: $hiddenTrips, inverted: true).wrappedValue = true
                                        zoomToMarkers(pins.filter { $0.tripID == trip.id } + cityPins.filter { $0.tripID == trip.id })
                                    }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                                }
                            }.padding(10).background(AppPalette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                        }
                        Toggle("All trip areas", isOn: Binding(get: {
                            !tripChoices.isEmpty && tripChoices.allSatisfy { tripExtents.split(separator: "|").contains(Substring($0.id.uuidString)) }
                        }, set: { tripExtents = $0 ? tripChoices.map { $0.id.uuidString }.joined(separator: "|") : "" }))
                            .font(.subheadline).disabled(tripChoices.isEmpty || !showTrips)
                    }
                } else if panel == "been" {
                    BeenMapFilterOptions(countryLayer: $showVisited, cities: $beenCityPins, badges: $beenBadges,
                        zoomLabels: $beenZoomLabels,
                        outlines: $beenOutlines, fill: $beenFill, hatching: $beenHatches,
                        detailed: $beenDetailed, innerCities: $beenInnerCities)
                } else {
                    let storage = panel == "apple" ? $hiddenAppleCategories : $hiddenPinCategories
                    let enabled = panel == "apple" ? showApplePlaces : showPins
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Place types").font(.custom("PlusJakartaSans-Bold", size: 13))
                            .foregroundStyle(AppPalette.secondaryInk).padding(.bottom, 8)
                        if panel == "apple" {
                            PillFlowLayout(spacing: 10) {
                                ForEach(AppleMapPlaceCategory.allCases) { category in
                                    categoryFilterPill(category.rawValue, symbol: category.symbol,
                                        enabled: membershipBinding(category.rawValue, in: storage, inverted: true))
                                }
                            }.padding(.horizontal, 4).padding(.vertical, 8).disabled(!enabled)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Map appearance").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.secondaryInk)
                                mapThemePicker
                                categoryFilterPill("Traffic", symbol: "car.2.fill", enabled: $showTraffic)
                                categoryFilterPill("3D / elevation", symbol: "mountain.2", enabled: $realisticElevation)
                                categoryFilterPill("Transit stations", symbol: "tram.fill", enabled: $showTransitStations)
                                categoryFilterPill("Apple Maps cards", symbol: "rectangle.on.rectangle", enabled: $nativePlaceCards)
                                categoryFilterPill("Map scale", symbol: "ruler", enabled: $showScale)
                                categoryFilterPill("Look Around", symbol: "binoculars", enabled: $showLookAround)
                            }.padding(.top, 24)
                        } else {
                            PillFlowLayout(spacing: 10) {
                                ForEach(MapPlaceCategory.allCases) { category in
                                    categoryFilterPill(category.rawValue, symbol: category.symbol,
                                        enabled: membershipBinding(category.rawValue, in: storage, inverted: true))
                                }
                                ForEach(customPinCategories, id: \.self) { category in
                                    categoryFilterPill(category, symbol: "tag.fill",
                                        enabled: membershipBinding(MarkGlyphCatalog.categoryKey(category), in: storage, inverted: true))
                                }
                            }.padding(.horizontal, 4).padding(.vertical, 8).disabled(!enabled)
                        }
                    }
                }
            }.contentMargins(.vertical, 8, for: .scrollContent)
                .frame(maxHeight: max(100, min(440, markerViewport.height - topControlsHeight - (panel == "apple" ? 170 : 110))))
        }
        .tint(Color(hex: "64A87B")).foregroundStyle(AppPalette.ink).padding(22)
        .modifier(MapFilterPanelSurface(beenTo: panel == "been"))
    }
    private var nativePOIFilter: MKPointOfInterestFilter {
        if !showApplePlaces || openNowOnly { return .excludingAll }
        if !quickFilters.isEmpty { return .init(including: quickPOICategories) }
        if appleCategories.count == AppleMapPlaceCategory.allCases.count {
            return showTransitStations ? .includingAll : .init(excluding: [.publicTransport])
        }
        if appleCategories.contains(.other) {
            return .init(excluding: AppleMapPlaceCategory.allCases.filter { !appleCategories.contains($0) }.flatMap(\.categories) + (showTransitStations ? [] : [.publicTransport]))
        }
        return .init(including: poiCategories.filter { showTransitStations || $0 != .publicTransport })
    }
    private var nativeGeneralMap: some View {
        GeneralNativeMap(controller: generalMapController, markers: GeneralMapDebugFixture.markers ?? generalMarkers, markerRevision: generalMarkerRevision,
            position: position, cameraRequestID: nativeCameraRequestID,
            countryShapes: generalCountryShapes, cityLayers: generalCityLayers, geometryRevision: generalGeometryRevision,
            showVisited: showVisited, outlines: beenOutlines, fill: beenFill, hatches: beenHatches, detailed: beenDetailed, innerCities: beenInnerCities,
            showVisitedBadges: beenBadges, showVisitedCityLabels: beenZoomLabels,
            focusLines: mapPlaceBoundaryLines, extents: visibleTripExtents.map(\.coordinates), directions: directionsRoute?.polyline,
            extraOverlayKey: mapPlaceBoundaryLines.map { $0.id + ":" + String($0.points.count) }.joined(separator: "|") + tripExtents + ":" + String(directionsRoute?.distance ?? 0),
            theme: theme, poiFilter: nativePOIFilter,
            configurationKey: "\(theme):\(showApplePlaces):\(hiddenAppleCategories):\(showTransitStations):\(showTraffic):\(realisticElevation):\(colorScheme):\(nativePlaceCards)",
            traffic: showTraffic, elevation: realisticElevation, nativeCards: nativePlaceCards,
            showLocation: currentLocationEnabled, showScale: showScale, dark: colorScheme == .dark, reduceMotion: reduceMotion,
            onFirstRender: { NotificationCenter.default.post(name: .trippyInitialGeneralMapDidRender, object: nil) },
            onSelection: selectGeneralMarkers, onApplePlace: { item, isTerritory in
                TrippyHaptics.selection()
                let boundaryLevel = isTerritory ? (item.placemark.locality == nil ? "region" : "city") : nil
                let place = PersonalPlace(id: "apple:" + (item.name ?? "place") + ":" + String(item.placemark.coordinate.latitude),
                    name: item.name ?? "Place", city: item.placemark.locality ?? "", address: item.placemark.title ?? "",
                    latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude,
                    category: MapPlaceCategory.classify(item.pointOfInterestCategory?.rawValue ?? item.name ?? ""),
                    searchKind: isTerritory ? .area : .place, boundaryCountryCode: item.placemark.isoCountryCode,
                    boundaryLevel: boundaryLevel,
                    phoneNumber: item.phoneNumber, websiteURL: item.url?.absoluteString)
                selectSearchResult(place)
            }, onCameraEnd: { region, camera in
                visibleRegion = region; visibleCamera = camera
                let span = region.span.latitudeDelta
                let zoomBand = span < 0.12 ? 0 : span < 2.4 ? 1 : 2
                if lastMapHapticZoomBand >= 0 && lastMapHapticZoomBand != zoomBand { TrippyHaptics.selection() }
                lastMapHapticZoomBand = zoomBand
            })
        .sheet(item: $nativeCitySelection, onDismiss: {
            guard let marker = pendingNativeCityInfo else { return }
            pendingNativeCityInfo = nil
            let pin = WorkspaceMapPin(id: "map-city:" + MapCityGrouping.key(marker.city), name: marker.city,
                coordinate: marker.coordinate, layer: "search", category: .other, city: marker.city,
                boundaryCountryCode: marker.countryCode)
            focusPin(pin)
        }) { marker in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    if let code = marker.countryCode { Text(MarkGlyphCatalog.flag(code)).font(.title2) }
                    Text(marker.city).font(.custom("PlusJakartaSans-Bold", size: 25)).tracking(-0.4)
                    Spacer()
                }
                mapSummaryView(marker, showsCityLabel: false, forceExpanded: true)
                HStack(spacing: 10) {
                    Button {
                        pendingNativeCityInfo = marker
                        nativeCitySelection = nil
                    } label: {
                        Label("Place info", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 42)
                            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.045), in: Capsule())
                    }.buttonStyle(QuietPressStyle())
                    if marker.members.isEmpty {
                        Button { nativeCitySelection = nil; onCity(marker.city) } label: {
                            Label("Open city", systemImage: "map")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 42)
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.045), in: Capsule())
                        }.buttonStyle(QuietPressStyle())
                    }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .presentationDetents([.height(230), .medium]).presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
    }
    private func refreshGeneralMarkers() {
        generalRefreshTask?.cancel()
        generalRefreshTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            let key = markerFilterKey + ":" + (selectedSearchPlace?.id ?? "")
            guard key != lastGeneralInputKey else { return }
            lastGeneralInputKey = key
            rebuildGeneralMarkers()
        }
    }
    private func rebuildGeneralMarkers() {
        TrippyPerformance.mark("filters.begin")
        defer { TrippyPerformance.mark("filters.end") }
        let source = mapMarkers
        let points = physicalPlaceGroups(source.filter { $0.layer != "city" })
        let anchors = makeCityAnchors(from: source)
        let tripsByCity = Dictionary(grouping: source.filter { $0.layer == "city" }, by: { MapCityGrouping.key($0.name) })
        let pointsByCity = Dictionary(grouping: points, by: { MapCityGrouping.key($0[0].city) })
        var result: [GeneralMapMarker] = []
        var memberLookup = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for anchor in anchors {
            let key = MapCityGrouping.key(anchor.city)
            let tripMembers = tripsByCity[key] ?? []
            let cityPoints = pointsByCity[key] ?? []
            result.append(.init(id: anchor.id, latitude: anchor.coordinate.latitude, longitude: anchor.coordinate.longitude,
                city: MapCityGrouping.name(anchor.city), countryCode: anchor.countryCode, visited: hasVisitedCity(anchor.city, countryCode: anchor.countryCode),
                isCity: true, symbol: "airplane", emoji: nil,
                baseMemberIDs: tripMembers.map(\.id), placeMemberIDs: cityPoints.flatMap { $0.map(\.id) },
                tripIDs: Set(tripMembers.compactMap { $0.tripID?.uuidString }),
                pinIDs: Set(cityPoints.filter { $0[0].layer == "pin" }.map { $0[0].id }),
                saveIDs: Set(cityPoints.filter { $0[0].layer == "saved" }.map { $0[0].id })))
        }
        for place in mapVisitedPlaces where beenCityPins {
            guard !anchors.contains(where: { MapCityGrouping.sameCity($0.city, countryCode: $0.countryCode, place.name, countryCode: place.countryCode) }) else { continue }
            result.append(.init(id: beenCityID(place), latitude: place.latitude, longitude: place.longitude,
                city: MapCityGrouping.name(place.name), countryCode: place.countryCode, visited: true,
                isCity: true, symbol: "checkmark.seal.fill", emoji: nil, baseMemberIDs: [], placeMemberIDs: [], tripIDs: [], pinIDs: [], saveIDs: []))
        }
        for group in points {
            let first = group[0]
            result.append(.init(id: first.id, latitude: first.coordinate.latitude, longitude: first.coordinate.longitude,
                city: MapCityGrouping.name(first.city), name: first.name, countryCode: first.boundaryCountryCode ?? anchors.first(where: { MapCityGrouping.key($0.city) == MapCityGrouping.key(first.city) })?.countryCode,
                visited: false, isCity: false, symbol: first.appearance?.kind == "icon" ? (first.appearance?.glyph ?? "mappin") : first.layer == "saved" ? "heart.fill" : "mappin",
                emoji: first.appearance.flatMap { $0.kind == "icon" ? nil : $0.glyph },
                baseMemberIDs: group.map(\.id), placeMemberIDs: [], tripIDs: [], pinIDs: first.layer == "pin" ? [first.id] : [], saveIDs: first.layer == "saved" ? [first.id] : []))
        }
        if let search = selectedSearchPlace, memberLookup[search.id] == nil {
            memberLookup[search.id] = search
            result.append(.init(id: search.id, latitude: search.coordinate.latitude, longitude: search.coordinate.longitude,
                city: MapCityGrouping.name(search.city), name: search.name, countryCode: search.boundaryCountryCode, visited: false, isCity: false,
                symbol: "mappin", emoji: nil, baseMemberIDs: [search.id], placeMemberIDs: [], tripIDs: [], pinIDs: [], saveIDs: []))
        }
        if result != generalMarkers { generalMarkers = result; generalMembers = memberLookup; generalMarkerRevision += 1 }
        else { generalMembers = memberLookup }
    }
    private func selectGeneralMarkers(_ ids: [String], local: Bool) {
        let selected = generalMarkers.filter { ids.contains($0.id) }
        guard let first = selected.first else { return }
        var seen = Set<String>()
        let members = selected.flatMap { $0.members(local: local) }.filter { seen.insert($0).inserted }.compactMap { generalMembers[$0] }
        if selected.count == 1 && !first.isCity, let pin = members.first { focusPin(pin); return }
        TrippyHaptics.selection()
        if selected.count == 1 && first.isCity {
            focusPin(WorkspaceMapPin(id: "map-city:" + MapCityGrouping.key(first.city), name: first.city,
                coordinate: first.coordinate, layer: "search", category: .other, city: first.city,
                boundaryCountryCode: first.countryCode))
            return
        }
        nativeCitySelection = MapRenderedMarker(id: first.id, members: members, coordinate: first.coordinate,
            city: first.city, countryCode: first.countryCode, isCitySummary: true)
    }
    /// What the traveler already has in a city, for the city panel.
    private func cityHoldings(_ pin: WorkspaceMapPin) -> (trips: Int, pins: Int, saves: Int, visited: VisitedPlace?) {
        let key = MapCityGrouping.key(pin.city.nonEmpty ?? pin.name)
        let markers = generalMarkers.filter { $0.isCity && MapCityGrouping.key($0.city) == key }
        let visit = visitedPlaces.first { MapCityGrouping.key(MapCityGrouping.name($0.name)) == key }
        return (Set(markers.flatMap(\.tripIDs)).count, Set(markers.flatMap(\.pinIDs)).count, Set(markers.flatMap(\.saveIDs)).count, visit)
    }
    private var markerAppearance: MapMarkerAppearance {
        .at(span: visibleRegion?.span.latitudeDelta ?? 0)
    }
    private var cityAnchors: [MapCityAnchor] { makeCityAnchors(from: mapMarkers) }
    private func makeCityAnchors(from markers: [WorkspaceMapPin]) -> [MapCityAnchor] {
        guard destination.isEmpty else { return [] }
        let buckets = Dictionary(grouping: markers.filter { !($0.city.isEmpty ? $0.name : $0.city).isEmpty }) {
            MapCityGrouping.key($0.layer == "city" ? $0.name : $0.city)
        }
        return buckets.keys.sorted().compactMap { key in
            guard !key.isEmpty, let members = buckets[key], let first = members.first else { return nil }
            let city = MapCityGrouping.name(cityPins.first { MapCityGrouping.key($0.name) == key }?.name
                ?? (first.layer == "city" ? first.name : first.city))
            let cachedCenter = cityCenters[city] ?? cityCenters.keys.sorted().first { MapCityGrouping.key($0) == key }.flatMap { cityCenters[$0] }
            let coordinate = cachedCenter?.coordinate
                ?? cityPins.first { MapCityGrouping.key($0.name) == key }?.coordinate
                ?? MapClusterAnchor.center(members.map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            guard let coordinate else { return nil }
            let countryCode = cachedCenter?.countryCode
                ?? members.compactMap(\.boundaryCountryCode).first
                ?? members.compactMap { MapCityGrouping.countryCode(in: $0.city) }.first
            return MapCityAnchor(id: "city-anchor:\(key)", city: city, coordinate: coordinate, countryCode: countryCode)
        }
    }
    private var renderedMarkers: [MapRenderedMarker] { cachedRenderedMarkers }
    private func makeRenderedMarkers(groups: [MapScreenCluster]? = nil, span: Double? = nil) -> [MapRenderedMarker] {
        let markers = mapMarkers
        let physical = physicalPinGroups
        let activeGroups = groups ?? markerGroups
        let activeSpan = span ?? visibleRegion?.span.latitudeDelta ?? 0
        let represented = Dictionary(physical.map { ($0[0].id, $0) }, uniquingKeysWith: { first, _ in first })
        let cities = Dictionary(markers.map { ($0.id, $0.layer == "city" ? $0.name : $0.city) }, uniquingKeysWith: { first, _ in first })
        var consumed = Set<String>()
        let compactCities = activeSpan >= MapCityFlagStyle.minimumSpan
        let combineCityMarkers = activeSpan >= 0.12
        var result: [MapRenderedMarker] = cityAnchors.compactMap { anchor in
            let attachedPoints = combineCityMarkers
                ? MapCityGrouping.attachedIDs(city: anchor.city, anchorID: anchor.id, groups: activeGroups, cities: cities)
                : Set<String>()
            let attached = Set(attachedPoints.flatMap { represented[$0]?.map(\.id) ?? [$0] })
            let members = markers.filter {
                (($0.layer == "city" || combineCityMarkers) && MapCityGrouping.key($0.layer == "city" ? $0.name : $0.city) == MapCityGrouping.key(anchor.city)) || attached.contains($0.id)
            }
            guard !members.isEmpty else { return nil }
            consumed.formUnion(members.map(\.id))
            return MapRenderedMarker(id: anchor.id, members: members, coordinate: anchor.coordinate, city: anchor.city, countryCode: anchor.countryCode, isCitySummary: true)
        }
        if compactCities {
            result = result.map { city in
                var compact = city
                compact.isCompactCity = true
                return compact
            }
        }
        for cluster in activeGroups {
            let representatives = cluster.memberIDs.compactMap { represented[$0]?.first }
                .filter { !consumed.contains($0.id) }
            let members = cluster.memberIDs.flatMap { represented[$0] ?? [] }.filter { !consumed.contains($0.id) }
            guard !members.isEmpty, let anchor = MapClusterAnchor.center(representatives.map {
                .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }) else { continue }
            consumed.formUnion(members.map(\.id))
            result.append(MapRenderedMarker(id: representatives[0].id, members: members,
                coordinate: representatives.count == 1 ? representatives[0].coordinate : .init(latitude: anchor.latitude, longitude: anchor.longitude)))
        }
        result += physical.filter { !consumed.contains($0[0].id) }.map {
            MapRenderedMarker(id: $0[0].id, members: $0, coordinate: $0[0].coordinate)
        }
        return result
    }
    private func refreshMarkerGroups(proxy: MapProxy, span: Double? = nil) {
        if destination.isEmpty { refreshGeneralMarkers(); return }
        let latitudeSpan = span ?? visibleRegion?.span.latitudeDelta ?? 0
        let appearance = MapMarkerAppearance.at(span: latitudeSpan)
        let compactCities = latitudeSpan >= MapCityFlagStyle.minimumSpan
        var points = physicalPinGroups.compactMap { $0.first }.compactMap { pin -> MapScreenPoint? in
            guard let point = proxy.convert(pin.coordinate, to: .local), point.x.isFinite, point.y.isFinite,
                  abs(point.x) < 1e9, abs(point.y) < 1e9 else { return nil }
            let stored = pin.layer == "pin" || pin.layer == "saved"
            if !destination.isEmpty {
                // Trip map: markers are small discs at every zoom; only true overlaps merge.
                return MapScreenPoint(id: pin.id, point: point, radius: pin.layer == "planned" ? 13 : (stored ? 12 : 10))
            }
            let labelRadius = max(20, min(63, CGFloat(pin.name.count) * 3.5 + 7))
            return MapScreenPoint(id: pin.id, point: point, radius: stored && appearance != .smallDot ? labelRadius : (appearance == .pill ? 0 : appearance.collisionRadius))
        }
        points += cityAnchors.compactMap { anchor -> MapScreenPoint? in
            guard let point = proxy.convert(anchor.coordinate, to: .local), point.x.isFinite, point.y.isFinite,
                  abs(point.x) < 1e9, abs(point.y) < 1e9 else { return nil }
            return MapScreenPoint(id: anchor.id, point: point, radius: appearance == .pill ? 0 : (compactCities ? 22 : 40))
        }
        let next = MapScreenClustering.groups(points, clusterRadius: destination.isEmpty ? (appearance == .smallDot ? 24 : 40) : 16)
        let nextRendered = makeRenderedMarkers(groups: next, span: latitudeSpan)
        let nextLabels = destination.isEmpty ? [] : tripLabelIDs(nextRendered, proxy: proxy, span: latitudeSpan)
        let nextStandalone = makeStandaloneBeenCities(renderedMarkers: nextRendered)
        let nextCountryClusters = makeCountryCityClusters(proxy: proxy, span: latitudeSpan, rendered: nextRendered, standalone: nextStandalone)
        let membershipChanged = next.map(\.memberIDs) != markerGroups.map(\.memberIDs)
            || nextCountryClusters.map(\.memberIDs) != countryCityClusters.map(\.memberIDs)
        let publish = {
            markerGroups = next
            cachedRenderedMarkers = nextRendered
            labeledMarkerIDs = nextLabels
            cachedStandaloneBeenCities = nextStandalone
            countryCityClusters = nextCountryClusters
        }
        if membershipChanged && !reduceMotion { withAnimation(.snappy(duration: 0.24), publish) }
        else { var transaction = Transaction(); transaction.disablesAnimations = true; withTransaction(transaction, publish) }
    }
    private func makeCountryCityClusters(proxy: MapProxy, span: Double, rendered: [MapRenderedMarker], standalone: [VisitedPlace]) -> [MapCountryCityCluster] {
        let summaries = rendered.filter(\.isCitySummary)
        let size = min(14, MapCityLabelStyle.size(span: span))
        var footprints: [MapCityScreenFootprint] = []
        for marker in summaries {
            guard let point = proxy.convert(marker.coordinate, to: .local) else { continue }
            let code = labelCountryCode(marker) ?? ""
            let title = MapCityGrouping.name(marker.city)
            let width = CGFloat(title.count) * size * 0.61 + 44
            footprints.append(.init(id: marker.id, countryCode: code.uppercased(), point: point, size: .init(width: width, height: 30), latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude))
        }
        for place in standalone {
            guard let point = proxy.convert(place.coordinate, to: .local) else { continue }
            let code = place.countryCode ?? ""
            let title = MapCityGrouping.name(place.name)
            let width = CGFloat(title.count) * size * 0.61 + 28
            footprints.append(.init(id: beenCityID(place), countryCode: code.uppercased(), point: point, size: .init(width: width, height: 34), latitude: place.latitude, longitude: place.longitude))
        }
        return MapCountryCityClustering.groups(footprints)
    }
    private func countryCityClusterView(_ cluster: MapCountryCityCluster) -> some View {
        return Text(cluster.memberIDs.count.formatted())
            .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color(hex: "7462C6")))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: Color(hex: "7462C6").opacity(0.25), radius: 3, y: 2)
            .accessibilityLabel("\(cluster.memberIDs.count) merged city pins")
            .transition(.scale(scale: 0.72).combined(with: .opacity))
    }
    private func summaryPlaceGroups(_ marker: MapRenderedMarker, layer: MapMarkerLayer) -> [[WorkspaceMapPin]] {
        physicalPlaceGroups(marker.members.filter { $0.layer != "city" }).filter {
            MapMarkerLayer.forLayer($0[0].layer) == layer
        }
    }
    private func summaryCount(_ layer: MapMarkerLayer, in marker: MapRenderedMarker) -> Int {
        if layer == .pins || layer == .saves { return summaryPlaceGroups(marker, layer: layer).count }
        return MapCityGrouping.count(layer: layer, items: marker.members.map {
            (id: $0.id, layer: $0.layer, tripID: $0.tripID?.uuidString ?? (destination.isEmpty ? nil : tripChoices.first?.id.uuidString))
        })
    }
    private func summaryAppearance(_ layer: MapMarkerLayer, in marker: MapRenderedMarker) -> MarkAppearance? {
        guard layer == .trips else { return nil }
        let ids = Set(marker.members.filter { MapMarkerLayer.forLayer($0.layer) == .trips }.compactMap(\.tripID))
        guard ids.count == 1, let id = ids.first else { return nil }
        return tripChoices.first { $0.id == id }?.appearance
    }
    private func summaryColor(_ layer: MapMarkerLayer) -> Color {
        switch layer { case .trips: Color(hex: "7462C6"); case .saves: Color(hex: "D8A14C"); case .pins: Color(hex: "E17861") }
    }
    private func openMapSummary(_ marker: MapRenderedMarker, layer: MapMarkerLayer) {
        nativeCitySelection = nil
        let members = layer == .trips ? marker.members.filter { MapMarkerLayer.forLayer($0.layer) == layer }
            : summaryPlaceGroups(marker, layer: layer).flatMap { $0.filter { MapMarkerLayer.forLayer($0.layer) == layer } }
        guard !members.isEmpty else { return }
        if let onCityLayer {
            let names = members.map { $0.layer == "city" ? $0.name : $0.city }.filter { !$0.isEmpty }
            let uniqueCities = Dictionary(names.map { (MapCityGrouping.key($0), $0) }, uniquingKeysWith: { first, _ in first })
            onCityLayer(MapLibraryFilter(cities: marker.isCitySummary ? [marker.city] : Set(uniqueCities.values),
                layer: layer, memberIDs: Set(members.map(\.id)), tripIDs: Set(members.compactMap(\.tripID))))
        } else { openCluster(members) }
    }
    private func mapSummaryView(_ marker: MapRenderedMarker, showsCityLabel: Bool = true, forceExpanded: Bool = false) -> some View {
        let expanded = forceExpanded || expandedMapSummaries.contains(marker.id)
        let dots = markerAppearance == .smallDot && !expanded
        return HStack(spacing: 8) {
            ForEach(MapMarkerLayer.allCases.filter { summaryCount($0, in: marker) > 0 }) { layer in
                Button {
                    if dots { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { _ = expandedMapSummaries.insert(marker.id) } }
                    else { openMapSummary(marker, layer: layer) }
                } label: {
                    if forceExpanded {
                        HStack(spacing: 6) {
                            MarkGlyphView(appearance: summaryAppearance(layer, in: marker), fallback: layer.symbol,
                                          tint: summaryColor(layer), size: 18)
                            Text(layer.rawValue).lineLimit(1)
                            Text(summaryCount(layer, in: marker).formatted()).monospacedDigit().font(.system(size: 14, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(summaryColor(layer))
                        .padding(.horizontal, 11).frame(minWidth: 88, minHeight: 44)
                        .background {
                            Capsule().fill(LinearGradient(
                                colors: colorScheme == .dark
                                    ? [summaryColor(layer).opacity(0.22), summaryColor(layer).opacity(0.11)]
                                    : [Color.white.opacity(0.96), summaryColor(layer).opacity(0.12)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay(Capsule().strokeBorder(summaryColor(layer).opacity(colorScheme == .dark ? 0.38 : 0.3), lineWidth: 1))
                        .shadow(color: summaryColor(layer).opacity(colorScheme == .dark ? 0.1 : 0.08), radius: 3, x: 0, y: 2)
                    } else if dots {
                        Circle().fill(summaryColor(layer)).frame(width: 18, height: 18)
                            .overlay {
                                Text(summaryCount(layer, in: marker).formatted()).font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                            .shadow(color: summaryColor(layer).opacity(0.3), radius: 3, y: 2)
                            .frame(width: 26, height: 26, alignment: .center).contentShape(Rectangle())
                    } else {
                        HStack(spacing: 5) {
                            MarkGlyphView(appearance: summaryAppearance(layer, in: marker), fallback: layer.symbol, tint: summaryColor(layer), size: 10)
                            Text(summaryCount(layer, in: marker).formatted()).monospacedDigit().lineLimit(1).foregroundStyle(AppPalette.ink)
                        }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).frame(height: 24)
                            .background(.white.opacity(colorScheme == .dark ? 0.08 : 0.35), in: Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: 28, alignment: .center).contentShape(Capsule())
                    }
                }.buttonStyle(QuietPressStyle())
                    .accessibilityLabel("\(marker.city) · \(summaryCount(layer, in: marker)) \(layer.rawValue)")
                    .accessibilityHint(dots ? "Show counts" : "Open Library with this filter")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height < -20 {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { _ = expandedMapSummaries.remove(marker.id) }
            }
        }, including: expanded ? .all : .none)
        .accessibilityAction(named: "Close counts") { _ = expandedMapSummaries.remove(marker.id) }
        .frame(minWidth: 28, minHeight: 28)
        .overlay(alignment: .center) {
            if marker.isCitySummary && showsCityLabel {
                // The badge/dot center is the map coordinate. The title is decoration
                // above it and must never change the annotation's measured anchor.
                MapCityLabel(city: marker.city, countryCode: labelCountryCode(marker), span: visibleRegion?.span.latitudeDelta ?? 0,
                             isVisited: beenBadges && hasVisitedCity(marker.city, countryCode: marker.countryCode))
                    .offset(y: dots ? -20 : -31).allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: dots)
    }
    private func citySummaryPinView(_ marker: MapRenderedMarker) -> some View {
        let expanded = expandedMapCities.contains(marker.id)
        let trips = summaryCount(.trips, in: marker)
        let saves = summaryCount(.saves, in: marker)
        let pins = summaryCount(.pins, in: marker)
        return VStack(spacing: 5) {
            if expanded {
                mapSummaryView(marker, showsCityLabel: false, forceExpanded: true)
                    .padding(8).background(colorScheme == .dark ? Color(hex: "25272B") : Color(hex: "F6F5F2"), in: RoundedRectangle(cornerRadius: 16))
            }
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    if expanded { expandedMapCities.remove(marker.id) } else { expandedMapCities.insert(marker.id) }
                }
            } label: {
                LightweightMapCityMarkerLabel(city: marker.city, countryCode: labelCountryCode(marker),
                    trips: trips, saves: saves, pins: pins,
                    visited: beenBadges && hasVisitedCity(marker.city, countryCode: marker.countryCode))
            }.buttonStyle(QuietPressStyle())
        }.fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder
    private func renderedMarkerView(_ marker: MapRenderedMarker) -> some View {
        if !destination.isEmpty { tripMarkerView(marker) }
        else if marker.isCitySummary { citySummaryPinView(marker) }
        else {
            let points = physicalPlaceGroups(marker.members)
            if points.count > 1 { mapSummaryView(marker) }
            else if let pin = points.first?.first {
                if pin.layer == "pin" || pin.layer == "saved" { storedLocationButton(pin) }
                else if markerAppearance != .pill {
                    Button { selectMarker(pin) } label: { mapDot([pin], count: nil) }
                        .buttonStyle(QuietPressStyle()).accessibilityLabel(pin.name)
                } else { pinButton(pin) }
            }
        }
    }
    /// (day index, stop number) from a planned pin's "day.stop" badge.
    private func tripStop(_ pin: WorkspaceMapPin) -> (day: Int, stop: Int)? {
        guard pin.layer == "planned", let parts = pin.badge?.split(separator: ".").compactMap({ Int($0) }), parts.count == 2 else { return nil }
        return (parts[0] - 1, parts[1])
    }
    /// Planned stops first (in plan order), then suggestions, then your own pins.
    private func tripPriority(_ pin: WorkspaceMapPin) -> (Int, Int, Int) {
        if let stop = tripStop(pin) { return (0, stop.day, stop.stop) }
        return (pin.layer == "recommended" ? 1 : 2, 0, 0)
    }
    @ViewBuilder private func tripMarkerView(_ marker: MapRenderedMarker) -> some View {
        let groups = physicalPlaceGroups(marker.members)
        let lead = groups.compactMap(\.first).min { tripPriority($0) < tripPriority($1) }
        if let pin = lead {
            if groups.count == 1 && (pin.layer == "pin" || pin.layer == "saved") { storedLocationButton(pin) }
            else {
                let stop = tripStop(pin)
                Button {
                    if groups.count > 1 { openCluster(marker.members) } else { focusPin(pin) }
                } label: {
                    TripStopMarker(name: pin.name, symbol: pin.category.symbol,
                                   tint: stop.map { routeColor($0.day) } ?? pinIconTint(pin.category.tint),
                                   number: stop?.stop, extra: groups.count - 1,
                                   showsLabel: labeledMarkerIDs.contains(marker.id),
                                   focused: groups.count == 1 && focusedMapPinID == pin.id)
                }.buttonStyle(QuietPressStyle())
                    .opacity(openNowOnly && openState(pin) == nil ? 0.4 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: labeledMarkerIDs.contains(marker.id))
            }
        }
    }
    /// Greedy label placement: a name goes to the right of its marker only when
    /// it overlaps no other label or marker and stays on screen.
    private func tripLabelIDs(_ rendered: [MapRenderedMarker], proxy: MapProxy, span: Double) -> Set<String> {
        guard span < 0.09 else { return [] }
        let size = markerViewport
        var dots: [(id: String, rect: CGRect)] = []
        var candidates: [(id: String, point: CGPoint, name: String, priority: (Int, Int, Int))] = []
        for marker in rendered {
            guard let point = proxy.convert(marker.coordinate, to: .local), point.x.isFinite, point.y.isFinite else { continue }
            dots.append((marker.id, CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)))
            let groups = physicalPlaceGroups(marker.members)
            guard groups.count == 1, let pin = groups.first?.first, pin.layer != "pin", pin.layer != "saved" else { continue }
            let priority = tripPriority(pin)
            if priority.0 == 1 && span > 0.03 { continue }   // suggestions are named only close in
            candidates.append((marker.id, point, pin.name, priority))
        }
        var placed: [CGRect] = []
        var result = Set<String>()
        for candidate in candidates.sorted(by: { $0.priority < $1.priority }) {
            let width = min(176, CGFloat(candidate.name.count) * 6.7 + 18)
            let rect = CGRect(x: candidate.point.x + 16, y: candidate.point.y - 12, width: width, height: 24)
            if size != .zero && (rect.maxX > size.width - 6 || rect.minY < 0 || rect.maxY > size.height) { continue }
            if placed.contains(where: { $0.insetBy(dx: -4, dy: -3).intersects(rect) }) { continue }
            if dots.contains(where: { $0.id != candidate.id && $0.rect.intersects(rect) }) { continue }
            placed.append(rect); result.insert(candidate.id)
        }
        return result
    }
    private func storedLocationButton(_ pin: WorkspaceMapPin) -> some View {
        Button { focusPin(pin) } label: {
            StoredLocationMarker(title: pin.name, appearance: pin.appearance, pinned: pin.layer == "pin",
                compact: markerAppearance != .pill, showsTitle: markerAppearance != .smallDot, lightweight: destination.isEmpty)
        }.buttonStyle(QuietPressStyle()).accessibilityLabel(pin.name)
    }
    private func selectMarker(_ pin: WorkspaceMapPin) {
        if pin.layer == "city" { onCity(pin.name) } else { focusPin(pin) }
    }
    private func mapDot(_ members: [WorkspaceMapPin], count: Int?) -> some View {
        let first = members[0]
        let color = first.layer == "city" || first.layer == "trip" ? Color(hex: "7462C6") : first.layer == "saved" ? AppPalette.accent : first.category.tint
        let diameter = count == nil ? markerAppearance.dotDiameter : markerAppearance.clusterDiameter
        return ZStack {
            if !destination.isEmpty && members.allSatisfy({ $0.layer == "city" || $0.layer == "trip" }) {
                Color.clear.frame(width: diameter, height: diameter)
                    .modifier(MapDotGlass(tint: color))
            } else {
                Circle().fill(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
            }
            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1).frame(width: diameter, height: diameter)
            if let count {
                Text(count.formatted()).font(.custom("PlusJakartaSans-Bold", size: count > 99 ? 9 : (markerAppearance == .smallDot ? 10 : 11)))
                    .foregroundStyle(!destination.isEmpty && members.allSatisfy { $0.layer == "city" || $0.layer == "trip" } || first.layer == "saved" ? AppPalette.ink : Color.white)
                if Set(members.map(\.layer)).count > 1 {
                    Circle().trim(from: 0, to: 0.35).stroke(AppPalette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: diameter + 2, height: diameter + 2)
                }
            }
        }.frame(width: 44, height: 44).contentShape(Circle())
            .shadow(color: color.opacity(0.25), radius: 4, y: 2)
    }
    private func openCluster(_ members: [WorkspaceMapPin]) {
        let locations = members.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        if let first = locations.first, locations.allSatisfy({ $0.distance(from: first) < 5 }) {
            selectedClusterPins = members
        } else { zoomToMarkers(members) }
    }
    private func zoomToMarkers(_ members: [WorkspaceMapPin]) {
        guard let first = members.first else { return }
        let latitudes = members.map { $0.coordinate.latitude }
        let longitudes = members.map { pin -> Double in
            first.coordinate.longitude + (pin.coordinate.longitude - first.coordinate.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        }
        let latitude = (latitudes.min()! + latitudes.max()!) / 2
        let longitude = ((longitudes.min()! + longitudes.max()!) / 2 + 540).truncatingRemainder(dividingBy: 360) - 180
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
            nativeCameraRequestID = UUID(); position = .region(.init(center: .init(latitude: latitude, longitude: longitude),
                span: .init(latitudeDelta: max(0.008, (latitudes.max()! - latitudes.min()!) * 1.7),
                            longitudeDelta: max(0.008, (longitudes.max()! - longitudes.min()!) * 1.7))))
        }
    }
    private func categoryFilterPill(_ title: String, symbol: String, enabled: Binding<Bool>) -> some View {
        MapFilterPill(title: title, symbol: symbol, enabled: enabled.wrappedValue,
                      expandable: false, expanded: false,
                      toggle: { enabled.wrappedValue.toggle() }, expand: {})
    }
    private var mapThemePicker: some View {
        Menu {
            Picker("Map appearance", selection: $theme) {
                Label("Explore", systemImage: "map").tag("Explore")
                Label("Quiet", systemImage: "leaf").tag("Quiet")
                Label("Satellite", systemImage: "globe.americas").tag("Satellite")
                Label("Hybrid", systemImage: "square.3.layers.3d").tag("Hybrid")
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: theme == "Satellite" ? "globe.americas.fill" : theme == "Hybrid" ? "square.3.layers.3d" : theme == "Quiet" ? "leaf" : "map")
                    .font(.system(size: 21, weight: .medium)).frame(width: 46, height: 46)
                    .background(.white.opacity(darkMode ? 0.08 : 0.5), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme).font(.custom("PlusJakartaSans-Bold", size: 16))
                    Text("Choose a theme").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
            }.foregroundStyle(AppPalette.ink).padding(14)
                .background(.white.opacity(darkMode ? 0.05 : 0.32), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Map appearance: \(theme), choose a theme")
    }
    /// You: profile photo → Account (plan, settings, admin). Replaces the old settings gear.
    private var mapOptionsMenu: some View {
        Button { onPlacesSettings?() } label: {
            ProfileAvatar(size: 44).frame(width: 52, height: 52).modifier(MapRaisedCircle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel("Account and settings")
    }
    func pinButton(_ pin: WorkspaceMapPin) -> some View {
        let span = visibleRegion?.span.latitudeDelta ?? 0
        let showsName = span < 0.12
        let iconColor = pinIconTint(pin.layer == "recommended" ? Color(hex: "CE6651") : pin.category.tint)
        return Button { focusPin(pin) } label: {
            if pin.layer == "search" {
                SearchMapPinView(category: pin.category)
            } else {
            HStack(spacing: 7) {
                MarkGlyphView(appearance: pin.appearance, fallback: pin.layer == "saved" ? "heart.fill" : pin.category.symbol, tint: iconColor, size: 14)
                if showsName {
                    Text(pin.name).font(.custom("PlusJakartaSans-SemiBold", size: 11)).lineLimit(1)
                        .frame(maxWidth: 190, alignment: .leading)
                }
                if let badge = pin.badge, showsName {
                    Text(badge).font(.custom("PlusJakartaSans-Bold", size: 8)).foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 6).frame(minHeight: 16).background(AppPalette.surface, in: Capsule())
                }
            }
            .foregroundStyle(AppPalette.ink).padding(.horizontal, showsName ? 11 : 13).frame(minHeight: 42)
            .modifier(MapFrostedCapsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
            .shadow(color: AppPalette.ink.opacity(0.17), radius: 6, y: 2)
            }
        }.buttonStyle(QuietPressStyle())
            .overlay {
                if focusedMapPinID == pin.id {
                    Circle().stroke(AppPalette.brand, lineWidth: 2).padding(-5)
                        .shadow(color: AppPalette.brand.opacity(0.4), radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("\(pin.name) · \(pin.category.rawValue)")
    }
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppPalette.secondaryInk)
            if showMapSearch {
                TextField("Place, city, or address", text: $query, prompt: Text("Place, city, or address").foregroundStyle(AppPalette.ink.opacity(0.7)))
                    .font(.subheadline).focused($searchFocused).submitLabel(.search).autocorrectionDisabled()
                    .onSubmit { searchFocused = false }
            } else {
                Button(action: openMapSearch) {
                    Text(destination.isEmpty ? "Search for a place" : "Search in \(destination)")
                        .font(.subheadline).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 52).contentShape(Rectangle())
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Open search")
            }
        }.padding(.horizontal, 18).frame(height: 52)
            .modifier(MapFrostedCapsule(focused: searchFocused))
            .task(id: "\(showMapSearch):\(query)") {
                guard showMapSearch else { return }
                await searchPlaces()
            }
    }
    // "New trip" lives in the tab bar; here the button only closes search.
    @ViewBuilder private var searchCloseOrCreateButton: some View {
        if showMapSearch { searchCloseButton }
    }
    private var searchCloseButton: some View {
        Button {
            if showMapSearch { closeMapSearch() } else { onNewTrip?() }
        } label: {
            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                .rotationEffect(.degrees(showMapSearch ? 45 : 0))
                .foregroundStyle(AppPalette.ink).frame(width: 48, height: 48).modifier(MapRaisedCircle())
        }.buttonStyle(QuietPressStyle()).accessibilityLabel(showMapSearch ? "Close search" : "New trip")
    }
    private func openMapSearch() {
        expandedMapFilter = nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { showMapSearch = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard showMapSearch else { return }
            searchFocused = true
        }
    }
    private func closeMapSearch() {
        searchFocused = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { showMapSearch = false }
        query = ""; searchResults = []; searchError = nil; searchSourceNotice = nil; searching = false
        appleSearchStatus = .idle; googleSearchStatus = .idle
    }
    private func providerLight(_ status: MapSearchProviderStatus) -> some View {
        Circle().fill(status == .used ? Color(hex: "64A87B") : status == .unavailable ? Color(hex: "BC514A") : Color.secondary.opacity(0.3))
            .frame(width: 5, height: 5)
    }
    private var providerStatusRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "apple.logo").font(.system(size: 16, weight: .medium))
                providerLight(appleSearchStatus)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Apple Maps: \(appleSearchStatus.label)")
            HStack(spacing: 5) {
                Image(systemName: "heart.text.square").font(.system(size: 15, weight: .medium))
                providerLight(googleSearchStatus)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Your saved places: \(googleSearchStatus.label)")
            Spacer()
            if searching { ProgressView().controlSize(.small) }
            Text("\(displayedSearchResults.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(AppPalette.secondaryInk)
                .accessibilityLabel("\(displayedSearchResults.count) results")
        }.foregroundStyle(AppPalette.ink).frame(height: 22)
    }
    private var mapSearchOverlay: some View {
        GeometryReader { geometry in
            if showMapSearch {
                MapSearchPanelContainer(availableHeight: geometry.size.height, viewportBottom: geometry.frame(in: .global).maxY, barHeight: topControlsHeight, onClose: closeMapSearch) { drag in
                    searchPanel(drag: drag)
                }.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    /// Your own saves and pins that match, shown first and instantly.
    private var localSearchMatches: [PersonalPlace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard q.count >= 2 else { return [] }
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        return Array(savedPlaces.filter { fold($0.name).contains(q) || fold($0.city).hasPrefix(q) }.prefix(4))
    }
    private var recentSearches: [String] { recentSearchStorage.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
    private func rememberSearch(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        recentSearchStorage = ([value] + recentSearches.filter { $0.caseInsensitiveCompare(value) != .orderedSame }).prefix(6).joined(separator: "\n")
    }
    private func distanceLabel(_ place: PersonalPlace) -> String? {
        guard let center = visibleRegion?.center else { return nil }
        let meters = CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        return meters < 1_000 ? "\(Int(meters / 10) * 10) m" : meters < 100_000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters / 1000).formatted()) km"
    }
    private func searchPanel(drag: AnyGesture<DragGesture.Value>) -> some View {
        let local = localSearchMatches
        let areas = displayedSearchResults.filter { $0.searchKind == .area }
        let places = displayedSearchResults.filter { $0.searchKind != .area }
        let hasResults = !local.isEmpty || !displayedSearchResults.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            // The container already draws the grabber; this strip only extends its drag area.
            Color.clear.frame(height: 8).contentShape(Rectangle()).gesture(drag)
            if !searchResults.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(MapSearchFilter.allCases) { filter in
                            MapFilterPill(title: filter.title, symbol: searchFilterSymbol(filter),
                                enabled: searchFilter == filter, expandable: false, expanded: false,
                                toggle: { searchFilter = filter }, expand: {})
                                .accessibilityAddTraits(searchFilter == filter ? .isSelected : [])
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 6)
                }.scrollIndicators(.hidden).frame(height: 46)
            }
            if hasResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !local.isEmpty { searchSection("Yours", local) }
                        if !areas.isEmpty { searchSection("Cities and areas", areas) }
                        if !places.isEmpty { searchSection("Places", places) }
                        if searching { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finding more…") }
                            .font(.footnote).foregroundStyle(AppPalette.secondaryInk).padding(.vertical, 10).padding(.horizontal, 4) }
                    }
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                VStack(alignment: .leading, spacing: 12) {
                    if !recentSearches.isEmpty {
                        Text("RECENT").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(AppPalette.secondaryInk)
                        FlowLayout(spacing: 8) {
                            ForEach(recentSearches, id: \.self) { recent in
                                Button { query = recent } label: {
                                    Label(recent, systemImage: "clock.arrow.circlepath").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                                        .padding(.horizontal, 12).frame(height: 36).raisedCapsule()
                                }.buttonStyle(QuietPressStyle())
                            }
                        }
                    }
                    Text("Search a city, neighborhood, address or place.")
                        .font(Sketch.text(15, relativeTo: .body)).foregroundStyle(AppPalette.secondaryInk)
                    Spacer()
                }
                .padding(.horizontal, 6).padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle()).gesture(drag)
            } else {
                VStack(spacing: 10) {
                    if searching { ProgressView(); Text("Searching…").font(.footnote).foregroundStyle(AppPalette.secondaryInk) }
                    else {
                        Text(searchError ?? "Nothing found").font(Sketch.text(16, "SemiBold", relativeTo: .body))
                        Text("Try adding the city, or check the spelling.").font(.footnote).foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).gesture(drag)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    @ViewBuilder private func searchSection(_ title: String, _ items: [PersonalPlace]) -> some View {
        Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(AppPalette.secondaryInk)
            .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 2)
        ForEach(items) { place in
            Button { rememberSearch(place.name); selectSearchResult(place) } label: {
                HStack(spacing: 12) {
                    let tint = place.searchKind == .area ? AppPalette.brand : place.category.tint
                    Image(systemName: place.isSaved ? "heart.fill" : place.isPinned ? "mappin" : place.searchKind == .area ? "map" : place.category.symbol)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                        .frame(width: 40, height: 40).background(tint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.custom("PlusJakartaSans-Bold", size: 15)).foregroundStyle(AppPalette.ink).lineLimit(1)
                        Text([place.searchKind == .area ? geographicScopeLabel(place.boundaryLevel) : place.category.rawValue,
                              place.address.isEmpty ? place.city : place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let distance = distanceLabel(place) {
                        Text(distance).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 8).frame(minHeight: 60).contentShape(Rectangle())
            }
            .buttonStyle(QuietPressStyle())
        }
    }
    private func searchFilterSymbol(_ filter: MapSearchFilter) -> String {
        switch filter { case .all: "square.grid.2x2"; case .places: "mappin"; case .cities: "building.2"; case .food: "fork.knife"; case .cafes: "cup.and.saucer"; case .sights: "building.columns" }
    }
    func searchPlaces() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            searching = false; searchResults = []; searchError = nil
            appleSearchStatus = .idle; googleSearchStatus = .idle
            return
        }
        do { try await Task.sleep(for: .milliseconds(220)); try Task.checkCancellation() }
        catch { return }
        searchError = nil; searching = true
        appleSearchStatus = .loading
        googleSearchStatus = .loading
        TrippyPerformance.mark("search.begin")
        // Apple's search plus the user's own saved, pinned and TikTok places. Google search results
        // can't be shown on our map under the EEA terms, so search no longer calls Google.
        var apple: [PersonalPlace] = [], google: [PersonalPlace] = []
        await withTaskGroup(of: (Bool, [PersonalPlace]?).self) { group in
            group.addTask { @MainActor in (true, try? await searchApplePlaces(text)) }
            group.addTask { @MainActor in (false, libraryMatches(text)) }
            for await (isApple, results) in group {
                guard !Task.isCancelled, showMapSearch, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { group.cancelAll(); return }
                if isApple { apple = results ?? []; appleSearchStatus = results == nil ? .unavailable : .used }
                else { google = results ?? []; googleSearchStatus = results == nil ? .unavailable : .used }
                searchResults = rankedUniqueSearchResults(google + apple, query: text)
                TrippyPerformance.mark(isApple ? "search.apple" : "search.google")
            }
        }
        guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
        searching = false
        if searchResults.isEmpty { searchError = appleSearchStatus == .unavailable ? "Search isn’t reachable right now" : "Nothing found" }
    }
    /// The user's own places whose name or address matches the query (free, on the phone).
    private func libraryMatches(_ text: String) -> [PersonalPlace] {
        func folded(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let needle = folded(text)
        var seen = Set<String>()
        return (savedPlaces.filter { $0.isSaved || $0.isPinned } + pins.map(\.personalPlace))
            .filter { place in
                guard place.searchKind != .area else { return false }
                return folded(place.name).contains(needle) || folded(place.address).contains(needle)
            }
            .filter { seen.insert(folded($0.name) + String(format: ":%.3f:%.3f", $0.latitude, $0.longitude)).inserted }
            .prefix(8).map { $0 }
    }
    private func searchApplePlaces(_ text: String) async throws -> [PersonalPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination.isEmpty ? text : "\(text), \(destination)"
        if let region = visibleRegion { request.region = region }
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
        return response.mapItems.prefix(12).compactMap { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let name = item.name ?? text
            let placemark = item.placemark
            let normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let areaNames = [placemark.subLocality, placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea, placemark.country]
                .compactMap { $0?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            let isArea = item.pointOfInterestCategory == nil && areaNames.contains(normalizedName)
            let kind: SearchPlaceKind = isArea ? .area : (item.pointOfInterestCategory == nil ? .attraction : .place)
            return PersonalPlace(id: "apple:\(name.lowercased()):\(coordinate.latitude):\(coordinate.longitude)", name: name,
                                 city: placemark.locality ?? destination, address: placemark.title ?? name,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude,
                                 category: .classify(item.pointOfInterestCategory?.rawValue ?? name),
                                 searchKind: kind, boundaryCountryCode: placemark.isoCountryCode,
                                 searchLatitudeSpan: response.boundingRegion.span.latitudeDelta,
                                 searchLongitudeSpan: response.boundingRegion.span.longitudeDelta,
                                 boundaryLevel: boundaryLevel(for: placemark, title: name),
                                 phoneNumber: item.phoneNumber, websiteURL: item.url?.absoluteString)
        }
    }
    private func boundaryLevel(for placemark: MKPlacemark, title: String) -> String? {
        let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        func matches(_ value: String?) -> Bool {
            value?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedTitle
        }
        if matches(placemark.country) { return "country" }
        if matches(placemark.administrativeArea) { return "region" }
        if matches(placemark.subAdministrativeArea) { return "district" }
        if matches(placemark.subLocality) { return "area" }
        if matches(placemark.locality) { return "city" }
        return nil
    }
    private func rankedUniqueSearchResults(_ candidates: [PersonalPlace], query: String) -> [PersonalPlace] {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var unique: [PersonalPlace] = []
        for place in candidates {
            let duplicate = unique.contains { existing in
                if existing.googlePlaceID != nil, existing.googlePlaceID == place.googlePlaceID { return true }
                if existing.searchKind == .area, place.searchKind == .area,
                   existing.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame { return true }
                let meters = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                return meters < 140 && existing.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame
            }
            if !duplicate { unique.append(place) }
            if unique.count == 24 { break }
        }
        return unique.sorted { lhs, rhs in
            func score(_ place: PersonalPlace) -> Int {
                let name = place.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if name == normalizedQuery { return place.searchKind == .area ? 100 : 90 }
                if place.searchKind == .area && name.hasPrefix(normalizedQuery) { return 80 }
                if name.hasPrefix(normalizedQuery) { return 70 }
                return 50
            }
            let a = score(lhs), b = score(rhs)
            if a != b { return a > b }
            guard let center = visibleRegion?.center else { return false }
            let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
            return origin.distance(from: CLLocation(latitude: lhs.latitude, longitude: lhs.longitude))
                < origin.distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
        }
    }
    private func searchGooglePlaces(_ text: String, timeout: TimeInterval = 6) async throws -> [PersonalPlace] {
        guard !placesAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard var components = URLComponents(string: placesBaseURL + "/api/places/search") else { throw URLError(.badURL) }
        let queryText = destination.isEmpty ? text : "\(text), \(destination)"
        components.queryItems = [URLQueryItem(name: "q", value: queryText),
                                 URLQueryItem(name: "lang", value: googlePlacesLanguage(for: text))]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(placesAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(GooglePlaceSearchResponse.self, from: data)
        return payload.places.map { place in
            let type = place.primaryType.lowercased()
            let knownTypes = place.types ?? []
            let areaTypes = ["locality", "country", "administrative_area_level_1", "administrative_area_level_2", "postal_town", "neighborhood", "sublocality"]
            let sameAsCity = place.city?.localizedCaseInsensitiveCompare(place.name) == .orderedSame
            let area = place.isArea == true || sameAsCity
                || knownTypes.contains(where: { candidate in areaTypes.contains(where: candidate.contains) })
                || areaTypes.contains(where: type.contains)
            let boundaryLevel = place.boundaryLevel ?? {
                if knownTypes.contains("country") { return "country" }
                if knownTypes.contains("administrative_area_level_1") { return "region" }
                if knownTypes.contains("administrative_area_level_2") { return "district" }
                if knownTypes.contains(where: { ["neighborhood", "sublocality"].contains($0) }) { return "area" }
                return area ? "city" : nil
            }()
            let category = MapPlaceCategory.classify(place.primaryType)
            let kind: SearchPlaceKind = area ? .area : (category == .sights ? .attraction : .place)
            return PersonalPlace(id: "google:\(place.placeID)", name: place.name, city: place.city ?? destination,
                                address: place.address, latitude: place.latitude, longitude: place.longitude,
                                category: category, searchKind: kind, boundaryCountryCode: place.countryCode,
                                searchLatitudeSpan: area ? (place.latitudeSpan ?? 1.2) : nil,
                                searchLongitudeSpan: area ? (place.longitudeSpan ?? 1.2) : nil,
                                boundaryLevel: boundaryLevel,
                                searchTypes: knownTypes, googlePlaceID: place.placeID)
        }
    }
    private func googlePlacesLanguage(for text: String) -> String {
        let containsGreek = text.unicodeScalars.contains { scalar in
            (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
        }
        return containsGreek ? "el" : "en"
    }
    private func geographicScopeLabel(_ level: String?) -> String {
        switch level {
        case "country": "Country"
        case "region": "Region"
        case "district", "area": "Area"
        default: "City"
        }
    }
    private func selectSearchResult(_ result: PersonalPlace) {
        let place = result
        let pin = WorkspaceMapPin(id: place.id, name: place.name, coordinate: place.coordinate, layer: "search",
                                  category: place.category, city: place.city, address: place.address,
                                  searchKind: place.searchKind ?? .place, boundaryCountryCode: place.boundaryCountryCode,
                                  searchLatitudeSpan: place.searchLatitudeSpan, searchLongitudeSpan: place.searchLongitudeSpan,
                                  boundaryLevel: place.boundaryLevel,
                                  phoneNumber: place.phoneNumber, websiteURL: place.websiteURL, googlePlaceID: place.googlePlaceID)
        presentPlace(pin)
    }
    private func presentPlace(_ pin: WorkspaceMapPin) {
        showMapSearch = false
        query = ""
        searchResults = []
        searchFocused = false
        searchSourceNotice = nil
        focusedMapPinID = pin.id
        selectedSearchPlace = pin.layer == "search" && pin.searchKind != .area ? pin : nil
        selectedPinCategory = nil
        googlePlaceDetails = nil
        googleDetailsError = nil
        // Frame inside the part of the map the low panel leaves visible, not the whole screen:
        // the highlighted area stays fully in view and the pin sits above the panel.
        let isArea = pin.searchKind == .area
        let latitudeSpan = isArea ? max(0.12, min(40, (pin.searchLatitudeSpan ?? 0.5) * MapPanelFraming.areaFit)) : 0.018
        let longitudeSpan = isArea ? max(0.12, min(40, (pin.searchLongitudeSpan ?? 0.5) * MapPanelFraming.areaFit)) : 0.018
        let shift = MapPanelFraming.visibleCenterShift(isArea: isArea)
        let region = MKCoordinateRegion(center: .init(latitude: max(-85, pin.coordinate.latitude - latitudeSpan * shift), longitude: pin.coordinate.longitude),
                                        span: .init(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
        withAnimation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.86)) {
            if pin.searchKind == .attraction || pin.searchKind == .place {
                let distance: Double = pin.searchKind == .attraction ? 3_400 : 2_800
                let down = distance * 0.9 * shift / 111_000
                nativeCameraRequestID = UUID(); position = .camera(MapCamera(centerCoordinate: .init(latitude: pin.coordinate.latitude - down, longitude: pin.coordinate.longitude),
                                                                              distance: distance, heading: 0, pitch: pin.searchKind == .attraction ? 40 : 24))
            } else { nativeCameraRequestID = UUID(); position = .region(region) }
        }
        selectedPin = pin
        guard pin.searchKind == .area else { mapPlaceBoundaryLines = []; areaHighlightOpacity = 0; return }
        if pin.boundaryLevel == "area" {
            mapPlaceBoundaryLines = []; areaHighlightOpacity = 0
            return
        }
        Task {
            let lines = try? await GeoBoundaryRepository.shared.boundary(
                countryISO2: pin.boundaryCountryCode,
                countryNames: [pin.address, pin.city].filter { !$0.isEmpty },
                placeNames: [pin.name], levelID: pin.boundaryLevel ?? "city",
                center: GeoBoundaryPoint(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
            guard !Task.isCancelled, focusedMapPinID == pin.id else { return }
            withAnimation(.easeInOut(duration: 0.35)) { mapPlaceBoundaryLines = lines ?? []; areaHighlightOpacity = 0 }
            guard lines != nil else { return }
            for _ in 0..<2 {
                withAnimation(.easeOut(duration: 0.24)) { areaHighlightOpacity = 1 }
                try? await Task.sleep(for: .milliseconds(360))
                withAnimation(.easeInOut(duration: 0.32)) { areaHighlightOpacity = 0.12 }
                try? await Task.sleep(for: .milliseconds(180))
            }
            withAnimation(.easeOut(duration: 0.35)) { areaHighlightOpacity = 0 }
        }
    }
    private func focusPin(_ pin: WorkspaceMapPin) {
        TrippyHaptics.selection()
        presentPlace(pin)
    }
    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard selectedPin != nil else { return }
        let selectablePins = pins + cityPins + (selectedSearchPlace.map { [$0] } ?? [])
        let touchedPin = selectablePins.contains { pin in
            guard let anchor = destination.isEmpty ? generalMapController.point(pin.coordinate) : proxy.convert(pin.coordinate, to: .local) else { return false }
            return hypot(anchor.x - point.x, anchor.y - point.y) < 125
        }
        guard !touchedPin else { return }
        selectedPin = nil
    }
    func selectedPlacePanel(_ pin: WorkspaceMapPin) -> some View {
        let saved = savedPlaces.contains { $0.isSaved && samePlace($0, pin) }
        let category = selectedPinCategory ?? pin.category
        let isArea = pin.searchKind == .area
        let tint = isArea ? Sketch.sage : category.tint
        let details = googlePlaceDetails
        let photos = details?.photos ?? []
        let mentions = relatedTikTokMentions(for: pin)
        let linkedSources = socialSources.filter { source in
            mentions.contains(where: { $0.sourceID == source.id })
        }
        let linkedNotes = travelNotes.filter { note in
            mentions.contains(where: { $0.noteID == note.id || note.sourceIDs.contains($0.sourceID) })
                || (note.linkedPlaceIDs ?? []).contains(pin.placeID ?? pin.id)
        }
        let title = details?.name.nonEmpty ?? pin.name
        let summary = details?.summary.nonEmpty ?? mentions.lazy.compactMap { $0.summary.nonEmpty }.first
        let collapsed: PresentationDetent = .height(isArea ? MapPanelFraming.areaHeight : MapPanelFraming.placeHeight)
        return ScrollViewReader { reader in ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                placePanelHeader(pin, title: title, category: category, tint: tint, details: details, photo: photos.first)

                if let summary {
                    (Text("In short; ").font(Sketch.display(.headline, weight: .bold)).foregroundStyle(AppPalette.ink)
                     + Text(summary).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(AppPalette.secondaryInk))
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        .lineLimit(placePanelDetent == collapsed ? 2 : nil)
                }

                let communityVideos = placeVideos.filter { video in !linkedSources.contains { $0.envelope.sourceURL == video.url } }
                if !isArea && linkedSources.count + communityVideos.count > 0 {
                    Button {
                        placePanelDetent = .large
                        Task { try? await Task.sleep(for: .milliseconds(250)); withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { reader.scrollTo("place-videos", anchor: .top) } }
                    } label: {
                        Label("\(linkedSources.count + communityVideos.count) TikToks & videos about this place", systemImage: "play.rectangle.on.rectangle.fill")
                            .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(minHeight: 38).background(Color(hex: "161616"), in: Capsule())
                    }.buttonStyle(BubblePressStyle())
                }

                let tags = mentions.lazy.compactMap { $0.vibeTags }.first { !$0.isEmpty } ?? []
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Sketch.paperDeep, in: Capsule())
                        }
                    }
                }

                if !isArea {
                    // Saved, pinned and TikTok places: Google's rating line through the UI Kit
                    // (the only form the EEA terms allow beside a map). Everything else stays free.
                    if let kitPlaceID, isLibraryPlace(pin) {
                        GooglePlaceBlock(placeID: kitPlaceID, baseURL: placesBaseURL, token: placesAccessToken)
                            .id(kitPlaceID)
                    }
                    if #available(iOS 18.0, *) {
                        if appleMapItem != nil { AppleMapsCardButton { appleCardItem = appleMapItem } }
                    }
                }

                if !isArea {
                    if !photos.isEmpty {
                        PlacePhotoMosaic(photos: photos, baseURL: placesBaseURL, accessToken: placesAccessToken, tint: tint) { photoViewerIndex = $0 }
                    } else if loadingGoogleDetails {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(tint.opacity(0.12))
                            .overlay(PlacePhotoShimmer(tint: tint)).frame(height: 212)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .accessibilityLabel("Loading photos")
                    } else {
                        // No Google photos: a real photo from Wikipedia or the venue's website,
                        // and only then the street view or the painted card.
                        PlacePhoto(name: title, latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude,
                                   sight: category == .sights || category == .parks, symbol: category.symbol, tint: tint,
                                   website: (details?.websiteURL).flatMap(URL.init(string:)))
                            .frame(height: 212).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }

                if let googleDetailsError, !isArea {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(Sketch.coral)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(googleDetailsError).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Try again", systemImage: "arrow.clockwise") { Task { await loadGoogleDetails(for: pin) } }
                                .font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(AppPalette.brand).frame(minHeight: 32)
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Sketch.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if !isArea {
                    let notes: [(String, String, [String])] = [
                        ("Pro tips", "lightbulb", mergedNotes(mentions, \.proTips)), ("Must try", "star", mergedNotes(mentions, \.mustTry)),
                        ("Why go", "heart.text.square", mergedNotes(mentions, \.whyGo)), ("Good to know", "info.circle", mergedNotes(mentions, \.goodToKnow))]
                    ForEach(notes.filter { !$0.2.isEmpty }, id: \.0) { note in PlaceNoteCard(title: note.0, symbol: note.1, items: note.2) }
                    placePanelSection("Details")
                    PlaceInfoCard(address: details?.address.nonEmpty ?? pin.address.nonEmpty ?? pin.city.nonEmpty, details: details,
                                  phone: details?.phoneNumber ?? pin.phoneNumber, website: details?.websiteURL ?? pin.websiteURL) {
                        beginDirections(to: pin)
                    }
                }

                if isArea {
                    let held = cityHoldings(pin)
                    if held.trips + held.pins + held.saves > 0 || held.visited != nil {
                        CityHoldingsCard(trips: held.trips, pins: held.pins, saves: held.saves, visited: held.visited?.visitedAt) {
                            dismissPlacePanel { onCity(pin.city.nonEmpty ?? pin.name) }
                        }
                    }
                    StatlasCityCard(city: pin.city.nonEmpty ?? pin.name, countryCode: pin.boundaryCountryCode, latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
                }

                if !linkedSources.isEmpty || linkedNotes.contains(where: { $0.userText.nonEmpty != nil }) {
                    placePanelSection("From your videos", count: linkedSources.count).id("place-videos")
                    if !linkedSources.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(linkedSources) { source in
                                    let video = source.envelope.attachments.first { $0.kind == "video" }.flatMap { SharedInbox.attachmentURL(sourceID: source.id, attachment: $0) }
                                    let image = source.envelope.attachments.first { $0.kind == "image" }.flatMap { SharedInbox.attachmentURL(sourceID: source.id, attachment: $0) }
                                    let poster = PlaceVideoPoster(title: source.listTitle ?? source.displayTitle ?? "Saved video",
                                                                  summary: mentions.first(where: { $0.sourceID == source.id })?.summary.nonEmpty,
                                                                  videoURL: video, imageURL: image)
                                    if let link = source.envelope.sourceURL.flatMap(URL.init(string:)) {
                                        Link(destination: link) { poster }.accessibilityLabel("Open video on TikTok")
                                    } else { poster }
                                }
                            }.padding(.horizontal, 20).padding(.vertical, 4)
                        }.scrollIndicators(.hidden).padding(.horizontal, -20)
                    }
                    ForEach(linkedNotes.filter { $0.userText.nonEmpty != nil }) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(note.title, systemImage: "note.text").font(Sketch.text(13, "Bold", relativeTo: .subheadline))
                            Text(note.userText).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(AppPalette.secondaryInk)
                                .lineLimit(placePanelDetent == .large ? nil : 3)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Sketch.plum.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                if !isArea && !communityVideos.isEmpty {
                    if linkedSources.isEmpty {
                        placePanelSection("TikToks about this place", count: communityVideos.count).id("place-videos")
                    } else {
                        placePanelSection("More from the community", count: communityVideos.count)
                    }
                    PlaceVideosSection(videos: communityVideos)
                }

                if let reviews = details?.reviews, !reviews.isEmpty {
                    placePanelSection("What people say", count: details?.reviewCount).id("reviews")
                    PlaceReviewStrip(reviews: reviews)
                }

                if showLookAround {
                    NativeLookAroundCard(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
                }

                if isArea && pin.boundaryLevel == "area" {
                    Button {
                        let place = NeighborhoodPlace(id: pin.id, name: pin.name, latitude: pin.coordinate.latitude,
                            longitude: pin.coordinate.longitude, city: pin.city, countryCode: pin.boundaryCountryCode,
                            source: pin.googlePlaceID == nil ? "Apple Maps" : "Google Places")
                        dismissPlacePanel { selectedNeighborhood = place }
                    } label: {
                        Label("Neighborhood · your feedback", systemImage: "square.3.layers.3d")
                            .font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Sketch.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }.buttonStyle(QuietPressStyle())
                }
                if onPlanPin != nil && (pin.layer == "planned" || pin.layer == "recommended") {
                    Button { pendingPlanPin = pin; selectedPin = nil } label: {
                        Label("Add to plan", systemImage: "calendar.badge.plus")
                            .font(Sketch.text(15, "Bold", relativeTo: .headline)).frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(AppPalette.ink).background(Sketch.card, in: Capsule())
                    }.buttonStyle(QuietPressStyle())
                }
                if appleMapItem != nil {
                    Text("Place details from Apple Maps").font(Sketch.text(11, relativeTo: .caption2))
                        .foregroundStyle(AppPalette.secondaryInk).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .task(id: pin.id) {
            placeVideos = []
            guard !isArea else { return }
            if let demo = CommunityDemo.placeVideos { placeVideos = demo; return }
            placeVideos = (try? await CommunityVideosClient.forPlace(googleID: pin.googlePlaceID ?? resolvedGooglePlaceIDs[pin.id], name: pin.name,
                                                                      city: pin.city, baseURL: placesBaseURL, token: placesAccessToken)) ?? []
        }
        .onChange(of: googlePlaceDetails?.placeID) { _, _ in
            guard PlacePanelDemo.scrollsToReviews else { return }
            Task { try? await Task.sleep(for: .milliseconds(900)); reader.scrollTo("reviews", anchor: .top) }
        }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { placeBottomBar(pin, category: category, saved: saved, tint: tint) }
        .presentationDetents(PlacePanelDemo.detent.map { [$0] } ?? [collapsed, .height(560), .large], selection: $placePanelDetent)
        .presentationContentInteraction(.resizes)
        .onAppear { placePanelDetent = PlacePanelDemo.detent ?? collapsed }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground { PlacePanelBackdrop(tint: tint) }
        .presentationBackgroundInteraction(.enabled(upThrough: collapsed))
        .overlay(alignment: .top) {
            if let emoji = celebrationEmoji { PinCelebrationView(emoji: emoji).padding(.top, 2).transition(.scale(scale: 0.2).combined(with: .opacity)).allowsHitTesting(false) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: celebrationEmoji)
        .fullScreenCover(isPresented: Binding(get: { photoViewerIndex != nil }, set: { if !$0 { photoViewerIndex = nil } })) {
            PlacePhotoViewer(title: title, photos: photos, baseURL: placesBaseURL, accessToken: placesAccessToken, index: photoViewerIndex ?? 0)
        }
        .modifier(AppleMapsCardSheet(item: $appleCardItem))
        .task(id: pin.id) {
            if let detent = PlacePanelDemo.detent {
                Task { try? await Task.sleep(for: .milliseconds(700)); placePanelDetent = detent
                    if PlacePanelDemo.opensViewer { try? await Task.sleep(for: .milliseconds(500)); photoViewerIndex = 0 } }
            }
            await loadGoogleDetails(for: pin)
        }
    }
    private func mergedNotes(_ mentions: [SocialPlaceMention], _ key: KeyPath<SocialPlaceMention, [String]?>) -> [String] {
        var seen = Set<String>()
        return mentions.flatMap { $0[keyPath: key] ?? [] }.filter { seen.insert($0.lowercased()).inserted }
    }
    private func placePanelHeader(_ pin: WorkspaceMapPin, title: String, category: MapPlaceCategory, tint: Color,
                                  details: GooglePlaceDetails?, photo: GooglePlacePhoto?) -> some View {
        let isArea = pin.searchKind == .area
        return HStack(alignment: .top, spacing: 14) {
            PlacePolaroid(photo: photo, baseURL: placesBaseURL, accessToken: placesAccessToken, tint: tint,
                          symbol: isArea ? "map.fill" : category.symbol)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(Sketch.text(25, "ExtraBold", relativeTo: .title)).tracking(-0.6)
                    .foregroundStyle(AppPalette.ink).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { placeMetaChips(pin, category: category, tint: tint, details: details) }
                    HStack(spacing: 8) { placeMetaChips(pin, category: category, tint: tint, details: details, compact: true) }
                    VStack(alignment: .leading, spacing: 6) { placeMetaChips(pin, category: category, tint: tint, details: details) }
                }
            }
            Spacer(minLength: 0)
            placeMoreMenu(pin, category: category)
        }
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder private func placeMetaChips(_ pin: WorkspaceMapPin, category: MapPlaceCategory, tint: Color, details: GooglePlaceDetails?, compact: Bool = false) -> some View {
        let isArea = pin.searchKind == .area
        HStack(spacing: 5) {
            Image(systemName: isArea ? "map.fill" : category.symbol).font(.system(size: 10, weight: .bold))
            Text(isArea ? geographicScopeLabel(pin.boundaryLevel) : (pin.customCategory?.nonEmpty ?? details?.primaryType.nonEmpty ?? category.rawValue))
                .lineLimit(1)
        }
        .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Sketch.card, in: Capsule()).overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
        .fixedSize()
        if let rating = details?.rating {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Sketch.ochre)
                Text(String(format: "%.1f", rating)).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
                if let count = details?.reviewCount, !compact {
                    Text("(\(count.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")))))").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                }
            }.fixedSize().accessibilityElement(children: .combine)
        }
        if let open = details?.openNow {
            HStack(spacing: 4) {
                Text("·").foregroundStyle(AppPalette.secondaryInk)
                Text(open ? "Open now" : "Closed now").font(Sketch.text(12, "Medium", relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
            }.fixedSize().accessibilityElement(children: .combine)
        }
        if isArea, let count = cityTripCount(for: pin), count > 0 {
            Text("\(count) trips").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 9).padding(.vertical, 5).background(AppPalette.accent.opacity(0.35), in: Capsule())
        }
    }
    private func placePanelSection(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(1.1).foregroundStyle(AppPalette.secondaryInk)
            Spacer()
            if let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")))).font(Sketch.text(11, "Bold", relativeTo: .caption2))
                    .foregroundStyle(AppPalette.secondaryInk).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Sketch.paperDeep, in: Capsule())
            }
        }
        .padding(.top, 4).accessibilityAddTraits(.isHeader)
    }
    private func placeMoreMenu(_ pin: WorkspaceMapPin, category: MapPlaceCategory) -> some View {
        Menu {
            Button("Customize pin", systemImage: "paintpalette") { beginCustomPin(pin, pinAsPrimary: true) }
            if let onSaveTripPin {
                Menu("Save to trip", systemImage: "airplane") {
                    ForEach(tripChoices) { trip in
                        Button(trip.title) { onSaveTripPin(trip.id, enrichedPlace(for: pin, category: category, tripID: trip.id)) }
                    }
                    if let onNewTrip { Button("New trip", systemImage: "plus") { dismissPlacePanel(then: onNewTrip) } }
                }
            }
            Menu("Notes", systemImage: "note.text") {
                if let onAddToNote {
                    ForEach(noteChoices) { note in
                        Button(note.title) { dismissPlacePanel { onAddToNote(enrichedPlace(for: pin, category: category), note.id) } }
                    }
                }
                Button("New note", systemImage: "plus") { dismissPlacePanel { onCreateNote?(enrichedPlace(for: pin, category: category), nil) } }
            }
            Button("Open in Apple Maps", systemImage: "apple.logo") {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate)); item.name = pin.name; item.openInMaps()
            }
            Button("Open in Google Maps", systemImage: "globe") {
                var url = URLComponents(string: "https://www.google.com/maps/search/")!
                url.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(pin.coordinate.latitude),\(pin.coordinate.longitude)")]
                if let id = googlePlaceDetails?.placeID ?? pin.googlePlaceID { url.queryItems?.append(URLQueryItem(name: "query_place_id", value: id)) }
                if let destination = url.url { UIApplication.shared.open(destination) }
            }
            Button("I have been there", systemImage: "checkmark.seal") {
                let place = VisitedPlace(name: pin.city.nonEmpty ?? pin.name, countryCode: pin.boundaryCountryCode,
                    latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
                visitedStorage = VisitedPlace.encode(VisitedPlace.adding(place, to: visitedPlaces))
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(AppPalette.ink)
                .frame(width: 40, height: 40).background(Sketch.card, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More actions")
    }
    private func placeBottomBar(_ pin: WorkspaceMapPin, category: MapPlaceCategory, saved: Bool, tint: Color) -> some View {
        let pinned = savedPlaces.contains { $0.isPinned && samePlace($0, pin) }
        return HStack(spacing: 10) {
            Button {
                if saved { removeLocationSave(pin) }
                else if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) { savedPlaces[index].saved = true }
                else { savedPlaces.append(enrichedPlace(for: pin, category: category)) }
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(saved ? Sketch.coral : AppPalette.ink)
                    .frame(width: 52, height: 52).background(Sketch.card, in: Circle())
                    .overlay(Circle().strokeBorder(Sketch.rule, lineWidth: 0.7))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel(saved ? "Saved. Remove from saves" : "Save")
            // Pin plus a clickable edge: the main part pins to the general set, the edge picks a premade
            // set (or a custom pin) instead.
            HStack(spacing: 0) {
                Button { toggleLocationPin(pin, category: category) } label: {
                    Group {
                        if placeTypeSize.isAccessibilitySize { Image(systemName: pinned ? "mappin.circle.fill" : "mappin") }
                        else { Label(pinned ? "Pinned" : "Pin", systemImage: pinned ? "mappin.circle.fill" : "mappin").lineLimit(1).fixedSize() }
                    }
                    .font(Sketch.text(15, "Bold", relativeTo: .headline))
                    .foregroundStyle(pinned ? .white : AppPalette.ink)
                    .padding(.leading, 18).padding(.trailing, 10).frame(minWidth: 52).frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietPressStyle())
                .accessibilityLabel(pinned ? "Pinned. Remove pin" : "Pin to map")
                Rectangle().fill((pinned ? Color.white : AppPalette.ink).opacity(0.22)).frame(width: 1, height: 24)
                Menu {
                    Section("Pin to a set") {
                        ForEach(pinSetChoices, id: \.self) { name in
                            Button { pinToSet(pin, set: name, category: category) } label: {
                                if currentPinSet(pin) == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                            }
                        }
                    }
                    Button("General pins", systemImage: "mappin") { pinToSet(pin, set: nil, category: category) }
                    Button("Custom pin…", systemImage: "paintpalette") { beginCustomPin(pin, pinAsPrimary: true) }
                } label: {
                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(pinned ? .white : AppPalette.ink)
                        .frame(width: 38, height: 52).contentShape(Rectangle())
                }
                .accessibilityLabel("Choose a pin set or make a custom pin")
            }
            .background(pinned ? AnyShapeStyle(tint) : AnyShapeStyle(Sketch.card), in: Capsule())
            .overlay(Capsule().strokeBorder(pinned ? .clear : Sketch.rule, lineWidth: 0.7))
            .contextMenu { Button("Customize pin", systemImage: "paintpalette") { beginCustomPin(pin, pinAsPrimary: true) } }
            Button { beginDirections(to: pin) } label: {
                HStack(spacing: 8) {
                    if calculatingDirections { ProgressView().tint(colorScheme == .dark ? AppPalette.brand : .white) }
                    else { Image(systemName: "location.north.fill").font(.system(size: 14, weight: .bold)).rotationEffect(.degrees(45)) }
                    Text("Directions").font(Sketch.text(15, "Bold", relativeTo: .headline)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(colorScheme == .dark ? AppPalette.brand : .white).frame(maxWidth: .infinity).frame(height: 52)
                .background(colorScheme == .dark ? Color(hex: "F3EDE2") : AppPalette.brand, in: Capsule())
                .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            }
            .buttonStyle(QuietPressStyle()).disabled(calculatingDirections)
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
        .background {
            LinearGradient(colors: [Sketch.paper.opacity(0), Sketch.paper.opacity(0.94), Sketch.paper], startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
        }
    }
    private func placeContactActions(_ pin: WorkspaceMapPin, phone: String?, website: String?) -> some View {
        HStack(spacing: 10) {
            Button { beginDirections(to: pin) } label: {
                Label("Directions", systemImage: "arrow.turn.up.right").font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 42).librarySurface(radius: 16)
            }.buttonStyle(QuietPressStyle()).disabled(calculatingDirections)

            if let phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) {
                    Label("Call", systemImage: "phone").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42).librarySurface(radius: 16)
                }.accessibilityLabel("Call \(phone)")
            }
            if let url = website.flatMap(URL.init(string:)) {
                Link(destination: url) {
                    Label("Website", systemImage: "globe").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 42).librarySurface(radius: 16)
                }
            }
        }.foregroundStyle(AppPalette.ink)
    }
    private func placeActionBar(_ pin: WorkspaceMapPin, category: MapPlaceCategory, saved: Bool) -> some View {
        let pinned = savedPlaces.contains { $0.isPinned && samePlace($0, pin) }
        return HStack(spacing: 8) {
            Button {
                if saved { removeLocationSave(pin) }
                else if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) { savedPlaces[index].saved = true }
                else { savedPlaces.append(enrichedPlace(for: pin, category: category)) }
            } label: { placeActionLabel(saved ? "Saved" : "Save", symbol: saved ? "heart.fill" : "heart", tint: saved ? .pink : AppPalette.ink) }
                .buttonStyle(QuietPressStyle())
            Button { toggleLocationPin(pin, category: category) } label: {
                placeActionLabel(pinned ? "Pinned" : "Pin", symbol: pinned ? "mappin.circle.fill" : "mappin", tint: pinned ? category.tint : AppPalette.ink)
            }.buttonStyle(QuietPressStyle()).contextMenu {
                Button("Customize pin", systemImage: "paintpalette") { beginCustomPin(pin, pinAsPrimary: true) }
            }
            Menu {
                if let onSaveTripPin {
                    Menu("Save to trip", systemImage: "airplane") {
                        ForEach(tripChoices) { trip in
                            Button(trip.title) { onSaveTripPin(trip.id, enrichedPlace(for: pin, category: category, tripID: trip.id)) }
                        }
                        if let onNewTrip { Button("New trip", systemImage: "plus") { dismissPlacePanel(then: onNewTrip) } }
                    }
                }
                Menu("Notes", systemImage: "note.text") {
                    if let onAddToNote {
                        ForEach(noteChoices) { note in
                            Button(note.title) { dismissPlacePanel { onAddToNote(enrichedPlace(for: pin, category: category), note.id) } }
                        }
                    }
                    Button("New note", systemImage: "plus") { dismissPlacePanel { onCreateNote?(enrichedPlace(for: pin, category: category), nil) } }
                }
                Button("Open in Apple Maps", systemImage: "apple.logo") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate)); item.name = pin.name; item.openInMaps()
                }
                Button("Open in Google Maps", systemImage: "globe") {
                    var url = URLComponents(string: "https://www.google.com/maps/search/")!
                    url.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "\(pin.coordinate.latitude),\(pin.coordinate.longitude)")]
                    if let id = googlePlaceDetails?.placeID ?? pin.googlePlaceID { url.queryItems?.append(URLQueryItem(name: "query_place_id", value: id)) }
                    if let destination = url.url { UIApplication.shared.open(destination) }
                }
                Button("I have been there", systemImage: "checkmark.seal") {
                    let place = VisitedPlace(name: pin.city.nonEmpty ?? pin.name, countryCode: pin.boundaryCountryCode,
                        latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
                    visitedStorage = VisitedPlace.encode(VisitedPlace.adding(place, to: visitedPlaces))
                }
            } label: { placeActionLabel("More", symbol: "ellipsis", tint: AppPalette.ink) }
        }.padding(.vertical, 2)
    }
    private func placeActionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(height: 20)
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }.foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 38)
            .modifier(AdaptiveGlassControl(shape: .capsule))
    }
    private func dismissPlacePanel(then action: @escaping () -> Void) {
        pendingPlacePanelAction = action
        selectedPin = nil
    }
    /// Ready-made sets, followed by any sets the traveler already made.
    private var pinSetChoices: [String] {
        let premade = ["Must eat", "Coffee & brunch", "Nightlife", "Sights", "Hidden gems", "Beaches & nature", "Shopping", "Where to stay"]
        return premade + customPinCategories.filter { name in !premade.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame } }
    }
    private func currentPinSet(_ pin: WorkspaceMapPin) -> String? {
        savedPlaces.first { $0.isPinned && samePlace($0, pin) }?.customCategory?.nonEmpty
    }
    /// Pins the place into a named set (nil = the general pins) without touching its saved state.
    private func pinToSet(_ pin: WorkspaceMapPin, set: String?, category: MapPlaceCategory) {
        TrippyHaptics.success()
        if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) {
            savedPlaces[index].pinned = true
            savedPlaces[index].customCategory = set
        } else {
            var place = enrichedPlace(for: pin, category: category)
            place.pinned = true; place.saved = false; place.customCategory = set
            savedPlaces.append(place)
        }
    }
    private func toggleLocationPin(_ pin: WorkspaceMapPin, category: MapPlaceCategory) {
        if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) {
            savedPlaces[index].pinned = !savedPlaces[index].isPinned
            if !savedPlaces[index].isPinned && !savedPlaces[index].isSaved { savedPlaces.remove(at: index) }
        } else {
            var place = enrichedPlace(for: pin, category: category)
            place.pinned = true; place.saved = false; savedPlaces.append(place)
        }
    }
    private func removeLocationSave(_ pin: WorkspaceMapPin) {
        guard let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) else { return }
        if savedPlaces[index].isPinned { savedPlaces[index].saved = false }
        else { savedPlaces.remove(at: index) }
    }
    private func customPinIdentityEditor(_ request: MapPinIdentityRequest) -> some View {
        let saved = request.tripID == nil ? savedPlaces.first { samePlace($0, request.pin) } : nil
        let original = saved ?? enrichedPlace(for: request.pin, category: selectedPinCategory ?? request.pin.category, tripID: request.tripID)
        return MarkIdentityEditor(title: "Customize pin", name: original.name, appearance: original.appearance,
            defaultSymbol: request.tripID == nil && !request.pinAsPrimary && !original.isPinned ? "heart.fill" : "mappin", tone: .pins,
            category: original.customCategory, allowsCategory: true) { name, appearance, category in
                var place = original
                place.name = name; place.appearance = appearance; place.customCategory = category
                if request.tripID == nil {
                    if request.pinAsPrimary { place.pinned = true; if saved == nil { place.saved = false } }
                    else { place.saved = true }
                }
                if let tripID = request.tripID { onSaveTripPin?(tripID, place) }
                else if let index = savedPlaces.firstIndex(where: { $0.id == place.id }) { savedPlaces[index] = place }
                else { savedPlaces.append(place) }
            }
    }
    private func beginCustomPin(_ pin: WorkspaceMapPin, tripID: UUID? = nil, pinAsPrimary: Bool = false) {
        dismissPlacePanel { customPinRequest = MapPinIdentityRequest(pin: pin, tripID: tripID, pinAsPrimary: pinAsPrimary) }
    }
    private func enrichedPlace(for pin: WorkspaceMapPin, category: MapPlaceCategory, tripID: UUID? = nil) -> PersonalPlace {
        let target = tripID.flatMap { id in pins.first { $0.tripID == id && ($0.placeID ?? $0.id) == (pin.placeID ?? pin.id) }?.personalPlace }
        var place = target ?? (tripID != nil && pin.layer != "search" ? pin.personalPlace : (savedPlaces.first { samePlace($0, pin) } ?? pin.personalPlace))
        place.category = category
        place.googlePlaceID = pin.googlePlaceID ?? resolvedGooglePlaceIDs[pin.id] ?? place.googlePlaceID
        return place
    }
    private func relatedTikTokMentions(for pin: WorkspaceMapPin) -> [SocialPlaceMention] {
        let target = pin.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return socialPlaces.filter { mention in
            let candidate = mention.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if pin.searchKind == .area,
               [pin.name, pin.city].contains(where: { !$0.isEmpty && mention.city?.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                return true
            }
            if target == candidate { return true }
            if let latitude = mention.latitude, let longitude = mention.longitude {
                let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                if distance <= 180 { return true }
            }
            return !(pin.city.isEmpty || mention.city == nil) && mention.city!.localizedCaseInsensitiveCompare(pin.city) == .orderedSame
                && candidate.localizedCaseInsensitiveContains(target)
        }
    }
    private func retainGoogleReferences(_ records: [[String: String]]) async {
        guard !records.isEmpty, !placesAccessToken.isEmpty,
              let url = URL(string: placesBaseURL + "/api/places/retain") else { return }
        for offset in stride(from: 0, to: records.count, by: 100) {
            guard !Task.isCancelled else { return }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = "POST"
            request.setValue("Bearer \(placesAccessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
            if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["places": Array(records[offset..<min(offset + 100, records.count)])])
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode != 200 { TrippyPerformance.mark("catalog.unavailable") }
            } catch { if !Task.isCancelled { TrippyPerformance.mark("catalog.unavailable") } }
        }
    }
    private var retainedPlaceReferences: [[String: String]] {
        let personal = savedPlaces.compactMap { place -> [String: String]? in
            guard let id = place.googlePlaceID else { return nil }
            return ["placeID": id, "source": place.isPinned ? "pins" : "saves"]
        }
        let imported = pins.compactMap { pin -> [String: String]? in
            guard let id = pin.googlePlaceID else { return nil }
            return ["placeID": id, "source": pin.tripID != nil ? "trips" : (pin.layer.contains("video") || pin.layer.contains("tiktok")) ? "videos" : pin.layer == "saved" ? "saves" : "pins"]
        }
        return personal + imported
    }
    /// Card data: Apple's place for our own layout (free), plus a stored Google place ID for the
    /// UI Kit rating line on saved, pinned and TikTok places. No Google content is fetched or kept here.
    private func loadGoogleDetails(for pin: WorkspaceMapPin) async {
        googlePlaceDetails = nil
        googleDetailsError = nil
        appleMapItem = nil
        kitPlaceID = nil
        guard pin.searchKind != .area else { return }
        loadingGoogleDetails = true
        defer { loadingGoogleDetails = false }
        if isLibraryPlace(pin) { Task { await loadKitPlace(for: pin) } }
        let item = await ApplePlaceLookup.mapItem(name: pin.name, coordinate: pin.coordinate)
        guard !Task.isCancelled, selectedPin?.id == pin.id else { return }
        appleMapItem = item
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TrippyAppleCardDemo") { try? await Task.sleep(for: .seconds(1.5)); appleCardItem = item }
        #endif
        googlePlaceDetails = GooglePlaceDetails(placeID: "", name: pin.name,
            address: item?.placemark.title ?? pin.address,
            latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude,
            primaryType: item.map(ApplePlaceLookup.categoryName) ?? "",
            rating: nil, reviewCount: nil, openNow: nil, openingHours: [],
            phoneNumber: item?.phoneNumber ?? pin.phoneNumber, websiteURL: item?.url?.absoluteString ?? pin.websiteURL,
            googleMapsURL: nil, summary: "", photos: [], reviews: [])
    }
    private func isLibraryPlace(_ pin: WorkspaceMapPin) -> Bool {
        savedPlaces.contains { ($0.isSaved || $0.isPinned) && samePlace($0, pin) } || !relatedTikTokMentions(for: pin).isEmpty
    }
    private func loadKitPlace(for pin: WorkspaceMapPin) async {
        guard await GooglePlacesKit.shared.prepare(baseURL: placesBaseURL, token: placesAccessToken) else { return }
        var placeID = pin.googlePlaceID ?? resolvedGooglePlaceIDs[pin.id]
            ?? savedPlaces.first(where: { samePlace($0, pin) })?.googlePlaceID
        if placeID == nil {
            placeID = await GooglePlacesKit.shared.matchPlaceID(name: pin.name, coordinate: pin.coordinate,
                                                                baseURL: placesBaseURL, token: placesAccessToken)
        }
        guard let placeID, !Task.isCancelled, selectedPin?.id == pin.id else { return }
        resolvedGooglePlaceIDs[pin.id] = placeID
        if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }), savedPlaces[index].googlePlaceID == nil {
            savedPlaces[index].googlePlaceID = placeID
        }
        kitPlaceID = placeID
    }
    private func cityTripCount(for pin: WorkspaceMapPin) -> Int? {
        let names = [pin.name, pin.city]
        let count = cityPins.filter { candidate in names.contains { $0.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame } }
            .compactMap { Int($0.badge ?? "0") }.reduce(0, +)
        return count == 0 ? nil : count
    }
    private func celebrate(_ category: MapPlaceCategory) {
        TrippyHaptics.success()
        let symbols: [MapPlaceCategory: String] = [.restaurants: "🍜", .streetFood: "🌮", .burgers: "🍔", .seafood: "🦐", .vegan: "🥑", .coffee: "☕️", .brunch: "🥐", .bars: "🍸", .clubs: "🎶", .parks: "🌿", .sights: "✨", .shopping: "🛍️", .touristShops: "🎁", .groceries: "🧺", .metro: "🚇", .other: "📍"]
        withAnimation { celebrationEmoji = symbols[category] ?? "✨" }
        Task { try? await Task.sleep(for: .milliseconds(850)); withAnimation { celebrationEmoji = nil } }
    }
    func samePlace(_ place: PersonalPlace, _ pin: WorkspaceMapPin) -> Bool {
        if place.id == (pin.placeID ?? pin.id) { return true }
        let distance = CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
        return distance < 30 && place.name.localizedCaseInsensitiveCompare(pin.name) == .orderedSame
    }
    func fitMap() {
        // A trip frames its planned stops; far-off suggestions shouldn't zoom the city out.
        let planned = mapMarkers.filter { $0.layer == "planned" }.map(\.coordinate)
        let coordinates = planned.count > 1 ? planned : mapMarkers.map(\.coordinate)
        #if DEBUG
        let debugSpan = UserDefaults.standard.double(forKey: "TrippyTripSpan")
        if debugSpan > 0, let first = coordinates.first {
            nativeCameraRequestID = UUID(); position = .region(.init(center: first, span: .init(latitudeDelta: debugSpan, longitudeDelta: debugSpan)))
            return
        }
        #endif
        if coordinates.isEmpty {
            if let fallback { nativeCameraRequestID = UUID(); position = .region(.init(center: fallback, span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08))) }
            else { nativeCameraRequestID = UUID(); position = .automatic }
            return
        }
        let latitudes = coordinates.map(\.latitude), longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!, minLon = longitudes.min()!, maxLon = longitudes.max()!
        nativeCameraRequestID = UUID(); position = .region(.init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                span: .init(latitudeDelta: max(0.015, (maxLat - minLat) * 1.8), longitudeDelta: max(0.015, (maxLon - minLon) * 1.5))))
    }
    private func disableCurrentLocation() {
        currentLocationEnabled = false
        centerWhenLocationArrives = false
        locationError = nil
        if pendingDirectionsPin == nil { locationService.cancelCurrentLocation() }
    }
    private func centerOnCurrentPosition() {
        currentLocationEnabled = true
        if let location = locationService.location, Date().timeIntervalSince(location.timestamp) < 120 {
            centerMap(on: location)
        } else {
            centerWhenLocationArrives = true
            locationService.requestCurrentLocation()
        }
    }
    private func centerMap(on location: CLLocation) {
        withAnimation(.easeInOut(duration: 0.35)) {
            nativeCameraRequestID = UUID(); position = .region(.init(center: location.coordinate,
                                     span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))
        }
    }
    /// Opens directions mode for a place: start (your location), destination, mode and time, routes from Apple Maps.
    /// Nothing opens by itself; the steps list appears only from the Steps button.
    private func beginDirections(to pin: WorkspaceMapPin) {
        guard CLLocationCoordinate2DIsValid(pin.coordinate) else { directionsError = "This place doesn't have a usable location yet."; return }
        directions.from = .currentLocation
        directions.to = .place(name: pin.name, coordinate: pin.coordinate)
        if let here = locationService.location {
            let metres = here.distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
            directions.transport = metres < 2_500 ? .walk : .car
        }
        dismissPlacePanel {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) { directionsActive = true }
        }
        if locationService.location == nil || Date().timeIntervalSince(locationService.location!.timestamp) > 120 {
            locationService.requestCurrentLocation()
        }
    }
    private func locationDidUpdate() {
        guard let location = locationService.location else { return }
        HomeCityStore.remember(location.coordinate)
        if currentLocationEnabled && centerWhenLocationArrives {
            centerWhenLocationArrives = false
            centerMap(on: location)
        }
        if let pin = pendingDirectionsPin {
            pendingDirectionsPin = nil
            Task { await calculateDirections(to: pin, from: location) }
        }
        if directionsActive && directions.route == nil && directions.usesCurrentLocation {
            directions.recalculate(location: location)
        }
    }
    /// Search, options and filters, or the directions panel while directions are open.
    private var mapTopChrome: some View {
            VStack(alignment: .leading, spacing: 16) {
                if directionsActive {
                    DirectionsTopPanel(model: directions, onPick: { directionsPicker = DirectionsPickerTarget(start: $0) })
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                // Inside a trip the header card is the only chrome; search and map options live in it.
                if showMapSearch || destination.isEmpty {
                HStack(spacing: 10) {
                    searchBar
                    if !showMapSearch { mapOptionsMenu }
                    if showMapSearch || (destination.isEmpty && onNewTrip != nil) { searchCloseOrCreateButton }
                }
                }
                if !showMapSearch && !destination.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { header(); filterDrawer(layers: true, opensUp: false) }
                }
                if !showMapSearch && destination.isEmpty { mapFilterCarousel }
                }
            }.frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.42, dampingFraction: 0.85), value: directionsActive)
                .padding(.horizontal, 20).padding(.top, 8)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { topControlsHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, height in topControlsHeight = height }
                    }
                }
    }
    /// Directions mode's map layers (routes card, picker, recalculation, camera), split out of the canvas body
    /// so the compiler can type-check it.
    func directionsLayer(_ content: AnyView) -> AnyView {
        AnyView(content
        .overlay(alignment: .bottom) {
            if directionsActive {
                DirectionsRoutesCard(model: directions, onAppleMaps: { directions.openInAppleMaps(location: locationService.location) },
                                     onClose: closeDirections,
                                     onTransitLines: { directions.loadLines(location: locationService.location, baseURL: placesBaseURL, token: placesAccessToken) })
                    .frame(maxWidth: 720)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preference(key: DirectionsActiveKey.self, value: directionsActive)
        .sheet(item: $directionsPicker) { target in
            DirectionsPlacePicker(title: target.start ? "Start" : "Destination", near: locationService.location?.coordinate ?? visibleRegion?.center) { endpoint in
                if target.start { directions.from = endpoint } else { directions.to = endpoint }
            }
        }
        .task(id: directionsActive ? directionsKey : "directions:off") {
            guard directionsActive else { return }
            if directions.usesCurrentLocation, locationService.location == nil {
                locationService.requestCurrentLocation()
            }
            directions.recalculate(location: locationService.location)
        }
        .onChange(of: directions.route) { _, route in
            directionsRoute = route
            guard let route else { return }
            frameRoute(route)
        }
        )
    }
    /// The route fills the space between the directions panel (top) and the routes card (bottom).
    private func frameRoute(_ route: MKRoute) {
        let rect = route.polyline.boundingMapRect
        let side = max(rect.width, rect.height)
        // Extra room above for the panel and below for the routes card.
        let framed = MKMapRect(x: rect.midX - side * 0.85, y: rect.minY - side * 1.25, width: side * 1.7, height: rect.height + side * 2.6)
        withAnimation(.easeInOut(duration: 0.45)) { nativeCameraRequestID = UUID(); position = .rect(framed) }
    }
    private func closeDirections() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.85)) {
            directionsActive = false
            directionsRoute = nil
        }
        directions.clear()
    }
    private var directionsKey: String {
        func key(_ endpoint: DirectionsEndpoint) -> String {
            switch endpoint { case .currentLocation: "here"; case .place(let name, let c): "\(name):\(c.latitude),\(c.longitude)" }
        }
        return [key(directions.from), key(directions.to), directions.transport.rawValue, directions.timing.rawValue,
                directions.timing == .now ? "" : String(Int(directions.date.timeIntervalSince1970 / 60))].joined(separator: "|")
    }
    private func calculateDirections(to pin: WorkspaceMapPin, from origin: CLLocation) async {
        calculatingDirections = true
        defer { calculatingDirections = false }
        guard CLLocationCoordinate2DIsValid(pin.coordinate), CLLocationCoordinate2DIsValid(origin.coordinate) else {
            directionsError = "This place doesn't have a usable location yet."
            return
        }
        // Apple Maps decides what is possible: short trips walk, longer ones drive, then transit.
        let metres = origin.distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
        let modes: [MKDirectionsTransportType] = metres < 3_000 ? [.walking, .automobile, .transit] : [.automobile, .transit, .walking]
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        destinationItem.name = pin.name
        var lastError: Error?
        for mode in modes {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
            request.destination = destinationItem
            request.transportType = mode
            request.requestsAlternateRoutes = false
            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else { continue }
                directionsRoute = route
                withAnimation(.easeInOut(duration: 0.45)) {
                    nativeCameraRequestID = UUID(); position = .rect(route.polyline.boundingMapRect)
                }
                selectedPin = nil
                try? await Task.sleep(for: .milliseconds(320))
                showDirections = true
                return
            } catch { lastError = error; if Task.isCancelled { return } }
        }
        // No in-app route (far away, across water, or no data): hand the trip to Apple Maps itself.
        directionsFallbackItem = destinationItem
        _ = lastError
        directionsError = "Apple Maps couldn't draw a route to \(pin.name) from where you are. You can open it in Apple Maps instead."
    }
    func routeKey(_ leg: TripRouteLeg) -> String {
        "\(leg.from.latitude),\(leg.from.longitude):\(leg.to.latitude),\(leg.to.longitude):\(leg.walking)"
    }
    func routeColor(_ day: Int) -> Color { TripDayPalette.color(day, dark: darkMode) }
    func updateRoutes() async {
        // Clearing first ensures a changed itinerary never shows a stale path.
        renderedRoutes = [:]; failedRoutes = 0
        routing = !routes.isEmpty
        let taskID = routeTaskID
        for leg in routes {
            guard !Task.isCancelled, taskID == routeTaskID else { return }
            let key = routeKey(leg)
            if let cached = routeCache[key] { renderedRoutes[key] = cached; continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: leg.from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: leg.to))
            request.transportType = leg.walking ? .walking : .automobile
            let directions = MKDirections(request: request)
            do {
                let response = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled, taskID == routeTaskID else { return }
                if let route = response.routes.first { routeCache[key] = route; renderedRoutes[key] = route }
                else { failedRoutes += 1 }
            } catch {
                guard !Task.isCancelled, taskID == routeTaskID else { return }
                failedRoutes += 1
            }
        }
        if !Task.isCancelled { routing = false }
    }
}

// A full-screen journey, with the supplied brand artwork as its signature detail.
// MARK: - Planning workshop (live planning screen)
/// What the planner is doing, read from the service's status JSON (diagnostics events + result).
struct PlanningLive: Equatable {
    struct Search: Equatable { let category: String; var count: Int?; var failed = false }
    struct DayPreview: Equatable, Identifiable { let id: Int; let date: String; let title: String; let summary: String; let stops: Int }
    var connected = false
    var startedAt: Date? = nil
    var libraryItems = 0
    var tripDays = 0
    var travelers = 0
    var plannedSearches: Int? = nil
    var searches: [Search] = []
    var composing = false
    var guideStarted = false
    var guideListings: Int? = nil
    var guideMatched: Int? = nil
    var notesStarted = false
    var notesStatus: String? = nil
    var notesModel: String? = nil
    var notesWritten: Int? = nil
    var elapsed: Double? = nil
    var places: Int? = nil
    var stops: Int? = nil
    var days: [DayPreview] = []
    var finished = false

    var placesFound: Int { searches.compactMap(\.count).reduce(0, +) }

    mutating func absorb(status json: [String: Any]) {
        connected = true
        let diagnostics = json["diagnostics"] as? [String: Any] ?? [:]
        if let value = diagnostics["elapsed_seconds"] as? Double { elapsed = value }
        if let value = diagnostics["planned_discovery_tasks"] as? Int { plannedSearches = value }
        for event in diagnostics["events"] as? [[String: Any]] ?? [] {
            let name = event["event"] as? String ?? ""
            let task = event["task"] as? String ?? ""
            switch name {
            case "pipeline_started": plannedSearches = event["planned_discovery_tasks"] as? Int ?? plannedSearches
            case "task_started" where task.hasPrefix("places-"):
                let category = String(task.dropFirst(7))
                if !searches.contains(where: { $0.category == category }) { searches.append(Search(category: category)) }
            case "task_completed" where task.hasPrefix("places-"):
                if let index = searches.firstIndex(where: { $0.category == String(task.dropFirst(7)) }) { searches[index].count = event["place_count"] as? Int ?? 0 }
            case "task_failed" where task.hasPrefix("places-"):
                if let index = searches.firstIndex(where: { $0.category == String(task.dropFirst(7)) }) { searches[index].failed = true }
            case "guide_started": composing = true; guideStarted = true
            case "guide_completed": guideListings = event["listings"] as? Int; guideMatched = event["matched"] as? Int
            case "notes_started": notesStarted = true
            case "notes_completed":
                notesStatus = event["status"] as? String; notesModel = event["model"] as? String; notesWritten = event["stops_written"] as? Int
            default: break
            }
        }
        if (json["step"] as? String) == "composing" { composing = true }
        if let result = json["result"] as? [String: Any] { absorb(result: result) }
    }

    mutating func absorb(result: [String: Any]) {
        finished = true; composing = true
        places = (result["places"] as? [Any])?.count
        let report = result["pipeline_report"] as? [String: Any] ?? [:]
        if let notes = report["notes"] as? [String: Any] {
            notesStatus = notesStatus ?? notes["status"] as? String
            notesModel = notesModel ?? notes["model"] as? String
            notesWritten = notesWritten ?? notes["stops_written"] as? Int
        }
        let rawDays = (result["itinerary"] as? [String: Any])?["days"] as? [[String: Any]] ?? []
        days = rawDays.enumerated().map { index, day in
            let stops = day["stops"] as? [[String: Any]] ?? []
            let theme = (day["theme"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            // Without notes the engine's placeholder theme says nothing; name the day by its first stops.
            let named = stops.prefix(2).compactMap { $0["activity"] as? String }.joined(separator: " · ")
            let title = theme.isEmpty || theme == "Η ημέρα σου" ? (named.isEmpty ? "Day \(index + 1)" : named) : theme
            return DayPreview(id: index, date: day["date"] as? String ?? "", title: title,
                              summary: day["summary"] as? String ?? "", stops: stops.count)
        }
        stops = days.map(\.stops).reduce(0, +)
    }

    static func categoryTitle(_ category: String) -> String {
        switch category {
        case "attraction": "Sights"; case "food": "Food"; case "coffee": "Coffee"; case "museum": "Museums"
        case "nature": "Nature"; case "shopping": "Shops"; case "bar": "Bars"; case "club": "Clubs"; case "excursion": "Day trips"
        default: category.capitalized
        }
    }

    #if DEBUG
    /// `-TrippyPlanningDemo search|notes|done|quota` for screenshots.
    static var demo: PlanningLive? {
        guard let stage = UserDefaults.standard.string(forKey: "TrippyPlanningDemo") else { return nil }
        var live = PlanningLive(connected: true, startedAt: .now.addingTimeInterval(-38), libraryItems: 4, tripDays: 3, travelers: 2, plannedSearches: 3)
        live.searches = [Search(category: "attraction", count: 12), Search(category: "food", count: stage == "search" ? nil : 10)]
        if stage == "search" { return live }
        live.searches.append(Search(category: "coffee", count: 6))
        live.composing = true; live.guideStarted = true; live.guideListings = 99; live.guideMatched = 4; live.notesStarted = true
        if stage == "notes" { return live }
        live.notesStatus = stage == "quota" ? "failed" : "written"; live.notesModel = stage == "quota" ? nil : "gemini-3.6-flash"; live.notesWritten = 12
        live.finished = true; live.places = 28; live.stops = 12; live.elapsed = 64
        let titles = stage == "quota" ? ["Piazza Navona · Cantina e Cucina", "Pantheon · Tonnarello", "Colosseum · Trattoria Vecchia Roma"] : ["Piazzas and pasta", "Ancient Rome on foot", "Fountains and views"]
        let summaries = stage == "quota" ? ["", "", ""] : ["Morning in the old squares, carbonara for lunch, Campo de' Fiori at golden hour.",
                                                             "The Pantheon first, then the Forum while the light is soft.",
                                                             "Colosseum at opening, Trevi before the crowds, dinner in Monti."]
        live.days = (0..<3).map { DayPreview(id: $0, date: "2026-12-1\($0)", title: titles[$0], summary: summaries[$0], stops: 4) }
        return live
    }
    #endif
}

/// The seven real steps of the personal-places pipeline.
private enum PlanningStage: Int, CaseIterable, Identifiable {
    case connect, library, search, guide, compose, notes, save
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .connect: "Connect"; case .library: "Your saved places"; case .search: "Google Maps"
        case .guide: "Local guide"; case .compose: "Build the days"; case .notes: "Write the notes"; case .save: "Save to your trip"
        }
    }
    var symbol: String {
        switch self {
        case .connect: "network"; case .library: "heart.text.square"; case .search: "map"
        case .guide: "book.pages"; case .compose: "calendar.day.timeline.left"; case .notes: "sparkles"; case .save: "tray.and.arrow.down"
        }
    }
}

private enum PlanningStepState: Equatable { case waiting, active, done, skipped, stopped }

private struct ResearchProgressScreen: View {
    let destination: String
    let operations: [ResearchOperation]
    let currentStep: Int
    let completedSteps: Set<Int>
    let running: Bool
    let saved: Bool
    let partial: Bool
    let error: String?
    let needsServiceUpdate: Bool
    let canRecover: Bool
    let resuming: Bool
    var needsNewRequest: Bool = false
    var diagnostic: String? = nil
    var phaseStates: [Int: String] = [:]
    var live = PlanningLive()
    let onClose: () -> Void
    let onRetry: () -> Void
    let onSettings: () -> Void
    let onRecover: () -> Void
    let onOpenPlan: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var doodle: Doodle { Doodle.suggested(title: "", city: destination) }
    private var city: String { destination.isEmpty ? "Your next trip" : destination }

    // MARK: state of each step
    private func state(_ stage: PlanningStage) -> PlanningStepState {
        let halted = error != nil
        let current = currentStage
        switch stage {
        case .save: return saved ? .done : (halted && current == .save ? .stopped : current == .save ? .active : .waiting)
        case .notes:
            if live.notesStatus == "written" { return .done }
            if live.notesStatus != nil || (live.finished && !live.notesStarted) { return .skipped }
            break
        case .guide:
            if live.guideListings != nil { return .done }
            if live.finished && !live.guideStarted { return .skipped }
        default: break
        }
        if stage.rawValue < current.rawValue { return .done }
        if stage == current { return halted ? .stopped : (running ? .active : .waiting) }
        return .waiting
    }
    private var currentStage: PlanningStage {
        if saved { return .save }
        if live.finished { return .save }
        if live.notesStarted { return .notes }
        if live.guideStarted { return live.guideListings == nil ? .guide : .notes }
        if live.composing { return .compose }
        if !live.searches.isEmpty { return live.searches.allSatisfy({ $0.count != nil }) && live.searches.count >= (live.plannedSearches ?? 0) ? .compose : .search }
        if live.connected || currentStep >= 2 { return .library }
        return .connect
    }

    private func detail(_ stage: PlanningStage) -> String {
        switch stage {
        case .connect: return live.connected || currentStep >= 2 ? "Planning service is on it" : "Reaching the planning service…"
        case .library: return live.libraryItems > 0 ? "\(live.libraryItems) saved \(live.libraryItems == 1 ? "place goes" : "places go") in first" : "Starting fresh: no saved places for here yet"
        case .search:
            if live.placesFound > 0 { return "\(live.placesFound) places to choose from" }
            return "Looking for what fits your interests…"
        case .guide:
            if let listings = live.guideListings {
                if listings == 0 { return "No Wikivoyage article for this place" }
                return "\(listings) Wikivoyage tips · \(live.guideMatched ?? 0) about your stops"
            }
            return state(.guide) == .skipped ? "Not used for this plan" : "Reading Wikivoyage for local knowledge…"
        case .compose:
            if let stops = live.stops, !live.days.isEmpty { return "\(stops) stops over \(live.days.count) \(live.days.count == 1 ? "day" : "days")" }
            return "Grouping nearby places, meals at meal times"
        case .notes:
            switch live.notesStatus {
            case "written": return "Day titles and a reason for each stop" + (live.notesModel.map { " · \(modelName($0))" } ?? "")
            case "failed": return "Free Gemini quota is busy; saved without notes"
            case .some: return "Skipped for this plan"
            case nil: return live.finished ? "Notes are off on this service" : "Gemini writes every day in one go…"
            }
        case .save: return saved ? (partial ? "Saved · a few things to check" : "Saved to your trip") : "Keeping your edits and the new plan"
        }
    }
    private func modelName(_ id: String) -> String {
        id.replacingOccurrences(of: "gemini-", with: "Gemini ").replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var headline: String {
        if saved { return partial ? "Your plan is here" : "Your trip is ready" }
        if needsServiceUpdate { return "Before we start" }
        if error != nil { return "Planning paused" }
        switch currentStage {
        case .connect: return "Packing the request"
        case .library: return "Starting from your places"
        case .search: return "Scouting \(city)"
        case .guide: return "Asking the locals"
        case .compose: return "Drawing your days"
        case .notes: return "Writing your days"
        case .save: return "Almost there"
        }
    }
    private var eyebrow: String {
        var parts = ["PLANNING"]
        if live.tripDays > 0 { parts.append("\(live.tripDays) \(live.tripDays == 1 ? "DAY" : "DAYS")") }
        if live.travelers > 0 { parts.append("\(live.travelers) \(live.travelers == 1 ? "TRAVELLER" : "TRAVELLERS")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow).font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkSoft)
                    Text(city).font(Sketch.display(.largeTitle, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine)
                ticket
                if !live.days.isEmpty && (saved || live.finished) { daysPreview }
                timeline
                if let error { errorCard(error) }
                if saved, let diagnostic {
                    DisclosureGroup("Plan and support details") {
                        Text(diagnostic).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                        Button("Copy details") { UIPasteboard.general.string = diagnostic }
                    }.font(Sketch.text(13, relativeTo: .caption)).tint(Sketch.ink)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Sketch.ink)
        .background(PaperBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .interactiveDismissDisabled(running)
        .environment(\.layoutDirection, .leftToRight)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: live)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: saved)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            TrippyIconView(icon: .suitcase, size: 20, weight: 2, animated: running).foregroundStyle(Sketch.clay)
            Text("trippy").font(Sketch.display(.headline, weight: .bold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Sketch.ink)
                    .frame(width: 44, height: 44).raisedCircle()
            }
            .buttonStyle(QuietPressStyle()).accessibilityLabel("Close")
        }
    }

    // MARK: ticket — the live card
    private var ticket: some View {
        VStack(spacing: 0) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
                ZStack {
                    Circle().fill(Sketch.coral.opacity(0.14))
                    if running && error == nil && !reduceMotion {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
                            Circle().trim(from: 0, to: 0.22).stroke(Sketch.coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(angle)).padding(2)
                        }
                    }
                    DoodleView(doodle: doodle, tint: Sketch.coral, lineWidth: 2).padding(14)
                    if saved {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Sketch.paper)
                            .frame(width: 24, height: 24).background(Circle().fill(Sketch.sage))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 72, height: 72).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if typeSize.isAccessibilitySize { clock }
                    Text(headline).font(Sketch.display(.title2, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .padding(.trailing, typeSize.isAccessibilitySize ? 0 : 40)
                    Text(detail(currentStage)).lineLimit(3)
                        .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .overlay(alignment: .topTrailing) { if !typeSize.isAccessibilitySize { clock.padding(12) } }
            perforation
            let stats = Group {
                StudioStat(value: live.placesFound > 0 ? "\(live.places ?? live.placesFound)" : "–", label: "places found")
                StudioStat(value: live.guideListings.map(String.init) ?? "–", label: "local tips")
                StudioStat(value: live.stops.map(String.init) ?? "–", label: "stops planned")
            }
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 0))) { stats }
            .padding(.horizontal, 16).padding(.vertical, 14)
            segments.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }
    /// Ticket tear line.
    private var perforation: some View {
        TearLine().stroke(Sketch.rule, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1, 6]))
            .frame(height: 2).padding(.horizontal, 16).accessibilityHidden(true)
    }
    /// Running time, top-right of the ticket.
    @ViewBuilder private var clock: some View {
        Group {
            if running, error == nil, let started = live.startedAt {
                Text(started, style: .timer).monospacedDigit()
            } else if saved, let elapsed = live.elapsed {
                Text("\(Int(elapsed.rounded()))s")
            }
        }
        .font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
        .padding(.horizontal, 8).padding(.vertical, 3).background(Sketch.paperDeep, in: Capsule())
    }
    /// One capsule per pipeline step.
    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(PlanningStage.allCases) { stage in
                let value = state(stage)
                Capsule().fill(value == .done ? Sketch.ink : value == .active ? Sketch.coral : value == .stopped ? Sketch.ochre
                               : value == .skipped ? Sketch.rule.opacity(0.6) : Sketch.rule)
                    .frame(height: 5)
                    .phaseAnimator(value == .active && !reduceMotion ? [1.0, 0.4] : [1.0]) { view, opacity in view.opacity(opacity) }
                        animation: { _ in .easeInOut(duration: 0.8) }
            }
        }.accessibilityHidden(true)
    }

    // MARK: timeline — how it's made
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioHeading(title: "How it's made")
            VStack(spacing: 0) {
                ForEach(PlanningStage.allCases) { stage in row(stage, last: stage == .save) }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 2)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        }
    }
    private func row(_ stage: PlanningStage, last: Bool) -> some View {
        let value = state(stage)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ResearchStepSymbol(symbol: stage.symbol, active: value == .active, completed: value == .done, stopped: value == .stopped)
                if !last {
                    Line().stroke(value == .done ? Sketch.ink.opacity(0.45) : Sketch.ink.opacity(0.14), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 5]))
                        .frame(width: 2).frame(maxHeight: .infinity).padding(.vertical, 4)
                }
            }.frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(stage.title).font(Sketch.text(15, "SemiBold", relativeTo: .subheadline))
                    if value == .skipped {
                        Text("skipped").font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Sketch.paperDeep, in: Capsule())
                    }
                }
                Text(detail(stage)).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if stage == .search && !live.searches.isEmpty { searchChips }
            }
            .padding(.top, 3).padding(.bottom, 16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(value == .waiting ? Sketch.inkFaint : Sketch.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value == .done ? "Done" : value == .active ? "In progress" : value == .stopped ? "Stopped" : value == .skipped ? "Skipped" : "Not started")
    }
    private var searchChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }
    @ViewBuilder private var chips: some View {
        ForEach(live.searches, id: \.category) { search in
            HStack(spacing: 5) {
                if search.count == nil && !search.failed { ProgressView().controlSize(.mini).tint(Sketch.coral) }
                Text(PlanningLive.categoryTitle(search.category)).font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                if let count = search.count { Text("\(count)").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
                if search.failed { Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Sketch.ochre) }
            }
            .padding(.horizontal, 10).frame(minHeight: 28)
            .background(Sketch.paperDeep, in: Capsule())
            .fixedSize()
        }
    }

    // MARK: ready — the days at a glance
    private var daysPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioHeading(title: "Your days", count: live.days.count)
            VStack(spacing: 10) {
                ForEach(live.days) { day in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Text("DAY").font(Sketch.text(9, "Bold", relativeTo: .caption2)).tracking(1)
                            Text("\(day.id + 1)").font(Sketch.display(.title2, weight: .bold))
                        }
                        .foregroundStyle(Sketch.coral).frame(width: 44, height: 52)
                        .background(Sketch.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title).font(Sketch.text(16, "Bold", relativeTo: .headline)).fixedSize(horizontal: false, vertical: true)
                            if !day.summary.isEmpty {
                                Text(day.summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("\(day.stops) \(day.stops == 1 ? "stop" : "stops")\(dayLabel(day.date).map { " · \($0)" } ?? "")")
                                .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    private func dayLabel(_ iso: String) -> String? {
        let parser = DateFormatter(); parser.calendar = Calendar(identifier: .gregorian); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return nil }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(needsServiceUpdate ? "Needs an update" : "Planning didn't finish",
                  systemImage: needsServiceUpdate ? "arrow.triangle.2.circlepath" : "exclamationmark.circle")
                .font(Sketch.text(16, "SemiBold", relativeTo: .body))
            Text(error).font(Sketch.text(15, relativeTo: .body)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(AppPalette.secondaryInk)
            if let diagnostic {
                DisclosureGroup("Support details") {
                    Text(diagnostic).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                }.font(Sketch.text(13, relativeTo: .caption)).tint(Sketch.ink)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Sketch.ochre.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func primaryAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        SketchPrimaryButton(title: title, symbol: symbol, enabled: true, action: action)
    }
    private var actions: some View {
        VStack(spacing: 8) {
            if saved {
                primaryAction("See your plan", symbol: "arrow.right", action: onOpenPlan)
            } else if canRecover {
                primaryAction("Recover the existing plan", symbol: "tray.and.arrow.down", action: onRecover)
            } else if needsServiceUpdate {
                primaryAction("Connection settings", symbol: "network", action: onSettings)
            } else if error != nil {
                primaryAction(needsNewRequest ? "Plan again" : resuming ? "Check status" : "Try again", symbol: "arrow.clockwise", action: onRetry)
            } else {
                Text(resuming ? "You can close this. Planning keeps running on the service." : "Usually about a minute. You can close this; it keeps going.")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }.padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background(Sketch.paper.ignoresSafeArea().shadow(color: .black.opacity(0.06), radius: 8, y: -4))
    }
}

private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) } }
}

private struct ResearchStepSymbol: View {
    let symbol: String
    let active: Bool
    let completed: Bool
    let stopped: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(active ? Sketch.clay.opacity(0.16) : completed ? Sketch.sage.opacity(0.16) : Sketch.paperDeep)
            Image(systemName: stopped ? "pause" : symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Sketch.clay : completed ? Sketch.sage : stopped ? Sketch.ochre : Sketch.inkFaint)
                .symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
            if active {
                if reduceMotion {
                    Circle().stroke(Sketch.clay, lineWidth: 2)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        Circle().trim(from: 0.12, to: 0.38).stroke(Sketch.clay, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180))
                    }
                }
            }
        }.frame(width: 40, height: 40).accessibilityHidden(true)
    }
}

// MARK: - Personal social-source library
private extension TripFlowView {
    func persistSocialLibrary() {
        guard !StudioDemo.enabled else { return } // sample data never reaches the real library
        do { try SocialLibraryStore.save(SocialLibraryDocument(sources: socialSources, places: socialPlaces, notes: travelNotes, takes: placeTakes)) }
        catch { showToast("Changes could not be saved. Check available storage.") }
    }
    func syncShareTargets() {
        SharedInbox.writeTargets(trips.map { ShareTarget(id: $0.id, title: $0.title, tripID: $0.id, kind: "trip") } + travelNotes.map { ShareTarget(id: $0.id, title: $0.title, tripID: $0.tripID, kind: "note") })
    }
    @MainActor func importSharedSources() async {
        guard !processingShares else { return }
        processingShares = true
        defer { processingShares = false }
        for envelope in SharedInbox.pending() where !deletedSourceIDs.contains(envelope.id) && !socialSources.contains(where: { $0.id == envelope.id }) {
            var source = await SharedSourceProcessor.process(envelope)
            guard !deletedSourceIDs.contains(envelope.id) else { continue }
            source.city = trips.first(where: { $0.id == envelope.destination.tripID })?.brief.destination
            socialSources.append(source)
            if envelope.destination.mode == "note" { attachSourceToNote(source, noteID: envelope.destination.noteID) }
            persistSocialLibrary()
        }
        Task { await runSocialExtractions() }
        presentShareSummaryIfNeeded()
    }
    /// Sends shared TikToks to the bridge's Gemini queue and pins what comes back. Polls while the app is open;
    /// unfinished jobs resume on the next launch or foreground.
    @MainActor func runSocialExtractions() async {
        guard !runningSocialExtractions else { return }
        runningSocialExtractions = true
        defer { runningSocialExtractions = false }
        let token = bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines), base = bridgeBaseURL
        guard !token.isEmpty else { return }
        for _ in 0..<60 {
            let pending = socialSources.filter(SocialExtractionClient.wantsExtraction)
            if pending.isEmpty { return }
            for source in pending {
                guard let index = socialSources.firstIndex(where: { $0.id == source.id }) else { continue }
                do {
                    var job: SocialExtractionJob?
                    if source.extractionStatus == nil {
                        let ready = await SocialExtractionClient.ensureSnapshot(source)
                        if let fresh = socialSources.firstIndex(where: { $0.id == source.id }) { socialSources[fresh] = ready }
                        job = try await SocialExtractionClient.submit(ready, baseURL: base, token: token)
                    } else {
                        job = try await SocialExtractionClient.poll(source.id.uuidString, baseURL: base, token: token)
                    }
                    guard let fresh = socialSources.firstIndex(where: { $0.id == source.id }) else { continue }
                    guard let job else { socialSources[fresh].extractionStatus = nil; continue }
                    socialSources[fresh].extractionStatus = job.status
                    socialSources[fresh].extractionError = job.error ?? job.note
                    if job.status == "ready", let result = job.result {
                        socialSources[fresh].rereadRequested = nil
                        applySocialExtraction(result, sourceIndex: fresh, fromIndex: job.cached == true)
                        // "8 stops" in the post, fewer found: say so on the video, with Read again one tap away.
                        if result.incomplete == true, let stated = result.statedCount {
                            socialSources[fresh].extractionError = "Found \(result.places.count) of the \(stated) places this post mentions. Read again to look closer."
                        }
                    }
                } catch {
                    if socialSources.indices.contains(index) { socialSources[index].extractionError = error.localizedDescription }
                }
            }
            persistSocialLibrary()
            presentShareSummaryIfNeeded()
            try? await Task.sleep(for: .seconds(4))
        }
    }
    /// "You're back" recap: everything read since the summary was last dismissed.
    @MainActor func presentShareSummaryIfNeeded() {
        if let demo = ShareSummary.demo { shareSummary = demo; return }
        guard shareSummaryEnabled, shareSummary == nil, appScenePhase == .active else { return }
        let since = Date(timeIntervalSince1970: shareSummaryLastSeen)
        let fresh = socialSources.filter { $0.extractionStatus == "ready" && ($0.extractedAt ?? .distantPast) > since }
        // Wait until everything shared in this batch has finished, so the recap appears once.
        guard !fresh.isEmpty, !socialSources.contains(where: { SocialExtractionClient.wantsExtraction($0) && $0.extractionStatus != nil }) else { return }
        let ids = Set(fresh.map(\.id))
        let places = socialPlaces.filter { ids.contains($0.sourceID) }
        let covers = fresh.compactMap { source -> URL? in
            let attachment = source.envelope.attachments.first { $0.kind == "cover" } ?? source.envelope.attachments.first { $0.kind == "image" }
            return attachment.flatMap { SharedInbox.attachmentURL(sourceID: source.id, attachment: $0) }
        }
        let cities = Array(Set(places.compactMap { $0.city?.nonEmpty } + fresh.compactMap { $0.city?.nonEmpty })).sorted()
        let countries = Array(Set(places.compactMap { $0.countryCode?.nonEmpty?.uppercased() } + fresh.compactMap { $0.countryCode?.nonEmpty?.uppercased() })).sorted()
        shareSummary = ShareSummary(videos: fresh.count, places: uniquePlaceCount(places), cities: cities, countries: countries,
                                    covers: Array(covers.prefix(3)), sharedSince: since)
    }
    /// One video in, everything out: each place becomes (or joins) one pin in the share's collection, one note per
    /// place gets this video's section (its caption timeline, tips, must-trys), and a tips post gets a tips note.
    /// Re-reading replaces this video's sections; it never adds a second pin or a second note for the same place.
    @MainActor private func applySocialExtraction(_ result: SocialExtractionJob.Result, sourceIndex: Int, fromIndex: Bool = false) {
        let source = socialSources[sourceIndex]
        let tripID = source.envelope.destination.tripID
        let mustDo = source.envelope.destination.mustDo == true
        let tips = result.tips ?? []
        socialSources[sourceIndex].displayTitle = result.postTitle.nonEmpty ?? source.displayTitle
        socialSources[sourceIndex].summary = result.postSummary.nonEmpty
        socialSources[sourceIndex].city = result.city.nonEmpty ?? source.city
        socialSources[sourceIndex].country = result.country.nonEmpty
        socialSources[sourceIndex].countryCode = result.countryCode?.nonEmpty
        socialSources[sourceIndex].listTitle = source.envelope.tiktok?.authorHandle.map { "@" + $0 } ?? source.listTitle
        socialSources[sourceIndex].extractionModel = result.model
        socialSources[sourceIndex].extractedAt = .now
        socialSources[sourceIndex].postKind = result.postKind ?? (result.places.isEmpty && !tips.isEmpty ? "tips" : "places")
        socialSources[sourceIndex].tips = tips.isEmpty ? nil : tips
        socialSources[sourceIndex].fromIndex = fromIndex
        socialSources[sourceIndex].state = result.places.isEmpty && tips.isEmpty ? "needs_place_review" : "ready"
        socialPlaces.removeAll { $0.sourceID == source.id }
        let current = socialSources[sourceIndex]
        // Saved from the community browser "to a city": keep the video, pin nothing, write no place notes.
        let videoOnly = source.envelope.destination.mode == "video"
        var linked: [UUID] = [], keys: Set<String> = []
        for place in result.places {
            let google = place.google
            var mention = SocialPlaceMention(
                id: UUID(), name: google?.name?.nonEmpty ?? place.name, summary: place.tldr, sourceID: source.id,
                evidenceIDs: [], tripID: tripID, latitude: google?.latitude, longitude: google?.longitude,
                city: google?.city?.nonEmpty ?? place.city?.nonEmpty ?? result.city.nonEmpty,
                category: place.category, nameLatin: place.nameLatin, neighborhood: place.neighborhood, country: place.country,
                countryCode: place.countryCode ?? google?.countryCode, address: google?.address ?? place.addressHint,
                googlePlaceID: google?.placeID, vibeTags: place.vibeTags, proTips: place.proTips, goodToKnow: place.goodToKnow,
                mustTry: place.mustTry, whyGo: place.whyGo, priceHint: place.priceHint, evidence: place.evidence, moments: place.moments)
            let key = PlaceKey.of(googlePlaceID: mention.googlePlaceID, name: mention.name, city: mention.city)
            keys.insert(key)
            if !videoOnly { mention.noteID = upsertPlaceNote(key: key, mention: mention, source: current, tripID: tripID) }
            socialPlaces.append(mention)
            linked.append(mention.id)
            if !videoOnly, let latitude = mention.latitude, let longitude = mention.longitude {
                pinFromVideo(mention, latitude: latitude, longitude: longitude, category: MapPlaceCategory(rawValue: place.category) ?? .other,
                             tripID: tripID, mustDo: mustDo)
            }
        }
        dropStaleSections(of: source.id, keeping: keys)
        upsertTipsNote(current)
        upsertGuideNote(current, places: videoOnly ? [] : socialPlaces.filter { $0.sourceID == source.id })
        socialSources[sourceIndex].linkedPlaceIDs = linked
        if !result.places.isEmpty || !tips.isEmpty { TrippyHaptics.success() }
    }
    /// One note per real place, whichever collection or video it came from.
    @discardableResult private func upsertPlaceNote(key: String, mention: SocialPlaceMention, source: ImportedSocialSource, tripID: UUID?) -> UUID {
        let section = AutoNote.placeSection(mention, source: source)
        let reference = mention.latitude.flatMap { latitude in mention.longitude.map { longitude in
            LinkedPlaceReference(id: key, name: mention.name, address: mention.address ?? "", latitude: latitude, longitude: longitude,
                                 googlePlaceID: mention.googlePlaceID)
        } }
        if let index = travelNotes.firstIndex(where: { $0.placeKey == key }) {
            travelNotes[index].fromSources = (travelNotes[index].fromSources ?? [:]).merging([source.id.uuidString: section]) { $1 }
            if !travelNotes[index].sourceIDs.contains(source.id) { travelNotes[index].sourceIDs.append(source.id) }
            if travelNotes[index].linkedPlaces?.isEmpty != false, let reference {
                travelNotes[index].linkedPlaces = [reference]; travelNotes[index].linkedPlaceIDs = [reference.id]
            }
            if travelNotes[index].kind == nil { travelNotes[index].kind = "place" }
            travelNotes[index].updatedAt = .now
            return travelNotes[index].id
        }
        let note = TravelNote(id: UUID(), title: mention.name, tripID: tripID, sourceIDs: [source.id], userText: "", updatedAt: .now,
                              placeMentionID: mention.id, city: mention.city, linkedPlaceIDs: reference.map { [$0.id] },
                              linkedPlaces: reference.map { [$0] }, kind: "place", placeKey: key, fromSources: [source.id.uuidString: section])
        travelNotes.insert(note, at: 0)
        return note.id
    }
    /// General tips (no single venue is the point) live in one note per city: every video about Athens adds its
    /// section to "Athens tips". Tips with no city go to the video's own tips note. A re-read with no tips left
    /// takes this video's section out again.
    private func upsertTipsNote(_ source: ImportedSocialSource) {
        let id = source.id.uuidString
        let city = cityForSource(source).nonEmpty
        let cityKey = city.map { MapCityGrouping.key(LibraryGrouping.cityTitle($0)) }
        let tripID = source.envelope.destination.tripID
        let own = travelNotes.firstIndex { $0.kind == "tips" && $0.sourceIDs.contains(source.id) }
        guard !(source.tips ?? []).isEmpty else {
            if let own { removeSection(id, of: source.id, at: own) }
            return
        }
        let section = AutoNote.tipsSection(source)
        let shared = cityKey.flatMap { key in
            travelNotes.firstIndex { $0.kind == "tips" && $0.tripID == tripID && $0.city.map { MapCityGrouping.key(LibraryGrouping.cityTitle($0)) } == key }
        }
        if let index = own ?? shared {
            travelNotes[index].fromSources = (travelNotes[index].fromSources ?? [:]).merging([id: section]) { $1 }
            if !travelNotes[index].sourceIDs.contains(source.id) { travelNotes[index].sourceIDs.append(source.id) }
            // A second video joining turns a video's tips note into the city's.
            if let city, travelNotes[index].sourceIDs.count > 1,
               socialSources.contains(where: { travelNotes[index].sourceIDs.contains($0.id) && $0.displayTitle == travelNotes[index].title }) {
                travelNotes[index].title = "\(MapCityGrouping.name(city)) tips"
            }
            travelNotes[index].updatedAt = .now
            return
        }
        travelNotes.insert(TravelNote(id: UUID(), title: city.map { "\(MapCityGrouping.name($0)) tips" } ?? source.displayTitle ?? "Travel tips",
                                      tripID: tripID, sourceIDs: [source.id], userText: "", updatedAt: .now, city: city,
                                      kind: "tips", fromSources: [id: section]), at: 0)
    }
    /// The video as one page: its general tips, then every place it names with the tips for that place. It links to
    /// all of those places; each place still keeps its own note. A video with no places has no guide.
    private func upsertGuideNote(_ source: ImportedSocialSource, places: [SocialPlaceMention]) {
        let id = source.id.uuidString
        let existing = travelNotes.firstIndex { $0.kind == "guide" && $0.sourceIDs.contains(source.id) }
        guard !places.isEmpty else {
            if let existing { removeSection(id, of: source.id, at: existing) }
            return
        }
        let section = AutoNote.guideSection(source, places: places)
        let keys = places.map { PlaceKey.of(googlePlaceID: $0.googlePlaceID, name: $0.name, city: $0.city) }
        let references = zip(places, keys).compactMap { place, key in
            place.latitude.flatMap { latitude in place.longitude.map { longitude in
                LinkedPlaceReference(id: key, name: place.name, address: place.address ?? "", latitude: latitude, longitude: longitude, googlePlaceID: place.googlePlaceID)
            } }
        }
        if let existing {
            travelNotes[existing].fromSources = [id: section]
            travelNotes[existing].linkedPlaceIDs = keys; travelNotes[existing].linkedPlaces = references
            travelNotes[existing].updatedAt = .now
            return
        }
        travelNotes.insert(TravelNote(id: UUID(), title: source.displayTitle ?? "Saved video", tripID: source.envelope.destination.tripID,
                                      sourceIDs: [source.id], userText: "", updatedAt: source.extractedAt ?? .now, city: cityForSource(source).nonEmpty,
                                      linkedPlaceIDs: keys, linkedPlaces: references, kind: "guide", fromSources: [id: section]), at: 0)
    }
    private func removeSection(_ id: String, of sourceID: UUID, at index: Int) {
        travelNotes[index].fromSources?[id] = nil
        travelNotes[index].sourceIDs.removeAll { $0 == sourceID }
        if travelNotes[index].fromSources?.isEmpty != false, travelNotes[index].userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            travelNotes.remove(at: index)
        }
    }
    /// Videos read before guides existed get theirs the next time the library loads.
    func backfillGuideNotes() {
        for source in socialSources where source.extractionStatus == "ready" && source.envelope.destination.mode != "video" {
            guard !travelNotes.contains(where: { $0.kind == "guide" && $0.sourceIDs.contains(source.id) }) else { continue }
            upsertGuideNote(source, places: socialPlaces.filter { $0.sourceID == source.id })
        }
    }
    /// A re-read that no longer finds a place removes only this video's section; a note left with nothing is removed.
    private func dropStaleSections(of sourceID: UUID, keeping keys: Set<String>) {
        let id = sourceID.uuidString
        for index in travelNotes.indices.reversed() where travelNotes[index].kind == "place" {
            guard let key = travelNotes[index].placeKey, !keys.contains(key), travelNotes[index].fromSources?[id] != nil else { continue }
            travelNotes[index].fromSources?[id] = nil
            travelNotes[index].sourceIDs.removeAll { $0 == sourceID }
            if travelNotes[index].fromSources?.isEmpty != false, travelNotes[index].userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                travelNotes.remove(at: index)
            }
        }
    }
    /// Pins go where the video was saved: a trip's pins or the general map. Same place twice = same pin, one more source.
    private func pinFromVideo(_ mention: SocialPlaceMention, latitude: Double, longitude: Double, category: MapPlaceCategory, tripID: UUID?, mustDo: Bool) {
        let id = mention.googlePlaceID.map { "google:" + $0 } ?? "social:\(mention.id.uuidString)"
        func same(_ place: PersonalPlace) -> Bool {
            place.id == id || (place.googlePlaceID != nil && place.googlePlaceID == mention.googlePlaceID)
        }
        func merge(_ place: inout PersonalPlace) {
            place.pinned = true
            if mustDo { place.saved = true }
            if !(place.sourceIDs ?? []).contains(mention.sourceID) { place.sourceIDs = (place.sourceIDs ?? []) + [mention.sourceID] }
        }
        var pin = PersonalPlace(id: id, name: mention.name, city: mention.city ?? "", address: mention.address ?? "",
                                latitude: latitude, longitude: longitude, category: category)
        pin.googlePlaceID = mention.googlePlaceID
        pin.boundaryCountryCode = mention.countryCode
        pin.saved = mustDo
        merge(&pin)
        if let tripID, let tripIndex = trips.firstIndex(where: { $0.id == tripID }) {
            var pins = trips[tripIndex].savedPins ?? []
            if let existing = pins.firstIndex(where: same) { merge(&pins[existing]) } else { pins.append(pin) }
            trips[tripIndex].savedPins = pins
            trips[tripIndex].updatedAt = .now
            TripStorage.save(trips)
            return
        }
        if let existing = savedPlaces.firstIndex(where: same) { merge(&savedPlaces[existing]) } else { savedPlaces.append(pin) }
    }
    // MARK: Takes
    func takeBinding(_ key: String) -> Binding<PlaceTake> {
        Binding(get: { placeTakes[key] ?? PlaceTake() }, set: { take in
            placeTakes[key] = take.isEmpty ? nil : take
            guard let googleID = PlaceKey.googleID(key) else { return }
            let base = bridgeBaseURL, token = bridgeToken
            takeSendTasks[key]?.cancel()
            takeSendTasks[key] = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700)) // a burst of taps sends once
                guard !Task.isCancelled else { return }
                if let community = await PlaceTakesClient.send(take, googleID: googleID, baseURL: base, token: token) {
                    placeCommunity[googleID] = community
                }
            }
        })
    }
    func refreshCommunity(_ keys: [String]) async {
        let ids = keys.compactMap(PlaceKey.googleID)
        guard !ids.isEmpty else { return }
        let fetched = await PlaceTakesClient.fetch(googleIDs: ids, baseURL: bridgeBaseURL, token: bridgeToken)
        for (id, value) in fetched { placeCommunity[id] = value }
    }
    // MARK: Saving from the community browser (never automatic)
    var communityActions: CommunityActions {
        CommunityActions(saveVideo: { saveCommunityVideo($0, pinAll: false) },
                         saveWithSpots: { saveCommunityVideo($0, pinAll: true) },
                         pinPlace: { pinCommunityPlace($1, from: $0) },
                         isSaved: { key in communitySource(key) != nil },
                         isPinned: { place in
                             savedPlaces.contains { $0.isPinned && ($0.googlePlaceID != nil && $0.googlePlaceID == place.googlePlaceID) }
                         })
    }
    private func communitySource(_ key: String) -> ImportedSocialSource? {
        guard let id = key.split(separator: ":", maxSplits: 1).last.map(String.init), !id.isEmpty else { return nil }
        return socialSources.first { $0.envelope.tiktok?.postID == id || ($0.envelope.sourceURL ?? "").contains(id) }
    }
    /// Keep a community video in your library, tied to its city. With pinAll its shops are pinned too.
    @MainActor func saveCommunityVideo(_ video: CommunityVideo, pinAll: Bool) {
        if let existing = communitySource(video.key) {
            if pinAll { for place in video.places { pinCommunityPlace(place, from: video, sourceID: existing.id) } }
            return
        }
        let envelope = SharedSourceEnvelope(id: UUID(), capturedAt: .now, sourceURL: video.url, sharedText: "", attachments: [],
                                            destination: ShareDestination(mode: pinAll ? "places" : "video", tripID: nil, noteID: nil))
        var source = ImportedSocialSource(id: envelope.id, envelope: envelope, evidence: [], state: "needs_retrieval", issues: [])
        source.displayTitle = video.title; source.city = video.city.nonEmpty; source.summary = video.summary
        source.listTitle = video.author.map { video.platform == "tiktok" ? "@" + $0 : $0 }
        source.tips = video.tips.isEmpty ? nil : video.tips.map { SocialTip(title: $0.title, detail: $0.detail, at: $0.at) }
        source.postKind = video.places.isEmpty && !video.tips.isEmpty ? "tips" : "places"
        source.fromIndex = true
        if video.platform != "tiktok" {
            // YouTube creator videos are already indexed by the research pipeline; nothing to read again.
            source.state = "ready"; source.extractionStatus = "ready"; source.extractedAt = .now
        }
        socialSources.append(source)
        persistSocialLibrary()
        if video.platform == "tiktok" { Task { await runSocialExtractions() } } // read once already: comes straight back
    }
    /// Pin one shop from a community video. Only shops with real coordinates can be pinned.
    @MainActor func pinCommunityPlace(_ place: CommunityPlace, from video: CommunityVideo, sourceID: UUID? = nil) {
        guard let latitude = place.latitude, let longitude = place.longitude else { return }
        let sourceID = sourceID ?? communitySource(video.key)?.id
        let id = place.googlePlaceID.map { "google:" + $0 } ?? "community:\(video.key):\(place.id)"
        if let index = savedPlaces.firstIndex(where: { $0.id == id || ($0.googlePlaceID != nil && $0.googlePlaceID == place.googlePlaceID) }) {
            savedPlaces[index].pinned = true
            if let sourceID, !(savedPlaces[index].sourceIDs ?? []).contains(sourceID) { savedPlaces[index].sourceIDs = (savedPlaces[index].sourceIDs ?? []) + [sourceID] }
            return
        }
        let label = ["food": "Food", "coffee": "Coffee", "bars": "Bars", "clubs": "Clubs", "sights": "Sights", "museums": "Sights",
                     "outdoors": "Parks", "shopping": "Shopping", "transport": "Metro"][place.category] ?? "Other"
        var pin = PersonalPlace(id: id, name: place.name, city: video.city, address: "", latitude: latitude, longitude: longitude,
                                category: MapPlaceCategory(rawValue: label) ?? .other)
        pin.googlePlaceID = place.googlePlaceID
        pin.pinned = true; pin.saved = false
        pin.sourceIDs = sourceID.map { [$0] }
        savedPlaces.append(pin)
    }
    /// A place mentioned by two videos is one place.
    func uniquePlaceCount(_ mentions: [SocialPlaceMention]) -> Int {
        Set(mentions.map { PlaceKey.of(googlePlaceID: $0.googlePlaceID, name: $0.name, city: $0.city) }).count
    }
    func community(_ key: String) -> PlaceCommunity? { PlaceKey.googleID(key).flatMap { placeCommunity[$0] } }
    /// Typing on the card appends "Name's notes: …" to the place's note (creating it if this place has none yet).
    func appendToPlaceNote(key: String, name: String, city: String?, tripID: UUID?, text: String) {
        let owner = AutoNote.ownerName
        if let index = travelNotes.firstIndex(where: { $0.placeKey == key }) {
            travelNotes[index].userText = AutoNote.appending(text, to: travelNotes[index].userText, owner: owner)
            travelNotes[index].updatedAt = .now
        } else {
            travelNotes.insert(TravelNote(id: UUID(), title: name, tripID: tripID, sourceIDs: [], userText: AutoNote.appending(text, to: "", owner: owner),
                                          updatedAt: .now, city: city, kind: "place", placeKey: key), at: 0)
        }
    }
    func openPlaceNote(key: String, name: String, city: String?, tripID: UUID?) {
        if let note = travelNotes.first(where: { $0.placeKey == key }) { selectedTravelNoteID = note.id; return }
        let id = UUID()
        travelNotes.insert(TravelNote(id: id, title: name, tripID: tripID, sourceIDs: [], userText: "", updatedAt: .now,
                                      city: city, kind: "place", placeKey: key), at: 0)
        selectedTravelNoteID = id
    }
    /// Every place gets a real link: Google Maps by place ID when known, Apple Maps by coordinates otherwise.
    func mapsLink(name: String, googlePlaceID: String?, latitude: Double?, longitude: Double?) -> URL? {
        var components = URLComponents()
        if let googlePlaceID {
            components = URLComponents(string: "https://www.google.com/maps/search/")!
            components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: name),
                                     URLQueryItem(name: "query_place_id", value: googlePlaceID)]
        } else if let latitude, let longitude {
            components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")]
        } else { return nil }
        return components.url
    }
    private func sourceTextBinding(_ sourceID: UUID, field: String) -> Binding<String> {
        Binding(get: {
            guard let source = socialSources.first(where: { $0.id == sourceID }) else { return "" }
            switch field {
            case "title": return source.displayTitle ?? ""
            case "city": return source.city ?? trips.first(where: { $0.id == source.envelope.destination.tripID })?.brief.destination ?? ""
            default: return source.listTitle ?? ""
            }
        }, set: { value in
            guard let index = socialSources.firstIndex(where: { $0.id == sourceID }) else { return }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            switch field {
            case "title": socialSources[index].displayTitle = clean
            case "city": socialSources[index].city = clean
            default: socialSources[index].listTitle = clean
            }
        })
    }
    private func isVideoSource(_ source: ImportedSocialSource) -> Bool {
        source.envelope.mediaKind == "video" || source.envelope.sourceURL?.localizedCaseInsensitiveContains("tiktok.com") == true
    }
    private func cityForSource(_ source: ImportedSocialSource) -> String {
        source.city?.nonEmpty ?? trips.first(where: { $0.id == source.envelope.destination.tripID })?.brief.destination ?? ""
    }
    private func cityForMention(_ place: SocialPlaceMention) -> String {
        if let city = place.city?.nonEmpty { return city }
        if let tripCity = trips.first(where: { $0.id == place.tripID })?.brief.destination { return tripCity }
        if let source = socialSources.first(where: { $0.id == place.sourceID }) { return cityForSource(source) }
        return ""
    }
    private func sourceMatchesLibrary(_ source: ImportedSocialSource) -> Bool {
        let city = cityForSource(source)
        if let libraryCity,
           MapCityGrouping.key(LibraryGrouping.cityTitle(city)) != MapCityGrouping.key(LibraryGrouping.cityTitle(libraryCity)) { return false }
        if libraryQuery.isEmpty { return true }
        let text = [source.displayTitle ?? "", source.listTitle ?? "", city, source.envelope.sourceURL ?? ""]
            + source.evidence.map(\.text)
        return text.joined(separator: " ").localizedCaseInsensitiveContains(libraryQuery)
    }
    private var filteredLibraryVideos: [ImportedSocialSource] {
        socialSources.filter { sourceMatchesLibrary($0) && (videoStatusFilter == .all || LibrarySourceStatus.classify($0.state) == videoStatusFilter) }.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
    }
    var videoLibrary: some View {
        let sources = socialSources.filter(sourceMatchesLibrary).sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
        let working = sources.filter { SocialExtractionClient.wantsExtraction($0) || $0.extractionStatus == "failed" }
        let workingIDs = Set(working.map(\.id))
        // Tips posts (no venue is the point) get their own shelf; their places, if any, are still pinned.
        let tipPosts = sources.filter { !workingIDs.contains($0.id) && $0.isTips }
        let tipIDs = Set(tipPosts.map(\.id))
        let groups = LibraryGrouping.cities(sources.filter { !workingIDs.contains($0.id) && !tipIDs.contains($0.id) }, city: cityForSource)
        let atlas = libraryAtlas
        return LazyVStack(alignment: .leading, spacing: 22) {
            studioHeader(sources)
            if !tipPosts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    StudioHeading(title: "Tips", count: tipPosts.count)
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(tipPosts) { source in
                                let note = travelNotes.first { $0.kind == "tips" && $0.sourceIDs.contains(source.id) }
                                Button { selectedSocialSource = source } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        StudioCover(url: studioCover(source)).frame(width: 150, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        Text(studioTitle(source)).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(AppPalette.ink)
                                            .lineLimit(2).multilineTextAlignment(.leading)
                                        Text("💡 \(source.tips?.count ?? 0) tips" + (note != nil ? " · note" : ""))
                                            .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                                    }
                                    .frame(width: 150, alignment: .leading).padding(10)
                                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                                }
                                .buttonStyle(SketchPressStyle())
                                .contextMenu {
                                    if let note { Button("Open tips note", systemImage: "note.text") { selectedTravelNoteID = note.id } }
                                    if let link = source.envelope.sourceURL.flatMap(URL.init(string:)) { Link(destination: link) { Label("Open on TikTok", systemImage: "music.note") } }
                                    Button("Delete", systemImage: "trash", role: .destructive) { deleteLibraryVideo(source.id) }
                                }
                            }
                        }.padding(.horizontal, 20)
                    }.scrollIndicators(.hidden).padding(.horizontal, -20)
                }
            }
            if !working.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    StudioHeading(title: "In the works", count: working.count)
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(working) { source in
                                Button { selectedSocialSource = source } label: {
                                    StudioWorkCard(title: studioTitle(source), author: source.envelope.tiktok?.authorHandle, cover: studioCover(source),
                                                   stage: StudioStage.of(source), status: studioStatus(source),
                                                   failed: source.extractionStatus == "failed") { retryExtraction(source.id) }
                                }.buttonStyle(QuietPressStyle())
                            }
                        }.padding(.horizontal, 20)
                    }.scrollIndicators(.hidden).padding(.horizontal, -20)
                }
            }
            if sources.isEmpty {
                LibraryEmptyState(title: "Your video studio is empty", message: "Share a TikTok to trippy and it lands here, read and pinned.",
                                  tone: .videos, actionTitle: "Add a link", action: { showImportLink = true })
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    StudioHeading(title: group.title, count: group.items.count, flag: libraryCountryCode(group.title).map(MarkGlyphCatalog.flag))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(group.items) { source in
                            Button { selectedSocialSource = source } label: {
                                StudioPosterCard(title: studioTitle(source), author: source.envelope.tiktok?.authorHandle, cover: studioCover(source),
                                                 placeCount: atlas.places(inVideo: source.id).count,
                                                 evidence: StudioEvidence.of(source), isSlideshow: source.envelope.tiktok?.isSlideshow ?? (source.envelope.mediaKind == "slides"),
                                                 noteCount: atlas.noteIDsByVideo[source.id]?.count ?? 0,
                                                 trip: trips.first { $0.id == source.envelope.destination.tripID }?.title)
                            }
                            .buttonStyle(SketchPressStyle())
                            .contextMenu {
                                Button("Open", systemImage: "arrow.up.right") { selectedSocialSource = source }
                                if let link = source.envelope.sourceURL.flatMap(URL.init(string:)) { Link(destination: link) { Label("Open on TikTok", systemImage: "music.note") } }
                                Button("Read again", systemImage: "arrow.clockwise") { retryExtraction(source.id) }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleteLibraryVideo(source.id) }
                            }
                        }
                    }
                }
            }
        }
    }
    private func studioHeader(_ sources: [ImportedSocialSource]) -> some View {
        let ids = Set(sources.map(\.id))
        let places = socialPlaces.filter { ids.contains($0.sourceID) }
        let cities = Set(places.compactMap { $0.city?.nonEmpty } + sources.compactMap { $0.city?.nonEmpty })
        let countries = Set(places.compactMap { $0.countryCode?.nonEmpty?.uppercased() })
        let flags = countries.sorted().prefix(3).map(MarkGlyphCatalog.flag).joined()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Image(systemName: "music.note").foregroundStyle(Color(hex: "25F4EE")).offset(x: -1.5, y: -1.5)
                        Image(systemName: "music.note").foregroundStyle(Color(hex: "FE2C55")).offset(x: 1.5, y: 1.5)
                        Image(systemName: "music.note").foregroundStyle(.white)
                    }
                    .font(.system(size: 17, weight: .black)).frame(width: 40, height: 40)
                    .background(Color(hex: "161616"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                    Text("Share a TikTok to trippy: we read it and pin every spot.").font(Sketch.text(13, relativeTo: .footnote))
                        .foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Add a link", systemImage: "link") { showImportLink = true }
                    Toggle(isOn: $shareSummaryEnabled) { Label("Recap when I'm back", systemImage: "sparkles.rectangle.stack") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(AppPalette.ink)
                        .frame(width: 40, height: 40).background(Sketch.paperDeep, in: Circle()).frame(width: 44, height: 44)
                }.accessibilityLabel("Studio options")
            }
            HStack(spacing: 8) {
                StudioStat(value: "\(sources.count)", label: sources.count == 1 ? "Video" : "Videos")
                StudioStat(value: "\(uniquePlaceCount(places))", label: uniquePlaceCount(places) == 1 ? "Place" : "Places")
                StudioStat(value: "\(cities.count)", label: cities.count == 1 ? "City" : "Cities")
                StudioStat(value: flags.isEmpty ? "–" : flags, label: countries.count == 1 ? "Country" : "Countries")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
    }
    private func studioTitle(_ source: ImportedSocialSource) -> String {
        source.displayTitle?.nonEmpty
            ?? source.envelope.tiktok?.slideshowTitle?.nonEmpty
            ?? source.envelope.tiktok?.caption.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }?.nonEmpty
            ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init)
            ?? "Saved video"
    }
    private func studioCover(_ source: ImportedSocialSource) -> URL? {
        let attachment = source.envelope.attachments.first { $0.kind == "cover" } ?? source.envelope.attachments.first { $0.kind == "image" }
        return attachment.flatMap { SharedSourceImageURL.resolve(source.id, $0) }
    }
    private func studioStatus(_ source: ImportedSocialSource) -> String {
        if source.extractionStatus == "failed" { return source.extractionError ?? "Couldn't read this one." }
        if bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Connect the bridge in Settings to read it." }
        switch source.extractionStatus {
        case "queued": return (source.extractionError ?? "").localizedCaseInsensitiveContains("quota") ? "Waiting for free Gemini quota" : "In line for Gemini"
        case "running": return "Gemini is reading it…"
        default:
            if let error = source.extractionError { return error }
            return source.envelope.tiktok == nil ? "Reading the post…" : "Sending to Gemini…"
        }
    }
    private func retryExtraction(_ id: UUID) {
        guard let index = socialSources.firstIndex(where: { $0.id == id }) else { return }
        socialSources[index].extractionStatus = nil
        socialSources[index].extractionError = nil
        socialSources[index].rereadRequested = true   // read it again even though it was indexed before
        persistSocialLibrary()
        Task { await runSocialExtractions() }
    }
    private var videoStatusFilters: some View {
        let sources = socialSources.filter(sourceMatchesLibrary)
        return PillFlowLayout(spacing: 8) {
            ForEach(LibrarySourceStatus.allCases) { status in
                let count = status == .all ? sources.count : sources.filter { LibrarySourceStatus.classify($0.state) == status }.count
                Button { videoStatusFilter = status } label: {
                    LibrarySourceFilterPill(status: status, count: count, selected: videoStatusFilter == status)
                }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(videoStatusFilter == status ? .isSelected : [])
            }
        }
    }
    private func libraryVideoRow(_ source: ImportedSocialSource) -> some View {
        let status = LibrarySourceStatus.classify(source.state)
        let places = socialPlaces.filter { $0.sourceID == source.id }
        let notes = travelNotes.filter { $0.sourceIDs.contains(source.id) }
        let title = source.displayTitle ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "Saved video"
        return HStack(alignment: .top, spacing: 14) {
            Button { selectedSocialSource = source } label: {
                libraryVideoThumbnail(source).frame(width: 92, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: isVideoSource(source) ? "play.fill" : "photo.stack").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).padding(6).background(Circle().fill(.black.opacity(0.45))).padding(6)
                    }
            }
            .buttonStyle(SketchPressStyle()).accessibilityLabel("Open \(title)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(source.listTitle ?? "Saved video").font(Sketch.eyebrow).tracking(0.6)
                        .foregroundStyle(LibraryTone.videos.color(libraryScheme)).lineLimit(1)
                    Spacer(minLength: 4)
                    Menu {
                        Button("Open", systemImage: "arrow.up.right") { selectedSocialSource = source }
                        if let note = notes.first { Button("Open note", systemImage: "note.text") { selectedTravelNoteID = note.id } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleteLibraryVideo(source.id) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(libraryInk)
                            .frame(width: 32, height: 32).raisedCircle()
                    }
                    .frame(width: 44, height: 44).accessibilityLabel("More for \(title)")
                }
                .frame(height: 22)
                Button { selectedSocialSource = source } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(libraryInk).lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if !places.isEmpty {
                            Text(places.prefix(3).map(\.name).joined(separator: " · ")).font(Sketch.text(12, relativeTo: .caption))
                                .foregroundStyle(libraryMuted).lineLimit(2).multilineTextAlignment(.leading)
                        } else if status != .ready {
                            Text(sourceStatus(source)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(libraryMuted).lineLimit(2)
                        }
                        HStack(spacing: 6) {
                            SketchTag(text: status.title, tint: status == .ready ? Sketch.sage : status == .review ? Sketch.ochre : Sketch.inkSoft, symbol: status.symbol)
                            if !places.isEmpty { SketchTag(text: "\(places.count) places", tint: Sketch.coral) }
                            if !notes.isEmpty { SketchTag(text: "\(notes.count) notes", tint: Sketch.plum) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sketchCard(padding: 12)
    }
    @ViewBuilder private func libraryVideoThumbnail(_ source: ImportedSocialSource) -> some View {
        if let video = source.envelope.attachments.first(where: { $0.kind == "video" }), let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: video) {
            SharedSourceVideoThumbnail(url: url)
        } else if let image = source.envelope.attachments.first(where: { $0.kind == "image" }), let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: image) {
            SharedSourceImage(url: url)
        } else {
            ZStack {
                LibraryTone.videos.color(libraryScheme).opacity(0.08)
                LibraryIconWell(symbol: "play.fill", tone: .videos, size: 68)
            }
        }
    }
    private func socialPlaceVideoCarousel(city: String) -> some View {
        let matches = socialPlaces.filter { cityForMention($0).localizedCaseInsensitiveCompare(city) == .orderedSame }
        let linkedSourceIDs = Set(matches.map(\.sourceID))
        let unlinkedVideos = socialSources.filter {
            isVideoSource($0) && cityForSource($0).localizedCaseInsensitiveCompare(city) == .orderedSame && !linkedSourceIDs.contains($0.id)
        }.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
        let grouped = Dictionary(grouping: matches) { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let clusters = grouped.compactMap { key, mentions -> TikTokPlaceCluster? in
            guard let first = mentions.first else { return nil }
            return TikTokPlaceCluster(id: key, title: first.name, city: city, mentions: mentions.sorted { mentionSourceDate($0) > mentionSourceDate($1) })
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "music.note").font(.headline).foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TikTok saves · \(city)").font(.custom("PlusJakartaSans-Bold", size: 19)).foregroundStyle(AppPalette.ink)
                }
                Spacer()
                Button("Videos") { librarySection = "Videos" }.font(.caption.weight(.bold)).foregroundStyle(AppPalette.brand)
            }
            if clusters.isEmpty && unlinkedVideos.isEmpty {
                Button { showImportLink = true } label: {
                    Label("Add a video for \(city)", systemImage: "plus")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                        .background(AppPalette.surface, in: Capsule())
                }.buttonStyle(QuietPressStyle())
            }
            if !clusters.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(clusters) { cluster in
                            TikTokPlaceMemoryCard(cluster: cluster,
                                sources: cluster.mentions.compactMap { mention in socialSources.first { $0.id == mention.sourceID } },
                                notes: travelNotes,
                                onOpenSource: { sourceID in selectedSocialSource = socialSources.first { $0.id == sourceID } },
                                onOpenNote: { selectedTravelNoteID = $0 })
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            }
            if !unlinkedVideos.isEmpty {
                Text("Unlinked videos").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(unlinkedVideos) { source in
                            TikTokVideoMemoryCard(source: source, places: [], notes: travelNotes.filter { $0.sourceIDs.contains(source.id) },
                                city: city, onOpenSource: { selectedSocialSource = source }, onOpenNote: { selectedTravelNoteID = $0 })
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            }
        }.padding(.top, 8)
    }
    private func mentionSourceDate(_ mention: SocialPlaceMention) -> Date {
        socialSources.first(where: { $0.id == mention.sourceID })?.envelope.capturedAt ?? .distantPast
    }
    func attachSourceToNote(_ source: ImportedSocialSource, noteID: UUID?) {
        if let noteID, let index = travelNotes.firstIndex(where: { $0.id == noteID }) {
            if !travelNotes[index].sourceIDs.contains(source.id) { travelNotes[index].sourceIDs.append(source.id) }
            if travelNotes[index].city == nil { travelNotes[index].city = cityForSource(source).nonEmpty }
            travelNotes[index].updatedAt = .now
        } else {
            let title = source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok inspiration"
            travelNotes.insert(TravelNote(id: UUID(), title: String(title.prefix(80)), tripID: source.envelope.destination.tripID,
                                         sourceIDs: [source.id], userText: "", updatedAt: .now, city: cityForSource(source).nonEmpty), at: 0)
        }
    }
    @MainActor private func saveTikTokPlace(from source: ImportedSocialSource) async {
        let name = socialPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = socialPlaceCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var latitude: Double?
        var longitude: Double?
        var resolvedCity = city
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, city].filter { !$0.isEmpty }.joined(separator: ", ")
        if let region = cityCoordinates[city]?.coordinate {
            request.region = MKCoordinateRegion(center: region, span: .init(latitudeDelta: 1, longitudeDelta: 1))
        }
        if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
            latitude = item.placemark.coordinate.latitude
            longitude = item.placemark.coordinate.longitude
            resolvedCity = item.placemark.locality ?? city
        }
        let mentionID = UUID()
        let noteID = UUID()
        let tripID = source.envelope.destination.tripID
        let evidenceText = source.evidence.first(where: { $0.id == socialEvidenceID })?.text ?? ""
        let noteText = [socialPlaceSummary.trimmingCharacters(in: .whitespacesAndNewlines), evidenceText]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        socialPlaces.append(SocialPlaceMention(id: mentionID, name: name, summary: socialPlaceSummary,
                                              sourceID: source.id, evidenceIDs: socialEvidenceID.isEmpty ? [] : [socialEvidenceID],
                                              tripID: tripID, latitude: latitude, longitude: longitude,
                                              city: resolvedCity.nonEmpty, noteID: noteID))
        if let index = socialSources.firstIndex(where: { $0.id == source.id }) {
            var placeIDs = socialSources[index].linkedPlaceIDs ?? []
            if !placeIDs.contains(mentionID) { placeIDs.append(mentionID) }
            socialSources[index].linkedPlaceIDs = placeIDs
            if socialSources[index].city == nil { socialSources[index].city = resolvedCity.nonEmpty }
        }
        travelNotes.insert(TravelNote(id: noteID, title: name, tripID: tripID,
                                      sourceIDs: [source.id], userText: noteText, updatedAt: .now,
                                      placeMentionID: mentionID, city: resolvedCity.nonEmpty), at: 0)
        showAddSocialPlace = false
        socialPlaceName = ""; socialPlaceSummary = ""; socialPlaceCity = ""
    }
    func sourceStatus(_ source: ImportedSocialSource) -> String {
        switch source.state {
        case "needs_retrieval": return "Link saved · Retrieval pending"
        case "needs_transcript": return "Video saved · Transcript pending"
        case "ready": return "Places ready"
        default: return "Review places"
        }
    }
    private var filteredLibraryNotes: [TravelNote] {
        travelNotes.filter { note in
            let trip = trips.first { $0.id == note.tripID }
            let noteCity = note.city ?? trip?.brief.destination
            return (libraryCity == nil || noteCity?.localizedCaseInsensitiveCompare(libraryCity!) == .orderedSame) &&
                (libraryQuery.isEmpty || "\(note.title) \(note.userText)".localizedCaseInsensitiveContains(libraryQuery) ||
                 socialSources.filter { note.sourceIDs.contains($0.id) }.contains { source in source.evidence.contains { $0.text.localizedCaseInsensitiveContains(libraryQuery) } })
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private func libraryNoteCity(_ note: TravelNote) -> String {
        note.city ?? trips.first { $0.id == note.tripID }?.brief.destination ?? ""
    }
    func socialSourceDetail(_ initial: ImportedSocialSource) -> some View {
        let source = socialSources.first { $0.id == initial.id } ?? initial
        let post = source.envelope.tiktok
        let places = socialPlaces.filter { $0.sourceID == source.id }
        let stage = StudioStage.of(source)
        let evidence = StudioEvidence.of(source)
        return NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 16) {
                        StudioCover(url: studioCover(source)).frame(width: 104, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(studioTitle(source)).font(Sketch.text(20, "ExtraBold", relativeTo: .title3)).tracking(-0.3)
                                .foregroundStyle(AppPalette.ink).fixedSize(horizontal: false, vertical: true)
                            if let handle = post?.authorHandle {
                                Text("@\(handle)").font(Sketch.text(13, "SemiBold", relativeTo: .subheadline)).foregroundStyle(AppPalette.secondaryInk)
                            }
                            if let summary = source.summary { Text(summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(AppPalette.secondaryInk).lineLimit(4) }
                            HStack(spacing: 6) {
                                if let city = source.city?.nonEmpty {
                                    Text((source.countryCode.map(MarkGlyphCatalog.flag).map { $0 + " " } ?? "") + city)
                                        .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
                                        .padding(.horizontal, 10).padding(.vertical, 5).background(Sketch.paperDeep, in: Capsule())
                                }
                                if let link = source.envelope.sourceURL.flatMap(URL.init(string:)) {
                                    Link(destination: link) {
                                        Label("TikTok", systemImage: "arrow.up.right").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 5).background(Color(hex: "161616"), in: Capsule())
                                    }.accessibilityLabel("Open on TikTok")
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(stage == .pinned ? "Done" : source.extractionStatus == "failed" ? "Stopped" : "In the works")
                                .font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(AppPalette.ink)
                            Spacer()
                            if stage == .pinned, let model = source.extractionModel {
                                Text(model).font(Sketch.text(11, "Medium", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                            }
                        }
                        StudioPipeline(stage: stage, failed: source.extractionStatus == "failed")
                        HStack {
                            ForEach(StudioStage.allCases, id: \.rawValue) { step in
                                Text(step.title).font(Sketch.text(10, "SemiBold", relativeTo: .caption2))
                                    .foregroundStyle(step.rawValue <= stage.rawValue ? AppPalette.ink : AppPalette.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: step == .saved ? .leading : step == .pinned ? .trailing : .center)
                            }
                        }
                        if stage != .pinned {
                            HStack {
                                Text(studioStatus(source)).font(Sketch.text(13, relativeTo: .footnote))
                                    .foregroundStyle(source.extractionStatus == "failed" ? Sketch.coral : AppPalette.secondaryInk)
                                Spacer()
                                if source.extractionStatus == "failed" || source.extractionError != nil {
                                    Button("Retry") { retryExtraction(source.id) }.font(Sketch.text(13, "Bold", relativeTo: .footnote))
                                        .foregroundStyle(AppPalette.ink).padding(.horizontal, 14).frame(minHeight: 36).background(Sketch.paperDeep, in: Capsule())
                                }
                            }
                        } else if let date = source.extractedAt {
                            Text("Read \(date.formatted(.relative(presentation: .named)))").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                        }
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))

                    if !evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            StudioHeading(title: "How we read it")
                            VStack(spacing: 0) {
                                ForEach(Array(evidence.enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 12) {
                                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppPalette.ink).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.title).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).foregroundStyle(AppPalette.ink)
                                            Text(item.detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                                        }
                                        Spacer()
                                        Image(systemName: stage == .pinned ? "checkmark" : "circle.dotted").font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                                    if index < evidence.count - 1 { Rectangle().fill(Sketch.rule.opacity(0.8)).frame(height: 0.7).padding(.leading, 50) }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
                        }
                    }

                    if let tips = source.tips, !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            StudioHeading(title: "Tips", count: tips.count)
                            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(tip.at?.nonEmpty ?? "💡").font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit()
                                        .foregroundStyle(AppPalette.secondaryInk).frame(minWidth: 40, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tip.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(AppPalette.ink)
                                        Text(tip.detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(AppPalette.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
                            }
                            if let note = travelNotes.first(where: { $0.kind == "tips" && $0.sourceIDs.contains(source.id) }) {
                                Button { selectedTravelNoteID = note.id } label: {
                                    Label("Open tips note", systemImage: "note.text").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                                        .foregroundStyle(AppPalette.ink).frame(maxWidth: .infinity, minHeight: 44).background(Sketch.paperDeep, in: Capsule())
                                }.buttonStyle(BubblePressStyle())
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        StudioHeading(title: "Pinned from this post", count: places.count).id("studio-places")
                        if !places.isEmpty {
                            Text("Been there? Tap Your take — a few one-tap questions.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                        }
                        VStack(alignment: .leading, spacing: 12) { ForEach(places) { place in
                            let key = PlaceKey.of(googlePlaceID: place.googlePlaceID, name: place.name, city: place.city)
                            VStack(alignment: .leading, spacing: 6) {
                                PlaceQuickTakeCard(
                                    placeName: place.name, take: takeBinding(key), community: community(key),
                                    subtitle: [place.neighborhood, place.city].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty,
                                    summary: place.summary.nonEmpty, moments: place.moments ?? [],
                                    onAppendNote: { text in appendToPlaceNote(key: key, name: place.name, city: place.city, tripID: place.tripID, text: text) },
                                    onOpenNote: { openPlaceNote(key: key, name: place.name, city: place.city, tripID: place.tripID) },
                                    onOpenLink: mapsLink(name: place.name, googlePlaceID: place.googlePlaceID, latitude: place.latitude, longitude: place.longitude)
                                        .map { url in { UIApplication.shared.open(url) } })
                                if place.latitude == nil {
                                    Label("Not found on Google Maps yet", systemImage: "mappin.slash").font(Sketch.text(11, "SemiBold", relativeTo: .caption2))
                                        .foregroundStyle(Sketch.coral).padding(.leading, 8)
                                }
                            }
                        } }
                        .task(id: places.map(\.id)) {
                            await refreshCommunity(places.map { PlaceKey.of(googlePlaceID: $0.googlePlaceID, name: $0.name, city: $0.city) })
                        }
                        Button {
                            socialPlaceSourceID = source.id; socialPlaceName = ""; socialPlaceSummary = ""
                            socialPlaceCity = cityForSource(source)
                            socialEvidenceID = source.evidence.first?.id ?? ""; showAddSocialPlace = true
                        } label: {
                            Label("Add a place it missed", systemImage: "plus").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                                .foregroundStyle(AppPalette.ink).frame(maxWidth: .infinity, minHeight: 46)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Sketch.rule, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        }.buttonStyle(QuietPressStyle())
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            if let post {
                                ForEach(Array(post.evidenceText.enumerated()), id: \.offset) { _, block in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(["post_caption": "Caption", "on_screen_text": "On-screen text", "auto_caption": "TikTok captions"][block.origin] ?? block.origin)
                                            .font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                                        Text(block.text).font(Sketch.text(13, relativeTo: .footnote)).textSelection(.enabled)
                                    }
                                }
                            }
                            ForEach(source.evidence.filter { $0.origin == "slide_ocr" || post == nil }.sorted { $0.order < $1.order }) { block in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(block.origin == "slide_ocr" ? "Slide \(block.order + 1) · OCR" : "Shared text").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                                    Text(block.text).font(Sketch.text(13, relativeTo: .footnote)).textSelection(.enabled)
                                }
                            }
                            ForEach(source.issues, id: \.self) { Text($0).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk) }
                        }.padding(.top, 10)
                    } label: {
                        Text("What it said").font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(AppPalette.ink)
                    }
                    .tint(AppPalette.ink)
                    .padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))

                    VStack(alignment: .leading, spacing: 10) {
                        StudioHeading(title: "Details")
                        TextField("Title", text: sourceTextBinding(source.id, field: "title")).font(Sketch.text(15, "SemiBold", relativeTo: .body))
                        Divider()
                        TextField("City", text: sourceTextBinding(source.id, field: "city")).font(Sketch.text(15, relativeTo: .body))
                        Divider()
                        Menu {
                            Button("New note", systemImage: "square.and.pencil") { attachSourceToNote(source, noteID: nil) }
                            ForEach(travelNotes) { note in Button(note.title) { attachSourceToNote(source, noteID: note.id) } }
                        } label: { Label("Save to a note", systemImage: "note.text.badge.plus").font(Sketch.text(15, "SemiBold", relativeTo: .body)) }
                            .frame(minHeight: 44).tint(AppPalette.ink)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                }
                .padding(20)
            }
            .task {
                guard StudioDemo.scrollsToPlaces else { return }
                try? await Task.sleep(for: .milliseconds(600)); reader.scrollTo("studio-places", anchor: .top)
            }
            }
            .background(Sketch.paper.ignoresSafeArea())
            .navigationTitle("Post").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedSocialSource = nil } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Read again", systemImage: "arrow.clockwise") { retryExtraction(source.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { selectedSocialSource = nil; deleteLibraryVideo(source.id) }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Post options")
                }
            }
            .sheet(isPresented: $showAddSocialPlace) { socialPlaceReviewSheet(source) }
        }
    }
    func socialPlaceReviewSheet(_ source: ImportedSocialSource) -> some View {
        NavigationStack {
            Form {
                TextField("Place name", text: $socialPlaceName)
                TextField("City / area", text: $socialPlaceCity)
                Picker("Source text", selection: $socialEvidenceID) {
                    ForEach(source.evidence) { Text($0.origin == "slide_ocr" ? "Slide \($0.order + 1)" : "Shared text").tag($0.id) }
                }
                if let evidence = source.evidence.first(where: { $0.id == socialEvidenceID }) { Text(evidence.text).font(.subheadline).textSelection(.enabled) }
                TextField("Short note", text: $socialPlaceSummary, axis: .vertical)
            }
            .navigationTitle("Save place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddSocialPlace = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveTikTokPlace(from: source) } }
                        .disabled(socialPlaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    func travelNoteDetail(_ id: UUID) -> some View {
        let note = travelNotes.first { $0.id == id }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Title", text: Binding(get: { travelNotes.first { $0.id == id }?.title ?? "" }, set: { title in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].title = title; travelNotes[index].updatedAt = .now }
                    })).font(.custom("PlusJakartaSans-Bold", size: 28))
                    Picker("Collection", selection: Binding(get: { travelNotes.first { $0.id == id }?.tripID }, set: { tripID in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].tripID = tripID }
                    })) {
                        Text("Personal notes").tag(UUID?.none)
                        ForEach(trips) { trip in Text(trip.title).tag(Optional(trip.id)) }
                    }
                    if let key = note?.placeKey {
                        let place = note?.linkedPlaces?.first
                        PlaceQuickTakeCard(placeName: note?.title ?? "", take: takeBinding(key), community: community(key),
                                           onOpenLink: mapsLink(name: note?.title ?? "", googlePlaceID: place?.googlePlaceID ?? PlaceKey.googleID(key),
                                                                latitude: place?.latitude, longitude: place?.longitude).map { url in { UIApplication.shared.open(url) } })
                            .task(id: key) { await refreshCommunity([key]) }
                    }
                    if let linkedPlaces = note?.linkedPlaces, !linkedPlaces.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Linked places").font(.headline)
                            ForEach(linkedPlaces) { place in
                                Button {
                                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
                                    item.name = place.name
                                    item.openInMaps()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse").foregroundStyle(AppPalette.brand)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.ink)
                                            Text(place.address).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                    }.padding(12).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                }.buttonStyle(QuietPressStyle())
                            }
                        }
                    }
                    TextField("Your thoughts…", text: Binding(get: { travelNotes.first { $0.id == id }?.userText ?? "" }, set: { text in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].userText = text; travelNotes[index].updatedAt = .now }
                    }), axis: .vertical).font(.body)
                    if let sections = note?.fromSources, !sections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(note?.kind == "guide" ? "The whole video" : note?.kind == "tips" ? (sections.count > 1 ? "Tips from \(sections.count) videos" : "Tips from the video") : sections.count > 1 ? "From \(sections.count) videos" : "From the video")
                                .font(.headline)
                            ForEach(sections.keys.sorted(), id: \.self) { sourceKey in
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("", text: Binding(get: { travelNotes.first { $0.id == id }?.fromSources?[sourceKey] ?? "" }, set: { text in
                                        if let index = travelNotes.firstIndex(where: { $0.id == id }) {
                                            travelNotes[index].fromSources?[sourceKey] = text; travelNotes[index].updatedAt = .now
                                        }
                                    }), axis: .vertical).font(.subheadline)
                                    if let source = socialSources.first(where: { $0.id.uuidString == sourceKey }) {
                                        HStack(spacing: 12) {
                                            Button("Open video") { selectedTravelNoteID = nil; Task { try? await Task.sleep(for: .milliseconds(450)); selectedSocialSource = source } }
                                            if let link = source.envelope.sourceURL.flatMap(URL.init(string:)) { Link("TikTok", destination: link) }
                                        }.font(.caption.weight(.semibold)).tint(AppPalette.brand)
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                    ForEach(socialSources.filter { note?.sourceIDs.contains($0.id) == true && note?.fromSources?[$0.id.uuidString] == nil }) { source in
                        VStack(alignment: .leading, spacing: 16) {
                            Label(sourceStatus(source), systemImage: "link").font(.caption).foregroundStyle(.secondary)
                            ForEach(source.evidence.sorted { $0.order < $1.order }) { block in
                                Text(block.text).font(.body).textSelection(.enabled)
                            }
                            ForEach(socialPlaces.filter { $0.sourceID == source.id }) { place in
                                VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.headline); Text(place.summary).font(.subheadline) }
                            }
                            if let link = source.envelope.sourceURL, let url = URL(string: link) { Link("Original post", destination: url) }
                        }.padding(20).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                }.padding(24)
            }.background(AppPalette.canvas).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedTravelNoteID = nil } } }
        }
    }
    var importLinkSheet: some View {
        NavigationStack {
            Form {
                TextField("TikTok link", text: $importSourceURL).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Text("Link saved to Videos. Media and transcripts appear after retrieval.").font(.caption).foregroundStyle(.secondary)
                if let importLinkError { Text(importLinkError).foregroundStyle(.red) }
            }.navigationTitle("Add a source")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showImportLink = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let url = URL(string: importSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
                                  let host = url.host?.lowercased(), host == "tiktok.com" || host.hasSuffix(".tiktok.com") else {
                                importLinkError = "Enter a valid HTTPS TikTok link."; return
                            }
                            let envelope = SharedSourceEnvelope(id: UUID(), capturedAt: .now, sourceURL: url.absoluteString, sharedText: "", attachments: [],
                                                                destination: ShareDestination(mode: "places", tripID: nil, noteID: nil))
                            socialSources.append(ImportedSocialSource(id: envelope.id, envelope: envelope, evidence: [], state: "needs_retrieval", issues: []))
                            importSourceURL = ""; importLinkError = nil; showImportLink = false
                        }
                    }
                }
        }
    }
}

private struct SharedSourceVideoThumbnail: View {
    let url: URL
    @State private var frame: UIImage?
    var body: some View {
        ZStack {
            if let frame { Image(uiImage: frame).resizable().scaledToFill() }
            else { RoundedRectangle(cornerRadius: 20).fill(AppPalette.ink).overlay(Image(systemName: "play.fill").font(.title).foregroundStyle(.white)) }
            Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
        }
        .frame(height: 172).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: url) {
            let generated = await Task.detached(priority: .utility) { () -> UIImage? in
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                guard let image = try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil) else { return nil }
                return UIImage(cgImage: image)
            }.value
            if !Task.isCancelled { frame = generated }
        }
        .accessibilityLabel("Saved video preview")
    }
}

private struct TikTokLinkPill: View {
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "music.note").font(.system(size: 13, weight: .bold))
                Text("Open TikTok").font(.custom("PlusJakartaSans-Bold", size: 12))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 42)
            .background(LinearGradient(colors: [Color(hex: "343433"), .black], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
            .overlay(alignment: .topLeading) { Capsule().fill(.white.opacity(0.22)).frame(height: 1).padding(.horizontal, 12).offset(y: 2) }
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Open TikTok video")
    }
}

private struct TikTokVideoMemoryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let source: ImportedSocialSource
    let places: [SocialPlaceMention]
    let notes: [TravelNote]
    let city: String
    let onOpenSource: () -> Void
    let onOpenNote: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.listTitle ?? "TikTok save").font(.caption.weight(.bold)).foregroundStyle(LibraryTone.videos.color(colorScheme)).lineLimit(1)
                    Text(source.displayTitle ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok video")
                        .font(.custom("PlusJakartaSans-Bold", size: 16)).foregroundStyle(AppPalette.ink).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !city.isEmpty { Text(city).font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 6).background(AppPalette.surface, in: Capsule()) }
            }
            if let attachment = source.envelope.attachments.first(where: { $0.kind == "video" }),
               let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment) {
                Button(action: onOpenSource) { SharedSourceVideoThumbnail(url: url) }.buttonStyle(QuietPressStyle())
            } else {
                Button(action: onOpenSource) {
                    RoundedRectangle(cornerRadius: 20).fill(AppPalette.ink)
                        .overlay(Image(systemName: "play.rectangle.fill").font(.system(size: 32)).foregroundStyle(.white))
                        .frame(height: 145)
                }.buttonStyle(QuietPressStyle())
            }
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PLACES FROM THIS VIDEO").font(.custom("PlusJakartaSans-ExtraBold", size: 9)).tracking(0.9).foregroundStyle(AppPalette.secondaryInk)
                    ForEach(places) { place in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(LibraryTone.videos.color(colorScheme))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.ink)
                                if let summary = place.summary.nonEmpty { Text(summary).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            ForEach(notes) { note in
                Button { onOpenNote(note.id) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "note.text").foregroundStyle(LibraryTone.videos.color(colorScheme))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title).font(.caption.weight(.bold)).foregroundStyle(AppPalette.ink)
                            Text(note.userText.nonEmpty ?? "Note from this video")
                                .font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                    }.padding(11).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.buttonStyle(QuietPressStyle())
            }
            if let rawURL = source.envelope.sourceURL, let url = URL(string: rawURL) { TikTokLinkPill(url: url) }
        }
        .padding(16).frame(width: 300, alignment: .leading)
        .librarySurface(radius: 26)
    }
}

private struct TikTokPlaceMemoryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let cluster: TikTokPlaceCluster
    let sources: [ImportedSocialSource]
    let notes: [TravelNote]
    let onOpenSource: (UUID) -> Void
    let onOpenNote: (UUID) -> Void
    private var uniqueSources: [ImportedSocialSource] {
        var seen = Set<UUID>()
        return sources.filter { seen.insert($0.id).inserted }.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cluster.title).font(.custom("PlusJakartaSans-Bold", size: 18)).foregroundStyle(AppPalette.ink).lineLimit(1)
                    Text(cluster.city).font(.caption.weight(.medium)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer(minLength: 0)
                Text("\(uniqueSources.count) videos").font(.caption2.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(LibraryTone.videos.color(colorScheme).opacity(0.12), in: Capsule()).foregroundStyle(LibraryTone.videos.color(colorScheme))
            }
            if let summary = cluster.mentions.first(where: { $0.summary.nonEmpty != nil })?.summary.nonEmpty {
                Text(summary).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(uniqueSources) { source in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(source.listTitle ?? source.displayTitle ?? "TikTok save")
                                .font(.caption.weight(.bold)).foregroundStyle(LibraryTone.videos.color(colorScheme)).lineLimit(2).frame(minHeight: 32, alignment: .topLeading)
                            if let attachment = source.envelope.attachments.first(where: { $0.kind == "video" }),
                               let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment) {
                                Button { onOpenSource(source.id) } label: { SharedSourceVideoThumbnail(url: url).frame(width: 206, height: 112) }
                                    .buttonStyle(QuietPressStyle())
                            } else {
                                Button { onOpenSource(source.id) } label: {
                                    RoundedRectangle(cornerRadius: 18).fill(AppPalette.ink)
                                        .overlay(Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.white))
                                        .frame(width: 206, height: 112)
                                }.buttonStyle(QuietPressStyle())
                            }
                            Text(source.displayTitle ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok video")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppPalette.ink).lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
                            ForEach(notes.filter { note in
                                note.placeMentionID.map { id in cluster.mentions.contains(where: { $0.id == id }) } ?? false
                            }) { note in
                                if note.sourceIDs.contains(source.id) {
                                    Button { onOpenNote(note.id) } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Label(note.title, systemImage: "note.text").font(.caption.weight(.bold)).lineLimit(1)
                                            Text(note.userText.nonEmpty ?? "Open note").font(.caption2).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                                        }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(9)
                                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(QuietPressStyle())
                                }
                            }
                            if let rawURL = source.envelope.sourceURL, let url = URL(string: rawURL) { TikTokLinkPill(url: url) }
                        }
                        .padding(11).frame(width: 228, alignment: .leading)
                        .background(AppPalette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .padding(15).frame(width: 326, alignment: .leading)
        .librarySurface(radius: 26)
    }
}

private struct SharedSourceImage: View {
    let url: URL
    @State private var preview: UIImage?
    @State private var finished = false
    var body: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().scaledToFit() }
            else if finished { Label("Image unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary).frame(minHeight: 80) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }.frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 20))
            .task(id: url) {
                let image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
                if !Task.isCancelled { preview = image; finished = true }
            }
            .accessibilityLabel("Source image")
    }
}

private struct GooglePlacesGlyph: View {
    var body: some View {
        Text("Google Maps").font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: "5E5E5E"))
            .accessibilityLabel("Google Maps")
    }
}

private struct GooglePlacesBrandLink: View {
    let url: URL?
    var body: some View {
        HStack(spacing: 7) {
            GooglePlacesGlyph()
            Spacer()
            if let url {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(AppPalette.brand)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}

// MARK: - Place panel design
/// Loads Google Places photos once per session. The bridge returns a short-lived
/// photo URI (or, on older deployments, the image bytes); images stay in memory only.
private actor PlacePhotoPipeline {
    static let shared = PlacePhotoPipeline()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage, Error>] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: configuration)
    }()

    init() { cache.countLimit = 120 }

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func image(name: String, width: Int, baseURL: String, token: String) async throws -> UIImage {
        let key = "\(name)#\(width)"
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] { return try await running.value }
        let task = Task<UIImage, Error> { [session] in
            await self.acquire()
            defer { Task { await self.release() } }
            #if DEBUG
            if name.hasPrefix("demo:"), let demo = UIImage(named: String(name.dropFirst(5))) { return demo }
            #endif
            return try await Self.fetch(name: name, width: width, baseURL: baseURL, token: token, session: session)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private func acquire() async {
        if active < 3 { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }

    enum Failure: LocalizedError {
        case missingToken, server(String)
        var errorDescription: String? {
            switch self {
            case .missingToken: "Add the bridge token in Settings to see photos."
            case .server(let message): message
            }
        }
    }

    private static func fetch(name: String, width: Int, baseURL: String, token: String, session: URLSession) async throws -> UIImage {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.missingToken }
        guard var components = URLComponents(string: baseURL + "/api/places/photo") else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "max_width", value: String(width)),
                                 URLQueryItem(name: "format", value: "uri")]
        guard let url = components.url else { throw URLError(.badURL) }
        var lastError: Error = Failure.server("Photo unavailable.")
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(900 * attempt * attempt)) }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
            if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
            request.setValue("application/json, image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { continue }
            if http.statusCode == 429 || http.statusCode >= 500 {
                lastError = Failure.server(http.statusCode == 429 ? "Busy for a moment — retrying…" : "Photo service unavailable (HTTP \(http.statusCode)).")
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                let failure = try? JSONDecoder().decode(GooglePlacesRequestError.self, from: data)
                throw Failure.server(failure?.message ?? failure?.errorCode ?? failure?.error ?? "Photo unavailable (HTTP \(http.statusCode)).")
            }
            if (http.mimeType ?? "").hasPrefix("image/"), let image = UIImage(data: data) { return image }
            // New gateway: {"photoUri": "https://lh3.googleusercontent.com/…"}; load it straight from Google's CDN.
            struct Pointer: Decodable { let photoUri: String }
            if let pointer = try? JSONDecoder().decode(Pointer.self, from: data), let direct = URL(string: pointer.photoUri) {
                let (bytes, directResponse) = try await session.data(from: direct)
                if let status = (directResponse as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), let image = UIImage(data: bytes) { return image }
                lastError = Failure.server("Photo didn't load.")
                continue
            }
            lastError = Failure.server("Photo didn't load.")
        }
        throw lastError
    }
}

private struct PlacePhotoImage: View {
    let photo: GooglePlacePhoto
    let baseURL: String
    let accessToken: String
    var width = 720
    var tint: Color = Sketch.clay
    var showsRetry = true
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var attempt = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else if let message = failure {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                    if showsRetry {
                        Text(message).font(Sketch.text(11, "Medium", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                            .multilineTextAlignment(.center).lineLimit(3)
                        Button("Try again") { failure = nil; attempt += 1 }
                            .font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(AppPalette.brand)
                            .frame(minHeight: 32)
                    }
                }.padding(10)
            } else {
                PlacePhotoShimmer(tint: tint)
            }
        }
        .clipped()
        .task(id: "\(photo.name)-\(attempt)") {
            if let hit = await PlacePhotoPipeline.shared.cached("\(photo.name)#\(width)") { image = hit; return }
            do {
                let loaded = try await PlacePhotoPipeline.shared.image(name: photo.name, width: width, baseURL: baseURL, token: accessToken)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { image = loaded }
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
        .accessibilityHidden(image == nil)
        .accessibilityLabel("Place photo")
    }
}

private struct PlacePhotoShimmer: View {
    let tint: Color
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 0.6)
                .offset(x: phase * proxy.size.width * 1.4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// Bento of the first three photos; the last tile shows how many more there are.
private struct PlacePhotoMosaic: View {
    let photos: [GooglePlacePhoto]
    let baseURL: String
    let accessToken: String
    let tint: Color
    let onOpen: (Int) -> Void

    var body: some View {
        let shown = Array(photos.prefix(3))
        HStack(spacing: 6) {
            tile(0, shown: shown).frame(maxWidth: .infinity)
            if shown.count > 1 {
                VStack(spacing: 6) {
                    tile(1, shown: shown)
                    if shown.count > 2 { tile(2, shown: shown) }
                }.frame(width: 128)
            }
        }
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func tile(_ index: Int, shown: [GooglePlacePhoto]) -> some View {
        Button { onOpen(index) } label: {
            PlacePhotoImage(photo: shown[index], baseURL: baseURL, accessToken: accessToken, width: index == 0 ? 900 : 480, tint: tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if index == shown.count - 1 && photos.count > shown.count {
                        ZStack {
                            Color.black.opacity(0.38)
                            Text("+\(photos.count - shown.count)").font(Sketch.text(20, "ExtraBold", relativeTo: .title3)).foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(index == 0 ? "Open photos, \(photos.count) in total" : "Open photo \(index + 1)")
    }
}

/// Full-screen pager with the attribution Google requires on every photo.
private struct PlacePhotoViewer: View {
    let title: String
    let photos: [GooglePlacePhoto]
    let baseURL: String
    let accessToken: String
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    PlacePhotoImage(photo: photo, baseURL: baseURL, accessToken: accessToken, width: 1400, tint: .white)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomLeading) { attribution(photo).padding(.bottom, 54) }
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Sketch.text(16, "Bold", relativeTo: .headline)).lineLimit(1)
                    Text("\(index + 1) of \(photos.count)").font(Sketch.text(12, "Medium", relativeTo: .caption))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.16), in: Circle())
                }.accessibilityLabel("Close photos")
            }
            .foregroundStyle(.white).padding(.horizontal, 16).padding(.top, 8)
        }
    }

    @ViewBuilder private func attribution(_ photo: GooglePlacePhoto) -> some View {
        let author = photo.authorAttributions?.first
        HStack(spacing: 6) {
            Image(systemName: "camera.fill").font(.system(size: 10, weight: .semibold))
            if let author, let url = author.uri.flatMap({ URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0) }) {
                Link(author.displayName, destination: url)
            } else { Text(author?.displayName ?? "Google Maps") }
            Text("· Google Maps").opacity(0.7)
        }
        .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 16)
    }
}

/// When there are no photos the hero becomes a painted card with the category's doodle.
private struct PlacePaintedHero: View {
    let doodle: Doodle
    let tint: Color
    let caption: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.30), Sketch.ochre.opacity(0.16), Sketch.paperDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(tint.opacity(0.22)).frame(width: 170).offset(x: 110, y: -40).blur(radius: 6)
            Circle().fill(Sketch.ochre.opacity(0.20)).frame(width: 120).offset(x: -120, y: 50).blur(radius: 4)
            DoodleView(doodle: doodle, tint: tint, lineWidth: 2.6).frame(width: 96, height: 96)
            Text(caption).font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(14)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Small tilted print of the first photo used in the collapsed header.
private struct PlacePolaroid: View {
    let photo: GooglePlacePhoto?
    let baseURL: String
    let accessToken: String
    let tint: Color
    let symbol: String
    var body: some View {
        ZStack {
            if let photo {
                PlacePhotoImage(photo: photo, baseURL: baseURL, accessToken: accessToken, width: 320, tint: tint, showsRetry: false)
            } else {
                ZStack {
                    tint.opacity(0.18)
                    Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
                }
            }
        }
        .frame(width: 66, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Sketch.card))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}

private struct PlaceInfoRow: View {
    let symbol: String
    let text: String
    var detail: String? = nil
    var tint: Color = AppPalette.ink
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(AppPalette.secondaryInk).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(Sketch.text(14, "Medium", relativeTo: .subheadline)).foregroundStyle(tint)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk) }
            }
            Spacer(minLength: 6)
            if let trailing { Image(systemName: trailing).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.secondaryInk) }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(minHeight: 48).contentShape(Rectangle())
    }
}

/// Address, hours, phone and website in one grouped card.
private struct PlaceInfoCard: View {
    let address: String?
    let details: GooglePlaceDetails?
    let phone: String?
    let website: String?
    let onAddress: () -> Void
    @State private var showHours = false

    var body: some View {
        VStack(spacing: 0) {
            if let address {
                Button(action: onAddress) { PlaceInfoRow(symbol: "mappin.and.ellipse", text: address, trailing: "arrow.turn.up.right") }
                    .buttonStyle(.plain).accessibilityHint("Gets directions")
                divider
            }
            if let details, !details.openingHours.isEmpty {
                Button { withAnimation(.snappy) { showHours.toggle() } } label: {
                    PlaceInfoRow(symbol: "clock", text: details.openNow == false ? "Closed now" : details.openNow == true ? "Open now" : "Opening hours",
                                 detail: today(details.openingHours),
                                 trailing: showHours ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain)
                if showHours {
                    VStack(spacing: 6) {
                        ForEach(Array(details.openingHours.enumerated()), id: \.offset) { _, line in
                            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
                            let isToday = line == todayLine(details.openingHours)
                            HStack(alignment: .firstTextBaseline) {
                                Text(pieces[0]).font(Sketch.text(12, isToday ? "Bold" : "Medium", relativeTo: .caption))
                                Spacer(minLength: 8)
                                if pieces.count > 1 {
                                    Text(pieces[1].trimmingCharacters(in: .whitespaces)).font(Sketch.text(12, isToday ? "Bold" : "Regular", relativeTo: .caption))
                                        .multilineTextAlignment(.trailing)
                                }
                            }.foregroundStyle(isToday ? AppPalette.ink : AppPalette.secondaryInk)
                        }
                    }.padding(.leading, 48).padding(.trailing, 14).padding(.bottom, 12)
                }
                divider
            }
            if let phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) { PlaceInfoRow(symbol: "phone", text: phone) }.accessibilityLabel("Call \(phone)")
                divider
            }
            if let website, let url = URL(string: website) {
                Link(destination: url) { PlaceInfoRow(symbol: "globe", text: url.host()?.replacingOccurrences(of: "www.", with: "") ?? "Website", trailing: "arrow.up.right") }
                divider
            }
            if let maps = details?.googleMapsURL.flatMap(URL.init(string:)) {
                Link(destination: maps) { PlaceInfoRow(symbol: "map", text: "Google Maps", trailing: "arrow.up.right") }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
    }
    private var divider: some View { Rectangle().fill(Sketch.rule.opacity(0.8)).frame(height: 0.7).padding(.leading, 48) }
    private func todayLine(_ lines: [String]) -> String? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "EEEE"
        let day = formatter.string(from: .now)
        return lines.first { $0.hasPrefix(day) }
    }
    private func today(_ lines: [String]) -> String? {
        todayLine(lines)?.split(separator: ":", maxSplits: 1).last.map { "Today · " + $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Reviews as colourful cards that swipe sideways.
private struct PlaceReviewStrip: View {
    let reviews: [GooglePlaceReview]
    private let washes: [Color] = [Sketch.coral, Sketch.ochre, Sketch.sage, Sketch.sky, Sketch.plum]
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(Array(reviews.enumerated()), id: \.element.id) { offset, review in card(review, wash: washes[offset % washes.count]) }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }
    private func card(_ review: GooglePlaceReview, wash: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { star in
                    Image(systemName: Double(star) < (review.rating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .bold))
                }
            }.foregroundStyle(Sketch.ochre)
            Text(review.text.nonEmpty ?? "No written review.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(AppPalette.ink)
                .lineSpacing(2).lineLimit(6).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let avatar = review.authorPhotoURL.flatMap(URL.init(string:)) { GoogleAuthorAvatar(url: avatar) }
                VStack(alignment: .leading, spacing: 1) {
                    if let profile = review.authorURL.flatMap(URL.init(string:)) {
                        Link(review.authorName, destination: profile).font(Sketch.text(12, "Bold", relativeTo: .caption))
                    } else { Text(review.authorName).font(Sketch.text(12, "Bold", relativeTo: .caption)) }
                    Text(review.relativeTime).font(Sketch.text(10, relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                }.lineLimit(1)
            }.foregroundStyle(AppPalette.ink)
        }
        .padding(16)
        .frame(width: 262, alignment: .topLeading)
        .frame(minHeight: 168, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card)
                .overlay(alignment: .topTrailing) {
                    Text("\u{201C}").font(.system(size: 76, weight: .black, design: .serif)).foregroundStyle(AppPalette.ink.opacity(0.06))
                        .offset(x: -10, y: -14).accessibilityHidden(true)
                }
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// TikTok-style poster for a saved video linked to this place.
private struct PlaceVideoPoster: View {
    let title: String
    let summary: String?
    let videoURL: URL?
    let imageURL: URL?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let videoURL { SharedSourceVideoThumbnail(url: videoURL) }
                else if let imageURL { SharedSourcePosterImage(url: imageURL) }
                else { LinearGradient(colors: [Color(hex: "25F4EE").opacity(0.5), Color(hex: "FE2C55").opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
            .frame(width: 132, height: 200).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Sketch.text(12, "Bold", relativeTo: .caption)).lineLimit(2)
                if let summary { Text(summary).font(Sketch.text(10, relativeTo: .caption2)).opacity(0.8).lineLimit(2) }
            }.foregroundStyle(.white).padding(10)
        }
        .frame(width: 132, height: 200)
        .overlay(alignment: .topLeading) {
            Image(systemName: "music.note").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: Color(hex: "25F4EE").opacity(0.9), radius: 0, x: -1, y: -1)
                .shadow(color: Color(hex: "FE2C55").opacity(0.9), radius: 0, x: 1, y: 1)
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
    }
}

enum SharedSourceImageURL {
    static var overrides: [UUID: URL] = [:]
    static func resolve(_ sourceID: UUID, _ attachment: SharedAttachment) -> URL? {
        overrides[sourceID] ?? SharedInbox.attachmentURL(sourceID: sourceID, attachment: attachment)
    }
}

/// DEBUG `-TrippyStudioDemo [-TrippyStudioDetail]`: sample posts in every pipeline state, never persisted.
enum StudioDemo {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-TrippyStudioDemo")
        #else
        false
        #endif
    }
    static var opensDetail: Bool { enabled && (ProcessInfo.processInfo.arguments.contains("-TrippyStudioDetail") || opensReady) }
    /// Opens a read post (with places, the caption timeline and the quick-take card) instead of a queued one.
    static var opensReady: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-TrippyStudioReady") }
    static var scrollsToPlaces: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-TrippyStudioPlaces") }
    static func load() -> (sources: [ImportedSocialSource], places: [SocialPlaceMention])? {
        guard enabled else { return nil }
        func post(_ id: String, _ handle: String, _ caption: String, slides: Int = 0, stickers: [String] = [], duration: Int = 0, title: String? = nil) -> TikTokPostSnapshot {
            TikTokPostSnapshot(postID: id, canonicalURL: "https://www.tiktok.com/@\(handle)/video/\(id)", isSlideshow: slides > 0, authorHandle: handle, authorName: handle,
                               caption: caption, slideshowTitle: title, onScreenText: stickers, slideCount: slides, transcript: nil, transcriptLanguage: nil,
                               durationSeconds: duration, region: "GR", topicLabels: [], mentions: [], hashtags: [], likes: nil, saves: nil, musicTitle: nil,
                               coverURL: nil, fetchedAt: .now)
        }
        func source(_ image: String, _ snapshot: TikTokPostSnapshot?, status: String?, error: String? = nil, title: String? = nil, summary: String? = nil, ago: Double) -> ImportedSocialSource {
            let id = UUID()
            if let picture = UIImage(named: image), let data = picture.jpegData(compressionQuality: 0.8) {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("studio-demo-\(image).jpg")
                try? data.write(to: file); SharedSourceImageURL.overrides[id] = file
            }
            let envelope = SharedSourceEnvelope(id: id, capturedAt: .now.addingTimeInterval(-ago), sourceURL: snapshot?.canonicalURL, sharedText: "",
                attachments: [SharedAttachment(id: UUID(), filename: "cover.jpg", kind: "cover", order: 0)] + (0..<(snapshot?.slideCount ?? 0)).map { SharedAttachment(id: UUID(), filename: "slide-\($0).jpg", kind: "image", order: $0 + 1) },
                destination: ShareDestination(mode: "places", tripID: nil, noteID: nil), tiktok: snapshot)
            var item = ImportedSocialSource(id: id, envelope: envelope, evidence: [], state: status == "ready" ? "ready" : "pending", issues: [])
            item.extractionStatus = status; item.extractionError = error; item.displayTitle = title; item.summary = summary
            item.city = "Athens"; item.countryCode = "GR"; item.extractionModel = status == "ready" ? "gemini-3.6-flash" : nil
            item.extractedAt = status == "ready" ? .now.addingTimeInterval(-ago + 60) : nil
            return item
        }
        let cozy = source("TripSantorini", post("7703109951702437142", "eleni__vasileiou", "#fypgr #athensspots", slides: 7, title: "Cozy Spots - Athens"), status: "ready",
                          title: "Cozy Spots in Athens", summary: "Six cozy cafés and bars for cold days around Athens.", ago: 3600)
        let voul = source("TripLisbon", post("7704754316732714262", "mario_sli", "Δοκιμάζουμε το Voulkanizater στο 📍Κουκάκι", stickers: ["Voulkanizater"], duration: 37), status: "ready",
                          title: "Voulkanizater in Koukaki", summary: "A cozy first-date restaurant with creative shared plates.", ago: 7200)
        let okupa = source("TripRome", post("7683909999734689046", "thefoodyfinds", "Το 📍@okupa.athens…", slides: 10, title: "Your go-to bar in Athens🍸"), status: "ready",
                           title: "Okupa Kitchen & Listening Bar", summary: "All-day kitchen and listening bar.", ago: 86_400)
        let anasa = source("TripKyoto", post("7690960467153407254", "thefoodyfinds", "Anasa Spritzeria ✨🍸 📍Exarcheia", stickers: ["Signature spritz", "Pinsa"], duration: 12),
                           status: "queued", error: "Waiting for free Gemini quota", ago: 120)
        let reading = source("TripBali", post("7704373081128652054", "thefoodyfinds", "We definitely love a good burger spot! 👀✨", duration: 42), status: "running", ago: 60)
        let failed = source("TripNewYork", nil, status: "failed", error: "TikTok didn't return this post. It may be private.", ago: 30)
        var tips = source("TripBali", post("7704373081128652099", "athens.local", "Things I wish I knew before Athens", duration: 48), status: "ready",
                          title: "Athens: what I wish I knew", summary: "Practical first-trip advice for Athens.", ago: 5400)
        tips.postKind = "tips"
        tips.tips = [SocialTip(title: "Metro from the airport", detail: "Line 3 goes straight to Syntagma; buy the €9 airport ticket.", at: "0:04"),
                     SocialTip(title: "Acropolis at opening", detail: "Be at the gate at 8:00, the cruise groups arrive by 10.", at: "0:17"),
                     SocialTip(title: "Tipping", detail: "Round up or leave about 10% at sit-down places.", at: "0:31")]
        func place(_ name: String, _ source: ImportedSocialSource, _ category: String, _ hood: String, _ tldr: String, found: Bool = true) -> SocialPlaceMention {
            SocialPlaceMention(id: UUID(), name: name, summary: tldr, sourceID: source.id, evidenceIDs: [], tripID: nil,
                               latitude: found ? 37.97 : nil, longitude: found ? 23.73 : nil, city: "Athens", category: category, neighborhood: hood, countryCode: "GR")
        }
        var voulkanizater = place("Voulkanizater", voul, "Food", "Koukaki", "Warm, dimly lit spot for a first date.")
        voulkanizater.moments = [SocialMoment(at: "0:02", text: "Hidden spot in Koukaki, easy to walk past"),
                                 SocialMoment(at: "0:09", text: "“The burnt leek is the dish you come back for”"),
                                 SocialMoment(at: "0:21", text: "Book on weekends, it fills by 9"),
                                 SocialMoment(at: "0:30", text: "About €25 a head with wine")]
        voulkanizater.googlePlaceID = "demo-voulkanizater"
        let places = [voulkanizater, place("Acapus", cozy, "Bars", "Exarcheia", "Board-game bar with warm, dim corners."), place("Minu", cozy, "Coffee", "Psyrri", "Plant-filled design café."),
                      place("Bel Ray", cozy, "Coffee", "Koukaki", "Retro neighbourhood café-bar."), place("Trigono", cozy, "Coffee", "Pangrati", "Old-school kafeneio for slow afternoons."),
                      place("Easy Peasy", cozy, "Coffee", "Peristeri", "Cozy café with a summer rooftop vibe."), place("Usurum", cozy, "Bars", "Psyrri", "Lively brunch and cocktails spot."),
                      place("Okupa", okupa, "Bars", "Kerameikos", "Greek–Eastern Med plates and vinyl.", found: false)]
        return (opensReady ? [voul, anasa, reading, failed, cozy, okupa, tips] : [anasa, reading, failed, cozy, voul, okupa, tips], places)
    }
}

struct SharedSourcePosterImage: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.black
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
            if !Task.isCancelled { image = loaded }
        }
    }
}

private extension MapPlaceCategory {
    var doodle: Doodle {
        switch self {
        case .coffee, .brunch: .cup
        case .restaurants, .streetFood, .burgers, .seafood, .vegan, .groceries: .fork
        case .bars, .clubs: .moon
        case .sights: .columns
        case .shopping, .touristShops: .bag
        case .parks: .mountain
        case .metro: .tram
        case .other: .map
        }
    }
}

/// DEBUG-only: `-TrippyPlacePanelDemo [-TrippyPlacePanelDetent small|medium|large] [-TrippyPlacePanelNoPhotos]`
/// opens a sample place with bundled images so the panel can be checked without a bridge token.
private enum PlacePanelDemo {
    static let pinID = "demo-place-panel"
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-TrippyPlacePanelDemo")
        #else
        false
        #endif
    }
    static var detent: PresentationDetent? {
        guard enabled, let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-TrippyPlacePanelDetent"),
              index + 1 < ProcessInfo.processInfo.arguments.count else { return nil }
        switch ProcessInfo.processInfo.arguments[index + 1] {
        case "medium": return .height(560)
        case "large": return .large
        default: return nil
        }
    }
    static var scrollsToReviews: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-TrippyPlacePanelReviews") }
    static var opensViewer: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-TrippyPlacePanelViewer") }
    static var pin: WorkspaceMapPin {
        WorkspaceMapPin(id: pinID, name: "Easy Peasy", coordinate: .init(latitude: 38.0139, longitude: 23.6934), layer: "search",
                        category: .coffee, city: "Athens", address: "Peristeri, Greece")
    }
    static func details(for pin: WorkspaceMapPin) -> GooglePlaceDetails? {
        guard enabled, pin.id == pinID else { return nil }
        let noPhotos = ProcessInfo.processInfo.arguments.contains("-TrippyPlacePanelNoPhotos")
        let photos = noPhotos ? [] : ["TripLisbon", "TripRome", "TripSantorini", "TripKyoto", "TripBali", "TripNewYork"].map {
            GooglePlacePhoto(name: "demo:" + $0, authorAttributions: [GooglePlaceAttribution(displayName: "Sample photographer", uri: nil, photoUri: nil)], googleMapsURL: nil)
        }
        let reviews = [
            GooglePlaceReview(rating: 5, text: "Tiny rooftop with the best freddo in the west of Athens. Go before sunset and grab the corner table.", relativeTime: "2 weeks ago", authorName: "Maria K.", authorURL: nil, authorPhotoURL: nil, googleMapsURL: "demo-1", visitDate: nil),
            GooglePlaceReview(rating: 4, text: "Cozy on cold days, lovely music, a little slow on weekends.", relativeTime: "a month ago", authorName: "Nikos", authorURL: nil, authorPhotoURL: nil, googleMapsURL: "demo-2", visitDate: nil),
            GooglePlaceReview(rating: 5, text: "Came for the coffee, stayed for the cocktails. Friendly team.", relativeTime: "3 months ago", authorName: "Elena V.", authorURL: nil, authorPhotoURL: nil, googleMapsURL: "demo-3", visitDate: nil)
        ]
        return GooglePlaceDetails(placeID: "demo", name: "Easy Peasy", address: "Ethnikis Antistaseos 12, Peristeri 121 34, Greece",
            latitude: 38.0139, longitude: 23.6934, primaryType: "Cafe", rating: 4.6, reviewCount: 1284, openNow: true,
            openingHours: ["Monday: 8:00 AM – 12:00 AM", "Tuesday: 8:00 AM – 12:00 AM", "Wednesday: 8:00 AM – 12:00 AM", "Thursday: 8:00 AM – 1:00 AM",
                           "Friday: 8:00 AM – 2:00 AM", "Saturday: 9:00 AM – 2:00 AM", "Sunday: 9:00 AM – 12:00 AM"],
            phoneNumber: "+30 21 0574 2689", websiteURL: "https://www.example.com", googleMapsURL: "https://maps.google.com",
            summary: "Cozy cafe with a summer rooftop vibe — coffee by day, drinks and snacks by night.", photos: photos, reviews: reviews)
    }
}

/// "You're back" recap of shares that finished processing while the user was away.
struct ShareSummary: Identifiable {
    let id = UUID()
    let videos: Int
    let places: Int
    let cities: [String]
    let countries: [String]
    let covers: [URL]
    let sharedSince: Date
    var coverImages: [UIImage] { covers.compactMap { UIImage(contentsOfFile: $0.path) } }
    var demoImages: [UIImage] = []

    /// DEBUG `-TrippySummaryDemo`: sample numbers and bundled photos for screenshots.
    static var demo: ShareSummary? {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-TrippySummaryDemo") else { return nil }
        var sample = ShareSummary(videos: 4, places: 9, cities: ["Athens"], countries: ["GR"], covers: [], sharedSince: .now.addingTimeInterval(-86_400 * 2))
        sample.demoImages = ["TripLisbon", "TripSantorini", "TripRome"].compactMap { UIImage(named: $0) }
        return sample
        #else
        return nil
        #endif
    }
}

/// A short, skippable recap. The same numbers live permanently at the top of Library › Videos.
private struct ShareSummarySheet: View {
    let summary: ShareSummary
    let onDone: () -> Void
    let onOpenStudio: () -> Void
    let onStopShowing: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let images = summary.demoImages.isEmpty ? summary.coverImages : summary.demoImages
        let flags = summary.countries.prefix(3).map(MarkGlyphCatalog.flag).joined()
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 46, height: 66).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .padding(2.5).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Sketch.card))
                            .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
                            .rotationEffect(.degrees(appeared ? [-9.0, 3.0, 12.0][index] : 0))
                            .offset(x: appeared ? [-14.0, 2.0, 18.0][index] : 0)
                    }
                    if images.isEmpty { Image(systemName: "music.note").font(.title).foregroundStyle(AppPalette.ink) }
                }
                .frame(width: 96, height: 80).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're back").font(Sketch.text(22, "ExtraBold", relativeTo: .title2)).tracking(-0.4).foregroundStyle(AppPalette.ink)
                    Text("Since your last visit we read your shares.").font(Sketch.text(13, relativeTo: .footnote))
                        .foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                StudioStat(value: "\(summary.videos)", label: summary.videos == 1 ? "Video" : "Videos")
                StudioStat(value: "\(summary.places)", label: summary.places == 1 ? "Place" : "Places")
                StudioStat(value: "\(summary.cities.count)", label: summary.cities.count == 1 ? summary.cities[0] : "Cities")
                StudioStat(value: flags.isEmpty ? "–" : flags, label: summary.countries.count == 1 ? "Country" : "Countries")
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
            HStack(spacing: 10) {
                Button("Open studio", action: onOpenStudio)
                    .font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Sketch.paperDeep, in: Capsule())
                Button("Done", action: onDone)
                    .font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50).background(AppPalette.brand, in: Capsule())
            }.buttonStyle(QuietPressStyle())
            Button("Don't show recaps", action: onStopShowing)
                .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(AppPalette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityHint("You can turn recaps back on from the Studio menu in Library › Videos.")
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)
        .background(Sketch.paper.ignoresSafeArea())
        .presentationDetents([.height(372)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { appeared = true } }
    }
}

// MARK: - Video studio (Library › Videos)
/// Where a shared post is in the share → read → Gemini → pins pipeline.
enum StudioStage: Int, CaseIterable {
    case saved, read, thinking, pinned
    var title: String {
        switch self { case .saved: "Saved"; case .read: "Read"; case .thinking: "Gemini"; case .pinned: "Pinned" }
    }
    static func of(_ source: ImportedSocialSource) -> StudioStage {
        if source.extractionStatus == "ready" { return .pinned }
        if source.extractionStatus == "queued" || source.extractionStatus == "running" { return .thinking }
        return source.envelope.tiktok != nil ? .read : .saved
    }
}

/// The evidence a post gave us, shown as small marks on posters and in "How we read it".
struct StudioEvidence: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    static func of(_ source: ImportedSocialSource) -> [StudioEvidence] {
        var items: [StudioEvidence] = []
        let post = source.envelope.tiktok
        if let caption = post?.caption, !caption.isEmpty {
            items.append(.init(id: "caption", symbol: "text.quote", title: "Caption", detail: "\(caption.count) characters"))
        } else if !source.envelope.sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.init(id: "caption", symbol: "text.quote", title: "Shared text", detail: "From the share sheet"))
        }
        if let lines = post?.onScreenText, !lines.isEmpty {
            items.append(.init(id: "stickers", symbol: "textformat", title: "On-screen text", detail: "\(lines.count) text \(lines.count == 1 ? "sticker" : "stickers")"))
        }
        let slides = source.envelope.attachments.filter { $0.kind == "image" }.count
        if slides > 0 {
            let ocr = source.evidence.filter { $0.origin == "slide_ocr" }.count
            items.append(.init(id: "slides", symbol: "photo.stack", title: "Slides", detail: "\(slides) images, seen by Gemini" + (ocr > 0 ? " · \(ocr) with OCR text" : "")))
        }
        if let transcript = post?.transcript, !transcript.isEmpty {
            items.append(.init(id: "captions", symbol: "captions.bubble", title: "TikTok captions", detail: post?.transcriptLanguage ?? "Auto-generated"))
        } else if let post, !post.isSlideshow, (post.durationSeconds ?? 0) > 0 {
            items.append(.init(id: "audio", symbol: "waveform", title: "Audio", detail: "\(post.durationSeconds ?? 0)s, transcribed by Gemini"))
        }
        return items
    }
}

struct StudioStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Sketch.text(22, "ExtraBold", relativeTo: .title2)).foregroundStyle(AppPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            Text(label).font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small cover for a post: TikTok cover, first slide, or a two-tone TikTok wash.
struct StudioCover: View {
    let url: URL?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1D1B1A"), Color(hex: "2C2826")], startPoint: .top, endPoint: .bottom)
            if let url { SharedSourcePosterImage(url: url) }
            else {
                Image(systemName: "music.note").font(.system(size: 22, weight: .black)).foregroundStyle(.white.opacity(0.85))
                    .shadow(color: Color(hex: "25F4EE"), radius: 0, x: -1.5, y: -1.5)
                    .shadow(color: Color(hex: "FE2C55"), radius: 0, x: 1.5, y: 1.5)
            }
        }.clipped()
    }
}

/// Step dots: Saved → Read → Gemini → Pinned, the current one pulsing.
struct StudioPipeline: View {
    let stage: StudioStage
    var failed = false
    var dark = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(StudioStage.allCases, id: \.rawValue) { step in
                let done = step.rawValue < stage.rawValue || stage == .pinned
                let current = step == stage && stage != .pinned
                Capsule()
                    .fill(failed && current ? Sketch.coral : done ? (dark ? Color.white : AppPalette.ink) : (dark ? Color.white.opacity(0.25) : Sketch.rule))
                    .frame(height: 4)
                    .opacity(current && !failed && pulse ? 0.45 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel(failed ? "Stopped at \(stage.title)" : stage == .pinned ? "Done" : "Step \(stage.rawValue + 1) of 4, \(stage.title)")
    }
}

/// Card in the "In the works" lane.
struct StudioWorkCard: View {
    let title: String
    let author: String?
    let cover: URL?
    let stage: StudioStage
    let status: String
    let failed: Bool
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            StudioCover(url: cover).frame(width: 54, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(AppPalette.ink).lineLimit(2)
                if let author { Text("@\(author)").font(Sketch.text(12, "Medium", relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk).lineLimit(1) }
                StudioPipeline(stage: stage, failed: failed)
                HStack(spacing: 6) {
                    Text(status).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(failed ? Sketch.coral : AppPalette.secondaryInk).lineLimit(2)
                    Spacer(minLength: 4)
                    if failed {
                        Button("Retry", action: onRetry).font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(AppPalette.ink)
                            .padding(.horizontal, 12).frame(minHeight: 32).background(Sketch.paperDeep, in: Capsule())
                    }
                }
            }
        }
        .padding(12).frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
    }
}

/// TikTok-style poster for a finished post.
struct StudioPosterCard: View {
    let title: String
    let author: String?
    let cover: URL?
    let placeCount: Int
    let evidence: [StudioEvidence]
    let isSlideshow: Bool
    /// Links out of the video: the notes it wrote and the trip it was saved to.
    var noteCount = 0
    var trip: String? = nil
    var body: some View {
        Color.clear
            .aspectRatio(9 / 14, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { StudioCover(url: cover) }
            .clipped()
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.25),
                                       .init(color: .clear, location: 0.5), .init(color: .black.opacity(0.82), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Image(systemName: isSlideshow ? "photo.stack.fill" : "play.fill").font(.system(size: 9, weight: .bold))
                    if placeCount > 0 { Text("\(placeCount)").font(Sketch.text(11, "Bold", relativeTo: .caption2)) + Text(placeCount == 1 ? " place" : " places").font(Sketch.text(11, "Medium", relativeTo: .caption2)) }
                }
                .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                .background(.black.opacity(0.45), in: Capsule()).padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if noteCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.system(size: 9, weight: .bold))
                        Text("\(noteCount)").font(Sketch.text(11, "Bold", relativeTo: .caption2))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.45), in: Capsule()).padding(8)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    if let trip {
                        Label(trip, systemImage: "airplane").font(Sketch.text(10, "Bold", relativeTo: .caption2)).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.22), in: Capsule())
                    }
                    Text(title).font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let author { Text("@\(author)").font(Sketch.text(11, "Medium", relativeTo: .caption2)).opacity(0.85).lineLimit(1) }
                        Spacer(minLength: 2)
                        HStack(spacing: 4) {
                            ForEach(evidence.prefix(4)) { item in Image(systemName: item.symbol).font(.system(size: 9, weight: .semibold)) }
                        }.opacity(0.85).accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.white).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)\(author.map { ", by \($0)" } ?? ""), \(placeCount) places")
    }
}

/// Section title in the studio: small caps with a count.
struct StudioHeading: View {
    let title: String
    var count: Int? = nil
    var flag: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let flag { Text(flag).font(.system(size: 13)) }
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(1.1).foregroundStyle(AppPalette.secondaryInk)
            if let count { Text("\(count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(AppPalette.secondaryInk)
                .padding(.horizontal, 7).padding(.vertical, 2).background(Sketch.paperDeep, in: Capsule()) }
            Spacer()
        }.accessibilityAddTraits(.isHeader)
    }
}

/// Mio-style collapsible note list (Pro tips, Must try, …) built from the place's videos.
private struct PlaceNoteCard: View {
    let title: String
    let symbol: String
    let items: [String]
    @State private var open = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppPalette.ink).frame(width: 22)
                    Text(title).font(Sketch.text(16, "Bold", relativeTo: .headline)).foregroundStyle(AppPalette.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }.frame(minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(.isHeader)
            if open {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(AppPalette.secondaryInk).frame(width: 4, height: 4).offset(y: -2)
                            Text(item).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(AppPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(.leading, 32)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
    }
}

/// Ivory paper with a soft wash of the place's category colour.
private struct PlacePanelBackdrop: View {
    let tint: Color
    var body: some View {
        ZStack(alignment: .top) {
            Sketch.paper
        }
        .ignoresSafeArea()
    }
}

private struct GoogleAuthorAvatar: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Circle().fill(AppPalette.brand.opacity(0.15)).overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(AppPalette.brand)) }
        }
        .frame(width: 28, height: 28).clipShape(Circle())
        .task(id: url) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data), !Task.isCancelled else { return }
            image = decoded
        }
    }
}

private struct DirectionsLayer: ViewModifier {
    let apply: (AnyView) -> AnyView
    func body(content: Content) -> some View { apply(AnyView(content)) }
}

private struct DirectionsPickerTarget: Identifiable { let start: Bool; var id: Bool { start } }

private struct RouteStepsSheet: View {
    let route: MKRoute
    @Environment(\.dismiss) private var dismiss

    private var steps: [MKRoute.Step] { route.steps.filter { !$0.instructions.isEmpty } }
    private var durationText: String {
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: route.transportType == .walking ? "figure.walk" : "car.fill").font(.title2.weight(.semibold))
                            .foregroundStyle(AppPalette.brand).frame(width: 48, height: 48)
                            .background(AppPalette.brand.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.transportType == .walking ? "Walking route" : "Driving route").font(.headline)
                            Text("\(distanceText(route.distance)) · \(durationText)")
                                .font(.subheadline).foregroundStyle(AppPalette.secondaryInk)
                        }
                    }.padding(.vertical, 5)
                }
                Section("Steps") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)").font(.caption.weight(.bold))
                                .foregroundStyle(AppPalette.ink).frame(width: 26, height: 26)
                                .background(AppPalette.brand.opacity(0.2), in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.instructions).font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.ink)
                                if step.distance > 0 {
                                    Text(distanceText(step.distance)).font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    if steps.isEmpty {
                        Text("No step-by-step directions for this route.")
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One colour per day, shared by the route lines, the stop markers and the day chips.
enum TripDayPalette {
    static func color(_ day: Int, dark: Bool) -> Color {
        let colors = dark
            ? [Color(hex: "8BCEAB"), Color(hex: "FF957D"), Color(hex: "91C9E4"), Color(hex: "D6BD86")]
            : [AppPalette.brand, Color(hex: "CE6651"), Color(hex: "427E9B"), Color(hex: "8D7846")]
        return colors[max(0, day) % colors.count]
    }
}

/// A place on the trip map: a numbered disc in the day's colour for planned
/// stops, a small quiet disc for suggestions. The name sits beside it only when
/// the map has room (decided by the canvas), so labels never pile up.
private struct TripStopMarker: View {
    let name: String
    let symbol: String
    let tint: Color
    var number: Int? = nil
    var extra = 0
    var showsLabel = false
    var focused = false
    @Environment(\.colorScheme) private var scheme
    private var planned: Bool { number != nil }
    var body: some View {
        ZStack {
            if let number {
                Circle().fill(tint).frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .overlay {
                        Text("\(number)").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : .white)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
            } else {
                Circle().fill(Sketch.card).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1.2))
                    .overlay { Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint) }
                    .shadow(color: .black.opacity(0.14), radius: 2.5, y: 1)
            }
            if extra > 0 {
                Text("+\(extra)").font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(AppPalette.inverseInk)
                    .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                    .background(AppPalette.ink, in: Capsule())
                    .overlay(Capsule().strokeBorder(Sketch.card, lineWidth: 1.2))
                    .offset(x: 12, y: -11)
            }
            if focused {
                Circle().strokeBorder(tint, lineWidth: 2).frame(width: planned ? 36 : 32, height: planned ? 36 : 32)
            }
        }
        .frame(width: 44, height: 44).contentShape(Circle())
        .overlay(alignment: .leading) {
            if showsLabel || focused {
                Text(name).font(.custom(planned ? "PlusJakartaSans-Bold" : "PlusJakartaSans-SemiBold", size: 12))
                    .foregroundStyle(planned ? AppPalette.ink : AppPalette.secondaryInk)
                    .lineLimit(1).frame(maxWidth: 160, alignment: .leading).fixedSize()
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(Sketch.card.opacity(0.94), in: Capsule())
                    .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    .offset(x: 38).allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number.map { "Stop \($0), \(name)" } ?? "Suggestion, \(name)")
        .accessibilityHint(extra > 0 ? "\(extra) more nearby. Double tap to zoom in." : "")
    }
}

// Quiet content, expressive title, glass reserved for floating controls.
private struct MapTripTitle: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).font(.custom("Georgia-BoldItalic", size: 32, relativeTo: .largeTitle))
            .tracking(-1).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppPalette.ink)
            .shadow(color: scheme == .dark ? .black.opacity(0.85) : .white.opacity(0.95), radius: 3)
            .shadow(color: scheme == .dark ? .black.opacity(0.5) : .white.opacity(0.8), radius: 8)
    }
}
private struct SelectedMapChip: ViewModifier {
    let selected: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if selected { content.background(AppPalette.brand, in: Capsule()) }
        else { content.modifier(AdaptiveGlassControl(shape: .capsule)) }
    }
}
private struct AdaptiveGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 8) { content() } }
        else { content() }
    }
}
struct QuietPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { TrippyHaptics.light() }
            }
    }
}

private extension TripFlowView {
    var bridgeSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Planning service") {
                    TextField("HTTPS URL", text: $bridgeHost).textInputAutocapitalization(.never)
                        .keyboardType(.URL).autocorrectionDisabled()
                    Text("Server address for planning.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Planning connection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showBridgeSettings = false } } }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    var placesSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Connect to Trippy") {
                    LabeledContent("Gateway") {
                        Text(bridgeBaseURL).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    SecureField("Trippy bridge token", text: $bridgeToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Enter the TRIPPY_BRIDGE_TOKEN from Render here, not the Google Places API key. It's stored in the Keychain; the Google key stays on Render. The check runs one Place ID lookup without loading or saving place details.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await checkPlacesConnection() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCheckingPlacesConnection { ProgressView().padding(.trailing, 5) }
                            Text(isCheckingPlacesConnection ? "Checking connection…" : "Check connection")
                            Spacer()
                        }
                    }
                    .disabled(isCheckingPlacesConnection)
                    placesConnectionFeedback
                }
                Section {
                    NavigationLink { AccountHub() } label: { Label("Account", systemImage: "person.crop.circle") }
                } footer: {
                    Text("Sign in, where you live, and the admin dashboard for admin accounts.")
                }
            }
            .navigationTitle("Google Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlacesSettings = false } } }
        }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    private var isCheckingPlacesConnection: Bool {
        if case .checking = placesConnectionState { return true }
        return false
    }

    @ViewBuilder
    private var placesConnectionFeedback: some View {
        switch placesConnectionState {
        case .idle:
            Label("The check tests app → Render → Google Places.", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(.secondary)
        case .checking:
            Label("Checking both legs of the connection…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption).foregroundStyle(.secondary)
        case .connected:
            Label("Connected: app → Render → Google Places API (New).", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "37835F"))
        case .missingToken:
            Label("TRIPPY_BRIDGE_TOKEN is missing. This field doesn't take the Google key.", systemImage: "key.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .rejectedToken:
            Label("Render rejected the token. Both sides need the same TRIPPY_BRIDGE_TOKEN.", systemImage: "lock.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .missingGoogleKey:
            Label("The app reached Render, but GOOGLE_PLACES_API_KEY is missing from Render's environment.", systemImage: "key.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .rateLimited:
            Label("The gateway hit its request limit. Wait a moment and try again.", systemImage: "hourglass")
                .font(.caption).foregroundStyle(Color(hex: "A96D45"))
        case .gatewayError(let message):
            Label("The Render gateway returned an error: \(message)", systemImage: "wifi.exclamationmark")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .googleError(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label("The app reached Render. Google Places rejected the request.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "B85C52"))
                Text(message).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func checkPlacesConnection() async {
        let token = bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            placesConnectionState = .missingToken
            return
        }
        placesConnectionState = .checking
        guard let url = URLComponents(string: bridgeBaseURL + "/api/places/status")?.url else {
            placesConnectionState = .gatewayError("The gateway address isn't valid.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                placesConnectionState = .gatewayError("The reply wasn't a valid HTTP response.")
                return
            }
            let result = try? JSONDecoder().decode(PlacesGatewayHealthResponse.self, from: data)
            if http.statusCode == 200, result?.gateway == "connected", result?.googlePlaces == "connected" {
                placesConnectionState = .connected
            } else if http.statusCode == 401 {
                placesConnectionState = .rejectedToken
            } else if result?.errorCode == "google_places_key_missing" {
                placesConnectionState = .missingGoogleKey
            } else if http.statusCode == 429 {
                placesConnectionState = .rateLimited
            } else if result?.gateway == "connected", result?.googlePlaces == "error" {
                let code = result?.errorCode ?? "UNKNOWN"
                let message = result?.message ?? "Unexpected Google Places response (\(code))."
                placesConnectionState = .googleError("\(code): \(message)")
            } else if http.statusCode == 404 {
                placesConnectionState = .gatewayError("Render doesn't have the new check endpoint yet; deploy the bridge version.")
            } else {
                let detail = result?.message ?? result?.error ?? "HTTP \(http.statusCode)"
                placesConnectionState = .gatewayError(detail)
            }
        } catch {
            placesConnectionState = .gatewayError("Couldn't reach Render. Check the address and your internet connection.")
        }
    }
}

// Plan typography scales with the user's preferred text size.
private enum PlanType {
    static let title = Font.custom("PlusJakartaSans-Bold", size: 24, relativeTo: .title2)
    static let heading = Font.custom("PlusJakartaSans-Bold", size: 17, relativeTo: .headline)
    static let body = Font.custom("PlusJakartaSans-Regular", size: 15, relativeTo: .body)
    static let detail = Font.custom("PlusJakartaSans-Medium", size: 13, relativeTo: .subheadline)
}

private struct PlanRouteMap: View {
    let points: [ResearchMapPoint]
    let legs: [TripRouteLeg]
    let fallback: CLLocationCoordinate2D?
    let missingCount: Int
    @State private var position: MapCameraPosition = .automatic
    @State private var rendered: [String: MKRoute] = [:]
    @State private var cache: [String: MKRoute] = [:]
    @State private var loading = false
    @State private var failed = 0
    private var taskKey: String {
        legs.map { "\($0.id):\($0.from.latitude),\($0.from.longitude):\($0.to.latitude),\($0.to.longitude):\($0.walking)" }.joined(separator: "|")
    }
    private var cameraKey: String {
        points.map { "\($0.id):\($0.latitude),\($0.longitude)" }.joined(separator: "|") + ":\(fallback?.latitude ?? 0):\(fallback?.longitude ?? 0)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !points.isEmpty {
                Map(position: $position, interactionModes: .all) {
                    ForEach(points) { point in Marker(point.title, coordinate: point.coordinate).tint(AppPalette.brand) }
                    ForEach(legs) { leg in
                        if let route = rendered[leg.id] { MapPolyline(route.polyline).stroke(AppPalette.brand, lineWidth: 4) }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                .frame(height: 176).clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("The day's stops and route preview")
                if loading { HStack { ProgressView(); Text("Calculating route…").font(PlanType.detail) } }
                else if !legs.isEmpty {
                    let minutes = Int(rendered.values.reduce(0) { $0 + $1.expectedTravelTime } / 60)
                    Text(rendered.isEmpty ? "Route unavailable. Open Directions on each stop." : "\(minutes) min travel · \(legs.allSatisfy(\.walking) ? "πεζή προεπισκόπηση" : "προεπισκόπηση διαδρομής")\(failed > 0 ? " · μερική διαδρομή" : "")")
                        .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                } else if points.count > 1 {
                    Text("Places are shown. For your chosen transport, see each stop's Directions.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                }
            } else {
                Label("The day's locations are missing", systemImage: "mappin.slash")
                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if missingCount > 0 && !points.isEmpty {
                Text("\(missingCount) stops have no exact location. The route is partial.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .task(id: cameraKey) { fit() }
        .task(id: taskKey) { await route() }
    }
    private func fit() {
        let coordinates = points.map(\.coordinate)
        guard let first = coordinates.first else { return }
        let minLat = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? first.latitude
        let minLon = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLon = coordinates.map(\.longitude).max() ?? first.longitude
        position = .region(.init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                 span: .init(latitudeDelta: max(0.012, (maxLat - minLat) * 1.6), longitudeDelta: max(0.012, (maxLon - minLon) * 1.6))))
    }
    private func route() async {
        rendered = [:]; failed = 0; loading = !legs.isEmpty
        let generation = taskKey
        for leg in legs {
            guard !Task.isCancelled, generation == taskKey else { return }
            let key = "\(leg.from.latitude),\(leg.from.longitude):\(leg.to.latitude),\(leg.to.longitude):\(leg.walking)"
            if let existing = cache[key] { rendered[leg.id] = existing; continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: leg.from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: leg.to))
            request.transportType = leg.walking ? .walking : .automobile
            let directions = MKDirections(request: request)
            do {
                let response = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled, generation == taskKey else { return }
                if let result = response.routes.first { rendered[leg.id] = result; cache[key] = result }
                else { failed += 1 }
            } catch {
                guard !Task.isCancelled, generation == taskKey else { return }
                failed += 1
            }
        }
        if !Task.isCancelled, generation == taskKey { loading = false }
    }
}

private struct PlanLocationPicker: View {
    let name: String
    let destination: String
    let center: CLLocationCoordinate2D?
    let onSelect: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var searching = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose the exact place and check the address.").font(PlanType.body)
                    TextField("Name and area", text: $query).textFieldStyle(.roundedBorder).font(PlanType.body)
                    if searching { ProgressView("Searching…") }
                    if let error { Text(error).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
                    ForEach(results.indices, id: \.self) { index in
                        let item = results[index]
                        Button { selected = item } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.name ?? name).font(PlanType.heading)
                                    Text(item.placemark.title ?? destination).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                Image(systemName: selected === item ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44)
                            }.contentShape(Rectangle())
                        }.buttonStyle(QuietPressStyle())
                        Divider()
                    }
                    if let selected {
                        Map(initialPosition: .region(.init(center: selected.placemark.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                            Marker(selected.name ?? name, coordinate: selected.placemark.coordinate)
                        }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12)).id(selected.placemark.coordinate.latitude.description + selected.placemark.coordinate.longitude.description)
                        Button { onSelect(selected.placemark.coordinate); dismiss() } label: {
                            Text("Use this place").font(PlanType.heading)
                                .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(AppPalette.inverseInk)
                                .background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(QuietPressStyle())
                    }
                }.padding(20)
            }.background(AppPalette.canvas).foregroundStyle(AppPalette.ink)
                .navigationTitle("Stop location").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(AppPalette.brand)
        .onAppear { query = "\(name), \(destination)" }
        .task(id: query) { await search() }
    }
    private func search() async {
        selected = nil; results = []; error = nil; searching = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 2 else { return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
            if let center { request.region = .init(center: center, span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4)) }
            let search = MKLocalSearch(request: request)
            let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
            guard !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(8))
            if results.isEmpty { error = "Place not found. Try the name and full address." }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Search isn't available. Try again."
        }
        if !Task.isCancelled { searching = false }
    }
}


// Offline preview states: these callbacks never start research or spend budget.
#Preview("Research · in progress") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 3, completedSteps: [1, 2], running: true, saved: false, partial: false,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: true,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · service update") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 1, completedSteps: [], running: false, saved: false, partial: false,
        error: "The service doesn't have the new planner yet. Nothing started and nothing was charged.",
        needsServiceUpdate: true, canRecover: false, resuming: false,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · saved with checks") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 5, completedSteps: [1, 2, 3, 4, 5], running: false, saved: true, partial: true,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: false,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · dark and large text") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 3, completedSteps: [1, 2], running: true, saved: false, partial: false,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: true,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
        .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility1)
}


// MARK: - Identity design components

struct MarkGlyphView: View {
    let appearance: MarkAppearance?
    let fallback: String
    let tint: Color
    var size: CGFloat = 20
    var body: some View {
        let color = appearance?.validColorHex.map(LibraryColors.hex) ?? tint
        Group {
            if let appearance, appearance.kind != "icon" {
                Text(appearance.glyph).font(.system(size: size, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Image(systemName: appearance?.glyph ?? fallback).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
            }
        }.accessibilityHidden(true)
    }
}
struct MarkIconWell: View {
    let appearance: MarkAppearance?
    let fallback: String
    let tone: LibraryTone
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let tint = appearance?.validColorHex.map(LibraryColors.hex) ?? tone.color(scheme)
        MarkGlyphView(appearance: appearance, fallback: fallback, tint: tint, size: size * 0.43)
            .frame(width: size, height: size)
            .background(tint.opacity(scheme == .dark ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: size * 0.3))
            .librarySurface(radius: size * 0.3)
    }
}

struct MarkGlyphGrid: View {
    let page: String
    let choices: [MarkGlyphChoice]
    @Binding var appearance: MarkAppearance
    let defaultSymbol: String
    let accent: Color
    var body: some View {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 12)], spacing: 14) {
                            ForEach(choices) { choice in
                                let selected = appearance.glyph == choice.glyph && appearance.kind == MarkGlyphCatalog.kind(page)
                                Button {
                                    appearance.glyph = choice.glyph; appearance.kind = MarkGlyphCatalog.kind(page)
                                } label: {
                                    MarkGlyphView(appearance: MarkAppearance(glyph: choice.glyph, kind: MarkGlyphCatalog.kind(page), colorHex: appearance.colorHex),
                                                  fallback: defaultSymbol, tint: accent, size: 25)
                                        .frame(maxWidth: .infinity).frame(height: 58)
                                        .background(selected ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 18))
                                        .librarySurface(radius: 18)
                                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? accent : .clear, lineWidth: 2))
                                }.buttonStyle(QuietPressStyle()).accessibilityLabel(choice.title).accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
    }
}

struct StoredLocationMarker: View {
    let title: String
    let appearance: MarkAppearance?
    let pinned: Bool
    var compact = false
    var showsTitle = true
    var lightweight = false
    @Environment(\.colorScheme) private var scheme
    private var tint: Color { appearance?.validColorHex.map(LibraryColors.hex) ?? (pinned ? LibraryTone.pins.color(scheme) : LibraryTone.notes.color(scheme)) }
    var body: some View {
        let diameter: CGFloat = showsTitle ? (compact ? 20 : pinned ? 28 : 24) : 14
        MarkGlyphView(appearance: appearance, fallback: pinned ? "mappin" : "heart.fill", tint: tint,
                      size: showsTitle ? (compact ? 11 : 15) : 8)
            .frame(width: diameter, height: diameter)
            .background {
                if lightweight { Circle().fill(LibraryColors.surface(scheme)) }
                else { Circle().fill(.ultraThinMaterial) }
            }
            .background(tint.opacity(0.12), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(scheme == .dark ? 0.22 : 0.7), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
            .frame(width: 44, height: 44).contentShape(Circle())
            .overlay(alignment: .bottom) {
                if showsTitle {
                    Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 10))
                        .foregroundStyle(LibraryColors.ink(scheme)).lineLimit(1)
                        .frame(maxWidth: 112).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background {
                            if lightweight { Capsule().fill(LibraryColors.surface(scheme)) }
                            else { Capsule().fill(.thinMaterial) }
                        }
                        .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.55), lineWidth: 0.6))
                        .offset(y: compact ? 8 : 12).allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Identity editor

private struct MarkIdentityEditor: View {
    let title: String
    let defaultSymbol: String
    let tone: LibraryTone
    let allowsCategory: Bool
    let allowsEmptyName: Bool
    let onSave: (String, MarkAppearance?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name: String
    @State private var appearance: MarkAppearance
    @State private var category: String
    @State private var page: String
    @State private var query = ""
    init(title: String, name: String, appearance: MarkAppearance?, defaultSymbol: String, tone: LibraryTone,
         category: String? = nil, allowsCategory: Bool = false, allowsEmptyName: Bool = false,
         onSave: @escaping (String, MarkAppearance?, String?) -> Void) {
        self.title = title; self.defaultSymbol = defaultSymbol; self.tone = tone
        self.allowsCategory = allowsCategory; self.allowsEmptyName = allowsEmptyName; self.onSave = onSave
        _name = State(initialValue: name)
        _appearance = State(initialValue: appearance ?? MarkAppearance(glyph: defaultSymbol))
        _category = State(initialValue: category ?? "")
        _page = State(initialValue: appearance?.kind == "emoji" ? "Emoji" : appearance?.kind == "flag" ? "Flags" : appearance?.kind == "symbol" ? "Symbols" : "Icons")
    }
    private var ink: Color { LibraryColors.ink(scheme) }
    private var accent: Color { tone.color(scheme) }
    private var chosenColor: Binding<Color> {
        Binding(get: { appearance.validColorHex.map(LibraryColors.hex) ?? accent }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            appearance.colorHex = String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        })
    }
    private var choices: [MarkGlyphChoice] {
        MarkGlyphCatalog.choices(page).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.glyph.contains(query) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        MarkIconWell(appearance: appearance, fallback: defaultSymbol, tone: tone, size: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name.isEmpty ? title : name).font(.custom("PlusJakartaSans-Bold", size: 22)).foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 14) {
                        TextField(tone == .trips ? "Trip name" : "Pin name", text: $name)
                            .font(.custom("PlusJakartaSans-SemiBold", size: 16)).padding(16).librarySurface(radius: 18, inset: true)
                        if allowsCategory {
                            TextField("Custom category · optional", text: $category)
                                .font(.body).padding(16).librarySurface(radius: 18, inset: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Color").font(.headline)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { colorSwatches }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) { colorSwatches }
                        }
                        HStack {
                            Button("Automatic") { appearance.colorHex = nil }.font(.subheadline.weight(.semibold))
                            Spacer()
                            ColorPicker("Custom color", selection: chosenColor, supportsOpacity: false).font(.subheadline)
                        }.frame(minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Icon").font(.headline)
                        Picker("Icon selection", selection: $page) {
                            ForEach(MarkGlyphCatalog.pages, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented).onChange(of: page) { _, _ in query = "" }
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(accent)
                            TextField(page == "Flags" ? "Search countries" : "Search icons", text: $query)
                                .autocorrectionDisabled()
                        }.padding(14).librarySurface(radius: 18, inset: true)
                        MarkGlyphGrid(page: page, choices: choices, appearance: $appearance, defaultSymbol: defaultSymbol, accent: accent)
                        if choices.isEmpty { Text("No matches.").font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme)) }
                        Button("Reset icon") { appearance = MarkAppearance(glyph: defaultSymbol) }
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }
                }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .background { LibraryAtmosphere(tone: tone).ignoresSafeArea() }.foregroundStyle(ink)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let defaultAppearance = MarkAppearance(glyph: defaultSymbol)
                            let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), appearance == defaultAppearance ? nil : appearance, category.isEmpty ? nil : category)
                            dismiss()
                        }.fontWeight(.semibold).disabled(!allowsEmptyName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.tint(accent).presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    @ViewBuilder private var colorSwatches: some View {
        ForEach(MarkGlyphCatalog.colors, id: \.self) { hex in
            Button { appearance.colorHex = hex } label: {
                Circle().fill(LibraryColors.hex(hex)).frame(width: 30, height: 30)
                    .overlay { if appearance.validColorHex == hex { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 1) } }
                    .frame(width: 38, height: 44).contentShape(Rectangle())
            }.buttonStyle(QuietPressStyle()).accessibilityLabel("Color #\(hex)").accessibilityAddTraits(appearance.validColorHex == hex ? .isSelected : [])
        }
    }
}

// MARK: - Planning design components

struct PlanningColors {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    private func color(_ light: String, _ dark: String) -> Color {
        let value = UInt64(self.dark ? dark : light, radix: 16) ?? 0
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var canvas: Color { color("F6F2EC", "14171C") }
    var surface: Color { color("F9F6F1", "20252C") }
    var raised: Color { color("FFFCF8", "2B323B") }
    var ink: Color { color("263C33", "F1F4F7") }
    var secondaryInk: Color { color("627269", "B5BEC9") }
    var brand: Color { color("28533F", "B8D9C7") }
    var accent: Color { color("A64E35", "EFA58E") }
    var inverseInk: Color { color("FFFFFF", "162B23") }
    var border: Color { color("DEDAD1", "424B57") }
    var selectedFill: Color { color("E3EDE4", "2A4037") }
    func progress(_ step: Int) -> Color {
        switch step {
        case 0: color("C56B32", "EDA16A")
        case 1: color("D89C72", "F0BC96")
        case 2: color("BEA044", "E5CE80")
        default: color("4A8B64", "A4D5AE")
        }
    }
}

private struct PlanningSurface: ViewModifier {
    let radius: CGFloat
    let raised: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let colors = PlanningColors(scheme: scheme)
        content.background(raised ? colors.raised : colors.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.12 : 0.9), colors.border.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.25 : 0.07), radius: raised ? 5 : 12, x: 2, y: raised ? 3 : 6)
    }
}

extension View {
    func planningSurface(radius: CGFloat, raised: Bool = false) -> some View {
        modifier(PlanningSurface(radius: radius, raised: raised))
    }
}

struct PlanningChoicePill: View {
    let title: String
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let colors = PlanningColors(scheme: scheme)
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").frame(width: 12)
                Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }.hidden()
            Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 12))
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                .offset(x: selected ? 8 : 0)
        }
        .overlay(alignment: .leading) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).frame(width: 12)
                .opacity(selected ? 1 : 0)
        }
        .foregroundStyle(selected ? colors.brand : colors.ink)
        .padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
        .background(selected ? colors.selectedFill : colors.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [selected ? colors.brand.opacity(0.6) : Color.white.opacity(scheme == .dark ? 0.16 : 0.95),
                                    colors.border.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.08), radius: 4, x: 2, y: 3)
        .contentShape(Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: selected)
    }
}

struct PlanningDestinationCard: View {
    let destination: String
    let dates: String
    let travelers: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let colors = PlanningColors(scheme: scheme)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 21, weight: .semibold))
                .foregroundStyle(colors.brand).frame(width: 48, height: 48).planningSurface(radius: 16, raised: true)
            VStack(alignment: .leading, spacing: 7) {
                Text(destination.isEmpty ? "Destination to decide" : destination)
                    .font(.custom("PlusJakartaSans-Bold", size: 19)).foregroundStyle(colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dates).font(.subheadline).foregroundStyle(colors.secondaryInk)
                Label(travelers.formatted(), systemImage: "person.2")
                    .font(.custom("PlusJakartaSans-Bold", size: 16)).foregroundStyle(colors.secondaryInk)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).planningSurface(radius: 20, raised: true)
    }
}

// MARK: - Library design components

struct LibraryDeleteButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var confirming = false
    var body: some View {
        Button(role: .destructive) { confirming = true } label: {
            Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryTone.pins.color(scheme)).frame(width: 44, height: 44).librarySurface(radius: 22)
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Delete \(title)")
            .confirmationDialog("Delete «\(title)»;", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: action)
                Button("Cancel", role: .cancel) { }
            }
    }
}

struct LibrarySourceFilterPill: View {
    let status: LibrarySourceStatus
    let count: Int
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: status.symbol).font(.system(size: 12, weight: .semibold))
            Text(status.title).font(.custom("PlusJakartaSans-SemiBold", size: 12))
            Text(count.formatted()).font(.custom("PlusJakartaSans-Bold", size: 11)).monospacedDigit().opacity(0.8)
        }.foregroundStyle(selected ? LibraryTone.videos.color(scheme) : LibraryColors.ink(scheme))
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(selected ? LibraryTone.videos.color(scheme).opacity(0.1) : .clear, in: Capsule())
            .librarySurface(radius: 22)
            .overlay(Capsule().strokeBorder(selected ? LibraryTone.videos.color(scheme).opacity(0.6) : .clear, lineWidth: 1))
    }
}

struct LibraryTripFacts: View {
    let dates: String
    let travelers: Int
    var accent: Color? = nil
    @Environment(\.colorScheme) private var scheme
    private var tripAccent: Color { accent ?? LibraryTone.trips.color(scheme) }
    private var year: String? {
        guard let last = dates.split(separator: " ").last, last.count == 4, Int(last) != nil else { return nil }
        return String(last)
    }
    private var dateText: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 15, weight: .semibold)).foregroundStyle(tripAccent)
            Text(year == nil ? dates : String(dates.dropLast(5)))
                .font(.custom("PlusJakartaSans-Bold", size: 17, relativeTo: .headline)).monospacedDigit()
                .foregroundStyle(LibraryColors.ink(scheme)).fixedSize(horizontal: false, vertical: true)
            if let year {
                Text(year).font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline)).monospacedDigit()
                    .foregroundStyle(tripAccent).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(tripAccent.opacity(scheme == .dark ? 0.1 : 0.07), in: Capsule())
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(dates)
    }
    private var people: some View {
        HStack(spacing: 7) {
            Image(systemName: "person.2").font(.system(size: 15, weight: .semibold))
            Text(travelers.formatted()).font(.custom("PlusJakartaSans-Bold", size: 17, relativeTo: .headline)).monospacedDigit()
        }.foregroundStyle(tripAccent)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(travelers) people")
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { dateText.padding(10).librarySurface(radius: 16, inset: true); people.padding(12).librarySurface(radius: 16, inset: true) }
            VStack(alignment: .leading, spacing: 10) { dateText.padding(10).librarySurface(radius: 16, inset: true); people.padding(12).librarySurface(radius: 16, inset: true) }
        }
    }
}
struct LibraryCityHeading: View {
    let city: String
    let countryCode: String?
    var count: Int? = nil
    let tone: LibraryTone
    var detail: String? = nil
    var onClear: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    private var country: String? { countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } }
    private var flag: String {
        guard let countryCode else { return "🌍" }
        let letters = countryCode.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ (65...90).contains($0.value) }) else { return "🌍" }
        return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(flag).font(.system(size: 31)).frame(width: 62, height: 62).librarySurface(radius: 22)
            VStack(alignment: .leading, spacing: 8) {
                Text(city).font(.custom("PlusJakartaSans-ExtraBold", size: 25, relativeTo: .title2)).tracking(-0.6)
                    .foregroundStyle(LibraryColors.ink(scheme)).fixedSize(horizontal: false, vertical: true)
                if let country { Text(country).font(.custom("PlusJakartaSans-SemiBold", size: 13, relativeTo: .subheadline)).foregroundStyle(LibraryColors.secondary(scheme)) }
                HStack(spacing: 7) {
                    Text(detail ?? tone.rawValue.capitalized)
                    if let count { Text("·"); Text(count.formatted()).fontWeight(.bold).monospacedDigit() }
                }.font(.caption.weight(.medium)).foregroundStyle(tone.color(scheme))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LibraryColors.secondary(scheme)).frame(width: 44, height: 44).librarySurface(radius: 22)
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Clear city filter")
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).librarySurface(radius: 26)
    }
}

// Library-only roles keep category colors, elevation and type consistent.
enum LibraryTone: String, CaseIterable {
    case trips, pins, videos, notes
    var symbol: String {
        switch self {
        case .trips: "suitcase.rolling.fill"
        case .pins: "mappin.and.ellipse"
        case .videos: "play.rectangle.fill"
        case .notes: "note.text"
        }
    }
    func color(_ scheme: ColorScheme) -> Color {
        let hex: String
        switch (self, scheme) {
        case (.trips, .dark): hex = "A4CEB9"
        case (.pins, .dark): hex = "EFAB94"
        case (.videos, .dark): hex = "C5B2E2"
        case (.notes, .dark): hex = "E3C48B"
        case (.trips, _): hex = "38634F"
        case (.pins, _): hex = "99523F"
        case (.videos, _): hex = "70588F"
        case (.notes, _): hex = "7B5A29"
        }
        return LibraryColors.hex(hex)
    }
}
enum LibraryColors {
    static func hex(_ value: String) -> Color {
        let number = UInt64(value, radix: 16) ?? 0
        return Color(.sRGB, red: Double((number >> 16) & 255) / 255,
                     green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, opacity: 1)
    }
    static func canvas(_ scheme: ColorScheme) -> Color { hex(scheme == .dark ? "191F1D" : "EFF2ED") }
    static func surface(_ scheme: ColorScheme) -> Color { hex(scheme == .dark ? "252D29" : "F7F9F4") }
    static func ink(_ scheme: ColorScheme) -> Color { hex(scheme == .dark ? "EAF0E8" : "20352A") }
    static func secondary(_ scheme: ColorScheme) -> Color { hex(scheme == .dark ? "DCE6DC" : "2E4035") }
}
// Pigment over paper/ink, with deliberately visible ordered dither and grain.
struct LibraryAtmosphere: View {
    let tone: LibraryTone
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            let dark = scheme == .dark
            let base: Color = dark ? .black : .white
            let pigment = tone.color(scheme)
            ZStack {
                base
                LinearGradient(stops: [
                    .init(color: base, location: 0),
                    .init(color: pigment.opacity(dark ? 0.08 : 0.07), location: 0.24),
                    .init(color: pigment.opacity(dark ? 0.25 : 0.22), location: 0.55),
                    .init(color: pigment.opacity(dark ? 0.30 : 0.32), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [pigment.opacity(dark ? 0.14 : 0.20), .clear],
                               center: UnitPoint(x: 1.06, y: 0.57), startRadius: 0,
                               endRadius: max(geometry.size.width, geometry.size.height) * 0.7)
                Image(decorative: LibraryGrain.texture, scale: 1)
                    .resizable(resizingMode: .tile).interpolation(.none)
                    .blendMode(.softLight).opacity(dark ? 0.29 : 0.24)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private enum LibraryGrain {
    static let texture: CGImage = {
        let side = 128
        let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        var bytes = [UInt8](repeating: 0, count: side * side)
        var seed: UInt32 = 0x54524950
        for y in 0..<side {
            for x in 0..<side {
                seed = seed &* 1664525 &+ 1013904223
                let noise = Int((seed >> 24) & 63) - 31
                let dither = (bayer[(y % 4) * 4 + x % 4] - 8) * 11
                bytes[y * side + x] = UInt8(clamping: 128 + noise + dither)
            }
        }
        let data = Data(bytes) as CFData
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }()
}
struct LibraryCityGroup<Item>: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}
enum LibraryGrouping {
    static func cityTitle(_ city: String) -> String {
        city.split(separator: ",", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyLibrary ?? "Unassigned"
    }
    static func cities<Item>(_ items: [Item], city: (Item) -> String) -> [LibraryCityGroup<Item>] {
        let buckets = Dictionary(grouping: items) { item in
            cityTitle(city(item)).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        return buckets.keys.sorted().map { key in
            LibraryCityGroup(id: key, title: cityTitle(city(buckets[key]![0])), items: buckets[key]!)
        }
    }
}
private extension String {
    var nonEmptyLibrary: String? { isEmpty ? nil : self }
}
struct LibraryRaisedSurface: ViewModifier {
    var radius: CGFloat = 24
    var inset = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: [LibraryColors.surface(scheme), LibraryColors.canvas(scheme)],
                                          startPoint: inset ? .bottomTrailing : .topLeading,
                                          endPoint: inset ? .topLeading : .bottomTrailing))
            }
            .overlay(shape.strokeBorder(.white.opacity(dark ? 0.07 : 0.72), lineWidth: 1))
            .shadow(color: .white.opacity(dark ? 0.035 : 0.85), radius: inset ? 2 : 5, x: -3, y: -3)
            .shadow(color: .black.opacity(dark ? 0.26 : 0.08), radius: inset ? 2 : 6, x: 3, y: 4)
    }
}
extension View {
    func librarySurface(radius: CGFloat = 24, inset: Bool = false) -> some View {
        modifier(LibraryRaisedSurface(radius: radius, inset: inset))
    }
}
struct LibraryIconWell: View {
    let symbol: String
    let tone: LibraryTone
    var size: CGFloat = 48
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(tone.color(scheme))
            .frame(width: size, height: size)
            .background(tone.color(scheme).opacity(scheme == .dark ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: size * 0.32))
            .librarySurface(radius: size * 0.32, inset: true)
            .accessibilityHidden(true)
    }
}
struct LibraryBadge: View {
    let title: String
    var symbol: String? = nil
    var tone: LibraryTone = .trips
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(title).lineLimit(1)
        }.font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(tone.color(scheme)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(tone.color(scheme).opacity(scheme == .dark ? 0.10 : 0.07), in: Capsule())
            .background(LibraryColors.surface(scheme), in: Capsule())
    }
}
struct LibrarySectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var count: Int? = nil
    var tone: LibraryTone = .trips
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Sketch.display(.title3)).foregroundStyle(LibraryColors.ink(scheme))
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme)) }
            }
            Spacer(minLength: 0)
            if let count { Text(count.formatted()).font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(LibraryColors.secondary(scheme)).accessibilityLabel("\(count) items") }
        }.padding(.top, 8).accessibilityElement(children: .combine)
    }
}
struct LibraryEmptyState: View {
    let title: String
    let message: String
    let tone: LibraryTone
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 18) {
            LibraryIconWell(symbol: tone.symbol, tone: tone, size: 64)
            VStack(spacing: 8) {
                Text(title).font(Sketch.display(.title3)).foregroundStyle(LibraryColors.ink(scheme))
                if !message.isEmpty {
                    Text(message).font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus").font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.color(scheme)).padding(.horizontal, 22).frame(minHeight: 48)
                        .librarySurface(radius: 24)
                }.buttonStyle(QuietPressStyle())
            }
        }.padding(28).frame(maxWidth: .infinity).librarySurface(radius: 28)
    }
}
struct LibraryCompactRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tone: LibraryTone
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            LibraryIconWell(symbol: symbol, tone: tone)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(LibraryColors.ink(scheme)).lineLimit(2)
                Text(subtitle).font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme)).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(tone.color(scheme))
        }.padding(18).frame(maxWidth: .infinity, minHeight: 94).librarySurface()
    }
}

// Offline design samples exercise the production surfaces without loading user data.
struct LibraryDesignGallery: View {
    var tone: LibraryTone = .trips
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Library").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(LibraryColors.ink(scheme))
            Text("Your trips and ideas, in one place.").font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme))
            LibraryCityHeading(city: "Barcelona", countryCode: "ES", count: 3, tone: tone)
            LibraryTripFacts(dates: "5/12-9/12 2026", travelers: 2)
            ForEach(LibraryTone.allCases, id: \.self) { tone in
                LibrarySectionHeading(title: tone.rawValue.capitalized, count: 3, tone: tone)
                LibraryCompactRow(title: sampleTitle(tone), subtitle: sampleSubtitle(tone), symbol: tone.symbol, tone: tone)
            }
        }.padding(24).frame(width: 390).background { LibraryAtmosphere(tone: tone) }
    }
    private func sampleTitle(_ tone: LibraryTone) -> String {
        switch tone {
        case .trips: "Weekend in Barcelona"
        case .pins: "Parc de la Ciutadella"
        case .videos: "Small stops, big finds"
        case .notes: "Ideas for day one"
        }
    }
    private func sampleSubtitle(_ tone: LibraryTone) -> String {
        switch tone {
        case .trips: "City weekend"
        case .pins: "Barcelona · Personal save"
        case .videos: "Barcelona · 3 places · 1 note"
        case .notes: "2 connected sources · Updated today"
        }
    }
}
#Preview("Library · light") { LibraryDesignGallery().preferredColorScheme(.light) }
#Preview("Library · dark") { LibraryDesignGallery().preferredColorScheme(.dark) }
#Preview("Library · large text") { LibraryDesignGallery().environment(\.dynamicTypeSize, .accessibility1) }
#Preview("Library · empty") {
    LibraryEmptyState(title: "Your next trip starts here", message: "Describe a trip and keep everything for it together.", tone: .trips, actionTitle: "New trip", action: {})
        .padding(24).background(LibraryColors.canvas(.light))
}
