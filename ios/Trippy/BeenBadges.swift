import SwiftUI

// Badges for Been to, drawn as embroidered scout patches: a merrowed (overlocked) rim in the colour of the
// level you've reached, a stitched inner ring, a twill field with a simple scene, and the emblem on top.
// Everything is vector, so a patch is as sharp at 60 points in the grid as at 220 in its detail sheet.

// MARK: - Model

struct BeenBadge: Identifiable {
    enum Outline { case circle, shield, hexagon, diamond }
    enum Scene { case rays, peaks, waves, stripes, globe, stars, plain }
    let id: String
    let group: String
    let title: String
    /// What it is for, in one line.
    let blurb: String
    let outline: Outline
    let scene: Scene
    let field: UInt32
    let symbol: String
    /// What you need for each level, lowest first.
    let levels: [Int]
    let unit: String
    let value: Int

    var level: Int { levels.filter { value >= $0 }.count }
    var earned: Bool { level > 0 }
    var next: Int? { levels.first { value < $0 } }
    /// Progress towards the next level, from the previous one.
    var progress: Double {
        guard let next else { return 1 }
        let floor = levels.last { value >= $0 } ?? 0
        return max(0, min(1, Double(value - floor) / Double(max(1, next - floor))))
    }
    var levelName: String { level == 0 ? "Not yet" : levels.count == 1 ? "Earned" : Self.levelNames[min(level, Self.levelNames.count) - 1] }
    static let levelNames = ["Bronze", "Silver", "Gold", "Platinum", "Diamond"]
    /// Thread colour of the rim for each level; grey until earned.
    var thread: UInt32 { level == 0 ? 0x9A958C : [0xB8733E, 0xC3C9D1, 0xE9B93F, 0x8FD9D0, 0xC7AEF7][min(level, 5) - 1] }
}

enum BeenBadges {
    private static func set(_ codes: String) -> Set<String> { Set(codes.split(separator: " ").map(String.init)) }
    private static let balkans = set("GR BG AL MK RS ME BA HR SI RO XK TR")
    private static let nordics = set("DK SE NO FI IS")
    private static let mediterranean = set("ES FR IT GR TR HR MT CY MA TN EG IL LB ME AL SI MC DZ LY SY")
    private static let islands = set("IS IE GB MT CY JP PH ID LK MV MG MU SC NZ FJ CU JM DO BS BB TT SG TW BH CV KM HT WS TO VU SB PG")

