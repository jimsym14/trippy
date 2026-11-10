import SwiftUI
import MapKit
import PhotosUI

// Adding and editing a place on Been to.
//
// One sheet does it all: type a country or a city (answers come from the bundled list, so they appear as you type),
// say whether you visited or lived there, and optionally when. Nothing is dated unless you pick a date.

// MARK: - When

/// "Been there / lived there" and the optional dates, before they are written to a place.
struct PlaceDraft: Equatable {
    enum Mode: String, CaseIterable { case none, month, range }
    var lived = false
    var mode = Mode.none
    var from = PlaceDraft.thisMonth
    var to = PlaceDraft.thisMonth
    var ongoing = false

    static var thisMonth: Date {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return VisitedPlace.month(parts.month ?? 1, parts.year ?? 2025) ?? .now
    }

    init() {}
    init(_ place: VisitedPlace) {
        lived = place.isLived
        if let start = place.when {
            from = start
            ongoing = place.ongoing == true
            to = place.until ?? start
            mode = ongoing || place.until != nil ? .range : .month
        }
    }

    func apply(to place: inout VisitedPlace) {
        place.lived = lived ? true : nil
        switch mode {
        case .none: place.setWhen(nil)
        case .month: place.setWhen(from)
        case .range: place.setWhen(from, until: max(from, to), ongoing: ongoing)
        }
    }

    /// "Lived there · Jun 2019 – Aug 2021"
    var summary: String {
        var probe = VisitedPlace(name: "x", countryCode: nil, latitude: 0, longitude: 0)
        apply(to: &probe)
        return probe.whenText
    }
}

/// Month and year as two small menus: quicker than wheels, and two of them fit on one line for a range.
struct MonthYearMenu: View {
    @Binding var date: Date
    @Environment(\.colorScheme) private var scheme
    private var month: Int { Calendar.current.component(.month, from: date) }
    private var year: Int { Calendar.current.component(.year, from: date) }
    private let thisYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        HStack(spacing: 6) {
            Picker("Month", selection: Binding(get: { month }, set: { set($0, year) })) {
                ForEach(1...12, id: \.self) { Text(Calendar.current.shortStandaloneMonthSymbols[$0 - 1]).tag($0) }
            }
            Picker("Year", selection: Binding(get: { year }, set: { set(month, $0) })) {
                ForEach(Array(stride(from: thisYear, through: thisYear - 90, by: -1)), id: \.self) { Text(String($0)).tag($0) }
            }
        }
        .pickerStyle(.menu).labelsHidden().tint(BeenPalette.ink(scheme))
        .padding(.horizontal, 2).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(BeenPalette.ink(scheme).opacity(0.06)))
    }
    private func set(_ month: Int, _ year: Int) {
        // Never later than this month.
        date = min(VisitedPlace.month(month, year) ?? date, PlaceDraft.thisMonth)
    }
}

