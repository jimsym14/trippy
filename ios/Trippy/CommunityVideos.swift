import SwiftUI
import MapKit

// MARK: - Models (GET /api/community/videos and /api/community/video, see trippy/social/community.py)

struct CommunityCategory: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    var count: Int? = nil
}
struct CommunityCounts: Decodable, Hashable { let places: Int; let recommended: Int; let tips: Int; let avoid: Int }
struct CommunityMoment: Decodable, Hashable { let at: String; let seconds: Double?; let text: String }
struct CommunityTakes: Decodable, Hashable {
    let voters: Int; let been: Int; let gotIn: [String: Int]; let tags: [String: Int]
    enum CodingKeys: String, CodingKey { case voters, been, tags; case gotIn = "got_in" }
}
struct CommunityPlace: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let category: String
    let stance: String
    let firstHand: Bool?
    let summary: String
    let moments: [CommunityMoment]
    let at: String?
    let seconds: Double?
    let neighborhood: String?
    let googlePlaceID: String?
    let latitude: Double?
    let longitude: Double?
    let mustTry: [String]?
    let tips: [String]?
    let goodToKnow: [String]?
    let price: String?
    let vibe: [String]?
    let takes: CommunityTakes?
    let needsCheck: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, kind, category, stance, summary, moments, at, seconds, neighborhood, latitude, longitude, tips, price, vibe, takes
        case firstHand = "first_hand", googlePlaceID = "google_place_id", mustTry = "must_try", goodToKnow = "good_to_know", needsCheck = "needs_check"
    }
}
struct CommunityTip: Decodable, Hashable { let title: String; let detail: String; let at: String?; let seconds: Double?; let category: String }

