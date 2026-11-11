import MapKit
import SwiftUI

// MARK: - Guides and tips (Community → Guides)
//
// Every read post is a guide, filed under the widest area it covers and every level above it (GET
// /api/community/guides; trippy/social/guides.py). Browse from Europe down to a city, filter by kind (not to
// miss, hidden spots, food, routes, tips), and open one as a story: one idea per page, tap to move on.

struct GuideCard: Decodable, Identifiable, Hashable {
    let key: String; let platform: String; let url: String; let title: String; let author: String?; let summary: String
    let types: [String]; let theme: String; let level: String; let scopeName: String; let region: String; let city: String
    let countries: [String]; let continents: [String]; let places: Int; let tips: Int; let foods: Int; let routeStops: Int; let savers: Int
    var id: String { key }
    enum CodingKeys: String, CodingKey {
        case key, platform, url, title, author, summary, types, theme, level, region, city, countries, continents, places, tips, foods, savers
        case scopeName = "scope_name", routeStops = "route_stops"
    }
    /// "Europe › Italy › Rome", widest first.
    var breadcrumb: String {
        var parts = continents.count == 1 ? continents : []
        if !region.isEmpty { parts.append(region) }
        if countries.count == 1 { parts.append(GuideKinds.country(countries[0])) }
        if !city.isEmpty { parts.append(city) }
        if ["neighbourhood", "place"].contains(level), !scopeName.isEmpty, scopeName != city { parts.append(scopeName) }
        return parts.joined(separator: " › ")
    }
}

struct GuideBrowse: Decodable {
    struct Count: Decodable, Hashable { let name: String; let count: Int }
    struct Kind: Decodable, Hashable, Identifiable { let id: String; let title: String; let count: Int }
    let guides: [GuideCard]; let count: Int; let types: [Kind]; let below: [Count]; let regions: [Count]
}

struct GuideTips: Decodable {
    struct Tip: Decodable, Hashable { let title: String; let detail: String?; let at: String? }
    struct Group: Decodable, Hashable, Identifiable { let level: String; let title: String; let tips: [Tip]; var id: String { level } }
    struct Food: Decodable, Hashable, Identifiable { let name: String; let detail: String; let `where`: [String]; let mentions: Int; var id: String { name } }
    let groups: [Group]; let foods: [Food]
}

/// The full story of one guide: what /api/community/video returns, with the guide fields.
struct GuideStory: Decodable {
    struct Food: Decodable, Hashable { let name: String; let detail: String?; let `where`: String? }
    struct Stop: Decodable, Hashable { let name: String; let city: String?; let countryCode: String?; let nights: Int?
        enum CodingKeys: String, CodingKey { case name, city, nights; case countryCode = "country_code" } }
    struct Route: Decodable, Hashable { let mode: String; let days: Int?; let costHint: String?; let stops: [Stop]
        enum CodingKeys: String, CodingKey { case mode, days, stops; case costHint = "cost_hint" } }
    let key: String; let platform: String; let url: String; let title: String; let author: String?; let summary: String?
    let places: [CommunityPlace]; let tips: [CommunityTip]
    let guideTypes: [String]?; let theme: String?; let foods: [Food]?; let route: Route?
    enum CodingKeys: String, CodingKey { case key, platform, url, title, author, summary, places, tips, theme, foods, route; case guideTypes = "guide_types" }
}

enum GuideKinds {
    static let order = ["must_see", "hidden_spots", "foods", "route", "themed_list", "city_guide", "area_guide", "venue", "tips"]
    static func title(_ id: String) -> String {
        switch id {
        case "must_see": "Not to miss"; case "hidden_spots": "Hidden spots"; case "foods": "Food to try"; case "route": "Routes"
        case "themed_list": "Lists"; case "city_guide": "City guides"; case "area_guide": "Neighbourhoods"; case "venue": "Single places"
        default: "Tips"
        }
    }
    static func symbol(_ id: String) -> String {
        switch id {
        case "must_see": "star.fill"; case "hidden_spots": "eye.slash.fill"; case "foods": "fork.knife"; case "route": "point.topleft.down.to.point.bottomright.curvepath.fill"
        case "themed_list": "list.star"; case "city_guide": "building.2.fill"; case "area_guide": "map.fill"; case "venue": "storefront.fill"
        default: "lightbulb.fill"
        }
    }
    static func tint(_ id: String) -> Color {
        switch id {
        case "must_see": Sketch.ochre; case "hidden_spots": Sketch.plum; case "foods": Sketch.coral; case "route": Sketch.sky
        case "tips": Sketch.sage; default: Sketch.clay
        }
    }
    static func country(_ code: String) -> String { Locale(identifier: "en").localizedString(forRegionCode: code) ?? code }
    static func flag(_ code: String) -> String { code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined() }
}

