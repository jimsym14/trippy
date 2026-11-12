import SwiftUI
import MapKit
import AuthenticationServices

// MARK: - What onboarding remembers

/// First launch only: a few cards, where you live, where you've been, an optional account.
enum OnboardingStore {
    private static let key = "trippy.onboarding.v1.done"
    static var shouldShow: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-TrippyOnboarding") { return true }
        // Screenshot and demo launches skip it.
        if args.contains(where: { $0.hasPrefix("-Trippy") }) { return false }
        return !UserDefaults.standard.bool(forKey: key)
    }
    static func finish() { UserDefaults.standard.set(true, forKey: key) }
}

/// Where the traveller lives, as precise as they chose: a country, maybe a city, maybe an area.
/// The map opens there, shows a home pin, and Been to marks the home country.
struct HomeProfile: Codable, Equatable {
    var countryCode: String?
    var city: String?
    var cityLatitude: Double?
    var cityLongitude: Double?
    var area: String?
    var areaLatitude: Double?
    var areaLongitude: Double?
    var countryLatitude: Double?
    var countryLongitude: Double?

    var countryName: String? { countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } }
    /// The most precise point the traveller gave.
    var coordinate: CLLocationCoordinate2D? {
        if let a = areaLatitude, let b = areaLongitude { return .init(latitude: a, longitude: b) }
        if let a = cityLatitude, let b = cityLongitude { return .init(latitude: a, longitude: b) }
        if let a = countryLatitude, let b = countryLongitude { return .init(latitude: a, longitude: b) }
        return nil
    }
    /// How far the map zooms out to show home.
    var span: Double { areaLatitude != nil ? 0.03 : cityLatitude != nil ? 0.12 : 6 }
    var label: String { [area, city, countryName].compactMap { $0 }.first ?? "Home" }
    var isEmpty: Bool { countryCode == nil && city == nil && area == nil }
}

enum HomeProfileStore {
    private static let key = "trippy.home.profile.v1"
    static func load() -> HomeProfile? {
        guard let data = UserDefaults.standard.data(forKey: key), let home = try? JSONDecoder().decode(HomeProfile.self, from: data), !home.isEmpty else { return nil }
        return home
    }
    static func save(_ home: HomeProfile?) {
        guard let home, !home.isEmpty, let data = try? JSONEncoder().encode(home) else { UserDefaults.standard.removeObject(forKey: key); return }
        UserDefaults.standard.set(data, forKey: key)
        // Prices and city comparisons already read this.
        if let city = home.cityLatitude.flatMap({ lat in home.cityLongitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }) {
            HomeCityStore.remember(city)
        }
    }
}

// MARK: - Countries and cities, offline

/// Every country with its flag and continent, and the bundled city list (3,000 cities)
/// for instant suggestions and a point on the globe without a network lookup.
struct CountryEntry: Identifiable, Hashable {
    let code: String
    let name: String
    let continent: String
    let latitude: Double?
    let longitude: Double?
    var id: String { code }
    var flag: String { WorldGlobeView.flag(code) }
}

struct CityEntry: Identifiable, Hashable {
    let name: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    var id: String { name + countryCode }
}

enum PlaceCatalog {
    static let countries: [CountryEntry] = {
        let english = Locale(identifier: "en")
        var anchors: [String: (Double, Double)] = [:]
        for city in cities where anchors[city.countryCode] == nil { anchors[city.countryCode] = (city.latitude, city.longitude) }
        let codes = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        return codes.compactMap { code -> CountryEntry? in
            guard let name = english.localizedString(forRegionCode: code), WorldContinentCatalog.name(for: code) != "Other" else { return nil }
            return CountryEntry(code: code, name: name, continent: WorldContinentCatalog.name(for: code),
                                latitude: anchors[code]?.0, longitude: anchors[code]?.1)
        }
        .sorted { (anchors[$0.code] == nil ? 1 : 0, $0.name) < (anchors[$1.code] == nil ? 1 : 0, $1.name) }
    }()

    static let cities: [CityEntry] = {
        guard let url = Bundle.main.url(forResource: "statlas-city-snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let points = root["points"] as? [[String: Any]] else { return [] }
        let english = Locale(identifier: "en")
        var byName: [String: String] = [:]
        for code in Locale.Region.isoRegions.map(\.identifier) where code.count == 2 {
            if let name = english.localizedString(forRegionCode: code) { byName[name.lowercased()] = code }
        }
        let aliases = ["united states": "US", "united kingdom": "GB", "czech republic": "CZ", "south korea": "KR", "russia": "RU",
                       "turkey": "TR", "vietnam": "VN", "hong kong": "HK", "taiwan": "TW", "bosnia and herzegovina": "BA",
                       "north macedonia": "MK", "ivory coast": "CI", "kosovo": "XK"]
        let all = points.compactMap { p -> CityEntry? in
            guard let name = p["n"] as? String, let country = (p["c"] as? String)?.lowercased(),
                  let lat = (p["lat"] as? NSNumber)?.doubleValue, let lon = (p["lon"] as? NSNumber)?.doubleValue,
                  let code = aliases[country] ?? byName[country] else { return nil }
            return CityEntry(name: name, countryCode: code, latitude: lat, longitude: lon)
        }
        // The source lists districts as cities ("Paris 15 Vaugirard", "Buda" and "Pest" beside "Budapest").
        // The list is biggest first, so a place is dropped when a bigger one in the same country is on top of it
        // (within 9 km), or is nearby (25 km) and is named in it.
        var kept: [String: [CityEntry]] = [:]
        var result: [CityEntry] = []
        for city in all {
            if city.name.contains(where: \.isNumber) { continue }
            let folded = VisitedPlace.normalized(city.name)
            let duplicate = (kept[city.countryCode] ?? []).contains { big in
                let dLat = (big.latitude - city.latitude) * 111, dLon = (big.longitude - city.longitude) * 111 * cos(city.latitude * .pi / 180)
                let km = (dLat * dLat + dLon * dLon).squareRoot()
                return km < 9 || (km < 25 && folded.contains(VisitedPlace.normalized(big.name)))
            }
            if duplicate { continue }
            kept[city.countryCode, default: []].append(city); result.append(city)
        }
        return result
    }()

    static func cities(in code: String) -> [CityEntry] { cities.filter { $0.countryCode == code } }
    /// The listed city a searched place is, if it is one: same name in the same country, or within 6 km of its centre.
    static func significantCity(name: String, countryCode: String?, latitude: Double, longitude: Double) -> CityEntry? {
        let folded = VisitedPlace.normalized(name)
        return cities.first { city in
            guard countryCode == nil || city.countryCode == countryCode, abs(city.latitude - latitude) < 0.6, abs(city.longitude - longitude) < 0.9 else { return false }
            let dLat = (city.latitude - latitude) * 111, dLon = (city.longitude - longitude) * 111 * cos(latitude * .pi / 180)
            let km = (dLat * dLat + dLon * dLon).squareRoot()
            return km < 6 || (km < 40 && VisitedPlace.normalized(city.name) == folded)
        }
    }
    static func country(_ code: String?) -> CountryEntry? { countries.first { $0.code == code } }
    static var deviceCountry: String? { Locale.current.region?.identifier }
}

// MARK: - Flow

/// Welcome → how you'd like to use Trippy (account or just this phone) → where you live →
/// where you've been → the briefing. Everything after the welcome can be skipped.
struct OnboardingFlow: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // DEBUG `-TrippyOnboardingStep N` opens a step directly for screenshots.
    @State private var step = UserDefaults.standard.integer(forKey: "TrippyOnboardingStep")
    @State private var home = HomeProfileStore.load() ?? HomeProfile()
    @AppStorage("trippy.native.visitedPlaces.v1") private var visitedStorage = "[]"
    @ObservedObject private var account = AccountSession.shared

