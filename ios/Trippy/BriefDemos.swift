import SwiftUI
import CoreLocation

// MARK: - Briefing demos
//
// Each card is a small, looping demo drawn in SwiftUI with the app's own styles, so it
// stays true when the UI changes. What carries information is real (a caption, a hashtag,
// text on the video, a stop and its time); everything else is drawn as soft sketch lines,
// the way a wireframe says "something goes here".

/// Sketch placeholder: a rounded bar standing in for text that doesn't matter here.
struct SketchLine: View {
    var width: CGFloat
    var height: CGFloat = 7
    var color: Color = .white
    var body: some View {
        Capsule().fill(color.opacity(0.32)).frame(width: width, height: height)
            .overlay(Capsule().strokeBorder(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// Sketch placeholder for an icon or avatar.
struct SketchDot: View {
    var size: CGFloat
    var color: Color = .white
    var square = false
    var body: some View {
        Group {
            if square { RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])) }
            else { Circle().strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])) }
        }
        .frame(width: size, height: size)
    }
}

/// A quick marker stroke: a loose loop around something that matters, drawn in one go.
struct ScribbleLoop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), rx = rect.width / 2 + 6, ry = rect.height / 2 + 5
        for i in 0...72 {
            let a = Double(i) / 72 * 2.12 * .pi - 0.5
            let wobble = 1 + 0.04 * sin(a * 2.7)
            let pt = CGPoint(x: c.x + rx * wobble * cos(a), y: c.y + ry * wobble * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// A quick wavy marker line under text.
struct ScribbleUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: rect.minX, y: rect.maxY))
        let steps = 6
        for i in 1...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            p.addQuadCurve(to: .init(x: x, y: rect.maxY), control: .init(x: x - rect.width / CGFloat(steps * 2), y: rect.maxY + (i.isMultiple(of: 2) ? 4 : -4)))
        }
        return p
    }
}

/// One short-video post, as a video or as photo slides. Layout only (no other app's branding):
/// what Trippy reads (text on the video, caption, hashtags, voice) is real and gets a quick
/// marker stroke; everything else is sketch lines.
struct PostMock: View {
    enum Kind { case video, slides }
    let kind: Kind
    let tint: Color
    var marks = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var slide = 0
    @State private var zoom = false

