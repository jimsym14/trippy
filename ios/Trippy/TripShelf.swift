import SwiftUI

/// What the shelf needs to know about a trip; built by the app from its own model.
struct ShelfTrip: Identifiable, Hashable {
    let id: UUID
    let title: String
    let city: String
    let flag: String?
    let startDate: String
    let endDate: String
    let travelers: Int
    let hasPlan: Bool
    let completed: Bool
    let colorHex: String?
    let emoji: String?
    let stops: Int
    let days: Int
}

enum ShelfCardStyle: String, Codable, CaseIterable, Identifiable {
    case postcard, ticket, polaroid
    var id: String { rawValue }
    var label: String { switch self { case .postcard: "Postcard"; case .ticket: "Ticket"; case .polaroid: "Photo" } }
}

struct ShelfLook: Codable, Equatable {
    var style: ShelfCardStyle = .postcard
    var doodle: Doodle?
    var pigment: String?
}

enum ShelfLookStore {
    private static let key = "trippy.shelf.looks.v1"
    static func load() -> [String: ShelfLook] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: ShelfLook].self, from: $0) } ?? [:]
    }
    static func save(_ looks: [String: ShelfLook]) {
        if let data = try? JSONEncoder().encode(looks) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct TripShelfView: View {
    let trips: [ShelfTrip]
    var onOpen: (UUID) -> Void
    var onEdit: (UUID) -> Void
    var onIdentity: (UUID) -> Void
    var onComplete: (UUID) -> Void
    var onDelete: (UUID) -> Void
    var onNew: () -> Void
    var journeys: [SavedJourney] = []
    var onWhereNext: (() -> Void)? = nil
    var onJourney: (() -> Void)? = nil

    @State private var looks = ShelfLookStore.load()
    @State private var styling: ShelfTrip?
    @State private var deleting: ShelfTrip?

    private var upcoming: [ShelfTrip] { trips.filter { !$0.completed && $0.hasPlan } }
    /// `-TrippyShelfCardsOnly YES` (debug): the rows of cards at the top, for screenshots.
    private static var cardsOnly: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "TrippyShelfCardsOnly")
        #else
        false
        #endif
    }
    private var ideas: [ShelfTrip] { trips.filter { !$0.completed && !$0.hasPlan } }
    private var past: [ShelfTrip] { trips.filter(\.completed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if (onWhereNext != nil || onJourney != nil) && !Self.cardsOnly { starters }
            if trips.isEmpty { emptyShelf }
            if !journeys.isEmpty && !Self.cardsOnly { journeyRow }
            if let next = upcoming.first, !Self.cardsOnly {
                NextTripCard(trip: next, look: look(next)) { onOpen(next.id) }
                    .contextMenu { menu(next) }
                    .overlay(alignment: .topTrailing) { cardActions(next).padding(12) }
            }
            if upcoming.count > 1 { row("Upcoming", trips: Array(upcoming.dropFirst())) }
            if !ideas.isEmpty { row("Drafts", trips: ideas) }
            if !past.isEmpty { stamps }
        }
        .onAppear { looks = ShelfLookStore.load() }
        .onChange(of: trips.map(\.id)) { _, _ in looks = ShelfLookStore.load() }
        .sheet(item: $styling) { trip in
            ShelfStyleSheet(trip: trip, look: Binding(get: { look(trip) }, set: { looks[trip.id.uuidString] = $0; ShelfLookStore.save(looks) }),
                            onIdentity: { styling = nil; onIdentity(trip.id) })
        }
        .confirmationDialog("Delete this trip?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { trip in
            Button("Delete “\(trip.title)”", role: .destructive) { GuideEditsStore.delete(trip.id); onDelete(trip.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("Its plan and your edits will be removed.") }
    }

    private func look(_ trip: ShelfTrip) -> ShelfLook {
        var look = looks[trip.id.uuidString] ?? ShelfLook()
        if look.doodle == nil { look.doodle = .suggested(title: trip.title, city: trip.city) }
        return look
    }

    @ViewBuilder private func menu(_ trip: ShelfTrip) -> some View {
        Button("Card style", systemImage: "paintbrush") { styling = trip }
        Button("Edit request", systemImage: "square.and.pencil") { onEdit(trip.id) }
        if !trip.completed { Button("Mark as done", systemImage: "checkmark.seal") { onComplete(trip.id) } }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = trip }
    }

    /// Delete and More, always visible on a card.
    private func cardActions(_ trip: ShelfTrip) -> some View {
        HStack(spacing: 6) {
            Button(role: .destructive) { deleting = trip } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(Sketch.coral)
                    .frame(width: 34, height: 34).raisedCircle()
            }
            .buttonStyle(SketchPressStyle()).accessibilityLabel("Delete \(trip.title)")
            Menu { menu(trip) } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Sketch.ink)
                    .frame(width: 34, height: 34).raisedCircle()
            }
            .accessibilityLabel("More for \(trip.title)")
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private func row(_ title: String, trips: [ShelfTrip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Sketch.display(.title3)).accessibilityAddTraits(.isHeader)
                Text("\(trips.count)").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(trips) { trip in
                        Button { onOpen(trip.id) } label: { ShelfCard(trip: trip, look: look(trip)) }
                            .buttonStyle(SketchPressStyle())
                            .contextMenu { menu(trip) }
                            .overlay(alignment: .topTrailing) { cardActions(trip).padding(8) }
                            .accessibilityLabel("\(trip.title), \(ShelfDates.range(trip))")
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    /// Two other ways to start: not sure where, or several places in one go.
    private var starters: some View {
        HStack(spacing: 12) {
            if let onWhereNext { starter("Where next?", "Picks made for you", doodle: .map, tint: Sketch.clay, action: onWhereNext) }
            if let onJourney { starter("Journey", "Several stops, one trip", doodle: .train, tint: Sketch.sky, action: onJourney) }
        }
    }

    private func starter(_ title: String, _ detail: String, doodle: Doodle, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                DoodleView(doodle: doodle, tint: tint, lineWidth: 2).frame(width: 44, height: 44)
                Text(title).font(Sketch.display(.title3, weight: .bold)).foregroundStyle(Sketch.ink)
                Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sketchCard(tint: tint, padding: 14)
        }
        .buttonStyle(SketchPressStyle())
    }

    private var journeyRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Journeys").font(Sketch.display(.title3)).accessibilityAddTraits(.isHeader)
            ForEach(journeys) { journey in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: journey.mode.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.sky)
                            .frame(width: 32, height: 32).background(Circle().fill(Sketch.sky.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(journey.name).font(Sketch.text(16, "Bold", relativeTo: .body)).lineLimit(1)
                            Text("\(GuideDates.format(journey.startDate, "d MMM")) – \(GuideDates.format(journey.endDate, "d MMM"))" + (journey.origin.map { " · from \($0)" } ?? ""))
                                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(zip(journey.tripIDs, journey.cities).enumerated()), id: \.element.0) { index, stop in
                                let planned = trips.first { $0.id == stop.0 }?.hasPlan ?? false
                                if index > 0 { Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Sketch.inkFaint) }
                                Button { onOpen(stop.0) } label: {
                                    HStack(spacing: 6) {
                                        Text("\(index + 1)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(.white)
                                            .frame(width: 20, height: 20).background(Circle().fill(Sketch.dayColor(index)))
                                        Text(stop.1).lineLimit(1)
                                        Image(systemName: planned ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 12))
                                            .foregroundStyle(planned ? Sketch.sage : Sketch.inkFaint)
                                    }
                                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.ink)
                                    .padding(.horizontal, 10).frame(minHeight: 44).background(Capsule().fill(Sketch.paperDeep))
                                }
                                .buttonStyle(SketchPressStyle())
                                .accessibilityLabel("Stop \(index + 1), \(stop.1), \(planned ? "planned" : "not planned yet")")
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                .sketchCard(padding: 14)
            }
        }
    }

    private var stamps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past trips").font(Sketch.display(.title3)).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 14)], spacing: 14) {
                ForEach(past) { trip in
                    Button { onOpen(trip.id) } label: { PassportStamp(trip: trip, look: look(trip)) }
                        .buttonStyle(SketchPressStyle()).contextMenu { menu(trip) }
                        .accessibilityLabel("\(trip.title), done")
                }
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            DoodleView(doodle: .balloon, tint: Sketch.coral).frame(width: 96, height: 96)
            Text("No trips yet").font(Sketch.display(.title2))
            Text("Describe a trip in one message to get a full plan.")
                .font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
            SketchPrimaryButton(title: "New trip", symbol: "plus", action: onNew).frame(maxWidth: 240).padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

