import SwiftUI
import MapKit

// MARK: - Place search

/// Finds a city, area or exact address with Apple Maps (free) and returns it with coordinates.
final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    init(addresses: Bool) {
        super.init()
        completer.delegate = self
        completer.resultTypes = addresses ? [.address, .pointOfInterest] : .address
    }
    func update(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { results = []; return }
        completer.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }

    static func resolve(_ item: MKLocalSearchCompletion) async -> JourneyPoint? {
        guard let found = try? await MKLocalSearch(request: .init(completion: item)).start().mapItems.first else { return nil }
        let c = found.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(c) else { return nil }
        return JourneyPoint(name: item.title, subtitle: item.subtitle, latitude: c.latitude, longitude: c.longitude,
                            countryCode: found.placemark.isoCountryCode?.uppercased())
    }
}

struct PlaceSearchSheet: View {
    let title: String
    let prompt: String
    /// Leaving from a street address or a station is fine; stops are cities and regions.
    var addresses = false
    var suggestions: [Destination] = []
    var onPick: (JourneyPoint) -> Void

    @StateObject private var completer: PlaceCompleter
    @State private var text = ""
    @State private var resolving = false
    @State private var failed = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, prompt: String, addresses: Bool = false, suggestions: [Destination] = [], onPick: @escaping (JourneyPoint) -> Void) {
        self.title = title; self.prompt = prompt; self.addresses = addresses; self.suggestions = suggestions; self.onPick = onPick
        _completer = StateObject(wrappedValue: PlaceCompleter(addresses: addresses))
    }

    var body: some View {
        NavigationStack {
            List {
                if text.count < 2 {
                    if addresses, let home = HomeCityStore.coordinate {
                        Button { Task { await pickHome(home) } } label: {
                            row(symbol: "location.fill", tint: Sketch.sky, title: "Near me", detail: "Your last known location")
                        }
                    }
                    if !suggestions.isEmpty {
                        Section("Fits your route") {
                            ForEach(suggestions) { d in
                                Button { onPick(JourneyPoint(d)); dismiss() } label: {
                                    row(symbol: d.highlights.first?.symbol ?? "mappin", tint: Sketch.clay, title: "\(d.flag) \(d.name)",
                                        detail: ([d.country] + d.highlights.prefix(2).map(\.short)).joined(separator: " · "))
                                }
                            }
                        }
                    }
                } else if completer.results.isEmpty {
                    Text("No places found for “\(text)”.").font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                } else {
                    ForEach(completer.results, id: \.self) { item in
                        Button { Task { await pick(item) } } label: {
                            row(symbol: "mappin", tint: Sketch.coral, title: item.title, detail: item.subtitle)
                        }
                    }
                }
                if failed {
                    Text("Couldn’t find that place. Check your connection and try again.")
                        .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.coral)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden).background(PaperBackground())
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .autocorrectionDisabled()
            .onChange(of: text) { _, value in failed = false; completer.update(value) }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay { if resolving { ProgressView().controlSize(.large) } }
        }
        .tint(Sketch.clay)
    }

    private func row(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34).background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                if !detail.isEmpty { Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }

    private func pick(_ item: MKLocalSearchCompletion) async {
        resolving = true; defer { resolving = false }
        guard let point = await PlaceCompleter.resolve(item) else { failed = true; return }
        onPick(point); dismiss()
    }

    private func pickHome(_ c: CLLocationCoordinate2D) async {
        resolving = true; defer { resolving = false }
        let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        onPick(JourneyPoint(name: mark?.locality ?? mark?.name ?? "My location", subtitle: mark?.country ?? "",
                            latitude: c.latitude, longitude: c.longitude, countryCode: mark?.isoCountryCode?.uppercased()))
        dismiss()
    }
}

// MARK: - Journey builder

/// Several stops in one trip: pick the places, and the app finds the quickest order, shares out the
/// nights and shows what each leg takes. Everything is worked out on the phone.
struct JourneyBuilderView: View {
    @State var draft: JourneyDraft
    var onCancel: () -> Void
    var onCreate: (JourneyDraft) -> Void

    @State private var taste = TasteProfile.load()
    @State private var measured: [String: JourneyLeg] = [:]
    @State private var camera: MapCameraPosition = .automatic
    @State private var picking: Picking?
    @State private var orderedByHand = false
    @State private var feedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Picking: String, Identifiable { case origin, stop; var id: String { rawValue } }

