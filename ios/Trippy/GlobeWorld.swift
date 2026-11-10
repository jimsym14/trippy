import SwiftUI
import Accelerate
import simd
import CoreLocation

// MARK: - World borders (bundled)
//
// Natural Earth 1:50m country polygons (public domain), packed by scripts/build_globe_borders.py.
// They give the globe its coastlines and every country's outline offline, and say which country
// sits under a point without asking a geocoder.

struct GlobeCountry {
    let code: String?
    let name: String
    let continent: String
    /// Rings as (longitude, latitude) in degrees. Outer rings and holes together; fill even-odd.
    let rings: [[SIMD2<Float>]]
    let minimum: SIMD2<Float>
    let maximum: SIMD2<Float>

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let p = SIMD2(Float(coordinate.longitude), Float(coordinate.latitude))
        guard p.x >= minimum.x, p.x <= maximum.x, p.y >= minimum.y, p.y <= maximum.y else { return false }
        var inside = false
        for ring in rings {
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
        }
        return inside
    }

    /// The outline on an equirectangular canvas of the given size (north at y = 0).
    func path(width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        let sx = CGFloat(width) / 360, sy = CGFloat(height) / 180
        for ring in rings {
            for (i, point) in ring.enumerated() {
                let p = CGPoint(x: (CGFloat(point.x) + 180) * sx, y: (90 - CGFloat(point.y)) * sy)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
        return path
    }
}

enum GlobeBorders {
    private static let continents = ["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America", "Open ocean"]

    static let countries: [GlobeCountry] = {
        guard let url = Bundle.main.url(forResource: "globe-borders", withExtension: "bin"), let data = try? Data(contentsOf: url),
              data.count > 6, data.prefix(4) == Data("TGB1".utf8) else { return [] }
        var offset = 4
        func u8() -> Int { defer { offset += 1 }; return Int(data[offset]) }
        func u16() -> Int { defer { offset += 2 }; return Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func i16() -> Float { Float(Int16(truncatingIfNeeded: u16())) }
        var result: [GlobeCountry] = []
        let count = u16()
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard offset + 6 <= data.count else { break }
            let code = String(decoding: data[offset..<offset + 2], as: UTF8.self); offset += 2
            let continent = u8(), nameLength = u8()
            let name = String(decoding: data[offset..<offset + nameLength], as: UTF8.self); offset += nameLength
            var rings: [[SIMD2<Float>]] = []
            var low = SIMD2<Float>(180, 90), high = SIMD2<Float>(-180, -90)
            for _ in 0..<u16() {
                let points = u16()
                guard offset + points * 4 <= data.count else { return result }
                var ring: [SIMD2<Float>] = []
                ring.reserveCapacity(points)
                for _ in 0..<points {
                    let p = SIMD2(i16() / 100, i16() / 100)
                    ring.append(p); low = simd_min(low, p); high = simd_max(high, p)
                }
                rings.append(ring)
            }
            result.append(GlobeCountry(code: code == "--" ? nil : code, name: name,
                                       continent: continent < continents.count ? continents[continent] : "",
                                       rings: rings, minimum: low, maximum: high))
        }
        return result
    }()

    static let byCode: [String: GlobeCountry] = Dictionary(countries.compactMap { c in c.code.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })

    /// The country under a point, found on the phone.
    static func country(at coordinate: CLLocationCoordinate2D) -> GlobeCountry? {
        countries.first { $0.contains(coordinate) }
    }
}

// MARK: - Appearance

/// Sea, land and the default highlight for one globe look. Relief comes from light, so each is a flat colour.
struct GlobeTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let ocean: UInt32
    let land: UInt32
    let border: UInt32
    let glow: UInt32
    /// Light globes need darker city dots and softer light.
    let light: Bool

    static let ink = GlobeTheme(id: "ink", name: "Ink", ocean: 0x2B2A28, land: 0x45433F, border: 0x1C1B19, glow: 0x9A948A, light: false)
    static let paper = GlobeTheme(id: "paper", name: "Paper", ocean: 0xD9D1C1, land: 0xFBF7EE, border: 0xB7AD9A, glow: 0xE9DFCB, light: true)
    static let all: [GlobeTheme] = [
        ink, paper,
        GlobeTheme(id: "midnight", name: "Midnight", ocean: 0x101C2E, land: 0x2A4059, border: 0x0A1320, glow: 0x6FA3D8, light: false),
        GlobeTheme(id: "atlas", name: "Atlas", ocean: 0xA9C6D8, land: 0xF3ECDB, border: 0xB5A88F, glow: 0xCFE3F0, light: true),
        GlobeTheme(id: "forest", name: "Forest", ocean: 0x17241F, land: 0x35503F, border: 0x0F1814, glow: 0x8DBB9F, light: false),
        GlobeTheme(id: "plum", name: "Plum", ocean: 0x211A2C, land: 0x443659, border: 0x15101C, glow: 0xB49AD2, light: false),
        GlobeTheme(id: "terracotta", name: "Terracotta", ocean: 0x33201A, land: 0x6B4031, border: 0x21140F, glow: 0xE08A68, light: false),
        GlobeTheme(id: "sand", name: "Sand", ocean: 0xC9B48F, land: 0xEEDDB8, border: 0xA58E66, glow: 0xF2E3C2, light: true),
    ]
}

