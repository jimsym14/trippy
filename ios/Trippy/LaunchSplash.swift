import SwiftUI
import UIKit

/// Full-screen animated launch banner in the style of `Brand/logo-idle.svg`:
/// the balloon mark floating over a warm sunset, drifting clouds, rolling hills
/// and a paper plane with a dashed trail. Dark mode is the same scene at night.
///
/// Everything is Core Animation, not SwiftUI animation or WebKit: the loops run
/// in the render server, so they stay smooth while the main thread is busy
/// building the app underneath, and the first frame needs no extra process.
/// Its first frame matches `LaunchScreen.storyboard` exactly (same colour, same
/// mark at the same size and centre), so the system launch screen and this view
/// read as one screen that comes alive.
struct TrippySplash: UIViewRepresentable {
    let dark: Bool
    func makeUIView(context: Context) -> TrippySplashView { TrippySplashView(dark: dark) }
    func updateUIView(_ view: TrippySplashView, context: Context) { view.setDark(dark) }
}

final class TrippySplashView: UIView {
    /// Must match the storyboard's `launch-mark` constraints.
    static let markSize = CGSize(width: 148, height: 160)

    private struct Palette {
        let background, sun, glow, cloud, trail, plane, far, mid, front, word: UIColor
        let cloudAlpha: Float
        /// Night look for dark mode. Charcoal matches the app's dark paper. DEBUG `-TrippySplashTheme dusk|forest` previews the alternatives.
        static var nightTheme: String {
            #if DEBUG
            if let theme = UserDefaults.standard.string(forKey: "TrippySplashTheme") { return theme }
            #endif
            return "charcoal"
        }
        static func make(dark: Bool) -> Palette {
            guard dark else {
                return Palette(
                    background: UIColor(hex: 0xF8F4EC), sun: UIColor(hex: 0xFFBE55), glow: UIColor(hex: 0xFFBE55, alpha: 0.30),
                    cloud: UIColor(hex: 0xFDD3C6), trail: UIColor(hex: 0xFB644F, alpha: 0.45), plane: UIColor(hex: 0xFB644F),
                    far: UIColor(hex: 0xFBD9CF), mid: UIColor(hex: 0xFCBA3D), front: UIColor(hex: 0xFB644F),
                    word: UIColor(hex: 0x102A22), cloudAlpha: 0.85)
            }
            switch nightTheme {
            case "charcoal": // the app's own dark paper, with ember hills
                return Palette(
                    background: UIColor(hex: 0x161513), sun: UIColor(hex: 0xFCBA3D), glow: UIColor(hex: 0xFB8A4F, alpha: 0.20),
                    cloud: .white, trail: UIColor(hex: 0xFFCDBD, alpha: 0.55), plane: UIColor(hex: 0xFFCDBD),
                    far: UIColor(hex: 0x231F1B), mid: UIColor(hex: 0x352620), front: UIColor(hex: 0x5A2F26),
                    word: UIColor(hex: 0xF1ECE2), cloudAlpha: 0.06)
            case "dusk": // deep blue night, warm sun
                return Palette(
                    background: UIColor(hex: 0x131A2C), sun: UIColor(hex: 0xFCBA3D), glow: UIColor(hex: 0xFB8A4F, alpha: 0.24),
                    cloud: .white, trail: UIColor(hex: 0xFFCDBD, alpha: 0.6), plane: UIColor(hex: 0xFFCDBD),
                    far: UIColor(hex: 0x1C2540), mid: UIColor(hex: 0x27304F), front: UIColor(hex: 0x3A3456),
                    word: UIColor(hex: 0xF8F3EC), cloudAlpha: 0.07)
            default: // forest
                return Palette(
                    background: UIColor(hex: 0x121F1A), sun: UIColor(hex: 0xFCBA3D), glow: UIColor(hex: 0xFCBA3D, alpha: 0.22),
                    cloud: .white, trail: UIColor(hex: 0xFFCDBD, alpha: 0.55), plane: UIColor(hex: 0xFFCDBD),
                    far: UIColor(hex: 0x1A2C25), mid: UIColor(hex: 0x213A30), front: UIColor(hex: 0x2B4A3D),
                    word: UIColor(hex: 0xF8F3EC), cloudAlpha: 0.07)
            }
        }
    }

