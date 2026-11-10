import SwiftUI

/// The Library's sections on a dial that curves around the bottom bar.
///
/// Sections sit on an arc whose centre is the tab bar, so the dial reads as a wheel turning around it.
/// Drag to turn it (a selection tick for every section that passes the lens), flick and it coasts to the
/// nearest one, or tap a section to roll there. The lens at the top is liquid glass: it magnifies whatever
/// passes under it (a refracted copy of the dial, clipped to the lens), stretches with the drag speed and,
/// when a section lands, squeezes and springs back like a genie settling into its bottle.
struct LibraryWheel: View {
    struct Item: Identifiable, Equatable { let id: String; let title: String; let symbol: String }

    let items: [Item]
    @Binding var selection: String
    var tint: Color = Sketch.ink

    /// Room the dial takes above the tab bar.
    static let height: CGFloat = 88
    /// Extra drawing room above that band, so the lens shadow and glass blur aren't cut off. Not part of the
    /// layout and not touchable: the view is lifted into it with a negative padding.
    private static let headroom: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// Height of the lens (and the row of sections) inside the dial.
    private let lensY: CGFloat = 36 + LibraryWheel.headroom
    /// Continuous position in items: 2.0 = the third item under the lens.
    @State private var position: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var stretch: CGFloat = 0
    @State private var landed = 0
    @State private var tick = 0
    @State private var spin: Task<Void, Never>?

