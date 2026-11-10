import SwiftUI
import SceneKit
import MapKit
import simd

// MARK: - Globe texture
//
// A world snapshot from Apple Maps (Web Mercator) gets the visited countries and
// cities painted on in map points, then is re-projected row by row to the
// equirectangular image a sphere expects. Snapshots are cached per appearance.

struct GlobeTextureKey: Hashable {
    let dark: Bool
    let satellite: Bool
    let style: String
}

actor GlobeTextureBuilder {
    static let shared = GlobeTextureBuilder()
    /// A world snapshot plus the linear map from map points to its pixels.
    struct Base { let image: CGImage; let ax: Double; let bx: Double; let ay: Double; let by: Double; var equirect = false }
    private var bases: [String: Base] = [:]
    private var textures: [String: UIImage] = [:]
    private let side = 4096

    /// `visitedCodes` colours those countries from the bundled outlines (no download); `shapes` adds
    /// per-country colours for the heat, continent and last-visit modes.
    func texture(key: GlobeTextureKey, shapes: CountryShapesOverlay?, visits: [VisitedPlace], visitedCodes: Set<String> = []) async -> UIImage? {
        let look = GlobeAppearance.stored
        let cacheKey = "\(key.dark)|\(key.satellite)|\(key.style)|\(look.cacheID)|\(visitedCodes.sorted().joined())"
        if let cached = textures[cacheKey] { return cached }
        let theme = look.theme(dark: key.dark)
        let base = key.satellite ? earthImage(dark: key.dark, realistic: true) : nil
        guard let image = Self.compose(base: base, width: side, shapes: shapes, visits: visits, dark: key.dark,
                                       theme: theme, accent: UIColor(sketchHex: look.accent.hex), visitedCodes: visitedCodes) else { return nil }
        GlobeSkin.attach(GlobeSkin(normal: look.relief == 0 ? nil : GlobeRelief.normalMap, relief: look.reliefIntensity * (key.satellite ? 0.8 : 1),
                                   glow: key.satellite ? UIColor(red: 0.55, green: 0.75, blue: 1, alpha: 1) : UIColor(sketchHex: theme.glow).mixed(with: .black, amount: theme.light ? 0.35 : 0.6),
                                   light: theme.light && !key.satellite), to: image)
        // Each texture is 32 MB; keep only the last few.
        if textures.count >= 3 { textures.removeAll() }
        textures[cacheKey] = image
        return image
    }

    /// NASA's Blue Marble (public domain, bundled as globe-earth.jpg): already equirectangular, so
    /// nothing is stretched at the poles. Realistic as it is, or toned to a black-and-grey atlas
    /// that lets visited countries carry the colour.
    private func earthImage(dark: Bool, realistic: Bool) -> Base? {
        let name = "earth-\(realistic ? "real" : "mono")-\(dark ? "dark" : "light")"
        if let cached = bases[name] { return cached }
        guard let url = Bundle.main.url(forResource: "globe-earth", withExtension: "jpg"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let image = realistic ? (Self.realisticTone(source) ?? source) : (Self.monoTone(source, dark: dark) ?? source)
        let base = Base(image: image, ax: 0, bx: 0, ay: 0, by: 0, equirect: true)
        bases[name] = base
        return base
    }

    /// A touch more contrast and warmth than the raw photo.
    static func realisticTone(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let out = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.12, kCIInputContrastKey: 1.08, kCIInputBrightnessKey: 0.02])
        return CIContext().createCGImage(out, from: input.extent)
    }

    /// A calm two-tone base for coloured countries. Land and water are told apart by colour (water is blue-dominant),
    /// not brightness, so dark forests stay land and all of Europe reads as land; a little relief is kept.
    static func monoTone(_ image: CGImage, dark: Bool) -> CGImage? {
        let input = CIImage(cgImage: image)
        let sea = dark ? CIColor(red: 0.08, green: 0.1, blue: 0.13) : CIColor(red: 0.72, green: 0.8, blue: 0.86)
        let land = dark ? CIColor(red: 0.4, green: 0.4, blue: 0.38) : CIColor(red: 0.97, green: 0.95, blue: 0.9)
        // landness = 0.3r + g - 0.9b, stretched: water < 0, forest ~0.9, desert/ice ~1.
        let landness = CIVector(x: 1.8, y: 6, z: -5.4, w: 0)
        let mask = input
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": landness, "inputGVector": landness, "inputBVector": landness,
                                                          "inputBiasVector": CIVector(x: 0.1, y: 0.1, z: 0.1, w: 0)])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2]).cropped(to: input.extent)
        let flat = mask.applyingFilter("CIFalseColor", parameters: ["inputColor0": sea, "inputColor1": land])
        // Relief: the photo's brightness, softly multiplied in.
        let relief = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 0.55,
                                                                        kCIInputBrightnessKey: dark ? 0.25 : 0.42])
        let out = flat.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: relief.applyingFilter("CIColorClamp")])
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: dark ? 0.02 : 0.06])
        return CIContext().createCGImage(out, from: input.extent)
    }

    private func baseImage(dark: Bool, satellite: Bool) async -> Base? {
        if let earth = earthImage(dark: dark, realistic: satellite) { return earth }
        let name = "globe-base-\(dark ? "dark" : "light")-\(satellite ? "sat" : "atlas")-v7"
        if let cached = bases[name] { return cached }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let imageURL = folder.appendingPathComponent(name + ".png"), metaURL = folder.appendingPathComponent(name + ".json")
        if let data = try? Data(contentsOf: imageURL), let image = UIImage(data: data)?.cgImage,
           let meta = try? JSONDecoder().decode([Double].self, from: Data(contentsOf: metaURL)), meta.count == 4 {
            let base = Base(image: image, ax: meta[0], bx: meta[1], ay: meta[2], by: meta[3]); bases[name] = base; return base
        }
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect.world
        options.size = CGSize(width: 1024, height: 1024)
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        options.preferredConfiguration = MKImageryMapConfiguration()   // no labels on a globe
        guard let snapshot = try? await MKMapSnapshotter(options: options).start(), var image = snapshot.image.cgImage else { return nil }
        // The snapshotter may frame the world differently; measure it.
        let a = snapshot.point(for: CLLocationCoordinate2D(latitude: 60, longitude: -120))
        let b = snapshot.point(for: CLLocationCoordinate2D(latitude: -40, longitude: 100))
        let ma = MKMapPoint(CLLocationCoordinate2D(latitude: 60, longitude: -120)), mb = MKMapPoint(CLLocationCoordinate2D(latitude: -40, longitude: 100))
        let scale = Double(snapshot.image.scale)
        let ax = (Double(b.x - a.x) * scale) / (mb.x - ma.x), bx = Double(a.x) * scale - ax * ma.x
        let ay = (Double(b.y - a.y) * scale) / (mb.y - ma.y), by = Double(a.y) * scale - ay * ma.y
        if !satellite, let toned = Self.atlasTone(image, dark: dark) { image = toned }
        if let png = UIImage(cgImage: image).pngData() { try? png.write(to: imageURL, options: .atomic) }
        try? JSONEncoder().encode([ax, bx, ay, by]).write(to: metaURL, options: .atomic)
        let base = Base(image: image, ax: ax, bx: bx, ay: ay, by: by)
        bases[name] = base
        return base
    }

    /// Satellite imagery reduced to a warm monochrome "atlas", so visited
    /// countries carry the colour.
    static func atlasTone(_ image: CGImage, dark: Bool) -> CGImage? {
        let input = CIImage(cgImage: image)
        let sea = dark ? CIColor(red: 0.07, green: 0.09, blue: 0.12) : CIColor(red: 0.74, green: 0.81, blue: 0.84)
        let land = dark ? CIColor(red: 0.36, green: 0.36, blue: 0.33) : CIColor(red: 0.98, green: 0.95, blue: 0.89)
        // Grey, then stretch so dark sea sits near 0 and land near 1 before colouring.
        let stretch = CIVector(x: 3.2, y: 0, z: 0, w: 0)
        let toned = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": stretch, "inputGVector": CIVector(x: 0, y: 3.2, z: 0, w: 0),
                                                         "inputBVector": CIVector(x: 0, y: 0, z: 3.2, w: 0), "inputBiasVector": CIVector(x: -0.32, y: -0.32, z: -0.32, w: 0)])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIFalseColor", parameters: ["inputColor0": sea, "inputColor1": land])
        return CIContext().createCGImage(toned, from: input.extent)
    }

    static func compose(base: Base?, width: Int, shapes: CountryShapesOverlay?, visits: [VisitedPlace], dark: Bool,
                        theme: GlobeTheme, accent: UIColor, visitedCodes: Set<String>) -> UIImage? {
        let height = width / 2
        let realistic = base != nil
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        // Equirectangular canvas: x = longitude, y = latitude, both linear.
        func px(_ lon: Double) -> Double { (lon + 180) / 360 * Double(width) }
        func py(_ lat: Double) -> Double { (90 - lat) / 180 * Double(height) }
        let scale = Double(width) / 4096
        // What each highlighted country is painted with. The plain "visited" look uses the chosen colour;
        // the other modes keep their own palette and strength.
        var colours: [String: UIColor] = Dictionary(visitedCodes.map { ($0.uppercased(), accent) }, uniquingKeysWith: { a, _ in a })
        var fallback: [(CGPath, UIColor)] = []
        if let shapes, shapes.style.fill {
            let land = UIColor(sketchHex: theme.land)
            for entry in shapes.entries {
                let plain = shapes.style.mode == .visited
                let strength = min(1, max(0.25, (entry.fill.alpha - 0.14) / 0.42))
                let own = UIColor(cgColor: entry.stroke).withAlphaComponent(1)
                let colour = plain ? accent : (realistic ? own : land.mixed(with: own, amount: 0.3 + 0.7 * strength))
                let code = entry.geometry.code.uppercased()
                if GlobeBorders.byCode[code] != nil { colours[code] = colour }
                else { fallback.append((Self.equirect(entry.geometry.paths[1], px: px, py: py), colour)) }
            }
        }
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { renderer in
            let ctx = renderer.cgContext
            UIColor(sketchHex: theme.ocean).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let paths = GlobeBorders.countries.map { ($0, $0.path(width: width, height: height)) }
            if let base {
                // CoreGraphics draws images bottom-up; flip so north stays up.
                ctx.saveGState(); ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .high
                ctx.draw(base.image, in: CGRect(x: 0, y: 0, width: width, height: height))
                ctx.restoreGState()
            } else {
                ctx.setFillColor(UIColor(sketchHex: theme.land).cgColor)
                for (_, path) in paths { ctx.addPath(path) }
                ctx.fillPath(using: .winding)
                // Hairline borders; the relief adds the groove.
                ctx.setStrokeColor(UIColor(sketchHex: theme.border).withAlphaComponent(theme.light ? 0.5 : 0.75).cgColor)
                ctx.setLineWidth(1.3 * scale); ctx.setLineJoin(.round)
                for (_, path) in paths { ctx.addPath(path) }
                ctx.strokePath()
            }
            // Visited countries: solid colour that sits a little above the ground (a soft shadow to the south-east).
            var highlighted: [(CGPath, UIColor)] = fallback
            for (country, path) in paths { if let code = country.code, let colour = colours[code] { highlighted.append((path, colour)) } }
            if !highlighted.isEmpty {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 5 * scale, height: 6 * scale), blur: 9 * scale, color: UIColor.black.withAlphaComponent(theme.light ? 0.28 : 0.55).cgColor)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                for (path, colour) in highlighted {
                    ctx.setFillColor(colour.withAlphaComponent(realistic ? 0.72 : 1).cgColor)
                    ctx.addPath(path); ctx.fillPath(using: .evenOdd)
                }
                ctx.endTransparencyLayer()
                ctx.restoreGState()
                ctx.setLineJoin(.round); ctx.setLineWidth(1.6 * scale)
                for (path, colour) in highlighted {
                    ctx.setStrokeColor(colour.darker.withAlphaComponent(0.9).cgColor); ctx.addPath(path); ctx.strokePath()
                }
            }
            let ink = UIColor(sketchHex: 0x1E1C19)
            // Only for still images (share cards); the live globe draws real 3D pins instead. A circle on this
            // flat canvas shrinks sideways on the sphere by cos(latitude), so it is drawn that much wider.
            for visit in visits where !visit.isCountry {
                let c = CGPoint(x: px(visit.longitude), y: py(visit.latitude))
                let widen = 1 / max(0.25, cos(visit.latitude * .pi / 180))
                func dot(_ radius: Double, _ color: CGColor) {
                    ctx.setFillColor(color)
                    ctx.fillEllipse(in: CGRect(x: c.x - radius * scale * widen, y: c.y - radius * scale, width: 2 * radius * scale * widen, height: 2 * radius * scale))
                }
                dot(5, UIColor.white.cgColor)   // halo
                dot(3, (visit.isLived ? UIColor(sketchHex: BeenLook.livedHex) : ink).cgColor)
            }
        }
        return canvas
    }

    /// Draws each output row from the matching Mercator row of the snapshot.
    private static func reproject(_ base: Base, into ctx: CGContext, width: Int, height: Int) {
        let left = base.bx, right = base.ax * MKMapSize.world.width + base.bx
        for y in 0..<height {
            let lat = 90 - (Double(y) + 0.5) / Double(height) * 180
            guard abs(lat) < 85 else { continue }
            let sy = base.ay * MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: 0)).y + base.by
            guard sy >= 0, sy < Double(base.image.height),
                  let row = base.image.cropping(to: CGRect(x: left, y: floor(sy), width: right - left, height: 1)) else { continue }
            ctx.draw(row, in: CGRect(x: 0, y: CGFloat(y), width: CGFloat(width), height: 1.0))
        }
    }

    private static func equirect(_ path: CGPath, px: @escaping (Double) -> Double, py: @escaping (Double) -> Double) -> CGPath {
        let out = CGMutablePath()
        path.applyWithBlock { element in
            let e = element.pointee
            func convert(_ p: CGPoint) -> CGPoint {
                let c = MKMapPoint(x: Double(p.x), y: Double(p.y)).coordinate
                var lon = c.longitude
                if p.x < 0 { lon -= 360 } else if Double(p.x) > MKMapSize.world.width { lon += 360 }
                return CGPoint(x: px(lon), y: py(c.latitude))
            }
            switch e.type {
            case .moveToPoint: out.move(to: convert(e.points[0]))
            case .addLineToPoint: out.addLine(to: convert(e.points[0]))
            case .closeSubpath: out.closeSubpath()
            default: break
            }
        }
        return out
    }
}