struct CommunityVideoSummary: Decodable, Identifiable, Hashable {
    let key: String
    let platform: String
    let url: String
    let title: String
    let author: String?
    let publishedAt: String?
    let city: String
    let countryCode: String?
    let summary: String?
    let kind: String
    let categories: [CommunityCategory]
    let counts: CommunityCounts
    let topPlaces: [String]
    let matchedPlaces: [String]?
    let savers: Int?
    var id: String { key }
    enum CodingKeys: String, CodingKey {
        case key, platform, url, title, author, city, summary, kind, categories, counts, savers
        case publishedAt = "published_at", countryCode = "country_code", topPlaces = "top_places", matchedPlaces = "matched_places"
    }
}
struct CommunityVideo: Decodable, Hashable {
    let key: String
    let platform: String
    let url: String
    let title: String
    let author: String?
    let publishedAt: String?
    let city: String
    let summary: String?
    let categories: [CommunityCategory]
    let counts: CommunityCounts
    let places: [CommunityPlace]
    let tips: [CommunityTip]
    let savers: Int?
    enum CodingKeys: String, CodingKey {
        case key, platform, url, title, author, city, summary, categories, counts, places, tips, savers
        case publishedAt = "published_at"
    }
}
struct CommunityVideoKey: Identifiable, Hashable { let id: String }
struct CommunityCityStat: Decodable, Identifiable, Hashable {
    let name: String; let countryCode: String?; let videos: Int?
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, videos; case countryCode = "country_code" }
}
struct CommunityBrowse: Decodable {
    let videos: [CommunityVideoSummary]; let cities: [String]; let categories: [CommunityCategory]; var areas: [String]? = nil
    var cityStats: [CommunityCityStat]? = nil
    enum CodingKeys: String, CodingKey { case videos, cities, categories, areas; case cityStats = "city_stats" }
}
/// One place on the Community map (GET /api/community/map) with the videos that mention it.
struct CommunityMapPin: Decodable, Identifiable, Hashable {
    struct Mention: Decodable, Hashable { let key: String; let platform: String; let title: String; let author: String?; let summary: String; let at: String; let stance: String }
    let id: String; let name: String; let category: String; let latitude: Double; let longitude: Double; let city: String
    let recommended: Int; let avoid: Int; let platforms: [String]; let videos: [Mention]
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
struct CommunityMap: Decodable { let places: [CommunityMapPin]; let attribution: String? }
/// Everything the Community search can narrow by.
struct CommunityFilters: Hashable {
    var city: String?; var platform: String?; var category: String?; var area: String?
    var only: String?; var sort: String?; var bbox: [Double]?
}
/// One video that mentions a shop (GET /api/community/place), with what it said about that shop.
struct CommunityPlaceVideo: Decodable, Identifiable, Hashable {
    struct Mention: Decodable, Hashable {
        let name: String; let stance: String; let summary: String?; let moments: [CommunityMoment]?; let at: String?; let seconds: Double?
        let mustTry: [String]?
        enum CodingKeys: String, CodingKey { case name, stance, summary, moments, at, seconds; case mustTry = "must_try" }
    }
    let key: String; let platform: String; let url: String; let title: String; let author: String?; let city: String; let place: Mention
    var id: String { key }
}

/// What the browser may do to *your* library. Nothing is pinned unless you choose it here (or share the post yourself).
struct CommunityActions {
    /// Keep the video, tied to its city — no pins.
    var saveVideo: (CommunityVideo) -> Void
    /// Keep the video and pin every shop it covers.
    var saveWithSpots: (CommunityVideo) -> Void
    /// Pin just this shop.
    var pinPlace: (CommunityVideo, CommunityPlace) -> Void
    var isSaved: (String) -> Bool
    var isPinned: (CommunityPlace) -> Bool
}

/// The indexed videos that can feed a plan for one city (GET /api/community/plan-sources). Reading it costs nothing.
struct CommunityPlanSources: Decodable {
    struct Video: Decodable, Identifiable, Hashable {
        let key: String; let platform: String; let title: String; let author: String?; let usable: Int; let topPlaces: [String]
        var id: String { key }
        enum CodingKeys: String, CodingKey { case key, platform, title, author, usable; case topPlaces = "top_places" }
    }
    let videos: [Video]
    let places: Int
}

enum CommunityVideosClient {
    static func planSources(city: String, baseURL: String, token: String) async throws -> CommunityPlanSources {
        var components = URLComponents(string: baseURL + "/api/community/plan-sources")
        components?.queryItems = [URLQueryItem(name: "city", value: city)]
        return try await get(components?.url, token: token)
    }
    static func browse(city: String?, platform: String?, category: String?, query: String, baseURL: String, token: String) async throws -> CommunityBrowse {
        try await browse(CommunityFilters(city: city, platform: platform, category: category), query: query, baseURL: baseURL, token: token)
    }
    static func browse(_ f: CommunityFilters, query: String, baseURL: String, token: String) async throws -> CommunityBrowse {
        var components = URLComponents(string: baseURL + "/api/community/videos")
        components?.queryItems = items(f) + [URLQueryItem(name: "q", value: query.nonEmptyCommunity)].filter { $0.value != nil }
        return try await get(components?.url, token: token)
    }
    static func map(_ f: CommunityFilters, baseURL: String, token: String) async throws -> CommunityMap {
        var components = URLComponents(string: baseURL + "/api/community/map")
        components?.queryItems = items(CommunityFilters(city: f.city, platform: f.platform, category: f.category))
        return try await get(components?.url, token: token)
    }
    private static func items(_ f: CommunityFilters) -> [URLQueryItem] {
        [("city", f.city), ("platform", f.platform), ("category", f.category), ("area", f.area), ("only", f.only), ("sort", f.sort),
         ("bbox", f.bbox.map { $0.map { String(format: "%.5f", $0) }.joined(separator: ",") })]
            .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }
    static func forPlace(googleID: String?, name: String, city: String, baseURL: String, token: String) async throws -> [CommunityPlaceVideo] {
        struct Response: Decodable { let videos: [CommunityPlaceVideo] }
        var components = URLComponents(string: baseURL + "/api/community/place")
        components?.queryItems = [("id", googleID), ("name", name.nonEmptyCommunity), ("city", city.nonEmptyCommunity)]
            .compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        let response: Response = try await get(components?.url, token: token)
        return response.videos
    }
    static func video(_ key: String, baseURL: String, token: String) async throws -> CommunityVideo {
        var components = URLComponents(string: baseURL + "/api/community/video")
        components?.queryItems = [URLQueryItem(name: "key", value: key)]
        return try await get(components?.url, token: token)
    }
    private static func get<T: Decodable>(_ url: URL?, token: String) async throws -> T {
        guard let url, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private extension String {
    var nonEmptyCommunity: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

// MARK: - Look

enum CommunityStyle {
    static let youtubeRed = Color(red: 0.89, green: 0.15, blue: 0.12)
    static let tiktokBlack = Color(white: 0.086)
    /// Platform fills that read in both modes: TikTok's black flips to cream on the dark paper.
    static func platformFill(_ platform: String) -> Color { platform == "youtube" ? youtubeRed : Sketch.ink }
    static func platformText(_ platform: String) -> Color { platform == "youtube" ? .white : Sketch.paper }
    static func platformSymbol(_ platform: String) -> String { platform == "youtube" ? "play.rectangle.fill" : "music.note" }
    static func symbol(_ category: String) -> String {
        switch category {
        case "sights": "building.columns.fill"
        case "food": "fork.knife"
        case "coffee": "cup.and.saucer.fill"
        case "bars": "wineglass.fill"
        case "clubs": "music.note.house.fill"
        case "museums": "paintpalette.fill"
        case "outdoors": "leaf.fill"
        case "shopping": "bag.fill"
        case "stay": "bed.double.fill"
        case "day_trips": "car.fill"
        case "transport": "tram.fill"
        case "tickets": "ticket.fill"
        case "budget_practical": "eurosign.circle.fill"
        case "events": "sparkles"
        case "family_accessibility": "figure.and.child.holdinghands"
        default: "mappin"
        }
    }
    /// A pigment per category. Never the ink colour: white glyphs on it vanish in dark mode.
    static func tint(_ category: String) -> Color {
        switch category {
        case "food", "coffee": Sketch.coral
        case "bars", "clubs", "events": Sketch.plum
        case "outdoors", "day_trips": Sketch.sage
        case "transport", "tickets", "budget_practical": Sketch.ochre
        case "sights", "museums": Sketch.sky
        default: Sketch.clay
        }
    }
    /// Deep, fixed poster colours (the same in both modes, so the white artwork on them always reads).
    static func poster(_ category: String) -> (Color, Color) {
        func c(_ hex: UInt32) -> Color { Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
        switch category {
        case "food", "coffee": return (c(0xD9614E), c(0x8E2F2A))
        case "bars", "clubs", "events": return (c(0x7D5FA0), c(0x3B2A5A))
        case "outdoors", "day_trips": return (c(0x5A8A70), c(0x24473A))
        case "transport", "tickets", "budget_practical": return (c(0xC79437), c(0x7A5418))
        case "sights", "museums": return (c(0x4F82AB), c(0x22405E))
        default: return (c(0xC0603F), c(0x6E2F1E))
        }
    }
    static func stance(_ stance: String) -> (String, String, Color) {
        switch stance {
        case "recommended": ("Recommended", "hand.thumbsup.fill", Sketch.sage)
        case "mixed": ("Mixed", "hand.raised.fill", Sketch.ochre)
        case "avoid": ("Skip it", "hand.thumbsdown.fill", Sketch.coral)
        default: ("Mentioned", "text.bubble", Sketch.inkSoft)
        }
    }
    static func platformBadge(_ platform: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platformSymbol(platform)).font(.system(size: 10, weight: .black))
            Text(platform == "youtube" ? "YouTube" : "TikTok").font(Sketch.text(10, "Bold", relativeTo: .caption2))
        }
        .foregroundStyle(platformText(platform)).padding(.horizontal, 8).padding(.vertical, 4)
        .background(platformFill(platform), in: Capsule())
    }
    /// YouTube links open at the moment; TikTok has no timestamp links.
    static func link(_ url: String, seconds: Double?) -> URL? {
        guard var components = URLComponents(string: url) else { return nil }
        if let seconds, components.host?.contains("youtube") == true {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(Int(seconds))s")]
        }
        return components.url
    }
    /// YouTube's public still for a video key ("youtube:<id>"). TikTok has none we may keep.
    static func thumbnail(_ key: String, large: Bool = false) -> URL? {
        guard key.hasPrefix("youtube:") else { return nil }
        let id = key.dropFirst("youtube:".count)
        return URL(string: "https://i.ytimg.com/vi/\(id)/\(large ? "hqdefault" : "mqdefault").jpg")
    }
    static func year(_ iso: String?) -> String? { iso.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
    static func flag(_ code: String?) -> String? {
        guard let code, code.count == 2 else { return nil }
        let scalars = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }
    static func handle(_ author: String?) -> String? {
        guard let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else { return nil }
        return author.contains(" ") ? author : "@" + author.replacingOccurrences(of: "@", with: "")
    }
}

/// A small toggle used inside a video's detail (stance filter). Selected = ink fill with paper text, so it reads in both modes.
private struct Chip: View {
    let title: String
    var symbol: String? = nil
    let on: Bool
    var tint: Color? = nil
    let action: () -> Void
    var body: some View {
        Button(action: { TrippyHaptics.selection(); action() }) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(Sketch.text(13, on ? "Bold" : "SemiBold", relativeTo: .footnote))
            }
            // Tinted chips stay tinted text on a wash: white on the lighter dark-mode pigments wouldn't read.
            .foregroundStyle(on ? (tint ?? Sketch.paper) : Sketch.ink)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background(Capsule().fill(on ? (tint.map { $0.opacity(0.18) } ?? Sketch.ink) : Sketch.paperDeep))
            .overlay(Capsule().strokeBorder(on ? (tint ?? .clear).opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(BubblePressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: on)
    }
}

private struct Stat: View {
    let value: Int; let label: String; let tint: Color
    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)").font(Sketch.text(18, "ExtraBold", relativeTo: .headline)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(Sketch.text(10, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
        }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Sketch.paperDeep.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Browse

/// Every video anyone has indexed: TikTok shares (read once for everyone) and YouTube creator videos.
/// Lives inside the Library as its Community tab; opening a video is the host's job (`onOpen`).
///
/// Layout, top to bottom: a segmented Videos · Guides · Map switch; a rail of city cards; one row of
/// dropdown filters (source, category, area, show); the result count with the sort menu; the videos.
struct CommunityBrowseContent: View {
    enum Mode: String, CaseIterable {
        case videos = "Videos", guides = "Guides", places = "Places", map = "Map"
        var symbol: String {
            switch self { case .videos: "play.rectangle"; case .guides: "book.pages"; case .places: "mappin.and.ellipse"; case .map: "map" }
        }
    }
    let baseURL: String
    let token: String
    var initialCity: String? = nil
    /// The Library's own search field: titles, creators, places, neighbourhoods and tips.
    var query: String = ""
    var preview: CommunityBrowse? = nil
    let onOpen: (String) -> Void
    @State private var data: CommunityBrowse?
    @State private var filters = CommunityFilters()
    @State private var mode: Mode = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-TrippyGuidesDemo") { return .guides }
        if args.contains("-TrippyCommunityShowMap") { return .map }
        if let i = args.firstIndex(of: "-TrippyCommunityMode"), i + 1 < args.count, let mode = Mode(rawValue: args[i + 1].capitalized) { return mode }
        #endif
        return .videos
    }()
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CommunityTabs(mode: $mode)
            switch mode {
            case .guides:
                GuidesBrowseView(baseURL: baseURL, token: token, query: query)
            case .places:
                cityRail
                filterBar
                CommunityPlacesSection(baseURL: baseURL, token: token, filters: filters, query: query, onOpen: onOpen)
            case .map:
                cityRail
                filterBar
                CommunityMapSection(baseURL: baseURL, token: token, filters: filters, onOpen: onOpen) { box in
                    filters.bbox = box; withAnimation(.snappy) { mode = .videos }
                }
            case .videos:
                cityRail
                list
            }
        }
        .task(id: "\(filters.hashValue)|\(query)") { await load() }
        .onAppear { if filters.city == nil { filters.city = initialCity } }
    }