struct GlobeAccent: Identifiable, Equatable {
    let id: String
    let name: String
    let hex: UInt32
    static let all: [GlobeAccent] = [
        GlobeAccent(id: "amber", name: "Amber", hex: 0xF0A83D), GlobeAccent(id: "clay", name: "Clay", hex: 0xD9704A),
        GlobeAccent(id: "coral", name: "Coral", hex: 0xEE6A5B), GlobeAccent(id: "ochre", name: "Ochre", hex: 0xD9A441),
        GlobeAccent(id: "sage", name: "Sage", hex: 0x6FA487), GlobeAccent(id: "sky", name: "Sky", hex: 0x5C9BD1),
        GlobeAccent(id: "plum", name: "Plum", hex: 0x9A78C4), GlobeAccent(id: "rose", name: "Rose", hex: 0xE27FA4),
        GlobeAccent(id: "mint", name: "Mint", hex: 0x58C4B0), GlobeAccent(id: "snow", name: "Snow", hex: 0xF4EFE6),
    ]
}

/// What the person picked for the globe, shared by every globe in the app.
struct GlobeAppearance: Equatable {
    /// "auto" follows light and dark mode (Paper and Ink).
    var themeID = "auto"
    var accentID = "amber"
    /// 0 flat, 1 natural, 2 bold.
    var relief = 1

    static let themeKey = "trippy.globe.theme", accentKey = "trippy.globe.accent", reliefKey = "trippy.globe.relief"

    static var stored: GlobeAppearance {
        let d = UserDefaults.standard
        return GlobeAppearance(themeID: d.string(forKey: themeKey) ?? "auto", accentID: d.string(forKey: accentKey) ?? "amber",
                               relief: d.object(forKey: reliefKey) as? Int ?? 1)
    }

    func theme(dark: Bool) -> GlobeTheme {
        GlobeTheme.all.first { $0.id == themeID } ?? (dark ? .ink : .paper)
    }
    var accent: GlobeAccent { GlobeAccent.all.first { $0.id == accentID } ?? GlobeAccent.all[0] }
    var reliefIntensity: CGFloat { [0, 1.25, 2.2][min(max(relief, 0), 2)] }
    var cacheID: String { "\(themeID)|\(accentID)|\(relief)" }
}

/// What a globe texture carries besides its picture: the scene reads it to set relief and glow.
final class GlobeSkin {
    let normal: CGImage?
    let relief: CGFloat
    let glow: UIColor
    let light: Bool
    init(normal: CGImage?, relief: CGFloat, glow: UIColor, light: Bool) {
        self.normal = normal; self.relief = relief; self.glow = glow; self.light = light
    }

    private static var key: UInt8 = 0
    static func attach(_ skin: GlobeSkin, to image: UIImage) { objc_setAssociatedObject(image, &key, skin, .OBJC_ASSOCIATION_RETAIN) }
    static func of(_ image: UIImage?) -> GlobeSkin? { image.flatMap { objc_getAssociatedObject($0, &key) as? GlobeSkin } }
}

// MARK: - Relief
//
// NASA's GEBCO elevation image (public domain, bundled as globe-elevation.jpg) becomes a normal map:
// the light then catches real mountain ranges. Coasts get a small step up from the sea and borders a
// fine groove, both from the bundled outlines.

enum GlobeRelief {
    /// Built once, on first use; every globe shares it.
    static let normalMap: CGImage? = build(width: 4096, height: 2048)