    private var image: String { kind == .video ? "TripRome" : "TripLisbon" }
    private var titles: [String] { kind == .video ? ["8 SPOTS TO EAT\nUNDER 10€ IN ROME"] : ["1 · MIRADOURO\nDA GRAÇA", "2 · PASTÉIS\nDE BELÉM", "3 · TIME OUT\nMARKET"] }
    private var caption: String { kind == .video ? "8 spots to eat under 10€ in Rome 🇮🇹" : "Lisbon in 3 slides ☀️" }
    private var tags: String { kind == .video ? "#rome #romefood" : "#lisbon #portugal" }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Image(image).resizable().scaledToFill().frame(width: w, height: h)
                    .scaleEffect(zoom ? 1.1 : 1).overlay(Color.black.opacity(0.3)).clipped()
                // Text on the video / slide, with a marker loop.
                Text(titles[slide]).font(.system(size: w * 0.085, weight: .black)).multilineTextAlignment(.center).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .padding(6)
                    .overlay { if marks { ScribbleLoop().trim(from: 0, to: drawn).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)) } }
                    .id(slide).transition(.opacity)
                    .position(x: w / 2, y: h * 0.34)
                // Top: back and search (sketched).
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: w * 0.05, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.55), lineWidth: 1).frame(height: h * 0.042)
                        .overlay(alignment: .leading) { SketchLine(width: w * 0.28, height: 5).padding(.leading, 8) }
                }
                .padding(.horizontal, w * 0.05).frame(maxHeight: .infinity, alignment: .top).padding(.top, h * 0.06)
                // Right rail: sketched icons, real Share.
                VStack(spacing: h * 0.024) {
                    SketchDot(size: w * 0.12)
                    ForEach(0..<3, id: \.self) { _ in VStack(spacing: 3) { SketchDot(size: w * 0.08); SketchLine(width: w * 0.06, height: 4) } }
                    Image(systemName: "arrowshape.turn.up.right.fill").font(.system(size: w * 0.075)).foregroundStyle(.white).shadow(radius: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, w * 0.035).padding(.bottom, h * 0.2)
                // Bottom: slide dots or a voice line, author (sketched), caption and hashtags (real, underlined).
                VStack(alignment: .leading, spacing: 5) {
                    if kind == .slides {
                        HStack(spacing: 4) { ForEach(0..<titles.count, id: \.self) { i in Capsule().fill(.white.opacity(i == slide ? 1 : 0.4)).frame(width: i == slide ? 14 : 5, height: 5) } }
                    } else {
                        Image(systemName: "waveform").font(.system(size: w * 0.05, weight: .bold)).foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    }
                    SketchLine(width: w * 0.26, height: 7)
                    Text(caption).font(.system(size: w * 0.042, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        .overlay(alignment: .bottom) { if marks { ScribbleUnderline().trim(from: 0, to: drawn).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).frame(height: 5).offset(y: 5) } }
                    Text(tags).font(.system(size: w * 0.04, weight: .bold)).foregroundStyle(.white)
                        .overlay(alignment: .bottom) { if marks { ScribbleUnderline().trim(from: 0, to: drawn).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).frame(height: 5).offset(y: 5) } }
                }
                .padding(.horizontal, w * 0.05).padding(.trailing, w * 0.16).padding(.bottom, h * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .task {
            if reduceMotion { drawn = 1; return }
            withAnimation(.easeInOut(duration: 0.9).delay(0.3)) { drawn = 1 }
            withAnimation(.linear(duration: 4)) { zoom = true }
            guard kind == .slides else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0))
                withAnimation(.easeInOut(duration: 0.35)) { slide = (slide + 1) % titles.count }
            }
        }
    }
}

/// Two phones (a video post and a slides post) slide together into one: same thing to Trippy.
/// Then the merged phone shares to Trippy and ends on the places it found.
struct ShareStage: View {
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var merged = false
    @State private var sharing = false
    @State private var round = 0

    var body: some View {
        ZStack {
            if sharing {
                phone(ShareFlowDemo(tint: tint) { restart() }, scale: 1)
                    .transition(.opacity)
            } else {
                // Slides phone behind, video phone in front; they meet in the middle.
                phone(PostMock(kind: .slides, tint: tint), scale: merged ? 1 : 0.7)
                    .rotationEffect(.degrees(merged ? 0 : 6))
                    .offset(x: merged ? 0 : width * 0.32, y: merged ? 0 : height * 0.04)
                    .opacity(merged ? 0 : 1)
                phone(PostMock(kind: .video, tint: tint), scale: merged ? 1 : 0.7)
                    .rotationEffect(.degrees(merged ? 0 : -6))
                    .offset(x: merged ? 0 : -width * 0.32, y: merged ? 0 : -height * 0.02)
                if !merged {
                    HStack {
                        label("Video"); Spacer(); label("Slides")
                    }
                    .frame(width: width * 1.25).offset(y: height * 0.42)
                }
            }
        }
        .id(round)
        .frame(width: width, height: height)
        .task(id: round) {
            if reduceMotion { merged = true; sharing = true; return }
            merged = false; sharing = false
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { merged = true }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut(duration: 0.3)) { sharing = true }
        }
    }

    private func restart() { withAnimation(.easeInOut(duration: 0.4)) { round += 1 } }

    private func label(_ text: String) -> some View {
        Text(text).font(Sketch.hand(.headline)).foregroundStyle(Sketch.ink)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.08), radius: 4, y: 2))
    }

    private func phone<Content: View>(_ content: Content, scale: CGFloat) -> some View {
        let corner = width * 0.14
        return content
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Sketch.ink, lineWidth: 4))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 12)
            .scaleEffect(scale)
    }
}

// MARK: Share a video

