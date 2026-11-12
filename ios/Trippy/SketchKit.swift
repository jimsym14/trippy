import SwiftUI

// MARK: - Design tokens
//
// Warm paper, dark ink and six pigments, one per meaning. Display type is a
// serif; everything you read is Plus Jakarta Sans. Illustrations are line
// drawings that draw themselves in once, then stay still.

enum Sketch {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(sketchHex: dark) : UIColor(sketchHex: light) })
    }
    static let paper = dynamic(0xF7F3EB, 0x161513)
    static let paperDeep = dynamic(0xEEE8DC, 0x22201C)
    static let card = dynamic(0xFFFDF9, 0x201E1B)
    static let ink = dynamic(0x1E1C19, 0xF1ECE2)
    static let inkSoft = dynamic(0x5E5850, 0xB9B1A4)
    static let inkFaint = dynamic(0x8F877B, 0x857D71)
    static let rule = dynamic(0xE3DCCF, 0x34302A)

    static let clay = dynamic(0xC0603F, 0xE08A68)
    static let coral = dynamic(0xDD5A4A, 0xF08374)
    static let ochre = dynamic(0xB9852C, 0xE8BA62)
    static let sage = dynamic(0x4A7560, 0x8DBB9F)
    static let sky = dynamic(0x4A79A0, 0x8DB6D8)
    static let plum = dynamic(0x765896, 0xB49AD2)

    static let pigments: [(String, Color)] = [("clay", clay), ("coral", coral), ("ochre", ochre),
                                              ("sage", sage), ("sky", sky), ("plum", plum)]
    static func pigment(_ name: String?) -> Color { pigments.first { $0.0 == name }?.1 ?? clay }
    static func dayColor(_ index: Int) -> Color { [clay, sky, sage, plum, ochre, coral][index % 6] }

    static func display(_ style: Font.TextStyle = .title, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }
    /// Supporting text: the reading face at a quieter size (no italics, no script).
    static func hand(_ style: Font.TextStyle = .callout) -> Font {
        let sizes: [Font.TextStyle: CGFloat] = [.caption: 12, .caption2: 11, .footnote: 13, .callout: 15, .body: 16,
                                                .headline: 16, .title3: 19, .subheadline: 14]
        return .custom("PlusJakartaSans-Regular", size: sizes[style] ?? 15, relativeTo: style)
    }
    static func text(_ size: CGFloat, _ weight: String = "Regular", relativeTo: Font.TextStyle = .body) -> Font {
        .custom("PlusJakartaSans-\(weight)", size: size, relativeTo: relativeTo)
    }
    static let eyebrow = Font.custom("PlusJakartaSans-Bold", size: 11, relativeTo: .caption2)
}

extension UIColor {
    convenience init(sketchHex value: UInt32) {
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(sketchHex hex: String) { self.init(uiColor: UIColor(sketchHex: UInt32(hex, radix: 16) ?? 0xC0603F)) }
}

// MARK: - Geometry

struct SketchNoise {
    private var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 97) | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 10_000) / 10_000 - 0.5
    }
}

/// Kept for illustrations; cards use plain continuous rounded rectangles.
struct WobblyRect: Shape {
    var radius: CGFloat = 18
    var wobble: CGFloat = 0
    var seed: Int = 1
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(radius, min(rect.width, rect.height) / 2), style: .continuous)
    }
}

/// Dotted travel line between timeline stops.
struct DottedTrail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - Illustrations

/// Line drawings in a 100×100 box. Decoration only; hidden from VoiceOver.
enum Doodle: String, CaseIterable, Codable, Identifiable {
    case balloon, sun, spires, tram, wave, palm, plane, fork, ticket, bag, mountain, moon, star, heart, camera, cup, bridge, map
    case tower, arena, pagoda, windmill, dome, skyline
    case car, train, columns, castle, pyramid, lighthouse
    var id: String { rawValue }

