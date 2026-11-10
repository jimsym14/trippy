import SwiftUI
import MapKit

/// "Where next?": picks places to go from what you like, when you can travel, what you want to spend
/// and where you leave from. The globe shows each pick; a pick becomes one trip or a journey with stops.
/// Everything is scored on the phone from the bundled catalog: no account, no network, no cost.
struct WhereNextView: View {
    var onClose: () -> Void
    var onPlanTrip: (Recommendation, WhereNextQuery) -> Void
    var onPlanJourney: (JourneyDraft) -> Void

    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @AppStorage(GlobeAppearance.accentKey) private var accentID = "amber"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var query = WhereNextQuery()
    @State private var taste = TasteProfile.load()
    @State private var picks: [Recommendation] = []
    @State private var selectedID: String?
    @State private var texture: UIImage?
    @State private var focusID = UUID()
    @State private var showOrigin = false
    @State private var showDuel = false
    @State private var surprise = 0

    private static let originKey = "trippy.wherenext.origin.v1"
    private static let months = TripMonth.short
    private var visits: [VisitedPlace] { VisitedPlace.decode(storage) }
    private var selected: Recommendation? { picks.first { $0.id == selectedID } ?? picks.first }
    private var accent: UIColor { UIColor(sketchHex: (GlobeAccent.all.first { $0.id == accentID } ?? GlobeAccent.all[0]).hex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                globe
                filters
                moods
                if picks.isEmpty { nothingFits } else { carousel; tuning }
            }
            .padding(.top, 8).padding(.bottom, 32)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-TrippyWhereNextBottom") ? .bottom : .top)
        #endif
        .background(PaperBackground())
        .foregroundStyle(Sketch.ink).tint(Sketch.clay)
        .sheet(isPresented: $showOrigin) {
            PlaceSearchSheet(title: "Leaving from", prompt: "City, area or address", addresses: true) { point in
                query.origin = point
                if let data = try? JSONEncoder().encode(point) { UserDefaults.standard.set(data, forKey: Self.originKey) }
            }
        }
        .sheet(isPresented: $showDuel, onDismiss: { recompute() }) {
            TasteDuelView(pool: WhereNextEngine.recommend(query, taste: TasteProfile(), visits: visits, limit: 14), taste: $taste)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .task { await start() }
        .onChange(of: query) { _, _ in recompute() }
        .onChange(of: selectedID) { _, _ in focusID = UUID() }
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.impact(weight: .medium), trigger: surprise)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where next?").font(Sketch.display(.largeTitle, weight: .bold))
                Text("Picked for you from what you like, when you can go and where you start.")
                    .font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 44).raisedCircle()
            }
            .buttonStyle(SketchPressStyle()).accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
    }

    // MARK: Globe

    private var overlay: GlobeOverlay {
        var pins = picks.map { GlobeOverlay.Pin(id: $0.id, coordinate: $0.destination.coordinate) }
        var routes: [[CLLocationCoordinate2D]] = []
        if let origin = query.origin {
            pins.append(.init(id: "home", coordinate: origin.coordinate, home: true))
            if let selected { routes.append([origin.coordinate, selected.destination.coordinate]) }
        }
        return GlobeOverlay(pins: pins, routes: routes, selected: selected?.id, color: accent, lift: 0.12)
    }

    private var globe: some View {
        let far = selected.flatMap { s in query.origin.map { Geo.km($0.coordinate, s.destination.coordinate) > 3500 } } ?? false
        return BeenGlobe3DView(texture: texture, focus: selected?.destination.coordinate ?? query.origin?.coordinate ?? .init(latitude: 40, longitude: 15),
                               focusID: focusID, zoom: far ? 4.7 : 3.9, dark: scheme == .dark, reduceMotion: reduceMotion,
                               onTap: { tapped in
                                   // Tap near a pin to jump to that pick.
                                   if let near = picks.map({ ($0, Geo.km($0.destination.coordinate, tapped)) }).filter({ $0.1 < 500 }).min(by: { $0.1 < $1.1 }) {
                                       withAnimation(.snappy) { selectedID = near.0.id }
                                   }
                               },
                               overlay: overlay)
            .frame(height: typeSize.isAccessibilitySize ? 220 : 300)
            .accessibilityElement()
            .accessibilityLabel(selected.map { "Globe showing \($0.destination.name), \($0.destination.country)" } ?? "Globe")
    }

    // MARK: Filters

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showOrigin = true } label: {
                    chip(symbol: "house.fill", text: query.origin.map { "From \($0.name)" } ?? "Leaving from…", active: query.origin != nil, attention: query.origin == nil)
                }
                .buttonStyle(SketchPressStyle())
                Menu {
                    Picker("When", selection: $query.month) {
                        Text("Any time").tag(Int?.none)
                        ForEach(1...12, id: \.self) { Text(TripMonth.names[$0 - 1]).tag(Int?.some($0)) }
                    }
                } label: { chip(symbol: "calendar", text: query.month.map { Self.months[$0 - 1] } ?? "Any time", active: query.month != nil) }
                Menu {
                    Picker("How long", selection: $query.days) {
                        Text("A weekend").tag(3); Text("5 days").tag(5); Text("A week").tag(7); Text("10 days").tag(10); Text("Two weeks").tag(14)
                    }
                } label: { chip(symbol: "clock", text: query.days == 3 ? "Weekend" : "\(query.days) days", active: true) }
                Menu {
                    Picker("Budget", selection: $query.budget) {
                        Text("Any budget").tag(Int?.none)
                        Text("Up to €60 a day").tag(Int?.some(60)); Text("Up to €100 a day").tag(Int?.some(100))
                        Text("Up to €150 a day").tag(Int?.some(150)); Text("Up to €220 a day").tag(Int?.some(220))
                    }
                } label: { chip(symbol: "eurosign", text: query.budget.map { "≤ €\($0) a day" } ?? "Any budget", active: query.budget != nil) }
                Menu {
                    Picker("How", selection: $query.mode) {
                        Label("Any way", systemImage: "arrow.triangle.branch").tag(JourneyMode?.none)
                        ForEach(JourneyMode.allCases) { Label($0.title, systemImage: $0.symbol).tag(JourneyMode?.some($0)) }
                    }
                } label: { chip(symbol: query.mode?.symbol ?? "arrow.triangle.branch", text: query.mode?.title ?? "Any way", active: query.mode != nil) }
                Menu {
                    Picker("Travelers", selection: $query.travelers) { ForEach(1...8, id: \.self) { Text("\($0) \($0 == 1 ? "traveler" : "travelers")").tag($0) } }
                } label: { chip(symbol: "person.2.fill", text: "\(query.travelers)", active: true) }
                Button { query.newPlacesOnly.toggle() } label: {
                    chip(symbol: query.newPlacesOnly ? "sparkles" : "arrow.uturn.backward", text: query.newPlacesOnly ? "New places" : "Returns OK", active: query.newPlacesOnly)
                }
                .buttonStyle(SketchPressStyle())
                .accessibilityLabel("Only places I haven't been").accessibilityAddTraits(query.newPlacesOnly ? .isSelected : [])
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func chip(symbol: String, text: String, active: Bool, attention: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(text).lineLimit(1)
        }
        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
        .foregroundStyle(attention ? Sketch.paper : Sketch.ink)
        .padding(.horizontal, 13).frame(minHeight: 44)
        .background(Capsule().fill(attention ? Sketch.clay : active ? Sketch.clay.opacity(0.16) : Sketch.paperDeep))
        .contentShape(Capsule())
    }

    private var moods: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IN THE MOOD FOR").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TripTrait.allCases) { trait in
                        let on = query.wants.contains(trait)
                        Button {
                            withAnimation(.snappy) { if on { query.wants.remove(trait) } else { query.wants.insert(trait) } }
                        } label: {
                            Label(trait.title, systemImage: trait.symbol).font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                                .padding(.horizontal, 13).frame(minHeight: 44)
                                .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                                .background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
                        }
                        .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Picks

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                    PickCard(pick: pick, rank: index + 1, query: query, onPlan: { plan(pick) }, onJourney: { journey(pick, $0) })
                        .containerRelativeFrame(.horizontal) { width, _ in min(width - 56, 420) }
                        .id(pick.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID)
        .scrollClipDisabled()
    }

    private var tuning: some View {
        HStack(spacing: 10) {
            Button { showDuel = true } label: {
                Label(taste.duels == 0 ? "Teach it your taste" : "Tune my taste", systemImage: "slider.horizontal.3")
                    .font(Sketch.text(14, "Bold", relativeTo: .subheadline)).frame(maxWidth: .infinity, minHeight: 48).raisedCapsule()
            }
            .buttonStyle(SketchPressStyle())
            Button {
                let others = picks.prefix(6).filter { $0.id != selectedID }
                if let lucky = others.randomElement() { withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) { selectedID = lucky.id }; surprise += 1 }
            } label: {
                Label("Surprise me", systemImage: "dice").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, minHeight: 48).raisedCapsule()
            }
            .buttonStyle(SketchPressStyle())
        }
        .padding(.horizontal, 20)
    }

    private var nothingFits: some View {
        VStack(spacing: 12) {
            DoodleView(doodle: .map, tint: Sketch.clay).frame(width: 84, height: 84)
            Text("Nothing fits all of that").font(Sketch.display(.title3))
            Text("Try a longer trip, another month, or any way of travelling.")
                .font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
            Button("Clear filters") {
                var fresh = WhereNextQuery(); fresh.origin = query.origin; fresh.month = nil; fresh.newPlacesOnly = false
                query = fresh
            }
            .font(Sketch.text(15, "Bold", relativeTo: .body)).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 20)
    }

    // MARK: Work

    private func start() async {
        if let data = UserDefaults.standard.data(forKey: Self.originKey), let saved = try? JSONDecoder().decode(JourneyPoint.self, from: data) {
            query.origin = saved
        } else if let home = HomeCityStore.coordinate {
            query.origin = JourneyPoint(name: "my location", latitude: home.latitude, longitude: home.longitude)
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: home.latitude, longitude: home.longitude)).first,
               let city = mark.locality ?? mark.name {
                query.origin = JourneyPoint(name: city, subtitle: mark.country ?? "", latitude: home.latitude, longitude: home.longitude,
                                            countryCode: mark.isoCountryCode?.uppercased())
            }
        }
        #if DEBUG
        // Screenshot checks: `-TrippyWhereNextFrom "Athens"` starts from a catalog place.
        if let name = UserDefaults.standard.string(forKey: "TrippyWhereNextFrom"), let d = DestinationCatalog.named(name) { query.origin = JourneyPoint(d) }
        if UserDefaults.standard.bool(forKey: "TrippyWhereNextDuel") { showDuel = true }
        #endif
        recompute()
        let codes = Set(visits.compactMap { $0.countryCode?.uppercased() })
        texture = await GlobeTextureBuilder.shared.texture(key: GlobeTextureKey(dark: scheme == .dark, satellite: false, style: "where-next"),
                                                           shapes: nil, visits: [], visitedCodes: codes)
    }

    private func recompute() {
        let next = WhereNextEngine.recommend(query, taste: taste, visits: visits)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            picks = next
            if !next.contains(where: { $0.id == selectedID }) { selectedID = next.first?.id }
        }
        focusID = UUID()
    }

    private func plan(_ pick: Recommendation) {
        taste.reinforce(pick.destination); taste.save()
        onPlanTrip(pick, query)
    }

    private func journey(_ pick: Recommendation, _ mode: JourneyMode) {
        taste.reinforce(pick.destination); taste.save()
        var draft = WhereNextEngine.route(around: pick.destination, query: query, mode: mode, taste: taste, visits: visits)
        draft.interests = Set(taste.strongest(pick.destination, boosted: query.wants).prefix(3).compactMap(\.interest))
        onPlanJourney(draft)
    }
}

