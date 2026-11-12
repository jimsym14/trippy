import MapKit
import SwiftUI

// MARK: - Three ways to see a plan
//
// Plan: the days, with ideas and recommendations to build on. Map: every day on one map, one day at a time.
// Must-see: the checklist of what the trip shouldn't miss, each place with our three-part rating.

enum GuideMode: String, CaseIterable, Identifiable {
    case plan, map, mustSee
    var id: String { rawValue }
    var title: String { switch self { case .plan: "Plan"; case .map: "Map"; case .mustSee: "Must-see" } }
    var symbol: String { switch self { case .plan: "list.bullet.below.rectangle"; case .map: "map.fill"; case .mustSee: "checkmark.seal.fill" } }
}

struct GuideModePicker: View {
    @Binding var mode: GuideMode
    let tint: Color
    var mustSeeLeft: Int = 0
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(GuideMode.allCases) { item in
                let on = mode == item
                Button {
                    TrippyHaptics.selection()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { mode = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .bold)).symbolEffect(.bounce, value: on)
                        Text(item.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(on ? Sketch.paper : Sketch.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background { if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "mode", in: space) } }
                    .contentShape(Capsule())
                    // A notification badge on the segment's top corner, like an app icon's: the label stays centred.
                    .overlay(alignment: .topTrailing) {
                        if item == .mustSee && mustSeeLeft > 0 {
                            Text(mustSeeLeft > 99 ? "99+" : "\(mustSeeLeft)").font(Sketch.text(11, "ExtraBold", relativeTo: .caption2)).monospacedDigit()
                                .foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20).fixedSize()
                                .background(Capsule().fill(Sketch.coral))
                                .overlay(Capsule().strokeBorder(Sketch.card, lineWidth: 2))
                                .contentTransition(.numericText())
                                .offset(x: 4, y: -8)
                                .accessibilityLabel("\(mustSeeLeft) not seen yet")
                        }
                    }
                }
                .buttonStyle(SketchPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3))
    }
}

// MARK: - Our rating

/// Three short scores instead of one number, each from data we hold (no model, no paid ratings):
/// Iconic: how famous and significant it is (Wikipedia editions, the city's guide).
/// Loved: how much travellers and creators recommend it, less when they call it overhyped or a tourist trap.
/// Worth the time: what you get for the hours and money it takes.
struct PlaceRating: Equatable {
    let iconic: Int
    let loved: Int?
    let worth: Int
    let line: String

    static func of(_ place: GuidePlace, minutes: Int) -> PlaceRating {
        let fame = place.fame
        let iconic = fame >= 100 ? 5 : fame >= 50 ? 4 : fame >= 25 ? 3 : fame >= 10 ? 2 : fame > 0 || place.fromWikivoyage ? 1 : 0
        var signals = 0, loved = 0
        if place.videoCount > 0 || place.fromVideo { loved += min(3, max(1, place.videoCount)); signals += 1 }
        if place.fromWikivoyage { loved += 1; signals += 1 }
        if place.personal { loved += 1; signals += 1 }
        if place.tags.contains("touristy:low") { loved += 1; signals += 1 }
        if place.tags.contains("touristy:high") { loved -= 1; signals += 1 }
        if let rating = place.rating, let scale = place.ratingScale, scale > 0 { loved += Int((rating / scale * 5 - 3).rounded()); signals += 1 }
        let lovedScore = signals == 0 ? nil : max(1, min(5, loved))
        // A short visit to something remarkable is worth more than a half day at something minor.
        var worth = Double(max(iconic, lovedScore ?? iconic))
        worth += minutes <= 45 ? 1 : minutes >= 150 ? -1 : 0
        if let price = place.priceMax { worth += price == 0 ? 0.5 : price > 25 ? -0.5 : 0 }
        if place.tags.contains("touristy:high") { worth -= 0.5 }
        let worthScore = max(1, min(5, Int(worth.rounded())))
        let parts = [iconic >= 4 ? "A landmark" : iconic >= 2 ? "Well known" : nil,
                     (lovedScore ?? 0) >= 4 ? "loved by travellers" : nil,
                     minutes <= 45 ? "quick to see" : minutes >= 150 ? "takes a while" : nil].compactMap { $0 }
        let line = parts.isEmpty ? "" : (parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst())
        return PlaceRating(iconic: iconic, loved: lovedScore, worth: worthScore, line: line)
    }
}

struct RatingBars: View {
    let rating: PlaceRating
    var tint: Color = Sketch.clay
    var body: some View {
        HStack(spacing: 14) {
            bar("Iconic", rating.iconic, Sketch.ochre)
            bar("Loved", rating.loved, Sketch.coral)
            bar("Worth it", rating.worth, Sketch.sage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Iconic \(rating.iconic) of 5, loved \(rating.loved.map { "\($0) of 5" } ?? "not known"), worth the time \(rating.worth) of 5")
    }
    private func bar(_ title: String, _ value: Int?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(Sketch.inkFaint)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(value.map { index < $0 } ?? false ? color : Sketch.rule).frame(width: 9, height: 5)
                }
            }
        }
    }
}

// MARK: - Must-see

