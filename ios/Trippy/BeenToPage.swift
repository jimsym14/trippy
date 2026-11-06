import SwiftUI
import MapKit

// MARK: - Page

/// "Been to": a map or 3D globe of the places you have visited, filters, and a
/// passport panel with insights for the world or one continent.
struct WorldGlobeView: View {
    var addRequestID: UUID? = nil
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @AppStorage("trippy.native.been.library.outlines") private var showOutlines = true
    @AppStorage("trippy.native.been.library.fill") private var showFill = true
    @AppStorage("trippy.native.been.library.cities") private var showCities = true
    @AppStorage("trippy.native.been.library.hatching") private var hatching = false
    @AppStorage("trippy.native.been.library.imagery") private var imagery = false
    @AppStorage("trippy.native.been.library.globe3d") private var terrain = true
    @AppStorage("trippy.native.been.library.view") private var viewMode = "map"
    @AppStorage("trippy.native.been.library.fillMode") private var fillModeRaw = CountryFillMode.visited.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var all = BeenPassportSnapshot()
    @State private var years: Set<Int> = []
    @State private var continent: String?
    @State private var camera = BeenCameraRequest()
    @State private var globeFocus: CLLocationCoordinate2D?
    @State private var globeFocusID = UUID()
    @State private var geometries: [CountryGeometry] = []
    @State private var shapes: CountryShapesOverlay?
    @State private var globeTexture: UIImage?
    @State private var unavailable: [String] = []
    @State private var detent: PanelDetent = .peek
    @State private var dragOffset: CGFloat = 0
    @State private var collection: BeenCollection?
    @State private var countryDetail: VisitedCountryGroup?
    @State private var cityDetail: VisitedPlace?
    @State private var clusterDetail: BeenClusterSelection?
    @State private var showAdd = false
    @State private var showFilters = false
    @State private var showShare = false
    @State private var visitFeedbackID: UUID?

    enum PanelDetent: CaseIterable { case peek, half, full }