enum GuidesClient {
    static func browse(continent: String, country: String, city: String, region: String, kind: String, query: String, baseURL: String, token: String) async throws -> GuideBrowse {
        try await get("/api/community/guides", ["continent": continent, "country": country, "city": city, "region": region, "type": kind, "q": query], baseURL, token)
    }
    static func tips(city: String, country: String, baseURL: String, token: String) async throws -> GuideTips {
        try await get("/api/community/tips", ["city": city, "country": country], baseURL, token)
    }
    static func story(_ key: String, baseURL: String, token: String) async throws -> GuideStory {
        try await get("/api/community/video", ["key": key], baseURL, token)
    }
    private static func get<T: Decodable>(_ path: String, _ query: [String: String], _ baseURL: String, _ token: String) async throws -> T {
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = query.filter { !$0.value.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Screenshot checks without a server: `-TrippyGuidesDemo <browse.json>` and `-TrippyGuideStoryDemo <video.json>`.
enum GuidesDemo {
    static var browse: GuideBrowse? { CommunityDemo.file("-TrippyGuidesDemo").flatMap { try? JSONDecoder().decode(GuideBrowse.self, from: $0) } }
    static var story: GuideStory? { CommunityDemo.file("-TrippyGuideStoryDemo").flatMap { try? JSONDecoder().decode(GuideStory.self, from: $0) } }
}

// MARK: - Browse

struct GuidesBrowseView: View {
    let baseURL: String
    let token: String
    var query = ""
    @State private var continent = ""
    @State private var country = ""
    @State private var city = ""
    @State private var region = ""
    @State private var kind = ""
    @State private var data: GuideBrowse?
    @State private var tips: GuideTips?
    @State private var failed = false
    @State private var open: GuideCard?
    @Namespace private var kinds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            trail
            if let data {
                if !data.below.isEmpty || !data.regions.isEmpty { levels(data) }
                kindBar(data)
                if !city.isEmpty || !country.isEmpty, let tips, !tips.groups.isEmpty || !tips.foods.isEmpty { TipsShelf(tips: tips) }
                if data.guides.isEmpty {
                    Text("No guides here yet. Share a post about this place and it becomes one.").font(Sketch.text(14, relativeTo: .subheadline))
                        .foregroundStyle(Sketch.inkSoft).padding(.vertical, 20)
                }
                LazyVStack(spacing: 12) {
                    ForEach(Array(data.guides.enumerated()), id: \.element.id) { index, guide in
                        Button { TrippyHaptics.light(); open = guide } label: { GuideCardView(guide: guide) }
                            .buttonStyle(SketchPressStyle()).atlasRise(index)
                    }
                }
            } else if failed {
                Text("Couldn't load guides. Check the connection.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
        .task(id: "\(continent)|\(country)|\(city)|\(region)|\(kind)|\(query)") { await load() }
        .fullScreenCover(item: $open) { guide in GuideStoryView(card: guide, baseURL: baseURL, token: token) }
        #if DEBUG
        .task {
            // `-TrippyGuideStoryDemo <video.json> [-TrippyGuideStoryPage N]` opens the first guide's story on that page.
            guard GuidesDemo.story != nil, open == nil else { return }
            try? await Task.sleep(for: .seconds(1)); open = data?.guides.first { $0.key == GuidesDemo.story?.key } ?? data?.guides.first
        }
        #endif
    }

    /// Where you are: World › Europe › Italy › Rome. Each step goes back up.
    private var trail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                step("World", on: continent.isEmpty) { continent = ""; country = ""; city = ""; region = "" }
                if !continent.isEmpty { chevron; step(continent, on: country.isEmpty && region.isEmpty) { country = ""; city = ""; region = "" } }
                if !region.isEmpty { chevron; step(region, on: true) {} }
                if !country.isEmpty { chevron; step("\(GuideKinds.flag(country)) \(GuideKinds.country(country))", on: city.isEmpty) { city = "" } }
                if !city.isEmpty { chevron; step(city, on: true) {} }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: "\(continent)\(country)\(city)\(region)")
    }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Sketch.inkFaint) }
    private func step(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { TrippyHaptics.selection(); withAnimation(.snappy) { action() } } label: {
            Text(title).font(Sketch.text(14, on ? "Bold" : "SemiBold", relativeTo: .subheadline)).foregroundStyle(on ? Sketch.ink : Sketch.inkSoft)
                .padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().fill(on ? Sketch.card : .clear))
        }.buttonStyle(SketchPressStyle()).transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// The level below, as big round tiles: continents, then countries, then cities. Named regions sit alongside.
    private func levels(_ data: GuideBrowse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(data.below, id: \.name) { item in
                    Button {
                        TrippyHaptics.light()
                        withAnimation(.snappy) {
                            if continent.isEmpty { continent = item.name } else if country.isEmpty { country = item.name } else { city = item.name }
                        }
                    } label: { tile(item.name, count: item.count, flag: continent.isEmpty || !country.isEmpty ? nil : GuideKinds.flag(item.name)) }
                    .buttonStyle(SketchPressStyle())
                }
                ForEach(data.regions, id: \.name) { item in
                    Button { TrippyHaptics.light(); withAnimation(.snappy) { region = item.name } } label: { tile(item.name, count: item.count, flag: "⛰") }
                        .buttonStyle(SketchPressStyle())
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.horizontal, -22)
    }
    private func tile(_ name: String, count: Int, flag: String?) -> some View {
        VStack(spacing: 6) {
            Group {
                if let flag { Text(flag).font(.system(size: 28)) }
                else { Image(systemName: continent.isEmpty ? "globe.europe.africa.fill" : "building.2.fill").font(.system(size: 24, weight: .semibold)) }
            }
                .foregroundStyle(Sketch.clay).frame(width: 64, height: 64).background(Circle().fill(Sketch.card))
                .overlay(Circle().strokeBorder(Sketch.rule, lineWidth: 0.7))
            Text(continent.isEmpty || !country.isEmpty ? name : GuideKinds.country(name)).font(Sketch.text(12, "Bold", relativeTo: .caption)).lineLimit(1)
            Text("\(count)").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
        }
        .frame(width: 84)
    }