struct PlaceWhenEditor: View {
    @Binding var draft: PlaceDraft
    var isCountry = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                kind("Been there", "mappin.and.ellipse", selected: !draft.lived, tint: BeenPalette.amber) { draft.lived = false; draft.ongoing = false }
                kind("Lived there", "house.fill", selected: draft.lived, tint: BeenLook.lived) {
                    draft.lived = true
                    if draft.mode == .month { draft.mode = .range }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("WHEN").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                HStack(spacing: 6) {
                    chip("No date", .none)
                    if !draft.lived { chip("A month", .month) }
                    chip(draft.lived ? "From – to" : "A range", .range)
                }
                switch draft.mode {
                case .none:
                    Text(draft.lived ? "Saved as a place you lived, with no dates." : "Saved without a date. You can add one any time.")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                case .month:
                    MonthYearMenu(date: $draft.from)
                case .range:
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { rangeFields }
                        VStack(alignment: .leading, spacing: 8) { rangeFields }
                    }
                    if draft.lived {
                        Toggle("I still live here", isOn: $draft.ongoing.animation(.snappy))
                            .font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).tint(BeenLook.lived).frame(minHeight: 44)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: draft.mode)
        .animation(.snappy(duration: 0.22), value: draft.lived)
    }

    @ViewBuilder private var rangeFields: some View {
        MonthYearMenu(date: $draft.from)
        if !draft.ongoing {
            Text("to").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
            MonthYearMenu(date: Binding(get: { max(draft.to, draft.from) }, set: { draft.to = max($0, draft.from) }))
        } else {
            Text("until today").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
        }
    }

    private func kind(_ title: String, _ symbol: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button { TrippyHaptics.selection(); action() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? BeenPalette.ink(scheme) : BeenPalette.secondary(scheme))
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(selected ? tint.opacity(scheme == .dark ? 0.3 : 0.24) : BeenPalette.ink(scheme).opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(selected ? tint : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chip(_ title: String, _ mode: PlaceDraft.Mode) -> some View {
        let selected = draft.mode == mode
        return Button { TrippyHaptics.selection(); draft.mode = mode } label: {
            Text(title).font(Sketch.text(13, "Bold", relativeTo: .footnote)).padding(.horizontal, 14).frame(minHeight: 38)
                .foregroundStyle(selected ? BeenPalette.base(scheme) : BeenPalette.ink(scheme))
                .background(Capsule().fill(selected ? BeenPalette.ink(scheme) : BeenPalette.ink(scheme).opacity(0.06)))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Add sheet

struct VisitedPlacePicker: View {
    var initialQuery = ""
    /// Called with the main place after it is saved, so the map can fly there.
    var onAdd: ((VisitedPlace) -> Void)? = nil
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var picked: VisitedPlace?
    @State private var draft = PlaceDraft()
    @State private var cities: Set<String> = []
    @State private var remote: [VisitedPlace] = []
    @State private var searching = false
    @State private var addedNow: [VisitedPlace] = []
    @State private var showScan = false
    @State private var savedTick = 0

    private var term: String { VisitedPlace.normalized(query) }
    private var saved: [VisitedPlace] { VisitedPlace.decode(storage) }

    /// Countries and cities from the bundled list. Names that start with what you typed come first.
    private var local: (countries: [VisitedPlace], cities: [VisitedPlace]) {
        guard term.count >= 2 else { return ([], []) }
        func rank(_ name: String) -> Int? {
            let n = VisitedPlace.normalized(name)
            return n.hasPrefix(term) ? 0 : n.contains(" " + term) ? 1 : n.contains(term) && term.count >= 4 ? 2 : nil
        }
        let countries = PlaceCatalog.countries.compactMap { c -> (Int, VisitedPlace)? in
            guard let r = rank(c.name), let lat = c.latitude, let lon = c.longitude else { return nil }
            return (r, VisitedPlace(name: c.name, countryCode: c.code, latitude: lat, longitude: lon, kind: .country, dated: false))
        }.sorted { $0.0 < $1.0 }.prefix(5).map(\.1)
        let cities = PlaceCatalog.cities.compactMap { c -> (Int, VisitedPlace)? in
            guard let r = rank(c.name) else { return nil }
            return (r, VisitedPlace(name: c.name, countryCode: c.countryCode, latitude: c.latitude, longitude: c.longitude, kind: .city, dated: false))
        }.sorted { $0.0 < $1.0 }.prefix(20).map(\.1)
        return (Array(countries), Array(cities))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(picked.map { p in (saved.contains { $0.id == p.id } ? "Edit " : "Add ") + p.name } ?? "Add a place")
                        .font(.custom("PlusJakartaSans-Bold", size: 30, relativeTo: .title)).tracking(-1).fixedSize(horizontal: false, vertical: true)
                    if let picked {
                        setup(picked).transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        BeenVisitSearchField(query: $query, focused: $searchFocused, loading: searching)
                        results.transition(.opacity)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 30).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
            .background(BeenPalette.base(scheme).ignoresSafeArea()).foregroundStyle(BeenPalette.ink(scheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if picked != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Back") { withAnimation(.snappy) { picked = nil }; searchFocused = true } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .tint(BeenPalette.accent(scheme)).presentationDetents([.large]).presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: savedTick)
        .sheet(isPresented: $showScan) { PhotoScanSheet() }
        .onAppear {
            query = initialQuery
            #if DEBUG
            // `-TrippyBeenAddDemo France`: open the setup card for a country without tapping.
            if let name = UserDefaults.standard.string(forKey: "TrippyBeenAddDemo"), picked == nil {
                query = name
                if let first = local.countries.first ?? local.cities.first { choose(first) }
                if UserDefaults.standard.bool(forKey: "TrippyBeenAddLived") { draft.lived = true; draft.mode = .range }
                return
            }
            #endif
            searchFocused = true
        }
        .task(id: term) {
            remote = []
            // Only ask Apple when the bundled list has little to offer.
            guard term.count >= 3, local.cities.count < 4 else { searching = false; return }
            searching = true
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await searchApple(query)
        }
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let found = local
        if term.count < 2 {
            if !addedNow.isEmpty {
                section("Added just now") {
                    ForEach(addedNow) { place in row(place, trailing: "pencil") { choose(place) } }
                }
            } else {
                Text("Type a country to add it with its cities in one go, or a city on its own.")
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal, 4)
            }
            photosEntry
        } else if found.countries.isEmpty && found.cities.isEmpty && remote.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searching ? "magnifyingglass" : "map").font(.system(size: 28, weight: .light)).foregroundStyle(BeenPalette.accent(scheme))
                Text(searching ? "Looking further…" : "Nothing found for “\(query)”.").font(.subheadline.weight(.medium))
                if !searching { Text("Check the spelling, or add the country instead.").font(.caption).foregroundStyle(BeenPalette.secondary(scheme)) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            if !found.countries.isEmpty { section("Countries") { ForEach(found.countries) { place in row(place) { choose(place) } } } }
            if !found.cities.isEmpty { section("Cities") { ForEach(found.cities) { place in row(place) { choose(place) } } } }
            if !remote.isEmpty { section("More places") { ForEach(remote) { place in row(place) { choose(place) } } } }
        }
    }

    private var photosEntry: some View {
        Button { showScan = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 20, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
                    .frame(width: 46, height: 46).beenSurface(radius: 16, inset: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find places from my photos").font(Sketch.text(15, "Bold", relativeTo: .subheadline))
                    Label("Private. Nothing leaves this iPhone.", systemImage: "lock.fill")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(BeenPalette.secondary(scheme))
            }
            .padding(14).beenSurface(radius: 22)
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme)).padding(.leading, 4)
            VStack(spacing: 8, content: content)
        }
    }

    private func row(_ place: VisitedPlace, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        let existing = saved.first { $0.id == place.id }
        return Button(action: action) {
            HStack(spacing: 12) {
                PlaceMark(place: existing ?? place, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(Sketch.text(16, "Bold", relativeTo: .body)).multilineTextAlignment(.leading)
                    Text(place.isCountry ? "Country" : Locale(identifier: "en").localizedString(forRegionCode: place.countryCode ?? "") ?? "City")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 6)
                if let existing {
                    Text(existing.whenText == "No date" ? "Added" : existing.whenText).font(Sketch.text(11, "Bold", relativeTo: .caption2))
                        .foregroundStyle(BeenPalette.secondary(scheme))
                }
                Image(systemName: trailing ?? (existing == nil ? "plus" : "pencil")).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BeenPalette.accent(scheme)).frame(width: 34, height: 34)
                    .background(Circle().fill(BeenPalette.amber.opacity(0.16)))
            }
            .padding(.horizontal, 12).frame(minHeight: 64).beenSurface(radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(place.name), \(place.isCountry ? "country" : "city")\(existing == nil ? "" : ", already added")")
    }

    // MARK: Setup card

    private func setup(_ place: VisitedPlace) -> some View {
        let options = place.isCountry ? Array(PlaceCatalog.cities(in: place.countryCode ?? "").filter { !$0.name.contains(where: \.isNumber) }.prefix(16)) : []
        let already = Set(saved.filter { !$0.isCountry && $0.countryCode?.uppercased() == place.countryCode?.uppercased() }.map { VisitedPlace.normalized($0.name) })
        let editing = saved.contains { $0.id == place.id }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PlaceMark(place: place, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.isCountry ? "Country" : Locale(identifier: "en").localizedString(forRegionCode: place.countryCode ?? "") ?? "City")
                        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                    Text(place.isCountry ? "Fills the whole country on the map" : "Shows as a pin on the map")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
            }
            PlaceWhenEditor(draft: $draft, isCountry: place.isCountry).padding(16).beenSurface(radius: 22)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WHICH CITIES?").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                    FlowLayout(spacing: 7) {
                        ForEach(options) { city in
                            let key = VisitedPlace.normalized(city.name)
                            let had = already.contains(key), on = had || cities.contains(key)
                            Button {
                                TrippyHaptics.selection()
                                if cities.contains(key) { cities.remove(key) } else { cities.insert(key) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: on ? "checkmark" : "plus").font(.system(size: 10, weight: .heavy))
                                    Text(city.name).font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1)
                                }
                                .padding(.horizontal, 12).frame(minHeight: 38)
                                .foregroundStyle(had ? BeenPalette.secondary(scheme) : on ? Color.white : BeenPalette.ink(scheme))
                                .background(Capsule().fill(had ? Sketch.sage.opacity(0.22) : on ? Sketch.sage : BeenPalette.ink(scheme).opacity(0.06)))
                            }
                            .buttonStyle(.plain).disabled(had)
                            .accessibilityLabel(city.name).accessibilityValue(had ? "Already added" : on ? "Selected" : "Not selected")
                        }
                    }
                    Text("Optional. They get the same date. Search for any city that isn’t listed.")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                .padding(16).beenSurface(radius: 22)
            }
            if editing, place.when != nil, draft.mode != .none, !place.isLived {
                Button { addVisit(place) } label: {
                    Label("Add as another visit", systemImage: "plus.circle").font(Sketch.text(15, "Bold", relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(BeenPalette.accent(scheme))
                        .background(Capsule().strokeBorder(BeenPalette.accent(scheme).opacity(0.6), lineWidth: 1.5))
                }.buttonStyle(.plain)
            }
            Button { save(place, options: options) } label: {
                Text(buttonTitle(place, editing: editing)).font(Sketch.text(16, "Bold", relativeTo: .headline))
                    .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(BeenPalette.base(scheme))
                    .background(Capsule().fill(BeenPalette.ink(scheme)))
            }
            .buttonStyle(SketchPressStyle())
        }
    }

    private func buttonTitle(_ place: VisitedPlace, editing: Bool) -> String {
        let extra = cities.isEmpty ? "" : " and \(cities.count) \(cities.count == 1 ? "city" : "cities")"
        return "\(editing ? "Save" : "Add") \(place.name)\(extra)"
    }

    private func choose(_ place: VisitedPlace) {
        searchFocused = false
        let existing = saved.first { $0.id == place.id }
        draft = existing.map(PlaceDraft.init) ?? PlaceDraft()
        cities = []
        withAnimation(.snappy) { picked = existing ?? place }
    }

    /// Keeps the dates already saved and records this one as a further visit.
    private func addVisit(_ place: VisitedPlace) {
        var records = saved
        guard let index = records.firstIndex(where: { $0.id == place.id }) else { return }
        var probe = place; draft.apply(to: &probe)
        guard let start = probe.when else { return }
        records[index].extra = (records[index].extra ?? []) + [VisitSpan(start: start, until: probe.end)]
        storage = VisitedPlace.encode(records)
        savedTick += 1; query = ""
        withAnimation(.snappy) { picked = nil }
    }

    private func save(_ place: VisitedPlace, options: [CityEntry]) {
        var records = saved
        var main = place
        draft.apply(to: &main)
        records = VisitedPlace.saving(main, in: records)
        for city in options where cities.contains(VisitedPlace.normalized(city.name)) {
            var visit = VisitedPlace(name: city.name, countryCode: city.countryCode, latitude: city.latitude, longitude: city.longitude, kind: .city)
            draft.apply(to: &visit)
            records = VisitedPlace.saving(visit, in: records)
        }
        storage = VisitedPlace.encode(records)
        addedNow.removeAll { $0.id == main.id }
        addedNow.insert(main, at: 0)
        savedTick += 1
        onAdd?(main)
        query = ""
        withAnimation(.snappy) { picked = nil }
    }

    @MainActor private func searchApple(_ text: String) async {
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text; request.resultTypes = .address
        defer { searching = false }
        guard let response = try? await MKLocalSearch(request: request).start(), !Task.isCancelled else { return }
        var seen = Set(local.cities.map(\.id))
        remote = response.mapItems.compactMap { item in
            let mark = item.placemark
            guard let name = mark.locality ?? mark.subAdministrativeArea ?? item.name else { return nil }
            let place = VisitedPlace(name: name, countryCode: mark.isoCountryCode, latitude: mark.coordinate.latitude, longitude: mark.coordinate.longitude, kind: .city, dated: false)
            return place.isCountry ? nil : seen.insert(place.id).inserted ? place : nil
        }
    }
}