enum ShelfDates {
    static func range(_ trip: ShelfTrip) -> String {
        guard !trip.startDate.isEmpty else { return trip.days > 0 ? "\(trip.days) days, dates open" : "Dates open" }
        let sameMonth = trip.startDate.prefix(7) == trip.endDate.prefix(7)
        let a = GuideDates.format(trip.startDate, sameMonth ? "d" : "d MMM")
        let b = trip.endDate.isEmpty ? "" : GuideDates.format(trip.endDate, "d MMM")
        return b.isEmpty ? GuideDates.format(trip.startDate, "d MMM") : "\(a) – \(b)"
    }
    static func countdown(_ trip: ShelfTrip) -> String? {
        guard let start = GuideDates.date(trip.startDate) else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        let days = Calendar.current.dateComponents([.day], from: today, to: start).day ?? 0
        if days > 1 { return "In \(days) days" }
        if days == 1 { return "Tomorrow" }
        if days == 0 { return "Today" }
        if let end = GuideDates.date(trip.endDate), end >= today { return "Now" }
        return nil
    }
    static func code(_ city: String) -> String {
        let known = ["barcelona": "BCN", "lisbon": "LIS", "lisboa": "LIS", "paris": "PAR", "london": "LON", "rome": "ROM",
                     "athens": "ATH", "madrid": "MAD", "berlin": "BER", "amsterdam": "AMS", "prague": "PRG", "vienna": "VIE"]
        let key = city.lowercased().trimmingCharacters(in: .whitespaces)
        return known[key] ?? String(city.folding(options: .diacriticInsensitive, locale: nil).filter(\.isLetter).prefix(3)).uppercased()
    }
}