// MARK: - Pick card

private struct PickCard: View {
    let pick: Recommendation
    let rank: Int
    let query: WhereNextQuery
    var onPlan: () -> Void
    var onJourney: (JourneyMode) -> Void

    var body: some View {
        let d = pick.destination
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rank == 1 ? "TOP PICK" : "PICK \(rank)").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(rank == 1 ? Sketch.clay : Sketch.inkFaint)
                    Text("\(d.flag) \(d.name)").font(Sketch.display(.title2, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(d.country).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                }
                Spacer(minLength: 4)
                MatchRing(percent: pick.percent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(d.highlights.prefix(4)) { SketchTag(text: $0.title, tint: Sketch.sky, symbol: $0.symbol) } }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(pick.reasons, id: \.self) { reason in
                    Label { Text(reason) } icon: { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.sage) }
                }
                if let caution = pick.caution {
                    Label { Text(caution) } icon: { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Sketch.ochre) }
                }
            }
            .font(Sketch.text(14, relativeTo: .subheadline))
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("About €\(pick.total.formatted())").font(Sketch.text(16, "Bold", relativeTo: .body))
                Text("for \(query.travelers), \(query.days) days").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 8) {
                SketchPrimaryButton(title: "Plan this trip", symbol: "sparkles", action: onPlan)
                Menu {
                    Section("Add stops around \(d.name)") {
                        Button("By train", systemImage: "tram.fill") { onJourney(.train) }
                        Button("As a road trip", systemImage: "car.fill") { onJourney(.car) }
                        Button("Flying between stops", systemImage: "airplane") { onJourney(.plane) }
                    }
                } label: {
                    Label("Make it a journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(Sketch.text(15, "Bold", relativeTo: .body)).frame(maxWidth: .infinity, minHeight: 48).raisedCapsule()
                }
            }
        }
        .sketchCard(padding: 16)
    }
}