    private var fillMode: CountryFillMode { CountryFillMode(rawValue: fillModeRaw) ?? .visited }
    /// The visits the map and panel show after the year and continent filters.
    private var snapshot: BeenPassportSnapshot {
        BeenPassportSnapshot(all.visits.filter { visit in
            (years.isEmpty || years.contains(Calendar.current.component(.year, from: visit.visitedAt)))
                && (continent == nil || WorldContinentCatalog.name(for: visit.countryCode) == continent)
        })
    }
    private var geometryKey: String { all.countries.map(\.id).joined(separator: "|") }
    private var styleKey: String {
        "\(snapshot.countries.map { "\($0.id)\($0.visits.count)" }.joined()):\(showFill):\(showOutlines):\(hatching):\(fillModeRaw):\(scheme == .dark)"
    }
    private var filtered: Bool { !years.isEmpty }
    static func flag(_ code: String?) -> String {
        guard let code, code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "🌍" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar($0.value + 127397) }))
    }

    var body: some View {
        GeometryReader { geometry in
            let snapshot = self.snapshot
            let heights = panelHeights(geometry.size.height)
            let height = min(heights.full, max(heights.peek, heights.value(detent) - dragOffset))
            ZStack(alignment: .bottom) {
                canvas(snapshot).ignoresSafeArea(.container, edges: .bottom)
                VStack(alignment: .leading, spacing: 12) {
                    header(snapshot)
                    controls
                    Spacer()
                    if fillMode != .visited && showFill && !snapshot.countries.isEmpty {
                        BeenLegend(mode: fillMode, snapshot: snapshot).padding(.bottom, height + 10)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .opacity(detent == .full ? 0 : 1).allowsHitTesting(detent != .full)
                .padding(.bottom, Self.tabBarClearance)
                panel(snapshot, height: height, heights: heights)
                    .padding(.horizontal, 10).padding(.bottom, Self.tabBarClearance)
            }
        }
        .foregroundStyle(BeenPalette.ink(scheme)).background(BeenPalette.base(scheme))
        .sheet(isPresented: $showAdd) { VisitedPlacePicker(onAdd: addVisit) }
        .sheet(isPresented: $showFilters) { filterSheet }
        .sheet(isPresented: $showShare) { BeenShareSheet(snapshot: snapshot, texture: globeTexture, scopeTitle: scopeTitle) }
        .sheet(item: $collection) { BeenCollectionSheet(collection: $0) }
        .sheet(item: $countryDetail) { WorldCountryVisitsView(group: $0) }
        .sheet(item: $cityDetail) { BeenVisitDetail(place: $0) }
        .sheet(item: $clusterDetail) { BeenClusterCitiesSheet(selection: $0) }
        .onAppear { all = BeenPassportSnapshot(VisitedPlace.decode(storage)) }
        .onChange(of: storage) { _, value in all = BeenPassportSnapshot(VisitedPlace.decode(value)) }
        .onChange(of: addRequestID) { _, id in if id != nil { showAdd = true } }
        .sensoryFeedback(.success, trigger: visitFeedbackID)
        .sensoryFeedback(.selection, trigger: detent)
        .task(id: geometryKey) { await loadGeometries() }
        .onChange(of: styleKey) { _, _ in rebuildShapes() }
        .task(id: "\(styleKey):\(imagery):\(viewMode):\(geometries.count)") { await loadGlobeTexture() }
    }

    private var scopeTitle: String {
        [continent.map(BeenContinentName.title), years.isEmpty ? nil : years.sorted().map(String.init).joined(separator: ", ")].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Canvas

    @ViewBuilder private func canvas(_ snapshot: BeenPassportSnapshot) -> some View {
        ZStack {
            if viewMode == "globe" {
                ZStack {
                    RadialGradient(colors: [BeenPalette.amber.opacity(scheme == .dark ? 0.16 : 0.12), .clear], center: .center, startRadius: 40, endRadius: 300)
                    BeenGlobe3DView(texture: globeTexture, focus: globeFocus, focusID: globeFocusID, dark: scheme == .dark, reduceMotion: reduceMotion)
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            } else {
                BeenGlobeMap(visits: showCities ? snapshot.visits : [], dataRevision: snapshot.revision, shapes: shapes, camera: camera,
                             showCities: showCities, imagery: imagery, globe3D: terrain, dark: scheme == .dark, reduceMotion: reduceMotion,
                             onVisit: { cityDetail = $0 }, onCluster: { clusterDetail = BeenClusterSelection(visits: $0) })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: BeenPalette.base(scheme), location: 0), .init(color: BeenPalette.base(scheme).opacity(0.85), location: 0.45), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 170).allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: viewMode)
    }

    // MARK: Header and controls

    private func header(_ snapshot: BeenPassportSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Been to").font(Sketch.display(.title, weight: .bold))
                Text(snapshot.visits.isEmpty ? "Add the cities you’ve visited"
                     : "\(snapshot.countryCount) \(snapshot.countryCount == 1 ? "country" : "countries") · \(snapshot.visits.count) \(snapshot.visits.count == 1 ? "city" : "cities")\(scopeTitle.isEmpty ? "" : " · \(scopeTitle)")")
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BeenAddVisitButton { showAdd = true }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            SegmentedPill(options: [("map", "Map", "map"), ("globe", "Globe", "globe")], selection: $viewMode)
            Spacer()
            RaisedIconButton(symbol: filtered || fillMode != .visited ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                             title: "Filters and map style") { showFilters = true }
            RaisedIconButton(symbol: "square.and.arrow.up", title: "Share") { showShare = true }
        }
    }

    // MARK: Panel

    struct Heights { let peek: CGFloat; let half: CGFloat; let full: CGFloat
        func value(_ d: PanelDetent) -> CGFloat { switch d { case .peek: peek; case .half: half; case .full: full } } }
    /// Room the app's floating tab bar takes at the bottom.
    static let tabBarClearance: CGFloat = 78
    private func panelHeights(_ total: CGFloat) -> Heights {
        let usable = total - Self.tabBarClearance
        return Heights(peek: 136, half: max(300, usable * 0.55), full: max(320, usable - 8))
    }

    private func panel(_ snapshot: BeenPassportSnapshot, height: CGFloat, heights: Heights) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Capsule().fill(BeenPalette.ink(scheme).opacity(0.22)).frame(width: 36, height: 5).padding(.top, 8)
                    .accessibilityHidden(true)
                ContinentCarousel(selection: continent, counts: all.continentCounts) { select($0) }
                if detent == .peek {
                    HStack(spacing: 6) {
                        Text(snapshot.visits.isEmpty ? "Your passport is empty" : snapshot.peekLine(continent: continent))
                        Spacer()
                        Image(systemName: "chevron.up").font(.caption.weight(.bold))
                    }
                    .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                    .padding(.horizontal, 18).padding(.bottom, 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(panelDrag(heights))
            .onTapGesture { setDetent(detent == .peek ? .half : .peek) }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: detent == .peek ? "Open passport" : "Close passport") { setDetent(detent == .peek ? .half : .peek) }

            if detent != .peek {
                ScrollView {
                    BeenInsights(snapshot: snapshot, continent: continent, unavailable: !unavailable.isEmpty,
                                 onCollection: { collection = $0 }, onCountry: { focus(on: $0); countryDetail = $0 },
                                 onYear: { toggleYear($0) }, selectedYears: years, onAdd: { showAdd = true })
                }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .top).frame(maxWidth: 640)
        .background(BeenPalette.base(scheme).opacity(0.72), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(BeenGlassSurface(radius: 30))
    }

    /// The panel follows the finger, then settles on the detent nearest to where
    /// the flick would have carried it.
    private func panelDrag(_ heights: Heights) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { dragOffset = value.translation.height }
            }
            .onEnded { value in
                let current = heights.value(detent) - value.translation.height
                let projected = heights.value(detent) - value.predictedEndTranslation.height
                let target = PanelDetent.allCases.min { abs(heights.value($0) - projected) < abs(heights.value($1) - projected) } ?? detent
                _ = current
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    detent = target; dragOffset = 0
                }
            }
    }

    private func setDetent(_ value: PanelDetent) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { detent = value; dragOffset = 0 }
    }

    // MARK: Filters sheet

    private var filterSheet: some View {
        BeenSheetFrame(title: "Map", subtitle: "") {
            VStack(alignment: .leading, spacing: 22) {
                group("View") {
                    Picker("View", selection: $viewMode) { Text("Map").tag("map"); Text("Globe").tag("globe") }
                        .pickerStyle(.segmented).padding(.vertical, 12)
                }
                group("Color countries") {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(CountryFillMode.allCases) { mode in
                                Button { fillModeRaw = mode.rawValue } label: {
                                    Label(mode.title, systemImage: mode.symbol)
                                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(fillMode == mode ? BeenPalette.ink(scheme) : BeenPalette.secondary(scheme))
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(fillMode == mode ? BeenPalette.amber.opacity(0.2) : BeenPalette.ink(scheme).opacity(0.04)))
                                }
                                .buttonStyle(.plain).accessibilityAddTraits(fillMode == mode ? .isSelected : [])
                            }
                        }
                        if fillMode != .visited { BeenLegend(mode: fillMode, snapshot: snapshot, compact: false) }
                    }
                    .padding(.vertical, 12)
                }
                group("Layers") {
                    Toggle("Fill", isOn: $showFill).frame(minHeight: 48)
                    Divider()
                    Toggle("Outlines", isOn: $showOutlines).frame(minHeight: 48)
                    Divider()
                    Toggle("Hatching", isOn: $hatching).frame(minHeight: 48)
                    Divider()
                    Toggle("City markers", isOn: $showCities).frame(minHeight: 48)
                }
                if !all.years.isEmpty {
                    group("Years") {
                        FlowLayout(spacing: 8) {
                            chip("All years", selected: years.isEmpty) { years = [] }
                            ForEach(all.years, id: \.self) { year in chip(String(year), selected: years.contains(year)) { toggleYear(year) } }
                        }
                        .padding(.vertical, 12)
                    }
                }
                group("Base map") {
                    Picker("Base map", selection: $imagery) { Text("Standard").tag(false); Text("Satellite").tag(true) }
                        .pickerStyle(.segmented).padding(.vertical, 12)
                    Divider()
                    Toggle("3D terrain", isOn: $terrain).frame(minHeight: 48)
                }
            }
            .font(Sketch.text(15, "SemiBold", relativeTo: .body)).tint(BeenPalette.accent(scheme))
        }
        .presentationDetents([.medium, .large])
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme)).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0, content: content).padding(.horizontal, 16).beenSurface(radius: 20)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .foregroundStyle(selected ? BeenPalette.ink(scheme) : BeenPalette.secondary(scheme))
                .background(Capsule().fill(selected ? BeenPalette.amber.opacity(0.22) : BeenPalette.ink(scheme).opacity(0.05)))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

    private func toggleYear(_ year: Int) {
        if years.contains(year) { years.remove(year) } else { years.insert(year) }
    }

    private func select(_ value: String?) {
        continent = value
        let center = value.map(BeenContinentName.center) ?? CLLocationCoordinate2D(latitude: 25, longitude: 15)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
            camera = BeenCameraRequest(latitude: center.latitude, longitude: center.longitude, distance: value == nil ? 78_000_000 : 16_000_000)
        }
        globeFocus = center; globeFocusID = UUID()
        if detent == .peek && value != nil { setDetent(.half) }
    }

    private func focus(on group: VisitedCountryGroup) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) {
            camera = BeenCameraRequest(latitude: group.coordinate.latitude, longitude: group.coordinate.longitude, distance: 2_600_000)
        }
        globeFocus = group.coordinate; globeFocusID = UUID()
    }

    private func addVisit(_ place: VisitedPlace) {
        guard !all.visits.contains(where: { $0.id == place.id }) else { return }
        storage = VisitedPlace.encode(VisitedPlace.adding(place, to: all.visits))
        visitFeedbackID = UUID()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.65)) {
            camera = BeenCameraRequest(latitude: place.latitude, longitude: place.longitude, distance: 1_800_000)
        }
        globeFocus = place.coordinate; globeFocusID = UUID()
    }

    // MARK: Geometry

    @MainActor private func loadGeometries() async {
        let requests = all.countries.compactMap { group -> CountryShapeStore.Request? in
            guard let code = group.countryCode else { return nil }
            return .init(code: code, latitude: group.coordinate.latitude, longitude: group.coordinate.longitude)
        }
        let result = await CountryShapeStore.shared.geometries(for: requests)
        guard !Task.isCancelled else { return }
        geometries = result.shapes; unavailable = result.unavailable
        rebuildShapes()
    }

    private func rebuildShapes() {
        let snapshot = self.snapshot
        let codes = Set(snapshot.countries.compactMap(\.countryCode))
        let visible = geometries.filter { codes.contains($0.code) }
        guard !visible.isEmpty, showFill || showOutlines || hatching else { shapes = nil; return }
        shapes = CountryShapesOverlay(geometries: visible, stats: snapshot.countryStats,
                                      style: CountryShapeStyle(fill: showFill, outlines: showOutlines, hatching: hatching, mode: fillMode, dark: scheme == .dark))
    }

    @MainActor private func loadGlobeTexture() async {
        guard viewMode == "globe" || showShare else { return }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let key = GlobeTextureKey(dark: scheme == .dark, satellite: imagery, style: styleKey + ":\(geometries.count)")
        let image = await GlobeTextureBuilder.shared.texture(key: key, shapes: shapes, visits: snapshot.visits)
        guard !Task.isCancelled else { return }
        globeTexture = image
    }
}