    private enum Step: Int { case welcome, access, home, been, brief1, brief2, brief3 }
    private let last = Step.brief3.rawValue
    private var current: Step { Step(rawValue: step) ?? .welcome }
    private var isBrief: Bool { step >= Step.brief1.rawValue }

    var body: some View {
        ZStack {
            OnboardingBackdrop(step: step)
            VStack(spacing: 0) {
                if current != .welcome { topBar }
                Group {
                    switch current {
                    case .welcome: WelcomeStep(next: { go(1) }, signIn: { go(1) })
                    case .access: AccessStep(onContinue: { go(2) })
                    case .home: HomeStep(home: $home)
                    case .been: BeenStep(home: home, storage: $visitedStorage)
                    case .brief1, .brief2, .brief3: BriefCardStep(card: BriefCard.all[step - Step.brief1.rawValue]).id(step)
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if current != .welcome && current != .access { bottomBar }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard isBrief else { return }
            if value.translation.width < -60 { next() } else if value.translation.width > 60 && step > Step.brief1.rawValue { back() }
        })
    }

    private var topBar: some View {
        HStack {
            Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                .accessibilityLabel("Back")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...last, id: \.self) { i in
                    Capsule().fill(i <= step ? Sketch.ink : Sketch.ink.opacity(0.15)).frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: step)
            .accessibilityElement().accessibilityLabel("Step \(step) of \(last)")
            Spacer()
            if isBrief {
                Button { finish() } label: {
                    Text("Skip").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(Sketch.ink.opacity(0.06)))
                }
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .accessibilityHint("Skips the tour")
            } else { Color.clear.frame(width: 64, height: 44) }
        }
        .foregroundStyle(Sketch.ink)
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        let label: String = switch current {
        case .home: home.isEmpty ? "Skip for now" : "Continue"
        case .been: VisitedPlace.decode(visitedStorage).isEmpty ? "Skip for now" : "Continue"
        case .brief3: "Start exploring"
        default: "Next"
        }
        return Button(action: next) {
            Text(label).font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Capsule().fill(Sketch.ink))
        }
        .buttonStyle(SketchPressStyle())
        .padding(.horizontal, 24).padding(.bottom, 12)
    }

    private func go(_ target: Int) {
        if current == .home { HomeProfileStore.save(home) }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) { step = target }
    }
    private func next() { step >= last ? finish() : go(step + 1) }
    private func back() { go(max(step - 1, 0)) }
    private func finish() {
        HomeProfileStore.save(home)
        OnboardingStore.finish()
        onFinish()
    }
}


/// Paper with slow-drifting watercolour blobs that change hue per step.
struct OnboardingBackdrop: View {
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private var tints: [Color] {
        switch step {
        case 1: [Sketch.coral, Sketch.plum]
        case 2: [Sketch.sky, Sketch.sage]
        case 3: [Sketch.sage, Sketch.sky]
        case 4: [Sketch.coral, Sketch.sage]
        case 5: [Sketch.plum, Sketch.sky]
        default: [Sketch.sky, Sketch.coral]
        }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Sketch.paper
                // Warm pigments over near-black read as brown smudges, so dark mode
                // keeps them faint and lets the cooler second glow lead.
                Circle().fill(tints[0].opacity(scheme == .dark ? 0.10 : 0.22)).frame(width: 420).blur(radius: 70)
                    .offset(x: -120 + 30 * sin(t / 5), y: -260 + 20 * cos(t / 6))
                Circle().fill(tints[1].opacity(scheme == .dark ? 0.12 : 0.18)).frame(width: 380).blur(radius: 80)
                    .offset(x: 140 + 25 * cos(t / 7), y: 300 + 30 * sin(t / 5))
            }
            .animation(.easeInOut(duration: 0.8), value: step)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let next: () -> Void
    let signIn: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var texture: UIImage?
    @State private var drawn: CGFloat = 0
    @State private var shown = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var globe: CGFloat { typeSize.isAccessibilitySize ? 170 : 280 }