    static func all(_ snapshot: BeenPassportSnapshot, stays: [StayRecord], photoCounts: [String: Int]) -> [BeenBadge] {
        let codes = Set(snapshot.countries.compactMap(\.countryCode))
        let cities = snapshot.cities
        func inContinent(_ names: String...) -> Int { snapshot.countries.filter { names.contains(WorldContinentCatalog.name(for: $0.countryCode)) }.count }
        let entries = BeenFacts.entries(snapshot, stays: stays)
        let trips = entries.filter { !$0.lived }
        let returns = Dictionary(grouping: trips.filter { !$0.place.isCountry }, by: \.place.id).values.map(\.count).max() ?? 0
        let hemispheres = [cities.contains { $0.latitude >= 0 }, cities.contains { $0.latitude < 0 }, cities.contains { $0.longitude >= 0 }, cities.contains { $0.longitude < 0 }].filter { $0 }.count
        let livedYears = snapshot.lived.compactMap { p in p.when.map { (p.end ?? $0).timeIntervalSince($0) / 31_557_600 } }.max() ?? 0
        let worldShare = Int(Double(codes.count) / 195 * 100)
        func badge(_ id: String, _ group: String, _ title: String, _ blurb: String, _ outline: BeenBadge.Outline, _ scene: BeenBadge.Scene,
                   _ field: UInt32, _ symbol: String, _ levels: [Int], _ unit: String, _ value: Int) -> BeenBadge {
            BeenBadge(id: id, group: group, title: title, blurb: blurb, outline: outline, scene: scene, field: field, symbol: symbol, levels: levels, unit: unit, value: value)
        }
        return [
            badge("first", "Explorer", "First Steps", "Add your first place.", .circle, .rays, 0x4A7560, "shoeprints.fill", [1], "place", snapshot.visits.count),
            badge("countries", "Explorer", "Border Hopper", "Countries you've set foot in.", .shield, .stripes, 0x2F4A6B, "flag.fill", [3, 10, 25, 50, 100], "countries", codes.count),
            badge("cities", "Explorer", "City Collector", "Different cities on your map.", .hexagon, .rays, 0xB5553A, "building.2.fill", [5, 15, 40, 80, 150], "cities", cities.count),
            badge("continents", "Explorer", "Continental", "Continents reached, out of six.", .circle, .globe, 0x2B7A78, "globe.europe.africa.fill", [2, 3, 4, 5, 6], "continents", snapshot.continents.count),
            badge("world", "Explorer", "World Share", "Per cent of the world's countries.", .diamond, .stars, 0x4B3F72, "chart.pie.fill", [5, 10, 25, 50], "%", worldShare),

            badge("europe", "Regions", "Grand Tour", "Countries in Europe.", .shield, .peaks, 0x3F6FA8, "building.columns.fill", [5, 12, 25, 44], "countries", inContinent("Europe")),
            badge("asia", "Regions", "Silk Road", "Countries in Asia.", .hexagon, .rays, 0xB8443A, "sun.max.fill", [3, 8, 20], "countries", inContinent("Asia")),
            badge("africa", "Regions", "Savannah", "Countries in Africa.", .circle, .rays, 0xC98A2B, "tree.fill", [2, 6, 15], "countries", inContinent("Africa")),
            badge("americas", "Regions", "New World", "Countries in the Americas.", .diamond, .peaks, 0x2E7D5B, "mountain.2.fill", [2, 6, 15], "countries", inContinent("North America", "South America")),
            badge("oceania", "Regions", "Southern Cross", "Countries in Oceania.", .circle, .stars, 0x23466E, "sparkles", [1, 3, 6], "countries", inContinent("Oceania")),
            badge("balkans", "Regions", "Balkan Trail", "Countries of the Balkans.", .shield, .peaks, 0x7A4B2A, "figure.hiking", [3, 6, 10], "countries", codes.intersection(balkans).count),
            badge("nordics", "Regions", "Nordic Lights", "The five Nordic countries.", .hexagon, .stars, 0x35557A, "snowflake", [2, 4, 5], "countries", codes.intersection(nordics).count),
            badge("med", "Regions", "Mediterranean", "Countries on the Mediterranean.", .circle, .waves, 0x1F7FA6, "sailboat.fill", [3, 7, 12], "countries", codes.intersection(mediterranean).count),
            badge("islands", "Regions", "Island Hopper", "Island nations.", .diamond, .waves, 0x1E8C82, "beach.umbrella.fill", [2, 5, 10], "islands", codes.intersection(islands).count),

            badge("north", "Feats", "True North", "How far north you've been, in degrees.", .hexagon, .peaks, 0x466A8C, "location.north.fill", [50, 60, 66], "°N", Int(cities.map(\.latitude).max() ?? 0)),
            badge("hemispheres", "Feats", "Line Crosser", "Hemispheres: north, south, east, west.", .circle, .globe, 0x8A3F6A, "safari.fill", [2, 3, 4], "hemispheres", hemispheres),
            badge("far", "Feats", "Long Hauler", "Thousands of km between your two farthest places.", .shield, .stars, 0x3A3F7A, "airplane", [2, 5, 10, 15], "thousand km", Int((snapshot.farthestPair?.2 ?? 0) / 1_000_000)),
            badge("regular", "Feats", "Regular", "Separate trips to the same place.", .circle, .stripes, 0xA8562F, "arrow.triangle.2.circlepath", [3, 5, 10], "trips", returns),
            badge("slow", "Feats", "Slow Traveller", "Your longest single trip, in days.", .diamond, .peaks, 0x5B7A3A, "tent.fill", [7, 14, 30], "days", trips.map(\.days).max() ?? 0),
            badge("years", "Feats", "Time Traveller", "Different years with a dated trip.", .hexagon, .rays, 0x6A4A8A, "hourglass", [3, 6, 10, 20], "years", Set(entries.map(\.year)).count),
            badge("dates", "Feats", "Archivist", "Places you've put a date on.", .shield, .plain, 0x5A5148, "calendar", [5, 20, 50], "places", snapshot.visits.filter { $0.when != nil }.count),
            badge("photos", "Feats", "Scrapbook", "Places with a photo pinned to them.", .circle, .plain, 0xB04A6A, "photo.fill", [1, 5, 15], "places", photoCounts.count),

            badge("settler", "Home", "Settler", "Places you've lived.", .shield, .rays, 0x2F9E86, "house.fill", [1, 2, 4], "homes", snapshot.lived.count),
            badge("local", "Home", "Local", "Years lived in one place.", .hexagon, .stripes, 0x24705F, "key.fill", [1, 3, 5, 10], "years", Int(livedYears)),
        ]
    }
}