/// The merged post: Share → the iOS share sheet → Trippy → what it read → the places it found.
struct ShareFlowDemo: View {
    let tint: Color
    var onFinish: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 2        // 2 tap share, 3 sheet, 4 tap Trippy, 5 reading, 6 places
    @State private var read = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                PostMock(kind: .video, tint: tint, marks: false)
                    .overlay(alignment: .bottomTrailing) {
                        if phase == 2 { TapRing(size: w * 0.18).padding(.trailing, w * 0.01).padding(.bottom, h * 0.185) }
                    }
                if phase >= 3 && phase <= 4 { shareSheet(w: w, h: h).transition(.move(edge: .bottom)) }
                if phase >= 5 { trippy(w: w, h: h).transition(.opacity) }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .task { await loop() }
    }

    // The iOS share sheet: the post header, people, apps (sketched) and Trippy (real).
    private func shareSheet(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: h * 0.022) {
                HStack(spacing: 10) {
                    SketchDot(size: w * 0.13, color: .primary, square: true)
                    VStack(alignment: .leading, spacing: 5) { SketchLine(width: w * 0.4, height: 7, color: .primary); SketchLine(width: w * 0.26, height: 6, color: .primary) }
                }
                Divider()
                HStack(spacing: w * 0.05) { ForEach(0..<4, id: \.self) { _ in VStack(spacing: 4) { SketchDot(size: w * 0.14, color: .primary); SketchLine(width: w * 0.12, height: 5, color: .primary) } } }
                Divider()
                HStack(spacing: w * 0.05) {
                    ForEach(0..<3, id: \.self) { _ in VStack(spacing: 4) { SketchDot(size: w * 0.14, color: .primary, square: true); SketchLine(width: w * 0.1, height: 5, color: .primary) } }
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: w * 0.035, style: .continuous).fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .frame(width: w * 0.14, height: w * 0.14)
                            .overlay(Image("BrandMark").resizable().scaledToFit().padding(w * 0.022))
                            .overlay(RoundedRectangle(cornerRadius: w * 0.035, style: .continuous).strokeBorder(tint, lineWidth: phase == 4 ? 3 : 0))
                            .scaleEffect(phase == 4 ? 1.14 : 1)
                            .overlay { if phase == 4 { TapRing(size: w * 0.2) } }
                        Text("trippy").font(.system(size: w * 0.03, weight: .semibold))
                    }
                }
            }
            .padding(w * 0.055).padding(.bottom, h * 0.03)
            .background(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26).fill(.regularMaterial))
        }
        .environment(\.colorScheme, .dark)
    }

    // Trippy: what it read, then what it found.
    private func trippy(w: CGFloat, h: CGFloat) -> some View {
        let signals: [(String, String, String)] = [
            ("text.bubble", "Caption", "8 spots to eat under 10€ in Rome"),
            ("number", "Hashtags", "#rome #romefood"),
            ("textformat", "Text on screen", "SUPPLÌ · TRAPIZZINO · …"),
            ("waveform", "Voice", "“Via di San Francesco…”"),
            ("photo.stack", "Slides", "8 photos, one place each"),
        ]
        let places = [("I Supplì", "Trastevere"), ("Trapizzino", "Testaccio"), ("Forno Campo de’ Fiori", "Centro"), ("Pizzarium", "Prati")]
        return ZStack {
            Sketch.paper
            VStack(alignment: .leading, spacing: h * 0.018) {
                HStack(spacing: 8) {
                    Image("BrandMark").resizable().scaledToFit().frame(width: w * 0.09)
                    Text(phase == 5 ? "Reading the post" : "8 places found").font(.system(size: w * 0.058, weight: .bold)).foregroundStyle(Sketch.ink)
                        .contentTransition(.opacity)
                }
                if phase == 5 {
                    ForEach(Array(signals.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: i < read ? "checkmark.circle.fill" : s.0).font(.system(size: w * 0.045))
                                .foregroundStyle(i < read ? Sketch.sage : Sketch.inkFaint).frame(width: w * 0.07)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.1).font(.system(size: w * 0.038, weight: .bold)).foregroundStyle(Sketch.ink)
                                Text(s.2).font(.system(size: w * 0.032)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                            }
                        }
                        .opacity(i <= read ? 1 : 0.35)
                    }
                } else {
                    // The useful output: the spots, already on a map of the city.
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.paperDeep)
                        Path { p in
                            p.move(to: .init(x: 0, y: h * 0.15)); p.addCurve(to: .init(x: w * 0.84, y: h * 0.05), control1: .init(x: w * 0.3, y: h * 0.2), control2: .init(x: w * 0.5, y: 0))
                            p.move(to: .init(x: w * 0.42, y: 0)); p.addLine(to: .init(x: w * 0.36, y: h * 0.2))
                        }
                        .stroke(Sketch.rule, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        ForEach(Array([CGPoint(x: 0.2, y: 0.62), CGPoint(x: 0.36, y: 0.82), CGPoint(x: 0.5, y: 0.38), CGPoint(x: 0.7, y: 0.28),
                                       CGPoint(x: 0.6, y: 0.66), CGPoint(x: 0.82, y: 0.55)].enumerated()), id: \.offset) { i, pt in
                            Image(systemName: "mappin.circle.fill").font(.system(size: w * 0.06)).symbolRenderingMode(.palette).foregroundStyle(.white, tint)
                                .position(x: pt.x * w * 0.84, y: pt.y * h * 0.2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(height: h * 0.2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ForEach(Array(places.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: w * 0.07)).symbolRenderingMode(.palette).foregroundStyle(.white, tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.0).font(.system(size: w * 0.042, weight: .bold)).foregroundStyle(Sketch.ink)
                                Text(p.1).font(.system(size: w * 0.033)).foregroundStyle(Sketch.inkSoft)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 1)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    HStack(spacing: 6) {
                        SketchLine(width: w * 0.22, height: 6, color: Sketch.ink)
                        Text("+ 4 more").font(.system(size: w * 0.034, weight: .semibold)).foregroundStyle(Sketch.inkFaint)
                    }
                    Label("Pinned on your Rome map", systemImage: "map.fill").font(.system(size: w * 0.036, weight: .bold)).foregroundStyle(tint)
                        .padding(.top, 4)
                }
            }
            .padding(w * 0.08).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, h * 0.06)
        }
    }

    private func loop() async {
        if reduceMotion { phase = 6; return }
        await wait(0.8)
        set(3); await wait(1.0)
        set(4); await wait(0.7)
        set(5)
        for i in 1...5 { await wait(0.42); withAnimation(.snappy) { read = i } }
        await wait(0.6)
        set(6); await wait(3.4)
        if !Task.isCancelled { onFinish() }
    }
    private func set(_ value: Int) { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { phase = value } }
    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}

