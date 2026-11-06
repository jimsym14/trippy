import SwiftUI

/// Trippy's own line icons, drawn on a 24-point grid like SF Symbols so they sit
/// next to text at the same weight. Each one can draw itself in when it appears
/// or becomes selected.
enum TrippyIcon: String, CaseIterable {
    case map, library, plus, suitcase, pin, heart, plane, calendar, ticket, fork, tram, check, clock, euro, list, question, bed
    case people, star, sparkle, car, train, pencil, bolt, compass

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: o.x + x * s, y: o.y + y * s, width: w * s, height: h * s) }
        var path = Path()
        switch self {
        case .map:
            path.move(to: p(3, 6)); path.addLine(to: p(9, 3.5)); path.addLine(to: p(15, 6)); path.addLine(to: p(21, 3.5))
            path.addLine(to: p(21, 18)); path.addLine(to: p(15, 20.5)); path.addLine(to: p(9, 18)); path.addLine(to: p(3, 20.5)); path.closeSubpath()
            path.move(to: p(9, 3.5)); path.addLine(to: p(9, 18)); path.move(to: p(15, 6)); path.addLine(to: p(15, 20.5))
        case .library:
            path.addRoundedRect(in: r(3.5, 4, 4.5, 16), cornerSize: CGSize(width: 1.2 * s, height: 1.2 * s))
            path.addRoundedRect(in: r(9.5, 6, 4.5, 14), cornerSize: CGSize(width: 1.2 * s, height: 1.2 * s))
            path.move(to: p(15.6, 7.2)); path.addLine(to: p(19.8, 6)); path.addLine(to: p(21.2, 19)); path.addLine(to: p(17, 20.2)); path.closeSubpath()
            path.move(to: p(3.5, 8)); path.addLine(to: p(8, 8)); path.move(to: p(9.5, 10)); path.addLine(to: p(14, 10))
        case .plus:
            path.move(to: p(12, 5)); path.addLine(to: p(12, 19)); path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
        case .suitcase:
            path.addRoundedRect(in: r(4, 7, 16, 12.5), cornerSize: CGSize(width: 2.4 * s, height: 2.4 * s))
            path.move(to: p(9, 7)); path.addLine(to: p(9, 4.5)); path.addLine(to: p(15, 4.5)); path.addLine(to: p(15, 7))
            path.move(to: p(9, 10)); path.addLine(to: p(9, 16.5)); path.move(to: p(15, 10)); path.addLine(to: p(15, 16.5))
        case .pin:
            path.move(to: p(12, 21)); path.addCurve(to: p(12, 3), control1: p(5, 14), control2: p(4.5, 3))
            path.addCurve(to: p(12, 21), control1: p(19.5, 3), control2: p(19, 14))
            path.addEllipse(in: r(9.5, 7.5, 5, 5))
        case .heart:
            path.move(to: p(12, 20)); path.addCurve(to: p(12, 7), control1: p(2, 13.5), control2: p(4.5, 2.5))
            path.addCurve(to: p(12, 20), control1: p(19.5, 2.5), control2: p(22, 13.5))
        case .plane:
            path.move(to: p(3, 13)); path.addLine(to: p(19.5, 7.5)); path.addQuadCurve(to: p(20.5, 10.5), control: p(22.5, 8))
            path.addLine(to: p(4.5, 15.5)); path.closeSubpath()
            path.move(to: p(11, 10.5)); path.addLine(to: p(8, 4.5)); path.addLine(to: p(10, 4)); path.addLine(to: p(15, 9))
            path.move(to: p(11.5, 13.5)); path.addLine(to: p(10.5, 19)); path.addLine(to: p(12.5, 18.6)); path.addLine(to: p(15, 12.2))
        case .calendar:
            path.addRoundedRect(in: r(3.5, 5, 17, 15), cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
            path.move(to: p(3.5, 9.5)); path.addLine(to: p(20.5, 9.5))
            path.move(to: p(8, 3)); path.addLine(to: p(8, 6.5)); path.move(to: p(16, 3)); path.addLine(to: p(16, 6.5))
        case .ticket:
            path.move(to: p(3.5, 7)); path.addLine(to: p(20.5, 7)); path.addLine(to: p(20.5, 10)); path.addArc(center: p(20.5, 12), radius: 2 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: p(20.5, 17)); path.addLine(to: p(3.5, 17)); path.addLine(to: p(3.5, 14))
            path.addArc(center: p(3.5, 12), radius: 2 * s, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true); path.closeSubpath()
            path.move(to: p(14.5, 7.5)); path.addLine(to: p(14.5, 16.5))
        case .fork:
            path.move(to: p(7, 3)); path.addLine(to: p(7, 8.5)); path.addQuadCurve(to: p(9.5, 11), control: p(7, 11)); path.addLine(to: p(9.5, 21))
            path.move(to: p(12, 3)); path.addLine(to: p(12, 8.5)); path.addQuadCurve(to: p(9.5, 11), control: p(12, 11))
            path.move(to: p(9.5, 3)); path.addLine(to: p(9.5, 8))
            path.move(to: p(17, 21)); path.addLine(to: p(17, 3)); path.addCurve(to: p(17, 13), control1: p(20.5, 5), control2: p(20.5, 12))
        case .tram:
            path.addRoundedRect(in: r(5, 6, 14, 12), cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(5, 12)); path.addLine(to: p(19, 12)); path.move(to: p(12, 6)); path.addLine(to: p(12, 3))
            path.move(to: p(8, 3)); path.addLine(to: p(16, 3)); path.move(to: p(8, 18)); path.addLine(to: p(6, 21)); path.move(to: p(16, 18)); path.addLine(to: p(18, 21))
        case .check:
            path.move(to: p(5, 12.5)); path.addLine(to: p(10, 17)); path.addLine(to: p(19, 7))
        case .clock:
            path.addEllipse(in: r(3.5, 3.5, 17, 17)); path.move(to: p(12, 7.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(15, 14))
        case .euro:
            path.move(to: p(17.5, 6.5)); path.addCurve(to: p(17.5, 17.5), control1: p(8, 1.5), control2: p(8, 22.5))
            path.move(to: p(5, 10.5)); path.addLine(to: p(14, 10.5)); path.move(to: p(5, 13.5)); path.addLine(to: p(13, 13.5))
        case .list:
            for y in [6.5, 12.0, 17.5] {
                path.addEllipse(in: r(3.5, CGFloat(y) - 1, 2, 2)); path.move(to: p(8.5, CGFloat(y))); path.addLine(to: p(20.5, CGFloat(y)))
            }
        case .question:
            path.addEllipse(in: r(3.5, 3.5, 17, 17))
            path.move(to: p(9.5, 9.5)); path.addCurve(to: p(12, 13.5), control1: p(9.5, 6), control2: p(15.5, 7.5)); path.addLine(to: p(12, 14.5))
            path.addEllipse(in: r(11.4, 16.6, 1.2, 1.2))
        case .bed:
            path.move(to: p(3, 19)); path.addLine(to: p(3, 6)); path.move(to: p(3, 15)); path.addLine(to: p(21, 15)); path.addLine(to: p(21, 19))
            path.move(to: p(3, 11.5)); path.addLine(to: p(21, 11.5)); path.addLine(to: p(21, 15))
            path.addRoundedRect(in: r(5, 8, 5, 3.5), cornerSize: CGSize(width: 1.2 * s, height: 1.2 * s))
        case .people:
            path.addEllipse(in: r(5.5, 4.5, 6, 6)); path.move(to: p(2.5, 20)); path.addCurve(to: p(14.5, 20), control1: p(3, 12), control2: p(14, 12))
            path.addEllipse(in: r(14, 6, 4.8, 4.8)); path.move(to: p(16, 13.6)); path.addCurve(to: p(21.5, 19.5), control1: p(20, 13.4), control2: p(21.5, 16))
        case .star:
            for i in 0..<5 {
                let a = CGFloat(i) / 5 * .pi * 2 - .pi / 2, b = a + .pi / 5
                let outer = p(12 + cos(a) * 9, 12.6 + sin(a) * 9), inner = p(12 + cos(b) * 3.9, 12.6 + sin(b) * 3.9)
                if i == 0 { path.move(to: outer) } else { path.addLine(to: outer) }
                path.addLine(to: inner)
            }
            path.closeSubpath()
        case .sparkle:
            path.move(to: p(10, 3)); path.addQuadCurve(to: p(17, 10.5), control: p(10.5, 10)); path.addQuadCurve(to: p(10, 18), control: p(10.5, 11))
            path.addQuadCurve(to: p(3, 10.5), control: p(9.5, 11)); path.addQuadCurve(to: p(10, 3), control: p(9.5, 10))
            path.move(to: p(18.5, 14)); path.addLine(to: p(18.5, 21)); path.move(to: p(15, 17.5)); path.addLine(to: p(22, 17.5))
        case .car:
            path.move(to: p(3, 16.5)); path.addLine(to: p(3, 12.5)); path.addLine(to: p(6, 7)); path.addLine(to: p(18, 7)); path.addLine(to: p(21, 12.5)); path.addLine(to: p(21, 16.5))
            path.closeSubpath(); path.move(to: p(3, 12.5)); path.addLine(to: p(21, 12.5))
            path.addEllipse(in: r(5.5, 15, 3.6, 3.6)); path.addEllipse(in: r(14.9, 15, 3.6, 3.6))
        case .train:
            path.addRoundedRect(in: r(5.5, 3, 13, 14.5), cornerSize: CGSize(width: 3.5 * s, height: 3.5 * s))
            path.move(to: p(5.5, 10.5)); path.addLine(to: p(18.5, 10.5))
            path.addEllipse(in: r(8, 13, 1.6, 1.6)); path.addEllipse(in: r(14.4, 13, 1.6, 1.6))
            path.move(to: p(8.5, 17.5)); path.addLine(to: p(6, 21)); path.move(to: p(15.5, 17.5)); path.addLine(to: p(18, 21))
        case .pencil:
            path.move(to: p(4, 20)); path.addLine(to: p(5, 15.5)); path.addLine(to: p(15.5, 5)); path.addLine(to: p(19, 8.5)); path.addLine(to: p(8.5, 19)); path.closeSubpath()
            path.move(to: p(13, 7.5)); path.addLine(to: p(16.5, 11))
        case .bolt:
            path.move(to: p(13.5, 2.5)); path.addLine(to: p(5, 13.5)); path.addLine(to: p(11.5, 13.5)); path.addLine(to: p(10.5, 21.5))
            path.addLine(to: p(19, 10.5)); path.addLine(to: p(12.5, 10.5)); path.closeSubpath()
        case .compass:
            path.addEllipse(in: r(3, 3, 18, 18))
            path.move(to: p(15.5, 8.5)); path.addLine(to: p(13.2, 13.2)); path.addLine(to: p(8.5, 15.5)); path.addLine(to: p(10.8, 10.8)); path.closeSubpath()
        }
        return path
    }
}

struct TrippyIconShape: Shape {
    let icon: TrippyIcon
    func path(in rect: CGRect) -> Path { icon.path(in: rect) }
}

/// A Trippy icon. With `animated`, it draws itself in on appear and whenever
/// `trigger` changes (for example when its tab becomes selected).
struct TrippyIconView: View {
    let icon: TrippyIcon
    var size: CGFloat = 22
    var weight: CGFloat = 1.8
    var filled = false
    var animated = false
    var trigger: AnyHashable = 0
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if filled { TrippyIconShape(icon: icon).fill(.tint.opacity(0.18)) }
            TrippyIconShape(icon: icon)
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: weight * size / 24 * 1.15, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { draw() }
        .onChange(of: trigger) { _, _ in draw() }
    }

    private func draw() {
        guard animated, !reduceMotion else { progress = 1; return }
        progress = 0
        withAnimation(.easeOut(duration: 0.55)) { progress = 1 }
    }
}