    var dark: Bool
    private var builtSize: CGSize = .zero
    private var didIntro = false
    let scene = CALayer()
    let markView = UIImageView(image: UIImage(named: "SplashMark"))
    let wordmark = UILabel()
    var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Loading Trippy"
        accessibilityTraits = .updatesFrequently
        backgroundColor = UIColor(named: "LaunchBackground")
        layer.addSublayer(scene)
        markView.contentMode = .scaleAspectFit
        addSubview(markView)
        wordmark.text = "trippy"
        wordmark.font = UIFont(name: "PlusJakartaSans-ExtraBold", size: 42) ?? .systemFont(ofSize: 42, weight: .heavy)
        wordmark.textAlignment = .center
        wordmark.isAccessibilityElement = false
        addSubview(wordmark)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setDark(_ value: Bool) {
        guard value != dark else { return }
        dark = value
        builtSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        markView.bounds = CGRect(origin: .zero, size: Self.markSize)
        markView.center = center
        wordmark.sizeToFit()
        wordmark.center = CGPoint(x: center.x, y: center.y + Self.markSize.height / 2 + 34)
        guard size != builtSize else { return }
        builtSize = size
        build(in: size, intro: !didIntro)
        didIntro = true
    }

    // MARK: Scene

    private func build(in size: CGSize, intro: Bool) {
        let p = Palette.make(dark: dark)
        let W = size.width, H = size.height
        let compact = H < W // landscape: keep the hills low so the mark stays clear
        let horizon = H * (compact ? 0.80 : 0.76)
        if intro {
            // The storyboard follows the system appearance; the app may use its own.
            // Ease from the storyboard's colour so the hand-off never flashes.
            backgroundColor = UIColor(named: "LaunchBackground")?.resolvedColor(with: traitCollection) ?? p.background
            UIView.animate(withDuration: reduceMotion ? 0 : 0.35) { self.backgroundColor = p.background }
        } else {
            backgroundColor = p.background
        }
        wordmark.textColor = p.word
        scene.sublayers?.forEach { $0.removeFromSuperlayer() }
        scene.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let concept = Self.concept {
            buildConcept(concept, size: size, intro: intro)
            CATransaction.commit()
            floatMark()
            return
        }

        if dark { addStars(W: W, H: horizon, intro: intro) }

        // Sun (or warm moon) setting on the horizon, with a soft glow.
        let sunR = min(W, H) * 0.21
        let sunCenter = CGPoint(x: W * 0.70, y: horizon - sunR * 0.15)
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [p.glow.cgColor, p.glow.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: sunR * 6, height: sunR * 6)
        glow.position = sunCenter
        scene.addSublayer(glow)
        let sun = CAShapeLayer()
        sun.path = UIBezierPath(ovalIn: CGRect(x: -sunR, y: -sunR, width: sunR * 2, height: sunR * 2)).cgPath
        sun.fillColor = p.sun.withAlphaComponent(dark ? 0.78 : 0.92).cgColor
        sun.position = sunCenter
        scene.addSublayer(sun)

        // Clouds drifting at different speeds.
        let clouds: [(y: CGFloat, w: CGFloat, duration: Double, start: Double)] = [
            (0.15, 118, 46, 0.15), (0.27, 82, 34, 0.62), (0.36, 64, 40, 0.88), (0.60, 96, 52, 0.40)
        ]
        var cloudLayers: [CALayer] = []
        for c in clouds {
            let cloud = CAShapeLayer()
            cloud.path = Self.cloudPath(width: c.w).cgPath
            cloud.fillColor = p.cloud.cgColor
            cloud.opacity = p.cloudAlpha
            cloud.bounds = CGRect(x: 0, y: 0, width: c.w, height: c.w * 0.42)
            cloud.position = CGPoint(x: -c.w + (W + c.w * 2) * c.start, y: H * c.y)
            scene.addSublayer(cloud)
            cloudLayers.append(cloud)
            guard !reduceMotion else { continue }
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = -c.w; drift.toValue = W + c.w
            drift.duration = c.duration; drift.repeatCount = .infinity
            drift.timeOffset = c.duration * c.start
            cloud.add(drift, forKey: "drift")
        }

        // Paper plane crossing the sky above the balloon, leaving a dashed trail.
        let flight = UIBezierPath()
        flight.move(to: CGPoint(x: -30, y: H * 0.31))
        flight.addCurve(to: CGPoint(x: W + 30, y: H * 0.17),
                        controlPoint1: CGPoint(x: W * 0.30, y: H * 0.13),
                        controlPoint2: CGPoint(x: W * 0.62, y: H * 0.36))
        let trail = CAShapeLayer()
        trail.path = flight.cgPath
        trail.fillColor = nil
        trail.strokeColor = p.trail.cgColor
        trail.lineWidth = 2.5; trail.lineCap = .round; trail.lineDashPattern = [0.5, 9]
        trail.strokeEnd = 0
        scene.addSublayer(trail)
        let plane = CAShapeLayer()
        plane.path = Self.planePath().cgPath
        plane.fillColor = p.plane.cgColor
        plane.bounds = CGRect(x: -12, y: -9, width: 24, height: 18)
        plane.position = CGPoint(x: -60, y: 0)
        scene.addSublayer(plane)
        if !reduceMotion { animateFlight(plane: plane, trail: trail, path: flight.cgPath) }

        // Rolling hills, three layers of parallax. Each path is two screen widths
        // of a wave that repeats every screen width, so sliding by W loops cleanly.
        let hills: [(color: UIColor, base: CGFloat, amps: [CGFloat], duration: Double, alpha: Float)] = [
            (p.far, horizon - H * 0.035, [H * 0.040, H * 0.022, H * 0.012], 70, 1),
            (p.mid, horizon + H * 0.030, [H * 0.026, H * 0.016, H * 0.010], 44, dark ? 1 : 0.92),
            (p.front, horizon + H * 0.095, [H * 0.022, H * 0.012, H * 0.008], 28, 1)
        ]
        var hillLayers: [CALayer] = []
        for (i, h) in hills.enumerated() {
            let hill = CAShapeLayer()
            hill.path = Self.wavePath(width: W, height: H, base: h.base, amps: h.amps, phase: CGFloat(i) * 1.7).cgPath
            hill.fillColor = h.color.cgColor
            hill.opacity = h.alpha
            hill.frame = CGRect(x: 0, y: 0, width: W * 2, height: H)
            scene.addSublayer(hill)
            hillLayers.append(hill)
            guard !reduceMotion else { continue }
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = W; slide.toValue = 0
            slide.duration = h.duration; slide.repeatCount = .infinity
            hill.add(slide, forKey: "slide")
        }

        CATransaction.commit()
        floatMark()
        guard intro else { wordmark.alpha = 1; return }
        playIntro(sun: sun, glow: glow, clouds: cloudLayers, hills: hillLayers, H: H)
    }