    var label: String {
        switch self {
        case .balloon: "Balloon"; case .sun: "Sun"; case .spires: "Spires"; case .tram: "Tram"; case .wave: "Sea"
        case .palm: "Palm"; case .plane: "Plane"; case .fork: "Food"; case .ticket: "Ticket"; case .bag: "Shopping"
        case .mountain: "Mountain"; case .moon: "Night"; case .star: "Star"; case .heart: "Heart"; case .camera: "Camera"
        case .cup: "Coffee"; case .bridge: "Bridge"; case .map: "Map"
        case .tower: "Tower"; case .arena: "Arena"; case .pagoda: "Pagoda"; case .windmill: "Windmill"; case .dome: "Dome"; case .skyline: "Skyline"
        case .car: "Road trip"; case .train: "Train"; case .columns: "Temple"; case .castle: "Castle"; case .pyramid: "Pyramid"; case .lighthouse: "Lighthouse"
        }
    }

    /// The trip's own name wins over the city ("Vermut weekend" → fork).
    static func suggested(title: String, city: String) -> Doodle { match(title) ?? match(city) ?? .balloon }
    static func suggested(for text: String) -> Doodle { match(text) ?? .balloon }
    private static func match(_ text: String) -> Doodle? {
        let t = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let rules: [([String], Doodle)] = [
            (["food", "φαγητ", "vermut", "tapas", "γαστρο", "wine", "κρασ"], .fork), (["kids", "παιδ", "family"], .balloon),
            (["καλοκ", "summer", "beach", "παραλ"], .sun),
            (["barcelona", "sagrada", "gaudi"], .spires), (["lisbon", "lisboa", "porto", "tram", "san francisco"], .tram),
            (["road trip", "roadtrip", "drive"], .car), (["interrail", "by train", "rail"], .train),
            (["athens", "αθην", "acropolis", "delphi", "olympia", "agrigento"], .columns),
            (["edinburgh", "salzburg", "munich", "neuschwanstein", "krakow", "kraków", "ljubljana", "tallinn", "disney"], .castle),
            (["cairo", "giza", "egypt", "luxor", "mexico city", "teotihuacan", "chichen", "louvre"], .pyramid),
            (["cape town", "algarve", "cornwall", "brittany", "maine", "nova scotia", "faro", "iceland", "reykjav"], .lighthouse),
            (["paris", "eiffel"], .tower), (["rome", "roma", "colosseum", "verona"], .arena),
            (["tokyo", "kyoto", "osaka", "japan", "seoul", "beijing", "hanoi"], .pagoda),
            (["amsterdam", "netherlands", "holland", "rotterdam"], .windmill),
            (["istanbul", "florence", "firenze", "vatican", "dubai", "marrakech"], .dome),
            (["new york", "nyc", "chicago", "hong kong", "singapore", "london", "toronto"], .skyline),
            (["island", "νησι", "santorini", "mykonos", "crete", "κρητ", "bali", "maldives"], .wave),
            (["prague", "budapest", "venice", "sydney"], .bridge),
            (["alps", "swiss", "βουν", "ski", "dolomit"], .mountain), (["night", "βραδ"], .moon),
        ]
        return rules.first { $0.0.contains { t.contains($0) } }?.1
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let o = CGPoint(x: rect.midX - 50 * s, y: rect.midY - 50 * s)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: o.x + (x - r) * s, y: o.y + (y - r) * s, width: 2 * r * s, height: 2 * r * s))
        }
        var p = Path()
        switch self {
        case .balloon:
            p.move(to: pt(50, 70)); p.addCurve(to: pt(50, 12), control1: pt(18, 52), control2: pt(20, 14))
            p.addCurve(to: pt(50, 70), control1: pt(80, 14), control2: pt(82, 52))
            p.move(to: pt(44, 72)); p.addLine(to: pt(56, 72)); p.addLine(to: pt(53, 84)); p.addLine(to: pt(47, 84)); p.closeSubpath()
            p.move(to: pt(38, 30)); p.addQuadCurve(to: pt(45, 20), control: pt(39, 22))
        case .sun:
            p.addPath(circle(50, 50, 17))
            for i in 0..<10 {
                let a = CGFloat(i) / 10 * .pi * 2, outer: CGFloat = i.isMultiple(of: 2) ? 38 : 33
                p.move(to: pt(50 + cos(a) * 26, 50 + sin(a) * 26)); p.addLine(to: pt(50 + cos(a) * outer, 50 + sin(a) * outer))
            }
        case .spires:
            for (x, h) in [(24.0, 30.0), (40.0, 14.0), (60.0, 14.0), (76.0, 30.0)] {
                p.move(to: pt(x - 7, 88)); p.addLine(to: pt(x - 6, h + 16)); p.addQuadCurve(to: pt(x, h), control: pt(x - 4, h + 4))
                p.addQuadCurve(to: pt(x + 6, h + 16), control: pt(x + 4, h + 4)); p.addLine(to: pt(x + 7, 88))
                p.addPath(circle(x, h - 3, 2.2))
            }
            p.move(to: pt(10, 88)); p.addLine(to: pt(90, 88))
            p.move(to: pt(46, 88)); p.addLine(to: pt(46, 70)); p.addQuadCurve(to: pt(54, 70), control: pt(50, 62)); p.addLine(to: pt(54, 88))
        case .tram:
            p.addRoundedRect(in: CGRect(x: o.x + 18 * s, y: o.y + 30 * s, width: 64 * s, height: 44 * s), cornerSize: CGSize(width: 9 * s, height: 9 * s))
            p.move(to: pt(18, 52)); p.addLine(to: pt(82, 52))
            for x in [30.0, 50.0, 70.0] { p.addRect(CGRect(x: o.x + (x - 7) * s, y: o.y + 36 * s, width: 14 * s, height: 11 * s)) }
            p.addPath(circle(32, 80, 5)); p.addPath(circle(68, 80, 5))
            p.move(to: pt(50, 30)); p.addLine(to: pt(50, 18)); p.move(to: pt(36, 14)); p.addLine(to: pt(64, 22))
            p.move(to: pt(8, 88)); p.addLine(to: pt(92, 88))
        case .wave:
            for row in 0..<3 {
                let y = 42 + CGFloat(row) * 14
                p.move(to: pt(10, y))
                for k in 0..<4 { let x = 10 + CGFloat(k) * 20; p.addQuadCurve(to: pt(x + 20, y), control: pt(x + 10, y - 9)) }
            }
            p.addPath(circle(72, 22, 9))
        case .palm:
            p.move(to: pt(52, 90)); p.addCurve(to: pt(50, 34), control1: pt(56, 70), control2: pt(46, 50))
            for (dx, dy) in [(-30.0, 6.0), (30.0, 4.0), (-22.0, -14.0), (22.0, -16.0), (2.0, -22.0)] {
                p.move(to: pt(50, 34)); p.addQuadCurve(to: pt(50 + dx, 34 + dy + 10), control: pt(50 + dx * 0.5, 34 + dy - 10))
            }
            p.move(to: pt(20, 90)); p.addLine(to: pt(84, 90))
        case .plane:
            p.move(to: pt(12, 56)); p.addLine(to: pt(86, 38)); p.addQuadCurve(to: pt(88, 46), control: pt(94, 40))
            p.addLine(to: pt(18, 64)); p.closeSubpath()
            p.move(to: pt(46, 49)); p.addLine(to: pt(30, 24)); p.addLine(to: pt(38, 22)); p.addLine(to: pt(62, 45))
            p.move(to: pt(50, 57)); p.addLine(to: pt(46, 80)); p.addLine(to: pt(53, 79)); p.addLine(to: pt(62, 54))
        case .fork:
            p.move(to: pt(34, 12)); p.addLine(to: pt(34, 34)); p.addQuadCurve(to: pt(42, 44), control: pt(34, 42))
            p.addLine(to: pt(42, 88)); p.move(to: pt(42, 12)); p.addLine(to: pt(42, 32))
            p.move(to: pt(50, 12)); p.addLine(to: pt(50, 34)); p.addQuadCurve(to: pt(42, 44), control: pt(50, 42))
            p.move(to: pt(66, 88)); p.addLine(to: pt(66, 12)); p.addCurve(to: pt(66, 52), control1: pt(80, 22), control2: pt(80, 46))
        case .ticket:
            p.move(to: pt(14, 30)); p.addLine(to: pt(86, 30)); p.addLine(to: pt(86, 42)); p.addQuadCurve(to: pt(86, 58), control: pt(78, 50))
            p.addLine(to: pt(86, 70)); p.addLine(to: pt(14, 70)); p.addLine(to: pt(14, 58)); p.addQuadCurve(to: pt(14, 42), control: pt(22, 50))
            p.closeSubpath(); p.move(to: pt(62, 32)); p.addLine(to: pt(62, 68))
        case .bag:
            p.move(to: pt(22, 36)); p.addLine(to: pt(78, 36)); p.addLine(to: pt(84, 86)); p.addLine(to: pt(16, 86)); p.closeSubpath()
            p.move(to: pt(38, 44)); p.addLine(to: pt(38, 28)); p.addQuadCurve(to: pt(62, 28), control: pt(50, 8)); p.addLine(to: pt(62, 44))
        case .mountain:
            p.move(to: pt(6, 84)); p.addLine(to: pt(38, 30)); p.addLine(to: pt(54, 54)); p.addLine(to: pt(66, 38)); p.addLine(to: pt(94, 84))
            p.move(to: pt(30, 44)); p.addLine(to: pt(38, 38)); p.addLine(to: pt(44, 46)); p.addPath(circle(78, 20, 7))
        case .moon:
            p.move(to: pt(60, 14)); p.addCurve(to: pt(60, 86), control1: pt(14, 18), control2: pt(14, 82))
            p.addCurve(to: pt(60, 14), control1: pt(36, 72), control2: pt(36, 28))
        case .star:
            for i in 0..<5 {
                let a = CGFloat(i) / 5 * .pi * 2 - .pi / 2, b = a + .pi / 5
                let outer = pt(50 + cos(a) * 36, 52 + sin(a) * 36), inner = pt(50 + cos(b) * 15, 52 + sin(b) * 15)
                if i == 0 { p.move(to: outer) } else { p.addLine(to: outer) }
                p.addLine(to: inner)
            }
            p.closeSubpath()
        case .heart:
            p.move(to: pt(50, 84)); p.addCurve(to: pt(50, 32), control1: pt(8, 56), control2: pt(18, 14))
            p.addCurve(to: pt(50, 84), control1: pt(82, 14), control2: pt(92, 56))
        case .camera:
            p.addRoundedRect(in: CGRect(x: o.x + 14 * s, y: o.y + 32 * s, width: 72 * s, height: 46 * s), cornerSize: CGSize(width: 8 * s, height: 8 * s))
            p.move(to: pt(36, 32)); p.addLine(to: pt(42, 22)); p.addLine(to: pt(58, 22)); p.addLine(to: pt(64, 32))
            p.addPath(circle(50, 55, 13))
        case .cup:
            p.move(to: pt(20, 40)); p.addLine(to: pt(70, 40)); p.addCurve(to: pt(20, 40), control1: pt(68, 88), control2: pt(22, 88))
            p.move(to: pt(70, 48)); p.addCurve(to: pt(68, 66), control1: pt(88, 46), control2: pt(86, 66))
            p.move(to: pt(36, 30)); p.addQuadCurve(to: pt(36, 14), control: pt(28, 22))
            p.move(to: pt(52, 30)); p.addQuadCurve(to: pt(52, 14), control: pt(44, 22))
        case .bridge:
            p.move(to: pt(6, 62)); p.addLine(to: pt(94, 62))
            p.move(to: pt(10, 62)); p.addQuadCurve(to: pt(50, 62), control: pt(30, 30)); p.addQuadCurve(to: pt(90, 62), control: pt(70, 30))
            for x in [20.0, 50.0, 80.0] { p.move(to: pt(x, 62)); p.addLine(to: pt(x, 84)) }
        case .tower:
            p.move(to: pt(30, 90)); p.addQuadCurve(to: pt(46, 30), control: pt(42, 60)); p.addLine(to: pt(48, 10)); p.addLine(to: pt(52, 10)); p.addLine(to: pt(54, 30))
            p.addQuadCurve(to: pt(70, 90), control: pt(58, 60))
            p.move(to: pt(38, 62)); p.addLine(to: pt(62, 62)); p.move(to: pt(44, 40)); p.addLine(to: pt(56, 40))
            p.move(to: pt(40, 90)); p.addQuadCurve(to: pt(60, 90), control: pt(50, 72))
        case .arena:
            p.addEllipse(in: CGRect(x: o.x + 10 * s, y: o.y + 30 * s, width: 80 * s, height: 22 * s))
            p.move(to: pt(10, 41)); p.addLine(to: pt(12, 80)); p.addQuadCurve(to: pt(88, 80), control: pt(50, 94)); p.addLine(to: pt(90, 41))
            for x in stride(from: 20.0, through: 80.0, by: 12) {
                p.move(to: pt(x, 60 + abs(50 - x) * 0.12)); p.addLine(to: pt(x, 80 + (40 - abs(50 - x)) * 0.12)); p.addArc(center: pt(x + 4, 60 + abs(50 - x) * 0.12), radius: 4 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            }
        case .pagoda:
            for (i, w) in [36.0, 28.0, 20.0].enumerated() {
                let y = 74 - Double(i) * 20
                p.move(to: pt(50 - w, y)); p.addQuadCurve(to: pt(50 + w, y), control: pt(50, y - 10))
                p.move(to: pt(50 - w * 0.6, y)); p.addLine(to: pt(50 - w * 0.6, y + 12)); p.move(to: pt(50 + w * 0.6, y)); p.addLine(to: pt(50 + w * 0.6, y + 12))
            }
            p.move(to: pt(50, 26)); p.addLine(to: pt(50, 12)); p.move(to: pt(14, 88)); p.addLine(to: pt(86, 88))
        case .windmill:
            p.move(to: pt(38, 88)); p.addLine(to: pt(44, 44)); p.addLine(to: pt(56, 44)); p.addLine(to: pt(62, 88))
            p.move(to: pt(42, 44)); p.addQuadCurve(to: pt(58, 44), control: pt(50, 32))
            for a in [45.0, 135.0, 225.0, 315.0] {
                let r = a * .pi / 180
                p.move(to: pt(50, 40)); p.addLine(to: pt(50 + cos(r) * 34, 40 + sin(r) * 34))
            }
            p.addPath(circle(50, 40, 3)); p.move(to: pt(10, 88)); p.addLine(to: pt(90, 88))
        case .dome:
            p.move(to: pt(22, 60)); p.addQuadCurve(to: pt(78, 60), control: pt(50, 6)); p.move(to: pt(50, 24)); p.addLine(to: pt(50, 12))
            p.addRect(CGRect(x: o.x + 18 * s, y: o.y + 60 * s, width: 64 * s, height: 26 * s))
            for x in [30.0, 44.0, 56.0, 70.0] { p.move(to: pt(x, 86)); p.addLine(to: pt(x, 70)) }
            p.move(to: pt(8, 88)); p.addLine(to: pt(8, 36)); p.addLine(to: pt(12, 30)); p.addLine(to: pt(16, 36)); p.addLine(to: pt(16, 88))
        case .skyline:
            p.move(to: pt(6, 88))
            for (x, h) in [(14.0, 60.0), (24.0, 40.0), (34.0, 52.0), (44.0, 20.0), (54.0, 46.0), (66.0, 30.0), (78.0, 56.0), (90.0, 64.0)] {
                p.addLine(to: pt(x - 8, h)); p.addLine(to: pt(x, h))
            }
            p.addLine(to: pt(94, 88)); p.move(to: pt(41, 20)); p.addLine(to: pt(41, 10))
        case .car:
            p.move(to: pt(10, 70)); p.addLine(to: pt(10, 56)); p.addLine(to: pt(24, 52)); p.addLine(to: pt(34, 36)); p.addLine(to: pt(66, 36))
            p.addLine(to: pt(78, 52)); p.addLine(to: pt(90, 56)); p.addLine(to: pt(90, 70)); p.closeSubpath()
            p.move(to: pt(38, 40)); p.addLine(to: pt(32, 52)); p.addLine(to: pt(70, 52)); p.addLine(to: pt(62, 40)); p.closeSubpath()
            p.addPath(circle(28, 72, 8)); p.addPath(circle(72, 72, 8))
            p.move(to: pt(4, 88)); p.addLine(to: pt(30, 88)); p.move(to: pt(44, 88)); p.addLine(to: pt(56, 88)); p.move(to: pt(70, 88)); p.addLine(to: pt(96, 88))
        case .train:
            p.addRoundedRect(in: CGRect(x: o.x + 26 * s, y: o.y + 12 * s, width: 48 * s, height: 60 * s), cornerSize: CGSize(width: 14 * s, height: 14 * s))
            p.addRect(CGRect(x: o.x + 34 * s, y: o.y + 22 * s, width: 32 * s, height: 20 * s))
            p.addPath(circle(38, 58, 4)); p.addPath(circle(62, 58, 4))
            p.move(to: pt(36, 72)); p.addLine(to: pt(26, 88)); p.move(to: pt(64, 72)); p.addLine(to: pt(74, 88))
            p.move(to: pt(20, 82)); p.addLine(to: pt(80, 82)); p.move(to: pt(14, 92)); p.addLine(to: pt(86, 92))
        case .columns:
            p.move(to: pt(10, 34)); p.addLine(to: pt(50, 14)); p.addLine(to: pt(90, 34)); p.closeSubpath()
            p.move(to: pt(14, 40)); p.addLine(to: pt(86, 40))
            for x in [22.0, 38.0, 54.0, 70.0] {
                p.move(to: pt(x + 2, 42)); p.addLine(to: pt(x + 2, 80)); p.move(to: pt(x + 8, 42)); p.addLine(to: pt(x + 8, 80))
            }
            p.move(to: pt(12, 82)); p.addLine(to: pt(88, 82)); p.move(to: pt(8, 88)); p.addLine(to: pt(92, 88))
        case .castle:
            p.move(to: pt(16, 88)); p.addLine(to: pt(16, 30)); p.addLine(to: pt(22, 30)); p.addLine(to: pt(22, 36)); p.addLine(to: pt(28, 36)); p.addLine(to: pt(28, 30)); p.addLine(to: pt(34, 30))
            p.addLine(to: pt(34, 50)); p.addLine(to: pt(66, 50)); p.addLine(to: pt(66, 30)); p.addLine(to: pt(72, 30)); p.addLine(to: pt(72, 36)); p.addLine(to: pt(78, 36))
            p.addLine(to: pt(78, 30)); p.addLine(to: pt(84, 30)); p.addLine(to: pt(84, 88))
            p.move(to: pt(42, 88)); p.addLine(to: pt(42, 72)); p.addQuadCurve(to: pt(58, 72), control: pt(50, 60)); p.addLine(to: pt(58, 88))
            p.move(to: pt(50, 50)); p.addLine(to: pt(50, 22)); p.addLine(to: pt(64, 27)); p.addLine(to: pt(50, 32))
            p.move(to: pt(8, 88)); p.addLine(to: pt(92, 88))
        case .pyramid:
            p.move(to: pt(8, 84)); p.addLine(to: pt(42, 26)); p.addLine(to: pt(76, 84)); p.move(to: pt(42, 26)); p.addLine(to: pt(50, 84))
            p.move(to: pt(62, 60)); p.addLine(to: pt(76, 40)); p.addLine(to: pt(94, 84))
            p.addPath(circle(80, 18, 7)); p.move(to: pt(4, 86)); p.addLine(to: pt(96, 86))
        case .lighthouse:
            p.move(to: pt(38, 84)); p.addLine(to: pt(44, 34)); p.addLine(to: pt(56, 34)); p.addLine(to: pt(62, 84))
            p.addRect(CGRect(x: o.x + 42 * s, y: o.y + 20 * s, width: 16 * s, height: 14 * s))
            p.move(to: pt(40, 20)); p.addQuadCurve(to: pt(60, 20), control: pt(50, 8))
            p.move(to: pt(41, 52)); p.addLine(to: pt(59, 52)); p.move(to: pt(40, 68)); p.addLine(to: pt(60, 68))
            p.move(to: pt(60, 24)); p.addLine(to: pt(88, 16)); p.move(to: pt(40, 24)); p.addLine(to: pt(12, 16))
            p.move(to: pt(6, 88)); p.addQuadCurve(to: pt(30, 88), control: pt(18, 82)); p.addQuadCurve(to: pt(54, 88), control: pt(42, 82))
            p.addQuadCurve(to: pt(78, 88), control: pt(66, 82)); p.addQuadCurve(to: pt(96, 88), control: pt(88, 82))
        case .map:
            p.move(to: pt(12, 24)); p.addLine(to: pt(36, 16)); p.addLine(to: pt(64, 26)); p.addLine(to: pt(88, 18))
            p.addLine(to: pt(88, 78)); p.addLine(to: pt(64, 86)); p.addLine(to: pt(36, 76)); p.addLine(to: pt(12, 84)); p.closeSubpath()
            p.move(to: pt(36, 16)); p.addLine(to: pt(36, 76)); p.move(to: pt(64, 26)); p.addLine(to: pt(64, 86))
        }
        return p
    }
}

