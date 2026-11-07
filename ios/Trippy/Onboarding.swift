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
        return points.compactMap { p in
            guard let name = p["n"] as? String, let country = (p["c"] as? String)?.lowercased(),
                  let lat = (p["lat"] as? NSNumber)?.doubleValue, let lon = (p["lon"] as? NSNumber)?.doubleValue,
                  let code = aliases[country] ?? byName[country] else { return nil }
            return CityEntry(name: name, countryCode: code, latitude: lat, longitude: lon)
        }
    }()

    static func cities(in code: String) -> [CityEntry] { cities.filter { $0.countryCode == code } }
    static func country(_ code: String?) -> CountryEntry? { countries.first { $0.code == code } }
    static var deviceCountry: String? { Locale.current.region?.identifier }
}

// MARK: - Flow

struct OnboardingFlow: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // DEBUG `-TrippyOnboardingStep N` opens a step directly for screenshots.
    @State private var step = UserDefaults.standard.integer(forKey: "TrippyOnboardingStep")
    @State private var home = HomeProfileStore.load() ?? HomeProfile()
    @AppStorage("trippy.native.visitedPlaces.v1") private var visitedStorage = "[]"

    /// welcome, three cards, home, been, account
    private let steps = 7
    private var isCard: Bool { (1...3).contains(step) }

    var body: some View {
        ZStack {
            OnboardingBackdrop(step: step)
            VStack(spacing: 0) {
                topBar
                Group {
                    switch step {
                    case 0: WelcomeStep(next: next, signIn: { go(6) })
                    case 1, 2, 3: FeatureCardStep(card: FeatureCard.all[step - 1]).id(step)
                    case 4: HomeStep(home: $home)
                    case 5: BeenStep(home: home, storage: $visitedStorage)
                    default: AccountStep(onDone: finish)
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if step > 0 && step < 6 { bottomBar }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard isCard else { return }
            if value.translation.width < -60 { next() } else if value.translation.width > 60 { back() }
        })
    }

    private var topBar: some View {
        HStack {
            if step > 0 {
                Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Back")
            } else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            if step > 0 {
                HStack(spacing: 6) {
                    ForEach(1..<steps, id: \.self) { i in
                        Capsule().fill(i <= step ? Sketch.ink : Sketch.ink.opacity(0.15)).frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: step)
                .accessibilityElement().accessibilityLabel("Step \(step) of \(steps - 1)")
            }
            Spacer()
            if isCard {
                Button("Skip") { go(4) }.font(Sketch.text(15, "SemiBold", relativeTo: .body)).frame(minWidth: 44, minHeight: 44)
            } else { Color.clear.frame(width: 44, height: 44) }
        }
        .foregroundStyle(Sketch.ink)
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        let label: String = switch step {
        case 3: "Set up my map"
        case 4: home.isEmpty ? "Skip for now" : "Continue"
        case 5: "Continue"
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
        if step == 4 { HomeProfileStore.save(home) }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) { step = target }
    }
    private func next() { go(min(step + 1, steps - 1)) }
    private func back() { go(max(step - 1, 0)) }
    private func finish() {
        HomeProfileStore.save(home)
        OnboardingStore.finish()
        onFinish()
    }
}

/// Paper with slow-drifting watercolour blobs that change hue per step.
private struct OnboardingBackdrop: View {
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Circle().fill(tints[0].opacity(0.22)).frame(width: 420).blur(radius: 70)
                    .offset(x: -120 + 30 * sin(t / 5), y: -260 + 20 * cos(t / 6))
                Circle().fill(tints[1].opacity(0.18)).frame(width: 380).blur(radius: 80)
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
                Image("BrandWordmark").resizable().scaledToFit().frame(height: 34).accessibilityLabel("Trippy")
                    .colorMultiply(Sketch.ink)
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
            let key = GlobeTextureKey(dark: scheme == .dark, satellite: false, style: "onboarding")
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

// MARK: - Feature cards

/// A card shows a real screen of the app (re-shot by scripts/render_onboarding_shots.sh)
/// with hand-drawn marks animating on top, at positions given as fractions of the screen.
struct FeatureCard: Hashable {
    enum Mark: Hashable {
        case circle(CGRect)                  // ring around a part of the screen
        case arrow(from: CGPoint, to: CGPoint)
        case underline(CGRect)
        case route([CGPoint])
        case sparkle(CGPoint)
    }
    let image: String
    let eyebrow: String
    let title: String
    let body: String
    let tint: Color
    let marks: [Mark]
    let note: String?
    let notePoint: CGPoint

    // Positions are fractions of the screenshot; re-check them after re-shooting (scripts/render_onboarding_shots.sh).
    static let all: [FeatureCard] = [
        FeatureCard(image: "OnboardingVideos", eyebrow: "SAVE FROM TIKTOK", title: "Share a video, get the places",
                    body: "Send any travel TikTok to Trippy. It reads the caption, the text on screen and the voice, and pins every café, bar and sight.",
                    tint: Sketch.coral,
                    marks: [.circle(.init(x: 0.03, y: 0.285, width: 0.94, height: 0.15)),
                            .arrow(from: .init(x: 0.74, y: 0.62), to: .init(x: 0.56, y: 0.78)),
                            .sparkle(.init(x: 0.13, y: 0.30))],
                    note: "8 places from 6 videos", notePoint: .init(x: 0.66, y: 0.58)),
        FeatureCard(image: "OnboardingPlan", eyebrow: "PLANS THAT FIT", title: "A plan that actually works",
                    body: "Days grouped by area, starting where you stay, with lunch and drinks close by. Every stop is a choice you can swap.",
                    tint: Sketch.sky,
                    marks: [.underline(.init(x: 0.07, y: 0.452, width: 0.66, height: 0.01)),
                            .route([.init(x: 0.36, y: 0.585), .init(x: 0.46, y: 0.56), .init(x: 0.53, y: 0.55), .init(x: 0.62, y: 0.585)]),
                            .circle(.init(x: 0.12, y: 0.89, width: 0.6, height: 0.07))],
                    note: "one visit, not three", notePoint: .init(x: 0.62, y: 0.68)),
        FeatureCard(image: "OnboardingBeen", eyebrow: "YOUR WORLD", title: "Every place you’ve been",
                    body: "Tap the countries and cities you know. Your map fills in colour, and Trippy shows what’s left to see.",
                    tint: Sketch.sage,
                    marks: [.circle(.init(x: 0.18, y: 0.32, width: 0.56, height: 0.24)), .sparkle(.init(x: 0.76, y: 0.33)), .sparkle(.init(x: 0.2, y: 0.58))],
                    note: "yours, in colour", notePoint: .init(x: 0.68, y: 0.62)),
    ]
}

private struct FeatureCardStep: View {
    let card: FeatureCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var draw: CGFloat = 0

    var body: some View {
        VStack(spacing: 18) {
            GeometryReader { proxy in
                let aspect = UIImage(named: card.image).map { $0.size.height / max($0.size.width, 1) } ?? 2.17
                let height = proxy.size.height, width = min(proxy.size.width - 64, height / aspect)
                ZStack {
                    phone(width: width, height: width * aspect)
                        .rotation3DEffect(.degrees(appear ? -6 : -24), axis: (x: 0.2, y: 1, z: 0), perspective: 0.6)
                        .scaleEffect(appear ? 1 : 0.9)
                        .offset(y: appear ? 0 : 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 8) {
                Text(card.eyebrow).font(Sketch.eyebrow).tracking(1.4).foregroundStyle(card.tint)
                Text(card.title).font(Sketch.display(.title, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(Sketch.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body).font(Sketch.text(16, relativeTo: .body)).multilineTextAlignment(.center).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .opacity(appear ? 1 : 0)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .padding(.bottom, 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8)) { appear = true }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4).delay(0.45)) { draw = 1 }
            if reduceMotion { appear = true; draw = 1 }
        }
        .accessibilityElement(children: .combine)
    }

    private func phone(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Group {
                if UIImage(named: card.image) != nil {
                    Image(card.image).resizable().scaledToFit()
                } else {
                    LinearGradient(colors: [card.tint.opacity(0.3), Sketch.paperDeep], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: width * 0.13, style: .continuous).strokeBorder(Sketch.ink.opacity(0.9), lineWidth: 5))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 18)
            .accessibilityHidden(true)
            // Hand-drawn marks on top of the real screen.
            ForEach(Array(card.marks.enumerated()), id: \.offset) { index, mark in
                SketchMarkShape(mark: mark).trim(from: 0, to: max(0, min(1, draw * 1.3 - CGFloat(index) * 0.15)))
                    .stroke(card.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height)
            }
            if let note = card.note {
                Text(note).font(Sketch.hand(.headline)).foregroundStyle(card.tint).lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.large)   // a drawing on the screenshot, not reading text
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.12), radius: 6, y: 3))
                    .rotationEffect(.degrees(-4))
                    .position(x: card.notePoint.x * width, y: card.notePoint.y * height)
                    .frame(width: width, height: height)
                    .opacity(draw > 0.6 ? 1 : 0).scaleEffect(draw > 0.6 ? 1 : 0.7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: draw > 0.6)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
    }
}

/// The hand-drawn marks: slightly wobbly, like a pen over a screenshot.
private struct SketchMarkShape: Shape {
    let mark: FeatureCard.Mark
    func path(in rect: CGRect) -> Path {
        func p(_ u: CGPoint) -> CGPoint { .init(x: rect.minX + u.x * rect.width, y: rect.minY + u.y * rect.height) }
        var path = Path()
        switch mark {
        case .circle(let r):
            // An ellipse drawn in one stroke that overshoots its start, as by hand.
            let c = CGPoint(x: r.midX, y: r.midY), rx = r.width / 2, ry = r.height / 2
            for i in 0...64 {
                let a = Double(i) / 64 * 2.15 * .pi - 0.4
                let wobble = 1 + 0.035 * sin(a * 3)
                let point = p(.init(x: c.x + rx * wobble * cos(a), y: c.y + ry * wobble * sin(a)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        case .arrow(let from, let to):
            let a = p(from), b = p(to)
            let control = CGPoint(x: (a.x + b.x) / 2 + (b.y - a.y) * 0.3, y: (a.y + b.y) / 2 - (b.x - a.x) * 0.3)
            path.move(to: a); path.addQuadCurve(to: b, control: control)
            let angle = atan2(b.y - control.y, b.x - control.x)
            for side in [-1.0, 1.0] {
                path.move(to: b)
                path.addLine(to: CGPoint(x: b.x - 14 * cos(angle + side * 0.5), y: b.y - 14 * sin(angle + side * 0.5)))
            }
        case .underline(let r):
            let a = p(.init(x: r.minX, y: r.midY)), b = p(.init(x: r.maxX, y: r.midY))
            path.move(to: a)
            path.addCurve(to: b, control1: .init(x: a.x + (b.x - a.x) / 3, y: a.y + 5), control2: .init(x: a.x + 2 * (b.x - a.x) / 3, y: a.y - 4))
        case .route(let points):
            guard let first = points.first else { break }
            path.move(to: p(first))
            for (i, point) in points.dropFirst().enumerated() {
                let previous = p(points[i]), next = p(point)
                path.addQuadCurve(to: next, control: .init(x: (previous.x + next.x) / 2, y: min(previous.y, next.y) - 18))
            }
        case .sparkle(let u):
            let c = p(u)
            for angle in stride(from: 0.0, to: .pi * 2, by: .pi / 3) {
                path.move(to: .init(x: c.x + 5 * cos(angle), y: c.y + 5 * sin(angle)))
                path.addLine(to: .init(x: c.x + 13 * cos(angle), y: c.y + 13 * sin(angle)))
            }
        }
        return path
    }
}

// MARK: - Where you live

struct HomeStep: View {
    @Binding var home: HomeProfile
    @State private var query = ""
    @StateObject private var search = LocalSearch()
    @FocusState private var focused: Bool

    private enum Level { case country, city, area }
    private var level: Level { home.countryCode == nil ? .country : home.city == nil ? .city : .area }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where do you live?").font(Sketch.display(.largeTitle, weight: .bold)).foregroundStyle(Sketch.ink)
                    Text("Only as much as you like. Your map opens there and your home is marked. You can change it any time.")
                        .font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                chosen
                if level != .area || home.area == nil { picker }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, value in search.update(value, level: level == .area ? .area : .city, around: home.coordinate) }
    }

    /// The chosen country / city / area as removable bubbles, most general first.
    private var chosen: some View {
        FlowLayout(spacing: 8) {
            if let code = home.countryCode {
                Bubble(text: "\(WorldGlobeView.flag(code)) \(home.countryName ?? code)", tint: Sketch.coral, selected: true) {
                    withAnimation(.snappy) { home = HomeProfile() }
                }
            }
            if let city = home.city {
                Bubble(text: city, tint: Sketch.sky, selected: true, symbol: "building.2") {
                    withAnimation(.snappy) { home.city = nil; home.cityLatitude = nil; home.cityLongitude = nil; home.area = nil; home.areaLatitude = nil; home.areaLongitude = nil }
                }
            }
            if let area = home.area {
                Bubble(text: area, tint: Sketch.sage, selected: true, symbol: "house") {
                    withAnimation(.snappy) { home.area = nil; home.areaLatitude = nil; home.areaLongitude = nil }
                }
            }
        }
    }

    @ViewBuilder private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(level == .country ? "COUNTRY" : level == .city ? "CITY · OPTIONAL" : "AREA · OPTIONAL")
                .font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField(level == .country ? "Search countries" : level == .city ? "Search cities" : "Neighbourhood, e.g. Koukaki", text: $query)
                    .font(Sketch.text(16, relativeTo: .body)).focused($focused).autocorrectionDisabled().submitLabel(.done)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Sketch.inkFaint) }.accessibilityLabel("Clear") }
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Sketch.ink : Sketch.rule, lineWidth: focused ? 1.5 : 0.7))
            FlowLayout(spacing: 8) {
                switch level {
                case .country:
                    ForEach(countryOptions) { country in
                        Bubble(text: "\(country.flag) \(country.name)", tint: Sketch.coral, selected: false) { pick(country) }
                    }
                case .city:
                    ForEach(cityOptions) { city in
                        Bubble(text: city.name, tint: Sketch.sky, selected: false, symbol: "building.2") { pick(city) }
                    }
                    ForEach(search.results.prefix(6)) { result in
                        Bubble(text: result.title, tint: Sketch.sky, selected: false, symbol: "magnifyingglass") { Task { await pickCity(result) } }
                    }
                case .area:
                    ForEach(search.results.prefix(8)) { result in
                        Bubble(text: result.title, tint: Sketch.sage, selected: false, symbol: "house") { Task { await pickArea(result) } }
                    }
                }
            }
            if search.loading { ProgressView().padding(.top, 4) }
            if level == .area && query.isEmpty {
                Text("Type your neighbourhood for a home pin on the map, or leave it at the city.")
                    .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkFaint)
            }
        }
        .animation(.snappy, value: level == .country)
    }

    private var countryOptions: [CountryEntry] {
        let all = PlaceCatalog.countries
        if query.isEmpty {
            // The phone's own region first, then well-travelled countries.
            let device = PlaceCatalog.deviceCountry.flatMap(PlaceCatalog.country)
            let popular = ["GR", "IT", "ES", "FR", "GB", "DE", "US", "PT", "NL", "CY"].compactMap(PlaceCatalog.country)
            return ([device].compactMap { $0 } + popular).reduce(into: [CountryEntry]()) { if !$0.contains($1) { $0.append($1) } }
        }
        return Array(all.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(12))
    }
    private var cityOptions: [CityEntry] {
        guard let code = home.countryCode else { return [] }
        let cities = PlaceCatalog.cities(in: code)
        return Array((query.isEmpty ? cities : cities.filter { $0.name.localizedCaseInsensitiveContains(query) }).prefix(10))
    }

    private func pick(_ country: CountryEntry) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            home = HomeProfile(countryCode: country.code, countryLatitude: country.latitude, countryLongitude: country.longitude)
            query = ""
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private func pick(_ city: CityEntry) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            home.city = city.name; home.cityLatitude = city.latitude; home.cityLongitude = city.longitude; query = ""
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private func pickCity(_ result: LocalSearch.Result) async {
        guard let place = await search.resolve(result) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            home.city = place.name; home.cityLatitude = place.latitude; home.cityLongitude = place.longitude; query = ""
        }
    }
    private func pickArea(_ result: LocalSearch.Result) async {
        guard let place = await search.resolve(result) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            home.area = place.name; home.areaLatitude = place.latitude; home.areaLongitude = place.longitude; query = ""
        }
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

