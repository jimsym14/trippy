import SwiftUI

// MARK: - Range calendar

/// One calendar: tap the first day, then the last. Days in between are shaded.
struct RangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date
    var maxNights = 30
    @State private var month: Date
    @State private var pickingEnd = false
    static let en = Locale(identifier: "en_GB")
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.locale = Locale(identifier: "en_GB"); return c
    }()

    init(start: Binding<Date>, end: Binding<Date>) {
        _start = start; _end = end
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2
        _month = State(initialValue: c.date(from: c.dateComponents([.year, .month], from: start.wrappedValue)) ?? .now)
    }

    /// Past months can't be picked; nil-safe, so a calendar hiccup never traps.
    private var canGoBack: Bool {
        let today = Date()
        guard let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else { return true }
        return month > thisMonth
    }

    private var nights: Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0 }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                endpoint("Arrive", start, active: !pickingEnd) { pickingEnd = false }
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                    Text(nights == 0 ? "day trip" : "\(nights) \(nights == 1 ? "night" : "nights")")
                        .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                        .contentTransition(.numericText()).fixedSize()
                }
                endpoint("Leave", end, active: pickingEnd) { pickingEnd = true }
            }
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(!canGoBack)
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(Self.en))).font(Sketch.display(.headline, weight: .semibold))
                    .contentTransition(.opacity)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Sketch.ink)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, d in
                    Text(d).font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(days().enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 40) }
                }
            }
            .id(month)
            .transition(.opacity)
            Text(pickingEnd ? "Now tap the day you leave" : "Tap the day you arrive")
                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
        }
        .animation(.snappy(duration: 0.25), value: month)
    }

    private func endpoint(_ title: String, _ date: Date, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(active ? Sketch.clay : Sketch.inkFaint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(date.formatted(.dateTime.day().locale(Self.en))).font(Sketch.display(.title, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(date.formatted(.dateTime.month(.abbreviated).locale(Self.en))).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                        Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Self.en))).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(active ? Sketch.clay.opacity(0.1) : Sketch.paperDeep))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(active ? Sketch.clay.opacity(0.5) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(SketchPressStyle())
        .environment(\.locale, Locale(identifier: "en_GB"))
        .accessibilityLabel("\(title) \(date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Self.en)))")
    }

    private func cell(_ day: Date) -> some View {
        let s = calendar.startOfDay(for: start), e = calendar.startOfDay(for: end), d = calendar.startOfDay(for: day)
        let past = d < calendar.startOfDay(for: .now)
        let isStart = d == s, isEnd = d == e, inside = d > s && d < e
        let band = Sketch.clay.opacity(0.16)
        return Button { pick(d) } label: {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle().fill((inside || (isEnd && s != e)) ? band : .clear)
                    Rectangle().fill((inside || (isStart && s != e)) ? band : .clear)
                }
                .frame(height: 36)
                if isStart || isEnd { Circle().fill(Sketch.ink).frame(width: 36, height: 36) }
                Text(day.formatted(.dateTime.day().locale(Self.en))).font(Sketch.text(14, isStart || isEnd ? "Bold" : "Medium", relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(isStart || isEnd ? Sketch.paper : past ? Sketch.inkFaint.opacity(0.5) : Sketch.ink)
                if calendar.isDateInToday(d) && !(isStart || isEnd) {
                    Circle().fill(Sketch.clay).frame(width: 4, height: 4).offset(y: 12)
                }
            }
            .frame(height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(past)
        .accessibilityLabel(day.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Self.en)))
        .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
    }

    private func pick(_ day: Date) {
        withAnimation(.snappy(duration: 0.22)) {
            if !pickingEnd || day < calendar.startOfDay(for: start) {
                start = day; end = day; pickingEnd = true
            } else {
                let limit = calendar.date(byAdding: .day, value: maxNights, to: calendar.startOfDay(for: start)) ?? day
                end = min(day, limit); pickingEnd = false
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func shift(_ by: Int) { if let next = calendar.date(byAdding: .month, value: by, to: month) { month = next } }

    private func days() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }
}

// MARK: - Interests

/// Broad interests that open into specific ones. IDs match the planner's
/// preference catalog, so each tap steers retrieval and ranking.
struct InterestGroup: Identifiable {
    let id: String, title: String, symbol: String, tint: Color
    let children: [InterestChild]
    struct InterestChild: Identifiable { let id: String, title: String; var onlyIn: [String] = [] }

    static let spain = ["barcelona", "madrid", "sevilla", "seville", "valencia", "granada", "malaga", "málaga", "bilbao", "san sebastian", "spain", "ibiza", "mallorca"]
    static let all: [InterestGroup] = [
        .init(id: "sights", title: "Sights & culture", symbol: "building.columns", tint: Sketch.sky, children: [
            .init(id: "museums", title: "Museums"), .init(id: "architecture", title: "Architecture"),
            .init(id: "gaudi", title: "Gaudí", onlyIn: ["barcelona"]), .init(id: "historic_places", title: "Historic sites"),
            .init(id: "churches", title: "Churches"), .init(id: "art_galleries", title: "Galleries")]),
        .init(id: "food", title: "Food", symbol: "fork.knife", tint: Sketch.clay, children: [
            .init(id: "tapas", title: "Tapas", onlyIn: spain), .init(id: "catalan_food", title: "Catalan food", onlyIn: ["barcelona", "girona"]),
            .init(id: "seafood", title: "Seafood"), .init(id: "street_food", title: "Street food"),
            .init(id: "vegan_food", title: "Vegan"), .init(id: "desserts", title: "Sweets")]),
        .init(id: "coffee", title: "Coffee & brunch", symbol: "cup.and.saucer", tint: Sketch.ochre, children: [
            .init(id: "specialty_coffee", title: "Specialty coffee"), .init(id: "bakeries", title: "Bakeries"), .init(id: "brunch", title: "Brunch")]),
        .init(id: "outdoors", title: "Nature & beach", symbol: "leaf", tint: Sketch.sage, children: [
            .init(id: "parks", title: "Parks"), .init(id: "beaches", title: "Beaches"),
            .init(id: "viewpoints", title: "Views & sunsets"), .init(id: "day_trips", title: "Day trips")]),
        .init(id: "nightlife", title: "Nightlife", symbol: "wineglass", tint: Sketch.plum, children: [
            .init(id: "cocktail_bars", title: "Cocktails"), .init(id: "wine_bars", title: "Wine bars"), .init(id: "bars", title: "Bars"),
            .init(id: "pubs", title: "Pubs"), .init(id: "clubs", title: "Clubs"), .init(id: "live_music", title: "Live music")]),
        .init(id: "shopping", title: "Markets & shops", symbol: "bag", tint: Sketch.coral, children: [
            .init(id: "markets", title: "Food markets"), .init(id: "vintage", title: "Vintage"),
            .init(id: "bookshops", title: "Bookshops"), .init(id: "local_design", title: "Local design")]),
        .init(id: "events", title: "Events", symbol: "ticket", tint: Sketch.sky, children: [
            .init(id: "concerts", title: "Concerts"), .init(id: "festivals", title: "Festivals"),
            .init(id: "exhibitions", title: "Exhibitions"), .init(id: "sports", title: "Sports")]),
    ]

    func children(for city: String) -> [InterestChild] {
        let c = city.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return children.filter { $0.onlyIn.isEmpty || $0.onlyIn.contains { c.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) } }
    }
}