    private func kindBar(_ data: GuideBrowse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                kindChip("", "All", "square.grid.2x2.fill", data.count, Sketch.ink)
                ForEach(data.types.sorted { (GuideKinds.order.firstIndex(of: $0.id) ?? 99) < (GuideKinds.order.firstIndex(of: $1.id) ?? 99) }) { item in
                    kindChip(item.id, GuideKinds.title(item.id), GuideKinds.symbol(item.id), item.count, GuideKinds.tint(item.id))
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.horizontal, -22)
    }
    private func kindChip(_ id: String, _ title: String, _ symbol: String, _ count: Int, _ tint: Color) -> some View {
        let on = kind == id
        return Button { TrippyHaptics.selection(); withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { kind = id } } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).symbolEffect(.bounce, value: on)
                Text(title).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                Text("\(count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).opacity(0.6)
            }
            .foregroundStyle(on ? Color.white : tint).padding(.horizontal, 12).frame(minHeight: 40)
            .background { if on { Capsule().fill(tint).matchedGeometryEffect(id: "kind", in: kinds) } else { Capsule().fill(tint.opacity(0.12)) } }
        }.buttonStyle(SketchPressStyle())
    }

    private func load() async {
        if let demo = GuidesDemo.browse { data = demo; return }
        do {
            data = try await GuidesClient.browse(continent: continent, country: country, city: city, region: region, kind: kind, query: query, baseURL: baseURL, token: token)
            failed = false
            tips = country.isEmpty && city.isEmpty ? nil : try? await GuidesClient.tips(city: city, country: country, baseURL: baseURL, token: token)
        } catch { failed = data == nil }
    }
}