/// A finger tap: a ring that grows and fades.
struct TapRing: View {
    let size: CGFloat
    @State private var on = false
    var body: some View {
        Circle().strokeBorder(.white, lineWidth: 3).frame(width: size, height: size)
            .scaleEffect(on ? 1.6 : 0.6).opacity(on ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 0.6)) { on = true } }
    }
}

// MARK: A plan that works

/// One day building itself: the stay, an area, sights seen together, food nearby to pick from.
struct PlanDayDemo: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var drawn: CGFloat = 0

    private let rows: [(String, String, String, String)] = [
        ("house.fill", "9:30", "From your stay", "Trastevere · 15 min"),
        ("building.columns.fill", "10:00", "Colosseum", "+ Arch of Constantine, one visit"),
        ("building.columns.fill", "11:45", "Roman Forum", "+ Palatine Hill"),
        ("fork.knife", "14:00", "Lunch nearby", "3 picks, 4 min walk · swap any"),
        ("wineglass.fill", "19:30", "Aperitivo", "Monti · your saved bar"),
    ]
    private let points: [CGPoint] = [.init(x: 0.18, y: 0.78), .init(x: 0.62, y: 0.52), .init(x: 0.5, y: 0.36), .init(x: 0.7, y: 0.28), .init(x: 0.8, y: 0.62)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            VStack(alignment: .leading, spacing: 0) {
                // A sketched map: one area, the walk drawn as the day fills in.
                ZStack {
                    Sketch.paperDeep
                    Path { p in
                        p.move(to: .init(x: 0, y: h * 0.12)); p.addCurve(to: .init(x: w, y: h * 0.2), control1: .init(x: w * 0.3, y: h * 0.02), control2: .init(x: w * 0.6, y: h * 0.3))
                        p.move(to: .init(x: w * 0.3, y: 0)); p.addLine(to: .init(x: w * 0.38, y: h * 0.38))
                    }
                    .stroke(Sketch.rule, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    Ellipse().fill(tint.opacity(0.12)).frame(width: w * 0.62, height: h * 0.2).position(x: w * 0.64, y: h * 0.16)
                        .overlay(Text("Ancient Rome").font(.system(size: w * 0.032, weight: .bold)).foregroundStyle(tint).position(x: w * 0.68, y: h * 0.07))
                    RouteShape(points: points.prefix(max(1, shown)).map { .init(x: $0.x * w, y: $0.y * h * 0.4) })
                        .trim(from: 0, to: drawn)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
                    ForEach(0..<min(shown, points.count), id: \.self) { i in
                        Group {
                            if i == 0 { Image(systemName: "house.circle.fill").font(.system(size: w * 0.08)).foregroundStyle(Sketch.ink) }
                            else { Text("\(i)").font(.system(size: w * 0.034, weight: .heavy)).foregroundStyle(.white).frame(width: w * 0.065, height: w * 0.065).background(Circle().fill(tint)) }
                        }
                        .position(x: points[i].x * w, y: points[i].y * h * 0.4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: h * 0.4).clipped()
                VStack(alignment: .leading, spacing: h * 0.018) {
                    Text("DAY 2 · ANCIENT ROME").font(.system(size: w * 0.032, weight: .heavy)).tracking(1).foregroundStyle(tint)
                    ForEach(0..<min(shown, rows.count), id: \.self) { i in
                        let row = rows[i]
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.1).font(.system(size: w * 0.036, weight: .bold)).monospacedDigit().foregroundStyle(Sketch.ink).frame(width: w * 0.13, alignment: .leading)
                            Image(systemName: row.0).font(.system(size: w * 0.038)).foregroundStyle(i == 0 ? Sketch.ink : tint).frame(width: w * 0.06)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.2).font(.system(size: w * 0.04, weight: .bold)).foregroundStyle(Sketch.ink)
                                Text(row.3).font(.system(size: w * 0.032)).foregroundStyle(Sketch.inkSoft)
                            }
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if shown >= rows.count {
                        // The useful part: lunch is a choice, a few doors away.
                        Text("PICK YOUR LUNCH").font(.system(size: w * 0.03, weight: .heavy)).tracking(1).foregroundStyle(Sketch.inkFaint).padding(.top, 4)
                        HStack(spacing: 8) {
                            ForEach([("Roscioli", "4 min"), ("Supplizio", "6 min"), ("Da Enzo", "9 min")], id: \.0) { option in
                                VStack(alignment: .leading, spacing: 2) {
                                    Image(systemName: "fork.knife").font(.system(size: w * 0.04)).foregroundStyle(tint)
                                    Text(option.0).font(.system(size: w * 0.034, weight: .bold)).foregroundStyle(Sketch.ink).lineLimit(1)
                                    Text(option.1).font(.system(size: w * 0.028)).foregroundStyle(Sketch.inkSoft)
                                }
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Sketch.card))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(option.0 == "Roscioli" ? tint : Sketch.rule, lineWidth: option.0 == "Roscioli" ? 2 : 0.7))
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(w * 0.06)
                Spacer(minLength: 0)
            }
            .background(Sketch.paper)
        }
        .task {
            if reduceMotion { shown = rows.count; drawn = 1; return }
            while !Task.isCancelled {
                shown = 0; drawn = 0
                for i in 1...rows.count {
                    try? await Task.sleep(for: .seconds(0.65))
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = i }
                    withAnimation(.easeInOut(duration: 0.6)) { drawn = 1 }
                }
                try? await Task.sleep(for: .seconds(3.5))
            }
        }
    }
}