// MARK: - Patch artwork

struct BadgeOutline: Shape {
    let kind: BeenBadge.Outline
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        switch kind {
        case .circle: return Path(ellipseIn: r)
        case .diamond:
            let side = w / 2.squareRoot() * 0.92
            return Path(roundedRect: CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side), cornerRadius: side * 0.2, style: .continuous)
                .applying(CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: .pi / 4).translatedBy(x: -r.midX, y: -r.midY))
        case .hexagon:
            // Six points, corners rounded by running quad curves through them.
            let points = (0..<6).map { i -> CGPoint in
                let a = CGFloat(i) * .pi / 3 - .pi / 2
                return CGPoint(x: r.midX + cos(a) * w / 2, y: r.midY + sin(a) * h / 2)
            }
            var path = Path()
            for i in 0..<6 {
                let p = points[i], next = points[(i + 1) % 6], previous = points[(i + 5) % 6]
                let a = CGPoint(x: p.x + (previous.x - p.x) * 0.16, y: p.y + (previous.y - p.y) * 0.16)
                let b = CGPoint(x: p.x + (next.x - p.x) * 0.16, y: p.y + (next.y - p.y) * 0.16)
                if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
                path.addQuadCurve(to: b, control: p)
            }
            path.closeSubpath()
            return path
        case .shield:
            var path = Path()
            let c = w * 0.14
            path.move(to: CGPoint(x: x + c, y: y + h * 0.04))
            path.addLine(to: CGPoint(x: x + w - c, y: y + h * 0.04))
            path.addQuadCurve(to: CGPoint(x: x + w * 0.96, y: y + h * 0.04 + c), control: CGPoint(x: x + w * 0.96, y: y + h * 0.04))
            path.addLine(to: CGPoint(x: x + w * 0.96, y: y + h * 0.52))
            path.addQuadCurve(to: CGPoint(x: x + w / 2, y: y + h), control: CGPoint(x: x + w * 0.94, y: y + h * 0.84))
            path.addQuadCurve(to: CGPoint(x: x + w * 0.04, y: y + h * 0.52), control: CGPoint(x: x + w * 0.06, y: y + h * 0.84))
            path.addLine(to: CGPoint(x: x + w * 0.04, y: y + h * 0.04 + c))
            path.addQuadCurve(to: CGPoint(x: x + c, y: y + h * 0.04), control: CGPoint(x: x + w * 0.04, y: y + h * 0.04))
            path.closeSubpath()
            return path
        }
    }
}

/// A patch as a picture. Drawing one takes about forty layered shapes, so each is drawn once and the
/// picture reused; a grid of live patches made the page stutter.
struct BadgeArt: View {
    let badge: BeenBadge
    var size: CGFloat = 88
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Image(uiImage: picture).resizable().frame(width: size * 1.16, height: size * 1.16).padding(-size * 0.08)
            .accessibilityHidden(true)
    }

    @MainActor private var picture: UIImage {
        let key = "\(badge.id):\(badge.level):\(Int(size))" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        // Room around the patch for its shadow.
        let renderer = ImageRenderer(content: BadgeDrawing(badge: badge, size: size).padding(size * 0.08))
        renderer.scale = 3
        let image = renderer.uiImage ?? UIImage()
        Self.cache.setObject(image, forKey: key)
        return image
    }
}

/// The patch itself, as live vector layers (used directly only for the large one you can tilt).
struct BadgeDrawing: View {
    let badge: BeenBadge
    var size: CGFloat = 88