    var body: some View {
        ScrollView {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            ZStack {
                BeenGlobe3DView(texture: texture, focus: .init(latitude: 38, longitude: 18), focusID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                dark: scheme == .dark, reduceMotion: reduceMotion)
                    .frame(width: globe, height: globe)
                    .shadow(color: Sketch.sky.opacity(0.25), radius: 30, y: 16)
                    // Without its texture the sphere renders plain white; fade in once it's painted.
                    .opacity(texture == nil ? 0 : 1).animation(.easeOut(duration: 0.4), value: texture == nil)
                    .accessibilityHidden(true)
                // Hand-drawn flight arcs looping round the globe.
                FlightArcs().trim(from: 0, to: drawn)
                    .stroke(Sketch.coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 7]))
                    .frame(width: globe * 1.18, height: globe * 1.18).allowsHitTesting(false)
                ForEach(Array(FlightArcs.pins.enumerated()), id: \.offset) { index, point in
                    Image(systemName: "mappin.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, [Sketch.coral, Sketch.plum, Sketch.sage][index % 3])
                        .offset(x: (point.x - 0.5) * globe * 1.18, y: (point.y - 0.5) * globe * 1.18)
                        .scaleEffect(shown ? 1 : 0.2).opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.7 + Double(index) * 0.25), value: shown)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: globe * 1.22)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                Image(scheme == .dark ? "BrandWordmarkDark" : "BrandWordmark").resizable().scaledToFit().frame(height: 34).accessibilityLabel("Trippy")
                Text("Everything you save, every trip you plan, every place you’ve been. On one map.")
                    .font(Sketch.display(.title3, weight: .semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
            Spacer(minLength: 16)
            VStack(spacing: 10) {
                Button(action: next) {
                    Text("Get started").font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                        .frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(Sketch.ink))
                }
                .buttonStyle(SketchPressStyle())
                Button("I already have an account", action: signIn)
                    .font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.inkSoft).frame(minHeight: 44)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .frame(minHeight: typeSize.isAccessibilitySize ? nil : 640)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            let key = GlobeTextureKey(dark: scheme == .dark, satellite: true, style: "onboarding-real")
            texture = await GlobeTextureBuilder.shared.texture(key: key, shapes: nil, visits: [])
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { shown = true }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 2.2).delay(0.3)) { drawn = 1 }
            if reduceMotion { drawn = 1 }
        }
    }
}

/// Three looping arcs between pins around the globe, in a unit square.
private struct FlightArcs: Shape {
    static let pins: [CGPoint] = [.init(x: 0.12, y: 0.36), .init(x: 0.86, y: 0.24), .init(x: 0.78, y: 0.84), .init(x: 0.2, y: 0.8)]
    func path(in rect: CGRect) -> Path {
        func p(_ u: CGPoint) -> CGPoint { .init(x: rect.minX + u.x * rect.width, y: rect.minY + u.y * rect.height) }
        var path = Path()
        let pins = Self.pins
        path.move(to: p(pins[0]))
        path.addQuadCurve(to: p(pins[1]), control: p(.init(x: 0.45, y: -0.12)))
        path.addQuadCurve(to: p(pins[2]), control: p(.init(x: 1.12, y: 0.55)))
        path.addQuadCurve(to: p(pins[3]), control: p(.init(x: 0.5, y: 1.1)))
        return path
    }
}

// MARK: - Briefing

/// The killer features, last, once the map is set up. Each card is a short looping demo
/// (BriefDemos.swift) that ends on the app's most useful output for that feature.
struct BriefCard: Hashable {
    enum Demo: Hashable { case share, plan, world }
    let demo: Demo
    let eyebrow: String
    let title: String
    let body: String
    let tint: Color

    static let all: [BriefCard] = [
        BriefCard(demo: .share, eyebrow: "FROM TIKTOK", title: "Share it.\nWe’ll map it.",
                  body: "Videos or slides. Every spot, pinned.", tint: Sketch.coral),
        BriefCard(demo: .plan, eyebrow: "PLANS", title: "Days that\njust work.",
                  body: "Built around your stay. Swap anything.", tint: Sketch.sky),
        BriefCard(demo: .world, eyebrow: "YOUR WORLD", title: "Everywhere\nyou’ve been.",
                  body: "Watch your map fill in.", tint: Sketch.sage),
    ]
}

struct BriefCardStep: View {
    let card: BriefCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            GeometryReader { proxy in
                let aspect: CGFloat = 2.05
                let width = min(proxy.size.width - 96, (proxy.size.height - 8) / aspect)
                phone(width: width, height: width * aspect)
                    .scaleEffect(appear ? 1 : 0.94).offset(y: appear ? 0 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                Text(card.eyebrow).font(Sketch.eyebrow).tracking(1.6).foregroundStyle(card.tint)
                    .padding(.bottom, 12)
                Text(card.title).font(Sketch.display(.largeTitle, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(Sketch.ink)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                Text(card.body).font(Sketch.text(17, "Medium", relativeTo: .body)).multilineTextAlignment(.center).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .opacity(appear ? 1 : 0)
        }
        .padding(.bottom, 28)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.82)) { appear = true }
            if reduceMotion { appear = true }
        }
    }

    private func phone(width: CGFloat, height: CGFloat) -> some View {
        let corner = width * 0.14
        return Group {
            switch card.demo {
            case .share: ShareStage(tint: card.tint, width: width, height: height)
            case .plan: PlanDayDemo(tint: card.tint).clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(PhoneBezel(corner: corner))
            case .world: WorldDemo(tint: card.tint).clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(PhoneBezel(corner: corner))
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(card.demo == .share ? 0 : 0.18), radius: 22, y: 14)
        .accessibilityHidden(true)
    }
}

/// A device frame that reads as hardware in both appearances: near-black
/// in light mode, and a dark frame with a faint edge in dark mode, instead of
/// an ivory outline that glares against the dark backdrop.
private struct PhoneBezel: View {
    let corner: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape.strokeBorder(Color(white: scheme == .dark ? 0.16 : 0.12), lineWidth: 4)
            .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0), lineWidth: 0.75))
    }
}

// MARK: - Where you live

/// One search field that narrows as you go: country, then city, then area. Each level is optional;
/// the trail above it ("Greece › Athens › Koukaki") is what the map will use.
struct HomeStep: View {
    @Binding var home: HomeProfile
    /// Optional street address; stays on this phone only (see AccountData.deviceOnly).
    @AppStorage(HomeAddress.key) private var address = ""
    @State private var query = ""
    @StateObject private var search = LocalSearch()
    @FocusState private var focused: Bool