struct DoodleShape: Shape {
    let doodle: Doodle
    func path(in rect: CGRect) -> Path { doodle.path(in: rect) }
}

/// Ink line over a soft pigment wash. The line draws itself in when it first appears.
struct DoodleView: View {
    let doodle: Doodle
    var tint: Color = Sketch.clay
    var lineWidth: CGFloat = 2.2
    var wash = true
    var animated = true
    @State private var drawn: CGFloat = 1
    @State private var washed: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if wash { DoodleShape(doodle: doodle).fill(tint.opacity(0.2)).offset(x: 3, y: 3).opacity(washed) }
            DoodleShape(doodle: doodle).trim(from: 0, to: drawn)
                .stroke(Sketch.ink.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard animated, !reduceMotion else { return }
            drawn = 0; washed = 0
            withAnimation(.easeInOut(duration: 1.1)) { drawn = 1 }
            withAnimation(.easeOut(duration: 0.6).delay(0.7)) { washed = 1 }
        }
    }
}

// MARK: - Surfaces

struct SketchCard: ViewModifier {
    var seed = 1
    var tint: Color? = nil
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return content.padding(padding)
            .background(shape.fill(Sketch.card))
            .background(shape.fill(tint?.opacity(0.06) ?? .clear))
            .overlay(shape.strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
    }
}