private struct BeenStep: View {
    let home: HomeProfile
    @Binding var storage: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var continent = "Europe"
    @State private var query = ""
    @State private var focus: CLLocationCoordinate2D?
    @State private var focusID = UUID()
    @State private var texture: UIImage?
    @State private var lived: [CityEntry] = []
    @State private var pop: String?
    @State private var cityQuery = ""

    private var visits: [VisitedPlace] { VisitedPlace.decode(storage) }
    private var visitedCodes: Set<String> { Set(visits.compactMap { $0.countryCode?.uppercased() }) }
    private let continents = ["Europe", "Asia", "North America", "South America", "Africa", "Oceania"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    BeenGlobe3DView(texture: texture, focus: focus ?? home.coordinate ?? .init(latitude: 46, longitude: 14), focusID: focusID,
                                    dark: scheme == .dark, reduceMotion: reduceMotion)
                        .frame(width: 118, height: 118).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Where have you been?").font(Sketch.display(.title, weight: .bold)).foregroundStyle(Sketch.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(visitedCodes.isEmpty ? "Tap what you know. Skip if you like." : "\(visitedCodes.count) \(visitedCodes.count == 1 ? "country" : "countries") · \(Int((Double(visitedCodes.count) / 195 * 100).rounded()))% of the world")
                            .font(Sketch.text(15, "SemiBold", relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                            .contentTransition(.numericText())
                    }
                }
                livedSection
                Divider().overlay(Sketch.rule)
                countriesSection
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .task(id: visitedCodes.count) {
            let key = GlobeTextureKey(dark: scheme == .dark, satellite: false, style: "onboarding-been-\(visits.count)")
            texture = await GlobeTextureBuilder.shared.texture(key: key, shapes: nil, visits: visits)
        }
    }