// MARK: - Scene

/// Places and routes shown on top of the globe.
struct GlobeOverlay: Equatable {
    struct Pin: Equatable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        var home = false
        /// `.dot` is a glowing bead (Where next); `.city` and `.lived` are small standing map pins.
        enum Style { case dot, city, lived }
        var style = Style.dot
        static func == (a: Pin, b: Pin) -> Bool { a.id == b.id && a.home == b.home && a.style == b.style && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude }
    }
    var pins: [Pin] = []
    /// Each route is drawn as great-circle arcs between its points, in order.
    var routes: [[CLLocationCoordinate2D]] = []
    var selected: String?
    var color = UIColor(sketchHex: 0xF0A83D)
    /// How far arcs rise at their middle, in globe radii.
    var lift: Float = 0.1

    static func == (a: GlobeOverlay, b: GlobeOverlay) -> Bool {
        a.pins == b.pins && a.selected == b.selected && a.color == b.color && a.lift == b.lift && a.routes.count == b.routes.count
            && zip(a.routes, b.routes).allSatisfy { x, y in x.count == y.count && zip(x, y).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude } }
    }
}

/// A spinnable globe. Drag to turn it, pinch to zoom; `focus` turns it to a place.
struct BeenGlobe3DView: UIViewRepresentable {
    let texture: UIImage?
    let focus: CLLocationCoordinate2D?
    let focusID: UUID
    /// Camera distance for the focus: 4.9 shows the whole globe, 2.4 is as close as it goes.
    var zoom: Float? = nil
    let dark: Bool
    let reduceMotion: Bool
    /// Tapping the globe reports the place under the finger (for picking countries).
    var onTap: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Where the globe came to rest: the point facing you and the camera distance (4.9 = whole globe, 2.4 = closest).
    var onSettle: ((CLLocationCoordinate2D, Float) -> Void)? = nil