// MARK: - Snapshot insights

extension BeenPassportSnapshot {
    static let worldCountries = 195

    var continentCounts: [String: Int] {
        Dictionary(grouping: countries, by: { WorldContinentCatalog.name(for: $0.countryCode) }).mapValues(\.count)
    }
    var countryStats: [String: CountryVisitStats] {
        Dictionary(uniqueKeysWithValues: countries.compactMap { group in
            group.countryCode.map { ($0, CountryVisitStats(code: $0, continent: WorldContinentCatalog.name(for: $0), cities: group.visits.count,
                                                            lastVisit: group.visits.map(\.visitedAt).max() ?? .now)) }
        })
    }
    func peekLine(continent: String?) -> String {
        if let continent {
            let total = WorldContinentCatalog.count(continent)
            return "\(BeenContinentName.title(continent)): \(countryCount) of \(total) countries · \(visits.count) cities"
        }
        let percent = Int((Double(countryCount) / Double(Self.worldCountries) * 100).rounded())
        return "\(countryCount) countries · \(percent)% of the world · \(visits.count) cities"
    }
    var mostVisited: VisitedCountryGroup? { countries.max { $0.visits.count < $1.visits.count } }
    var latest: VisitedPlace? { visits.max { $0.visitedAt < $1.visitedAt } }
    var northernmost: VisitedPlace? { visits.max { $0.latitude < $1.latitude } }
    var southernmost: VisitedPlace? { visits.min { $0.latitude < $1.latitude } }
    /// The two visited cities farthest apart (great-circle).
    var farthestPair: (VisitedPlace, VisitedPlace, Double)? {
        let sample = Array(visits.prefix(300))
        guard sample.count > 1 else { return nil }
        var best: (VisitedPlace, VisitedPlace, Double)?
        for i in sample.indices { for j in sample.indices where j > i {
            let d = CLLocation(latitude: sample[i].latitude, longitude: sample[i].longitude)
                .distance(from: CLLocation(latitude: sample[j].latitude, longitude: sample[j].longitude))
            if d > (best?.2 ?? 0) { best = (sample[i], sample[j], d) }
        } }
        return best
    }
    /// New countries first reached in each year, for the year chart.
    var newCountriesByYear: [(Int, Int)] {
        var first: [String: Int] = [:]
        for visit in visits { if let code = visit.countryCode?.uppercased() {
            let year = Calendar.current.component(.year, from: visit.visitedAt)
            first[code] = min(first[code] ?? year, year)
        } }
        let counts = Dictionary(grouping: first.values, by: { $0 }).mapValues(\.count)
        return years.sorted().map { ($0, counts[$0] ?? 0) }
    }
}