    // MARK: Cities

    private var cityStats: [CommunityCityStat] {
        if let stats = data?.cityStats, !stats.isEmpty { return stats }
        return (data?.cities ?? []).map { CommunityCityStat(name: $0, countryCode: nil, videos: nil) }
    }

    @ViewBuilder private var cityRail: some View {
        if cityStats.count > 0 {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    CityCard(title: "Everywhere", flag: nil, count: cityStats.compactMap(\.videos).reduce(0, +), on: filters.city == nil) {
                        filters.city = nil; filters.area = nil
                    }
                    ForEach(cityStats) { city in
                        CityCard(title: city.name, flag: city.countryCode, count: city.videos, on: filters.city == city.name) {
                            filters.city = filters.city == city.name ? nil : city.name; filters.area = nil
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .animation(.snappy, value: filters.city)
        }
    }

    // MARK: Filters

    private var activeFilters: Int {
        [filters.platform, filters.category, filters.area, filters.only].compactMap { $0 }.count + (filters.bbox == nil ? 0 : 1)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if activeFilters > 0 {
                    Button {
                        TrippyHaptics.selection()
                        withAnimation(.snappy) { filters.platform = nil; filters.category = nil; filters.area = nil; filters.only = nil; filters.bbox = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.ink)
                            .frame(width: 36, height: 36).background(Sketch.card, in: Circle())
                            .overlay(Circle().strokeBorder(Sketch.rule, lineWidth: 1))
                    }
                    .buttonStyle(BubblePressStyle()).accessibilityLabel("Clear filters")
                }
                if filters.bbox != nil {
                    Button { withAnimation(.snappy) { filters.bbox = nil } } label: { FilterButton(title: "Map area", symbol: "map", value: "In map area") }
                        .buttonStyle(BubblePressStyle()).accessibilityHint("Clears the map area")
                }
                Menu {
                    Picker("Source", selection: $filters.platform) {
                        Label("All sources", systemImage: "square.stack").tag(String?.none)
                        Label("TikTok", systemImage: "music.note").tag(String?.some("tiktok"))
                        Label("YouTube", systemImage: "play.rectangle.fill").tag(String?.some("youtube"))
                    }
                } label: {
                    FilterButton(title: "Source", symbol: filters.platform.map(CommunityStyle.platformSymbol) ?? "square.stack",
                                 value: filters.platform.map { $0 == "youtube" ? "YouTube" : "TikTok" })
                }
                if let categories = data?.categories, !categories.isEmpty {
                    Menu {
                        Picker("Category", selection: $filters.category) {
                            Label("All categories", systemImage: "square.grid.2x2").tag(String?.none)
                            ForEach(categories) { item in Label(item.title, systemImage: CommunityStyle.symbol(item.id)).tag(String?.some(item.id)) }
                        }
                    } label: {
                        FilterButton(title: "Category", symbol: filters.category.map(CommunityStyle.symbol) ?? "square.grid.2x2",
                                     value: filters.category.flatMap { id in categories.first { $0.id == id }?.title })
                    }
                }
                if filters.city != nil, let areas = data?.areas, !areas.isEmpty {
                    Menu {
                        Picker("Area", selection: $filters.area) {
                            Text("Whole city").tag(String?.none)
                            ForEach(areas, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        FilterButton(title: "Area", symbol: "square.dashed", value: filters.area)
                    }
                }
                if mode == .videos { Menu {
                    Picker("Show", selection: $filters.only) {
                        Label("Everything", systemImage: "circle.grid.2x2").tag(String?.none)
                        Label("Recommended places", systemImage: "hand.thumbsup.fill").tag(String?.some("recommended"))
                        Label("Has travel tips", systemImage: "lightbulb.fill").tag(String?.some("tips"))
                    }
                } label: {
                    FilterButton(title: "Show", symbol: filters.only == "tips" ? "lightbulb.fill" : filters.only == nil ? "line.3.horizontal.decrease" : "hand.thumbsup.fill",
                                 value: ["recommended": "Recommended", "tips": "With tips"][filters.only ?? ""])
                } }
            }
            .padding(.horizontal, 20).padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        .animation(.snappy, value: activeFilters)
    }

    // MARK: Results

    @ViewBuilder private var list: some View {
        if let data {
            // One quiet line instead of a big count: what's here, and how it's sorted.
            HStack(spacing: 8) {
                Text(countLine(data.videos)).font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                    .lineLimit(1).contentTransition(.numericText())
                Spacer(minLength: 8)
                sortMenu
            }
            filterBar
            if data.videos.isEmpty {
                ContentUnavailableView("No videos match", systemImage: "play.slash", description: Text("Try another city or clear a filter."))
            }
            LazyVStack(spacing: 12) {
                ForEach(Array(data.videos.enumerated()), id: \.element.id) { index, video in
                    Button { TrippyHaptics.light(); onOpen(video.key) } label: {
                        if index == 0 && data.videos.count > 2 { CommunityFeatureCard(video: video) } else { CommunityVideoCard(video: video) }
                    }
                    .buttonStyle(BubblePressStyle())
                }
            }
            if !data.videos.isEmpty {
                Label("Each video is read once and shared with everyone. Nothing is pinned until you save it.", systemImage: "person.2")
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).padding(.top, 4)
            }
        } else if failed {
            ContentUnavailableView("Couldn’t load community videos", systemImage: "wifi.exclamationmark",
                                   description: Text("Check your connection and try again."))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func countLine(_ videos: [CommunityVideoSummary]) -> String {
        let places = videos.reduce(0) { $0 + $1.counts.places }, tips = videos.reduce(0) { $0 + $1.counts.tips }
        return ["\(videos.count) video\(videos.count == 1 ? "" : "s")", places > 0 ? "\(places) places" : nil, tips > 0 ? "\(tips) tips" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $filters.sort) {
                Label("Most saved", systemImage: "person.2").tag(String?.none)
                Label("Newest", systemImage: "clock").tag(String?.some("newest"))
                Label("Most places", systemImage: "mappin").tag(String?.some("places"))
                Label("Most tips", systemImage: "lightbulb").tag(String?.some("tips"))
            }
        } label: {
            HStack(spacing: 4) {
                Text(["newest": "Newest", "places": "Most places", "tips": "Most tips"][filters.sort ?? ""] ?? "Most saved")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Sort videos")
    }

    private func load() async {
        if let preview { data = preview; return }
        try? await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await CommunityVideosClient.browse(filters, query: query, baseURL: baseURL, token: token)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { data = result; failed = false }
        } catch is CancellationError {
        } catch { if data == nil { failed = true } }
    }
}

/// Videos · Guides · Places · Map: icon over name, the open one sits on a sliding ink tile.
private struct CommunityTabs: View {
    @Binding var mode: CommunityBrowseContent.Mode
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(CommunityBrowseContent.Mode.allCases, id: \.self) { item in
                let on = mode == item
                Button {
                    TrippyHaptics.selection()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) { mode = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold)).symbolVariant(on ? .fill : .none)
                        Text(item.rawValue).font(Sketch.text(13, on ? "ExtraBold" : "SemiBold", relativeTo: .footnote))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Sketch.paper : Sketch.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "communityTab", in: space) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Sketch.card))
        .overlay(Capsule().strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
    }
}

/// Every place the community's videos mention, as cards: most-covered first. Tap one for the videos that mention it.
struct CommunityPlacesSection: View {
    let baseURL: String
    let token: String
    let filters: CommunityFilters
    var query = ""
    let onOpen: (String) -> Void
    @State private var map: CommunityMap?
    @State private var open: String?
    @State private var failed = false
    @State private var limit = 30