    /// Pins and routes drawn on the surface (Where next, journeys).
    var overlay: GlobeOverlay? = nil

    func makeCoordinator() -> GlobeSceneController { GlobeSceneController() }
    func makeUIView(context: Context) -> SCNView {
        let view = context.coordinator.makeView(dark: dark)
        context.coordinator.onTap = onTap
        context.coordinator.onSettle = onSettle
        context.coordinator.update(texture: texture, dark: dark)
        context.coordinator.show(overlay)
        context.coordinator.focus(on: focus ?? .init(latitude: 35, longitude: 15), zoom: zoom, animated: false)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.onTap = onTap
        context.coordinator.onSettle = onSettle
        context.coordinator.update(texture: texture, dark: dark)
        context.coordinator.show(overlay)
        if context.coordinator.lastFocus != focusID {
            context.coordinator.lastFocus = focusID
            if let focus { context.coordinator.focus(on: focus, zoom: zoom, animated: !reduceMotion) }
        }
    }
}

final class GlobeSceneController: NSObject {
    let scene = SCNScene()
    let tilt = SCNNode()
    let spin = SCNNode()
    let globe = SCNNode()
    let cameraNode = SCNNode()
    var lastFocus: UUID?
    var reduceMotion = false
    var onTap: ((CLLocationCoordinate2D) -> Void)?
    var onSettle: ((CLLocationCoordinate2D, Float) -> Void)?
    private var reported: (Float, Float, Float) = (.nan, .nan, .nan)
    private weak var texture: UIImage?
    private var atmosphere: SCNNode?
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var velocity = CGPoint.zero
    private var displayLink: CADisplayLink?
    private var lastInteraction = Date.distantPast