extension WorldContinentCatalog {
    static let totals = ["Europe": 44, "Asia": 48, "Africa": 54, "North America": 23, "South America": 12, "Oceania": 14]
    static func count(_ continent: String) -> Int { totals[continent] ?? 0 }
}

// MARK: - Insights panel

struct BeenInsights: View {
    let snapshot: BeenPassportSnapshot
    let continent: String?
    let unavailable: Bool
    var onCollection: (BeenCollection) -> Void
    var onCountry: (VisitedCountryGroup) -> Void
    var onYear: (Int) -> Void
    var selectedYears: Set<Int>
    var onAdd: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.visits.isEmpty {
                BeenEmptyPassport(action: onAdd)
            } else if let continent {
                continentSummary(continent)
                countryList
            } else {
                worldSummary
                highlights
                if snapshot.newCountriesByYear.count > 1 { yearChart }
                collections
            }
            Text(unavailable ? "Some outlines couldn’t load. Your visits are saved." : "Outlines: geoBoundaries · Map: Apple")
                .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal, 4)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 28)
    }

    private var worldSummary: some View {
        let share = Double(snapshot.countryCount) / Double(BeenPassportSnapshot.worldCountries)
        return HStack(spacing: 0) {
            metric(snapshot.countryCount.formatted(), "of 195 countries")
            divider
            metric(snapshot.visits.count.formatted(), "cities")
            divider
            metric("\(snapshot.continents.count)/6", "continents")
            Spacer(minLength: 8)
            ProgressRing(value: share, label: "\(Int((share * 100).rounded()))%")
        }
        .padding(18).beenSurface(radius: 24)
    }

    private func continentSummary(_ continent: String) -> some View {
        let total = WorldContinentCatalog.count(continent)
        let share = total == 0 ? 0 : Double(snapshot.countryCount) / Double(total)
        let firstYear = snapshot.visits.map { Calendar.current.component(.year, from: $0.visitedAt) }.min()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ContinentIcon(name: continent, size: 40, selected: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BeenContinentName.title(continent)).font(Sketch.display(.title2, weight: .bold))
                    Text("\(snapshot.countryCount) of \(total) countries · \(snapshot.visits.count) cities")
                        .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer()
                ProgressRing(value: share, label: "\(Int((share * 100).rounded()))%")
            }
            HStack(spacing: 10) {
                fact("Most visited", snapshot.mostVisited.map { "\(WorldGlobeView.flag($0.countryCode)) \($0.name)" } ?? "—")
                fact("Since", firstYear.map(String.init) ?? "—")
                fact("To go", "\(max(0, total - snapshot.countryCount))")
            }
        }
        .padding(18).beenSurface(radius: 24)
    }

    private var highlights: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            if let most = snapshot.mostVisited {
                tile("Most visited", "\(WorldGlobeView.flag(most.countryCode)) \(most.name)", "\(most.visits.count) cities") { onCountry(most) }
            }
            if let latest = snapshot.latest {
                tile("Latest", latest.name, latest.visitedAt.formatted(.dateTime.month(.abbreviated).year())) { onCollection(.timeline) }
            }
            if let pair = snapshot.farthestPair {
                tile("Farthest apart", "\(pair.0.name) – \(pair.1.name)", "\(Int(pair.2 / 1000).formatted()) km") { onCollection(.cities) }
            }
            if let north = snapshot.northernmost, let south = snapshot.southernmost, north.id != south.id {
                tile("North to south", "\(north.name) → \(south.name)", String(format: "%.0f° of latitude", north.latitude - south.latitude)) { onCollection(.cities) }
            }
        }
    }

    private var yearChart: some View {
        let data = snapshot.newCountriesByYear
        let peak = max(1, data.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New countries by year").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Spacer()
                Text("Tap a year to filter").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(BeenPalette.secondary(scheme))
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data, id: \.0) { year, count in
                    let selected = selectedYears.contains(year)
                    Button { onYear(year) } label: {
                        VStack(spacing: 4) {
                            Text(count.formatted()).font(Sketch.text(10, "Bold", relativeTo: .caption2)).monospacedDigit()
                                .opacity(count > 0 ? 1 : 0.4)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected ? BeenPalette.accent(scheme) : BeenPalette.amber.opacity(count > 0 ? 0.55 : 0.18))
                                .frame(height: max(6, CGFloat(count) / CGFloat(peak) * 70))
                            Text("’" + String(year).suffix(2)).font(Sketch.text(10, "SemiBold", relativeTo: .caption2))
                                .foregroundStyle(selected ? BeenPalette.ink(scheme) : BeenPalette.secondary(scheme))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(year): \(count) new countries")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(height: 104, alignment: .bottom)
        }
        .padding(16).beenSurface(radius: 22)
    }

    private var collections: some View {
        VStack(spacing: 0) {
            BeenCollectionRow(title: "Countries", subtitle: snapshot.mostVisited.map { "Most: \($0.name), \($0.visits.count) cities" } ?? "",
                              symbol: "flag", value: snapshot.countryCount.formatted()) { onCollection(.countries) }
            Divider().opacity(0.4)
            BeenCollectionRow(title: "Continents", subtitle: snapshot.continents.map { "\(BeenContinentName.title($0)) \(snapshot.continentCounts[$0] ?? 0)/\(WorldContinentCatalog.count($0))" }.joined(separator: " · "),
                              symbol: "globe.europe.africa", value: "\(snapshot.continents.count)/6") { onCollection(.continents) }
            Divider().opacity(0.4)
            BeenCollectionRow(title: "Cities", subtitle: snapshot.latest.map { "Latest: \($0.name), \($0.visitedAt.formatted(.dateTime.month(.abbreviated).year()))" } ?? "",
                              symbol: "building.2", value: snapshot.visits.count.formatted()) { onCollection(.cities) }
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                shortcut("Timeline", "clock") { onCollection(.timeline) }
                shortcut("Flags", "flag.2.crossed") { onCollection(.flags) }
                shortcut("Milestones", "rosette") { onCollection(.milestones) }
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16).beenSurface(radius: 24, inset: true)
    }

    private var countryList: some View {
        VStack(spacing: 10) {
            ForEach(snapshot.countries.sorted { $0.visits.count > $1.visits.count }) { group in
                BeenCountryRow(group: group) { onCountry(group) }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(BeenPalette.ink(scheme).opacity(0.1)).frame(width: 1, height: 34).padding(.horizontal, 12)
    }
    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Sketch.display(.title2, weight: .bold)).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme))
            Text(caption).font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(BeenPalette.secondary(scheme))
        }
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.6).foregroundStyle(BeenPalette.secondary(scheme))
            Text(value).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func tile(_ title: String, _ value: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.6).foregroundStyle(BeenPalette.accent(scheme))
                Text(value).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading).padding(14).beenSurface(radius: 20)
        }
        .buttonStyle(SketchPressStyle())
    }
    private func shortcut(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
                Text(title).font(Sketch.text(12, "SemiBold", relativeTo: .caption))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(SketchPressStyle())
    }
}