    private var summary: JourneySummary { JourneyEngine.summary(for: draft, measured: measured) }
    private var best: [JourneyStop] { JourneyEngine.bestOrder(draft) }
    /// Minutes a better order would save, when it is worth mentioning.
    private var saving: Int {
        guard draft.stops.count > 2 || (draft.stops.count == 2 && draft.origin != nil) else { return 0 }
        let better = best
        guard better.map(\.id) != draft.stops.map(\.id) else { return 0 }
        return JourneyEngine.travelMinutes(draft) - JourneyEngine.travelMinutes(draft, order: better)
    }
    private static let dayMonth = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "en_GB"))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journey").font(Sketch.display(.largeTitle, weight: .bold))
                        Text("Several stops, one trip. Add places and we’ll find the quickest way round.")
                            .font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !draft.stops.isEmpty || draft.origin != nil { map }
                    section("How", icon: draft.mode == .car ? .car : draft.mode == .train ? .train : .plane, tint: Sketch.sky) { modePicker }
                    section("From", icon: .pin, tint: Sketch.coral) { originRow }
                    section("Stops", icon: .map, tint: Sketch.clay, trailing: draft.stops.isEmpty ? nil : "\(draft.stops.count)") { stopList }
                    if !draft.stops.isEmpty {
                        section("When", icon: .calendar, tint: Sketch.ochre, trailing: range) { when }
                        section("Who", icon: .people, tint: Sketch.plum) { who }
                        if draft.stops.count > 1 { section("The whole journey", icon: .euro, tint: Sketch.sage) { totals } }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-TrippyJourneyBottom") ? .bottom : ProcessInfo.processInfo.arguments.contains("-TrippyJourneyMiddle") ? .center : .top)
            #endif
            .background(PaperBackground())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
        .tint(Sketch.clay).foregroundStyle(Sketch.ink)
        .sheet(item: $picking) { kind in
            if kind == .origin {
                PlaceSearchSheet(title: "Leaving from", prompt: "City, area or address", addresses: true) { point in
                    withAnimation(.snappy) { draft.origin = point }; afterChange()
                }
            } else {
                PlaceSearchSheet(title: "Add a stop", prompt: "City or region",
                                 suggestions: JourneyEngine.stopsOnTheWay(draft, taste: taste)) { add($0) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .task(id: draft.stops.map(\.id.uuidString).joined() + draft.mode.rawValue + (draft.origin?.name ?? "")) { await measureDrives() }
        .onChange(of: draft.stops.map(\.id)) { _, _ in withAnimation(reduceMotion ? nil : .smooth) { camera = .automatic } }
    }

    private func section<Content: View>(_ title: String, icon: TrippyIcon, tint: Color, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerSectionHeader(title: title, icon: icon, tint: tint, trailing: trailing)
            content()
        }
        .sketchCard(padding: 14)
    }

    // MARK: Map

    private var routePath: [CLLocationCoordinate2D] {
        var points = [draft.origin].compactMap { $0 } + draft.stops.map(\.place)
        if draft.roundTrip, let origin = draft.origin, !draft.stops.isEmpty { points.append(origin) }
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).flatMap { a, b in
            // Flights follow the great circle; roads and rails read fine as straight lines at this scale.
            JourneyEngine.leg(from: a, to: b, mode: draft.mode).mode == .plane ? Geo.arc(a.coordinate, b.coordinate, steps: 24) : [a.coordinate, b.coordinate]
        }
    }

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if routePath.count > 1 {
                MapPolyline(coordinates: routePath)
                    .stroke(Sketch.clay, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: draft.mode == .plane ? [2, 7] : []))
            }
            if let origin = draft.origin {
                Annotation(origin.name, coordinate: origin.coordinate) {
                    Image(systemName: "house.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.paper)
                        .frame(width: 26, height: 26).background(Circle().fill(Sketch.ink))
                        .overlay(Circle().strokeBorder(Sketch.paper, lineWidth: 2))
                }
            }
            ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.place.name, coordinate: stop.place.coordinate) {
                    Text("\(index + 1)").font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Circle().fill(Sketch.dayColor(index)))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
        .accessibilityLabel("Map of the route: " + draft.stops.map(\.place.name).joined(separator: ", then "))
    }

    // MARK: How

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach([(JourneyMode.train, Doodle.train), (.car, .car), (.plane, .plane)], id: \.0) { mode, doodle in
                    let on = draft.mode == mode
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { draft.mode = mode }; afterChange() } label: {
                        VStack(spacing: 4) {
                            DoodleView(doodle: doodle, tint: on ? Sketch.sky : Sketch.inkFaint, lineWidth: 2, wash: on).frame(width: 44, height: 44).id(on)
                            Text(mode.title).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Sketch.sky.opacity(0.14) : Sketch.paperDeep))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Sketch.sky.opacity(0.6) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Picker("Route shape", selection: Binding(get: { draft.roundTrip }, set: { value in withAnimation(.snappy) { draft.roundTrip = value }; afterChange() })) {
                Text("Loop back to start").tag(true); Text("One way").tag(false)
            }
            .pickerStyle(.segmented)
            Text(draft.roundTrip ? "The last stop is chosen to be close to where you began." : "The route ends wherever is quickest; you travel home from the last stop.")
                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: From

    private var originRow: some View {
        Button { picking = .origin } label: {
            HStack(spacing: 12) {
                Image(systemName: "house.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.paper)
                    .frame(width: 32, height: 32).background(Circle().fill(Sketch.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.origin?.name ?? "Where do you leave from?").font(Sketch.text(16, "SemiBold", relativeTo: .body))
                        .foregroundStyle(draft.origin == nil ? Sketch.inkSoft : Sketch.ink)
                    Text(draft.origin.map { $0.subtitle.isEmpty ? "Start and end of the journey" : $0.subtitle } ?? "A city, an area or your exact address")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Sketch.inkFaint)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(SketchPressStyle())
    }

    // MARK: Stops

    private var stopList: some View {
        let s = summary
        let dates = draft.dates
        return VStack(alignment: .leading, spacing: 0) {
            if let out = s.outbound { legRow(out) }
            ForEach(Array(draft.stops.enumerated()), id: \.element.id) { index, stop in
                stopRow(stop, index: index, dates: dates[index])
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first, let from = draft.stops.firstIndex(where: { $0.id.uuidString == id }), from != index else { return false }
                        move(from: from, to: index); return true
                    }
                if index < s.legs.count { legRow(s.legs[index]) }
            }
            if let back = s.inbound, !draft.stops.isEmpty { legRow(back, home: true) }
            if saving >= 10 { quickerOrder }
            Button { picking = .stop } label: {
                Label(draft.stops.isEmpty ? "Add the first stop" : "Add a stop", systemImage: "plus")
                    .font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(Sketch.paper)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Capsule().fill(Sketch.ink))
            }
            .buttonStyle(SketchPressStyle()).padding(.top, 12)
            onTheWay
        }
    }

    private func stopRow(_ stop: JourneyStop, index: Int, dates: (start: Date, end: Date)) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)").font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Circle().fill(Sketch.dayColor(index)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stop.place.name).font(Sketch.text(16, "Bold", relativeTo: .body)).lineLimit(1)
                    if stop.locked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Sketch.ochre).accessibilityLabel("Position locked") }
                }
                Text("\(dates.start.formatted(Self.dayMonth)) – \(dates.end.formatted(Self.dayMonth))")
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                stepButton("minus", label: "One night fewer in \(stop.place.name)", disabled: stop.nights <= 1) { setNights(stop.id, stop.nights - 1) }
                VStack(spacing: 0) {
                    Text("\(stop.nights)").font(Sketch.display(.title3, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                    Text(stop.nights == 1 ? "night" : "nights").font(Sketch.text(10, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                }
                .frame(minWidth: 38)
                .accessibilityElement(children: .ignore).accessibilityLabel("\(stop.nights) nights")
                stepButton("plus", label: "One night more in \(stop.place.name)", disabled: stop.nights >= 14) { setNights(stop.id, stop.nights + 1) }
            }
            Menu {
                Button(stop.locked ? "Unlock position" : "Keep in this position", systemImage: stop.locked ? "lock.open" : "lock") { toggleLock(stop.id) }
                if index > 0 { Button("Move earlier", systemImage: "arrow.up") { move(from: index, to: index - 1) } }
                if index < draft.stops.count - 1 { Button("Move later", systemImage: "arrow.down") { move(from: index, to: index + 1) } }
                Button("Remove", systemImage: "trash", role: .destructive) { remove(stop.id) }
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .semibold)).foregroundStyle(Sketch.inkFaint)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Reorder or remove \(stop.place.name)")
            .draggable(stop.id.uuidString)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
    }

    private func stepButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).frame(width: 34, height: 34).raisedCircle()
                .frame(minWidth: 36, minHeight: 44)
        }
        .buttonStyle(SketchPressStyle()).disabled(disabled).opacity(disabled ? 0.4 : 1).accessibilityLabel(label)
    }

    /// The trip between two rows: a dotted line and what it takes.
    private func legRow(_ leg: JourneyLeg, home: Bool = false) -> some View {
        let long = leg.minutes > 6 * 60
        let flown = leg.mode != draft.mode
        return HStack(spacing: 12) {
            DottedTrail().stroke(Sketch.inkFaint, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 6])).frame(width: 32, height: 34)
            HStack(spacing: 6) {
                Image(systemName: leg.mode.symbol).font(.system(size: 11, weight: .semibold))
                Text([leg.duration, leg.distance, "about €\(leg.cost)"].joined(separator: " · "))
                if leg.ferry { Text("+ ferry") }
                if home { Text("home") }
            }
            .font(Sketch.text(12, "SemiBold", relativeTo: .caption))
            .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            .foregroundStyle(long ? Sketch.coral : Sketch.inkSoft)
            .padding(.horizontal, 10).frame(minHeight: 26)
            .background(Capsule().fill((long ? Sketch.coral : Sketch.ink).opacity(0.07)))
            if flown { SketchTag(text: "no land route", tint: Sketch.ochre).fixedSize() }
            else if long { SketchTag(text: "long day", tint: Sketch.coral).fixedSize() }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(leg.from) to \(leg.to): \(leg.duration) \(leg.mode.verb), about \(leg.cost) euros each")
    }

    private var quickerOrder: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap").font(.system(size: 15, weight: .bold)).foregroundStyle(Sketch.sage)
                .frame(width: 34, height: 34).background(Circle().fill(Sketch.sage.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("A quicker order saves \(JourneyEngine.duration(saving))").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Text(best.map(\.place.name).joined(separator: " → ")).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Use it") { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)) { draft.stops = best }; orderedByHand = false; feedback += 1 }
                .font(Sketch.text(14, "Bold", relativeTo: .subheadline)).padding(.horizontal, 14).frame(minHeight: 44)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.sage.opacity(0.1)))
        .padding(.top, 10)
        .transition(.opacity)
    }

    @ViewBuilder private var onTheWay: some View {
        let ideas = JourneyEngine.stopsOnTheWay(draft, taste: taste, limit: 6)
        if !ideas.isEmpty && !draft.stops.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ON YOUR WAY").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ideas) { d in
                            Button { add(JourneyPoint(d)) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                    Text("\(d.flag) \(d.name)")
                                }
                                .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                                .padding(.horizontal, 12).frame(minHeight: 40).background(Capsule().fill(Sketch.paperDeep))
                            }
                            .buttonStyle(SketchPressStyle()).accessibilityLabel("Add \(d.name)")
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .padding(.top, 14)
        }
    }

    // MARK: When, who, totals

    private var range: String {
        "\(draft.startDate.formatted(Self.dayMonth)) – \(draft.endDate.formatted(Self.dayMonth))"
    }

    private var when: some View {
        VStack(spacing: 8) {
            DatePicker("First day", selection: $draft.startDate, in: Date.now..., displayedComponents: .date)
                .font(Sketch.text(15, relativeTo: .body)).frame(minHeight: 44)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(draft.nights) nights in all").font(Sketch.text(15, "SemiBold", relativeTo: .body)).contentTransition(.numericText())
                    Text("Shared out by how much there is to do").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                }
                Spacer()
                stepButton("minus", label: "One night fewer overall", disabled: draft.nights <= draft.stops.count) { rebalance(draft.nights - 1) }
                stepButton("plus", label: "One night more overall", disabled: draft.nights >= 45) { rebalance(draft.nights + 1) }
            }
            .frame(minHeight: 44)
            if draft.stops.contains(where: \.nightsPinned) {
                Button("Share nights out again") { withAnimation(.snappy) { for i in draft.stops.indices { draft.stops[i].nightsPinned = false }; rebalance(draft.nights) } }
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).frame(minHeight: 44)
            }
        }
        .animation(.snappy, value: draft.nights)
    }

    private var who: some View {
        HStack(spacing: 12) {
            Text("Travelers").font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
            Spacer()
            stepButton("minus", label: "One fewer traveler", disabled: draft.travelers <= 1) { draft.travelers -= 1 }
            Text("\(draft.travelers)").font(Sketch.display(.title2, weight: .bold)).monospacedDigit().contentTransition(.numericText()).frame(minWidth: 28)
            stepButton("plus", label: "One more traveler", disabled: draft.travelers >= 20) { draft.travelers += 1 }
        }
        .animation(.snappy, value: draft.travelers)
    }

    private var totals: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                fact("\(draft.nights + 1)", "days")
                fact(JourneyEngine.duration(s.minutes), "travelling")
                fact("\(Int((s.km / 10).rounded()) * 10)", "km")
            }
            VStack(spacing: 6) {
                costRow("Getting around", s.travelCost)
                costRow("Beds, food and days out", s.stayCost)
                Divider()
                costRow("About, for \(draft.travelers)", s.total, bold: true)
            }
            Text("Estimates from typical speeds and prices, to compare routes. Check real fares before you book." + (measured.isEmpty ? "" : " Driving times are from Apple Maps."))
                .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Sketch.display(.title3, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1).contentTransition(.numericText())
            Text(label).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 58).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.paperDeep))
        .accessibilityElement(children: .combine)
    }

    private func costRow(_ title: String, _ amount: Int, bold: Bool = false) -> some View {
        HStack {
            Text(title); Spacer(); Text("€\(amount.formatted())").monospacedDigit().contentTransition(.numericText())
        }
        .font(Sketch.text(bold ? 16 : 14, bold ? "Bold" : "Regular", relativeTo: .body)).foregroundStyle(bold ? Sketch.ink : Sketch.inkSoft)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if draft.stops.count == 1 {
                Text("Add one more stop to make it a journey.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
            SketchPrimaryButton(title: draft.stops.count > 1 ? "Create journey · \(draft.stops.count) stops" : "Create journey", enabled: draft.stops.count > 1) {
                onCreate(draft)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
        .background(Sketch.paper.ignoresSafeArea())
    }

    // MARK: Changes

    private func add(_ point: JourneyPoint) {
        guard !draft.stops.contains(where: { Geo.km($0.place.coordinate, point.coordinate) < 5 }) else { return }
        let nights = [1, 2, 3][min(max(point.size, 1), 3) - 1]
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) {
            draft.stops.append(JourneyStop(place: point, nights: nights))
            // Until someone orders stops by hand, each new one slots in where it adds least travel.
            if !orderedByHand { draft.stops = JourneyEngine.bestOrder(draft) }
        }
        feedback += 1
    }
    private func afterChange() {
        if !orderedByHand, draft.stops.count > 1 { withAnimation(reduceMotion ? nil : .smooth) { draft.stops = JourneyEngine.bestOrder(draft) } }
    }
    private func remove(_ id: UUID) { withAnimation(.snappy) { draft.stops.removeAll { $0.id == id } } }
    private func move(from: Int, to: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
            let stop = draft.stops.remove(at: from); draft.stops.insert(stop, at: to)
        }
        orderedByHand = true; feedback += 1
    }
    private func toggleLock(_ id: UUID) {
        guard let i = draft.stops.firstIndex(where: { $0.id == id }) else { return }
        draft.stops[i].locked.toggle()
    }
    private func setNights(_ id: UUID, _ nights: Int) {
        guard let i = draft.stops.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { draft.stops[i].nights = min(14, max(1, nights)); draft.stops[i].nightsPinned = true }
    }
    private func rebalance(_ total: Int) {
        withAnimation(.snappy) { draft.stops = JourneyEngine.allocate(nights: total, to: draft.stops) }
    }

    /// Road trips get real driving times from Apple Maps, one leg at a time.
    private func measureDrives() async {
        guard draft.mode == .car else { measured = [:]; return }
        try? await Task.sleep(for: .milliseconds(600))
        var points = [draft.origin].compactMap { $0 } + draft.stops.map(\.place)
        if let origin = draft.origin, !draft.stops.isEmpty { points.append(origin) }
        for (a, b) in zip(points, points.dropFirst()) {
            guard !Task.isCancelled else { return }
            let key = JourneyEngine.legKey(a, b, .car)
            if measured[key] != nil { continue }
            let estimate = JourneyEngine.leg(from: a, to: b, mode: .car, travelers: draft.travelers)
            if let real = await JourneyEngine.measuredDrive(estimate, from: a, to: b, travelers: draft.travelers) { measured[key] = real }
        }
    }
}
