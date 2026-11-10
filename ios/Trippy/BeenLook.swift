import SwiftUI
import UIKit

// How the three kinds of place look everywhere on Been to:
// a country is a filled shape and a flag patch, a city is a pin, and somewhere you lived is a green home pin.

enum BeenLook {
    static let livedHex: UInt32 = 0x2F9E86
    static let lived = Color(uiColor: UIColor(sketchHex: livedHex))
    /// Pale amber for a place you passed through, deep red for one you keep going back to.
    static func heat(_ t: Double) -> UIColor {
        let stops: [UIColor] = [UIColor(sketchHex: 0xF6C453), UIColor(sketchHex: 0xF0943A), UIColor(sketchHex: 0xE2603A), UIColor(sketchHex: 0xC8332F)]
        let x = max(0, min(0.9999, t)) * Double(stops.count - 1)
        return stops[Int(x)].mixed(with: stops[Int(x) + 1], amount: CGFloat(x - floor(x)))
    }
}

/// The small mark in front of a place in lists: flag patch, city pin or home pin.
struct PlaceMark: View {
    let place: VisitedPlace
    var size: CGFloat = 42
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if place.isCountry {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(BeenPalette.amber.opacity(scheme == .dark ? 0.22 : 0.2))
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(BeenPalette.amber.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.4]))
                Text(WorldGlobeView.flag(place.countryCode)).font(.system(size: size * 0.52))
            } else {
                Image(uiImage: BeenPinArt.image(place.isLived ? .lived : .city, heat: place.heat))
                    .resizable().scaledToFit().frame(height: size * 0.82)
                    .overlay(alignment: .bottomTrailing) { Text(WorldGlobeView.flag(place.countryCode)).font(.system(size: size * 0.3)).offset(x: size * 0.18) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension BeenPinArt {
    /// Several places merged: a round counter, not a pin. A pin points at one exact spot, and a group has none.
    fileprivate static func cluster(_ count: Int, colour: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { renderer in
            let ctx = renderer.cgContext
            let disc = CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5)
            // A soft halo says "an area", then the solid counter.
            ctx.setFillColor(colour.withAlphaComponent(0.28).cgColor); ctx.fillEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(UIColor.white.cgColor); ctx.fillEllipse(in: disc)
            ctx.restoreGState()
            ctx.saveGState(); ctx.addEllipse(in: disc.insetBy(dx: 2, dy: 2)); ctx.clip()
            let colours = [colour.mixed(with: .white, amount: 0.22).cgColor, colour.darker.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: disc.minY), end: CGPoint(x: 0, y: disc.maxY), options: [])
            }
            ctx.restoreGState()
            let text = (count > 99 ? "99+" : String(count)) as NSString
            let font = UIFont(name: "PlusJakartaSans-ExtraBold", size: count > 99 ? 10 : 13.5) ?? .systemFont(ofSize: 13, weight: .heavy)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let box = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: size.width / 2 - box.width / 2, y: size.height / 2 - box.height / 2), withAttributes: attributes)
        }
    }
}

/// Map pins, drawn once per look and cached.
enum BeenPinArt {
    enum Style: Hashable { case city, lived, cluster(Int) }
    private static let cache = NSCache<NSString, UIImage>()

    static func size(_ style: Style) -> CGSize {
        switch style {
        case .city: CGSize(width: 28, height: 38)
        case .lived: CGSize(width: 34, height: 46)
        case .cluster: CGSize(width: 40, height: 40)
        }
    }

    static func image(_ style: Style, heat: Double = 0.4) -> UIImage {
        let bucket = Int((heat * 6).rounded())
        let key = "\(style):\(bucket)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let size = size(style)
        if case .cluster(let count) = style {
            let image = cluster(count, colour: BeenLook.heat(Double(bucket) / 6), size: size)
            cache.setObject(image, forKey: key)
            return image
        }
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            let ctx = renderer.cgContext
            let w = size.width, r = w / 2 - 3
            let centre = CGPoint(x: w / 2, y: r + 3), tip = CGPoint(x: w / 2, y: size.height - 3)
            // Where it touches the ground.
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            ctx.fillEllipse(in: CGRect(x: tip.x - 5, y: tip.y - 1.5, width: 10, height: 4))
            // Teardrop: a circle whose lower sides run down to the tip.
            let body = UIBezierPath()
            let spread = CGFloat.pi * 0.29
            body.addArc(withCenter: centre, radius: r, startAngle: .pi / 2 - spread, endAngle: .pi / 2 + spread, clockwise: false)
            body.addLine(to: tip); body.close()
            let base: UIColor = { switch style { case .lived: UIColor(sketchHex: BeenLook.livedHex); default: BeenLook.heat(Double(bucket) / 6) } }()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill(); body.fill()
            ctx.restoreGState()
            ctx.saveGState(); body.addClip()
            let colours = [base.mixed(with: .white, amount: 0.28).cgColor, base.cgColor, base.darker.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w * 0.6, y: size.height), options: [])
            }
            ctx.restoreGState()
            UIColor.white.setStroke(); body.lineWidth = 2; body.lineJoinStyle = .round; body.stroke()
            // A highlight, top left, so it looks enamelled.
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            ctx.fillEllipse(in: CGRect(x: centre.x - r * 0.62, y: centre.y - r * 0.7, width: r * 0.55, height: r * 0.36))
            switch style {
            case .city:
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: centre.x - r * 0.36, y: centre.y - r * 0.36, width: r * 0.72, height: r * 0.72))
            case .lived:
                let glyph = UIImage(systemName: "house.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: r * 0.95, weight: .bold))?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                if let glyph { glyph.draw(at: CGPoint(x: centre.x - glyph.size.width / 2, y: centre.y - glyph.size.height / 2)) }
            case .cluster(let count):
                let text = (count > 99 ? "99+" : String(count)) as NSString
                let font = UIFont(name: "PlusJakartaSans-ExtraBold", size: count > 99 ? 11 : 14) ?? .systemFont(ofSize: 14, weight: .heavy)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let box = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: centre.x - box.width / 2, y: centre.y - box.height / 2), withAttributes: attributes)
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