// MARK: - Place detail

struct BeenVisitDetail: View {
    let place: VisitedPlace
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @AppStorage(PlacePhotoStore.key) private var photoIndex = "{}"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var draft = PlaceDraft()
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var viewing: PinnedPhoto?
    @State private var addingStop = false
    struct PinnedPhoto: Identifiable { let id: String }

    private var current: VisitedPlace { VisitedPlace.decode(storage).first { $0.id == place.id } ?? place }
    private var photos: [String] { PlacePhotoStore.photos(for: place.id, in: photoIndex) }

    var body: some View {
        let place = current
        BeenSheetFrame(title: place.name, subtitle: place.isCountry ? "\(WorldGlobeView.flag(place.countryCode))  Country"
                       : "\(WorldGlobeView.flag(place.countryCode))  \(place.countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } ?? "City")") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    PlaceMark(place: place, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.isLived ? "You lived here" : "You’ve been here").font(Sketch.text(16, "Bold", relativeTo: .headline))
                        Text(place.whenText).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                    }
                    Spacer(minLength: 4)
                    Button { openMap() } label: {
                        Image(systemName: "map").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44)
                            .background(Circle().fill(BeenPalette.ink(scheme).opacity(0.06)))
                    }.buttonStyle(.plain).foregroundStyle(BeenPalette.accent(scheme)).accessibilityLabel("Open in Apple Maps")
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }.buttonStyle(.plain).foregroundStyle(.red).accessibilityLabel("Remove place")
                }
                if place.days != nil || place.trips != nil {
                    Label([place.trips.map { "\($0) \($0 == 1 ? "trip" : "trips")" }, place.days.map { "\($0) \($0 == 1 ? "day" : "days") with photos" }]
                        .compactMap { $0 }.joined(separator: " · ") + ", from your photos", systemImage: "photo.on.rectangle")
                        .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                PlaceWhenEditor(draft: $draft, isCountry: place.isCountry).padding(16).beenSurface(radius: 22)
                if !place.isLived { otherVisits(place) }
                if !place.isCountry { stopsSection(place) }
                photoStrip
            }
        }
        .presentationDetents([.large])
        .onAppear { draft = PlaceDraft(current); loaded = true }
        .onChange(of: draft) { _, value in
            // Edits save as you make them; there is no Save button to forget.
            guard loaded else { return }
            var records = VisitedPlace.decode(storage)
            guard let index = records.firstIndex(where: { $0.id == place.id }) else { return }
            value.apply(to: &records[index])
            storage = VisitedPlace.encode(records)
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoIndex = PlacePhotoStore.add(data, to: place.id, in: photoIndex)
                    }
                }
                picks = []
            }
        }
        .sheet(isPresented: $addingStop) {
            PlaceSearchSheet(title: "Add a stop", prompt: "A city, village, beach, anything", addresses: true) { addStop($0) }
        }
        .fullScreenCover(item: $viewing) { photo in
            PinnedPhotoViewer(name: photo.id) { photoIndex = PlacePhotoStore.remove(photo.id, from: place.id, in: photoIndex); viewing = nil }
        }
        .confirmationDialog("Remove \(place.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove place", role: .destructive) {
                storage = VisitedPlace.encode(VisitedPlace.decode(storage).filter { $0.id != place.id }); dismiss()
            }
        } message: { Text("Its dates and pinned photos go with it. Photos in your library are not touched.") }
    }

    /// Every further trip here. The first visit is the one above.
    private func otherVisits(_ place: VisitedPlace) -> some View {
        let spans = place.extra ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OTHER VISITS").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                Spacer()
                if place.visitCount > 1 { Text("\(place.visitCount) in all").font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(BeenPalette.accent(scheme)) }
            }
            ForEach(Array(spans.enumerated()), id: \.element.id) { index, span in
                HStack(spacing: 8) {
                    MonthYearMenu(date: Binding(get: { span.start }, set: { new in mutate { place in
                        guard var list = place.extra, index < list.count else { return }
                        list[index].start = new
                        if let u = list[index].until, u < new { list[index].until = new }
                        place.extra = list } }))
                    Text("to").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                    MonthYearMenu(date: Binding(get: { span.until ?? span.start }, set: { new in mutate { place in
                        guard var list = place.extra, index < list.count else { return }
                        list[index].until = max(new, list[index].start)
                        place.extra = list } }))
                    Spacer(minLength: 0)
                    Button { mutate { $0.extra?.remove(at: index); if $0.extra?.isEmpty == true { $0.extra = nil } } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(BeenPalette.secondary(scheme)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Remove visit \(span.text)")
                }
            }
            Button {
                TrippyHaptics.selection()
                mutate { $0.extra = ($0.extra ?? []) + [VisitSpan(start: PlaceDraft.thisMonth)] }
            } label: {
                Label("Add another visit", systemImage: "plus").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(BeenPalette.accent(scheme))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BeenPalette.accent(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            if spans.isEmpty { Text("Been here more than once? Add each trip and they all show on the timeline.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)) }
        }
        .padding(16).beenSurface(radius: 22)
    }

    /// Where else the trip went from here. A city becomes its own pin joined to this one; a smaller place
    /// stays with this city and appears around it when the map is zoomed in.
    private func stopsSection(_ place: VisitedPlace) -> some View {
        let stops = place.stops ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STOPS FROM HERE").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                Spacer()
                if !stops.isEmpty { Text("\(stops.count)").font(Sketch.text(12, "Bold", relativeTo: .caption)).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme)) }
            }
            ForEach(stops) { stop in
                let km = Int(Geo.km(place.coordinate, stop.coordinate).rounded())
                HStack(spacing: 12) {
                    // The rail: this city at the top, each stop hanging off it.
                    ZStack {
                        Circle().fill((stop.cityID != nil ? BeenPalette.amber : BeenLook.lived).opacity(0.18)).frame(width: 36, height: 36)
                        Image(systemName: stop.cityID != nil ? "mappin.and.ellipse" : "smallcircle.filled.circle").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(stop.cityID != nil ? BeenPalette.accent(scheme) : BeenLook.lived)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).lineLimit(1)
                        Text(stop.cityID != nil ? "City · joined to \(place.name) on the map · \(km) km" : "Shows around \(place.name) when you zoom in · \(km) km")
                            .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation(.snappy) { removeStop(stop) } } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(BeenPalette.secondary(scheme)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Remove stop \(stop.name)")
                }
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
            }
            Button { addingStop = true } label: {
                Label("Add a stop", systemImage: "plus").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(BeenPalette.accent(scheme))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BeenPalette.accent(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            if stops.isEmpty {
                Text("Day trips and other places on the same trip. A city gets its own pin, joined to this one; a small place stays with \(place.name).")
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).beenSurface(radius: 22)
        .sensoryFeedback(.impact(weight: .light), trigger: stops.count)
    }

    private func addStop(_ point: JourneyPoint) {
        var records = VisitedPlace.decode(storage)
        guard let index = records.firstIndex(where: { $0.id == place.id }) else { return }
        var stops = records[index].stops ?? []
        if let city = PlaceCatalog.significantCity(name: point.name, countryCode: point.countryCode, latitude: point.latitude, longitude: point.longitude) {
            // A city in its own right: make sure it is on the map, and join the two both ways.
            var other = VisitedPlace(name: city.name, countryCode: city.countryCode, latitude: city.latitude, longitude: city.longitude, kind: .city)
            guard other.id != place.id else { return }
            if let saved = records.first(where: { $0.id == other.id }) { other = saved }
            else { other.setWhen(records[index].when, until: records[index].until) }
            if !stops.contains(where: { $0.cityID == other.id }) { stops.append(PlaceStop(name: other.name, latitude: other.latitude, longitude: other.longitude, cityID: other.id)) }
            var back = other.stops ?? []
            if !back.contains(where: { $0.cityID == place.id }) {
                back.append(PlaceStop(name: records[index].name, latitude: records[index].latitude, longitude: records[index].longitude, cityID: place.id))
            }
            other.stops = back
            records[index].stops = stops
            records = VisitedPlace.saving(other, in: records)
        } else {
            let stop = PlaceStop(name: point.name, latitude: point.latitude, longitude: point.longitude)
            if !stops.contains(where: { $0.id == stop.id }) { stops.append(stop) }
            records[index].stops = stops
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { storage = VisitedPlace.encode(records) }
    }

    private func removeStop(_ stop: PlaceStop) {
        var records = VisitedPlace.decode(storage)
        for i in records.indices {
            if records[i].id == place.id { records[i].stops?.removeAll { $0.id == stop.id } }
            // The other end of a city link goes too; the city itself stays.
            if records[i].id == stop.cityID { records[i].stops?.removeAll { $0.cityID == place.id } }
            if records[i].stops?.isEmpty == true { records[i].stops = nil }
        }
        storage = VisitedPlace.encode(records)
    }

    private func mutate(_ change: (inout VisitedPlace) -> Void) {
        var records = VisitedPlace.decode(storage)
        guard let index = records.firstIndex(where: { $0.id == place.id }) else { return }
        change(&records[index]); storage = VisitedPlace.encode(records)
    }

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PINNED PHOTOS").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                Spacer()
                Label("Kept on this iPhone", systemImage: "lock.fill").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(BeenPalette.secondary(scheme))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 12, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .bold))
                            Text("Pin photos").font(Sketch.text(11, "Bold", relativeTo: .caption2))
                        }
                        .foregroundStyle(BeenPalette.accent(scheme)).frame(width: 96, height: 120)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BeenPalette.accent(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    ForEach(photos, id: \.self) { name in
                        Button { viewing = PinnedPhoto(id: name) } label: {
                            PinnedThumb(name: name).frame(width: 96, height: 120).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Pinned photo")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16).beenSurface(radius: 22)
    }

    private func openMap() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); item.name = place.name; item.openInMaps()
    }
}