    private var places: [CommunityMapPin] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (map?.places ?? [])
            .filter { wanted.isEmpty || $0.name.localizedCaseInsensitiveContains(wanted) || $0.videos.contains { $0.title.localizedCaseInsensitiveContains(wanted) } }
            .sorted { ($0.videos.count, $0.recommended, $1.name) > ($1.videos.count, $1.recommended, $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if map != nil {
                let all = places
                Text("\(all.count) place\(all.count == 1 ? "" : "s") · most-mentioned first")
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                if all.isEmpty {
                    ContentUnavailableView("No places match", systemImage: "mappin.slash", description: Text("Try another city or clear a filter."))
                }
                LazyVStack(spacing: 10) {
                    ForEach(all.prefix(limit)) { pin in placeCard(pin) }
                }
                if all.count > limit {
                    Button { withAnimation(.snappy) { limit += 30 } } label: {
                        Text("Show \(min(30, all.count - limit)) more").font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink)
                            .frame(maxWidth: .infinity, minHeight: 44).background(Sketch.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 1))
                    }.buttonStyle(BubblePressStyle())
                }
            } else if failed {
                ContentUnavailableView("Couldn’t load places", systemImage: "wifi.exclamationmark", description: Text("Check your connection and try again."))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .animation(.snappy, value: open)
        .task(id: "\(filters.city ?? "")|\(filters.platform ?? "")|\(filters.category ?? "")") { await load() }
    }