    private enum Level { case country, city, area }
    private var level: Level { home.countryCode == nil ? .country : home.city == nil ? .city : .area }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where’s home?").font(Sketch.display(.largeTitle, weight: .bold)).foregroundStyle(Sketch.ink)
                    Text("Optional. Your map starts here.")
                        .font(Sketch.text(17, "Medium", relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                }
                if !home.isEmpty { trail }
                if !(level == .area && home.area != nil) { field; results }
                if home.city != nil { addressCard.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 24)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: home)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, value in search.update(value, level: level == .area ? .area : .city, around: home.coordinate) }
    }

    /// Optional home address, explained: what it's for, and that it never leaves the phone.
    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("HOME ADDRESS · OPTIONAL").font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkFaint)
                Spacer()
                Label("Only on this phone", systemImage: "lock.fill").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.sage)
            }
            HStack(spacing: 10) {
                Image(systemName: "house").foregroundStyle(Sketch.inkFaint)
                TextField("Street and number", text: $address).font(Sketch.text(17, relativeTo: .body))
                    .textContentType(.fullStreetAddress).autocorrectionDisabled().submitLabel(.done)
                if !address.isEmpty {
                    Button { address = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Sketch.inkFaint) }
                        .accessibilityLabel("Clear address")
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
            Text("For your own use: directions can start from your door, and day plans can begin and end at home. It's saved on this phone only — never sent to us, not even to your account backup.")
                .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Greece › Athens › Koukaki, each part tappable to go back to it.
    private var trail: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.fill").foregroundStyle(Sketch.sage)
            ViewThatFits(in: .horizontal) {
                trailText.lineLimit(1)
                trailText.lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { withAnimation { home = HomeProfile(); query = "" } } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Sketch.inkFaint)
            }
            .accessibilityLabel("Clear home")
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var trailText: some View {
        let parts = [home.countryCode.map { "\(WorldGlobeView.flag($0)) \(home.countryName ?? $0)" }, home.city, home.area].compactMap { $0 }
        return Text(parts.joined(separator: "  ›  ")).font(Sketch.text(17, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
        Text(level == .country ? "COUNTRY" : level == .city ? "CITY · OPTIONAL" : "NEIGHBOURHOOD · OPTIONAL")
            .font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkFaint)
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
            TextField(prompt, text: $query).font(Sketch.text(17, relativeTo: .body)).focused($focused)
                .autocorrectionDisabled().submitLabel(.done)
            if search.loading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Sketch.ink : .clear, lineWidth: 1.5))
        }
    }

    private var prompt: String {
        switch level {
        case .country: "Country"
        case .city: "City"
        case .area: "Neighbourhood"
        }
    }

    @ViewBuilder private var results: some View {
        VStack(spacing: 0) {
            switch level {
            case .country:
                ForEach(countryOptions) { country in row("\(country.flag)  \(country.name)", detail: nil) { pick(country) } }
            case .city:
                ForEach(cityOptions) { city in row(city.name, detail: nil, symbol: "building.2") { pick(city) } }
                ForEach(search.results.prefix(5)) { r in row(r.title, detail: r.subtitle, symbol: "mappin") { Task { await pickCity(r) } } }
            case .area:
                ForEach(search.results.prefix(6)) { r in row(r.title, detail: r.subtitle, symbol: "house") { Task { await pickArea(r) } } }
                if query.isEmpty {
                    Text("For an exact home pin.").font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
                        .padding(.top, 10).padding(.leading, 16).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func row(_ title: String, detail: String?, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).foregroundStyle(Sketch.inkFaint).frame(width: 22) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Sketch.text(17, relativeTo: .body)).foregroundStyle(Sketch.ink)
                    if let detail, !detail.isEmpty { Text(detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint) }
                }
                Spacer()
            }
            .padding(.horizontal, 16).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Sketch.rule.opacity(0.7)).frame(height: 0.5).padding(.leading, 16) }
    }

    private var countryOptions: [CountryEntry] {
        if query.isEmpty {
            // The phone's region first, then a few common ones.
            let device = PlaceCatalog.deviceCountry.flatMap(PlaceCatalog.country)
            let common = ["GR", "IT", "ES", "GB", "DE", "FR", "US"].compactMap(PlaceCatalog.country)
            return ([device].compactMap { $0 } + common).reduce(into: [CountryEntry]()) { if !$0.contains($1) { $0.append($1) } }.prefix(6).map { $0 }
        }
        return Array(PlaceCatalog.countries.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(8))
    }
    private var cityOptions: [CityEntry] {
        guard let code = home.countryCode else { return [] }
        let cities = PlaceCatalog.cities(in: code)
        return Array((query.isEmpty ? cities : cities.filter { $0.name.localizedCaseInsensitiveContains(query) }).prefix(query.isEmpty ? 5 : 8))
    }

    private func pick(_ country: CountryEntry) {
        home = HomeProfile(countryCode: country.code, countryLatitude: country.latitude, countryLongitude: country.longitude)
        query = ""; UISelectionFeedbackGenerator().selectionChanged()
    }
    private func pick(_ city: CityEntry) {
        home.city = city.name; home.cityLatitude = city.latitude; home.cityLongitude = city.longitude
        query = ""; UISelectionFeedbackGenerator().selectionChanged()
    }
    private func pickCity(_ result: LocalSearch.Result) async {
        guard let place = await search.resolve(result) else { return }
        home.city = place.name; home.cityLatitude = place.latitude; home.cityLongitude = place.longitude; query = ""
    }
    private func pickArea(_ result: LocalSearch.Result) async {
        guard let place = await search.resolve(result) else { return }
        home.area = result.title; home.areaLatitude = place.latitude; home.areaLongitude = place.longitude; query = ""
        focused = false
    }
}


