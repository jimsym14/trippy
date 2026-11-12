import UIKit

/// Alternative launch banner concepts, all Core Animation only (no WebKit, no
/// images beyond the mark), so they paint on the first frame and keep moving
/// while the app builds underneath.
///
/// DEBUG `-TrippySplashConcept diorama|planet|route` picks one; with no flag the
/// default sunset scene in `LaunchSplash.swift` is used.
extension TrippySplashView {
    /// The launch banner: your route. DEBUG `-TrippySplashConcept diorama|planet|sunset` previews the others.
    static var concept: String? {
        #if DEBUG
        if let picked = UserDefaults.standard.string(forKey: "TrippySplashConcept") { return picked == "sunset" ? nil : picked }
        #endif
        return "route"
    }

    func buildConcept(_ name: String, size: CGSize, intro: Bool) {
        switch name {
        case "planet": buildPlanet(size, intro: intro)
        case "route": buildRoute(size, intro: intro)
        default: buildDiorama(size, intro: intro)
        }
        introWordmark(delay: intro ? 0.35 : 0, animated: intro)
    }

    // MARK: Shared helpers

    /// The scene's settled background (the view's own colour may still be easing in).
    fileprivate var paperColor: UIColor { UIColor(hex: dark ? 0x161513 : 0xF8F4EC) }

    fileprivate func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor { UIColor(hex: hex, alpha: alpha).cgColor }