/// One guide in the list: its kinds, where it applies, and what is inside.
struct GuideCardView: View {
    let guide: GuideCard
    var body: some View {
        let lead = guide.types.sorted { (GuideKinds.order.firstIndex(of: $0) ?? 99) < (GuideKinds.order.firstIndex(of: $1) ?? 99) }.first ?? "tips"
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GuideKinds.tint(lead).opacity(0.14))
                Image(systemName: GuideKinds.symbol(lead)).font(.system(size: 22, weight: .semibold)).foregroundStyle(GuideKinds.tint(lead))
            }
            .frame(width: 58, height: 74)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: guide.platform == "youtube" ? "play.rectangle.fill" : "music.note").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white).frame(width: 20, height: 20).background(Circle().fill(guide.platform == "youtube" ? CommunityStyle.youtubeRed : CommunityStyle.tiktokBlack))
                    .offset(x: 5, y: 5)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(guide.breadcrumb.isEmpty ? GuideKinds.title(lead).uppercased() : guide.breadcrumb.uppercased())
                    .font(Sketch.eyebrow).tracking(0.7).foregroundStyle(GuideKinds.tint(lead)).lineLimit(1)
                Text(guide.title).font(Sketch.text(16, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink).lineLimit(2).multilineTextAlignment(.leading)
                if !guide.summary.isEmpty {
                    Text(guide.summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 10) {
                    if guide.routeStops > 0 { count("mappin.and.ellipse", "\(guide.routeStops) stops") }
                    else if guide.places > 0 { count("mappin", "\(guide.places) places") }
                    if guide.foods > 0 { count("fork.knife", "\(guide.foods) dishes") }
                    if guide.tips > 0 { count("lightbulb", "\(guide.tips) tips") }
                    if let author = guide.author { Text("@" + author).lineLimit(1) }
                }
                .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .accessibilityElement(children: .combine)
    }
    private func count(_ symbol: String, _ text: String) -> some View { Label(text, systemImage: symbol).labelStyle(.titleAndIcon) }
}

/// "Before you go": tips pooled from the city up to its country and continent, and what to eat.
struct TipsShelf: View {
    let tips: GuideTips
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tips.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text("TIPS FOR \(group.title.uppercased())").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.sage)
                    ForEach(Array(group.tips.prefix(expanded ? 12 : 3).enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill").font(.system(size: 11)).foregroundStyle(Sketch.sage).frame(width: 18).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                                if let detail = tip.detail, !detail.isEmpty { Text(detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
                            }
                        }
                    }
                }
            }
            if !tips.foods.isEmpty {
                Text("FOOD TO TRY").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.coral)
                BubbleFlow(spacing: 6) {
                    ForEach(tips.foods.prefix(expanded ? 20 : 8)) { food in
                        SketchTag(text: food.mentions > 1 ? "\(food.name) · \(food.mentions)" : food.name, tint: Sketch.coral, symbol: "fork.knife")
                    }
                }
            }
            if tips.groups.contains(where: { $0.tips.count > 3 }) || tips.foods.count > 8 {
                Button(expanded ? "Show less" : "Show all") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(Sketch.text(13, "Bold", relativeTo: .footnote)).frame(minHeight: 44)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.sage.opacity(0.08)))
    }
}

// MARK: - The story