    private static func gray(width: Int, height: Int, draw: (CGContext) -> Void) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            draw(ctx)
            return true
        }
        return ok ? pixels : nil
    }

    private static func blurred(_ pixels: [UInt8], width: Int, height: Int, kernel: UInt32) -> [UInt8] {
        var source = pixels, output = [UInt8](repeating: 0, count: pixels.count)
        source.withUnsafeMutableBytes { src in
            output.withUnsafeMutableBytes { dst in
                var a = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                var b = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                vImageTentConvolve_Planar8(&a, &b, nil, 0, 0, kernel, kernel, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return output
    }

    private static func build(width: Int, height: Int) -> CGImage? {
        guard let url = Bundle.main.url(forResource: "globe-elevation", withExtension: "jpg"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        // Bitmap memory starts at the top row, so no flip is needed for an image drawn as it is.
        guard let raw = gray(width: width, height: height, draw: { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }) else { return nil }
        let elevation = blurred(raw, width: width, height: height, kernel: 5)
        // Land as a plateau, borders as grooves. Paths have north at y = 0, the context has y up: flip.
        let outlineMask = gray(width: width, height: height) { ctx in
            ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 1, alpha: 1); ctx.setStrokeColor(gray: 0.72, alpha: 1); ctx.setLineWidth(1.4)
            for country in GlobeBorders.countries {
                let path = country.path(width: width, height: height)
                ctx.addPath(path); ctx.fillPath(using: .evenOdd)
            }
            for country in GlobeBorders.countries { ctx.addPath(country.path(width: width, height: height)); ctx.strokePath() }
        }
        let outlines: [UInt8] = outlineMask.map { blurred($0, width: width, height: height, kernel: 3) } ?? []

        // Low hills matter as much as high peaks on a globe this size: a square-root curve keeps both.
        var curve = [Float](repeating: 0, count: 256)
        for i in 0..<256 { curve[i] = powf(Float(i) / 255, 0.62) * 46 }
        var output = [UInt8](repeating: 255, count: width * height * 4)
        elevation.withUnsafeBufferPointer { e in
            outlines.withUnsafeBufferPointer { o in
                output.withUnsafeMutableBufferPointer { out in
                    let hasOutlines = o.count == e.count
                    let outPointer = out.baseAddress!
                    func h(_ x: Int, _ y: Int) -> Float {
                        let i = y * width + (x + width) % width
                        return curve[Int(e[i])] + (hasOutlines ? Float(o[i]) * 0.012 : 0)
                    }
                    DispatchQueue.concurrentPerform(iterations: height) { y in
                        let up = max(y - 1, 0), down = min(y + 1, height - 1)
                        // A pixel spans less ground towards the poles, so east–west slopes steepen.
                        let latitude = (0.5 - (Float(y) + 0.5) / Float(height)) * .pi
                        let stretch = 1 / max(cos(latitude), 0.22)
                        for x in 0..<width {
                            let dx = (h(x + 1, y) - h(x - 1, y)) * stretch
                            let dy = h(x, down) - h(x, up)
                            // Tangent space: +x east, +y north, +z out of the ground. Rows run south, so dy flips.
                            var n = SIMD3<Float>(-dx, dy, 1)
                            n = simd_normalize(n)
                            let p = outPointer + (y * width + x) * 4
                            p[0] = UInt8(max(0, min(255, (n.x * 0.5 + 0.5) * 255)))
                            p[1] = UInt8(max(0, min(255, (n.y * 0.5 + 0.5) * 255)))
                            p[2] = UInt8(max(0, min(255, (n.z * 0.5 + 0.5) * 255)))
                        }
                    }
                }
            }
        }
        let data = Data(output) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Style picker

/// Globe colours: a look for sea and land, a colour for the places you've been, and how strong the relief is.
struct GlobeStylePicker: View {
    @AppStorage(GlobeAppearance.themeKey) private var themeID = "auto"
    @AppStorage(GlobeAppearance.accentKey) private var accentID = "amber"
    @AppStorage(GlobeAppearance.reliefKey) private var relief = 1
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { Color(uiColor: UIColor(sketchHex: (GlobeAccent.all.first { $0.id == accentID } ?? GlobeAccent.all[0]).hex)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    swatch(id: "auto", name: "Auto", theme: scheme == .dark ? .ink : .paper)
                    ForEach(GlobeTheme.all) { swatch(id: $0.id, name: $0.name, theme: $0) }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
            .scrollClipDisabled()
            VStack(alignment: .leading, spacing: 8) {
                Text("Visited colour").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(GlobeAccent.all) { item in
                        let on = item.id == accentID
                        Button { accentID = item.id } label: {
                            Circle().fill(Color(uiColor: UIColor(sketchHex: item.hex))).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                                .padding(5)
                                .overlay(Circle().strokeBorder(on ? Color.primary : .clear, lineWidth: 2))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).accessibilityLabel(item.name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Picker("Relief", selection: $relief) { Text("Flat").tag(0); Text("Natural").tag(1); Text("Bold").tag(2) }
                .pickerStyle(.segmented).accessibilityLabel("Mountain relief")
        }
        .sensoryFeedback(.selection, trigger: themeID + accentID)
    }

    private func swatch(id: String, name: String, theme: GlobeTheme) -> some View {
        let on = themeID == id
        return Button { themeID = id } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(uiColor: UIColor(sketchHex: theme.ocean)))
                    // A little continent in the theme's land colour with a visited patch.
                    Circle().fill(Color(uiColor: UIColor(sketchHex: theme.land))).frame(width: 30, height: 24).offset(x: -5, y: -6)
                    Circle().fill(Color(uiColor: UIColor(sketchHex: theme.land))).frame(width: 20, height: 22).offset(x: 9, y: 9)
                    Circle().fill(accent).frame(width: 13, height: 13).offset(x: -3, y: -4)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.35)],
                                                 center: UnitPoint(x: 0.3, y: 0.25), startRadius: 2, endRadius: 44))
                }
                .frame(width: 52, height: 52).clipShape(Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                .padding(4)
                .overlay(Circle().strokeBorder(on ? Color.primary : .clear, lineWidth: 2))
                Text(name).font(Sketch.text(12, on ? "Bold" : "SemiBold", relativeTo: .caption))
                    .foregroundStyle(on ? .primary : .secondary)
            }
            .frame(minWidth: 62)
        }
        .buttonStyle(.plain).accessibilityLabel("\(name) globe").accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension UIColor {
    /// This colour moved towards another by `amount` (0 keeps it, 1 replaces it).
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1); other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
