import SwiftUI
import MapKit

/// New trip: every choice is a tap away, and anything else can be typed.
/// Taps and typed text feed the same request.
struct TripComposerView: View {
    @State var result: ComposerResult
    var onCancel: () -> Void
    var onSubmit: (ComposerResult) -> Void
    var onDetailed: (() -> Void)? = nil
    /// The traveller's saves for a destination, with what their videos say (offered next to the recommendations).
    var savesFor: ((String) -> [PickInfo])? = nil

    @State private var start = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var end = Calendar.current.date(byAdding: .day, value: 33, to: .now) ?? .now
    @State private var budgetLevel: String?
    @State private var placeQuery = ""
    @State private var placeResults: [MKMapItem] = []
    @State private var suggestions: [MKMapItem] = []
    @State private var famous: [ComposerPlace] = []
    @State private var localPicks: [String: [ComposerPlace]] = [:]   // "food", "bars": from Apple Maps
    @State private var pickCategory = "sights"
    @State private var pickSource: PickInfo.Source = .recommended
    @State private var openPick: PickInfo?
    @State private var pickList: PickList?
    @State private var seededNames: Set<String> = []
    @State private var seededCity: String?
    @State private var loadedSaves: (city: String, items: [PickInfo]) = ("", [])
    enum PickList: Identifiable, Hashable {
        case saves, recommended(String)
        var id: String { switch self { case .saves: "saves"; case .recommended(let c): "rec-" + c } }
    }
    @State private var stayResults: [MKMapItem] = []
    @State private var showLook = false
    @State private var showStayMap = false
    @State private var look = ShelfLook()
    @StateObject private var cities = CityCompleter()
    @FocusState private var focus: Field?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Field { case name, destination, place, message, budget, stay, arrival, departure }

    private static let groups: [(String, String)] = [("Solo", "person"), ("Couple", "person.2"), ("Friends", "person.3"), ("Family", "figure.2.and.child.holdinghands")]
    private static let paces: [(id: String, title: String, detail: String, symbol: String)] = [
        ("relaxed", "Relaxed", "2–3 stops, long lunches", "cup.and.saucer"),
        ("balanced", "Balanced", "3–4 stops a day", "figure.walk"),
        ("intense", "Full", "As much as fits", "figure.run"),
        ("speedrun", "Speedrun", "Every highlight, no lingering", "bolt.fill"),
    ]
    private static let modes: [(id: String, title: String, doodle: Doodle, icon: TrippyIcon)] = [
        ("plane", "Plane", .plane, .plane), ("train", "Train", .train, .train), ("car", "Road trip", .car, .car)]
    /// Per person per day; a group budget multiplies by the number of travelers.
    private static let budgets: [(String, String, Int)] = [("€", "Budget", 60), ("€€", "Mid-range", 120), ("€€€", "Comfort", 250)]

    private var city: String { result.destination.trimmingCharacters(in: .whitespaces) }
    private var autoDoodle: Doodle {
        Doodle.suggested(title: result.name + " " + (result.travelMode == "car" ? "road trip" : ""), city: result.destination)
    }