    private func playIntro(sun: CALayer, glow: CALayer, clouds: [CALayer], hills: [CALayer], H: CGFloat) {
        let now = CACurrentMediaTime()
        func fadeIn(_ layer: CALayer, delay: Double, duration: Double = 0.5) {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = layer.opacity
            a.beginTime = now + delay; a.duration = duration; a.fillMode = .backwards
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(a, forKey: "introFade")
        }
        func rise(_ layer: CALayer, by distance: CGFloat, delay: Double) {
            let a = CASpringAnimation(keyPath: "transform.translation.y")
            a.fromValue = distance; a.toValue = 0
            a.damping = 18; a.stiffness = 120; a.mass = 1
            a.beginTime = now + delay; a.duration = a.settlingDuration; a.fillMode = .backwards
            layer.add(a, forKey: "introRise")
        }
        if reduceMotion {
            ([sun, glow] + clouds + hills).forEach { fadeIn($0, delay: 0, duration: 0.3) }
        } else {
            for (i, hill) in hills.enumerated() { rise(hill, by: H * 0.32, delay: 0.04 * Double(i)); fadeIn(hill, delay: 0.04 * Double(i), duration: 0.25) }
            rise(sun, by: H * 0.10, delay: 0.10); fadeIn(sun, delay: 0.10, duration: 0.45)
            fadeIn(glow, delay: 0.25, duration: 0.8)
            for (i, cloud) in clouds.enumerated() { fadeIn(cloud, delay: 0.15 + 0.07 * Double(i), duration: 0.7) }
        }
        wordmark.alpha = 0
        wordmark.transform = reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: 10)
        UIView.animate(withDuration: 0.5, delay: 0.12, options: [.curveEaseOut]) {
            self.wordmark.alpha = 1
            self.wordmark.transform = .identity
        }
    }

    /// Gentle bob and sway; starts from the storyboard's resting position.
    func floatMark() {
        markView.layer.removeAnimation(forKey: "bob")
        markView.layer.removeAnimation(forKey: "sway")
        guard !reduceMotion else { return }
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, -9, 0, 3, 0]
        bob.keyTimes = [0, 0.4, 0.7, 0.85, 1]
        bob.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        bob.duration = 3.6; bob.repeatCount = .infinity
        markView.layer.add(bob, forKey: "bob")
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let tilt = 1.8 * Double.pi / 180
        sway.values = [0, tilt, 0, -tilt, 0]
        sway.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        sway.duration = 5.2; sway.repeatCount = .infinity
        markView.layer.add(sway, forKey: "sway")
    }

    private func animateFlight(plane: CALayer, trail: CAShapeLayer, path: CGPath) {
        let cycle = 8.0, flightTime = 4.2
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path; move.calculationMode = .paced; move.rotationMode = .rotateAuto
        move.duration = flightTime
        move.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut)]
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0; draw.toValue = 1; draw.duration = flightTime
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        draw.fillMode = .forwards
        let erase = CABasicAnimation(keyPath: "strokeStart")
        erase.fromValue = 0; erase.toValue = 1
        erase.beginTime = 1.4; erase.duration = flightTime
        erase.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        erase.fillMode = .both
        let planeGroup = CAAnimationGroup()
        planeGroup.animations = [move]; planeGroup.duration = cycle; planeGroup.repeatCount = .infinity
        let trailGroup = CAAnimationGroup()
        trailGroup.animations = [draw, erase]; trailGroup.duration = cycle; trailGroup.repeatCount = .infinity
        // First pass starts shortly after the intro.
        let begin = CACurrentMediaTime() + 0.5
        planeGroup.beginTime = begin; trailGroup.beginTime = begin
        plane.add(planeGroup, forKey: "flight")
        trail.add(trailGroup, forKey: "trail")
    }

    func addStars(W: CGFloat, H: CGFloat, intro: Bool) {
        // Fixed pseudo-random field so the sky looks the same every launch.
        var seed: UInt64 = 0x7121_9FA3
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        for _ in 0..<34 {
            let r = 0.8 + next() * 1.3
            let star = CAShapeLayer()
            star.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)).cgPath
            star.fillColor = UIColor(hex: 0xFFF4EA).cgColor
            star.position = CGPoint(x: next() * W, y: 24 + next() * (H * 0.82))
            star.opacity = Float(0.35 + next() * 0.45)
            scene.addSublayer(star)
            guard !reduceMotion else { continue }
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = star.opacity; twinkle.toValue = star.opacity * 0.25
            twinkle.duration = 1.4 + Double(next()) * 2.2; twinkle.autoreverses = true; twinkle.repeatCount = .infinity
            twinkle.timeOffset = Double(next()) * twinkle.duration
            star.add(twinkle, forKey: "twinkle")
        }
    }

    // MARK: Paths

    private static func wavePath(width W: CGFloat, height H: CGFloat, base: CGFloat, amps: [CGFloat], phase: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let steps = 96
        path.move(to: CGPoint(x: 0, y: H))
        for i in 0...steps {
            let x = W * 2 * CGFloat(i) / CGFloat(steps)
            let t = x / W * 2 * .pi
            var y = base
            for (k, a) in amps.enumerated() { y -= a * sin(t * CGFloat(k + 1) + phase * CGFloat(k + 1)) }
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: W * 2, y: H))
        path.close()
        return path
    }

    static func cloudPath(width w: CGFloat) -> UIBezierPath {
        let h = w * 0.42
        let path = UIBezierPath(roundedRect: CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45), cornerRadius: h * 0.225)
        path.append(UIBezierPath(ovalIn: CGRect(x: w * 0.14, y: h * 0.25, width: w * 0.34, height: w * 0.34)))
        path.append(UIBezierPath(ovalIn: CGRect(x: w * 0.38, y: 0, width: w * 0.40, height: w * 0.40)))
        path.append(UIBezierPath(ovalIn: CGRect(x: w * 0.64, y: h * 0.36, width: w * 0.26, height: w * 0.26)))
        path.usesEvenOddFillRule = false
        return path
    }

    /// Paper plane pointing along +x, centred on the origin.
    static func planePath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 12, y: 0))
        path.addLine(to: CGPoint(x: -11, y: -9))
        path.addLine(to: CGPoint(x: -5, y: 0))
        path.addLine(to: CGPoint(x: -11, y: 9))
        path.close()
        return path
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