    var body: some View {
        let thread = Color(uiColor: UIColor(sketchHex: badge.thread))
        let field = UIColor(sketchHex: badge.earned ? badge.field : 0x77736B)
        let cream = Color(red: 0.99, green: 0.96, blue: 0.88)
        let rim = size * 0.105
        ZStack {
            // Merrowed rim: thick thread wrapped round the edge.
            BadgeOutline(kind: badge.outline)
                .fill(LinearGradient(colors: [thread, thread.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
            BadgeOutline(kind: badge.outline, inset: rim * 0.5)
                .stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: rim * 0.82, lineCap: .butt, dash: [size * 0.016, size * 0.02]))
            BadgeOutline(kind: badge.outline, inset: rim * 0.5)
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: rim * 0.82, lineCap: .butt, dash: [size * 0.008, size * 0.028], dashPhase: size * 0.012))
            // Twill field with its scene.
            ZStack {
                LinearGradient(colors: [Color(uiColor: field.mixed(with: .white, amount: 0.16)), Color(uiColor: field), Color(uiColor: field.darker)], startPoint: .top, endPoint: .bottom)
                BadgeScene(scene: badge.scene, tint: cream)
                Twill().stroke(Color.black.opacity(0.1), lineWidth: max(0.5, size * 0.006))
            }
            .clipShape(BadgeOutline(kind: badge.outline, inset: rim))
            // Stitched inner ring.
            BadgeOutline(kind: badge.outline, inset: rim + size * 0.045)
                .stroke(cream.opacity(0.85), style: StrokeStyle(lineWidth: max(1, size * 0.014), lineCap: .round, dash: [size * 0.035, size * 0.03]))
            // Emblem, raised: a dark thread shadow under cream thread.
            Image(systemName: badge.symbol).font(.system(size: size * 0.33, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.35)).offset(x: size * 0.012, y: size * 0.018)
            Image(systemName: badge.symbol).font(.system(size: size * 0.33, weight: .heavy)).foregroundStyle(cream)
            // One knot per level, filled as you earn them.
            if badge.levels.count > 1 {
                HStack(spacing: size * 0.028) {
                    ForEach(0..<badge.levels.count, id: \.self) { i in
                        Circle().fill(i < badge.level ? cream : cream.opacity(0.25)).frame(width: size * 0.052, height: size * 0.052)
                    }
                }
                .offset(y: size * (badge.outline == .shield ? 0.24 : 0.27))
            }
            if !badge.earned {
                Image(systemName: "lock.fill").font(.system(size: size * 0.13, weight: .bold)).foregroundStyle(cream)
                    .padding(size * 0.05).background(Circle().fill(Color.black.opacity(0.55))).offset(x: size * 0.3, y: -size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .saturation(badge.earned ? 1 : 0.15).opacity(badge.earned ? 1 : 0.7)
        .shadow(color: .black.opacity(badge.earned ? 0.28 : 0.12), radius: size * 0.04, y: size * 0.03)
        .accessibilityHidden(true)
    }
}

/// Diagonal weave lines across the field.
private struct Twill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(2.5, rect.width / 26)
        var x = -rect.height
        while x < rect.width { path.move(to: CGPoint(x: x, y: rect.height)); path.addLine(to: CGPoint(x: x + rect.height, y: 0)); x += step }
        return path
    }
}