private func shelfTint(_ trip: ShelfTrip, _ look: ShelfLook) -> Color {
    if let p = look.pigment { return Sketch.pigment(p) }
    if let hex = trip.colorHex { return Color(sketchHex: hex) }
    return Sketch.dayColor(Int(trip.id.uuid.0) % 6)  // stable across launches
}

// MARK: - Next trip

private struct NextTripCard: View {
    let trip: ShelfTrip
    let look: ShelfLook
    let open: () -> Void
    var body: some View {
        let color = shelfTint(trip, look)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("NEXT TRIP").font(Sketch.eyebrow).tracking(1.1).foregroundStyle(color)
                            if let c = ShelfDates.countdown(trip) { SketchTag(text: c, tint: color) }
                        }
                        Text(trip.title).font(Sketch.display(.title, weight: .bold)).foregroundStyle(Sketch.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(ShelfDates.range(trip)).font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    }
                    Spacer(minLength: 0)
                    DoodleView(doodle: look.doodle ?? .balloon, tint: color, lineWidth: 2.4)
                        .frame(width: 96, height: 96).padding(.top, 34)
                }
                .padding(20)
                .background(color.opacity(0.1))
                HStack(spacing: 0) {
                    stat(ShelfDates.code(trip.city), "city")
                    stat("\(trip.days)", trip.days == 1 ? "day" : "days")
                    stat("\(trip.stops)", "stops")
                    stat("\(trip.travelers)", trip.travelers == 1 ? "traveler" : "travelers")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.headline).foregroundStyle(Sketch.paper)
                        .frame(width: 44, height: 44).background(Circle().fill(Sketch.ink))
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .background(shape.fill(Sketch.card))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(SketchPressStyle())
        .accessibilityLabel("Next trip: \(trip.title), \(ShelfDates.range(trip))")
        .accessibilityHint("Opens the plan")
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).monospacedDigit()
            Text(label).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
        }
        .frame(minWidth: 64, alignment: .leading)
    }
}

