import SwiftUI
import UIKit
import WebKit

// MARK: - Native balloon mark with hidden tap tricks

/// The balloon mark, drawn natively so it costs nothing to show anywhere.
/// It hides a few tricks for people who poke it:
/// - tap: a little hop
/// - three quick taps: loop-the-loop
/// - six quick taps: lift off, out of frame and back, with a burst
/// - press and hold: it inflates; let go and it pops back with a burst
/// None of it is advertised; VoiceOver reads it as the "trippy" logo.
struct TrippyLogo: UIViewRepresentable {
    var size: CGFloat = 34
    /// Gentle float, for places where something is in progress.
    var idle = false
    var interactive = true

    func makeUIView(context: Context) -> TrippyLogoView { TrippyLogoView() }
    func updateUIView(_ view: TrippyLogoView, context: Context) {
        view.isUserInteractionEnabled = interactive
        view.setIdle(idle)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TrippyLogoView, context: Context) -> CGSize? {
        CGSize(width: size * TrippyLogoView.aspect, height: size)
    }
}

final class TrippyLogoView: UIView {
    /// Width over height of `SplashMark`.
    static let aspect: CGFloat = 975.0 / 1053.0

    private let floater = UIView()       // carries the idle float
    private let mark = UIImageView(image: UIImage(named: "SplashMark")) // carries the tricks
    private var idle = false
    private var taps: [CFTimeInterval] = []
    private var busyUntil: CFTimeInterval = 0
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    init() {
        super.init(frame: .zero)
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityLabel = "trippy"
        accessibilityTraits = .image
        mark.contentMode = .scaleAspectFit
        floater.addSubview(mark)
        addSubview(floater)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        addGestureRecognizer(hold)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        floater.frame = bounds
        mark.frame = floater.bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Small logos still get a comfortable target.
        bounds.insetBy(dx: min(0, (bounds.width - 44) / 2), dy: min(0, (bounds.height - 44) / 2)).contains(point)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { applyIdle() }
    }

    func setIdle(_ value: Bool) {
        guard value != idle else { return }
        idle = value
        applyIdle()
    }