private struct BadgeScene: View {
    let scene: BeenBadge.Scene
    let tint: Color
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            switch scene {
            case .plain: break
            case .rays:
                for i in 0..<12 where i % 2 == 0 {
                    let a = CGFloat(i) / 12 * 2 * .pi, b = CGFloat(i + 1) / 12 * 2 * .pi
                    var p = Path(); p.move(to: CGPoint(x: w / 2, y: h / 2))
                    p.addLine(to: CGPoint(x: w / 2 + cos(a) * w, y: h / 2 + sin(a) * w)); p.addLine(to: CGPoint(x: w / 2 + cos(b) * w, y: h / 2 + sin(b) * w)); p.closeSubpath()
                    context.fill(p, with: .color(tint.opacity(0.13)))
                }
            case .peaks:
                func peak(_ cx: CGFloat, _ top: CGFloat, _ half: CGFloat, _ opacity: Double) {
                    var p = Path(); p.move(to: CGPoint(x: cx - half, y: h)); p.addLine(to: CGPoint(x: cx, y: top)); p.addLine(to: CGPoint(x: cx + half, y: h)); p.closeSubpath()
                    context.fill(p, with: .color(.black.opacity(opacity)))
                    var cap = Path(); let d = (h - top) * 0.24
                    cap.move(to: CGPoint(x: cx, y: top)); cap.addLine(to: CGPoint(x: cx - half * 0.26, y: top + d)); cap.addLine(to: CGPoint(x: cx, y: top + d * 0.7))
                    cap.addLine(to: CGPoint(x: cx + half * 0.26, y: top + d)); cap.closeSubpath()
                    context.fill(cap, with: .color(tint.opacity(0.75)))
                }
                peak(w * 0.3, h * 0.5, w * 0.34, 0.22); peak(w * 0.72, h * 0.56, w * 0.3, 0.3); peak(w * 0.52, h * 0.64, w * 0.26, 0.38)
            case .waves:
                for row in 0..<3 {
                    var p = Path(); let y = h * (0.66 + CGFloat(row) * 0.1)
                    p.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x < w { p.addQuadCurve(to: CGPoint(x: x + w / 8, y: y), control: CGPoint(x: x + w / 16, y: y - h * 0.05)); x += w / 8 }
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                    context.fill(p, with: .color(tint.opacity(0.14 + Double(row) * 0.07)))
                }
            case .stripes:
                for row in 0..<3 { context.fill(Path(CGRect(x: 0, y: h * (0.62 + CGFloat(row) * 0.1), width: w, height: h * 0.045)), with: .color(tint.opacity(0.3))) }
                context.fill(Path(CGRect(x: 0, y: h * 0.2, width: w, height: h * 0.03)), with: .color(tint.opacity(0.2)))
            case .globe:
                let r = w * 0.36, c = CGPoint(x: w / 2, y: h / 2)
                for k in [1.0, 0.62, 0.24] { context.stroke(Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r, width: 2 * r * k, height: 2 * r)), with: .color(tint.opacity(0.22)), lineWidth: w * 0.012) }
                for k in [-0.5, 0.0, 0.5] {
                    let half = r * (1 - k * k).squareRoot()
                    var p = Path(); p.move(to: CGPoint(x: c.x - half, y: c.y + r * k)); p.addLine(to: CGPoint(x: c.x + half, y: c.y + r * k))
                    context.stroke(p, with: .color(tint.opacity(0.22)), lineWidth: w * 0.012)
                }
            case .stars:
                for (x, y, s) in [(0.24, 0.3, 0.035), (0.72, 0.24, 0.05), (0.8, 0.52, 0.03), (0.2, 0.62, 0.04), (0.5, 0.17, 0.028), (0.66, 0.74, 0.035), (0.36, 0.78, 0.028)] {
                    context.fill(Path(ellipseIn: CGRect(x: w * x - w * s / 2, y: h * y - w * s / 2, width: w * s, height: w * s)), with: .color(tint.opacity(0.55)))
                }
            }
        }
    }
}

// MARK: - Grid and detail