    private func placeCard(_ pin: CommunityMapPin) -> some View {
        let expanded = open == pin.id
        let colors = CommunityStyle.poster(pin.category)
        return VStack(alignment: .leading, spacing: 0) {
            Button { TrippyHaptics.selection(); open = expanded ? nil : pin.id } label: {
                HStack(spacing: 12) {
                    Image(systemName: CommunityStyle.symbol(pin.category)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.name).font(Sketch.text(15, "ExtraBold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink).lineLimit(1)
                        HStack(spacing: 12) {
                            if !pin.city.isEmpty { Text(pin.city).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1) }
                            CommunityMeta(symbol: "play.rectangle.fill", value: pin.videos.count)
                            if pin.recommended > 0 { CommunityMeta(symbol: "hand.thumbsup.fill", value: pin.recommended, tint: Sketch.sage) }
                            if pin.avoid > 0 { CommunityMeta(symbol: "hand.thumbsdown.fill", value: pin.avoid, tint: Sketch.coral) }
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.vertical, 8).padding(.horizontal, 10).padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pin.name), \(pin.videos.count) video\(pin.videos.count == 1 ? "" : "s")")
            .accessibilityHint(expanded ? "Hides its videos" : "Shows the videos that mention it")
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pin.videos, id: \.key) { mention in
                        Divider().overlay(Sketch.rule)
                        Button { onOpen(mention.key) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: CommunityStyle.platformSymbol(mention.platform)).font(.system(size: 10, weight: .black))
                                    .foregroundStyle(CommunityStyle.platformText(mention.platform)).frame(width: 22, height: 22)
                                    .background(CommunityStyle.platformFill(mention.platform), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mention.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink).lineLimit(2)
                                    if !mention.summary.isEmpty {
                                        Text(mention.summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                                    }
                                    let meta = [CommunityStyle.handle(mention.author), mention.at.isEmpty ? nil : "at " + mention.at].compactMap { $0 }
                                    if !meta.isEmpty { Text(meta.joined(separator: " · ")).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func load() async {
        do {
            let result: CommunityMap
            if let demo = CommunityDemo.map { result = demo }
            else { result = try await CommunityVideosClient.map(filters, baseURL: baseURL, token: token) }
            withAnimation(.snappy) { map = result; failed = false; limit = 30 }
        } catch is CancellationError {
        } catch { if map == nil { failed = true } }
    }
}

/// The app's map pin (round head, small tail) with the country code in it; a globe for "Everywhere".
private struct CommunityCityPin: View {
    let code: String?
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let code, code.count == 2 {
                    Text(code.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.3)
                } else {
                    Image(systemName: "globe.europe.africa.fill").font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(code == nil ? Sketch.sky : Sketch.coral))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
                .foregroundStyle(code == nil ? Sketch.sky : Sketch.coral).offset(y: -2)
        }
        .offset(y: 2)
        .accessibilityHidden(true)
    }
}

/// A selectable city: pin, name and how many videos cover it. Selected = ink card with paper text.
private struct CityCard: View {
    let title: String
    let flag: String?
    let count: Int?
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button { TrippyHaptics.selection(); action() } label: {
            // One line high: the flag (or globe) in a small disc, then name over count.
            HStack(spacing: 10) {
                CommunityCityPin(code: flag)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Sketch.text(14, "ExtraBold", relativeTo: .subheadline)).lineLimit(1)
                        .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                    if let count {
                        Text("\(count) video\(count == 1 ? "" : "s")").font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).lineLimit(1)
                            .foregroundStyle(on ? Sketch.paper.opacity(0.7) : Sketch.inkSoft)
                    }
                }
            }
            .padding(.leading, 10).padding(.trailing, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Sketch.ink : Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.clear : Sketch.rule, lineWidth: 1))
        }
        .buttonStyle(BubblePressStyle())
        .accessibilityLabel("\(title)\(count.map { ", \($0) videos" } ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The face of one dropdown filter: icon, its value (or its name when unset) and a chevron. Set = ink fill.
private struct FilterButton: View {
    let title: String
    let symbol: String
    let value: String?
    var body: some View {
        let on = value != nil
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(value ?? title).font(Sketch.text(14, on ? "Bold" : "SemiBold", relativeTo: .subheadline)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(on ? Sketch.paper : Sketch.ink)
        .padding(.horizontal, 14).frame(height: 36)
        .background(Capsule().fill(on ? Sketch.ink : Sketch.card))
        .overlay(Capsule().strokeBorder(on ? Color.clear : Sketch.rule, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(on ? "\(title): \(value ?? "")" : title)
    }
}

/// Every place the community's videos mention, on a map. Tap a pin for its videos; "Search this area" filters the list.
struct CommunityMapSection: View {
    let baseURL: String
    let token: String
    let filters: CommunityFilters
    let onOpen: (String) -> Void
    let onSearchArea: ([Double]) -> Void
    @State private var map: CommunityMap?
    @State private var selected: CommunityMapPin?
    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    ForEach(map?.places ?? []) { pin in
                        Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                            Button { selected = pin } label: {
                                Image(systemName: CommunityStyle.symbol(pin.category)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: pin.videos.count > 1 ? 30 : 24, height: pin.videos.count > 1 ? 30 : 24)
                                    .background(CommunityStyle.tint(pin.category), in: Circle())
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                    .overlay(alignment: .topTrailing) {
                                        if pin.videos.count > 1 {
                                            Text("\(pin.videos.count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Sketch.ink)
                                                .padding(3).background(Circle().fill(Sketch.card)).offset(x: 6, y: -6)
                                        }
                                    }
                            }
                            .accessibilityLabel("\(pin.name), \(pin.videos.count) video\(pin.videos.count == 1 ? "" : "s")")
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in region = context.region }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if let region {
                    Button {
                        let span = region.span, c = region.center
                        onSearchArea([c.latitude - span.latitudeDelta / 2, c.longitude - span.longitudeDelta / 2,
                                      c.latitude + span.latitudeDelta / 2, c.longitude + span.longitudeDelta / 2])
                    } label: {
                        Label("Search this area", systemImage: "magnifyingglass").font(Sketch.text(13, "Bold", relativeTo: .subheadline))
                            .foregroundStyle(Sketch.ink).padding(.horizontal, 14).frame(minHeight: 36)
                            .background(Sketch.card, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
                    .padding(.top, 10)
                }
            }
            if let attribution = map?.attribution, !attribution.isEmpty {
                Text(attribution).font(Sketch.text(10, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
            }
            if failed { Text("Couldn’t load the map. Check your connection.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.coral) }
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selected.name).font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                        Spacer()
                        Button { self.selected = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Sketch.inkFaint) }
                            .accessibilityLabel("Close")
                    }
                    ForEach(selected.videos, id: \.key) { mention in
                        Button { onOpen(mention.key) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                CommunityStyle.platformBadge(mention.platform)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mention.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink).lineLimit(2)
                                    if !mention.summary.isEmpty {
                                        Text(mention.summary).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                                    }
                                    Text([mention.author, mention.at.isEmpty ? nil : "at " + mention.at].compactMap { $0 }.joined(separator: " · "))
                                        .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                            }
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected)
        .task(id: "\(filters.city ?? "")|\(filters.platform ?? "")|\(filters.category ?? "")") { await load() }
    }

    private func load() async {
        do {
            let result: CommunityMap
            if let demo = CommunityDemo.map { result = demo }
            else { result = try await CommunityVideosClient.map(filters, baseURL: baseURL, token: token) }
            map = result; failed = false
            if let first = result.places.first {
                let lats = result.places.map(\.latitude), lngs = result.places.map(\.longitude)
                let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
                let span = MKCoordinateSpan(latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.3), longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.3))
                position = result.places.count == 1 ? .region(.init(center: first.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
                                                     : .region(.init(center: center, span: span))
            }
        } catch is CancellationError {
        } catch { failed = true }
    }
}

/// The poster beside each video: YouTube's still when there is one, otherwise artwork from the video's main
/// category (TikTok covers are not kept). Platform mark in the corner, place count along the bottom.
private struct CommunityPoster: View {
    let video: CommunityVideoSummary
    var large = false
    var body: some View {
        let category = video.categories.first?.id ?? "other"
        let colors = CommunityStyle.poster(category)
        ZStack {
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: CommunityStyle.symbol(category))
                .font(.system(size: large ? 120 : 64, weight: .bold)).foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12)).offset(x: large ? 90 : 18, y: large ? 10 : 14)
            if let url = CommunityStyle.thumbnail(video.key, large: large) {
                // Sized by the frame, never by the image: a filled still would otherwise grow the card.
                Color.clear.overlay {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                    }
                }
                .clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(large ? 0.7 : 0.45)], startPoint: .center, endPoint: .bottom)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: CommunityStyle.platformSymbol(video.platform)).font(.system(size: 10, weight: .black))
                .foregroundStyle(.white).frame(width: 22, height: 22)
                .background(video.platform == "youtube" ? CommunityStyle.youtubeRed : Color.black.opacity(0.55), in: Circle())
                .padding(8)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Icon + number, the quiet way to show what a video holds.
private struct CommunityMeta: View {
    let symbol: String
    let value: Int
    var tint: Color = Sketch.inkSoft
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text("\(value)").font(Sketch.text(12, "Bold", relativeTo: .caption)).monospacedDigit()
        }.foregroundStyle(tint)
    }
}

private func communityByline(_ video: CommunityVideoSummary) -> String {
    [CommunityStyle.handle(video.author), video.city.isEmpty ? nil : video.city].compactMap { $0 }.joined(separator: " · ")
}

private func communityMetaRow(_ video: CommunityVideoSummary) -> some View {
    HStack(spacing: 12) {
        if video.counts.places > 0 { CommunityMeta(symbol: "mappin.and.ellipse", value: video.counts.places) }
        if video.counts.recommended > 0 { CommunityMeta(symbol: "hand.thumbsup.fill", value: video.counts.recommended, tint: Sketch.sage) }
        if video.counts.tips > 0 { CommunityMeta(symbol: "lightbulb.fill", value: video.counts.tips, tint: Sketch.ochre) }
        if let savers = video.savers, savers > 1 { CommunityMeta(symbol: "person.2.fill", value: savers) }
        Spacer(minLength: 0)
        HStack(spacing: 4) {
            ForEach(video.categories.prefix(3)) { item in
                Circle().fill(CommunityStyle.tint(item.id)).frame(width: 7, height: 7)
            }
        }
    }
}

/// One video in the list: poster on the left; creator, title, what it covers and a quiet meta row on the right.
private struct CommunityVideoCard: View {
    let video: CommunityVideoSummary
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CommunityPoster(video: video)
                .frame(width: 88, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(communityByline(video)).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                Text(video.title).font(Sketch.text(16, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                    .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let matched = video.matchedPlaces, !matched.isEmpty {
                    Label(matched.joined(separator: ", "), systemImage: "text.magnifyingglass")
                        .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.sage).lineLimit(1)
                } else if !video.topPlaces.isEmpty {
                    Text(video.topPlaces.prefix(3).joined(separator: " · ")).font(Sketch.text(13, relativeTo: .footnote))
                        .foregroundStyle(Sketch.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 4)
                communityMetaRow(video)
            }
            .frame(minHeight: 116, alignment: .topLeading)
        }
        .padding(10).padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The top video, larger: a wide poster with the title over it, then what it covers.
private struct CommunityFeatureCard: View {
    let video: CommunityVideoSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommunityPoster(video: video, large: true)
                .frame(height: 188)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FEATURED").font(Sketch.text(10, "ExtraBold", relativeTo: .caption2)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
                        Text(video.title).font(Sketch.text(19, "ExtraBold", relativeTo: .title3)).foregroundStyle(.white)
                            .multilineTextAlignment(.leading).lineLimit(2).shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    }
                    .padding(16)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(communityByline(video)).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                if !video.topPlaces.isEmpty {
                    Text(video.topPlaces.prefix(4).joined(separator: " · ")).font(Sketch.text(14, relativeTo: .subheadline))
                        .foregroundStyle(Sketch.ink.opacity(0.85)).lineLimit(2).multilineTextAlignment(.leading)
                }
                communityMetaRow(video)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sketch.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One video

struct CommunityVideoDetailView: View {
    let key: String
    let baseURL: String
    let token: String
    var preview: CommunityVideo? = nil
    var actions: CommunityActions? = nil
    @State private var video: CommunityVideo?
    @State private var savedNow = false
    @State private var pinnedNow: Set<String> = []
    @State private var section = "places"
    @State private var stanceFilter: String?
    @State private var expanded: Set<String> = []
    @State private var failed = false
    @State private var confirmRemove = false
    @State private var removing = false
    @ObservedObject private var account = AccountSession.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VerticalPage {
            if let video {
                VStack(alignment: .leading, spacing: 16) {
                    header(video)
                    Picker("Section", selection: $section) {
                        Text("Places \(video.places.count)").tag("places")
                        Text("Timeline").tag("timeline")
                        Text("Tips \(video.tips.count)").tag("tips")
                    }.pickerStyle(.segmented)
                    switch section {
                    case "timeline": timeline(video)
                    case "tips": tips(video)
                    default: places(video)
                    }
                    Text("Summaries are written from the video and may be out of date — check opening hours and prices before you go.")
                        .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                }
                .padding(18)
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: section)
            } else if failed {
                ContentUnavailableView("Couldn’t load this video", systemImage: "wifi.exclamationmark")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(Sketch.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Developers can take a video out of the community; the next share of it is read from the start.
            if account.isAdmin, key.hasPrefix("tiktok:") || key.hasPrefix("url:") {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Remove from Community", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    } label: {
                        if removing { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                    }
                    .accessibilityLabel("Developer actions")
                }
            }
        }
        .confirmationDialog("Remove this video from Community?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                removing = true
                Task {
                    let done = await SocialExtractionClient.forgetInCommunity(key: key, baseURL: baseURL, token: token)
                    removing = false
                    if done { TrippyHaptics.success(); dismiss() }
                }
            }
        } message: {
            Text("It disappears for everyone. If someone shares it again, it is read from the start.")
        }
        .task(id: key) {
            if let preview, preview.key == key { video = preview; return }
            do { video = try await CommunityVideosClient.video(key, baseURL: baseURL, token: token) } catch { failed = true }
        }
    }