/// Apple Maps search completions, for cities and neighbourhoods outside the bundled list.
@MainActor final class LocalSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Result: Identifiable, Hashable { let id: String; let title: String; let subtitle: String; let completion: MKLocalSearchCompletion
        static func == (a: Result, b: Result) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    enum Kind { case city, area }
    @Published var results: [Result] = []
    @Published var loading = false
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(_ text: String, level: Kind, around center: CLLocationCoordinate2D?) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        if let center { completer.region = MKCoordinateRegion(center: center, latitudinalMeters: level == .area ? 40_000 : 1_500_000, longitudinalMeters: level == .area ? 40_000 : 1_500_000) }
        loading = true
        completer.queryFragment = text
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results.prefix(10).map { Result(id: $0.title + "|" + $0.subtitle, title: $0.title, subtitle: $0.subtitle, completion: $0) }
        Task { @MainActor in self.results = Array(found); self.loading = false }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.loading = false }
    }

    func resolve(_ result: Result) async -> (name: String, latitude: Double, longitude: Double, countryCode: String?)? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result.completion)).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return (item.placemark.locality ?? result.title, c.latitude, c.longitude, item.placemark.isoCountryCode)
    }
}

// MARK: - Been to

/// Tap countries on the globe and they fill in. A small card after each tap offers "When?"
/// (month and year, optional) and undo. Search is there for small countries and for speed.
struct BeenStep: View {
    let home: HomeProfile
    @Binding var storage: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focus: CLLocationCoordinate2D?
    @State private var focusID = UUID()
    @State private var texture: UIImage?
    @State private var geometries: [CountryGeometry] = []
    @State private var last: CountryEntry?
    @State private var lastWasAdd = true
    @State private var query = ""
    @State private var showCities = false
    @State private var cityQuery = ""
    @State private var looking = false
    @State private var zoomProbe: ZoomProbe?
    @State private var zoomTarget: ZoomAddTarget?
    @FocusState private var searching: Bool

    private var visits: [VisitedPlace] { VisitedPlace.decode(storage) }
    private var codes: [String] {
        var seen = Set<String>()
        return visits.compactMap { $0.countryCode?.uppercased() }.filter { seen.insert($0).inserted }
    }