struct InterestPicker: View {
    @Binding var groups: Set<String>
    @Binding var tags: Set<String>
    let city: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(InterestGroup.all) { group in
                    let on = groups.contains(group.id)
                    Button { toggle(group) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: group.symbol).font(.system(size: 13, weight: .semibold))
                            Text(group.title)
                            if on {
                                let count = tags.intersection(group.children.map(\.id)).count
                                if count > 0 { Text("\(count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Sketch.paper.opacity(0.25))) }
                            }
                        }
                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                        .background(Capsule().fill(on ? group.tint : Sketch.paperDeep))
                    }
                    .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            ForEach(InterestGroup.all.filter { groups.contains($0.id) }) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Rectangle().fill(group.tint).frame(width: 3, height: 14).clipShape(Capsule())
                        Text("Within \(group.title.lowercased())").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(Array(group.children(for: city).enumerated()), id: \.element.id) { index, child in
                            SubInterestChip(title: child.title, tint: group.tint, on: tags.contains(child.id), delay: reduceMotion ? 0 : Double(index) * 0.04) {
                                withAnimation(.snappy(duration: 0.2)) { if tags.contains(child.id) { tags.remove(child.id) } else { tags.insert(child.id) } }
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(group.tint.opacity(0.07)))
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity), removal: .opacity))
            }
        }
    }

    private func toggle(_ group: InterestGroup) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) {
            if groups.contains(group.id) { groups.remove(group.id); tags.subtract(group.children.map(\.id)) }
            else { groups.insert(group.id) }
        }
    }
}