struct MustSeeView: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    var onAdd: (String, String) -> Void          // place id, date
    var onShowDay: (String) -> Void              // date
    @State private var burst: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Item: Identifiable { let place: GuidePlace; let date: String?; let rating: PlaceRating; var id: String { place.id } }

    /// The plan's sights, then the city's most significant ones the plan left out. Best known first.
    static func items(_ ctx: GuideContext) -> [Item] {
        var dateOf: [String: String] = [:], minutes: [String: Int] = [:]
        for day in ctx.days {
            for stop in day.stops where stop.slot == nil && !stop.place.isFood {
                dateOf[stop.place.id] = dateOf[stop.place.id] ?? day.date; minutes[stop.place.id] = stop.durationMinutes
            }
        }
        let grouped = Set(ctx.model.days.flatMap { $0.stops.flatMap(\.includes) })
        let planned = dateOf.keys.compactMap { ctx.model.places[$0] }
        let missing = ctx.model.places.values.filter { p in
            dateOf[p.id] == nil && !grouped.contains(p.id) && !p.isFood && !p.isSlotPlaceholder && p.coordinate != nil && (p.fame >= 20 || p.personal)
        }
        return (planned + missing).map { Item(place: $0, date: dateOf[$0.id], rating: PlaceRating.of($0, minutes: minutes[$0.id] ?? 90)) }
            .sorted { ($0.place.personal ? 1 : 0, $0.rating.iconic, $0.rating.loved ?? 0, $0.place.name) > ($1.place.personal ? 1 : 0, $1.rating.iconic, $1.rating.loved ?? 0, $1.place.name) }
            .prefix(24).map { $0 }
    }

    var body: some View {
        let items = Self.items(ctx)
        let done = items.filter { edits.checklistDone.contains("seen|" + $0.id) }.count
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(done) of \(items.count) seen").font(Sketch.display(.title2, weight: .bold)).contentTransition(.numericText())
                    Spacer()
                    Text(items.filter { $0.date == nil }.isEmpty ? "All in the plan" : "\(items.filter { $0.date == nil }.count) not planned yet")
                        .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Sketch.rule)
                        Capsule().fill(Sketch.sage).frame(width: items.isEmpty ? 0 : geometry.size.width * CGFloat(done) / CGFloat(items.count))
                    }
                }
                .frame(height: 8)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: done)
                Text("Our rating has three parts: how iconic a place is, how loved it is by travellers and creators, and whether it's worth the time it takes.")
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item).atlasRise(index)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        let key = "seen|" + item.id
        let seen = edits.checklistDone.contains(key)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55)) {
                    if seen { edits.checklistDone.remove(key) } else { edits.checklistDone.insert(key); burst = item.id }
                }
                seen ? TrippyHaptics.light() : TrippyHaptics.success()
            } label: {
                ZStack {
                    Circle().strokeBorder(seen ? Sketch.sage : Sketch.rule, lineWidth: 2).background(Circle().fill(seen ? Sketch.sage : .clear))
                    if seen { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Sketch.paper).transition(.scale.combined(with: .opacity)) }
                }
                .frame(width: 30, height: 30)
                .overlay { if burst == item.id { CheckBurst().allowsHitTesting(false) } }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(seen ? "Seen \(item.place.name)" : "Mark \(item.place.name) as seen")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.place.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).strikethrough(seen, color: Sketch.inkFaint)
                        .foregroundStyle(seen ? Sketch.inkSoft : Sketch.ink).fixedSize(horizontal: false, vertical: true)
                    if item.place.personal { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Sketch.coral) }
                }
                if !item.rating.line.isEmpty { Text(item.rating.line).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
                RatingBars(rating: item.rating)
                if let date = item.date {
                    Button { onShowDay(date) } label: {
                        Label(GuideDates.format(date, "EEE d MMM"), systemImage: "calendar").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.sky)
                            .frame(minHeight: 32)
                    }.buttonStyle(SketchPressStyle())
                } else {
                    Menu {
                        ForEach(ctx.days) { day in
                            Button("\(GuideDates.format(day.date, "EEEE d MMM"))") {
                                TrippyHaptics.success(); withAnimation(.snappy) { onAdd(item.id, day.date) }
                            }
                        }
                    } label: {
                        Label("Add to a day", systemImage: "plus.circle.fill").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.clay)
                            .padding(.horizontal, 10).frame(minHeight: 32).background(Capsule().fill(Sketch.clay.opacity(0.1)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(seen ? Sketch.sage.opacity(0.4) : Sketch.rule.opacity(0.8), lineWidth: seen ? 1.2 : 0.7))
    }
}

/// A small ring of dots that flies out when something is ticked off.
private struct CheckBurst: View {
    @State private var out = false
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle().fill([Sketch.sage, Sketch.ochre, Sketch.coral, Sketch.sky][index % 4]).frame(width: 5, height: 5)
                    .offset(x: out ? 24 : 4).rotationEffect(.degrees(Double(index) * 45)).opacity(out ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { out = true } }
    }
}

// MARK: - Map

struct GuideMapMode: View {
    let ctx: GuideContext
    @State private var day: String?
    var body: some View {
        let shown = day.map { d in ctx.days.filter { $0.date == d } } ?? ctx.days
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All days", nil, Sketch.ink)
                    ForEach(ctx.days) { d in chip(GuideDates.format(d.date, "EEE d"), d.date, Sketch.dayColor(d.index)) }
                }
            }
            GuideMap(days: shown, height: 520, interactive: true, base: ctx.base)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .animation(.snappy, value: day)
            ForEach(shown) { d in
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.title).font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.dayColor(d.index))
                    Text(d.stops.map(\.place.name).joined(separator: " → ")).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                }
            }
        }
    }
    private func chip(_ title: String, _ value: String?, _ tint: Color) -> some View {
        let on = day == value
        return Button { TrippyHaptics.selection(); withAnimation(.snappy) { day = value } } label: {
            Text(title).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(on ? .white : tint)
                .padding(.horizontal, 12).frame(minHeight: 40).background(Capsule().fill(on ? tint : tint.opacity(0.12)))
        }.buttonStyle(SketchPressStyle())
    }
}