    /// The flag whose visit date is being picked on the wheels.
    @State private var whenCode: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where have you been?").font(Sketch.display(.largeTitle, weight: .bold)).foregroundStyle(Sketch.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(codes.isEmpty ? "Tap the countries you know. Drag to turn the globe." : summary)
                        .font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                        .contentTransition(.numericText()).animation(.snappy, value: codes.count)
                }
                globe
                if !codes.isEmpty { flags }
                searchField
                if !query.isEmpty { searchResults }
                livedCities
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: codes.joined()) { await redraw() }
        .sheet(item: Binding(get: { whenCode.map(WhenCode.init) }, set: { whenCode = $0?.id })) { item in
            WhenPickerSheet(title: PlaceCatalog.country(item.id).map { "When did you go to \($0.name)?" } ?? "When did you go?",
                            date: Binding(get: { date(for: item.id) }, set: { setDate($0, for: item.id) }))
        }
    }
    private struct WhenCode: Identifiable { let id: String }

    private var summary: String {
        let percent = Int((Double(codes.count) / 195 * 100).rounded())
        return "\(codes.count) \(codes.count == 1 ? "country" : "countries") · \(percent)% of the world"
    }

    private var globe: some View {
        ZStack(alignment: .bottom) {
            BeenGlobe3DView(texture: texture, focus: focus ?? home.coordinate ?? .init(latitude: 42, longitude: 15), focusID: focusID,
                            dark: scheme == .dark, reduceMotion: reduceMotion, onTap: { tapped in Task { await toggle(at: tapped) } },
                            onSettle: { center, z in
                                let next = z < 3.9 ? ZoomProbe(latitude: (center.latitude * 50).rounded() / 50, longitude: (center.longitude * 50).rounded() / 50, level: .country) : nil
                                if next != zoomProbe { zoomProbe = next }
                            })
                .frame(height: 320)
                .overlay {
                    if let zoomTarget {
                        // Zoomed into a country: a "+" right where you're looking.
                        ZoomAddBubble(target: zoomTarget, added: codes.contains(zoomTarget.countryCode)) {
                            if let country = PlaceCatalog.country(zoomTarget.countryCode) { toggle(country) }
                        }
                        .offset(y: -30)
                        .id(zoomTarget.countryCode)
                    }
                }
                .task(id: zoomProbe) {
                    guard let zoomProbe else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { zoomTarget = nil }; return }
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    let found = await ZoomAddTarget.resolve(zoomProbe.center, level: .country)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { zoomTarget = found }
                }
                .accessibilityLabel("Globe. Tap a country to add it.")
            if looking { ProgressView().padding(.bottom, 12) }
            if let last { lastCard(last).padding(.bottom, 4).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: last)
    }

    /// "Italy added · When?" with an optional month and year, and undo.
    private func lastCard(_ country: CountryEntry) -> some View {
        HStack(spacing: 10) {
            Text(country.flag).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 0) {
                Text(country.name).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).lineLimit(1)
                Text(lastWasAdd ? "Added" : "Removed").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
            Spacer(minLength: 4)
            if lastWasAdd { WhenMenu(date: Binding(get: { date(for: country.code) }, set: { setDate($0, for: country.code) })) }
            Button(lastWasAdd ? "Undo" : "Add back") { toggle(country) }
                .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.coral).frame(minHeight: 44)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    /// The chosen countries as a row of flags; tap one to set when, long-press to remove.
    private var flags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    if let country = PlaceCatalog.country(code) {
                        Menu {
                            Section(country.name) {
                                Button(date(for: code).map { "When: " + $0.formatted(.dateTime.month(.wide).year()) } ?? "When did you go?",
                                       systemImage: "calendar") { whenCode = code }
                                Button("Remove", systemImage: "trash", role: .destructive) { toggle(country) }
                            }
                        } label: {
                            Text(country.flag).font(.system(size: 26)).frame(width: 46, height: 46)
                                .background(Circle().fill(Sketch.card)).overlay(Circle().strokeBorder(Sketch.rule, lineWidth: 0.7))
                        }
                        .accessibilityLabel(country.name)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: codes)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
            TextField("Or type a country", text: $query).font(Sketch.text(17, relativeTo: .body)).focused($searching).autocorrectionDisabled()
        }
        .padding(.horizontal, 4).frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(searching ? Sketch.ink : Sketch.rule).frame(height: searching ? 2 : 1) }
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(PlaceCatalog.countries.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(6)) { country in
                let chosen = codes.contains(country.code)
                Button { toggle(country); query = "" } label: {
                    HStack {
                        Text("\(country.flag)  \(country.name)").font(Sketch.text(17, relativeTo: .body)).foregroundStyle(Sketch.ink)
                        Spacer()
                        Image(systemName: chosen ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(chosen ? Sketch.sage : Sketch.inkFaint)
                    }
                    .frame(minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(Sketch.rule).frame(height: 0.5) }
            }
        }
    }

    private var livedCities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { showCities.toggle() } } label: {
                HStack {
                    Label("Cities you’ve lived in", systemImage: "house").font(Sketch.text(16, "SemiBold", relativeTo: .body))
                    Spacer()
                    Image(systemName: showCities ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Sketch.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showCities {
                TextField("City", text: $cityQuery).font(Sketch.text(17, relativeTo: .body)).autocorrectionDisabled()
                    .frame(minHeight: 44).overlay(alignment: .bottom) { Rectangle().fill(Sketch.rule).frame(height: 1) }
                let typed = cityQuery.trimmingCharacters(in: .whitespaces)
                let matches = typed.count >= 2 ? PlaceCatalog.cities.filter { $0.name.localizedCaseInsensitiveContains(typed) }.prefix(5).map { $0 }
                    : (home.countryCode.map(PlaceCatalog.cities(in:)) ?? []).prefix(4).map { $0 }
                FlowLayout(spacing: 8) {
                    ForEach(matches) { city in
                        let chosen = visits.contains { $0.name == city.name && $0.countryCode?.uppercased() == city.countryCode }
                        Bubble(text: city.name, tint: Sketch.plum, selected: chosen, symbol: chosen ? "checkmark" : "plus") { toggle(city: city) }
                    }
                }
            }
        }
    }

    // MARK: Changes

    private func toggle(at coordinate: CLLocationCoordinate2D) async {
        looking = true; defer { looking = false }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let code = try? await CLGeocoder().reverseGeocodeLocation(location).first?.isoCountryCode,
              let country = PlaceCatalog.country(code) else { return }
        toggle(country, at: coordinate)
    }

    private func toggle(_ country: CountryEntry, at tapped: CLLocationCoordinate2D? = nil) {
        var records = visits
        let adding = !codes.contains(country.code)
        if adding {
            let point = country.latitude.flatMap { lat in country.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } ?? tapped
            guard let point else { return }
            records = VisitedPlace.adding(VisitedPlace(name: country.name, countryCode: country.code, latitude: point.latitude, longitude: point.longitude, kind: .country, dated: false), to: records)
            focus = point; focusID = UUID()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            records.removeAll { $0.countryCode?.uppercased() == country.code }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { storage = VisitedPlace.encode(records); last = country; lastWasAdd = adding }
    }

    private func toggle(city: CityEntry) {
        var records = visits
        if records.contains(where: { $0.name == city.name && $0.countryCode?.uppercased() == city.countryCode }) {
            records.removeAll { $0.name == city.name && $0.countryCode?.uppercased() == city.countryCode }
        } else {
            records = VisitedPlace.adding(VisitedPlace(name: city.name, countryCode: city.countryCode, latitude: city.latitude, longitude: city.longitude, kind: .city, dated: false), to: records)
            focus = .init(latitude: city.latitude, longitude: city.longitude); focusID = UUID()
        }
        withAnimation(.snappy) { storage = VisitedPlace.encode(records) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// nil = "any time" (stored as the moment it was added, as the Been page always has).
    private func date(for code: String) -> Date? {
        visits.filter { $0.countryCode?.uppercased() == code }.compactMap(\.when).min()
    }
    private func setDate(_ date: Date?, for code: String) {
        var records = visits
        for i in records.indices where records[i].countryCode?.uppercased() == code { records[i].setWhen(date) }
        storage = VisitedPlace.encode(records)
    }

    /// Visited countries drawn on the monochrome globe.
    private func redraw() async {
        let snapshot = BeenPassportSnapshot(visits)
        let requests = snapshot.countries.compactMap { group -> CountryShapeStore.Request? in
            guard let code = group.countryCode else { return nil }
            return .init(code: code, latitude: group.coordinate.latitude, longitude: group.coordinate.longitude)
        }
        let key = { GlobeTextureKey(dark: scheme == .dark, satellite: false, style: "been-step-\(codes.joined())-\(geometries.count)") }
        texture = await GlobeTextureBuilder.shared.texture(key: key(), shapes: nil, visits: visits, visitedCodes: Set(codes.map { $0.uppercased() }))
        geometries = await CountryShapeStore.shared.geometries(for: requests).shapes
        guard !geometries.isEmpty, !Task.isCancelled else { return }
        let shapes = CountryShapesOverlay(geometries: geometries, stats: snapshot.countryStats,
                                          style: CountryShapeStyle(fill: true, outlines: true, hatching: false, mode: .visited, dark: scheme == .dark))
        texture = await GlobeTextureBuilder.shared.texture(key: key(), shapes: shapes, visits: visits, visitedCodes: Set(codes.map { $0.uppercased() }))
    }
}

/// "When?" — any time, or a month and year, picked on the standard iOS scroll wheels.
struct WhenMenu: View {
    @Binding var date: Date?
    var title: String = "When did you go?"
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            Label(date.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "When?", systemImage: "calendar")
                .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.ink)
                .padding(.horizontal, 10).frame(minHeight: 34).background(Capsule().fill(Sketch.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.map { "Visited \($0.formatted(.dateTime.month(.wide).year()))" } ?? "When did you go?")
        .sheet(isPresented: $open) { WhenPickerSheet(title: title, date: $date) }
    }

    /// The date stored for "this month": the 1st at noon (noon keeps it on the same day in every time zone).
    static func month(_ month: Int, _ year: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
    }
    @ViewBuilder static func items(date: Binding<Date?>) -> some View {
        Button("Any time", systemImage: date.wrappedValue == nil ? "checkmark" : "") { date.wrappedValue = nil }
        let year = Calendar.current.component(.year, from: .now)
        ForEach(Array(stride(from: year, through: year - 30, by: -1)), id: \.self) { y in
            Menu(String(y)) {
                ForEach(1...12, id: \.self) { m in
                    Button(Calendar.current.monthSymbols[m - 1]) {
                        date.wrappedValue = Calendar.current.date(from: DateComponents(year: y, month: m, day: 1, hour: 12))
                    }
                }
            }
        }
    }
}


/// Month and year on two scroll wheels, "Any time" to clear, and a tick to confirm and close.
/// `extra` adds controls under the wheels (for example "Same date for the cities you added", or Remove).
struct WhenPickerSheet<Extra: View>: View {
    let title: String
    @Binding var date: Date?
    var onConfirm: (Date?) -> Void = { _ in }
    @ViewBuilder var extra: () -> Extra
    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var anyTime = false
    private let thisYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                Spacer()
                Button { confirm() } label: {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Sketch.paper)
                        .frame(width: 40, height: 40).background(Circle().fill(Sketch.ink))
                }
                .accessibilityLabel("Done")
            }
            Toggle("Any time", isOn: $anyTime.animation(.snappy)).font(Sketch.text(15, "SemiBold", relativeTo: .body)).tint(Sketch.sage)
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { Text(Calendar.current.standaloneMonthSymbols[$0 - 1]).tag($0) }
                }
                Picker("Year", selection: $year) {
                    ForEach(Array(stride(from: thisYear, through: thisYear - 80, by: -1)), id: \.self) { Text(String($0)).tag($0) }
                }
                .frame(maxWidth: 130)
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .disabled(anyTime).opacity(anyTime ? 0.35 : 1)
            extra()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
        .presentationDetents([.height(Extra.self == EmptyView.self ? 330 : 400)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Sketch.paper)
        .onAppear {
            if let date {
                month = Calendar.current.component(.month, from: date); year = Calendar.current.component(.year, from: date)
            } else { anyTime = false }
        }
        .onChange(of: month) { _, _ in date = value }
        .onChange(of: year) { _, _ in date = value }
        .onChange(of: anyTime) { _, _ in date = value }
    }

    private var value: Date? { anyTime ? nil : WhenMenu.month(month, year) }
    private func confirm() { TrippyHaptics.selection(); date = value; onConfirm(value); dismiss() }
}