private struct SubInterestChip: View {
    let title: String, tint: Color, on: Bool, delay: Double
    var action: () -> Void
    @State private var shown = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
                Text(title)
            }
            .font(Sketch.text(12, "SemiBold", relativeTo: .caption))
            .padding(.horizontal, 10).frame(minHeight: 32)
            .foregroundStyle(on ? Sketch.paper : Sketch.ink)
            .background(Capsule().fill(on ? tint : Sketch.card))
            .overlay(Capsule().strokeBorder(on ? .clear : tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(SketchPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.34, dampingFraction: 0.7).delay(delay)) { shown = true } }
    }
}

// MARK: - Section header

struct ComposerSectionHeader: View {
    let title: String
    let icon: TrippyIcon
    var tint: Color = Sketch.clay
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            TrippyIconView(icon: icon, size: 18, weight: 2, animated: true).foregroundStyle(tint)
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
            Spacer()
            if let trailing { Text(trailing).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
        }
    }
}

// MARK: - Card look

struct ComposerLookPicker: View {
    @Binding var look: ShelfLook
    let preview: ShelfTrip
    let autoDoodle: Doodle
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShelfCard(trip: preview, look: shown).frame(maxWidth: .infinity).allowsHitTesting(false)
                .animation(.snappy, value: look)
            Picker("Card", selection: $look.style) {
                ForEach(ShelfCardStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 4) {
                ForEach(Sketch.pigments, id: \.0) { name, color in
                    let on = (look.pigment ?? "clay") == name
                    Button { look.pigment = name } label: {
                        Circle().fill(color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Sketch.ink, lineWidth: on ? 2 : 0).padding(-3))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain).accessibilityLabel(name.capitalized).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    doodleButton(nil, label: "Auto")
                    ForEach(Doodle.allCases) { doodleButton($0, label: $0.label) }
                }
                .padding(.vertical, 2)
            }
        }
    }
    private var shown: ShelfLook { var l = look; if l.doodle == nil { l.doodle = autoDoodle }; return l }
    private func doodleButton(_ doodle: Doodle?, label: String) -> some View {
        let selected = look.doodle == doodle
        return Button { withAnimation(.snappy) { look.doodle = doodle } } label: {
            VStack(spacing: 3) {
                DoodleView(doodle: doodle ?? autoDoodle, tint: Sketch.pigment(look.pigment), lineWidth: 1.6, animated: false)
                    .padding(9).frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Sketch.pigment(look.pigment).opacity(0.14) : Sketch.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Sketch.ink : Sketch.ink.opacity(0.08), lineWidth: selected ? 1.5 : 1))
                Text(label).font(Sketch.text(10, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            }
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Browse links

/// Outside search pages for getting there and somewhere to stay, prefilled.
enum TripLinks {
    static func travelTitle(mode: String, city: String) -> String {
        switch mode { case "train": "Trains to \(city.isEmpty ? "the city" : city)"; case "car": "Drive there"; default: "Browse flights" }
    }
    /// Dates as yyyy-MM-dd, or nil when flexible.
    static func travel(mode: String, city: String, start: String?, end: String?) -> URL? {
        let place = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch mode {
        case "train": return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(place)&travelmode=transit")
        case "car": return URL(string: "https://maps.apple.com/?daddr=\(place)&dirflg=d")
        default:
            var q = "Flights to \(city)"
            if let start, let end, !start.isEmpty, !end.isEmpty { q += " on \(start) through \(end)" }
            return URL(string: "https://www.google.com/travel/flights?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        }
    }
    static func stay(area: String, city: String, start: String?, end: String?, travelers: Int, airbnb: Bool) -> URL? {
        let place = area.isEmpty ? city : "\(area), \(city)"
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var dates = ""
        if let start, let end, !start.isEmpty, !end.isEmpty { dates = "&checkin=\(start)&checkout=\(end)" }
        return airbnb ? URL(string: "https://www.airbnb.com/s/\(q)/homes?adults=\(travelers)\(dates)")
                      : URL(string: "https://www.booking.com/searchresults.html?ss=\(q)&group_adults=\(travelers)\(dates)")
    }
}