// MARK: - Cards

struct ShelfCard: View {
    let trip: ShelfTrip
    let look: ShelfLook
    var body: some View {
        switch look.style {
        case .postcard: Postcard(trip: trip, look: look)
        case .ticket: TicketCard(trip: trip, look: look)
        case .polaroid: PhotoCard(trip: trip, look: look)
        }
    }
}

/// The default trip card: a tinted panel with the trip's doodle and city code, then when, what and how long.
/// One fixed size, so a row of them lines up; the top-right corner stays clear for the card's buttons.
private struct Postcard: View {
    let trip: ShelfTrip, look: ShelfLook
    var body: some View {
        let color = shelfTint(trip, look)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                DoodleView(doodle: look.doodle ?? .balloon, tint: color, lineWidth: 2.2).frame(width: 62, height: 62)
                Text(ShelfDates.code(trip.city)).font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(color)
            }
            .frame(width: 96).frame(maxHeight: .infinity)
            .background(color.opacity(0.14))
            VStack(alignment: .leading, spacing: 6) {
                // Clear of the delete and more buttons in the corner.
                Group {
                    if !trip.hasPlan { SketchTag(text: "Draft", tint: Sketch.ochre) }
                    else if let countdown = ShelfDates.countdown(trip) { SketchTag(text: countdown, tint: color) }
                    else { Color.clear.frame(height: 22) }
                }
                .padding(.trailing, 78).frame(height: 28, alignment: .leading)
                Text(trip.title).font(Sketch.display(.headline, weight: .bold)).foregroundStyle(Sketch.ink)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if !trip.city.isEmpty {
                    Text([trip.flag, trip.city].compactMap { $0 }.joined(separator: " "))
                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 2)
                Label(trip.hasPlan ? ShelfDates.range(trip) : "No plan yet", systemImage: "calendar")
                    .labelStyle(CompactLabel()).font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                    .foregroundStyle(trip.hasPlan ? Sketch.ink : Sketch.ochre).lineLimit(1)
                HStack(spacing: 12) {
                    if trip.days > 0 { Label("\(trip.days)", systemImage: "sun.max").accessibilityLabel("\(trip.days) days") }
                    if trip.stops > 0 { Label("\(trip.stops)", systemImage: "mappin.and.ellipse").accessibilityLabel("\(trip.stops) stops") }
                    Label("\(trip.travelers)", systemImage: "person.2").accessibilityLabel("\(trip.travelers) travelers")
                }
                .labelStyle(CompactLabel())
                .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300, height: 176)
        .background(shape.fill(Sketch.card))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
    }
}

/// An icon and its value close together: "📅 5 – 9 Dec  ☀ 5  📍 20".
private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 11, weight: .semibold)); configuration.title }
    }
}