extension WhenPickerSheet where Extra == EmptyView {
    init(title: String, date: Binding<Date?>, onConfirm: @escaping (Date?) -> Void = { _ in }) {
        self.init(title: title, date: date, onConfirm: onConfirm, extra: { EmptyView() })
    }
}


// MARK: - Account or just this phone

/// The one real choice in onboarding. Both paths get the same setup afterwards; an account adds
/// what costs us to run (plans, reading videos) with free monthly credits.
struct AccessStep: View {
    let onContinue: () -> Void
    var offerLocal = true
    @ObservedObject private var account = AccountSession.shared
    @Environment(\.webAuthenticationSession) private var webAuthentication
    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var showEmail = false
    @State private var showPerks = false
    @State private var working = false
    @State private var error: String?
    @State private var nonce = AccountSession.makeNonce()
    @FocusState private var field: Field?
    private enum Field { case email, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if account.isSignedIn { signedIn } else { choose }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(working)
        .overlay { if working { ProgressView().controlSize(.large) } }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Sketch.sage)
                .symbolEffect(.bounce, value: account.isSignedIn)
            Text("You’re in").font(Sketch.display(.largeTitle, weight: .bold))
            Text(account.email ?? "Signed in").font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
            if let credits = account.credits { CreditsStrip(credits: credits) }
            primary("Continue", action: onContinue).padding(.top, 6)
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                Text(offerLocal ? "Make it yours." : "Sign in").font(Sketch.display(.largeTitle, weight: .bold))
                HStack(spacing: 6) {
                    Text("Plans, video reading and free credits.").font(Sketch.text(17, "Medium", relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                    Button { showPerks = true } label: { Image(systemName: "info.circle").foregroundStyle(Sketch.inkFaint) }
                        .accessibilityLabel("What an account includes")
                }
            }
            VStack(spacing: 10) {
                providerButton("Continue with Google", image: "GoogleSearchGlyph", system: nil, dark: true) { Task { await google() } }
                if AccountFeatures.appleSignIn {
                    providerButton("Continue with Apple", image: nil, system: "apple.logo", dark: true) { }
                        .overlay { appleOverlay }
                }
                if showEmail { emailForm } else {
                    providerButton("Continue with email", image: nil, system: "envelope", dark: false) {
                        withAnimation(.snappy) { showEmail = true }; field = .email
                    }
                }
            }
            if offerLocal {
                VStack(spacing: 4) {
                    Button("Continue without an account", action: onContinue)
                        .font(Sketch.text(16, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink).frame(minHeight: 44)
                    Text("Map, saves and places work on this phone.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 24)
        .sheet(isPresented: $showPerks) { perksSheet }
    }

    /// The details, one tap away instead of on the page.
    private var perksSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("With an account").font(Sketch.display(.title2, weight: .bold))
            perk("sparkles", "Plans made for you, and TikToks read into places")
            perk("gift", "Free credits every month")
            perk("iphone.and.arrow.forward", "Your account on a new phone")
            perk("link", "Google and email with the same address are one account")
            Divider().overlay(Sketch.rule)
            perk("iphone", "Without one, your map, saves and places still work on this phone")
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Sketch.paper)
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true) }
            icon: { Image(systemName: symbol).foregroundStyle(Sketch.coral).frame(width: 22) }
    }