    private func header(_ video: CommunityVideo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                CommunityStyle.platformBadge(video.platform)
                Text([video.author, CommunityStyle.year(video.publishedAt), video.city].compactMap { $0 }.joined(separator: " · "))
                    .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            }
            Text(video.title).font(Sketch.text(22, "ExtraBold", relativeTo: .title2)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
            if let summary = video.summary { Text(summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
            HStack(spacing: 8) {
                Stat(value: video.counts.places, label: "places", tint: Sketch.ink)
                Stat(value: video.counts.recommended, label: "loved", tint: Sketch.sage)
                Stat(value: video.counts.tips, label: "tips", tint: Sketch.ochre)
                Stat(value: video.counts.avoid, label: "skip", tint: Sketch.coral)
            }
            if let link = URL(string: video.url) {
                Button { openURL(link) } label: {
                    Label(video.platform == "youtube" ? "Watch on YouTube" : "Open on TikTok", systemImage: "play.fill")
                        .font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(CommunityStyle.platformText(video.platform))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(CommunityStyle.platformFill(video.platform), in: Capsule())
                }.buttonStyle(BubblePressStyle())
            }
            if let actions {
                let saved = savedNow || actions.isSaved(video.key)
                let pinnable = video.places.filter { $0.latitude != nil }
                Menu {
                    Button("Save to \(video.city.isEmpty ? "my videos" : video.city)", systemImage: "mappin.and.ellipse") {
                        actions.saveVideo(video); TrippyHaptics.success(); withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { savedNow = true }
                    }
                    if !pinnable.isEmpty {
                        Button("Save and pin all \(pinnable.count) spots", systemImage: "pin.fill") {
                            actions.saveWithSpots(video); TrippyHaptics.success()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { savedNow = true; pinnedNow.formUnion(pinnable.map(\.id)) }
                        }
                    }
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(saved ? Sketch.sage : Sketch.ink)
                        .frame(maxWidth: .infinity, minHeight: 48).background(Sketch.paperDeep, in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(pinnable.isEmpty ? "Saving keeps it with \(video.city.isEmpty ? "your videos" : video.city) — nothing is pinned."
                                      : "Save it to \(video.city.isEmpty ? "your videos" : video.city), pin every spot, or pin shops one by one below.")
                    .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
            }
            if let savers = video.savers, savers > 1 {
                Label("Saved by \(savers) people · read once", systemImage: "person.2.fill").font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                    .foregroundStyle(Sketch.inkSoft)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
    }

    @ViewBuilder private func places(_ video: CommunityVideo) -> some View {
        let shown = video.places.filter { stanceFilter == nil || $0.stance == stanceFilter }
        let groups = Dictionary(grouping: shown, by: \.category)
        let order = video.categories.map(\.id).filter { groups[$0] != nil }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(["recommended", "mixed", "avoid"], id: \.self) { stance in
                    let style = CommunityStyle.stance(stance)
                    if video.places.contains(where: { $0.stance == stance }) {
                        Chip(title: style.0, symbol: style.1, on: stanceFilter == stance, tint: style.2) { stanceFilter = stanceFilter == stance ? nil : stance }
                    }
                }
            }
            ForEach(order, id: \.self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: CommunityStyle.symbol(category)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(CommunityStyle.tint(category), in: Circle())
                        Text(video.categories.first { $0.id == category }?.title ?? category.capitalized)
                            .font(Sketch.text(15, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                        Text("\(groups[category]?.count ?? 0)").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    }
                    ForEach(groups[category] ?? []) { place in placeRow(place, video: video) }
                }
            }
        }
    }

    private func placeRow(_ place: CommunityPlace, video: CommunityVideo) -> some View {
        let style = CommunityStyle.stance(place.stance)
        let open = expanded.contains(place.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { if open { expanded.remove(place.id) } else { expanded.insert(place.id) } }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: style.1).font(.system(size: 12, weight: .bold)).foregroundStyle(style.2)
                        .frame(width: 30, height: 30).background(style.2.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(place.name).font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink).lineLimit(2)
                            if place.firstHand == true { Text("visited").font(Sketch.text(9, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.sage)
                                .padding(.horizontal, 5).padding(.vertical, 2).background(Sketch.sage.opacity(0.13), in: Capsule()) }
                        }
                        if let hood = place.neighborhood { Text(hood).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft) }
                        Text(place.summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.ink)
                            .lineLimit(open ? nil : 2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) {
                        if let at = place.at, !at.isEmpty { timeChip(at, seconds: place.seconds, url: video.url) }
                        if let actions, place.latitude != nil {
                            let pinned = pinnedNow.contains(place.id) || actions.isPinned(place)
                            Button {
                                guard !pinned else { return }
                                actions.pinPlace(video, place); TrippyHaptics.success()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { _ = pinnedNow.insert(place.id) }
                            } label: {
                                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(pinned ? Color.white : Sketch.ink).frame(width: 32, height: 32)
                                    .background(pinned ? Sketch.coral : Sketch.paperDeep, in: Circle())
                                    .contentTransition(.symbolEffect(.replace))
                            }.buttonStyle(BubblePressStyle()).accessibilityLabel(pinned ? "\(place.name) is pinned" : "Pin \(place.name)")
                        }
                    }
                }
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(place.moments.dropFirst(place.summary == place.moments.first?.text ? 1 : 0).enumerated()), id: \.offset) { _, moment in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            timeChip(moment.at, seconds: moment.seconds, url: video.url)
                            Text(moment.text).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    list("Must try", place.mustTry)
                    list("Tips", place.tips)
                    list("Good to know", place.goodToKnow)
                    if let price = place.price { Text("💶 " + price).font(Sketch.text(12, "SemiBold", relativeTo: .caption)) }
                    if let takes = place.takes { takesRow(takes) }
                }
                .padding(.leading, 40).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
    }