private struct TicketCard: View {
    let trip: ShelfTrip, look: ShelfLook
    var body: some View {
        let color = shelfTint(trip, look)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(ShelfDates.code(trip.city)).font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(color)
                Spacer()
                TrippyIconView(icon: .plane, size: 20).foregroundStyle(Sketch.inkFaint)
            }
            Text(trip.title).font(Sketch.text(15, "Bold", relativeTo: .headline)).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Sketch.ink.opacity(0.15)).frame(height: 1).mask(HStack(spacing: 3) { ForEach(0..<40, id: \.self) { _ in Rectangle().frame(width: 3) } })
            HStack {
                Text(trip.hasPlan ? ShelfDates.range(trip) : "No plan yet").font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                Spacer()
                Text("\(trip.travelers) \(trip.travelers == 1 ? "traveler" : "travelers")").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
        }
        .padding(16)
        .frame(width: 240, alignment: .topLeading).frame(minHeight: 150)
        .background(TicketShape().fill(Sketch.card))
        .overlay(TicketShape().stroke(Sketch.ink.opacity(0.1), lineWidth: 1))
    }
}

private struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch: CGFloat = 9, y = rect.height * 0.66
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        notches.addEllipse(in: CGRect(x: rect.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        return Path(roundedRect: rect, cornerRadius: 16, style: .continuous).subtracting(notches)
    }
}

private struct PhotoCard: View {
    let trip: ShelfTrip, look: ShelfLook
    var body: some View {
        let color = shelfTint(trip, look)
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                color.opacity(0.16)
                DoodleView(doodle: look.doodle ?? .balloon, tint: color, lineWidth: 2.4).padding(26)
            }
            .frame(width: 168, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(trip.title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
                .frame(width: 168, alignment: .leading)
            Text(trip.hasPlan ? ShelfDates.range(trip) : "No plan yet").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
        }
        .padding(8).padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
    }
}

private struct PassportStamp: View {
    let trip: ShelfTrip, look: ShelfLook
    var body: some View {
        let color = shelfTint(trip, look)
        VStack(spacing: 2) {
            Text(ShelfDates.code(trip.city)).font(.system(size: 20, weight: .heavy, design: .rounded))
            Text(GuideDates.format(trip.startDate, "MMM yyyy").uppercased()).font(Sketch.eyebrow)
        }
        .foregroundStyle(color)
        .frame(width: 92, height: 92)
        .overlay(Circle().strokeBorder(color, lineWidth: 2))
        .overlay(Circle().strokeBorder(color.opacity(0.4), lineWidth: 1).padding(5))
    }
}

// MARK: - Style sheet

private struct ShelfStyleSheet: View {
    let trip: ShelfTrip
    @Binding var look: ShelfLook
    var onIdentity: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VerticalPage {
                VStack(alignment: .leading, spacing: 24) {
                    ShelfCard(trip: trip, look: look).frame(maxWidth: .infinity).padding(.vertical, 8)
                    Picker("Style", selection: $look.style) {
                        ForEach(ShelfCardStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                        HStack(spacing: 6) {
                            ForEach(Sketch.pigments, id: \.0) { name, color in
                                Button { look.pigment = name } label: {
                                    Circle().fill(color).frame(width: 32, height: 32)
                                        .overlay(Circle().stroke(Sketch.ink, lineWidth: look.pigment == name ? 2.5 : 0).padding(-4))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain).accessibilityLabel(name.capitalized)
                                .accessibilityAddTraits(look.pigment == name ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Illustration").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                            ForEach(Doodle.allCases) { doodle in
                                let selected = look.doodle == doodle
                                Button { look.doodle = doodle } label: {
                                    DoodleView(doodle: doodle, tint: Sketch.pigment(look.pigment), lineWidth: 1.8, animated: false)
                                        .padding(12).frame(width: 64, height: 64)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selected ? Sketch.pigment(look.pigment).opacity(0.14) : Sketch.card))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(selected ? Sketch.ink : Sketch.ink.opacity(0.1), lineWidth: selected ? 1.5 : 1))
                                }
                                .buttonStyle(.plain).accessibilityLabel(doodle.label)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    Button("Name and emoji", systemImage: "face.smiling", action: onIdentity)
                        .font(Sketch.text(15, "SemiBold", relativeTo: .body)).frame(minHeight: 44)
                }
                .padding(20)
            }
            .background(PaperBackground())
            .navigationTitle("Trip card").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