    fileprivate func gradient(_ top: UInt32, _ bottom: UInt32, size: CGSize) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.colors = [c(top), c(bottom)]
        g.frame = CGRect(origin: .zero, size: size)
        return g
    }

    fileprivate func fade(_ layer: CALayer, delay: Double, duration: Double = 0.5) {
        guard !reduceMotion else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0; a.toValue = layer.opacity
        a.beginTime = CACurrentMediaTime() + delay; a.duration = duration; a.fillMode = .backwards
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(a, forKey: "introFade")
    }

    fileprivate func introWordmark(delay: Double, animated: Bool) {
        guard animated else { wordmark.alpha = 1; wordmark.transform = .identity; return }
        wordmark.alpha = 0
        wordmark.transform = reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: 10)
        UIView.animate(withDuration: 0.6, delay: delay, options: [.curveEaseOut]) {
            self.wordmark.alpha = 1; self.wordmark.transform = .identity
        }
    }

    /// A soft pool of background colour behind the mark and wordmark, so the
    /// logo stays legible over busy scenery.
    fileprivate func clearing(at center: CGPoint, radius: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        let bg = paperColor
        g.colors = [bg.withAlphaComponent(0.92).cgColor, bg.withAlphaComponent(0.6).cgColor, bg.withAlphaComponent(0).cgColor]
        g.locations = [0, 0.55, 1]
        g.startPoint = CGPoint(x: 0.5, y: 0.5); g.endPoint = CGPoint(x: 1, y: 1)
        g.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        g.position = center
        return g
    }

    // MARK: 1 · Paper diorama

    /// Cut-paper layers that fold up like a pop-up book, cast soft paper shadows,
    /// then drift with gentle parallax. At night the town's windows light up and
    /// the balloon's burner glows.
    private func buildDiorama(_ size: CGSize, intro: Bool) {
        let W = size.width, H = size.height
        scene.addSublayer(gradient(dark ? 0x141312 : 0xFBE3D6, dark ? 0x2A1E19 : 0xF8F4EC, size: size))
        if dark { addStars(W: W, H: H * 0.55, intro: intro) }

        // Paper sun / moon behind everything.
        let r = W * 0.2
        let orb = CAShapeLayer()
        orb.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)).cgPath
        orb.fillColor = dark ? c(0xF3E3C3) : c(0xFFBE55)
        orb.position = CGPoint(x: W * 0.80, y: H * 0.22)
        paperShadow(orb, path: orb.path!, strength: 0.6)
        scene.addSublayer(orb)

        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 900
        let stage = CALayer()
        stage.frame = CGRect(origin: .zero, size: size)
        stage.sublayerTransform = perspective
        scene.addSublayer(stage)

        // Back to front: colour, crest height, wave amplitude, shape.
        let layers: [(UInt32, UInt32, CGFloat, CGFloat, String)] = [
            (0xF9D3C5, 0x2B231F, 0.64, 0.05, "peaks"),
            (0xF4B39E, 0x3B2C26, 0.78, 0.00, "town"),
            (0xFFBE55, 0x47332A, 0.80, 0.025, "hills"),
            (0xFB8A6E, 0x583027, 0.86, 0.022, "hills"),
            (0xFB644F, 0x6E3328, 0.92, 0.018, "hills"),
        ]
        var paper: [CALayer] = []
        for (i, l) in layers.enumerated() {
            let sheet = CAShapeLayer()
            let path: CGPath
            switch l.4 {
            case "peaks": path = Self.peaksPath(W: W, H: H, crest: H * l.2, height: H * 0.12)
            case "town": path = Self.townPath(W: W, H: H, base: H * l.2)
            default: path = Self.hillPath(W: W, H: H, base: H * l.2, amp: H * l.3, phase: CGFloat(i) * 1.3)
            }
            sheet.path = path
            sheet.fillColor = c(dark ? l.1 : l.0)
            sheet.anchorPoint = CGPoint(x: 0.5, y: 1)
            sheet.bounds = CGRect(x: -W * 0.1, y: 0, width: W * 1.2, height: H)
            sheet.position = CGPoint(x: W / 2, y: H)
            paperShadow(sheet, path: path, strength: 1)
            if l.4 == "town" && dark { addWindows(to: sheet, W: W, base: H * l.2) }
            stage.addSublayer(sheet)
            paper.append(sheet)
        }

        // Paper clouds on threads.
        for (i, cl) in [(0.20, 0.17, 110.0), (0.78, 0.25, 80.0), (0.36, 0.33, 64.0)].enumerated() {
            let w = CGFloat(cl.2)
            let cloud = CAShapeLayer()
            let path = Self.cloudPath(width: w).cgPath
            cloud.path = path
            cloud.fillColor = dark ? c(0x3A302A) : c(0xFFFDF9)
            cloud.bounds = CGRect(x: 0, y: 0, width: w, height: w * 0.42)
            cloud.position = CGPoint(x: W * cl.0, y: H * cl.1)
            paperShadow(cloud, path: path, strength: 0.8)
            let thread = CAShapeLayer()
            let tp = UIBezierPath(); tp.move(to: CGPoint(x: w * 0.55, y: 0)); tp.addLine(to: CGPoint(x: w * 0.55, y: -H))
            thread.path = tp.cgPath; thread.strokeColor = dark ? c(0xFFFFFF, 0.12) : c(0x102A22, 0.12); thread.lineWidth = 0.7
            cloud.addSublayer(thread)
            stage.addSublayer(cloud)
            paper.append(cloud)
            if !reduceMotion {
                let swing = CABasicAnimation(keyPath: "transform.translation.x")
                swing.fromValue = -6 - CGFloat(i) * 2; swing.toValue = 6 + CGFloat(i) * 2
                swing.duration = 3.4 + Double(i) * 0.7; swing.autoreverses = true; swing.repeatCount = .infinity
                swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                cloud.add(swing, forKey: "swing")
            }
        }

        // The burner glow behind the balloon (night), or a warm halo (day).
        let halo = CAGradientLayer()
        halo.type = .radial
        halo.colors = [c(0xFFBE55, dark ? 0.45 : 0.25), c(0xFFBE55, 0)]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5); halo.endPoint = CGPoint(x: 1, y: 1)
        halo.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        halo.position = CGPoint(x: W / 2, y: H / 2)
        scene.addSublayer(halo)
        if !reduceMotion {
            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [1, 0.7, 1, 0.85, 1]; flicker.duration = 2.2; flicker.repeatCount = .infinity
            halo.add(flicker, forKey: "flicker")
        }

        guard intro, !reduceMotion else { return }
        // Pop-up book: each sheet folds up from flat, back to front.
        for (i, sheet) in paper.enumerated() {
            let fold = CASpringAnimation(keyPath: "transform")
            fold.fromValue = NSValue(caTransform3D: CATransform3DMakeRotation(.pi / 2 * 0.97, 1, 0, 0))
            fold.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            fold.damping = 13; fold.stiffness = 110; fold.mass = 1
            fold.beginTime = CACurrentMediaTime() + 0.05 + Double(i) * 0.09
            fold.duration = fold.settlingDuration; fold.fillMode = .backwards
            sheet.add(fold, forKey: "fold")
        }
        fade(orb, delay: 0.1, duration: 0.6)
        fade(halo, delay: 0.5, duration: 0.8)
        // Then a slow parallax drift: nearer sheets move more.
        for (i, sheet) in paper.prefix(5).enumerated() {
            let sway = CABasicAnimation(keyPath: "position.x")
            let reach = CGFloat(i + 1) * 3
            sway.fromValue = W / 2 - reach; sway.toValue = W / 2 + reach
            sway.duration = 6; sway.autoreverses = true; sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sway.beginTime = CACurrentMediaTime() + 1.2
            sheet.add(sway, forKey: "parallax")
        }
    }

    private func paperShadow(_ layer: CALayer, path: CGPath, strength: Float) {
        layer.shadowPath = path
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = (dark ? 0.55 : 0.16) * strength
        layer.shadowRadius = 7
        layer.shadowOffset = CGSize(width: 0, height: -3)
    }

    private func addWindows(to sheet: CALayer, W: CGFloat, base: CGFloat) {
        var seed: UInt64 = 42
        func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1; return CGFloat((seed >> 33) % 1000) / 1000 }
        for b in Self.buildings(W: W) {
            let rows = Int(b.h / 16), cols = max(1, Int(b.w / 14))
            for row in 0..<rows { for col in 0..<cols where next() > 0.45 {
                let win = CALayer()
                win.backgroundColor = c(0xFFC66B)
                win.frame = CGRect(x: b.x + 5 + CGFloat(col) * 13, y: base - b.h + 8 + CGFloat(row) * 15, width: 5, height: 7)
                win.cornerRadius = 1
                win.opacity = Float(0.55 + next() * 0.45)
                sheet.addSublayer(win)
                guard !reduceMotion else { continue }
                let on = CABasicAnimation(keyPath: "opacity")
                on.fromValue = 0; on.toValue = win.opacity
                on.beginTime = CACurrentMediaTime() + 0.8 + Double(next()) * 1.4; on.duration = 0.25; on.fillMode = .backwards
                win.add(on, forKey: "on")
            } }
        }
    }

    private static func buildings(W: CGFloat) -> [(x: CGFloat, w: CGFloat, h: CGFloat)] {
        let widths: [CGFloat] = [26, 36, 22, 40, 30, 34, 24, 38, 28, 32]
        let heights: [CGFloat] = [40, 28, 56, 34, 46, 26, 64, 38, 30, 50]
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        var x: CGFloat = -W * 0.1
        var i = 0
        while x < W * 1.1 { let w = widths[i % widths.count]; out.append((x, w, heights[i % heights.count])); x += w + 4; i += 1 }
        return out
    }

    private static func townPath(W: CGFloat, H: CGFloat, base: CGFloat) -> CGPath {
        let path = UIBezierPath()
        for (i, b) in buildings(W: W).enumerated() {
            path.append(UIBezierPath(rect: CGRect(x: b.x, y: base - b.h, width: b.w, height: H - base + b.h)))
            switch i % 5 {
            case 1: path.append(UIBezierPath(arcCenter: CGPoint(x: b.x + b.w / 2, y: base - b.h), radius: b.w / 2, startAngle: .pi, endAngle: 0, clockwise: true))
            case 3: let roof = UIBezierPath(); roof.move(to: CGPoint(x: b.x, y: base - b.h)); roof.addLine(to: CGPoint(x: b.x + b.w / 2, y: base - b.h - b.w * 0.7)); roof.addLine(to: CGPoint(x: b.x + b.w, y: base - b.h)); roof.close(); path.append(roof)
            default: break
            }
        }
        return path.cgPath
    }

    private static func hillPath(W: CGFloat, H: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -W * 0.1, y: H))
        for i in 0...60 {
            let x = -W * 0.1 + W * 1.2 * CGFloat(i) / 60
            let t = x / W * .pi * 2
            path.addLine(to: CGPoint(x: x, y: base - amp * sin(t + phase) - amp * 0.5 * sin(t * 2.3 + phase)))
        }
        path.addLine(to: CGPoint(x: W * 1.1, y: H)); path.close()
        return path.cgPath
    }

    private static func peaksPath(W: CGFloat, H: CGFloat, crest: CGFloat, height: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -W * 0.1, y: H))
        let peaks: [(CGFloat, CGFloat)] = [(-0.1, 0.4), (0.08, 0.9), (0.26, 0.5), (0.44, 1.0), (0.62, 0.55), (0.8, 0.85), (1.0, 0.45), (1.1, 0.6)]
        for (x, h) in peaks { path.addLine(to: CGPoint(x: W * x, y: crest + height * (1 - h))) }
        path.addLine(to: CGPoint(x: W * 1.1, y: H)); path.close()
        return path.cgPath
    }

    // MARK: 2 · Around the world

    /// A small planet turns under the balloon; landmarks from around the world
    /// rise over its horizon and pass by. A windmill keeps spinning.
    private func buildPlanet(_ size: CGSize, intro: Bool) {
        let W = size.width, H = size.height
        scene.addSublayer(gradient(dark ? 0x141312 : 0xF8F4EC, dark ? 0x2A1E26 : 0xFCD6C6, size: size))
        if dark { addStars(W: W, H: H * 0.7, intro: intro) }

        let R = W * 0.95
        let center = CGPoint(x: W / 2, y: H * 0.79 + R)
        // Sun or moon sitting on the horizon.
        let sr = W * 0.16
        let orb = CAShapeLayer()
        orb.path = UIBezierPath(ovalIn: CGRect(x: -sr, y: -sr, width: sr * 2, height: sr * 2)).cgPath
        orb.fillColor = dark ? c(0xF3E3C3, 0.9) : c(0xFFBE55)
        orb.position = CGPoint(x: W * 0.80, y: H * 0.20)
        scene.addSublayer(orb)

        // Atmosphere rings, then the planet itself.
        for (width, alpha) in [(46.0, 0.06), (22.0, 0.10)] {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: center.x - R, y: center.y - R, width: R * 2, height: R * 2)).cgPath
            ring.fillColor = nil; ring.strokeColor = dark ? c(0xFFBE55, alpha) : c(0xFB644F, alpha); ring.lineWidth = width
            scene.addSublayer(ring)
        }
        let planet = CAShapeLayer()
        planet.path = UIBezierPath(ovalIn: CGRect(x: center.x - R, y: center.y - R, width: R * 2, height: R * 2)).cgPath
        planet.fillColor = dark ? c(0x3A2A26) : c(0xF6B9A6)
        scene.addSublayer(planet)
        let band = CAShapeLayer()
        let bandR = R * 0.93
        band.path = UIBezierPath(ovalIn: CGRect(x: center.x - bandR, y: center.y - bandR, width: bandR * 2, height: bandR * 2)).cgPath
        band.fillColor = dark ? c(0x47302A) : c(0xF8C7B6)
        scene.addSublayer(band)

        // Landmarks around the rim, carried by one rotating layer.
        let globe = CALayer()
        globe.position = center
        globe.bounds = .zero
        scene.addSublayer(globe)
        let kinds = ["eiffel", "pyramids", "torii", "santorini", "windmill", "bigben", "fuji", "palm", "lighthouse",
                     "torii", "eiffel", "santorini", "pyramids", "windmill", "palm", "bigben", "lighthouse", "fuji"]
        for (i, kind) in kinds.enumerated() {
            let angle = CGFloat(i) / CGFloat(kinds.count) * .pi * 2
            let mark = landmark(kind)
            mark.anchorPoint = CGPoint(x: 0.5, y: 1)
            mark.position = CGPoint(x: sin(angle) * (R - 2), y: -cos(angle) * (R - 2))
            mark.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            globe.addSublayer(mark)
        }
        // Start with a landmark just past the top so the first frame isn't empty.
        globe.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 12))
        if !reduceMotion {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -Double.pi / 12; spin.toValue = -Double.pi / 12 - Double.pi * 2
            spin.duration = 90; spin.repeatCount = .infinity
            globe.add(spin, forKey: "spin")
        }

        // Drifting clouds above the horizon.
        for (i, cl) in [(0.12, 0.2, 96.0, 40.0), (0.5, 0.3, 70.0, 30.0), (0.7, 0.62, 84.0, 50.0)].enumerated() {
            let w = CGFloat(cl.2)
            let cloud = CAShapeLayer()
            cloud.path = Self.cloudPath(width: w).cgPath
            cloud.fillColor = dark ? c(0xFFFFFF, 0.07) : c(0xFFFFFF, 0.9)
            cloud.bounds = CGRect(x: 0, y: 0, width: w, height: w * 0.42)
            cloud.position = CGPoint(x: W * cl.0, y: H * cl.1)
            scene.addSublayer(cloud)
            guard !reduceMotion else { continue }
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = W + w; drift.toValue = -w
            drift.duration = cl.3; drift.repeatCount = .infinity; drift.timeOffset = cl.3 * (1 - cl.0) + Double(i)
            cloud.add(drift, forKey: "drift")
        }
        scene.addSublayer(clearing(at: CGPoint(x: W / 2, y: H / 2 + 20), radius: 150))

        guard intro, !reduceMotion else { return }
        for layer in [planet, band, globe] as [CALayer] {
            let rise = CASpringAnimation(keyPath: "position.y")
            rise.fromValue = H * 0.35; rise.toValue = 0
            rise.damping = 16; rise.stiffness = 90
            rise.beginTime = CACurrentMediaTime() + 0.05; rise.duration = rise.settlingDuration; rise.fillMode = .backwards
            rise.isAdditive = true
            layer.add(rise, forKey: "rise")
        }
        fade(orb, delay: 0.3, duration: 0.8)
    }

    /// One landmark silhouette, base centred at the bottom of its bounds.
    private func landmark(_ kind: String) -> CALayer {
        let coral = dark ? c(0xC2574A) : c(0xFB644F)
        let amber = dark ? c(0xC99A45) : c(0xFCBA3D)
        let forest = dark ? c(0x6F8F7C) : c(0x102A22)
        let sage = dark ? c(0x5E7F6A) : c(0x477461)
        let ivory = dark ? c(0xE8DCC8) : c(0xFFFDF9)
        let sky = dark ? c(0x6F93B8) : c(0x4A79A0)
        let box = CALayer()
        func shape(_ path: UIBezierPath, _ fill: CGColor) {
            let s = CAShapeLayer(); s.path = path.cgPath; s.fillColor = fill; box.addSublayer(s)
        }
        func poly(_ pts: [(CGFloat, CGFloat)]) -> UIBezierPath {
            let p = UIBezierPath(); p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); pts.dropFirst().forEach { p.addLine(to: CGPoint(x: $0.0, y: $0.1)) }; p.close(); return p
        }
        switch kind {
        case "eiffel":
            let w: CGFloat = 54, h: CGFloat = 128
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            let p = poly([(0, h), (w * 0.36, h * 0.42), (w * 0.46, h * 0.08), (w * 0.5, 0), (w * 0.54, h * 0.08), (w * 0.64, h * 0.42), (w, h), (w * 0.7, h)])
            p.addQuadCurve(to: CGPoint(x: w * 0.3, y: h), controlPoint: CGPoint(x: w * 0.5, y: h * 0.68)); p.close()
            shape(p, forest)
            shape(UIBezierPath(rect: CGRect(x: w * 0.14, y: h * 0.62, width: w * 0.72, height: 4)), forest)
            shape(UIBezierPath(rect: CGRect(x: w * 0.3, y: h * 0.4, width: w * 0.4, height: 3)), forest)
        case "pyramids":
            let w: CGFloat = 130, h: CGFloat = 64
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(poly([(w * 0.38, h), (w * 0.7, h * 0.22), (w, h)]), amber)
            shape(poly([(0, h), (w * 0.32, 0), (w * 0.64, h)]), coral)
            shape(poly([(w * 0.32, 0), (w * 0.64, h), (w * 0.44, h)]), dark ? c(0x9E463C) : c(0xD9482F))
        case "torii":
            let w: CGFloat = 76, h: CGFloat = 70
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(UIBezierPath(rect: CGRect(x: w * 0.18, y: h * 0.18, width: 7, height: h * 0.82)), coral)
            shape(UIBezierPath(rect: CGRect(x: w * 0.82 - 7, y: h * 0.18, width: 7, height: h * 0.82)), coral)
            let top = UIBezierPath(); top.move(to: CGPoint(x: 0, y: 2)); top.addQuadCurve(to: CGPoint(x: w, y: 2), controlPoint: CGPoint(x: w / 2, y: 12))
            top.addLine(to: CGPoint(x: w - 4, y: 12)); top.addQuadCurve(to: CGPoint(x: 4, y: 12), controlPoint: CGPoint(x: w / 2, y: 20)); top.close()
            shape(top, coral)
            shape(UIBezierPath(rect: CGRect(x: w * 0.1, y: h * 0.32, width: w * 0.8, height: 6)), coral)
        case "santorini":
            let w: CGFloat = 96, h: CGFloat = 70
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(UIBezierPath(rect: CGRect(x: 0, y: h * 0.55, width: w * 0.36, height: h * 0.45)), ivory)
            shape(UIBezierPath(rect: CGRect(x: w * 0.32, y: h * 0.36, width: w * 0.36, height: h * 0.64)), ivory)
            shape(UIBezierPath(rect: CGRect(x: w * 0.66, y: h * 0.6, width: w * 0.34, height: h * 0.4)), ivory)
            shape(UIBezierPath(arcCenter: CGPoint(x: w * 0.5, y: h * 0.36), radius: w * 0.16, startAngle: .pi, endAngle: 0, clockwise: true), sky)
            shape(UIBezierPath(rect: CGRect(x: w * 0.49, y: h * 0.06, width: 2, height: h * 0.14)), sky)
            for x in [0.1, 0.42, 0.76] { shape(UIBezierPath(roundedRect: CGRect(x: w * x, y: h * 0.74, width: 7, height: 10), cornerRadius: 3.5), sky) }
        case "windmill":
            let w: CGFloat = 64, h: CGFloat = 96
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(poly([(w * 0.28, h), (w * 0.38, h * 0.32), (w * 0.62, h * 0.32), (w * 0.72, h)]), ivory)
            shape(poly([(w * 0.34, h * 0.34), (w * 0.5, h * 0.18), (w * 0.66, h * 0.34)]), coral)
            let blades = CAShapeLayer()
            let bp = UIBezierPath()
            for k in 0..<4 { let a = CGFloat(k) * .pi / 2; bp.append(UIBezierPath(roundedRect: CGRect(x: -3, y: -34, width: 9, height: 30), cornerRadius: 2).applyingRotation(a)) }
            blades.path = bp.cgPath; blades.fillColor = forest
            blades.position = CGPoint(x: w * 0.5, y: h * 0.3)
            box.addSublayer(blades)
            if !reduceMotion {
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0; turn.toValue = Double.pi * 2; turn.duration = 4; turn.repeatCount = .infinity
                blades.add(turn, forKey: "turn")
            }
        case "bigben":
            let w: CGFloat = 34, h: CGFloat = 124
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(UIBezierPath(rect: CGRect(x: 4, y: h * 0.22, width: w - 8, height: h * 0.78)), amber)
            shape(poly([(4, h * 0.22), (w / 2, 0), (w - 4, h * 0.22)]), forest)
            shape(UIBezierPath(ovalIn: CGRect(x: w * 0.24, y: h * 0.28, width: w * 0.52, height: w * 0.52)), ivory)
        case "fuji":
            let w: CGFloat = 150, h: CGFloat = 70
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(poly([(0, h), (w * 0.4, 4), (w * 0.6, 4), (w, h)]), sage)
            shape(poly([(w * 0.3, h * 0.3), (w * 0.4, 4), (w * 0.6, 4), (w * 0.7, h * 0.3), (w * 0.6, h * 0.4), (w * 0.5, h * 0.28), (w * 0.42, h * 0.42)]), ivory)
        case "palm":
            let w: CGFloat = 70, h: CGFloat = 96
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            let trunk = CAShapeLayer()
            let tp = UIBezierPath(); tp.move(to: CGPoint(x: w * 0.5, y: h)); tp.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.2), controlPoint: CGPoint(x: w * 0.38, y: h * 0.55))
            trunk.path = tp.cgPath; trunk.strokeColor = dark ? c(0x8B6A4E) : c(0x8B4A3A); trunk.lineWidth = 6; trunk.fillColor = nil; trunk.lineCap = .round
            box.addSublayer(trunk)
            for a in stride(from: -2.6, through: 0.4, by: 0.75) {
                let leaf = UIBezierPath(ovalIn: CGRect(x: 0, y: -5, width: 34, height: 10)).applyingRotation(CGFloat(a))
                leaf.apply(CGAffineTransform(translationX: w * 0.58, y: h * 0.2))
                shape(leaf, sage)
            }
        default: // lighthouse
            let w: CGFloat = 40, h: CGFloat = 110
            box.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            shape(poly([(w * 0.2, h), (w * 0.32, h * 0.22), (w * 0.68, h * 0.22), (w * 0.8, h)]), ivory)
            for y in [0.4, 0.62, 0.84] { shape(poly([(w * (0.27 - (y - 0.4) * 0.08), h * y), (w * (0.73 + (y - 0.4) * 0.08), h * y), (w * (0.745 + (y - 0.4) * 0.08), h * (y + 0.09)), (w * (0.255 - (y - 0.4) * 0.08), h * (y + 0.09))]), coral) }
            shape(UIBezierPath(rect: CGRect(x: w * 0.3, y: h * 0.1, width: w * 0.4, height: h * 0.12)), amber)
            shape(poly([(w * 0.26, h * 0.1), (w * 0.5, 0), (w * 0.74, h * 0.1)]), coral)
        }
        return box
    }

    // MARK: 3 · Your route

    /// A dot map of the region you've travelled, your route drawing itself
    /// between the places in Been to, pins landing as it reaches them.
    private func buildRoute(_ size: CGSize, intro: Bool) {
        let W = size.width, H = size.height
        let (places, personal) = Self.routePlaces()
        // Fit the route into a band above the logo; the dot map fills the rest of the screen.
        let lats = places.map { $0.lat }, lons = places.map { $0.lon }
        let cLat = (lats.min()! + lats.max()!) / 2, cLon = (lons.min()! + lons.max()!) / 2
        let kx = cos(cLat * .pi / 180)
        let band = CGRect(x: W * 0.14, y: H * 0.11, width: W * 0.72, height: H * 0.24)
        let dLon = max(lons.max()! - lons.min()!, 6) * kx, dLat = max(lats.max()! - lats.min()!, 4)
        let s = min(Double(band.width) / dLon, Double(band.height) / dLat) // points per degree of latitude
        func project(_ lat: Double, _ lon: Double) -> CGPoint {
            CGPoint(x: band.midX + CGFloat((lon - cLon) * kx * s), y: band.midY - CGFloat((lat - cLat) * s))
        }
        let minLon = cLon - Double(band.midX) / (kx * s), maxLon = cLon + Double(W - band.midX) / (kx * s)
        let maxLat = cLat + Double(band.midY) / s, minLat = cLat - Double(H - band.midY) / s
        let spanLon = maxLon - minLon, spanLat = maxLat - minLat

        // Dot-matrix land.
        let dots = CAShapeLayer()
        let dotPath = CGMutablePath()
        if let url = Bundle.main.url(forResource: "splash-land", withExtension: "bin", subdirectory: "Brand"),
           let data = try? Data(contentsOf: url) {
            let bytes = [UInt8](data)
            var step = 0.5
            while (spanLon / step) * (spanLat / step) > 4200 { step *= 2 }
            let dotR = max(1.1, W / CGFloat(spanLon / step) * 0.26)
            var lat = (maxLat / step).rounded(.down) * step
            while lat > minLat {
                var lon = (minLon / step).rounded(.down) * step
                while lon < maxLon {
                    let row = Int((90 - lat) / 0.5), col = Int((lon.truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) / 0.5)
                    let index = row * 720 + col
                    if row >= 0, row < 360, col >= 0, col < 720, bytes[index >> 3] & (0x80 >> (index & 7)) != 0 {
                        let p = project(lat, lon)
                        dotPath.addEllipse(in: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2))
                    }
                    lon += step
                }
                lat -= step
            }
        }
        dots.path = dotPath
        dots.fillColor = dark ? c(0xF1ECE2, 0.16) : c(0x102A22, 0.13)
        let map = CALayer()
        map.frame = CGRect(origin: .zero, size: size)
        map.addSublayer(dots)
        // The map is densest around the route and softens towards the bottom edge.
        let fadeMask = CAGradientLayer()
        fadeMask.frame = map.bounds
        fadeMask.colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor(white: 0, alpha: 0.12).cgColor]
        fadeMask.locations = [0, 0.18, 0.45, 1]
        map.mask = fadeMask
        scene.addSublayer(map)

        // The route: gentle arcs between stops.
        let points = places.map { project($0.lat, $0.lon) }
        let route = UIBezierPath()
        route.move(to: points[0])
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let d = hypot(b.x - a.x, b.y - a.y)
            let ctrl = CGPoint(x: mid.x + (a.y - b.y) * 0.25, y: mid.y - abs(b.x - a.x) * 0.25 - d * 0.08)
            route.addQuadCurve(to: b, controlPoint: ctrl)
            lengths.append(lengths.last! + d)
        }
        let total = max(lengths.last!, 1)
        let accent = dark ? c(0xFFBE55) : c(0xFB644F)
        // A soft band under the dotted line, like a highlighter on a paper map.
        let glow = CAShapeLayer()
        glow.path = route.cgPath
        glow.fillColor = nil; glow.strokeColor = dark ? c(0xFFBE55, 0.14) : c(0xFB644F, 0.12); glow.lineWidth = 9
        glow.lineCap = .round; glow.lineJoin = .round
        scene.addSublayer(glow)
        let line = CAShapeLayer()
        line.path = route.cgPath
        line.fillColor = nil; line.strokeColor = accent; line.lineWidth = 2.8
        line.lineCap = .round; line.lineDashPattern = [0.5, 8]
        scene.addSublayer(line)

        let start = CACurrentMediaTime() + (intro ? 0.2 : 0)
        let drawTime = reduceMotion ? 0 : 1.7
        if !reduceMotion && intro {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0; draw.toValue = 1; draw.beginTime = start; draw.duration = drawTime; draw.fillMode = .backwards
            draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            line.add(draw, forKey: "draw")
            glow.add(draw, forKey: "draw")
            // A paper plane flies the route ahead of the line.
            let plane = CAShapeLayer()
            plane.path = Self.planePath().cgPath; plane.fillColor = accent
            plane.bounds = CGRect(x: -12, y: -9, width: 24, height: 18)
            plane.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))
            plane.position = CGPoint(x: -100, y: -100)
            scene.addSublayer(plane)
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = route.cgPath; fly.calculationMode = .paced; fly.rotationMode = .rotateAuto
            fly.beginTime = start; fly.duration = drawTime
            fly.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut)]
            plane.add(fly, forKey: "fly")
            plane.opacity = 0
            let show = CABasicAnimation(keyPath: "opacity"); show.fromValue = 1; show.toValue = 1
            show.beginTime = start; show.duration = drawTime * 0.98
            plane.add(show, forKey: "show")
        }

        // Pins and names, landing as the line reaches them. Names never overlap:
        // each tries the right, then the left, then stays unnamed.
        var taken: [CGRect] = points.map { CGRect(x: $0.x - 8, y: $0.y - 8, width: 16, height: 16) }
        for (i, place) in places.enumerated() {
            let p = points[i]
            let pin = CALayer()
            pin.position = p
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: -14, y: -14, width: 28, height: 28)).cgPath
            ring.fillColor = dark ? c(0xFFBE55, 0.18) : c(0xFB644F, 0.16)
            pin.addSublayer(ring)
            let dot = CAShapeLayer()
            dot.path = UIBezierPath(ovalIn: CGRect(x: -6, y: -6, width: 12, height: 12)).cgPath
            dot.fillColor = accent; dot.strokeColor = paperColor.cgColor; dot.lineWidth = 2.5
            pin.addSublayer(dot)
            let label = CATextLayer()
            label.string = place.name
            label.font = UIFont(name: "PlusJakartaSans-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
            label.fontSize = 12
            label.foregroundColor = dark ? c(0xF1ECE2, 0.85) : c(0x102A22, 0.8)
            label.contentsScale = UIScreen.main.scale
            let textWidth = min(120, (place.name as NSString).size(withAttributes: [.font: label.font as! UIFont]).width + 4)
            let right = CGRect(x: 12, y: -8, width: textWidth, height: 16), left = CGRect(x: -12 - textWidth, y: -8, width: textWidth, height: 16)
            let options = p.x > W * 0.62 ? [left, right] : [right, left]
            if let spot = options.first(where: { option in
                let onScreen = option.offsetBy(dx: p.x, dy: p.y)
                return onScreen.minX > 8 && onScreen.maxX < W - 8 && !taken.contains { $0.intersects(onScreen.insetBy(dx: -3, dy: -2)) }
            }) {
                label.frame = spot
                label.alignmentMode = spot == left ? .right : .left
                taken.append(spot.offsetBy(dx: p.x, dy: p.y))
                pin.addSublayer(label)
            }
            scene.addSublayer(pin)
            guard intro, !reduceMotion else { continue }
            let at = start + drawTime * Double(lengths[i] / total)
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0; pop.toValue = 1; pop.damping = 9; pop.stiffness = 220
            pop.beginTime = at; pop.duration = pop.settlingDuration; pop.fillMode = .backwards
            pin.add(pop, forKey: "pop")
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1; pulse.toValue = 1.5; pulse.duration = 1.6; pulse.repeatCount = .infinity
            pulse.beginTime = at + 0.3; pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(pulse, forKey: "pulse")
            let pulseFade = CABasicAnimation(keyPath: "opacity")
            pulseFade.fromValue = 1; pulseFade.toValue = 0; pulseFade.duration = 1.6; pulseFade.repeatCount = .infinity; pulseFade.beginTime = at + 0.3
            ring.add(pulseFade, forKey: "pulseFade")
        }

        scene.insertSublayer(clearing(at: CGPoint(x: W / 2, y: H / 2 + 20), radius: 150), above: map)

        // A quiet line under the wordmark when the route is really yours.
        if personal {
            let caption = CATextLayer()
            caption.string = "\(places.count) of your places"
            caption.font = UIFont(name: "PlusJakartaSans-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14)
            caption.fontSize = 14
            caption.foregroundColor = dark ? c(0xF1ECE2, 0.62) : c(0x102A22, 0.7)
            caption.alignmentMode = .center
            caption.contentsScale = UIScreen.main.scale
            caption.frame = CGRect(x: 0, y: H / 2 + Self.markSize.height / 2 + 62, width: W, height: 20)
            scene.addSublayer(caption)
            if intro { fade(caption, delay: 0.2 + drawTime, duration: 0.5) }
        }

        guard intro, !reduceMotion else { return }
        let settle = CABasicAnimation(keyPath: "transform.scale")
        settle.fromValue = 1.18; settle.toValue = 1; settle.duration = 2.4
        settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        map.add(settle, forKey: "settle")
        fade(map, delay: 0, duration: 0.9)
    }

    /// The places from Been to, in a sensible travel order; a sample for new users.
    private static func routePlaces() -> (places: [(name: String, lat: Double, lon: Double)], personal: Bool) {
        let visits = VisitedPlace.decode(UserDefaults.standard.string(forKey: "trippy.native.visitedPlaces.v1") ?? "[]")
        // Cities make a better route than country centres, when there are enough.
        let cities = visits.filter { $0.kind == .city }
        let stored = (cities.count >= 2 ? cities : visits).map { (name: $0.name, lat: $0.latitude, lon: $0.longitude) }
        var places = stored.count >= 2 ? Array(stored.prefix(40)) : [
            ("Lisbon", 38.72, -9.14), ("Barcelona", 41.39, 2.17), ("Paris", 48.86, 2.35),
            ("Rome", 41.9, 12.5), ("Athens", 37.98, 23.73), ("Istanbul", 41.01, 28.98),
        ].map { (name: $0.0, lat: $0.1, lon: $0.2) }
        // Keep a readable cluster: the region with the most stops, up to seven.
        if places.count > 7 {
            let anchor = places.max { a, b in
                places.filter { abs($0.lat - a.lat) < 15 && abs($0.lon - a.lon) < 22 }.count
                    < places.filter { abs($0.lat - b.lat) < 15 && abs($0.lon - b.lon) < 22 }.count
            }!
            let cluster = places.filter { abs($0.lat - anchor.lat) < 15 && abs($0.lon - anchor.lon) < 22 }
            places = Array((cluster.count >= 2 ? cluster : places).prefix(7))
        }
        // A journey: start in the west, then always hop to the nearest place not yet visited.
        var remaining = places.sorted { $0.lon < $1.lon }
        var ordered = [remaining.removeFirst()]
        while !remaining.isEmpty {
            let last = ordered.last!
            let next = remaining.indices.min { a, b in
                hypot(remaining[a].lat - last.lat, remaining[a].lon - last.lon) < hypot(remaining[b].lat - last.lat, remaining[b].lon - last.lon)
            }!
            ordered.append(remaining.remove(at: next))
        }
        return (ordered, stored.count >= 2)
    }
}

private extension UIBezierPath {
    func applyingRotation(_ angle: CGFloat) -> UIBezierPath {
        let copy = self.copy() as! UIBezierPath
        copy.apply(CGAffineTransform(rotationAngle: angle))
        return copy
    }
}