    private var parsed: ComposerResult {
        var r = ComposerParser.parse(result.message, into: result)
        r.group = result.group; r.travelers = result.travelers; r.name = result.name; r.mustSee = result.mustSee; r.savesSeeded = result.savesSeeded
        r.tags = result.tags; r.budgetBasis = result.budgetBasis; r.travelMode = result.travelMode
        if let pace = result.pace { r.pace = pace }
        r.interests.formUnion(result.interests)
        if !result.budget.isEmpty { r.budget = result.budget }
        if !result.arrivalTime.isEmpty { r.arrivalTime = result.arrivalTime }
        if !result.departureTime.isEmpty { r.departureTime = result.departureTime }
        if !result.stay.isEmpty { r.stay = result.stay }
        var notes: [String] = []
        if !result.mustSee.isEmpty { notes.append("Must include: " + result.mustSee.map(\.name).joined(separator: ", ")) }
        if !result.stay.isEmpty { notes.append("Staying in " + result.stay) }
        if result.travelMode == "car" { notes.append("Road trip: we have a car") }
        if result.travelMode == "train" { notes.append("Arriving by train") }
        if result.pace == "speedrun" { notes.append("Speedrun: short visits, see as many highlights as possible") }
        r.message = ([result.message] + notes).filter { !$0.isEmpty }.joined(separator: ". ")
        if !r.flexible {
            r.startDate = GuideDates.iso.string(from: start)
            r.endDate = GuideDates.iso.string(from: max(start, end))
            r.duration = (Calendar.current.dateComponents([.day], from: start, to: max(start, end)).day ?? 0) + 1
        }
        r.look = look == ShelfLook() ? nil : look
        return r
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            VerticalPage {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if showLook {
                        ComposerLookPicker(look: $look, preview: previewTrip, autoDoodle: autoDoodle)
                            .sketchCard(padding: 14)
                            .transition(.scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
                    }
                    section("Where", icon: .pin, tint: Sketch.coral) { whereField }
                    section("Who", icon: .people, tint: Sketch.plum) { who }
                    section("When", icon: .calendar, tint: Sketch.clay, trailing: result.flexible ? nil : dateSummary) { dates }
                    section("Getting there", icon: modeIcon, tint: Sketch.sky) { gettingThere }
                    section("Pace", icon: .bolt, tint: Sketch.ochre) { paceGrid }
                    section("Interests", icon: .sparkle, tint: Sketch.sage, trailing: interestSummary) {
                        InterestPicker(groups: $result.interests, tags: $result.tags, city: city)
                    }
                    section("Must-see places", icon: .star, tint: Sketch.ochre) { mustSee }
                    section("Budget", icon: .euro, tint: Sketch.clay) { budgetRow }
                    section("Stay", icon: .bed, tint: Sketch.plum) { stay }
                    section("Anything else", icon: .pencil, tint: Sketch.inkSoft) { message }
                    summary
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 120)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            #if DEBUG
            .task {
                // Screenshot checks: `-TrippyComposerCity Barcelona -TrippyComposerScroll Pace`.
                if let c = UserDefaults.standard.string(forKey: "TrippyComposerCity") { result.destination = c; focus = nil; cities.chosen = c }
                if UserDefaults.standard.bool(forKey: "TrippyComposerLook") { showLook = true }
                // `-TrippyComposerDemoSaves 34`: that many sample saves in the city (cap, ranking, See all).
                let demo = UserDefaults.standard.integer(forKey: "TrippyComposerDemoSaves")
                if demo > 0 {
                    ComposerSaves.provider = { city in PickInfo.demoSaves(demo, city: city) }
                    loadedSaves = ("", []); seedSaves()
                    if UserDefaults.standard.string(forKey: "TrippyComposerPickSource") == "recommended" { pickSource = .recommended }
                    if let open = UserDefaults.standard.string(forKey: "TrippyComposerOpenPick") {
                        try? await Task.sleep(for: .seconds(1.2))
                        if open == "all" { pickList = .saves } else { openPick = citySaves.first }
                    }
                }
                if UserDefaults.standard.bool(forKey: "TrippyComposerStayMap") { try? await Task.sleep(for: .seconds(1)); showStayMap = true }
                if let t = UserDefaults.standard.string(forKey: "TrippyComposerScroll") {
                    result.interests = ["food", "nightlife"]; result.tags = ["tapas"]
                    try? await Task.sleep(for: .milliseconds(600)); focus = nil; proxy.scrollTo(t, anchor: .top)
                }
            }
            #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PaperBackground())
            .safeAreaInset(edge: .bottom) { if focus == nil { bottomBar } }
            .keyboardDismissButton()
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Sketch.clay)
        .foregroundStyle(Sketch.ink)
        .sheet(isPresented: $showStayMap) {
            StayHeatmapView(city: city) { area in result.stay = area }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onAppear {
            if let s = GuideDates.date(result.startDate) { start = s }
            if let e = GuideDates.date(result.endDate) { end = e }
            if result.destination.isEmpty { focus = .destination }
            if result.pace == nil { result.pace = ComposerParser.parse(result.message, into: result).pace ?? "balanced" }
            if let saved = result.look { look = saved }
        }
        .task(id: placeQuery + "|" + result.destination) { await searchPlaces() }
        .task(id: result.destination) { await loadSuggestions() }
        .task(id: result.stay + "|" + result.destination) { await searchStays() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New trip").font(Sketch.display(.largeTitle, weight: .bold))
                Text("Tap what fits. Type anything else at the end.")
                    .font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            let doodle = look.doodle ?? autoDoodle
            Button { withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) { showLook.toggle() } } label: {
                DoodleView(doodle: doodle, tint: Sketch.pigment(look.pigment ?? "coral")).frame(width: 72, height: 72).id(doodle)
                    .transition(.opacity)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: showLook ? "chevron.up" : "paintbrush.pointed.fill").font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28).raisedCircle().offset(x: 6, y: 6)
                    }
            }
            .buttonStyle(SketchPressStyle())
            .accessibilityLabel("Card style and illustration")
        }
        .animation(.easeInOut(duration: 0.3), value: look.doodle ?? autoDoodle)
    }

    private var previewTrip: ShelfTrip {
        ShelfTrip(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: result.name.isEmpty ? (city.isEmpty ? "New trip" : city) : result.name,
                  city: city, flag: nil, startDate: result.flexible ? "" : GuideDates.iso.string(from: start),
                  endDate: result.flexible ? "" : GuideDates.iso.string(from: end), travelers: result.travelers,
                  hasPlan: false, completed: false, colorHex: nil, emoji: nil, stops: 0, days: result.duration)
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, icon: TrippyIcon, tint: Color, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerSectionHeader(title: title, icon: icon, tint: tint, trailing: trailing)
            content()
        }
        .sketchCard(padding: 14)
        .id(title)
    }

    private func chips(_ items: [(String, String, String)], selected: Set<String>, toggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { id, title, symbol in
                let on = selected.contains(id)
                Button { toggle(id) } label: {
                    Label(title, systemImage: symbol).font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                        .background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
                }
                .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func tile(_ title: String, _ detail: String, symbol: String? = nil, selected: Bool, accent: Color = Sketch.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: symbol == nil ? .center : .leading, spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).symbolEffect(.bounce, value: selected) }
                Text(title).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                // Tiles in a grid are one size: a two-line detail ("Every highlight, no lingering") reserves the same room as one.
                Text(detail).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(selected ? Sketch.paper.opacity(0.78) : Sketch.inkSoft)
                    .lineLimit(symbol == nil ? 1 : 2, reservesSpace: symbol != nil).multilineTextAlignment(symbol == nil ? .center : .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: symbol == nil ? .center : .leading)
            .padding(.horizontal, symbol == nil ? 0 : 12).padding(.vertical, symbol == nil ? 0 : 10)
            .foregroundStyle(selected ? Sketch.paper : Sketch.ink)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? accent : Sketch.paperDeep))
        }
        .buttonStyle(SketchPressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func roundButton(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 40, height: 40).raisedCircle()
        }
        .buttonStyle(SketchPressStyle()).disabled(disabled).opacity(disabled ? 0.4 : 1).accessibilityLabel(label)
    }

    // MARK: Where

    private var whereField: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("City", text: $result.destination)
                .font(Sketch.display(.title2, weight: .semibold)).textContentType(.addressCity).submitLabel(.next)
                .autocorrectionDisabled()
                .focused($focus, equals: .destination).onSubmit { focus = .name }
                .onChange(of: result.destination) { _, text in cities.update(text) }
            if focus == .destination && !cities.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(cities.results.prefix(5), id: \.self) { item in
                        Button {
                            cities.chosen = item.title
                            result.destination = item.title
                            cities.results = []; focus = .name
                        } label: {
                            HStack(spacing: 10) {
                                TrippyIconView(icon: .pin, size: 18, weight: 2).foregroundStyle(Sketch.coral)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(Sketch.text(15, "SemiBold", relativeTo: .body))
                                    if !item.subtitle.isEmpty { Text(item.subtitle).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
                                }
                                Spacer()
                            }
                            .frame(minHeight: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
            TextField("Trip name (optional)", text: $result.name).font(Sketch.text(15, relativeTo: .body))
                .focused($focus, equals: .name).submitLabel(.done)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Sketch.paperDeep))
                .accessibilityLabel("Trip name")
        }
    }

    // MARK: Who

    private var who: some View {
        VStack(alignment: .leading, spacing: 12) {
            chips(Self.groups.map { ($0.0, $0.0, $0.1) }, selected: [result.group]) { group in
                withAnimation(.snappy) {
                    result.group = group
                    if group == "Solo" { result.travelers = 1 } else if group == "Couple" { result.travelers = 2 }
                    else if result.travelers < 3 { result.travelers = group == "Family" ? 4 : 3 }
                }
            }
            HStack(spacing: 12) {
                Text("Travelers").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                Spacer()
                roundButton("minus", label: "One fewer traveler", disabled: result.travelers <= 1) { result.travelers -= 1 }
                Text("\(result.travelers)").font(Sketch.display(.title2, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText()).frame(minWidth: 28)
                    .accessibilityLabel("\(result.travelers) travelers")
                roundButton("plus", label: "One more traveler", disabled: result.travelers >= 20) { result.travelers += 1 }
            }
            .animation(.snappy, value: result.travelers)
        }
    }

    // MARK: When

    private var dateSummary: String {
        let f = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "en_GB"))
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Dates", selection: $result.flexible.animation(.snappy)) {
                Text("Exact dates").tag(false); Text("Flexible").tag(true)
            }
            .pickerStyle(.segmented)
            if result.flexible {
                HStack(spacing: 12) {
                    Text("How long").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    Spacer()
                    roundButton("minus", label: "One day fewer", disabled: result.duration <= 1) { result.duration -= 1 }
                    Text("\(result.duration) \(result.duration == 1 ? "day" : "days")").font(Sketch.display(.title3, weight: .bold))
                        .monospacedDigit().contentTransition(.numericText()).frame(minWidth: 70)
                    roundButton("plus", label: "One day more", disabled: result.duration >= 21) { result.duration += 1 }
                }
                .animation(.snappy, value: result.duration)
            } else {
                RangeCalendar(start: $start, end: $end)
            }
        }
    }

    // MARK: Getting there

    private var modeIcon: TrippyIcon { Self.modes.first { $0.id == result.travelMode }?.icon ?? .plane }

    private var gettingThere: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Self.modes, id: \.id) { mode in
                    let on = result.travelMode == mode.id
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { result.travelMode = mode.id } } label: {
                        VStack(spacing: 4) {
                            DoodleView(doodle: mode.doodle, tint: on ? Sketch.sky : Sketch.inkFaint, lineWidth: 2, wash: on)
                                .frame(width: 44, height: 44).id(on)
                            Text(mode.title).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Sketch.sky.opacity(0.14) : Sketch.paperDeep))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Sketch.sky.opacity(0.6) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            VStack(spacing: 6) {
                timeRow(result.travelMode == "plane" ? "Landing" : "Arriving", text: $result.arrivalTime, field: .arrival, placeholder: "18:45")
                Divider()
                timeRow(result.travelMode == "plane" ? "Flight home" : result.travelMode == "train" ? "Train home" : "Heading home", text: $result.departureTime, field: .departure, placeholder: "19:40")
            }
            HStack(spacing: 8) {
                browseButton(modeBrowseTitle, symbol: "arrow.up.right") { if let url = modeBrowseURL { openURL(url) } }
                    .disabled(city.isEmpty)
                if result.travelMode != "car" { FindBookingMenu(city: city, mode: result.travelMode) }
            }
        }
    }

    private func timeRow(_ title: String, text: Binding<String>, field: Field, placeholder: String) -> some View {
        HStack {
            Text(title).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
            Spacer()
            TextField(placeholder, text: text).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                .font(Sketch.text(15, "SemiBold", relativeTo: .body)).monospacedDigit().frame(maxWidth: 120)
                .focused($focus, equals: field)
                .onSubmit { text.wrappedValue = TimeShorthand.normalize(text.wrappedValue) }
                .onChange(of: focus) { old, new in
                    // "12" becomes "12:00" as soon as the field is left.
                    if old == field && new != field { text.wrappedValue = TimeShorthand.normalize(text.wrappedValue) }
                }
        }
        .frame(minHeight: 40)
    }

    private func browseButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title); Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
            .padding(.horizontal, 14).frame(minHeight: 40).raisedCapsule()
        }
        .buttonStyle(SketchPressStyle())
    }

    private var isoStart: String? { result.flexible ? nil : GuideDates.iso.string(from: start) }
    private var isoEnd: String? { result.flexible ? nil : GuideDates.iso.string(from: end) }
    private var modeBrowseTitle: String { TripLinks.travelTitle(mode: result.travelMode, city: city) }
    private var modeBrowseURL: URL? { TripLinks.travel(mode: result.travelMode, city: city, start: isoStart, end: isoEnd) }

    // MARK: Pace

    private var paceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Self.paces, id: \.id) { pace in
                tile(pace.title, pace.detail, symbol: pace.symbol, selected: (result.pace ?? "balanced") == pace.id,
                     accent: pace.id == "speedrun" ? Sketch.coral : Sketch.ink) {
                    withAnimation(.snappy) { result.pace = pace.id }
                }
            }
        }
    }

    // MARK: Interests

    private var interestSummary: String? {
        let n = result.interests.count + result.tags.count
        return n == 0 ? nil : "\(result.interests.count) picked" + (result.tags.isEmpty ? "" : " · \(result.tags.count) specific")
    }

    // MARK: Budget

    private var budgetRow: some View {
        let group = result.budgetBasis == "group"
        let factor = group ? max(1, result.travelers) : 1
        return VStack(spacing: 10) {
            Picker("Budget for", selection: Binding(get: { result.budgetBasis }, set: { basis in
                // Keep the same spend when switching basis.
                if let amount = Int(result.budget), basis != result.budgetBasis {
                    result.budget = String(basis == "group" ? amount * max(1, result.travelers) : amount / max(1, result.travelers))
                }
                result.budgetBasis = basis
            })) {
                Text("Per person").tag("per person"); Text("Whole group").tag("group")
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                ForEach(Self.budgets, id: \.0) { symbol, title, amount in
                    let selected = budgetLevel == symbol
                    tile(symbol, "\(title) · €\(amount * factor)", selected: selected) {
                        budgetLevel = selected ? nil : symbol; result.budget = selected ? "" : String(amount * factor)
                    }
                }
            }
            HStack {
                Text(group ? "Or your own, for everyone a day" : "Or your own, per person a day")
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                Spacer()
                TextField("€", text: Binding(get: { result.budget }, set: { result.budget = $0.filter(\.isNumber); budgetLevel = nil }))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Sketch.paperDeep)).focused($focus, equals: .budget)
            }
        }
    }

    // MARK: Stay

    private var stay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField("Hotel or neighbourhood", text: $result.stay).font(Sketch.text(15, relativeTo: .body))
                    .focused($focus, equals: .stay).autocorrectionDisabled()
                if !result.stay.isEmpty {
                    Button { result.stay = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Sketch.inkFaint) }
                        .accessibilityLabel("Clear stay")
                }
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Sketch.paperDeep))
            if focus == .stay && !stayResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(stayResults.prefix(4).enumerated()), id: \.offset) { _, item in
                        Button { result.stay = item.name ?? result.stay; stayResults = []; focus = nil } label: {
                            HStack(spacing: 10) {
                                TrippyIconView(icon: .bed, size: 18, weight: 2).foregroundStyle(Sketch.plum)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name ?? "").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).lineLimit(1)
                                    if let area = item.placemark.subLocality ?? item.placemark.thoroughfare {
                                        Text(area).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                                    }
                                }
                                Spacer()
                            }
                            .frame(minHeight: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                Button { focus = nil; showStayMap = true } label: {
                    HStack(spacing: 6) {
                        TrippyIconView(icon: .compass, size: 16, weight: 2.2)
                        Text("Where to stay")
                    }
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.paper)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Capsule().fill(Sketch.ink))
                }
                .buttonStyle(SketchPressStyle()).disabled(city.isEmpty).opacity(city.isEmpty ? 0.4 : 1)
                Menu {
                    Button("Booking.com") { if let url = stayURL(airbnb: false) { openURL(url) } }
                    Button("Airbnb") { if let url = stayURL(airbnb: true) { openURL(url) } }
                } label: {
                    HStack(spacing: 6) { Text("Browse stays"); Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)) }
                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                        .padding(.horizontal, 14).frame(minHeight: 40).raisedCapsule()
                }
                .disabled(city.isEmpty)
            }
        }
    }

    private func stayURL(airbnb: Bool) -> URL? {
        TripLinks.stay(area: result.stay, city: city, start: isoStart, end: isoEnd, travelers: result.travelers, airbnb: airbnb)
    }

    // MARK: Must-see

    private var mustSee: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.mustSee.isEmpty { pickedStrip }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField(city.isEmpty ? "Search places" : "Search places in \(city)", text: $placeQuery)
                    .font(Sketch.text(15, relativeTo: .body)).focused($focus, equals: .place).autocorrectionDisabled()
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Sketch.paperDeep))
            if placeQuery.count >= 2 {
                VStack(spacing: 0) {
                    ForEach(Array(placeResults.prefix(6).enumerated()), id: \.offset) { _, item in placeRow(item) }
                }
            } else {
                if !citySaves.isEmpty {
                    Picker("Show", selection: $pickSource) {
                        Text("Your saves · \(citySaves.count)").tag(PickInfo.Source.save)
                        Text("Recommended").tag(PickInfo.Source.recommended)
                    }
                    .pickerStyle(.segmented)
                }
                if pickSource == .save && !citySaves.isEmpty { savesPanel }
                else if Self.pickCategories.contains(where: { !picks($0.id).isEmpty }) { pickBrowser }
            }
        }
        .sheet(item: $openPick) { info in
            NavigationStack {
                PickDetailView(info: info, picked: isPicked(info.place)) { toggle(info.place) }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { openPick = nil } } }
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $pickList) { list in
            switch list {
            case .saves:
                PickListSheet(title: "Your saves in \(city)", items: citySaves, picked: $result.mustSee, bestCount: savesTarget)
            case .recommended(let category):
                PickListSheet(title: Self.pickCategories.first { $0.id == category }?.title ?? "Recommended",
                              items: recommendedPicks(category), picked: $result.mustSee)
            }
        }
        .onAppear(perform: seedSaves)
        .onChange(of: city) { _, _ in seedSaves() }
    }

    // MARK: Picked

    /// What is picked, on one line that scrolls sideways: the section never grows as more are added.
    private var pickedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(result.mustSee.count) PICKED · PLANNED FIRST").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.ochre)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(result.mustSee, id: \.self) { place in
                        HStack(spacing: 6) {
                            Image(systemName: savedNames.contains(place.name) ? "heart.fill" : "star.fill").imageScale(.small)
                                .foregroundStyle(savedNames.contains(place.name) ? Sketch.coral : Sketch.ochre)
                            Text(place.name).lineLimit(1)
                            Button { toggle(place) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                .frame(minWidth: 32, minHeight: 32).accessibilityLabel("Remove \(place.name)")
                        }
                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                        .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 36)
                        .background(Capsule().fill(Sketch.ochre.opacity(0.14)))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .cardEdgeRow()
        }
    }

    // MARK: Saves

    /// The traveller's saves for this city, the ones with the most to go on first.
    /// Built once per destination, not on every redraw (a traveller can have hundreds of saves).
    private var citySaves: [PickInfo] { loadedSaves.city == city ? loadedSaves.items : [] }
    private func refreshSaves() {
        guard loadedSaves.city != city else { return }
        loadedSaves = (city, PickInfo.rankSaves((savesFor ?? ComposerSaves.provider)?(city) ?? []))
    }
    private var savedNames: Set<String> { Set(citySaves.map(\.place.name)) }
    private var savesTarget: Int { PickInfo.defaultCount(days: parsed.duration) }

    private var savesPanel: some View {
        let saves = citySaves
        let picked = saves.filter { isPicked($0.place) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(picked == 0 ? "None picked. They stay ideas you can add on the plan."
                     : picked == saves.count ? "All \(saves.count) picked. Picked places are planned first."
                     : "\(picked) of \(saves.count) picked for \(parsed.duration) days, the ones your videos say most about. The rest stay ideas.")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Menu {
                    Button("Pick the best \(min(savesTarget, saves.count))", systemImage: "star") { pickBestSaves(savesTarget) }
                    Button("Pick all \(saves.count)", systemImage: "checkmark.circle") { pickBestSaves(saves.count) }
                    Button("Pick none", systemImage: "circle.slash", role: .destructive) { pickBestSaves(0) }
                } label: {
                    Text("Pick").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).frame(minWidth: 44, minHeight: 44)
                }
            }
            row(Array(saves.prefix(12)), total: saves.count, tint: Sketch.coral) { pickList = .saves }
        }
    }

    private func pickBestSaves(_ n: Int) {
        withAnimation(.snappy) {
            let saves = citySaves
            let names = Set(saves.map(\.place.name))
            result.mustSee.removeAll { names.contains($0.name) }
            result.mustSee.append(contentsOf: saves.prefix(n).map(\.place))
        }
    }

    /// Saves are ticked by default, once, up to about two a day; a city change swaps the old city's for the new one's.
    private func seedSaves() {
        refreshSaves()
        let saves = citySaves
        guard !saves.isEmpty else { return }
        if seededCity != nil && seededCity != city {
            result.mustSee.removeAll { seededNames.contains($0.name) }
        } else if result.savesSeeded {
            return
        }
        let chosen = saves.prefix(savesTarget).map(\.place).filter { place in !result.mustSee.contains { $0.name == place.name } }
        result.mustSee.append(contentsOf: chosen)
        seededNames = Set(chosen.map(\.name)); seededCity = city
        result.savesSeeded = true
        pickSource = .save
    }

    // MARK: Picks by category

    private static let pickCategories: [(id: String, title: String, symbol: String)] = [
        ("sights", "Sights", "building.columns"), ("museums", "Museums", "paintpalette"), ("nature", "Parks & views", "leaf"),
        ("food", "Food & markets", "fork.knife"), ("bars", "Bars", "wineglass"),
    ]
    /// Famous places (Wikidata, ranked by fame) split by kind; food and bars come from Apple Maps.
    private func picks(_ category: String) -> [ComposerPlace] {
        let saved = Set(savedNames.map(ComposerParser.fold))
        let all: [ComposerPlace]
        switch category {
        case "museums": all = famous.filter { $0.category == "museum" }
        case "nature": all = famous.filter { $0.category == "nature" }
        case "sights":
            all = famous.filter { $0.category == "attraction" } + (famous.isEmpty ? suggestions.compactMap(Self.composerPlace) : [])
        default: all = localPicks[category] ?? []
        }
        // A saved place is shown once, with the saves, not again among the recommendations.
        return all.filter { !saved.contains(ComposerParser.fold($0.name)) }
    }
    private func recommendedPicks(_ category: String) -> [PickInfo] {
        picks(category).map { place in
            PickInfo(place: place, source: .recommended, summary: place.summary ?? "", fame: place.fame ?? 0, wikiTitle: place.wikiTitle)
        }
    }
    private static func composerPlace(_ item: MKMapItem) -> ComposerPlace? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let c = item.placemark.coordinate
        return ComposerPlace(name: name, latitude: c.latitude, longitude: c.longitude,
                             address: item.placemark.thoroughfare ?? "", category: plannerCategory(item))
    }

    private var pickBrowser: some View {
        let available = Self.pickCategories.filter { !picks($0.id).isEmpty }
        let current = available.contains { $0.id == pickCategory } ? pickCategory : (available.first?.id ?? "sights")
        let items = recommendedPicks(current)
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(available, id: \.id) { category in
                        let on = category.id == current
                        Button {
                            withAnimation(.snappy) { pickCategory = category.id }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.symbol).font(.system(size: 12, weight: .semibold))
                                Text(category.title)
                                Text("\(picks(category.id).count)").monospacedDigit().opacity(0.6)
                            }
                            .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                            .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
                        }
                        .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .cardEdgeRow()
            row(Array(items.prefix(12)), total: items.count, tint: Sketch.ochre) { pickList = .recommended(current) }
            Text(current == "food" || current == "bars" ? "From Apple Maps, near the centre of \(city). Tap a card for more."
                 : "Ranked by how widely they're known, from Wikipedia and Wikidata. Tap a card for more.")
                .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
        }
    }

    /// One row of fixed-size cards that scrolls sideways, then "See all" for the rest in a sheet.
    private func row(_ items: [PickInfo], total: Int, tint: Color, seeAll: @escaping () -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { info in
                    SavePickCard(info: info, picked: isPicked(info.place), tint: tint,
                             toggle: { toggle(info.place) }, open: { openPick = info })
                }
                if total > 3 { SeeAllCard(count: total, action: seeAll) }
            }
        }
        .cardEdgeRow()
    }

    private func isPicked(_ place: ComposerPlace) -> Bool { result.mustSee.contains { $0.name == place.name } }
    private func toggle(_ place: ComposerPlace) {
        withAnimation(.snappy) {
            if isPicked(place) { result.mustSee.removeAll { $0.name == place.name } } else { result.mustSee.append(place) }
        }
    }

    private func famousRow(_ place: ComposerPlace) -> some View {
        let added = result.mustSee.contains { $0.name == place.name }
        return Button {
            withAnimation(.snappy) {
                if added { result.mustSee.removeAll { $0.name == place.name } } else { result.mustSee.append(place) }
            }
        } label: {
            HStack(spacing: 10) {
                TrippyIconView(icon: .star, size: 18, weight: 2).foregroundStyle(Sketch.ochre).frame(width: 24)
                Text(place.name).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).lineLimit(1)
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(added ? Sketch.sage : Sketch.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(minHeight: 46).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "Remove \(place.name)" : "Add \(place.name)")
    }

    private func placeRow(_ item: MKMapItem) -> some View {
        let name = item.name ?? ""
        let added = result.mustSee.contains { $0.name == name }
        return Button {
            withAnimation(.snappy) {
                if added { result.mustSee.removeAll { $0.name == name } }
                else if !name.isEmpty {
                    let c = item.placemark.coordinate
                    result.mustSee.append(ComposerPlace(name: name, latitude: c.latitude, longitude: c.longitude,
                                                        address: item.placemark.thoroughfare ?? "", category: Self.plannerCategory(item)))
                }
            }
            placeQuery = ""
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(for: item)).foregroundStyle(Sketch.clay).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).lineLimit(1)
                    if let area = item.placemark.subLocality ?? item.placemark.locality {
                        Text(area).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(added ? Sketch.sage : Sketch.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "Remove \(name)" : "Add \(name)")
    }

    // MARK: Anything else

    private var message: some View {
        ZStack(alignment: .topLeading) {
            if result.message.isEmpty {
                Text("Diet, mobility, things to avoid, a birthday dinner… anything that matters.")
                    .font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.inkFaint).padding(.top, 8).padding(.leading, 5)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $result.message).font(Sketch.text(16, relativeTo: .body)).scrollContentBackground(.hidden)
                .frame(minHeight: 96).focused($focus, equals: .message)
                .accessibilityLabel("Anything else")
        }
    }

    private var summary: some View {
        let r = parsed
        var parts = ["\(r.travelers) \(r.travelers == 1 ? "traveler" : "travelers"), \(r.group.lowercased())"]
        switch r.pace { case "relaxed": parts.append("relaxed pace"); case "intense": parts.append("full days"); case "speedrun": parts.append("speedrun"); default: parts.append("balanced pace") }
        if !r.interests.isEmpty { parts.append("\(r.interests.count + r.tags.count) interests") }
        if !r.budget.isEmpty { parts.append("€\(r.budget) a day" + (r.budgetBasis == "group" ? " for all" : " each")) }
        if !r.arrivalTime.isEmpty { parts.append("arrives \(r.arrivalTime)") }
        if !result.mustSee.isEmpty { parts.append("\(result.mustSee.count) must-see") }
        return Text("Plan for " + parts.joined(separator: " · "))
            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).padding(.horizontal, 4)
    }

    private var bottomBar: some View {
        SketchPrimaryButton(title: "Create plan", enabled: !city.isEmpty) { onSubmit(parsed) }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
            .background(Sketch.paper.ignoresSafeArea())
    }

    // MARK: Places

    private static func symbol(for item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .museum: "building.columns"; case .restaurant, .bakery, .cafe: "fork.knife"; case .park, .nationalPark, .beach: "leaf"
        case .nightlife, .winery, .brewery: "wineglass"; case .store: "bag"; default: "mappin"
        }
    }

    private static func plannerCategory(_ item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .museum: "museum"; case .restaurant, .bakery: "food"; case .cafe: "coffee"
        case .park, .nationalPark, .beach: "nature"; case .nightlife, .winery, .brewery: "bar"; case .store: "shopping"
        default: "attraction"
        }
    }

    private func region() async -> MKCoordinateRegion? {
        guard city.count >= 2, let mark = try? await CLGeocoder().geocodeAddressString(city).first, let location = mark.location else { return nil }
        return MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    }

    private func searchPlaces() async {
        let text = placeQuery.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { placeResults = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = city.isEmpty ? text : "\(text), \(city)"
        request.resultTypes = .pointOfInterest
        let reg = await region()
        if let reg { request.region = reg }
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        guard !Task.isCancelled else { return }
        placeResults = reg.map { r in items.filter { Self.inside(r, $0) } } ?? items
    }

    private func searchStays() async {
        let text = result.stay.trimmingCharacters(in: .whitespaces)
        guard focus == .stay, text.count >= 2 else { stayResults = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = city.isEmpty ? text : "\(text), \(city)"
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel])
        request.resultTypes = .pointOfInterest
        let reg = await region()
        if let reg { request.region = reg }
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        guard !Task.isCancelled else { return }
        stayResults = reg.map { r in items.filter { Self.inside(r, $0) } } ?? items
    }

    /// Landmarks, museums and parks inside the city (a region-bound request, so
    /// nothing from elsewhere). Landmark categories come first.
    private func loadSuggestions() async {
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, let region = await region() else { suggestions = []; famous = []; localPicks = [:]; return }
        async let famousPlaces = FamousPlaces.shared.places(near: region.center, city: city)
        async let food = Self.mapPicks(query: "famous restaurant", categories: [.restaurant, .foodMarket, .bakery], region: region, as: "food")
        async let bars = Self.mapPicks(query: "cocktail bar", categories: [.nightlife, .winery, .brewery], region: region, as: "bar")
        famous = await famousPlaces
        localPicks = ["food": await food, "bars": await bars]
        guard !Task.isCancelled, famous.isEmpty else { return }
        var landmarks: [MKPointOfInterestCategory] = [.museum, .stadium, .theater]
        if #available(iOS 18.0, *) { landmarks = [.landmark, .castle, .nationalMonument, .fortress] + landmarks }
        let first = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        first.pointOfInterestFilter = MKPointOfInterestFilter(including: landmarks)
        let second = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        second.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park, .nationalPark, .beach, .aquarium, .zoo])
        let a = (try? await MKLocalSearch(request: first).start())?.mapItems ?? []
        let b = (try? await MKLocalSearch(request: second).start())?.mapItems ?? []
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        suggestions = Array((a + b).filter { Self.inside(region, $0) && seen.insert($0.name ?? "").inserted }.prefix(8))
    }

    /// Apple Maps places of some kinds in the city's centre, closest to the centre first.
    private static func mapPicks(query: String, categories: [MKPointOfInterestCategory], region: MKCoordinateRegion, as category: String) async -> [ComposerPlace] {
        let filter = MKPointOfInterestFilter(including: categories)
        let centre = MKCoordinateRegion(center: region.center, latitudinalMeters: 6000, longitudinalMeters: 6000)
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = query; search.region = centre
        search.resultTypes = .pointOfInterest; search.pointOfInterestFilter = filter
        let nearby = MKLocalPointsOfInterestRequest(coordinateRegion: centre)
        nearby.pointOfInterestFilter = filter
        async let a = try? MKLocalSearch(request: search).start()
        async let b = try? MKLocalSearch(request: nearby).start()
        let items = ((await a)?.mapItems ?? []) + ((await b)?.mapItems ?? [])
        var seen = Set<String>()
        return items.filter { item in
            guard let kind = item.pointOfInterestCategory, categories.contains(kind), inside(centre, item) else { return false }
            return seen.insert((item.name ?? "").lowercased()).inserted
        }.prefix(18).compactMap { item in
            composerPlace(item).map { var p = $0; p.category = category; return p }
        }
    }

    private static func inside(_ region: MKCoordinateRegion, _ item: MKMapItem) -> Bool {
        let c = item.placemark.coordinate
        return abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta
            && abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// City suggestions while typing the destination.
final class CityCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    var chosen = ""
    private let completer = MKLocalSearchCompleter()
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }
    func update(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2, query != chosen else { results = []; return }
        completer.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Keep places that read as cities or regions, not street addresses.
        results = completer.results.filter { !$0.title.contains(where: \.isNumber) && !$0.subtitle.contains(where: \.isNumber) }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }
}