    private func providerButton(_ title: String, image: String?, system: String?, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let image { Image(image).resizable().scaledToFit().frame(width: 18, height: 18) }
                if let system { Image(systemName: system).font(.system(size: 16, weight: .semibold)) }
                Text(title).font(Sketch.text(16, "Bold", relativeTo: .body))
            }
            .foregroundStyle(dark ? Sketch.paper : Sketch.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(dark ? Sketch.ink : Sketch.card))
            .overlay(Capsule().strokeBorder(dark ? .clear : Sketch.ink.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(SketchPressStyle())
    }

    /// Apple's own button, invisible over ours, so the system sheet and its rules apply.
    private var appleOverlay: some View {
        SignInWithAppleButton(.continue) { request in
            nonce = AccountSession.makeNonce()
            request.requestedScopes = [.email]
            request.nonce = AccountSession.sha256(nonce)
        } onCompletion: { result in Task { await apple(result) } }
        .opacity(0.02)
    }

    @ViewBuilder private var emailForm: some View {
        VStack(spacing: 10) {
            if let address = sentTo {
                Text("Enter the 6-digit code we sent to \(address).").font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                TextField("123456", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).focused($field, equals: .code)
                    .font(Sketch.text(26, "Bold", relativeTo: .title2)).multilineTextAlignment(.center).monospacedDigit()
                    .frame(minHeight: 54).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.paper))
                    .onChange(of: code) { _, value in if value.filter(\.isNumber).count == 6 { Task { await verify() } } }
                Button("Use another email") { sentTo = nil; code = "" }.font(Sketch.text(14, "SemiBold", relativeTo: .footnote)).frame(minHeight: 44)
            } else {
                TextField("you@example.com", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($field, equals: .email).submitLabel(.send)
                    .onSubmit { Task { await sendCode() } }
                    .font(Sketch.text(17, relativeTo: .body)).padding(.horizontal, 16).frame(minHeight: 50)
                    .background(Capsule().fill(Sketch.paper)).overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 1))
                primary("Send me a code") { Task { await sendCode() } }
                    .disabled(!email.contains("@")).opacity(email.contains("@") ? 1 : 0.45)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Sketch.ink))
        }
        .buttonStyle(SketchPressStyle())
    }

    private func run(_ work: () async throws -> Void) async {
        working = true; defer { working = false }
        do { try await work(); error = nil } catch { self.error = error.localizedDescription }
    }
    private func sendCode() async {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@") else { return }
        await run { try await account.sendEmailCode(address); sentTo = address; field = .code }
    }
    private func verify() async {
        guard let sentTo else { return }
        await run { try await account.verifyEmail(sentTo, code: String(code.filter(\.isNumber).prefix(6))) }
        if !account.isSignedIn { code = "" }
    }
    private func google() async {
        working = true; defer { working = false }
        do { try await account.signInWithGoogle(using: webAuthentication); error = nil }
        catch let failure as AccountSession.AccountError where failure.code == "cancelled" { error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func apple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            // Closing the Apple sheet is not an error.
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else { error = "Apple didn’t return a sign-in token."; return }
            await run { try await account.signInWithApple(idToken: token, nonce: nonce) }
        }
    }
}

/// Settings uses the same sign-in, without the "just this phone" option.
struct AccountStep: View {
    let onDone: () -> Void
    @ObservedObject private var account = AccountSession.shared
    var body: some View {
        AccessStep(onContinue: onDone, offerLocal: false)
            .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { onDone() } }
    }
}

/// What an account has left this month: the frame later subscriptions build on.
struct CreditsStrip: View {
    let credits: AccountSession.Credits
    var body: some View {
        HStack(spacing: 10) {
            ForEach(credits.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.unlimited ? "∞" : "\(max(0, item.limit - item.used))").font(Sketch.display(.title2, weight: .bold)).monospacedDigit()
                    Text(item.label).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    if !item.unlimited {
                        ProgressView(value: Double(min(item.used, item.limit)), total: Double(max(item.limit, 1))).tint(Sketch.sage)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
            }
        }
        .accessibilityElement(children: .combine)
    }
}


/// Sign in with Apple needs a paid Apple Developer Program team (a Personal Team can't sign
/// that capability). Turn this on, and add the "Sign in with Apple" capability in Xcode, after joining.
enum AccountFeatures {
    static let appleSignIn = false
}

// MARK: - Bubbles

/// A rounded, springy choice; selected ones fill with their colour.
struct Bubble: View {
    let text: String
    let tint: Color
    let selected: Bool
    var symbol: String? = nil
    var popping = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                Text(text).font(Sketch.text(15, "SemiBold", relativeTo: .subheadline)).lineLimit(1)
                if selected && symbol == nil { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)) }
            }
            .foregroundStyle(selected ? .white : Sketch.ink)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(Capsule().fill(selected ? tint : Sketch.card))
            .overlay(Capsule().strokeBorder(selected ? .clear : tint.opacity(0.35), lineWidth: 1))
            .shadow(color: selected ? tint.opacity(0.35) : .clear, radius: 8, y: 4)
            .scaleEffect(popping ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Home pin and the "you're here" greeting

/// Where the traveller lives, on the general map.
struct HomePin: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "house.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Sketch.sage))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8)).foregroundStyle(Sketch.sage).offset(y: -2)
        }
        .accessibilityLabel("Home")
    }
}

struct TripGreeting: Equatable {
    let city: String
    let day: Int
    let total: Int
    var hello: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(part) from \(city)"
    }
    var detail: String { total > 1 ? "Day \(min(day, total)) of \(total) · your plan is on the map" : "Your plan is on the map" }
}

/// A warm hello when the app opens during a trip; it drifts away on its own.
struct TripGreetingBanner: View {
    let greeting: TripGreeting
    let onDone: () -> Void
    @State private var waved = false
    var body: some View {
        HStack(spacing: 12) {
            Text("👋").font(.system(size: 26)).rotationEffect(.degrees(waved ? 14 : -10), anchor: .bottomTrailing)
                .animation(.easeInOut(duration: 0.35).repeatCount(5, autoreverses: true), value: waved)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting.hello).font(Sketch.display(.headline, weight: .bold)).foregroundStyle(Sketch.ink)
                Text(greeting.detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .task {
            waved = true
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeInOut(duration: 0.4)) { onDone() }
        }
    }
}

extension GuideDates {
    static func parse(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let x = date(a), let y = date(b) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: x, to: y).day
    }
}