private struct RouteShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for (a, b) in zip(points, points.dropFirst()) {
            p.addQuadCurve(to: b, control: .init(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 16))
        }
        return p
    }
}

// MARK: Your world

/// The traveller's own globe, with the countries they just picked (or a sample), filling in.
struct WorldDemo: View {
    let tint: Color
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var texture: UIImage?
    @State private var count = 0

    private var visits: [VisitedPlace] {
        let mine = VisitedPlace.decode(storage)
        if !mine.isEmpty { return mine }
        // A sample when nothing is picked yet.
        return [("Italy", "IT", 41.9, 12.5), ("Spain", "ES", 40.4, -3.7), ("Greece", "GR", 37.98, 23.7), ("Portugal", "PT", 38.7, -9.1),
                ("Japan", "JP", 35.7, 139.7), ("Mexico", "MX", 19.4, -99.1)]
            .map { VisitedPlace(name: $0.0, countryCode: $0.1, latitude: $0.2, longitude: $0.3) }
    }
    private var countries: Int { Set(visits.compactMap(\.countryCode)).count }
    private var continentRows: [(String, Int, Int)] {
        let codes = Set(visits.compactMap { $0.countryCode?.uppercased() })
        let byContinent = Dictionary(grouping: codes, by: { WorldContinentCatalog.name(for: $0) })
        return byContinent.keys.filter { $0 != "Other" }.sorted { byContinent[$0]!.count > byContinent[$1]!.count }.prefix(3)
            .map { ($0, byContinent[$0]!.count, WorldContinentCatalog.count($0)) }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            VStack(spacing: h * 0.03) {
                Spacer(minLength: 0)
                BeenGlobe3DView(texture: texture, focus: visits.first?.coordinate, focusID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                dark: true, reduceMotion: reduceMotion)
                    .frame(width: w * 0.86, height: w * 0.86)
                VStack(spacing: 4) {
                    Text("\(count)").font(.system(size: w * 0.16, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("countries · \(Int((Double(count) / 195 * 100).rounded()))% of the world").font(.system(size: w * 0.04, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 6) {
                    ForEach(Array(Set(visits.compactMap(\.countryCode))).sorted().prefix(6), id: \.self) { code in
                        Text(WorldGlobeView.flag(code)).font(.system(size: w * 0.06))
                    }
                }
                // The useful part: how far along each continent is.
                VStack(spacing: 6) {
                    ForEach(continentRows, id: \.0) { name, seen, total in
                        HStack(spacing: 8) {
                            Text(name).font(.system(size: w * 0.034, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).frame(width: w * 0.3, alignment: .leading)
                            GeometryReader { bar in
                                Capsule().fill(.white.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(WorldContinentCatalog.colors[name] ?? tint).frame(width: bar.size.width * CGFloat(seen) / CGFloat(max(total, 1)) * (count > 0 ? 1 : 0))
                                    }
                            }
                            .frame(height: 6)
                            Text("\(seen)/\(total)").font(.system(size: w * 0.03, weight: .bold)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                                .frame(width: w * 0.12, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, w * 0.08)
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: count)
                Spacer(minLength: 0)
            }
            .frame(width: w, height: h)
            .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.09), Color(red: 0.1, green: 0.11, blue: 0.16)], startPoint: .top, endPoint: .bottom))
        }
        .task {
            let key = GlobeTextureKey(dark: true, satellite: false, style: "brief-world-\(countries)")
            texture = await GlobeTextureBuilder.shared.texture(key: key, shapes: nil, visits: visits, visitedCodes: Set(visits.compactMap { $0.countryCode?.uppercased() }))
            if reduceMotion { count = countries; return }
            for i in 0...countries { withAnimation(.snappy) { count = i }; try? await Task.sleep(for: .seconds(0.12)) }
        }
    }
}
