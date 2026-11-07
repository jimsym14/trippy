import SwiftUI
import MapKit

// MARK: - Area coverage
//
// A trip is also about which parts of a city you see. This section shows every
// area the planner found, how much of the trip each one is, which days visit it,
// and its character (estimated, from the notes pass): touristy, price, safety.

struct AreasSection: View {
    let ctx: GuideContext
    let onAddPlace: (String, String) -> Void      // place id, date
    @State private var expanded: Set<String> = []

    private var areas: [GuideArea] { ctx.model.areas }
    private var covered: [GuideArea] { areas.filter { !$0.days.isEmpty } }
    private var total: Double { max(areas.reduce(0) { $0 + $1.importance }, 1) }
    private func dayIndex(_ date: String) -> Int? { ctx.days.first { $0.date == date }?.index }

    var body: some View {
        if areas.isEmpty {
            Text("This plan was made before areas existed. Make it again to see them.")
                .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                summary
                VStack(spacing: 10) {
                    ForEach(covered.sorted { (firstDay($0) ?? 99, -$0.importance) < (firstDay($1) ?? 99, -$1.importance) }) { card($0) }
                }
                let missed = areas.filter { $0.days.isEmpty }.sorted { $0.importance > $1.importance }
                if !missed.isEmpty {
                    Text("NOT IN YOUR PLAN").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft).padding(.top, 4)
                    VStack(spacing: 10) { ForEach(missed.prefix(5)) { card($0) } }
                }
            }
        }
    }

    private func firstDay(_ area: GuideArea) -> Int? { area.days.compactMap(dayIndex).min() }

    /// "You'll see 5 of 10 areas" and one bar: each area's share of what's worth seeing.
    private var summary: some View {
        let share = covered.reduce(0) { $0 + $1.importance } / total
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(covered.count) of \(areas.count) areas")
                    .font(Sketch.display(.title3, weight: .bold))
                Spacer()
                Text("\(Int((share * 100).rounded()))% of the highlights")
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(areas.sorted { (firstDay($0) ?? 99, -$0.importance) < (firstDay($1) ?? 99, -$1.importance) }) { area in
                        let tint = firstDay(area).map(Sketch.dayColor) ?? Sketch.rule
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint)
                            .frame(width: max(4, geometry.size.width * area.importance / total - 2))
                    }
                }
            }
            .frame(height: 14)
            .accessibilityElement()
            .accessibilityLabel("Your plan covers \(covered.count) of \(areas.count) areas, \(Int((share * 100).rounded())) percent of the highlights")
            Text("Each block is an area, sized by how much there is to see. Coloured ones are in your days.")
                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
        }
    }

    private func card(_ area: GuideArea) -> some View {
        let days = area.days.compactMap { date in ctx.days.first { $0.date == date } }
        let open = expanded.contains(area.id)
        let tint = days.first.map { Sketch.dayColor($0.index) } ?? Sketch.inkFaint
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { if open { expanded.remove(area.id) } else { expanded.insert(area.id) } } } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(area.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                            .multilineTextAlignment(.leading)
                        if !area.vibe.isEmpty {
                            Text(area.vibe).font(Sketch.hand(.subheadline)).foregroundStyle(tint)
                        }
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        ForEach(days) { day in
                            Text("D\(day.index + 1)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(minHeight: 20).background(Capsule().fill(Sketch.dayColor(day.index)))
                        }
                    }
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Shows less" : "Shows more about this area")
            if !area.character.isEmpty {
                Text(area.character).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if area.touristy != nil || area.price != nil || area.safety != nil {
                HStack(spacing: 14) {
                    meter("Touristy", area.touristy, tint: Sketch.coral)
                    meter("Price", area.price, tint: Sketch.ochre)
                    meter("Safe", area.safety, tint: Sketch.sage)
                }
            }
            let planned = area.plannedIDs.count
            Text(days.isEmpty ? "\(area.placeIDs.count) places worth seeing" : "\(planned) of \(area.placeIDs.count) places planned")
                .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
            if open { places(area) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 14)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
    }

    private func meter(_ label: String, _ value: Int?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Capsule().fill(i <= (value ?? 0) ? tint : Sketch.rule).frame(width: 10, height: 5)
                }
            }
            Text(label).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label): \(value.map { "\($0) of 5" } ?? "unknown")")
    }

    /// The area's places: what's planned and what you could add, with a one-tap add.
    private func places(_ area: GuideArea) -> some View {
        let used = Set(ctx.days.flatMap { $0.stops.map(\.place.id) })
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(area.placeIDs.compactMap { ctx.model.places[$0] }.sorted { ($0.fame, $0.name) > ($1.fame, $1.name) }) { place in
                HStack(spacing: 10) {
                    PlacePhoto(place: place, tint: Sketch.inkSoft).frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(place.name).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).lineLimit(2)
                    Spacer(minLength: 4)
                    if used.contains(place.id) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.sage)
                            .accessibilityLabel("Planned")
                    } else {
                        Menu {
                            ForEach(ctx.days) { day in
                                Button("Day \(day.index + 1) · \(GuideDates.short(day.date))") { onAddPlace(place.id, day.date) }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Sketch.ink)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Add \(place.name) to a day")
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Day pieces

/// The day's areas as small tags under its title.
struct AreaTags: View {
    let areas: [GuideArea]
    let tint: Color
    var body: some View {
        if !areas.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.square").font(.system(size: 11, weight: .semibold))
                Text(areas.map(\.name).joined(separator: " · ")).lineLimit(1)
            }
            .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(tint)
            .accessibilityLabel("Areas: \(areas.map(\.name).joined(separator: ", "))")
        }
    }
}