/// One guide as a full-screen story: a cover, then one idea per page. Tap the right side for the next page,
/// the left for the one before, hold to pause reading. Each page can be saved where it belongs.
struct GuideStoryView: View {
    let card: GuideCard
    let baseURL: String
    let token: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var story: GuideStory?
    @State private var page: Int = {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "TrippyGuideStoryPage")
        #else
        return 0
        #endif
    }()
    @State private var saved: Set<String> = []

    enum Page: Hashable { case cover, places(Int), tips(Int), foods, route, end }

    private var pages: [Page] {
        guard let story else { return [.cover] }
        var out: [Page] = [.cover]
        if let route = story.route, !route.stops.isEmpty { out.append(.route) }
        out += story.places.indices.map { Page.places($0) }
        out += stride(from: 0, to: story.tips.count, by: 3).map { Page.tips($0) }
        if !(story.foods ?? []).isEmpty { out.append(.foods) }
        out.append(.end)
        return out
    }
    private var tint: Color { GuideKinds.tint(card.types.first ?? "tips") }

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55), Sketch.ink.opacity(0.92)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 14) {
                progress
                HStack {
                    Text(card.breadcrumb.isEmpty ? (card.author.map { "@" + $0 } ?? "") : card.breadcrumb).font(Sketch.text(12, "Bold", relativeTo: .caption))
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44) }
                        .accessibilityLabel("Close")
                }
                ZStack {
                    content(pages[min(page, pages.count - 1)])
                        .id(page)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    // Left third goes back, the rest moves on.
                    turn(value.location.x < 120 ? -1 : 1)
                })
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .task {
            if let demo = GuidesDemo.story { story = demo; return }
            story = try? await GuidesClient.story(card.key, baseURL: baseURL, token: token)
        }
        .sensoryFeedback(.selection, trigger: page)
        .accessibilityAction(named: "Next page") { turn(1) }
        .accessibilityAction(named: "Previous page") { turn(-1) }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule().fill(.white.opacity(index <= page ? 0.95 : 0.3)).frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.25), value: page)
    }

    private func turn(_ by: Int) {
        let next = page + by
        guard pages.indices.contains(next) else { if by > 0 { dismiss() }; return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { page = next }
    }

    @ViewBuilder private func content(_ item: Page) -> some View {
        switch item {
        case .cover:
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                BubbleFlow(spacing: 6) {
                    ForEach(card.types, id: \.self) { kind in
                        Label(GuideKinds.title(kind), systemImage: GuideKinds.symbol(kind)).font(Sketch.text(12, "Bold", relativeTo: .caption))
                            .padding(.horizontal, 10).frame(minHeight: 28).background(Capsule().fill(.white.opacity(0.18)))
                    }
                }
                Text(card.title).font(Sketch.display(.largeTitle, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                if !card.summary.isEmpty { Text(card.summary).font(Sketch.text(17, relativeTo: .body)).opacity(0.9).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 14) {
                    if card.routeStops > 0 { Label("\(card.routeStops) stops", systemImage: "mappin.and.ellipse") }
                    if card.places > 0 { Label("\(card.places) places", systemImage: "mappin") }
                    if card.tips > 0 { Label("\(card.tips) tips", systemImage: "lightbulb") }
                    if card.foods > 0 { Label("\(card.foods) dishes", systemImage: "fork.knife") }
                }
                .font(Sketch.text(13, "Bold", relativeTo: .footnote)).opacity(0.85)
                Spacer()
                Label("Tap to start", systemImage: "hand.tap").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).opacity(0.7)
                    .frame(maxWidth: .infinity)
            }
        case .route:
            if let route = story?.route { RouteStoryPage(route: route) }
        case .places(let index):
            if let place = story?.places[safe: index] { placePage(place, index: index) }
        case .tips(let start):
            VStack(alignment: .leading, spacing: 18) {
                Text("TIPS").font(Sketch.eyebrow).tracking(1.2).opacity(0.8)
                ForEach(Array((story?.tips ?? []).dropFirst(start).prefix(3).enumerated()), id: \.offset) { offset, tip in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tip.title).font(Sketch.display(.title2, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text(tip.detail).font(Sketch.text(16, relativeTo: .body)).opacity(0.88).fixedSize(horizontal: false, vertical: true)
                    }
                    .atlasRise(offset)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .foods:
            VStack(alignment: .leading, spacing: 14) {
                Text("WHAT TO EAT").font(Sketch.eyebrow).tracking(1.2).opacity(0.8)
                ForEach(Array((story?.foods ?? []).prefix(8).enumerated()), id: \.offset) { offset, food in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(offset + 1)").font(Sketch.text(15, "ExtraBold", relativeTo: .body)).frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(Sketch.text(18, "Bold", relativeTo: .headline))
                            if let detail = food.detail, !detail.isEmpty { Text(detail).font(Sketch.text(14, relativeTo: .subheadline)).opacity(0.85) }
                            if let place = food.where, !place.isEmpty { Label(place, systemImage: "mappin").font(Sketch.text(12, "SemiBold", relativeTo: .caption)).opacity(0.75) }
                        }
                    }
                    .atlasRise(offset)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .end:
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).symbolEffect(.bounce, value: page)
                Text("That's the guide").font(Sketch.display(.title, weight: .bold))
                if !saved.isEmpty { Text("\(saved.count) saved to your places").font(Sketch.text(15, relativeTo: .body)).opacity(0.85) }
                if let url = URL(string: card.url) {
                    Link(destination: url) {
                        Label("Watch the original", systemImage: "arrow.up.right").font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                            .padding(.horizontal, 20).frame(minHeight: 50).background(Capsule().fill(.white))
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func placePage(_ place: CommunityPlace, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PLACE \(index + 1) OF \(story?.places.count ?? 0)").font(Sketch.eyebrow).tracking(1.2).opacity(0.8)
            Text(place.name).font(Sketch.display(.largeTitle, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            if let hood = place.neighborhood { Label(hood, systemImage: "mappin").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).opacity(0.85) }
            if !place.summary.isEmpty { Text(place.summary).font(Sketch.text(17, relativeTo: .body)).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(((place.mustTry ?? []).map { "Try: " + $0 } + (place.tips ?? [])).prefix(4).enumerated()), id: \.offset) { offset, line in
                Label(line, systemImage: "sparkle").font(Sketch.text(15, relativeTo: .subheadline)).opacity(0.92).atlasRise(offset)
            }
            Spacer()
            if place.latitude != nil {
                let on = saved.contains(place.id)
                Button {
                    TrippyHaptics.success()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { if on { saved.remove(place.id) } else { saved.insert(place.id) } }
                } label: {
                    Label(on ? "Saved" : "Save to my places", systemImage: on ? "heart.fill" : "heart").font(Sketch.text(15, "Bold", relativeTo: .body))
                        .foregroundStyle(on ? .white : Sketch.ink).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(on ? Sketch.coral : .white)).symbolEffect(.bounce, value: on)
                }
                .buttonStyle(SketchPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A route on one page: its stops as a line that draws itself, with nights and the way it travels.
private struct RouteStoryPage: View {
    let route: GuideStory.Route
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("THE ROUTE").font(Sketch.eyebrow).tracking(1.2).opacity(0.8)
            HStack(spacing: 14) {
                Label(route.mode.capitalized, systemImage: route.mode == "train" ? "tram.fill" : route.mode == "car" ? "car.fill" : route.mode == "hike" || route.mode == "walk" ? "figure.hiking" : "point.topleft.down.to.point.bottomright.curvepath")
                if let days = route.days, days > 0 { Label("\(days) days", systemImage: "calendar") }
                if let cost = route.costHint, !cost.isEmpty { Label(cost, systemImage: "eurosign") }
            }
            .font(Sketch.text(14, "Bold", relativeTo: .subheadline))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle().fill(.white).frame(width: 14, height: 14).scaleEffect(drawn ? 1 : 0.2)
                                .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.12), value: drawn)
                            if index < route.stops.count - 1 {
                                Rectangle().fill(.white.opacity(0.6)).frame(width: 2, height: 42)
                                    .scaleEffect(y: drawn ? 1 : 0, anchor: .top)
                                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.12 + 0.1), value: drawn)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text((stop.countryCode.map(GuideKinds.flag).map { $0 + " " } ?? "") + stop.name).font(Sketch.text(18, "Bold", relativeTo: .headline))
                            if let nights = stop.nights, nights > 0 { Text("\(nights) \(nights == 1 ? "night" : "nights")").font(Sketch.text(13, relativeTo: .footnote)).opacity(0.8) }
                        }
                        .offset(y: -3)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if reduceMotion { drawn = true } else { withAnimation { drawn = true } } }
    }
}