extension View {
    func sketchCard(seed: Int = 1, tint: Color? = nil, padding: CGFloat = 16) -> some View {
        modifier(SketchCard(seed: seed, tint: tint, padding: padding))
    }
}

struct PaperBackground: View {
    var body: some View { Sketch.paper.ignoresSafeArea() }
}

/// Section heading: a small drawn icon and a serif title.
struct SketchHeading: View {
    let title: String
    var icon: TrippyIcon? = nil
    var tint: Color = Sketch.clay
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                TrippyIconView(icon: icon, size: 20, weight: 2, animated: true).foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.12)))
            }
            Text(title).font(Sketch.display(.title3)).foregroundStyle(Sketch.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
    }
}

struct SketchTag: View {
    let text: String
    var tint: Color = Sketch.clay
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(Sketch.text(11, "SemiBold", relativeTo: .caption))
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct SketchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct SketchPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(Sketch.text(16, "Bold", relativeTo: .headline))
            .foregroundStyle(Sketch.paper)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(enabled ? Sketch.ink : Sketch.inkFaint))
        }
        .buttonStyle(SketchPressStyle())
        .disabled(!enabled)
    }
}

// MARK: - The map's raised controls, shared across the app

/// The general map's raised button surface: a soft vertical gradient, a lit
/// upper edge and two shadows. Used for round buttons and pills everywhere.
struct RaisedSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .background(shape.fill(LinearGradient(colors: dark ? [Color(sketchHex: "3A3833"), Color(sketchHex: "1D1C19")] : [.white, Color(sketchHex: "EFEBE3")],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.22 : 0.95), .black.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.3 : 0.13), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func raisedCircle() -> some View { modifier(RaisedSurface(shape: Circle())) }
    func raisedCapsule() -> some View { modifier(RaisedSurface(shape: Capsule())) }
    func raisedRounded(_ radius: CGFloat = 16) -> some View { modifier(RaisedSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous))) }
}

