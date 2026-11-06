import SwiftUI
import SceneKit
import MapKit

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
    struct Base { let image: CGImage; let ax: Double; let bx: Double; let ay: Double; let by: Double }
    private var bases: [String: Base] = [:]
    private var textures: [GlobeTextureKey: UIImage] = [:]
    private let side = 2048

    func texture(key: GlobeTextureKey, shapes: CountryShapesOverlay?, visits: [VisitedPlace]) async -> UIImage? {
        if let cached = textures[key] { return cached }
        let base = await baseImage(dark: key.dark, satellite: key.satellite)
        let image = Self.compose(base: base, width: side, shapes: shapes, visits: visits, dark: key.dark)
        if textures.count > 6 { textures.removeAll() }
        textures[key] = image
        return image
    }

    private func baseImage(dark: Bool, satellite: Bool) async -> Base? {
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

    static func compose(base: Base?, width: Int, shapes: CountryShapesOverlay?, visits: [VisitedPlace], dark: Bool) -> UIImage? {
        let height = width / 2
        let ocean = dark ? UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1) : UIColor(red: 0.74, green: 0.81, blue: 0.84, alpha: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        // Equirectangular canvas: x = longitude, y = latitude, both linear.
        func px(_ lon: Double) -> Double { (lon + 180) / 360 * Double(width) }
        func py(_ lat: Double) -> Double { (90 - lat) / 180 * Double(height) }
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { renderer in
            let ctx = renderer.cgContext
            ocean.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if let base { Self.reproject(base, into: ctx, width: width, height: height) }
            if let shapes {
                // Country paths are in map points; convert each vertex to lon/lat.
                for entry in shapes.entries {
                    let path = Self.equirect(entry.geometry.paths[1], px: px, py: py)
                    ctx.addPath(path); ctx.setFillColor(entry.fill.copy(alpha: min(0.85, entry.fill.alpha + 0.3)) ?? entry.fill)
                    ctx.fillPath(using: .evenOdd)
                    ctx.addPath(path); ctx.setStrokeColor(entry.stroke); ctx.setLineWidth(1.4); ctx.strokePath()
                }
            }
            for visit in visits {
                let c = CGPoint(x: px(visit.longitude), y: py(visit.latitude))
                ctx.setFillColor(UIColor.white.cgColor); ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
                ctx.setFillColor(CountryPalette.amber.darker.cgColor); ctx.fillEllipse(in: CGRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2))
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

/// A spinnable globe. Drag to turn it, pinch to zoom; `focus` turns it to a place.
struct BeenGlobe3DView: UIViewRepresentable {
    let texture: UIImage?
    let focus: CLLocationCoordinate2D?
    let focusID: UUID
    let dark: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> GlobeSceneController { GlobeSceneController() }
    func makeUIView(context: Context) -> SCNView {
        let view = context.coordinator.makeView(dark: dark)
        context.coordinator.update(texture: texture, dark: dark)
        context.coordinator.focus(on: focus ?? .init(latitude: 35, longitude: 15), animated: false)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.update(texture: texture, dark: dark)
        if context.coordinator.lastFocus != focusID {
            context.coordinator.lastFocus = focusID
            if let focus { context.coordinator.focus(on: focus, animated: !reduceMotion) }
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
    private weak var texture: UIImage?
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
        material.lightingModel = .lambert
        material.diffuse.mipFilter = .linear
        material.diffuse.wrapS = .repeat
        sphere.firstMaterial = material
        globe.geometry = sphere
        // SceneKit's sphere starts its texture at -X; this turns longitude 0 to face +Z.
        globe.eulerAngles.y = -.pi / 2
        spin.addChildNode(globe); tilt.addChildNode(spin); scene.rootNode.addChildNode(tilt)
        let camera = SCNCamera(); camera.fieldOfView = 34; camera.projectionDirection = .horizontal; camera.zNear = 0.1
        cameraNode.camera = camera; cameraNode.position = SCNVector3(0, 0, 4.9)
        scene.rootNode.addChildNode(cameraNode)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.5, -0.6, 0); scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .ambient; fill.light?.intensity = 520
        scene.rootNode.addChildNode(fill)
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        let link = CADisplayLink(target: WeakTick(self), selector: #selector(WeakTick.fire))
        link.add(to: .main, forMode: .common); displayLink = link
        return view
    }

    func update(texture: UIImage?, dark: Bool) {
        guard texture !== self.texture else { return }
        self.texture = texture
        globe.geometry?.firstMaterial?.diffuse.contents = texture ?? (dark ? UIColor(white: 0.18, alpha: 1) : UIColor(red: 0.8, green: 0.87, blue: 0.9, alpha: 1))
    }

    func focus(on coordinate: CLLocationCoordinate2D, animated: Bool) {
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

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        let z = Float(cameraNode.position.z) / Float(gesture.scale)
        cameraNode.position.z = max(2.4, min(8, z))
        gesture.scale = 1
        lastInteraction = Date()
    }

    /// Inertia after a flick, then a slow idle drift.
    @objc fileprivate func tick() {
        if abs(velocity.x) > 5 || abs(velocity.y) > 5 {
            yaw += Float(velocity.x) * 0.0001
            pitch = max(-1.2, min(1.2, pitch + Float(velocity.y) * 0.0001))
            velocity.x *= 0.93; velocity.y *= 0.93
            spin.eulerAngles.y = yaw; tilt.eulerAngles.x = pitch
        } else if !reduceMotion && Date().timeIntervalSince(lastInteraction) > 4 {
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