/// How well a pick fits, as a ring.
private struct MatchRing: View {
    let percent: Int
    var body: some View {
        ZStack {
            Circle().stroke(Sketch.ink.opacity(0.08), lineWidth: 5)
            Circle().trim(from: 0, to: CGFloat(percent) / 100).stroke(Sketch.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(percent)").font(Sketch.text(16, "Bold", relativeTo: .body)).monospacedDigit().contentTransition(.numericText())
                Text("match").font(Sketch.text(9, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(percent) percent match")
    }
}

// MARK: - Taste duel

/// "This or that": five quick choices between very different places. Each one moves the taste
/// weights towards what the chosen place has more of.
struct TasteDuelView: View {
    let pool: [Recommendation]
    @Binding var taste: TasteProfile
    @State private var round = 0
    @State private var pair: (Destination, Destination)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rounds = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if round < rounds, let pair {
                    VStack(spacing: 6) {
                        Text("Which pulls you more?").font(Sketch.display(.title2, weight: .bold))
                        Text("No wrong answers. Each choice sharpens your picks.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    }
                    .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(0..<rounds, id: \.self) { Capsule().fill($0 <= round ? Sketch.clay : Sketch.ink.opacity(0.12)).frame(width: $0 == round ? 22 : 8, height: 6) }
                    }
                    .accessibilityLabel("Question \(round + 1) of \(rounds)")
                    VStack(spacing: 12) {
                        option(pair.0, over: pair.1, tint: Sketch.clay)
                        Text("or").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
                        option(pair.1, over: pair.0, tint: Sketch.sky)
                    }
                    .id(round)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    Button("Can’t choose") { advance() }.font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).frame(minHeight: 44)
                } else {
                    Spacer()
                    DoodleView(doodle: .star, tint: Sketch.ochre).frame(width: 96, height: 96)
                    Text("Got it").font(Sketch.display(.title, weight: .bold))
                    Text(summary).font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
                    SketchPrimaryButton(title: "See my picks") { dismiss() }.frame(maxWidth: 280)
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(PaperBackground())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Sketch.ink).tint(Sketch.clay)
        .onAppear { pair = WhereNextEngine.duel(from: pool, round: taste.duels) }
    }

    private var summary: String {
        let top = TripTrait.allCases.sorted { taste.weights[$0.rawValue] > taste.weights[$1.rawValue] }.prefix(3).map(\.short)
        return "You lean towards \(top.joined(separator: ", ")). Your picks follow that from now on, and keep learning from the trips you plan."
    }

    private func option(_ d: Destination, over other: Destination, tint: Color) -> some View {
        Button {
            taste.prefer(d, over: other); taste.save(); advance()
        } label: {
            HStack(spacing: 14) {
                Text(d.flag).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.name).font(Sketch.display(.title3, weight: .bold)).multilineTextAlignment(.leading)
                    Text(d.highlights.prefix(3).map(\.title).joined(separator: " · ")).font(Sketch.text(13, relativeTo: .footnote))
                        .foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 96).sketchCard(tint: tint, padding: 16)
        }
        .buttonStyle(SketchPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: round)
    }

    private func advance() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) {
            round += 1
            pair = WhereNextEngine.duel(from: pool, round: taste.duels + round)
        }
    }
}