    private func applyIdle() {
        floater.layer.removeAnimation(forKey: "bob")
        floater.layer.removeAnimation(forKey: "sway")
        guard idle, !reduceMotion else { return }
        let lift = bounds.height * 0.06
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, -lift, 0, lift * 0.35, 0]
        bob.keyTimes = [0, 0.4, 0.7, 0.85, 1]
        bob.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        bob.duration = 3.6; bob.repeatCount = .infinity
        floater.layer.add(bob, forKey: "bob")
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let tilt = 2.5 * Double.pi / 180
        sway.values = [0, tilt, 0, -tilt, 0]
        sway.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        sway.duration = 5.2; sway.repeatCount = .infinity
        floater.layer.add(sway, forKey: "sway")
    }

    // MARK: Tricks

    @objc private func tapped() {
        let now = CACurrentMediaTime()
        taps = taps.filter { now - $0 < 1.6 } + [now]
        guard now >= busyUntil else { return }
        if taps.count >= 6 { taps = []; liftOff(); return }
        if taps.count == 3, now - taps[0] < 0.9 { loop(); return }
        hop()
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            taps = []
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = reduceMotion ? [1, 1.12] : [1, 1.22, 1.18, 1.34, 1.3]
            grow.duration = 0.9
            grow.fillMode = .forwards; grow.isRemovedOnCompletion = false
            mark.layer.add(grow, forKey: "trick")
            busyUntil = .infinity
        case .ended, .cancelled, .failed:
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = (mark.layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1.3
            pop.toValue = 1
            pop.damping = 9; pop.stiffness = 260; pop.initialVelocity = -4
            pop.duration = pop.settlingDuration
            mark.layer.add(pop, forKey: "trick")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            burst(count: 12, reach: 1.1)
            busyUntil = CACurrentMediaTime() + 0.3
        default: break
        }
    }

    private func hop() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        let h = bounds.height
        let up = CAKeyframeAnimation(keyPath: "transform")
        func t(_ y: CGFloat, _ sx: CGFloat, _ sy: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(0, y, 0), sx, sy, 1))
        }
        up.values = reduceMotion
            ? [t(0, 1, 1), t(0, 1.06, 1.06), t(0, 1, 1)]
            : [t(0, 1, 1), t(0, 1.08, 0.9), t(-h * 0.28, 0.95, 1.07), t(0, 1.06, 0.93), t(0, 1, 1)]
        up.keyTimes = reduceMotion ? [0, 0.5, 1] : [0, 0.15, 0.5, 0.8, 1]
        up.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: (up.values?.count ?? 2) - 1)
        up.duration = 0.5
        mark.layer.add(up, forKey: "trick")
    }

    private func loop() {
        guard !reduceMotion else { hop(); return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let h = bounds.height
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0; spin.toValue = Double.pi * 2
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, -h * 0.45, 0]
        let group = CAAnimationGroup()
        group.animations = [spin, rise]
        group.duration = 0.75
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
        mark.layer.add(group, forKey: "trick")
        busyUntil = CACurrentMediaTime() + 0.75
    }

    private func liftOff() {
        guard !reduceMotion else { burst(count: 8, reach: 0.8); return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let h = bounds.height
        let fly = CAKeyframeAnimation(keyPath: "transform.translation.y")
        fly.values = [0, h * 0.12, -h * 4, h * 2.5, h * 2.5, 0]
        fly.keyTimes = [0, 0.12, 0.45, 0.4501, 0.55, 1]
        fly.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
                               CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear),
                               CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.15)]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0, 0, 1, 1]
        fade.keyTimes = [0, 0.3, 0.45, 0.55, 0.75, 1]
        let group = CAAnimationGroup()
        group.animations = [fly, fade]
        group.duration = 1.8
        mark.layer.add(group, forKey: "trick")
        burst(count: 14, reach: 1.3)
        busyUntil = CACurrentMediaTime() + 1.8
    }

    /// A ring of brand-coloured dots that flies out and fades.
    private func burst(count: Int, reach: CGFloat) {
        let colors: [UIColor] = [UIColor(red: 0.98, green: 0.39, blue: 0.31, alpha: 1),
                                 UIColor(red: 0.99, green: 0.73, blue: 0.24, alpha: 1),
                                 UIColor(red: 0.97, green: 0.73, blue: 0.67, alpha: 1)]
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let distance = max(bounds.height, 30) * reach
        for i in 0..<count {
            let r = CGFloat.random(in: 2...4.5) * max(1, bounds.height / 60)
            let dot = CAShapeLayer()
            dot.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)).cgPath
            dot.fillColor = colors[i % colors.count].cgColor
            dot.position = center
            dot.opacity = 0
            layer.addSublayer(dot)
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + .random(in: -0.25...0.25)
            let far = distance * .random(in: 0.7...1.1)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: center)
            move.toValue = NSValue(cgPoint: CGPoint(x: center.x + cos(angle) * far, y: center.y + sin(angle) * far))
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.3, 1)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.5, 1]
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1; shrink.toValue = 0.3
            let group = CAAnimationGroup()
            group.animations = [move, fade, shrink]
            group.duration = 0.7
            CATransaction.begin()
            CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
            dot.add(group, forKey: "burst")
            CATransaction.commit()
        }
    }
}

// MARK: - The full idle journey animation

/// Plays `Brand/logo-idle.svg` (balloon → sailboat → mountains → pyramids →
/// Parthenon) with its original SMIL timing. WebKit takes a moment to start,
/// so this is for screens where something is already in progress, never for
/// launch; it fades in once the first frame has painted.
struct TrippyJourneyAnimation: View {
    var animate = true
    @State private var loaded = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        JourneySVGView(animate: animate && !reduceMotion && scenePhase != .background) { loaded = true }
            .aspectRatio(1278.0 / 1230.0, contentMode: .fit)
            .opacity(loaded ? 1 : 0)
            .animation(.easeOut(duration: 0.4), value: loaded)
            .accessibilityHidden(true)
    }
}

private struct JourneySVGView: UIViewRepresentable {
    let animate: Bool
    let onLoaded: () -> Void

    final class Coordinator: NSObject, WKNavigationDelegate {
        var animate = true
        var onLoaded: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.script(animate)) { _, _ in
                // Two animation frames so the first painted frame is the artwork, not blank.
                webView.evaluateJavaScript("new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(1))))") { _, _ in
                    self.onLoaded?()
                }
            }
        }
        static func script(_ animate: Bool) -> String {
            animate ? "document.querySelector('svg')?.unpauseAnimations()" : "document.querySelector('svg')?.pauseAnimations()"
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear; web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        context.coordinator.animate = animate; context.coordinator.onLoaded = onLoaded
        if let url = Bundle.main.url(forResource: "logo-idle", withExtension: "svg", subdirectory: "Brand"),
           let svg = try? String(contentsOf: url, encoding: .utf8) {
            web.loadHTMLString("<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}svg{width:100%;height:100%;display:block}</style></head><body>" + svg + "</body></html>", baseURL: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.animate != animate else { return }
        context.coordinator.animate = animate
        web.evaluateJavaScript(Coordinator.script(animate))
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.navigationDelegate = nil
    }
}
