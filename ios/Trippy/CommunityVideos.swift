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
struct CommunityBrowse: Decodable {
    let videos: [CommunityVideoSummary]; let cities: [String]; let categories: [CommunityCategory]; var areas: [String]? = nil
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
    static func tint(_ category: String) -> Color {
        switch category {
        case "food", "coffee": Sketch.coral
        case "bars", "clubs", "events": Sketch.plum
        case "outdoors", "day_trips": Sketch.sage
        case "transport", "tickets", "budget_practical": Sketch.ochre
        default: Sketch.ink
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
            Image(systemName: platform == "youtube" ? "play.rectangle.fill" : "music.note").font(.system(size: 10, weight: .black))
            Text(platform == "youtube" ? "YouTube" : "TikTok").font(Sketch.text(10, "Bold", relativeTo: .caption2))
        }
        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
        .background(platform == "youtube" ? CommunityStyle.youtubeRed : CommunityStyle.tiktokBlack, in: Capsule())
    }
    /// YouTube links open at the moment; TikTok has no timestamp links.
    static func link(_ url: String, seconds: Double?) -> URL? {
        guard var components = URLComponents(string: url) else { return nil }
        if let seconds, components.host?.contains("youtube") == true {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(Int(seconds))s")]
        }
        return components.url
    }
    static func year(_ iso: String?) -> String? { iso.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
}

private struct Chip: View {
    let title: String
    var symbol: String? = nil
    let on: Bool
    var tint: Color = Sketch.ink
    let action: () -> Void
    var body: some View {
        Button(action: { TrippyHaptics.selection(); action() }) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(Sketch.text(13, on ? "Bold" : "SemiBold", relativeTo: .footnote))
            }
            .foregroundStyle(on ? Color.white : Sketch.ink)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background(Capsule().fill(on ? tint : Sketch.paperDeep))
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
struct CommunityBrowseContent: View {
    let baseURL: String
    let token: String
    var initialCity: String? = nil
    /// The Library's own search field: titles, creators, places, neighbourhoods and tips.
    var query: String = ""
    var preview: CommunityBrowse? = nil
    let onOpen: (String) -> Void
    @State private var data: CommunityBrowse?
    @State private var filters = CommunityFilters()
    @State private var showMap = false
    @State private var showGuides: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TrippyGuidesDemo") { return true }
        #endif
        return false
    }()
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Chip(title: "Videos", symbol: "list.bullet", on: !showMap && !showGuides) { showMap = false; showGuides = false }
                Chip(title: "Guides", symbol: "book.pages", on: showGuides) { showGuides = true; showMap = false }
                Chip(title: "Map", symbol: "map", on: showMap) { showMap = true; showGuides = false }
                Spacer(minLength: 0)
                if !showGuides { sortMenu }
            }
            if showGuides {
                GuidesBrowseView(baseURL: baseURL, token: token, query: query)
            } else {
            filterChips
            if showMap {
                CommunityMapSection(baseURL: baseURL, token: token, filters: filters, onOpen: onOpen) { box in
                    filters.bbox = box; showMap = false
                }
            } else {
                if filters.bbox != nil {
                    Chip(title: "In the map area · clear", symbol: "xmark", on: true) { filters.bbox = nil }
                }
                list
            }
            }
        }
        .task(id: "\(filters.hashValue)|\(query)") { await load() }
        .onAppear {
            if filters.city == nil { filters.city = initialCity }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TrippyCommunityShowMap") { showMap = true }
            #endif
        }
    }

    @ViewBuilder private var list: some View {
        if let data {
            Text("\(data.videos.count) video\(data.videos.count == 1 ? "" : "s") · read once, shared with everyone. Nothing is pinned until you save it.")
                .font(Sketch.text(12, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            if data.videos.isEmpty {
                ContentUnavailableView("No videos match", systemImage: "play.slash", description: Text("Try another city, area or filter."))
            }
            ForEach(data.videos) { video in
                Button { onOpen(video.key) } label: { CommunityVideoCard(video: video) }.buttonStyle(BubblePressStyle())
            }
        } else if failed {
            ContentUnavailableView("Couldn’t load community videos", systemImage: "wifi.exclamationmark",
                                   description: Text("Check your connection and try again."))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $filters.sort) {
                Text("Most saved").tag(String?.none)
                Text("Newest").tag(String?.some("newest"))
                Text("Most places").tag(String?.some("places"))
                Text("Most tips").tag(String?.some("tips"))
            }
        } label: {
            Label(["newest": "Newest", "places": "Most places", "tips": "Most tips"][filters.sort ?? ""] ?? "Most saved", systemImage: "arrow.up.arrow.down")
                .font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.ink)
                .padding(.horizontal, 10).frame(minHeight: 32).background(Sketch.paperDeep, in: Capsule())
        }
        .accessibilityLabel("Sort videos")
    }

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(title: "All", on: filters.platform == nil) { filters.platform = nil }
                    Chip(title: "TikTok", symbol: "music.note", on: filters.platform == "tiktok", tint: CommunityStyle.tiktokBlack) { filters.platform = filters.platform == "tiktok" ? nil : "tiktok" }
                    Chip(title: "YouTube", symbol: "play.rectangle.fill", on: filters.platform == "youtube", tint: CommunityStyle.youtubeRed) { filters.platform = filters.platform == "youtube" ? nil : "youtube" }
                    Chip(title: "Recommended", symbol: "hand.thumbsup.fill", on: filters.only == "recommended") { filters.only = filters.only == "recommended" ? nil : "recommended" }
                    Chip(title: "With tips", symbol: "lightbulb.fill", on: filters.only == "tips") { filters.only = filters.only == "tips" ? nil : "tips" }
                }
            }.scrollIndicators(.hidden)
            if let cities = data?.cities, !cities.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(cities, id: \.self) { name in
                            Chip(title: name, symbol: "mappin", on: filters.city == name) { filters.city = filters.city == name ? nil : name; filters.area = nil }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if let areas = data?.areas, !areas.isEmpty, filters.city != nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(areas, id: \.self) { name in
                            Chip(title: name, symbol: "square.dashed", on: filters.area == name) { filters.area = filters.area == name ? nil : name }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if let categories = data?.categories, !categories.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories) { item in
                            Chip(title: item.title, symbol: CommunityStyle.symbol(item.id), on: filters.category == item.id, tint: CommunityStyle.tint(item.id)) {
                                filters.category = filters.category == item.id ? nil : item.id
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
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

private struct CommunityVideoCard: View {
    let video: CommunityVideoSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                CommunityStyle.platformBadge(video.platform)
                Text([video.author, CommunityStyle.year(video.publishedAt), video.city].compactMap { $0 }.joined(separator: " · "))
                    .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            }
            Text(video.title).font(Sketch.text(16, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                .multilineTextAlignment(.leading).lineLimit(3)
            if let matched = video.matchedPlaces, !matched.isEmpty {
                Label("Mentions " + matched.joined(separator: ", "), systemImage: "text.magnifyingglass")
                    .font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.sage).lineLimit(1)
            }
            if !video.topPlaces.isEmpty {
                Text(video.topPlaces.joined(separator: " · ")).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink.opacity(0.8)).lineLimit(2)
            }
            HStack(spacing: 6) {
                pill("📍 \(video.counts.places)")
                if video.counts.recommended > 0 { pill("👍 \(video.counts.recommended)") }
                if video.counts.tips > 0 { pill("💡 \(video.counts.tips)") }
                if video.counts.avoid > 0 { pill("⚠️ \(video.counts.avoid)") }
                Spacer(minLength: 0)
                HStack(spacing: -4) {
                    ForEach(video.categories.prefix(4)) { item in
                        Image(systemName: CommunityStyle.symbol(item.id)).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(CommunityStyle.tint(item.id), in: Circle())
                            .overlay(Circle().strokeBorder(Sketch.card, lineWidth: 1.5))
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
    }
    private func pill(_ text: String) -> some View {
        Text(text).font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.ink)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Sketch.paperDeep, in: Capsule())
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
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
                        .font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(video.platform == "youtube" ? CommunityStyle.youtubeRed : CommunityStyle.tiktokBlack, in: Capsule())
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