struct ProgressRing: View {
    let value: Double
    let label: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().stroke(BeenPalette.ink(scheme).opacity(0.08), lineWidth: 5)
            Circle().trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(BeenPalette.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(label).font(Sketch.text(13, "Bold", relativeTo: .footnote)).monospacedDigit()
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}

// MARK: - Legend

struct BeenLegend: View {
    let mode: CountryFillMode
    let snapshot: BeenPassportSnapshot
    var compact = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 10) {
            switch mode {
            case .heat:
                Text("1").font(Sketch.text(11, "Bold", relativeTo: .caption2))
                LinearGradient(colors: CountryPalette.heatRamp.map(Color.init), startPoint: .leading, endPoint: .trailing)
                    .frame(width: compact ? 90 : 140, height: 8).clipShape(Capsule())
                Text("\(snapshot.countries.map(\.visits.count).max() ?? 1) cities").font(Sketch.text(11, "Bold", relativeTo: .caption2))
            case .recent:
                Text("Earlier").font(Sketch.text(11, "Bold", relativeTo: .caption2))
                LinearGradient(colors: [Color(CountryPalette.recent).opacity(0.3), Color(CountryPalette.recent)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: compact ? 80 : 130, height: 8).clipShape(Capsule())
                Text("Recent").font(Sketch.text(11, "Bold", relativeTo: .caption2))
            case .continent:
                ForEach(snapshot.continents, id: \.self) { name in
                    HStack(spacing: 4) {
                        Circle().fill(Color(CountryPalette.continent(name))).frame(width: 8, height: 8)
                        Text(BeenContinentName.short(name)).font(Sketch.text(11, "Bold", relativeTo: .caption2))
                    }
                }
            case .visited: EmptyView()
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.1 : 0.5), lineWidth: 0.7))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Continent carousel and icons

struct ContinentCarousel: View {
    let selection: String?
    let counts: [String: Int]
    var onSelect: (String?) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil)
                ForEach(BeenContinentName.all, id: \.self) { chip($0) }
            }
            .padding(.horizontal, 14).padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
    private func chip(_ name: String?) -> some View {
        let selected = selection == name
        let count = name.map { counts[$0] ?? 0 } ?? counts.values.reduce(0, +)
        return Button { onSelect(name) } label: {
            HStack(spacing: 8) {
                ContinentIcon(name: name, size: 26, selected: selected)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.map(BeenContinentName.title) ?? "World").font(Sketch.text(12, "Bold", relativeTo: .caption))
                    Text("\(count) \(count == 1 ? "country" : "countries")").font(Sketch.text(10, relativeTo: .caption2))
                        .foregroundStyle(BeenPalette.secondary(scheme))
                }
            }
            .padding(.leading, 8).padding(.trailing, 12).frame(height: 44)
            .background(Capsule().fill(selected ? BeenPalette.amber.opacity(scheme == .dark ? 0.2 : 0.22) : BeenPalette.ink(scheme).opacity(0.04)))
            .overlay(Capsule().strokeBorder(selected ? BeenPalette.amber.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(SketchPressStyle())
        .accessibilityLabel("\(name.map(BeenContinentName.title) ?? "World"), \(count) countries")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Simplified continent silhouettes drawn from coarse coordinates; the selected
/// one draws its outline in and fills.
struct ContinentIcon: View {
    let name: String?
    var size: CGFloat = 26
    var selected = false
    @State private var drawn: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let color = name.map { Color(CountryPalette.continent($0)) } ?? BeenPalette.amber
        ZStack {
            Circle().fill(color.opacity(selected ? 0.22 : 0.1))
            ContinentShape(name: name).fill(color.opacity(selected ? 0.9 : 0.55)).padding(size * 0.18)
            ContinentShape(name: name).trim(from: 0, to: drawn)
                .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)).padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: selected) { _, isSelected in
            guard isSelected, !reduceMotion else { return }
            drawn = 0
            withAnimation(.easeOut(duration: 0.6)) { drawn = 1 }
        }
    }
}