struct BeenBadgeGrid: View {
    let snapshot: BeenPassportSnapshot
    @AppStorage(BeenStayStore.key) private var stayStorage = "[]"
    @AppStorage(PlacePhotoStore.key) private var photoIndex = "{}"
    @State private var open: BeenBadge?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let badges = BeenBadges.all(snapshot, stays: BeenStayStore.decode(stayStorage), photoCounts: PlacePhotoStore.counts(in: photoIndex))
        let earned = badges.filter(\.earned).count
        // The one you're closest to moving up on.
        let nextUp = badges.filter { $0.next != nil && $0.value > 0 }.max { $0.progress < $1.progress } ?? badges.first { $0.next != nil }
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(earned) of \(badges.count)").font(Sketch.display(.title, weight: .bold)).monospacedDigit()
                    Text("patches earned").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer()
                HStack(spacing: -14) { ForEach(badges.filter(\.earned).sorted { $0.level > $1.level }.prefix(4)) { BadgeArt(badge: $0, size: 50) } }
            }
            .padding(18).beenSurface(radius: 24)
            if let nextUp, let target = nextUp.next {
                Button { open = nextUp } label: {
                    HStack(spacing: 14) {
                        BadgeArt(badge: nextUp, size: 58)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEXT UP").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.accent(scheme))
                            Text("\(nextUp.title) · \(BeenBadge.levelNames[min(nextUp.level, 4)])").font(Sketch.text(15, "Bold", relativeTo: .subheadline))
                            ProgressView(value: nextUp.progress).tint(BeenPalette.amber)
                            Text("\(nextUp.value) of \(target) \(nextUp.unit)").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                        }
                    }
                    .padding(16).beenSurface(radius: 22, inset: true)
                }.buttonStyle(.plain)
            }
            ForEach(["Explorer", "Regions", "Feats", "Home"], id: \.self) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme)).padding(.leading, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 16) {
                        ForEach(badges.filter { $0.group == group }) { badge in
                            Button { TrippyHaptics.selection(); open = badge } label: {
                                VStack(spacing: 7) {
                                    BadgeArt(badge: badge, size: 84)
                                    Text(badge.title).font(Sketch.text(12, "Bold", relativeTo: .caption)).multilineTextAlignment(.center).lineLimit(2)
                                    Text(badge.earned ? badge.levelName : "\(badge.value)/\(badge.levels[0])").font(Sketch.text(11, relativeTo: .caption2))
                                        .foregroundStyle(badge.earned ? BeenPalette.accent(scheme) : BeenPalette.secondary(scheme))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SketchPressStyle())
                            .accessibilityLabel("\(badge.title), \(badge.earned ? badge.levelName : "not earned yet"). \(badge.blurb)")
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { BadgeDetail(badge: $0) }
    }
}

private struct BadgeDetail: View {
    let badge: BeenBadge
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var tilt = CGSize.zero

    var body: some View {
        VerticalPage {
            VStack(spacing: 18) {
                // Drag the patch to turn it in the light.
                BadgeDrawing(badge: badge, size: 200)
                    .rotation3DEffect(.degrees(Double(tilt.width) / 6), axis: (0, 1, 0))
                    .rotation3DEffect(.degrees(Double(-tilt.height) / 6), axis: (1, 0, 0))
                    .scaleEffect(shown || reduceMotion ? 1 : 0.6).rotationEffect(.degrees(shown || reduceMotion ? 0 : -18))
                    .gesture(DragGesture().onChanged { tilt = CGSize(width: max(-120, min(120, $0.translation.width)), height: max(-120, min(120, $0.translation.height))) }
                        .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { tilt = .zero } })
                    .padding(.top, 26)
                VStack(spacing: 6) {
                    Text(badge.title).font(Sketch.display(.title2, weight: .bold))
                    Text(badge.blurb).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(BeenPalette.secondary(scheme)).multilineTextAlignment(.center)
                }
                VStack(spacing: 0) {
                    ForEach(Array(badge.levels.enumerated()), id: \.offset) { index, need in
                        let done = badge.value >= need, current = !done && badge.next == need
                        HStack(spacing: 12) {
                            Circle().fill(Color(uiColor: UIColor(sketchHex: [0xB8733E, 0xC3C9D1, 0xE9B93F, 0x8FD9D0, 0xC7AEF7][min(index, 4)]))).frame(width: 14, height: 14)
                                .opacity(done ? 1 : 0.35)
                            Text(badge.levels.count == 1 ? "Earned" : BeenBadge.levelNames[min(index, 4)]).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                            Spacer()
                            Text(current ? "\(badge.value) of \(need) \(badge.unit)" : "\(need) \(badge.unit)").font(Sketch.text(13, relativeTo: .footnote)).monospacedDigit()
                                .foregroundStyle(BeenPalette.secondary(scheme))
                            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? BeenLook.lived : BeenPalette.secondary(scheme).opacity(0.5))
                        }
                        .frame(minHeight: 46)
                        if current { ProgressView(value: badge.progress).tint(BeenPalette.amber).padding(.bottom, 8) }
                        if index < badge.levels.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .padding(.horizontal, 16).beenSurface(radius: 22)
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
        }
        .background(BeenPalette.base(scheme).ignoresSafeArea()).foregroundStyle(BeenPalette.ink(scheme))
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { shown = true } }
        .sensoryFeedback(.impact(weight: .light), trigger: shown)
    }
}