    func makeView(dark: Bool) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 120
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.mipFilter = .linear
        material.diffuse.wrapS = .repeat
        material.specular.contents = UIColor(white: 0.18, alpha: 1)   // a soft sheen, not plastic
        material.shininess = 0.25
        sphere.firstMaterial = material
        globe.geometry = sphere
        // A thin atmosphere: brighter at the rim (Fresnel), invisible facing the camera.
        let air = SCNSphere(radius: 1.035); air.segmentCount = 96
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = UIColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)
        glow.isDoubleSided = false
        glow.writesToDepthBuffer = false
        glow.blendMode = .add
        glow.shaderModifiers = [.fragment: """
        float rim = 1.0 - max(dot(normalize(_surface.normal), normalize(_surface.view)), 0.0);
        _output.color.rgb *= pow(rim, 3.0) * 0.9;
        """]
        air.firstMaterial = glow
        let atmosphere = SCNNode(geometry: air)
        self.atmosphere = atmosphere
        tilt.addChildNode(atmosphere)
        // SceneKit's sphere puts texture u = 0.75 (longitude 90°E) at +Z; this turns longitude 0 to face the camera.
        // Measured with GlobeTapProbe: focusing longitude λ must put λ, not λ + 90°, under the screen centre.
        globe.eulerAngles.y = 0
        spin.addChildNode(globe); tilt.addChildNode(spin); scene.rootNode.addChildNode(tilt)
        let camera = SCNCamera(); camera.fieldOfView = 34; camera.projectionDirection = .horizontal; camera.zNear = 0.1
        cameraNode.camera = camera; cameraNode.position = SCNVector3(0, 0, 4.9)
        scene.rootNode.addChildNode(cameraNode)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 1150
        key.eulerAngles = SCNVector3(-0.5, -0.6, 0); scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient; fill.light?.intensity = 340
        scene.rootNode.addChildNode(fill)
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        let link = CADisplayLink(target: WeakTick(self), selector: #selector(WeakTick.fire))
        link.add(to: .main, forMode: .common); displayLink = link
        return view
    }

    func update(texture: UIImage?, dark: Bool) {
        guard texture !== self.texture else { return }
        self.texture = texture
        globe.geometry?.firstMaterial?.diffuse.contents = texture ?? UIColor(sketchHex: GlobeAppearance.stored.theme(dark: dark).ocean)
        // Relief and glow travel with the texture (see GlobeSkin).
        let skin = GlobeSkin.of(texture)
        if let material = globe.geometry?.firstMaterial {
            material.normal.contents = skin?.normal
            material.normal.intensity = skin?.relief ?? 0
            material.normal.mipFilter = .linear; material.normal.wrapS = .repeat
            material.diffuse.maxAnisotropy = 8; material.normal.maxAnisotropy = 8
        }
        if let skin { atmosphere?.geometry?.firstMaterial?.diffuse.contents = skin.glow }
        // Pins pick their contrast from the globe under them.
        let overlay = shownOverlay; shownOverlay = nil; show(overlay)
    }

    // MARK: Pins and routes

    private var overlayNode = SCNNode()
    private var shownOverlay: GlobeOverlay?

    /// A point on the unit globe. With the spin at zero, longitude 0 faces the camera (+Z) and east is +X.
    static func position(_ c: CLLocationCoordinate2D, radius: Float = 1) -> SCNVector3 {
        let lat = Float(c.latitude * .pi / 180), lon = Float(c.longitude * .pi / 180)
        return SCNVector3(radius * cos(lat) * sin(lon), radius * sin(lat), radius * cos(lat) * cos(lon))
    }

    func show(_ overlay: GlobeOverlay?) {
        guard overlay != shownOverlay else { return }
        shownOverlay = overlay
        overlayNode.removeFromParentNode()
        overlayNode = SCNNode()
        guard let overlay else { return }
        func glowing(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color; m.emission.contents = color; return m
        }
        for route in overlay.routes where route.count > 1 {
            for (a, b) in zip(route, route.dropFirst()) {
                if let geometry = Self.ribbon(from: a, to: b, lift: overlay.lift) {
                    geometry.firstMaterial = glowing((GlobeSkin.of(texture)?.light ?? false) ? overlay.color.darker : overlay.color); geometry.firstMaterial?.isDoubleSided = true
                    overlayNode.addChildNode(SCNNode(geometry: geometry))
                }
            }
        }
        pinNodes = []
        let onLight = GlobeSkin.of(texture)?.light ?? false
        for pin in overlay.pins where pin.style != .dot {
            let node = Self.standingPin(lived: pin.style == .lived, onLight: onLight)
            node.position = Self.position(pin.coordinate, radius: 1.001)
            // Stand it along the surface normal.
            node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(simd_float3(node.position)))
            overlayNode.addChildNode(node); pinNodes.append(node)
        }
        scalePins()
        for pin in overlay.pins where pin.style == .dot {
            let selected = pin.id == overlay.selected
            let dot = SCNSphere(radius: selected ? 0.022 : pin.home ? 0.016 : 0.012); dot.segmentCount = 16
            let light = GlobeSkin.of(texture)?.light ?? false
            let ink = UIColor(sketchHex: 0x1E1C19)
            dot.firstMaterial = glowing(pin.home ? (light ? ink : .white) : selected ? (light ? overlay.color.darker : overlay.color)
                                        : light ? overlay.color.mixed(with: ink, amount: 0.45) : overlay.color.mixed(with: .white, amount: 0.35))
            let node = SCNNode(geometry: dot); node.position = Self.position(pin.coordinate, radius: 1.004)
            overlayNode.addChildNode(node)
            if selected {
                // A soft halo that breathes, so the chosen place is easy to find.
                let halo = SCNSphere(radius: 0.04); halo.segmentCount = 16
                halo.firstMaterial = glowing(overlay.color.withAlphaComponent(0.28)); halo.firstMaterial?.blendMode = .add
                halo.firstMaterial?.writesToDepthBuffer = false
                let haloNode = SCNNode(geometry: halo); haloNode.position = node.position
                if !reduceMotion {
                    haloNode.runAction(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.9), .scale(to: 1, duration: 0.9)])))
                }
                overlayNode.addChildNode(haloNode)
            }
        }
        globe.addChildNode(overlayNode)
        lastInteraction = Date()
    }

    private var pinNodes: [SCNNode] = []
    private static var pinParts: [String: SCNGeometry] = [:]

    /// A small map pin: a round head on a stem, lit by the scene so it reads as an object, not a painted dot.
    /// Places lived in are taller, green, and stand on a ring.
    private static func standingPin(lived: Bool, onLight: Bool) -> SCNNode {
        func part(_ name: String, _ make: () -> SCNGeometry) -> SCNGeometry {
            if let cached = pinParts[name] { return cached }
            let geometry = make(); pinParts[name] = geometry; return geometry
        }
        func material(_ color: UIColor, glow: CGFloat) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .blinn; m.diffuse.contents = color
            m.emission.contents = color.withAlphaComponent(1).mixed(with: .black, amount: 1 - glow)
            m.specular.contents = UIColor(white: 0.9, alpha: 1); m.shininess = 0.6
            return m
        }
        let tone = "\(lived)\(onLight)"
        let headColor = lived ? UIColor(sketchHex: BeenLook.livedHex) : onLight ? UIColor(sketchHex: 0x1E1C19) : UIColor.white
        let stemColor = onLight ? UIColor(sketchHex: 0x1E1C19) : UIColor(white: 0.92, alpha: 1)
        let height: Float = lived ? 0.046 : 0.032, radius: CGFloat = lived ? 0.0125 : 0.0088
        let node = SCNNode()
        let stem = SCNNode(geometry: part("stem\(tone)") {
            let g = SCNCone(topRadius: 0.0022, bottomRadius: 0.0004, height: CGFloat(height)); g.radialSegmentCount = 10
            g.firstMaterial = material(stemColor, glow: 0.35); return g
        })
        stem.position.y = height / 2
        let head = SCNNode(geometry: part("head\(tone)") {
            let g = SCNSphere(radius: radius); g.segmentCount = 20; g.firstMaterial = material(headColor, glow: 0.45); return g
        })
        head.position.y = height + Float(radius) * 0.7
        node.addChildNode(stem); node.addChildNode(head)
        if lived {
            let ring = SCNNode(geometry: part("ring\(tone)") {
                let g = SCNTube(innerRadius: 0.014, outerRadius: 0.019, height: 0.0012); g.radialSegmentCount = 28
                g.firstMaterial = material(headColor, glow: 0.7); return g
            })
            ring.position.y = 0.002
            node.addChildNode(ring)
        }
        return node
    }

    /// Pins keep roughly the same size on screen: they shrink as the camera comes closer.
    private func scalePins() {
        let s = max(0.55, min(1.7, Float(cameraNode.position.z) / 4.9 * 1.6))
        for node in pinNodes { node.scale = SCNVector3(s, s, s) }
    }

    /// A flat band along the great circle between two places, lifted off the surface in the middle like a flight path.
    private static func ribbon(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, lift: Float) -> SCNGeometry? {
        let points = Geo.arc(a, b, steps: 40)
        guard points.count > 2 else { return nil }
        let span = Float(Geo.km(a, b) / 6371)   // radians
        let height = lift * min(1, span / 1.2)
        var vertices: [SCNVector3] = [], indices: [Int32] = []
        for (i, point) in points.enumerated() {
            let t = Float(i) / Float(points.count - 1)
            let radius = 1.006 + height * sin(.pi * t)
            let p = simd_float3(position(point, radius: radius))
            let next = simd_float3(position(points[min(i + 1, points.count - 1)], radius: radius))
            let previous = simd_float3(position(points[max(i - 1, 0)], radius: radius))
            let side = simd_normalize(simd_cross(simd_normalize(next - previous), simd_normalize(p))) * 0.0045
            vertices.append(SCNVector3(p + side)); vertices.append(SCNVector3(p - side))
            if i > 0 { let k = Int32(i * 2); indices += [k - 2, k - 1, k, k - 1, k + 1, k] }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    func focus(on coordinate: CLLocationCoordinate2D, zoom: Float? = nil, animated: Bool) {
        let targetYaw = -Float(coordinate.longitude * .pi / 180)
        let targetPitch = Float(max(-60, min(60, coordinate.latitude)) * .pi / 180)
        // Take the short way round.
        var delta = (targetYaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        yaw += delta; pitch = targetPitch; velocity = .zero
        lastInteraction = Date()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.9 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        spin.eulerAngles.y = yaw; tilt.eulerAngles.x = pitch
        if let zoom { cameraNode.position.z = max(2.4, min(8, zoom)) }
        scalePins()
        SCNTransaction.commit()
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        let zoom = Float(cameraNode.position.z / 4.9)
        yaw += Float(translation.x) * 0.006 * zoom
        pitch = max(-1.2, min(1.2, pitch + Float(translation.y) * 0.006 * zoom))
        spin.eulerAngles.y = yaw; tilt.eulerAngles.x = pitch
        lastInteraction = Date()
        if gesture.state == .ended { velocity = gesture.velocity(in: gesture.view) } else { velocity = .zero }
    }

    /// The texture is equirectangular, so the hit's texture coordinate is longitude and latitude.
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let onTap, let view = gesture.view as? SCNView else { return }
        // The atmosphere shell sits in front of the globe; look through it.
        let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        guard let hit = hits.first(where: { $0.node === globe }) else { return }
        let uv = hit.textureCoordinates(withMappingChannel: 0)
        let longitude = Double(uv.x) * 360 - 180, latitude = 90 - Double(uv.y) * 180
        lastInteraction = Date(); velocity = .zero
        onTap(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        let z = Float(cameraNode.position.z) / Float(gesture.scale)
        cameraNode.position.z = max(2.4, min(8, z))
        scalePins()
        gesture.scale = 1
        lastInteraction = Date()
    }

    /// The point facing the camera.
    var center: CLLocationCoordinate2D {
        var lon = Double(-yaw) * 180 / .pi
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return .init(latitude: Double(pitch) * 180 / .pi, longitude: lon)
    }

    /// Inertia after a flick, then a slow idle drift.
    @objc fileprivate func tick() {
        // Report where it rests, once, after it has been still for a moment.
        let still = abs(velocity.x) <= 5 && abs(velocity.y) <= 5 && Date().timeIntervalSince(lastInteraction) > 0.45
        let z = Float(cameraNode.position.z)
        // Zoomed out (idle drift) it reports once on the way out, not every frame.
        if still, let onSettle, z < 4.2 || reported.2 < 4.2 || reported.0.isNaN, abs(reported.0 - yaw) > 0.01 || abs(reported.1 - pitch) > 0.01 || abs(reported.2 - z) > 0.02 || reported.0.isNaN {
            reported = (yaw, pitch, z)
            onSettle(center, z)
        }
        if abs(velocity.x) > 5 || abs(velocity.y) > 5 {
            yaw += Float(velocity.x) * 0.0001
            pitch = max(-1.2, min(1.2, pitch + Float(velocity.y) * 0.0001))
            velocity.x *= 0.93; velocity.y *= 0.93
            spin.eulerAngles.y = yaw; tilt.eulerAngles.x = pitch
        } else if !reduceMotion && Date().timeIntervalSince(lastInteraction) > 4 && cameraNode.position.z > 4.2 {
            // Idle drift only when looking at the whole globe; zoomed in, it holds still for adding a place.
            yaw += 0.0012
            spin.eulerAngles.y = yaw
        }
    }

    deinit { displayLink?.invalidate() }
}

/// Breaks the display link's strong reference to the controller.
private final class WeakTick: NSObject {
    weak var target: GlobeSceneController?
    init(_ target: GlobeSceneController) { self.target = target }
    @objc func fire(_ link: CADisplayLink) { if let target { target.tick() } else { link.invalidate() } }
}

// MARK: - Still image for sharing

enum GlobeSnapshot {
    /// Renders the globe facing `center` to a transparent image.
    @MainActor static func render(texture: UIImage?, center: CLLocationCoordinate2D, size: CGFloat = 900) -> UIImage? {
        let controller = GlobeSceneController()
        let view = controller.makeView(dark: true)
        controller.update(texture: texture, dark: true)
        controller.focus(on: center, animated: false)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        _ = view
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = controller.scene
        renderer.pointOfView = controller.cameraNode
        renderer.autoenablesDefaultLighting = false
        controller.scene.background.contents = UIColor.clear
        return renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
    }
}


#if DEBUG
/// `-TrippyGlobeProbe <file>`: turns the globe to known places, hit-tests points on screen and writes what comes back.
enum GlobeTapProbe {
    @MainActor static func runIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-TrippyGlobeProbe"), index + 1 < args.count else { return }
        let controller = GlobeSceneController()
        let view = controller.makeView(dark: false)
        view.frame = CGRect(x: 0, y: 0, width: 360, height: 320)
        controller.update(texture: nil, dark: false)
        var lines: [String] = []
        for (lat, lon) in [(0.0, 0.0), (42.0, 15.0), (40.0, -100.0), (-30.0, 140.0)] {
            controller.focus(on: .init(latitude: lat, longitude: lon), animated: false)
            view.layoutIfNeeded()
            for point in [CGPoint(x: 180, y: 160), CGPoint(x: 230, y: 160), CGPoint(x: 180, y: 110)] {
                let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
                let names = hits.map { $0.node === controller.globe ? "globe" : "other" }
                if let hit = hits.first(where: { $0.node === controller.globe }) {
                    let uv = hit.textureCoordinates(withMappingChannel: 0)
                    lines.append("focus \(lat),\(lon) point \(Int(point.x)),\(Int(point.y)) -> lat \(90 - Double(uv.y) * 180) lon \(Double(uv.x) * 360 - 180) hits \(names)")
                } else { lines.append("focus \(lat),\(lon) point \(point) -> no globe hit \(names)") }
            }
        }
        try? lines.joined(separator: "\n").write(toFile: args[index + 1], atomically: true, encoding: .utf8)
    }
}
#endif
