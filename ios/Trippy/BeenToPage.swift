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
    @AppStorage("trippy.native.been.library.heat") private var showHeat = true
    @AppStorage("trippy.native.been.library.cityBorders") private var showCityBorders = true
    @AppStorage("trippy.native.been.library.imagery") private var imagery = false
    @AppStorage("trippy.native.been.library.globe3d") private var terrain = true
    @AppStorage("trippy.native.been.library.view") private var viewMode = "map"
    @AppStorage("trippy.native.been.library.fillMode") private var fillModeRaw = CountryFillMode.visited.rawValue
    @AppStorage(GlobeAppearance.themeKey) private var globeTheme = "auto"
    @AppStorage(GlobeAppearance.accentKey) private var globeAccent = "amber"
    @AppStorage(GlobeAppearance.reliefKey) private var globeRelief = 1
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var all = BeenPassportSnapshot()
    @State private var years: Set<Int> = []
    @State private var continent: String?
    @State private var camera = BeenCameraRequest()
    @State private var globeFocus: CLLocationCoordinate2D?
    @State private var globeFocusID = UUID()
    @State private var globeZoom: Float = 4.9
    @State private var canvasHeight: CGFloat = 800
    @State private var pickedDefaultContinent = false
    /// The passport card under the title: one line closed, view + regions + insights open.
    @State private var passportOpen = false
    /// The country or city under the middle of the map once zoomed in, with its "+" bubble.
    @State private var zoomProbe: ZoomProbe?
    @State private var zoomTarget: ZoomAddTarget?
    /// The place just added: Undo, When (month and year) and, for a country, its cities.
    @State private var lastAdded: VisitedPlace?
    @State private var lastAddedTask: Task<Void, Never>?
    /// The visit whose month and year is being picked on the wheels (the country, or one of its cities).
    @State private var whenTarget: WhenTarget?
    struct WhenTarget: Identifiable { let place: String; let title: String; let slot: Int; let existing: Bool
        var id: String { "\(place):\(slot)" } }
    /// Cities added from the card of the country just added (Undo takes them too).
    @State private var addedAlong: [String] = []
    @State private var drainID: UUID?
    @State private var cardDrag: CGFloat = 0
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
    @State private var heat: BeenHeatOverlay?
    @State private var cityShapes: [BeenCityPolygon] = []
    @State private var cityShapesID = 0
    /// The part of the map in view, rounded, so city outlines load once the map rests.
    @State private var viewKey = ""
    @State private var viewRegion: MKCoordinateRegion?
    @State private var showScan = false
    @State private var cityOutlines = CityOutlineCache()

    enum PanelDetent: CaseIterable { case peek, half, full }

    private var fillMode: CountryFillMode { CountryFillMode(rawValue: fillModeRaw) ?? .visited }
    /// The visits the map and panel show after the year and continent filters.
    private var snapshot: BeenPassportSnapshot {
        BeenPassportSnapshot(all.visits.filter { visit in
            (years.isEmpty || years.contains(visit.year ?? 0))
                && (continent == nil || WorldContinentCatalog.name(for: visit.countryCode) == continent)
        })
    }
    private var geometryKey: String { all.countries.map(\.id).joined(separator: "|") }
    private var styleKey: String {
        "\(snapshot.countries.map { "\($0.id)\($0.visits.count)" }.joined()):\(showFill):\(showOutlines):\(hatching):\(fillModeRaw):\(scheme == .dark)"
    }
    private var filtered: Bool { !years.isEmpty }
    private var heatKey: String {
        "\(showHeat):\(showCities):" + snapshot.cities.map { "\($0.id)\(Int($0.heat * 10))\($0.isLived)" }.joined()
    }
    /// 3D pins standing on the globe: crisp at any zoom, unlike dots painted into the texture.
    private var globePins: GlobeOverlay {
        // Linked cities are joined by arcs, like flight paths.
        GlobeOverlay(pins: showCities ? snapshot.cities.map { GlobeOverlay.Pin(id: $0.id, coordinate: $0.coordinate, style: $0.isLived ? .lived : .city) } : [],
                     routes: showCities ? BeenRoutes(snapshot.cities).links.map { [$0.from, $0.to] } : [],
                     color: UIColor(sketchHex: GlobeAppearance.stored.accent.hex), lift: 0.05)
    }
    static func flag(_ code: String?) -> String {
        guard let code, code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "🌍" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar($0.value + 127397) }))
    }

    var body: some View {
        GeometryReader { geometry in
            let snapshot = self.snapshot
            ZStack(alignment: .top) {
                canvas(snapshot).ignoresSafeArea(.container, edges: .bottom)
                if let added = lastAdded, !passportOpen {
                    VStack { Spacer(); addedBubble(added) }
                        .padding(.horizontal, 16).padding(.bottom, Self.tabBarClearance + 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
                if passportOpen {
                    // Dim the map while the card is open; tapping it closes the card.
                    Color.black.opacity(scheme == .dark ? 0.35 : 0.12).ignoresSafeArea()
                        .onTapGesture { setPassport(false) }
                        .transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 12) {
                    header(snapshot)
                    passportCard(snapshot, maxHeight: geometry.size.height - Self.tabBarClearance - 96)
                    if !passportOpen {
                        HStack { Spacer(); viewToggle.background(Capsule().fill(BeenPalette.base(scheme).opacity(0.85))).modifier(BeenGlassSurface(radius: 20)) }
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    if !passportOpen && lastAdded == nil && fillMode != .visited && showFill && !snapshot.countries.isEmpty {
                        BeenLegend(mode: fillMode, snapshot: snapshot).transition(.opacity)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .padding(.bottom, Self.tabBarClearance)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .onAppear { canvasHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, value in canvasHeight = value }
        }
        .foregroundStyle(BeenPalette.ink(scheme)).background(BeenPalette.base(scheme))
        .sheet(isPresented: $showAdd) { VisitedPlacePicker(onAdd: addVisit) }
        .sheet(item: $whenTarget) { whenSheet($0) }
        #if DEBUG
        // `-TrippyBeenAddedDemo [-TrippyBeenWhenDemo]`: add Italy with two cities and show the bubble (and the wheels).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-TrippyBeenAddedDemo"), let italy = PlaceCatalog.country("IT"),
                  let lat = italy.latitude, let lng = italy.longitude else { return }
            try? await Task.sleep(for: .seconds(1.5))
            var visits = all.visits.filter { $0.countryCode != "IT" }
            var country = VisitedPlace(name: italy.name, countryCode: "IT", latitude: lat, longitude: lng)
            country.kind = .country; country.setWhen(VisitedPlace.month(6, 2024))
            visits.append(country)
            for city in PlaceCatalog.cities(in: "IT").prefix(2) {
                var visit = VisitedPlace(name: city.name, countryCode: "IT", latitude: city.latitude, longitude: city.longitude)
                visit.kind = .city; visit.setWhen(country.when)
                visits.append(visit)
            }
            storage = VisitedPlace.encode(visits)
            showAdded(country); pauseAdded()
            if ProcessInfo.processInfo.arguments.contains("-TrippyBeenWhenDemo") {
                try? await Task.sleep(for: .seconds(1))
                whenTarget = WhenTarget(place: country.id, title: "Italy", slot: 1, existing: false)
            }
        }
        #endif
        .sheet(isPresented: $showFilters) { filterSheet }
        .sheet(isPresented: $showScan) { PhotoScanSheet() }
        .onChange(of: heatKey, initial: true) { _, _ in heat = showHeat && !snapshot.cities.isEmpty ? BeenHeatOverlay(snapshot.cities) : nil }
        .task(id: "\(viewKey):\(showCityBorders):\(heatKey)") { await loadCityOutlines() }
        .task(id: "\(showCityBorders):\(all.cities.count)") { await preloadCityOutlines() }
        .sheet(isPresented: $showShare) { BeenShareSheet(snapshot: snapshot, texture: globeTexture, scopeTitle: scopeTitle) }
        .sheet(item: $collection) { BeenCollectionSheet(collection: $0) }
        .sheet(item: $countryDetail) { WorldCountryVisitsView(group: $0) }
        .sheet(item: $cityDetail) { BeenVisitDetail(place: $0) }
        .sheet(item: $clusterDetail) { BeenClusterCitiesSheet(selection: $0) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TrippyBeenDemoData") { storage = VisitedPlace.encode(Self.demoVisits) }
            #endif
            all = BeenPassportSnapshot(VisitedPlace.decode(storage)); pickDefaultContinent()
            #if DEBUG
            // `-TrippyBeenSheet timeline|badges|add|scan|city`: open a sheet without tapping.
            switch UserDefaults.standard.string(forKey: "TrippyBeenSheet") {
            case "timeline": collection = .timeline
            case "badges": collection = .milestones
            case "cities": collection = .cities
            case "add": showAdd = true
            case "scan": showScan = true
            case "city": cityDetail = all.cities.first { $0.isLived } ?? all.cities.first
            default: break
            }
            // `-TrippyBeenFocus Paris [-TrippyBeenFocusKm 180] [-TrippyBeenAddedCard YES]`: fly to a saved city, optionally with its "added" card.
            if let name = UserDefaults.standard.string(forKey: "TrippyBeenFocus"), let city = all.cities.first(where: { $0.name == name }) {
                let km = max(20, UserDefaults.standard.double(forKey: "TrippyBeenFocusKm"))
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    camera = BeenCameraRequest(latitude: city.latitude, longitude: city.longitude, distance: km * 3000, points: [city.coordinate],
                                               minimumMeters: km * 1000, bottomInset: Self.tabBarClearance)
                    if UserDefaults.standard.bool(forKey: "TrippyBeenAddedCard") { showAdded(city); pauseAdded() }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-TrippyBeenOpen") { passportOpen = true }
            if ProcessInfo.processInfo.arguments.contains("-TrippyBeenAdded"), let country = PlaceCatalog.country("IT"),
               let lat = country.latitude, let lon = country.longitude {
                let place = VisitedPlace(name: country.name, countryCode: "IT", latitude: lat, longitude: lon)
                storage = VisitedPlace.encode(VisitedPlace.adding(place, to: all.visits)); showAdded(place)
            }
            #endif
        }
        .onChange(of: storage) { _, value in all = BeenPassportSnapshot(VisitedPlace.decode(value)); pickDefaultContinent() }
        .onChange(of: addRequestID) { _, id in if id != nil { showAdd = true } }
        .sensoryFeedback(.success, trigger: visitFeedbackID)
        .sensoryFeedback(.selection, trigger: passportOpen)
        .task(id: geometryKey) { await loadGeometries() }
        .task(id: zoomProbe) {
            guard let zoomProbe else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { zoomTarget = nil }; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await ZoomAddTarget.resolve(zoomProbe.center, level: zoomProbe.level)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { zoomTarget = found }
        }
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-TrippyBeenFilters") { try? await Task.sleep(for: .seconds(2)); showFilters = true } }
        #endif
        .onChange(of: styleKey) { _, _ in rebuildShapes() }
        .task(id: "\(styleKey):\(imagery):\(viewMode):\(geometries.count):\(globeTheme):\(globeAccent):\(globeRelief)") { await loadGlobeTexture() }
    }

    private var scopeTitle: String {
        [continent.map(BeenContinentName.title), years.isEmpty ? nil : years.sorted().map { $0 == 0 ? "No date" : String($0) }.joined(separator: ", ")].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Canvas

    @ViewBuilder private func canvas(_ snapshot: BeenPassportSnapshot) -> some View {
        ZStack {
            if viewMode == "globe" {
                ZStack {
                    RadialGradient(colors: [BeenPalette.amber.opacity(scheme == .dark ? 0.16 : 0.12), .clear], center: .center, startRadius: 40, endRadius: 300)
                    BeenGlobe3DView(texture: globeTexture, focus: globeFocus, focusID: globeFocusID, zoom: globeZoom, dark: scheme == .dark, reduceMotion: reduceMotion,
                                    overlay: globePins)
                        .padding(.top, 150).padding(.bottom, Self.tabBarClearance - 20)
                }
                .transition(.opacity)
            } else {
                BeenGlobeMap(visits: showCities ? snapshot.cities : [], dataRevision: snapshot.revision, shapes: shapes, camera: camera,
                             showCities: showCities, imagery: imagery, globe3D: terrain, dark: scheme == .dark, reduceMotion: reduceMotion,
                             onVisit: { cityDetail = $0 }, onCluster: { clusterDetail = BeenClusterSelection(visits: $0) },
                             onRegion: { region in
                                 if zoomProbe != nil { zoomProbe = nil }
                                 viewRegion = region
                                 let key = region.span.latitudeDelta > 9 ? "far"
                                     : "\(Int(region.center.latitude * 4)):\(Int(region.center.longitude * 4)):\(Int(region.span.latitudeDelta * 4))"
                                 if key != viewKey { viewKey = key }
                             },
                             addVisits: all.visits, onAdd: { addZoomed($0) },
                             cityShapes: cityShapes, cityShapesID: cityShapesID, heat: heat,
                             routes: BeenRoutes(showCities ? snapshot.cities : []))
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
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Been to").font(Sketch.display(.title, weight: .bold)).lineLimit(1)
                Text("Countries and cities you’ve visited").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                    .foregroundStyle(BeenPalette.secondary(scheme)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RaisedIconButton(symbol: filtered || fillMode != .visited ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                             title: "Filters and map style") { showFilters = true }
            RaisedIconButton(symbol: "square.and.arrow.up", title: "Share") { showShare = true }
        }
    }

    // MARK: Passport card (drops down from under the title)

    private func passportCard(_ snapshot: BeenPassportSnapshot, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Closed, the card is just the regions; the numbers live on each chip.
            ContinentCarousel(selection: continent, counts: all.continentCounts) { select($0) }
                .padding(.horizontal, -4).padding(.top, 10).padding(.bottom, 2)

            if passportOpen {
                Rectangle().fill(BeenPalette.ink(scheme).opacity(0.08)).frame(height: 0.7).padding(.horizontal, 14)
                VerticalPage {
                    cardSection("Your passport") {
                        BeenInsights(snapshot: snapshot, continent: continent, unavailable: !unavailable.isEmpty,
                                     onCollection: { collection = $0 }, onCountry: { focus(on: $0); countryDetail = $0 },
                                     onYear: { toggleYear($0) }, selectedYears: years, onAdd: { showAdd = true })
                    }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 22)
                }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
            // The handle is part of the card: its own strip, below the chips, in the card's colours.
            Button { setPassport(!passportOpen) } label: {
                HStack(spacing: 6) {
                    Capsule().fill(BeenPalette.ink(scheme).opacity(0.18)).frame(width: 28, height: 4)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                        .rotationEffect(.degrees(passportOpen ? 180 : 0))
                    Capsule().fill(BeenPalette.ink(scheme).opacity(0.18)).frame(width: 28, height: 4)
                }
                .foregroundStyle(BeenPalette.secondary(scheme))
                .frame(maxWidth: .infinity, minHeight: 24).padding(.bottom, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(passportOpen ? "Close passport" : "Open passport")
            .accessibilityValue(snapshot.peekLine(continent: continent))
        }
        .frame(maxHeight: passportOpen ? maxHeight : nil, alignment: .top)
        .background(BeenPalette.base(scheme).opacity(passportOpen ? 0.94 : 0.8), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .modifier(BeenGlassSurface(radius: 26))
        .offset(y: cardDrag)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { cardDrag = passportOpen ? min(0, value.translation.height) * 0.4 : max(0, value.translation.height) * 0.4 }
                }
                .onEnded { value in
                    let pull = value.predictedEndTranslation.height
                    if !passportOpen && pull > 50 { setPassport(true) } else if passportOpen && pull < -50 { setPassport(false) }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { cardDrag = 0 }
                }
        )
    }

    /// Map or globe, as two small icon segments.
    private var viewToggle: some View {
        HStack(spacing: 2) {
            ForEach([("map", "map"), ("globe", "globe")], id: \.0) { mode, symbol in
                let on = viewMode == mode
                Button {
                    TrippyHaptics.selection()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { viewMode = mode }
                } label: {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? BeenPalette.base(scheme) : BeenPalette.secondary(scheme))
                        .frame(width: 36, height: 30)
                        .background(Capsule().fill(on ? BeenPalette.ink(scheme) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == "map" ? "Map" : "Globe").accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(BeenPalette.ink(scheme).opacity(0.06)))
    }

    private func cardSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
            content()
        }
    }

    private func regionTile(_ name: String?) -> some View {
        let selected = continent == name
        let counts = all.continentCounts
        let count = name.map { counts[$0] ?? 0 } ?? counts.values.reduce(0, +)
        return Button { select(name) } label: {
            HStack(spacing: 10) {
                ContinentIcon(name: name, size: 30, selected: selected)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.map(BeenContinentName.title) ?? "World").font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(1)
                    Text("\(count) \(count == 1 ? "country" : "countries")").font(Sketch.text(11, relativeTo: .caption2))
                        .foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(BeenPalette.accent(scheme)) }
            }
            .padding(.horizontal, 10).frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? BeenPalette.amber.opacity(scheme == .dark ? 0.2 : 0.22) : BeenPalette.ink(scheme).opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? BeenPalette.amber.opacity(0.6) : .clear, lineWidth: 1))
            .opacity(count == 0 && name != nil ? 0.55 : 1)
        }
        .buttonStyle(SketchPressStyle())
        .accessibilityLabel("\(name.map(BeenContinentName.title) ?? "World"), \(count) countries")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setPassport(_ open: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.84)) { passportOpen = open }
    }

    // MARK: Panel

    struct Heights { let peek: CGFloat; let half: CGFloat; let full: CGFloat
        func value(_ d: PanelDetent) -> CGFloat { switch d { case .peek: peek; case .half: half; case .full: full } } }
    /// Room the app's floating tab bar takes at the bottom.
    static let tabBarClearance: CGFloat = 78 + LibraryWheel.height
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
                VerticalPage {
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
                    Toggle("City pins", isOn: $showCities).frame(minHeight: 48)
                    Divider()
                    Toggle("Heat: time spent in each city", isOn: $showHeat).frame(minHeight: 48)
                    Divider()
                    Toggle("City borders when zoomed in", isOn: $showCityBorders).frame(minHeight: 48)
                }
                if !all.years.isEmpty || !all.undated.isEmpty {
                    group("When") {
                        FlowLayout(spacing: 8) {
                            chip("Everything", selected: years.isEmpty) { years = [] }
                            // Places saved without a date are their own group.
                            if !all.undated.isEmpty { chip("No date · \(all.undated.count)", selected: years.contains(0)) { toggleYear(0) } }
                            ForEach(all.years, id: \.self) { year in chip(String(year), selected: years.contains(year)) { toggleYear(year) } }
                        }
                        .padding(.vertical, 12)
                    }
                }
                group("Globe colours") { GlobeStylePicker().padding(.vertical, 14) }
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

    private func probe(_ center: CLLocationCoordinate2D, level: ZoomAddTarget.Level?) {
        guard let level else { if zoomProbe != nil { zoomProbe = nil }; return }
        // Round so tiny camera nudges don't re-ask the geocoder.
        let next = ZoomProbe(latitude: (center.latitude * 50).rounded() / 50, longitude: (center.longitude * 50).rounded() / 50, level: level)
        if next != zoomProbe { zoomProbe = next }
    }

    /// The pill adds the place straight away (no camera move); the map redraws from the saved visits.
    private func addZoomed(_ target: ZoomAddTarget) {
        guard !target.isAdded(in: all.visits) else { return }
        storage = VisitedPlace.encode(VisitedPlace.adding(target.place, to: all.visits))
        visitFeedbackID = UUID()
        showAdded(target.place)
    }

    /// How long the card stays once you stop touching it. Everything is saved the moment it is added;
    /// the card only offers Undo and the dates.
    private static let addedSeconds = 6.0

    private func showAdded(_ place: VisitedPlace) {
        if lastAdded?.id != place.id { addedAlong = [] }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { lastAdded = place }
        keepAdded()
    }
    /// Restarts the countdown (any tap on the card counts as still using it).
    private func keepAdded() {
        lastAddedTask?.cancel()
        drainID = UUID()
        lastAddedTask = Task { try? await Task.sleep(for: .seconds(Self.addedSeconds)); guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { lastAdded = nil } }
    }
    private func pauseAdded() { lastAddedTask?.cancel(); drainID = nil }
    private func closeAdded() {
        lastAddedTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { lastAdded = nil }
    }
    private var isCountryVisit: Bool { lastAdded?.isCountry ?? false }

    /// A visit's date by slot: 0 is the first visit, 1… are the further ones.
    private func visitDate(_ id: String, slot: Int) -> VisitSpan? {
        guard let place = all.visits.first(where: { $0.id == id }) else { return nil }
        if slot == 0 { return place.when.map { VisitSpan(start: $0, until: place.until) } }
        return place.extra.flatMap { slot - 1 < $0.count ? $0[slot - 1] : nil }
    }
    /// Sets, adds or (nil) removes a visit's date. Removing the first visit moves the next one up.
    private func setVisit(_ date: Date?, id: String, slot: Int) {
        var visits = all.visits
        guard let index = visits.firstIndex(where: { $0.id == id }) else { return }
        var extra = visits[index].extra ?? []
        if slot == 0 {
            if let date { visits[index].setWhen(date) }
            else if let next = extra.first { visits[index].setWhen(next.start, until: next.until); extra.removeFirst() }
            else { visits[index].setWhen(nil) }
        } else if let date {
            if visits[index].when == nil { visits[index].setWhen(date) }
            else if slot - 1 < extra.count { extra[slot - 1] = VisitSpan(start: date) } else { extra.append(VisitSpan(start: date)) }
        } else if slot - 1 < extra.count { extra.remove(at: slot - 1) }
        visits[index].extra = extra.isEmpty ? nil : extra
        // A country's date also goes to the cities added with it that have none yet.
        if visits[index].isCountry, let date {
            for i in visits.indices where addedAlong.contains(visits[i].id) && visits[i].when == nil { visits[i].setWhen(date) }
        }
        storage = VisitedPlace.encode(visits)
    }

    /// Shown right after adding a place from the map. It is already saved; the card is for second thoughts:
    /// Undo, when you went (as many visits as you like), and for a country its cities. Left alone, it goes away.
    private func addedBubble(_ added: VisitedPlace) -> some View {
        let place = all.visits.first { $0.id == added.id } ?? added
        let cities = place.isCountry ? Array(PlaceCatalog.cities(in: place.countryCode ?? "").prefix(12)) : []
        let dates = [visitDate(place.id, slot: 0)].compactMap { $0 } + (place.extra ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlaceMark(place: place, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).lineLimit(1).minimumScaleFactor(0.8)
                    Label("Saved", systemImage: "checkmark.circle.fill").font(Sketch.text(11, "SemiBold", relativeTo: .caption2))
                        .foregroundStyle(BeenLook.lived).labelStyle(.titleAndIcon)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                Button {
                    TrippyHaptics.selection()
                    let gone = Set([place.id] + addedAlong)
                    storage = VisitedPlace.encode(all.visits.filter { !gone.contains($0.id) })
                    closeAdded()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1).fixedSize()
                        .foregroundStyle(Sketch.coral).padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Capsule().fill(Sketch.coral.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button { closeAdded(); cityDetail = place } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(BeenPalette.ink(scheme))
                        .frame(width: 40, height: 40).background(Circle().fill(BeenPalette.ink(scheme).opacity(0.07)))
                }
                .buttonStyle(.plain).accessibilityLabel("More: lived here, stops and photos")
            }
            // When you went: one chip per visit, and a chip to add the next.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { slot, span in
                        Button {
                            pauseAdded()
                            whenTarget = WhenTarget(place: place.id, title: place.name, slot: slot, existing: true)
                        } label: {
                            Label(span.text, systemImage: "calendar").font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1).fixedSize()
                                .foregroundStyle(.white).padding(.horizontal, 12).frame(minHeight: 38).background(Capsule().fill(Sketch.sage))
                        }
                        .buttonStyle(BubblePressStyle()).accessibilityHint("Change or remove this visit")
                    }
                    Button {
                        pauseAdded()
                        whenTarget = WhenTarget(place: place.id, title: place.name, slot: dates.count, existing: false)
                    } label: {
                        Label(dates.isEmpty ? "When?" : "Another visit", systemImage: "plus").font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1).fixedSize()
                            .foregroundStyle(BeenPalette.ink(scheme)).padding(.horizontal, 12).frame(minHeight: 38)
                            .background(Capsule().strokeBorder(BeenPalette.ink(scheme).opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                    }
                    .buttonStyle(BubblePressStyle())
                    if dates.isEmpty {
                        Text("Optional").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize()
                    }
                }
            }
            .scrollIndicators(.hidden)
            if !cities.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Text("Cities:").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize()
                        ForEach(cities) { city in
                            let visit = all.visits.first { !$0.isCountry && VisitedPlace.normalized($0.name) == VisitedPlace.normalized(city.name) && $0.countryCode?.uppercased() == city.countryCode }
                            Button {
                                TrippyHaptics.selection(); keepAdded()
                                if let visit {
                                    guard addedAlong.contains(visit.id) else { return }
                                    addedAlong.removeAll { $0 == visit.id }
                                    storage = VisitedPlace.encode(all.visits.filter { $0.id != visit.id })
                                } else {
                                    // A new city starts with the country's date, so one date covers the whole trip.
                                    var new = VisitedPlace(name: city.name, countryCode: city.countryCode, latitude: city.latitude, longitude: city.longitude, kind: .city)
                                    new.setWhen(place.when)
                                    addedAlong.append(new.id)
                                    storage = VisitedPlace.encode(VisitedPlace.adding(new, to: all.visits))
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: visit == nil ? "plus" : "checkmark").font(.system(size: 10, weight: .heavy))
                                    Text(city.name).font(Sketch.text(12, "Bold", relativeTo: .caption)).lineLimit(1)
                                }
                                .foregroundStyle(visit != nil ? Color.white : BeenPalette.ink(scheme))
                                .padding(.horizontal, 10).frame(minHeight: 36)
                                .background(Capsule().fill(visit != nil ? Sketch.sage : BeenPalette.ink(scheme).opacity(0.06)))
                            }
                            .buttonStyle(BubblePressStyle())
                            .accessibilityLabel(city.name).accessibilityValue(visit == nil ? "Not added" : "Added")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            // The line runs down while the card waits; touching the card refills it.
            if let drainID { DrainBar(seconds: Self.addedSeconds, tint: BeenPalette.ink(scheme)).id(drainID) }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(BeenPalette.ink(scheme).opacity(0.08), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .frame(maxWidth: 560)
        .simultaneousGesture(TapGesture().onEnded { if whenTarget == nil { keepAdded() } })
    }

    /// Month and year for one visit. Saving closes it and the card's countdown starts again.
    private func whenSheet(_ target: WhenTarget) -> some View {
        VisitMonthSheet(title: target.existing ? "Change this visit to \(target.title)" : "When did you go to \(target.title)?",
                        initial: visitDate(target.place, slot: target.slot)?.start, removable: target.existing) { date in
            setVisit(date, id: target.place, slot: target.slot)
            TrippyHaptics.selection()
            whenTarget = nil
        }
        .onDisappear { if lastAdded != nil { keepAdded() } }
    }

    /// When every visit is in one continent, open on that continent rather than the empty world.
    private func pickDefaultContinent() {
        // Only when the page opens: adding your first city must not swing the map out to its continent.
        guard !pickedDefaultContinent else { return }
        pickedDefaultContinent = true
        guard continent == nil, !all.visits.isEmpty else { return }
        let continents = Set(all.visits.map { WorldContinentCatalog.name(for: $0.countryCode) })
        guard continents.count == 1, let only = continents.first, only != "Other" else { return }
        select(only, openPanel: false)
    }

    /// Height the panel and tab bar cover for a detent, so the camera frames what stays visible.
    private func coveredHeight(_ value: PanelDetent) -> CGFloat { Self.tabBarClearance }

    private func select(_ value: String?, openPanel: Bool = true) {
        continent = value
        let target = detent
        if openPanel { setPassport(false) }   // picking a region closes the card so the map can show it
        let center = value.map(BeenContinentName.center) ?? CLLocationCoordinate2D(latitude: 25, longitude: 15)
        let points = value == nil ? [] : all.visits.filter { WorldContinentCatalog.name(for: $0.countryCode) == value }.map(\.coordinate)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
            camera = BeenCameraRequest(latitude: center.latitude, longitude: center.longitude, distance: value == nil ? 78_000_000 : 16_000_000,
                                       points: points, minimumMeters: 1_500_000, bottomInset: coveredHeight(target))
        }
        globeFocus = points.isEmpty ? center : Self.middle(points); globeZoom = value == nil ? 4.9 : 3.4; globeFocusID = UUID()

    }

    private func focus(on group: VisitedCountryGroup) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) {
            camera = BeenCameraRequest(latitude: group.coordinate.latitude, longitude: group.coordinate.longitude, distance: 2_600_000,
                                       points: group.visits.map(\.coordinate), minimumMeters: 400_000, bottomInset: coveredHeight(detent))
        }
        globeFocus = Self.middle(group.visits.map(\.coordinate)); globeZoom = 2.9; globeFocusID = UUID()
    }

    /// Centre of several places, averaging longitudes the short way round.
    private static func middle(_ points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard let first = points.first else { return .init(latitude: 25, longitude: 15) }
        let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let longitude = points.map { first.longitude + (($0.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180) }.reduce(0, +) / Double(points.count)
        return .init(latitude: latitude, longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    private func addVisit(_ place: VisitedPlace) {
        // The add sheet has already saved it; fly to it.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.65)) {
            camera = BeenCameraRequest(latitude: place.latitude, longitude: place.longitude, distance: 1_800_000,
                                       points: [place.coordinate], minimumMeters: 60_000, bottomInset: coveredHeight(detent))
        }
        globeFocus = place.coordinate; globeZoom = 2.5; globeFocusID = UUID()
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
        // Countries colour straight from the bundled outlines, before any boundary has downloaded.
        let codes = showFill ? Set(snapshot.countries.compactMap { $0.countryCode?.uppercased() }) : []
        // Share cards paint the cities into the picture; the live globe stands real pins on it instead.
        let image = await GlobeTextureBuilder.shared.texture(key: key, shapes: shapes, visits: showShare && showCities ? snapshot.cities : [], visitedCodes: codes)
        guard !Task.isCancelled else { return }
        globeTexture = image
    }
}

/// City outlines already fetched this session, by place.
final class CityOutlineCache {
    var rings: [String: [[CLLocationCoordinate2D]]] = [:]
}

extension WorldGlobeView {
    /// Outlines for the visited cities in view once zoomed in to about a region. Each is fetched once
    /// (geoBoundaries, by country) and then kept on the phone.
    @MainActor func loadCityOutlines() async {
        guard showCityBorders, showCities, viewMode == "map", viewKey != "far", !viewKey.isEmpty, let region = viewRegion else {
            if !cityShapes.isEmpty { cityShapes = []; cityShapesID += 1 }
            return
        }
        let inView = Array(snapshot.cities.filter {
            abs($0.latitude - region.center.latitude) < region.span.latitudeDelta * 0.8 && abs($0.longitude - region.center.longitude) < region.span.longitudeDelta * 0.8
        }.sorted { $0.heat > $1.heat }.prefix(14))
        func show() {
            var polygons: [BeenCityPolygon] = []
            for city in inView { for ring in cityOutlines.rings[city.id] ?? [] {
                let polygon = BeenCityPolygon(coordinates: ring, count: ring.count)
                polygon.heat = city.heat; polygon.lived = city.isLived
                polygons.append(polygon)
            } }
            cityShapes = polygons; cityShapesID += 1
        }
        // What is already known shows at once; the rest arrive one by one as they load.
        show()
        for city in inView where cityOutlines.rings[city.id] == nil {
            await fetchOutline(city)
            guard !Task.isCancelled else { return }
            show()
        }
    }

    @MainActor func fetchOutline(_ city: VisitedPlace) async {
        guard cityOutlines.rings[city.id] == nil, let code = city.countryCode else { return }
        let lines = try? await GeoBoundaryRepository.shared.boundary(countryISO2: code, countryNames: [], placeNames: [city.name], levelID: "city",
                                                                       center: .init(latitude: city.latitude, longitude: city.longitude), requireNameMatch: true)
        guard !Task.isCancelled else { return }
        cityOutlines.rings[city.id] = (lines ?? []).filter { $0.style == .outline && $0.points.count >= 4 }.map { line in
            (line.points.count > 500 ? GeoBoundaryRepository.simplify(line.points, maximumPoints: 500) : line.points).map(\.coordinate)
        }
    }

    /// Fetches outlines for your cities ahead of time (the ones with most time first), so they are
    /// there by the time you zoom in. Saved on the phone after the first fetch.
    @MainActor func preloadCityOutlines() async {
        guard showCityBorders else { return }
        try? await Task.sleep(for: .seconds(2))
        for city in all.cities.sorted(by: { $0.heat > $1.heat }).prefix(40) {
            guard !Task.isCancelled else { return }
            await fetchOutline(city)
        }
        if viewKey != "far" { await loadCityOutlines() }
    }

    #if DEBUG
    /// A passport that shows every kind of place: countries, dated and undated cities, repeat trips and two homes.
    static var demoVisits: [VisitedPlace] {
        func city(_ name: String, _ code: String, _ lat: Double, _ lon: Double, _ month: Int? = nil, _ year: Int? = nil, days: Int? = nil, trips: Int? = nil) -> VisitedPlace {
            var p = VisitedPlace(name: name, countryCode: code, latitude: lat, longitude: lon, kind: .city, dated: false, days: days, trips: trips)
            if let month, let year { p.setWhen(VisitedPlace.month(month, year)) }
            return p
        }
        var athens = city("Athens", "GR", 37.98, 23.73); athens.lived = true
        athens.setWhen(VisitedPlace.month(9, 2015), ongoing: true)
        var berlin = city("Berlin", "DE", 52.52, 13.40); berlin.lived = true
        berlin.setWhen(VisitedPlace.month(3, 2021), until: VisitedPlace.month(11, 2021))
        var france = VisitedPlace(name: "France", countryCode: "FR", latitude: 48.86, longitude: 2.35, kind: .country, dated: false)
        france.setWhen(VisitedPlace.month(9, 2022))
        let norway = VisitedPlace(name: "Norway", countryCode: "NO", latitude: 59.91, longitude: 10.75, kind: .country, dated: false)
        var paris = city("Paris", "FR", 48.86, 2.35, 9, 2022, days: 7), lyon = city("Lyon", "FR", 45.76, 4.84, 9, 2022, days: 2)
        paris.extra = [VisitSpan(start: VisitedPlace.month(5, 2019) ?? .now)]
        paris.stops = [PlaceStop(name: "Lyon", latitude: 45.76, longitude: 4.84, cityID: lyon.id),
                       PlaceStop(name: "Versailles", latitude: 48.80, longitude: 2.12), PlaceStop(name: "Giverny", latitude: 49.08, longitude: 1.53),
                       PlaceStop(name: "Fontainebleau", latitude: 48.40, longitude: 2.70)]
        lyon.stops = [PlaceStop(name: "Paris", latitude: 48.86, longitude: 2.35, cityID: paris.id)]
        return [athens, berlin, france, norway, paris, lyon,
                city("Sofia", "BG", 42.70, 23.32, 4, 2019, days: 26, trips: 7), city("Thessaloniki", "GR", 40.64, 22.94, 7, 2020, days: 9, trips: 4),
                city("Rome", "IT", 41.90, 12.50, 6, 2023, days: 4), city("Milan", "IT", 45.46, 9.19), city("Tromsø", "NO", 69.65, 18.96, 2, 2024, days: 5),
                city("Lisbon", "PT", 38.72, -9.14, 5, 2018, days: 5), city("Istanbul", "TR", 41.01, 28.98, 10, 2017, days: 3, trips: 2),
                city("Tokyo", "JP", 35.68, 139.69, 4, 2024, days: 12), city("Kyoto", "JP", 35.01, 135.77, 4, 2024, days: 4),
                city("New York", "US", 40.71, -74.01, 12, 2016, days: 8), city("Cape Town", "ZA", -33.92, 18.42), city("Belgrade", "RS", 44.79, 20.45)]
    }
    #endif
}

// MARK: - Snapshot insights

extension BeenPassportSnapshot {
    static let worldCountries = 195

    var continentCounts: [String: Int] {
        Dictionary(grouping: countries, by: { WorldContinentCatalog.name(for: $0.countryCode) }).mapValues(\.count)
    }
    var countryStats: [String: CountryVisitStats] {
        Dictionary(uniqueKeysWithValues: countries.compactMap { group in
            group.countryCode.map { ($0, CountryVisitStats(code: $0, continent: WorldContinentCatalog.name(for: $0), cities: group.cities.count,
                                                            lastVisit: group.visits.compactMap(\.when).max() ?? group.visits.map(\.visitedAt).max() ?? .now)) }
        })
    }
    func peekLine(continent: String?) -> String {
        if let continent {
            let total = WorldContinentCatalog.count(continent)
            // The continent's name is already the card's title.
            return "\(countryCount) of \(total) countries · \(cities.count) \(cities.count == 1 ? "city" : "cities")"
        }
        let percent = Int((Double(countryCount) / Double(Self.worldCountries) * 100).rounded())
        return "\(countryCount) countries · \(percent)% of the world · \(cities.count) cities"
    }
    var mostVisited: VisitedCountryGroup? { countries.max { $0.cities.count < $1.cities.count } }
    var latest: VisitedPlace? { visits.first { $0.when != nil } }
    var northernmost: VisitedPlace? { cities.max { $0.latitude < $1.latitude } }
    var southernmost: VisitedPlace? { cities.min { $0.latitude < $1.latitude } }
    /// The two visited cities farthest apart (great-circle).
    var farthestPair: (VisitedPlace, VisitedPlace, Double)? {
        let sample = Array(cities.prefix(300))
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
            guard let year = visit.year else { continue }
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
    @AppStorage(BeenStayStore.key) private var stayStorage = "[]"
    @State private var showScan = false

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
                photosRow
            }
            Text(unavailable ? "Some outlines couldn’t load. Your visits are saved." : "Outlines: geoBoundaries · Map: Apple")
                .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal, 4)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 28)
        .sheet(isPresented: $showScan) { PhotoScanSheet() }
    }

    private var photosRow: some View {
        Button { showScan = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 18, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
                    .frame(width: 40, height: 40).beenSurface(radius: 14, inset: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find places from my photos").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                    Label("Private. Nothing leaves this iPhone.", systemImage: "lock.fill").font(Sketch.text(11, relativeTo: .caption2))
                        .foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(BeenPalette.secondary(scheme))
            }
            .padding(14).beenSurface(radius: 22)
        }
        .buttonStyle(SketchPressStyle())
    }

    private var worldSummary: some View {
        let share = Double(snapshot.countryCount) / Double(BeenPassportSnapshot.worldCountries)
        return HStack(spacing: 0) {
            metric(snapshot.countryCount.formatted(), "of 195 countries")
            divider
            metric(snapshot.cities.count.formatted(), "cities")
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
        let firstYear = snapshot.visits.compactMap(\.year).min()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ContinentIcon(name: continent, size: 40, selected: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BeenContinentName.title(continent)).font(Sketch.display(.title2, weight: .bold))
                    Text("\(snapshot.countryCount) of \(total) countries · \(snapshot.cities.count) cities")
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

    /// The six most telling facts; the rest are under Stats & timeline.
    private var highlights: some View {
        BeenFactGrid(facts: Array(BeenFacts.all(snapshot, stays: BeenStayStore.decode(stayStorage)).prefix(6)))
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
            BeenCollectionRow(title: "Countries", subtitle: snapshot.mostVisited.map { "Most: \($0.name), \($0.cities.count) cities" } ?? "",
                              symbol: "flag", value: snapshot.countryCount.formatted()) { onCollection(.countries) }
            Divider().opacity(0.4)
            BeenCollectionRow(title: "Continents", subtitle: snapshot.continents.map { "\(BeenContinentName.title($0)) \(snapshot.continentCounts[$0] ?? 0)/\(WorldContinentCatalog.count($0))" }.joined(separator: " · "),
                              symbol: "globe.europe.africa", value: "\(snapshot.continents.count)/6") { onCollection(.continents) }
            Divider().opacity(0.4)
            BeenCollectionRow(title: "Cities", subtitle: snapshot.latest.map { "Latest: \($0.name), \($0.whenText)" } ?? "",
                              symbol: "building.2", value: snapshot.cities.count.formatted()) { onCollection(.cities) }
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                shortcut("Stats & timeline", "chart.bar.xaxis") { onCollection(.timeline) }
                shortcut("Flags", "flag.2.crossed") { onCollection(.flags) }
                shortcut("Badges", "rosette") { onCollection(.milestones) }
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16).beenSurface(radius: 24, inset: true)
    }

    private var countryList: some View {
        VStack(spacing: 10) {
            ForEach(snapshot.countries.sorted { $0.cities.count > $1.cities.count }) { group in
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
                Text("\(snapshot.countries.map(\.cities.count).max() ?? 1) cities").font(Sketch.text(11, "Bold", relativeTo: .caption2))
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


// MARK: - Added card pieces

/// A thin line that empties over `seconds`: how long the card will stay.
struct DrainBar: View {
    let seconds: Double
    let tint: Color
    @State private var full = true
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(tint.opacity(0.28)).frame(width: full ? proxy.size.width : 0)
        }
        .frame(height: 3).background(Capsule().fill(tint.opacity(0.07)))
        .onAppear { withAnimation(.linear(duration: seconds)) { full = false } }
        .accessibilityHidden(true)
    }
}

/// Month and year wheels for one visit.
struct VisitMonthSheet: View {
    let title: String
    let initial: Date?
    var removable = false
    var onDone: (Date?) -> Void
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    private let thisYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(title).font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { onDone(min(VisitedPlace.month(month, year) ?? .now, PlaceDraft.thisMonth)) } label: {
                    Label("Save", systemImage: "checkmark").font(Sketch.text(15, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.paper)
                        .padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(Sketch.ink))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                Picker("Month", selection: $month) { ForEach(1...12, id: \.self) { Text(Calendar.current.standaloneMonthSymbols[$0 - 1]).tag($0) } }
                Picker("Year", selection: $year) { ForEach(Array(stride(from: thisYear, through: thisYear - 90, by: -1)), id: \.self) { Text(String($0)).tag($0) } }
                    .frame(maxWidth: 130)
            }
            .pickerStyle(.wheel).frame(height: 150)
            if removable {
                Button(role: .destructive) { onDone(nil) } label: {
                    Label("Remove this visit", systemImage: "calendar.badge.minus").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(Sketch.coral).background(Capsule().fill(Sketch.coral.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
        .presentationDetents([.height(removable ? 340 : 280)]).presentationDragIndicator(.visible).presentationBackground(Sketch.paper)
        .onAppear {
            if let initial { month = Calendar.current.component(.month, from: initial); year = Calendar.current.component(.year, from: initial) }
        }
    }
}