    private let radius: CGFloat = 270
    private let step = Angle.degrees(17)
    private var stepPoints: CGFloat { radius * CGFloat(sin(step.radians)) }   // finger travel per section

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: lensY + radius)   // arc's centre sits below, at the bar
            ZStack {
                track(center: center)
                dial(center: center, magnified: false)
                lens(center: center)
            }
            // Soft edges: fades out sideways and at the bottom, and stays inside its own band above the bar.
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                       .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            // Only the dial's own band takes touches, not the headroom above it.
            .contentShape(Rectangle().path(in: CGRect(x: 0, y: Self.headroom, width: geometry.size.width, height: Self.height)))
            // Ahead of the section buttons, so a drag anywhere on the dial turns it; a tap still selects.
            .highPriorityGesture(drag)
        }
        .frame(height: Self.height + Self.headroom)
        .padding(.top, -Self.headroom)
        .onAppear { position = CGFloat(index(of: selection)) }
        .onChange(of: selection) { _, value in
            guard dragStart == nil, Int(position.rounded()) != index(of: value) else { return }
            roll(to: index(of: value), notify: false)
        }
        .sensoryFeedback(.selection, trigger: tick)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: landed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library section")
        .accessibilityValue(items.first { $0.id == selection }?.title ?? "")
        .accessibilityAdjustableAction { direction in
            let next = index(of: selection) + (direction == .increment ? 1 : -1)
            roll(to: next, notify: true)
        }
    }

    // MARK: Pieces

    /// A faint arc with tick marks: the wheel's rim.
    private func track(center: CGPoint) -> some View {
        Canvas { context, _ in
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90 - 44), endAngle: .degrees(-90 + 44), clockwise: false)
            // The wheel itself: a soft white band the sections ride on, fading at both ends.
            var band = Path()
            band.addArc(center: center, radius: radius, startAngle: .degrees(-90 - 46), endAngle: .degrees(-90 + 46), clockwise: false)
            let white = Color.white.opacity(scheme == .dark ? 0.1 : 0.62)
            context.stroke(band, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: white, location: 0.22),
                                                                         .init(color: white, location: 0.78), .init(color: .clear, location: 1)]),
                                                       startPoint: CGPoint(x: center.x - radius * 0.72, y: 0), endPoint: CGPoint(x: center.x + radius * 0.72, y: 0)),
                           style: StrokeStyle(lineWidth: 52, lineCap: .butt))
            // The rim: a hairline above and below the row of sections.
            for offset in [-26.0, 26.0] {
                var line = Path()
                line.addArc(center: center, radius: radius + offset, startAngle: .degrees(-90 - 44), endAngle: .degrees(-90 + 44), clockwise: false)
                context.stroke(line, with: .linearGradient(Gradient(colors: [.clear, Sketch.ink.opacity(0.14), .clear]),
                                                           startPoint: CGPoint(x: center.x - radius * 0.7, y: 0), endPoint: CGPoint(x: center.x + radius * 0.7, y: 0)),
                               lineWidth: 1)
            }
            for offset in stride(from: -40.0, through: 40.0, by: 17.0 / 3) {
                // Three marks per section, sliding with the dial.
                let shift = Double((position * 3).truncatingRemainder(dividingBy: 1)) * 17 / 3
                let angle = Angle.degrees(-90 + offset - shift)
                let inner = point(center, radius: radius - 17, angle: angle), outer = point(center, radius: radius - 13, angle: angle)
                var mark = Path(); mark.move(to: inner); mark.addLine(to: outer)
                context.stroke(mark, with: .color(Sketch.ink.opacity(0.12 * (1 - abs(offset) / 44))), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// The sections on the arc. `magnified` draws the copy the lens refracts.
    private func dial(center: CGPoint, magnified: Bool) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                let degrees = (CGFloat(offset) - position) * step.degrees
                let distance = min(1, abs(degrees) / 50)
                let selected = item.id == selection
                Button { roll(to: offset, notify: true) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol).font(.system(size: 19, weight: selected ? .bold : .semibold))
                            .symbolVariant(selected ? .fill : .none)
                        Text(item.title).font(Sketch.text(11, "Bold", relativeTo: .caption2)).lineLimit(1).fixedSize()
                            .opacity(magnified ? 1 : 1 - distance * 0.9)
                    }
                    .foregroundStyle(magnified ? Sketch.paper : Sketch.ink.opacity(0.85 - distance * 0.45))
                    .frame(width: 76, height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BubblePressStyle())
                .scaleEffect(1 - distance * 0.28)
                .rotationEffect(.degrees(degrees))
                .position(point(center, radius: radius, angle: .degrees(-90 + degrees)))
                .opacity(abs(degrees) > 52 ? 0 : 1 - distance * 0.35)
                .blur(radius: magnified ? 0 : distance * 1.2)
                .accessibilityHidden(true)
            }
        }
    }

    /// Liquid-glass lens with the refracted, magnified dial inside it.
    private func lens(center: CGPoint) -> some View {
        let width = 100 + min(46, abs(stretch) * 0.12)
        let height = 58 - min(10, abs(stretch) * 0.025)
        let lensCenter = CGPoint(x: center.x, y: lensY)
        return ZStack {
            Capsule().fill(tint)
                .frame(width: width, height: height)
                .modifier(LensGlass())
                .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
                .modifier(GenieSettle(trigger: landed))
                .position(lensCenter)
            // Refraction: the same dial, magnified around the lens and seen only through it.
            dial(center: center, magnified: true)
                .scaleEffect(1.16, anchor: UnitPoint(x: 0.5, y: lensCenter.y / (Self.height + Self.headroom)))
                .mask { Capsule().frame(width: width - 4, height: height - 4).modifier(GenieSettle(trigger: landed)).position(lensCenter) }
            // Glass: a bright top edge, a rim and a highlight that slides against the drag.
            ZStack {
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02), .clear], startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                Ellipse().fill(.white.opacity(0.2)).frame(width: width * 0.42, height: 7).blur(radius: 3)
                    .offset(x: -stretch * 0.03, y: -height / 2 + 7)
            }
            .frame(width: width, height: height)
            .modifier(GenieSettle(trigger: landed))
            .position(lensCenter)
        }
        .allowsHitTesting(false)
    }

    // MARK: Motion

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart == nil { spin?.cancel(); spin = nil; dragStart = position }   // catching a spinning wheel stops it
                let raw = (dragStart ?? 0) - value.translation.width / stepPoints
                let banded = rubberBand(raw)
                if Int(banded.rounded()) != Int(position.rounded()) { tick += 1 }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { position = banded; stretch = value.velocity.width }
            }
            .onEnded { value in
                dragStart = nil
                coast(velocity: -value.velocity.width / stepPoints)
            }
    }

    /// Past either end the dial gives a third as much.
    private func rubberBand(_ raw: CGFloat) -> CGFloat {
        let last = CGFloat(items.count - 1)
        return raw < 0 ? raw / 3 : raw > last ? last + (raw - last) / 3 : raw
    }

    /// Lets go like a real wheel: it keeps turning at the release speed, slows with friction, ticks past every
    /// section, then settles into the nearest one.
    private func coast(velocity start: CGFloat) {
        spin?.cancel()
        guard !reduceMotion, abs(start) > 1.2 else { roll(to: Int(position.rounded()), notify: true); return }
        spin = Task { @MainActor in
            var velocity = start                      // sections per second
            var last = Date()
            let lastIndex = CGFloat(items.count - 1)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(12))
                let now = Date(), dt = CGFloat(now.timeIntervalSince(last)); last = now
                velocity *= CGFloat(pow(0.06, Double(dt)))  // friction: about 94% of the speed is gone after a second
                var next = position + velocity * dt
                if next < -0.35 || next > lastIndex + 0.35 { next = min(max(next, -0.35), lastIndex + 0.35); velocity = 0 }
                if Int(next.rounded()) != Int(position.rounded()) { tick += 1 }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { position = next; stretch = velocity * stepPoints * 0.4 }
                if abs(velocity) < 0.9 { break }
            }
            guard !Task.isCancelled else { return }
            roll(to: Int(position.rounded()), notify: true)
        }
    }

    private func roll(to target: Int, notify: Bool) {
        spin?.cancel(); spin = nil
        let clamped = max(0, min(items.count - 1, target))
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.78)) {
            position = CGFloat(clamped); stretch = 0
        }
        guard notify, items.indices.contains(clamped), items[clamped].id != selection else { return }
        landed += 1
        selection = items[clamped].id
    }

    private func index(of id: String) -> Int { items.firstIndex { $0.id == id } ?? 0 }

    private func point(_ center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle.radians)), y: center.y + radius * CGFloat(sin(angle.radians)))
    }
}

/// The landing squeeze: narrower and taller, then wider and flatter, then still, anchored at the bottom like a genie
/// settling into its bottle.
private struct GenieSettle: ViewModifier {
    let trigger: Int
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: trigger) { view, scale in
            view.scaleEffect(x: scale.width, y: scale.height, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack(\.width) {
                SpringKeyframe(0.8, duration: 0.09)
                SpringKeyframe(1.1, duration: 0.18, spring: .bouncy)
                SpringKeyframe(1, duration: 0.24)
            }
            KeyframeTrack(\.height) {
                SpringKeyframe(1.18, duration: 0.09)
                SpringKeyframe(0.9, duration: 0.18, spring: .bouncy)
                SpringKeyframe(1, duration: 0.24)
            }
        }
    }
}

/// Real Liquid Glass where the system has it; elsewhere the hand-made glass in the lens carries the look.
private struct LensGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear.interactive(), in: Capsule())
        } else {
            content
        }
    }
}