    private func timeChip(_ at: String, seconds: Double?, url: String) -> some View {
        Button {
            if let link = CommunityStyle.link(url, seconds: seconds) { openURL(link) }
        } label: {
            Label(at, systemImage: "play.fill").labelStyle(.titleAndIcon).font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit()
                .foregroundStyle(Sketch.plum).padding(.horizontal, 8).padding(.vertical, 4).background(Sketch.plum.opacity(0.12), in: Capsule())
        }.buttonStyle(BubblePressStyle()).accessibilityLabel("Play from \(at)")
    }

    @ViewBuilder private func list(_ title: String, _ items: [String]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                ForEach(items, id: \.self) { Text("• " + $0).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink) }
            }
        }
    }

    private func takesRow(_ takes: CommunityTakes) -> some View {
        BubbleFlow(spacing: 6) {
            Text("👥 \(takes.voters) takes").font(Sketch.text(11, "Bold", relativeTo: .caption2))
            ForEach(takes.tags.sorted { $0.value > $1.value }, id: \.key) { key, count in
                if let tag = PlaceTakeTag(rawValue: key) {
                    Text("\(tag.emoji) \(tag.title) \(count)").font(Sketch.text(11, "SemiBold", relativeTo: .caption2))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(tag.tint.opacity(0.14), in: Capsule())
                }
            }
        }
    }