    /// "Where have you lived?" — cities, which also count as been.
    private var livedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CITIES YOU’VE LIVED IN").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField("Add a city", text: $cityQuery).font(Sketch.text(16, relativeTo: .body)).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.card))
            FlowLayout(spacing: 8) {
                ForEach(livedSuggestions) { city in
                    let chosen = lived.contains(city)
                    Bubble(text: city.name, tint: Sketch.plum, selected: chosen, symbol: chosen ? "checkmark" : "house") { toggle(lived: city) }
                }
            }
        }
    }

    private var livedSuggestions: [CityEntry] {
        // Matches for what's typed; otherwise the home country's cities, then the chosen ones.
        let query = cityQuery.trimmingCharacters(in: .whitespaces)
        let base = query.count >= 2 ? PlaceCatalog.cities.filter { $0.name.localizedCaseInsensitiveContains(query) }
            : home.countryCode.map(PlaceCatalog.cities(in:)) ?? []
        return (lived + base).reduce(into: [CityEntry]()) { if !$0.contains($1) { $0.append($1) } }.prefix(12).map { $0 }
    }

    private var countriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COUNTRIES").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(continents, id: \.self) { name in
                        let count = PlaceCatalog.countries.filter { $0.continent == name && visitedCodes.contains($0.code) }.count
                        Button { withAnimation(.snappy) { continent = name } } label: {
                            Text(count > 0 ? "\(name) · \(count)" : name).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                                .foregroundStyle(continent == name ? Sketch.paper : Sketch.ink)
                                .padding(.horizontal, 14).frame(minHeight: 38)
                                .background(Capsule().fill(continent == name ? Sketch.ink : Sketch.card))
                                .overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: continent == name ? 0 : 0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField("Find a country", text: $query).font(Sketch.text(16, relativeTo: .body)).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.card))
            FlowLayout(spacing: 8) {
                ForEach(countryList) { country in
                    let chosen = visitedCodes.contains(country.code)
                    Bubble(text: "\(country.flag) \(country.name)", tint: WorldContinentCatalog.colors[country.continent] ?? Sketch.sky,
                           selected: chosen, popping: pop == country.code) { toggle(country) }
                }
            }
        }
    }

    private var countryList: [CountryEntry] {
        let list = PlaceCatalog.countries
        if !query.isEmpty { return list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        return list.filter { $0.continent == continent }
    }

    private func toggle(_ country: CountryEntry) {
        var records = visits
        if visitedCodes.contains(country.code) {
            records.removeAll { $0.countryCode?.uppercased() == country.code && $0.name == country.name }
        } else {
            guard let lat = country.latitude, let lon = country.longitude else {
                Task { await addByGeocoding(country) }; return
            }
            records = VisitedPlace.adding(VisitedPlace(name: country.name, countryCode: country.code, latitude: lat, longitude: lon), to: records)
            focus = .init(latitude: lat, longitude: lon); focusID = UUID()
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { storage = VisitedPlace.encode(records); pop = country.code }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { try? await Task.sleep(for: .milliseconds(350)); pop = nil }
    }

    private func addByGeocoding(_ country: CountryEntry) async {
        guard let found = try? await CLGeocoder().geocodeAddressString(country.name).first?.location?.coordinate else { return }
        var records = visits
        records = VisitedPlace.adding(VisitedPlace(name: country.name, countryCode: country.code, latitude: found.latitude, longitude: found.longitude), to: records)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { storage = VisitedPlace.encode(records) }
        focus = found; focusID = UUID()
    }

    private func toggle(lived city: CityEntry) {
        var records = visits
        if let index = lived.firstIndex(of: city) {
            lived.remove(at: index)
            records.removeAll { $0.name == city.name && $0.countryCode?.uppercased() == city.countryCode }
        } else {
            lived.append(city)
            records = VisitedPlace.adding(VisitedPlace(name: city.name, countryCode: city.countryCode, latitude: city.latitude, longitude: city.longitude), to: records)
            focus = .init(latitude: city.latitude, longitude: city.longitude); focusID = UUID()
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { storage = VisitedPlace.encode(records) }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Account

struct AccountStep: View {
    let onDone: () -> Void
    @ObservedObject private var account = AccountSession.shared
    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var working = false
    @State private var error: String?
    @State private var nonce = AccountSession.makeNonce()
    @FocusState private var field: Field?
    private enum Field { case email, code }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: account.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.plus")
                    .font(.system(size: 54, weight: .semibold)).foregroundStyle(account.isSignedIn ? Sketch.sage : Sketch.ink)
                    .symbolEffect(.bounce, value: account.isSignedIn)
                    .padding(.top, 20)
                Text(account.isSignedIn ? "You’re in" : "Keep your trips safe").font(Sketch.display(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(account.isSignedIn ? (account.email ?? "Signed in") : "An account backs up your trips and saves and lets you use Trippy on a new phone. Everything works without one.")
                    .font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if account.isSignedIn {
                    primary("Start exploring", action: onDone).padding(.top, 8)
                } else {
                    SignInWithAppleButton(.continue) { request in
                        nonce = AccountSession.makeNonce()
                        request.requestedScopes = [.email]
                        request.nonce = AccountSession.sha256(nonce)
                    } onCompletion: { result in
                        Task { await apple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52).clipShape(Capsule())
                    emailForm
                    Button("Not now", action: onDone).font(Sketch.text(16, "SemiBold", relativeTo: .body))
                        .foregroundStyle(Sketch.inkSoft).frame(minHeight: 44)
                }
                if let error { Text(error).font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.coral).multilineTextAlignment(.center) }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(working)
        .overlay { if working { ProgressView().controlSize(.large) } }
    }

    @ViewBuilder private var emailForm: some View {
        VStack(spacing: 10) {
            if let address = sentTo {
                Text("We sent a 6-digit code to \(address).").font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                TextField("123456", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).focused($field, equals: .code)
                    .font(Sketch.text(24, "Bold", relativeTo: .title2)).multilineTextAlignment(.center).monospacedDigit()
                    .frame(minHeight: 54).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
                    .onChange(of: code) { _, value in if value.filter(\.isNumber).count == 6 { Task { await verify() } } }
                Button("Use another email") { sentTo = nil; code = "" }.font(Sketch.text(14, "SemiBold", relativeTo: .footnote)).frame(minHeight: 44)
            } else {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($field, equals: .email).submitLabel(.send)
                    .onSubmit { Task { await sendCode() } }
                    .font(Sketch.text(17, relativeTo: .body)).padding(.horizontal, 16).frame(minHeight: 52)
                    .background(Capsule().fill(Sketch.card)).overlay(Capsule().strokeBorder(Sketch.rule, lineWidth: 0.7))
                primary("Continue with email") { Task { await sendCode() } }
                    .disabled(!email.contains("@"))
                    .opacity(email.contains("@") ? 1 : 0.5)
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Sketch.ink))
        }
        .buttonStyle(SketchPressStyle())
    }

    private func sendCode() async {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@") else { return }
        working = true; defer { working = false }
        do { try await account.sendEmailCode(address); sentTo = address; error = nil; field = .code }
        catch { self.error = error.localizedDescription }
    }
    private func verify() async {
        guard let sentTo else { return }
        working = true; defer { working = false }
        do { try await account.verifyEmail(sentTo, code: String(code.filter(\.isNumber).prefix(6))); error = nil }
        catch { self.error = error.localizedDescription; code = "" }
    }
    private func apple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            // Closing the Apple sheet is not an error.
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else { error = "Apple didn’t return a sign-in token."; return }
            working = true; defer { working = false }
            do { try await account.signInWithApple(idToken: token, nonce: nonce); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
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