/// Every day starts at the base.
struct BaseStartRow: View {
    let base: GuideBase
    let minutes: Int?
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "house.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(Sketch.ink))
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 1) {
                Text("From \(base.name)").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                if let minutes {
                    Text(minutes > 25 ? "~\(minutes) min to the first stop · taxi or transit" : "~\(minutes) min to the first stop")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Gentle, one-tap ideas while editing a day; ignoring them is fine.
struct SuggestionStrip: View {
    let suggestions: [GuideSuggestion]
    let tint: Color
    let apply: (GuideSuggestion) -> Void
    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("IDEAS FOR THIS DAY").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            Button { apply(suggestion) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: suggestion.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(suggestion.text).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.ink)
                                        Text(suggestion.detail).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                                    }
                                }
                                .padding(.horizontal, 12).frame(minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                            .buttonStyle(SketchPressStyle())
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// What the planner proposed and the traveller took out, with a way back.
struct LeftOutSection: View {
    let items: [(date: String, place: GuidePlace)]
    let onRestore: (String, String) -> Void
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full").foregroundStyle(Sketch.inkSoft)
                    Text("Left out").font(Sketch.display(.title3))
                    Text("\(items.count)").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Sketch.paperDeep))
                }
                Text("Planned stops you removed. Put any of them back on its day.")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                ForEach(items, id: \.place.id) { item in
                    HStack(spacing: 12) {
                        PlacePhoto(place: item.place, tint: Sketch.inkSoft).frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name).font(Sketch.text(15, "SemiBold", relativeTo: .body)).lineLimit(2)
                            Text("\(item.place.categoryLabel) · was on \(GuideDates.short(item.date))")
                                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                        }
                        Spacer(minLength: 4)
                        Button("Put back") { onRestore(item.place.id, item.date) }
                            .font(Sketch.text(13, "Bold", relativeTo: .footnote))
                            .padding(.horizontal, 12).frame(minHeight: 36).background(Capsule().fill(Sketch.paperDeep))
                            .frame(minHeight: 44)
                            .accessibilityLabel("Put \(item.place.name) back")
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }
}

// MARK: - Food & nightlife scene

/// What eating and going out is like in this city (from its Wikivoyage guide),
/// and a few places to start with, each with the reason it is there.
struct SceneSection: View {
    let scene: GuideScene
    let ctx: GuideContext
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let drink = scene.drink { part("drink", title: "Drinks & going out", symbol: "wineglass", tint: Sketch.plum, drink) }
            if let eat = scene.eat { part("eat", title: "Eating out", symbol: "fork.knife", tint: Sketch.sage, eat) }
            if let url = scene.sourceURL {
                Link(destination: url) {
                    Label("From the Wikivoyage city guide", systemImage: "book.closed")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                }
            }
        }
    }

    private func part(_ key: String, title: String, symbol: String, tint: Color, _ part: GuideScene.Part) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(Sketch.text(16, "Bold", relativeTo: .headline)).foregroundStyle(tint)
            if !part.text.isEmpty {
                let paragraphs = part.text.components(separatedBy: "\n\n")
                let showAll = open.contains(key)
                Text((showAll ? paragraphs : Array(paragraphs.prefix(1))).joined(separator: "\n\n"))
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.ink.opacity(0.85))
                    .lineLimit(showAll ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if paragraphs.count > 1 || part.text.count > 220 {
                    Button(showAll ? "Less" : "Read more") {
                        withAnimation(.snappy) { if showAll { open.remove(key) } else { open.insert(key) } }
                    }
                    .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(tint)
                }
            }
            if !part.picks.isEmpty {
                Text("WHERE TO START").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.inkSoft).padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach(Array(part.picks.enumerated()), id: \.element.id) { index, pick in
                        pickRow(pick, tint: tint)
                        if index < part.picks.count - 1 { Divider().overlay(Sketch.rule) }
                    }
                }
            }
        }
        .sketchCard(padding: 14)
    }

    private func pickRow(_ pick: GuideScene.Pick, tint: Color) -> some View {
        let place = ctx.model.places[pick.placeID]
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if let place { PlacePhoto(place: place, tint: tint) } else { Rectangle().fill(tint.opacity(0.12)) }
            }
            .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pick.name).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).lineLimit(1)
                    if pick.planned {
                        Text("In your plan").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(tint)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.12)))
                    }
                }
                if !pick.reason.isEmpty {
                    Text(pick.reason).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