// MARK: - Hide the keyboard

/// A small round button at the right edge, just above the keyboard, that puts the keyboard away. It replaces the
/// keyboard toolbar's "Done", which iOS draws as a capsule in the middle of the screen.
private struct KeyboardDismissButton: ViewModifier {
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Sketch.ink)
                            .frame(width: 52, height: 44)
                            .background(Capsule().fill(Sketch.card))
                            .overlay(Capsule().strokeBorder(Sketch.rule.opacity(0.9), lineWidth: 0.7))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    }
                    .buttonStyle(SketchPressStyle())
                    .padding(.trailing, 16).padding(.bottom, 10)
                    .accessibilityLabel("Hide keyboard")
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.snappy) { visible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.snappy) { visible = false }
            }
    }
}

extension View {
    /// Shows a "hide keyboard" button above the keyboard while it is up.
    func keyboardDismissButton() -> some View { modifier(KeyboardDismissButton()) }
}

// MARK: - Pages scroll up and down only

/// A vertical scroll view whose content is exactly as wide as the screen. A child that is a little too wide
/// (a long word, a fixed-size row) can otherwise widen the page and let it drift sideways while scrolling,
/// which makes the whole screen feel loose. Use it for every page that scrolls.
struct VerticalPage<Content: View>: View {
    var showsIndicators = true
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content.containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
