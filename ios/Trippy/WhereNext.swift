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
    @State private var brief = WhereNextBrief.load()
    @State private var showBrief = false
    @State private var briefStart: BriefStep?

    private static let originKey = "trippy.wherenext.origin.v1"
    private static let months = TripMonth.short
    private var visits: [VisitedPlace] { VisitedPlace.decode(storage) }
    private var selected: Recommendation? { picks.first { $0.id == selectedID } ?? picks.first }
    private var accent: UIColor { UIColor(sketchHex: (GlobeAccent.all.first { $0.id == accentID } ?? GlobeAccent.all[0]).hex) }

    var body: some View {
        VerticalPage {
            VStack(alignment: .leading, spacing: 18) {
                header
                globe
                filters
                if picks.isEmpty { nothingFits } else { carousel; tuning }
                IdeaCheckSection(query: query, taste: taste, visits: visits) { pick in
                    // A better-fitting place from the idea check joins the picks and takes the globe.
                    withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) {
                        if !picks.contains(where: { $0.id == pick.id }) { picks.insert(pick, at: 0) }
                        selectedID = pick.id
                    }
                }
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
        .sheet(isPresented: $showBrief, onDismiss: { brief.save(); brief.apply(to: &query); Task { await paintGlobe() } }) {
            WhereNextBriefView(brief: $brief, start: briefStart) { showBrief = false }
                .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
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
                Text("A few questions about the trip, then places that fit. Scored on your phone.")
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

    // MARK: Your trip

    private func openBrief(_ step: BriefStep? = nil) { briefStart = step; showBrief = true }

    /// The answers are what the picks are built from, so they sit in the middle of the page as one card:
    /// where you leave from, each answer as a tile that opens its own question, and one clear way to change them.
    private var filters: some View {
        let moods = query.wants.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        var tiles: [(BriefStep, String, String, String)] = [
            (.who, brief.who?.symbol ?? "person.2", "Who", brief.who?.title ?? "Anyone"),
            (.when, "calendar", "When", brief.whenText),
            (.length, "clock", "How long", query.days == 3 ? "A weekend" : "\(query.days) days"),
            (.setting, brief.setting?.symbol ?? "square.grid.2x2", "Kind of place", brief.setting?.title ?? "A mix"),
        ]
        if let climate = brief.climate { tiles.insert((.weather, climate.symbol, "Weather", query.ski ? "Skiing" : climate.title), at: 3) }
        tiles.append((.mood, "heart.text.square", "About", moods.isEmpty ? "Anything" : moods.prefix(2).joined(separator: ", ") + (moods.count > 2 ? " +\(moods.count - 2)" : "")))
        tiles.append((.region, brief.region.symbol, "How far", brief.region.title))
        if query.budget != nil || query.mode != nil {
            tiles.append((.extras, query.mode?.symbol ?? "eurosign", "Extras", [query.budget.map { "≤ €\($0)/day" }, query.mode?.title].compactMap { $0 }.joined(separator: " · ")))
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR TRIP").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                Spacer(minLength: 8)
                if brief.finished { Text("Tap any answer to change it").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).lineLimit(1) }
            }
            Button { showOrigin = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "house.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(query.origin == nil ? Sketch.paper : Sketch.clay)
                        .frame(width: 38, height: 38).background(Circle().fill(query.origin == nil ? Sketch.clay : Sketch.clay.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Leaving from").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                        Text(query.origin?.name ?? "Choose a city").font(Sketch.text(16, "Bold", relativeTo: .body)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(SketchPressStyle())
            if brief.finished {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(tiles, id: \.0) { step, symbol, label, value in
                        Button { openBrief(step) } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sketch.clay).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(label).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                                    Text(value).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.paperDeep))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(SketchPressStyle()).accessibilityLabel("\(label): \(value)").accessibilityHint("Change this answer")
                    }
                }
            }
            SketchPrimaryButton(title: brief.finished ? "Change answers" : "Answer a few questions",
                                symbol: brief.finished ? "slider.horizontal.3" : "questionmark.bubble") { openBrief(brief.finished ? nil : .who) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .padding(.horizontal, 20)
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
            Text("Try a wider window of dates, a longer trip, or a looser region.")
                .font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
            Button("Change my answers") { openBrief() }
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
        // `-TrippyWhereNextSample YES`: a couple's snowy January week, already answered.
        if UserDefaults.standard.bool(forKey: "TrippyWhereNextSample") {
            brief = WhereNextBrief(who: .couple, when: .months, months: [1, 2], days: 7, climate: .snow, setting: .mountains, wants: [TripTrait.food.rawValue],
                                   region: .europe, somethingNew: false, finished: true)
        }
        if UserDefaults.standard.bool(forKey: "TrippyWhereNextBrief") { brief.finished = false }
        #endif
        // The questions come first; the picks are already there underneath for anyone who skips them.
        if brief.finished { brief.apply(to: &query) } else { showBrief = true }
        recompute()
        await paintGlobe()
    }

    /// Countries you've been to are coloured only when you asked for somewhere new; otherwise the globe is about the picks.
    private func paintGlobe() async {
        let codes = brief.somethingNew == true ? Set(visits.compactMap { $0.countryCode?.uppercased() }) : []
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