struct ContinentShape: Shape {
    let name: String?
    func path(in rect: CGRect) -> Path {
        guard let name else { return globe(in: rect) }
        let rings = ContinentOutlines.rings[name] ?? []
        let all = rings.flatMap { $0 }
        guard let minLon = all.map(\.0).min(), let maxLon = all.map(\.0).max(),
              let minLat = all.map(\.1).min(), let maxLat = all.map(\.1).max() else { return Path() }
        let k = cos((minLat + maxLat) / 2 * .pi / 180)
        let w = (maxLon - minLon) * k, h = maxLat - minLat
        let scale = min(rect.width / w, rect.height / h)
        let dx = rect.midX - w * scale / 2, dy = rect.midY - h * scale / 2
        var p = Path()
        for ring in rings {
            for (i, point) in ring.enumerated() {
                let x = dx + (point.0 - minLon) * k * scale, y = dy + (maxLat - point.1) * scale
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            p.closeSubpath()
        }
        return p
    }
    private func globe(in rect: CGRect) -> Path {
        var p = Path(ellipseIn: rect)
        p.addEllipse(in: rect.insetBy(dx: rect.width * 0.28, dy: 0))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

enum ContinentOutlines {
    typealias Ring = [(Double, Double)]
    static let rings: [String: [Ring]] = [
        "Europe": [[(-9.5, 37), (-9, 43), (-2, 43.5), (-4.5, 48.3), (2, 51), (5, 53.5), (8.5, 57), (5, 62), (14, 68), (25, 71), (31, 69.5), (30, 60), (40, 55), (40, 47), (30, 45.5), (28.5, 41), (23.5, 36.5), (20, 40), (16, 38), (12.5, 44), (8.5, 44), (3, 42.5), (-2, 36.8)]],
        "Africa": [[(-17, 21), (-16.5, 13), (-8, 4.5), (5, 4.2), (9.5, 4), (9, -1), (13, -6), (11.8, -17), (18.4, -34.5), (26, -34), (33, -26), (40.5, -15), (40, -5), (51, 11.5), (43, 12), (37.5, 20), (32.5, 31), (20, 32), (10, 37), (-6, 36), (-10, 30)]],
        "Asia": [[(26.5, 40), (36, 36), (35, 30), (43, 13), (52, 16), (57, 25), (67, 24.5), (73, 20), (77, 8), (80.5, 15), (90, 22), (98, 16), (104, 1.5), (109, 12), (108, 21.5), (122, 30.5), (122, 40), (130, 43), (135.5, 48), (142, 53), (150, 60), (170, 63), (180, 68), (140, 72.5), (110, 77), (80, 73), (60, 70), (50, 67), (40, 62), (40, 47), (35, 42)]],
        "North America": [[(-168, 66), (-161, 59), (-150, 61), (-135, 58), (-125, 49), (-124, 40), (-117, 32.5), (-110, 23), (-105.5, 20), (-97, 16), (-88, 15.5), (-83, 9), (-78, 8.5), (-82, 10.5), (-87, 21), (-90.5, 21), (-97.5, 26), (-90, 30), (-82, 25), (-80, 32), (-76, 38), (-70, 42), (-66, 45), (-60, 47), (-56, 52), (-62, 58), (-78, 62.5), (-90, 68), (-110, 68), (-130, 70), (-156, 71.3)]],
        "South America": [[(-77, 8.5), (-72, 12), (-62, 11), (-52, 5), (-35, -6), (-39, -15), (-48, -26), (-57, -35), (-63, -42), (-66, -48), (-69, -52), (-74, -52), (-73.5, -40), (-71.5, -30), (-70.3, -18), (-76, -14), (-81, -5), (-80, 1)]],
        "Oceania": [[(114, -22), (115, -34), (123, -34), (131, -31.5), (138, -35), (144, -38.5), (150, -37.5), (153.5, -28), (146, -19), (142.5, -11), (136.5, -12), (130.5, -11.5), (122, -17)],
                    [(172.5, -34.5), (178.5, -37.7), (174.5, -41.6), (170, -46), (166.5, -46), (172, -41)]],
    ]
}

extension BeenContinentName {
    static func short(_ name: String) -> String {
        switch name { case "North America": "N. Am."; case "South America": "S. Am."; default: title(name) }
    }
}

// MARK: - Shared controls (the map's raised buttons, reused across the app)

struct RaisedIconButton: View {
    let symbol: String
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44).raisedCircle()
        }
        .buttonStyle(SketchPressStyle()).accessibilityLabel(title)
    }
}

/// The map's frosted two-way switch, used wherever a view has two modes.
struct SegmentedPill: View {
    let options: [(id: String, title: String, symbol: String)]
    @Binding var selection: String
    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                let selected = selection == option.id
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { selection = option.id }
                } label: {
                    Label(option.title, systemImage: option.symbol).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                        .padding(.horizontal, 14).frame(height: 36)
                        .foregroundStyle(selected ? Sketch.paper : BeenPalette.secondary(scheme))
                        .background { if selected { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "pill", in: pill) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4).raisedCapsule()
    }
}