// MARK: - Pinned photos

/// Photos you pin to a place are copied (scaled down) into the app's own folder on the phone. They are never uploaded.
enum PlacePhotoStore {
    static let key = "trippy.been.photos.v1"
    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BeenPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static func decode(_ index: String) -> [String: [String]] {
        (index.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) }) ?? [:]
    }
    private static func encode(_ map: [String: [String]]) -> String {
        String(data: (try? JSONEncoder().encode(map)) ?? Data(), encoding: .utf8) ?? "{}"
    }
    static func photos(for place: String, in index: String) -> [String] { decode(index)[place] ?? [] }
    static func counts(in index: String) -> [String: Int] { decode(index).mapValues(\.count).filter { $0.value > 0 } }

    static func add(_ data: Data, to place: String, in index: String) -> String {
        guard let image = UIImage(data: data) else { return index }
        // 1,600 points on the long side is plenty for a phone screen and keeps storage small.
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let name = UUID().uuidString + ".jpg"
        guard let jpeg = small.jpegData(compressionQuality: 0.82), (try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil else { return index }
        var map = decode(index); map[place, default: []].append(name)
        return encode(map)
    }
    static func remove(_ name: String, from place: String, in index: String) -> String {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        var map = decode(index); map[place]?.removeAll { $0 == name }
        return encode(map)
    }
    static func image(_ name: String) -> UIImage? { UIImage(contentsOfFile: folder.appendingPathComponent(name).path) }
}

struct PinnedThumb: View {
    let name: String
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: name) {
            let loaded = await Task.detached(priority: .utility) { PlacePhotoStore.image(name)?.preparingThumbnail(of: CGSize(width: 320, height: 400)) }.value
            image = loaded
        }
    }
}

struct PinnedPhotoViewer: View {
    let name: String
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = PlacePhotoStore.image(name) { Image(uiImage: image).resizable().scaledToFit() }
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44).background(Circle().fill(.ultraThinMaterial)) }
                    .accessibilityLabel("Close")
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Label("Unpin", systemImage: "pin.slash").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 44).background(Capsule().fill(.ultraThinMaterial))
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 16)
        }
    }
}