    private func timeline(_ video: CommunityVideo) -> some View {
        let items: [(Double, String, String, String, String)] =
            video.places.flatMap { place in place.moments.map { ($0.seconds ?? .greatestFiniteMagnitude, $0.at, place.name, $0.text, place.category) } }
            + video.tips.map { ($0.seconds ?? .greatestFiniteMagnitude, $0.at ?? "", $0.title, $0.detail, $0.category) }
        let sorted = items.sorted { $0.0 < $1.0 }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(CommunityStyle.tint(item.4)).frame(width: 10, height: 10).padding(.top, 5)
                        if index < sorted.count - 1 { Rectangle().fill(Sketch.rule).frame(width: 2).frame(maxHeight: .infinity) }
                    }.frame(width: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if !item.1.isEmpty { timeChip(item.1, seconds: item.0 == .greatestFiniteMagnitude ? nil : item.0, url: video.url) }
                            Text(item.2).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.ink).lineLimit(1)
                        }
                        Text(item.3).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 14)
                }
            }
        }
    }

    private func tips(_ video: CommunityVideo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if video.tips.isEmpty { Text("No general tips in this video.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
            ForEach(Array(video.tips.enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: CommunityStyle.symbol(tip.category)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(CommunityStyle.tint(tip.category), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tip.title.prefix(1).uppercased() + tip.title.dropFirst()).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink)
                            Spacer()
                            if let at = tip.at, !at.isEmpty { timeChip(at, seconds: tip.seconds, url: video.url) }
                        }
                        Text(tip.detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
            }
        }
    }
}


// MARK: - On a shop's card

/// "Videos about this place": every community video that mentions the shop, with what it said and when.
struct PlaceVideosSection: View {
    let videos: [CommunityPlaceVideo]
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(videos) { video in
                    Button { if let url = URL(string: video.url) { openURL(url) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                CommunityStyle.platformBadge(video.platform)
                                let stance = CommunityStyle.stance(video.place.stance)
                                Image(systemName: stance.1).font(.system(size: 11, weight: .bold)).foregroundStyle(stance.2)
                            }
                            Text(video.title).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.ink).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let author = video.author { Text("@" + author.replacingOccurrences(of: "@", with: "")).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1) }
                            ForEach(Array((video.place.moments ?? []).prefix(2).enumerated()), id: \.offset) { _, moment in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(moment.at).font(Sketch.text(10, "Bold", relativeTo: .caption2)).monospacedDigit().foregroundStyle(Sketch.plum)
                                    Text(moment.text).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.ink).lineLimit(2).multilineTextAlignment(.leading)
                                }
                            }
                            if (video.place.moments ?? []).isEmpty, let summary = video.place.summary {
                                Text(summary).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.ink).lineLimit(3).multilineTextAlignment(.leading)
                            }
                        }
                        .padding(12).frame(width: 220, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
                    }
                    .buttonStyle(BubblePressStyle())
                    .accessibilityLabel("Open \(video.title)")
                }
            }.padding(.horizontal, 20).padding(.vertical, 4)
        }.scrollIndicators(.hidden).padding(.horizontal, -20)
    }
}


/// DEBUG screenshots: real community output exported to JSON files (simulators read host paths).
enum CommunityDemo {
    static func file(_ flag: String) -> Data? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: args[index + 1]))
        #else
        return nil
        #endif
    }
    static var browse: CommunityBrowse? { file("-TrippyCommunityBrowse").flatMap { try? JSONDecoder().decode(CommunityBrowse.self, from: $0) } }
    static var map: CommunityMap? { file("-TrippyCommunityMap").flatMap { try? JSONDecoder().decode(CommunityMap.self, from: $0) } }
    static var video: CommunityVideo? { file("-TrippyCommunityVideo").flatMap { try? JSONDecoder().decode(CommunityVideo.self, from: $0) } }
    static var placeVideos: [CommunityPlaceVideo]? {
        struct Response: Decodable { let videos: [CommunityPlaceVideo] }
        return file("-TrippyCommunityPlace").flatMap { try? JSONDecoder().decode(Response.self, from: $0).videos }
    }
    static var opensTakeFlow: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-TrippyTakeFlow")
        #else
        false
        #endif
    }
}
