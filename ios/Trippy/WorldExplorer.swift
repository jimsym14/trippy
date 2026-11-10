import SwiftUI
import MapKit

// Explicit visit records: a planned trip never implies that a place was visited.
/// A further visit to the same place: a month, or a range.
struct VisitSpan: Codable, Equatable, Identifiable, Hashable {
    var start: Date
    var until: Date? = nil
    var id: Double { start.timeIntervalSince1970 }
    var text: String {
        let f = Date.FormatStyle.dateTime.month(.abbreviated).year()
        guard let until, !Calendar.current.isDate(until, equalTo: start, toGranularity: .month) else { return start.formatted(f) }
        return start.formatted(f) + " – " + until.formatted(f)
    }
}

/// Somewhere you went from a city on the same trip. A stop that is a city in its own right points at that
/// city's own record (`cityID`) and the two are joined on the map; a smaller one (a village, a beach, a
/// winery) belongs to the city and shows around it when you zoom in.
struct PlaceStop: Codable, Equatable, Identifiable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    var cityID: String? = nil
    var id: String { cityID ?? "\(VisitedPlace.normalized(name)):\(Int(latitude * 1000)):\(Int(longitude * 1000))" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct VisitedPlace: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case country, city }
    var name: String
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    /// The start of the visit. Only meaningful when `dated` is true: use `when`.
    var visitedAt: Date = .now
    /// Everything below is optional so records saved by older builds still decode.
    var kind: Kind? = nil
    var dated: Bool? = nil
    /// Lived here, rather than visited.
    var lived: Bool? = nil
    /// End of a range (a long trip, or the years lived somewhere).
    var until: Date? = nil
    /// Lived here and still do.
    var ongoing: Bool? = nil
    /// Days there and separate trips, when known (from the photo scan).
    var days: Int? = nil
    var trips: Int? = nil
    /// Suggested from photos rather than typed in.
    var auto: Bool? = nil
    /// Other visits to this place, besides the one in `visitedAt`.
    var extra: [VisitSpan]? = nil
    /// Stops made from here: linked cities and smaller places.
    var stops: [PlaceStop]? = nil
    /// Every dated visit, first to last.
    var visitDates: [VisitSpan] {
        ((when.map { [VisitSpan(start: $0, until: until)] } ?? []) + (extra ?? [])).sorted { $0.start < $1.start }
    }
    /// How many separate visits are recorded (an undated place counts as one).
    var visitCount: Int { max(1, (when == nil ? 0 : 1) + (extra?.count ?? 0)) }

    var id: String { Self.normalized(name) + ":" + (countryCode ?? "").uppercased() }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// A whole country ("France") rather than a city in it. Older records have no kind, so the name decides.
    var isCountry: Bool {
        if let kind { return kind == .country }
        guard let code = countryCode?.uppercased(), let country = Locale(identifier: "en").localizedString(forRegionCode: code) else { return false }
        return Self.normalized(country) == Self.normalized(name)
    }
    var isLived: Bool { lived ?? false }
    /// When you went: nil means "no date". Older records only count as dated when a month was picked
    /// (saved as the 1st at noon); the old default of "today" was never a real date.
    var when: Date? {
        if let dated { return dated ? visitedAt : nil }
        let parts = Calendar.current.dateComponents([.day, .hour], from: visitedAt)
        return parts.day == 1 && parts.hour == 12 ? visitedAt : nil
    }
    var year: Int? { when.map { Calendar.current.component(.year, from: $0) } }
    /// The last day of the visit, when a range was given.
    var end: Date? { when == nil ? nil : (ongoing == true ? .now : until) }
    mutating func setWhen(_ date: Date?, until end: Date? = nil, ongoing still: Bool = false) {
        dated = date != nil
        if let date { visitedAt = date }
        until = date == nil || still ? nil : end.flatMap { $0 > date! ? $0 : nil }
        ongoing = date != nil && still ? true : nil
    }
    /// "Jun 2024", "2019 – 2022", "Since 2021" or "No date".
    var whenText: String {
        guard let start = when else { return "No date" }
        let month = Date.FormatStyle.dateTime.month(.abbreviated).year()
        if ongoing == true { return "Since " + start.formatted(month) }
        guard let until, !Calendar.current.isDate(until, equalTo: start, toGranularity: .month) else { return start.formatted(month) }
        let sameYear = Calendar.current.isDate(until, equalTo: start, toGranularity: .year)
        return (sameYear ? start.formatted(.dateTime.month(.abbreviated)) : start.formatted(month)) + " – " + until.formatted(month)
    }
    /// How much time this place has had, for the heat map: 0 (passed through) to 1 (lived there).
    var heat: Double {
        if isLived { return 1 }
        let byDays = min(1, log(Double(max(1, days ?? 1)) + 1) / log(40))
        let byTrips = min(1, Double((trips ?? 1) - 1) / 6)
        return max(0.18, min(0.9, max(byDays, byTrips)))
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func decode(_ storage: String) -> [Self] {
        guard let data = storage.data(using: .utf8), let records = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return records.filter { CLLocationCoordinate2DIsValid($0.coordinate) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    static func encode(_ records: [Self]) -> String {
        String(data: (try? JSONEncoder().encode(records)) ?? Data(), encoding: .utf8) ?? "[]"
    }
    static func adding(_ place: Self, to records: [Self]) -> [Self] {
        records.contains { $0.id == place.id } ? records : records + [place]
    }
    /// Adds the place, or updates the one already there.
    static func saving(_ place: Self, in records: [Self]) -> [Self] {
        var result = records
        if let index = result.firstIndex(where: { $0.id == place.id }) { result[index] = place } else { result.append(place) }
        return result
    }
    /// The 1st of a month at noon: how a picked month is stored.
    static func month(_ month: Int, _ year: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
    }
}

enum WorldContinentCatalog {
    private static let regions: [(String, Set<String>)] = [
        ("Europe", Set("AD AL AT AX BA BE BG BY CH CY CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK SM UA VA XK".split(separator: " ").map(String.init))),
        ("Asia", Set("AE AF AM AZ BD BH BN BT CN GE HK ID IL IN IQ IR JO JP KG KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA SA SG SY TH TJ TL TM TR TW UZ VN YE".split(separator: " ").map(String.init))),
        ("Africa", Set("AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG ER ET GA GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE NG RW SC SD SL SN SO SS ST SZ TD TG TN TZ UG ZA ZM ZW".split(separator: " ").map(String.init))),
        ("North America", Set("AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD GL GP GT HN HT JM KN KY LC MF MQ MS MX NI PA PM PR SV SX TC TT US VC VG VI".split(separator: " ").map(String.init))),
        ("South America", Set("AR BO BR CL CO EC FK GF GY PE PY SR UY VE".split(separator: " ").map(String.init))),
        ("Oceania", Set("AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PW SB TK TL TO TV VU WF WS".split(separator: " ").map(String.init)))
    ]
    static func name(for code: String?) -> String {
        guard let code = code?.uppercased() else { return "Other" }
        return regions.first { $0.1.contains(code) }?.0 ?? "Other"
    }
    static let colors: [String: Color] = [
        "Europe": Color(red: 0.39, green: 0.55, blue: 0.96),
        "Asia": Color(red: 0.62, green: 0.43, blue: 0.94),
        "Africa": Color(red: 0.95, green: 0.61, blue: 0.25),
        "North America": Color(red: 0.20, green: 0.72, blue: 0.65),
        "South America": Color(red: 0.91, green: 0.40, blue: 0.48),
        "Oceania": Color(red: 0.28, green: 0.68, blue: 0.89),
        "Other": Color(red: 0.55, green: 0.61, blue: 0.65)
    ]
}

struct NeighborhoodPlace: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var city: String = ""
    var countryCode: String? = nil
    var outline: [GeoBoundaryPoint] = []
    var source = "Apple Maps"
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum NeighborhoodMetric: String, CaseIterable, Identifiable, Codable {
    case safety, budget, family, nightlife
    var id: String { rawValue }
    var title: String {
        switch self { case .safety: "Felt safe"; case .budget: "Budget"; case .family: "Family"; case .nightlife: "Nightlife" }
    }
    var symbol: String {
        switch self { case .safety: "shield.lefthalf.filled"; case .budget: "eurosign.circle"; case .family: "figure.2.and.child.holdinghands"; case .nightlife: "moon.stars" }
    }
    var hint: String {
        switch self { case .safety: "How comfortable you felt"; case .budget: "5 = most affordable"; case .family: "Good for families"; case .nightlife: "Places to go out" }
    }
    var tint: Color {
        switch self { case .safety: Color.teal; case .budget: Color.orange; case .family: Color.indigo; case .nightlife: Color.purple }
    }
    func color(_ scheme: ColorScheme) -> Color {
        guard scheme == .light else { return tint }
        switch self {
        case .safety: return Color(red: 0.10, green: 0.43, blue: 0.40)
        case .budget: return Color(red: 0.48, green: 0.30, blue: 0.05)
        case .family: return Color(red: 0.32, green: 0.32, blue: 0.67)
        case .nightlife: return Color(red: 0.48, green: 0.30, blue: 0.64)
        }
    }
}
struct NeighborhoodFeedback: Codable, Equatable {
    var neighborhood: NeighborhoodPlace
    var scores: [String: Int] = [:]
    var note = ""
    var updatedAt: Date = .now
    static func decode(_ storage: String) -> [Self] {
        guard let data = storage.data(using: .utf8), let values = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return values.map { item in
            var copy = item
            copy.scores = item.scores.filter { (1...5).contains($0.value) && NeighborhoodMetric(rawValue: $0.key) != nil }
            return copy
        }
    }
    static func encode(_ values: [Self]) -> String {
        String(data: (try? JSONEncoder().encode(values)) ?? Data(), encoding: .utf8) ?? "[]"
    }
    static func matching(_ place: NeighborhoodPlace, in values: [Self]) -> Self? {
        values.first { $0.neighborhood.id == place.id } ?? values.first {
            VisitedPlace.normalized($0.neighborhood.name) == VisitedPlace.normalized(place.name)
                && CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: CLLocation(latitude: $0.neighborhood.latitude, longitude: $0.neighborhood.longitude)) < 1_500
        }
    }
    static func saving(_ value: Self, in values: [Self]) -> [Self] {
        var result = values
        if let match = matching(value.neighborhood, in: result), let index = result.firstIndex(where: { $0.neighborhood.id == match.neighborhood.id }) { result[index] = value }
        else { result.append(value) }
        return result
    }
}

struct NeighborhoodDetailView: View {
    let place: NeighborhoodPlace
    @AppStorage("trippy.native.neighborhoodFeedback.v1") private var storage = "[]"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var scores: [String: Int] = [:]
    @State private var note = ""
    @State private var saved = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NeighborhoodHeading(place: place)
                    StatlasCityCard(city: place.city.isEmpty ? place.name : place.city, countryCode: place.countryCode, latitude: place.latitude, longitude: place.longitude)
                    Text("Your experience").font(.custom("PlusJakartaSans-Bold", size: 19))
                    Text("Personal feedback, not an official safety rating. Rate only what you know.")
                        .font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme))
                    ForEach(NeighborhoodMetric.allCases) { metric in
                        NeighborhoodScoreRow(metric: metric, score: Binding(get: { scores[metric.rawValue] }, set: { scores[metric.rawValue] = $0 }))
                    }
                    TextField("A useful note…", text: $note, axis: .vertical)
                        .lineLimit(3...6).padding(16).librarySurface(radius: 20, inset: true)
                    Button {
                        let feedback = NeighborhoodFeedback(neighborhood: place, scores: scores, note: note, updatedAt: .now)
                        storage = NeighborhoodFeedback.encode(NeighborhoodFeedback.saving(feedback, in: NeighborhoodFeedback.decode(storage)))
                        saved = true
                    } label: {
                        Label(saved ? "Saved" : "Save feedback", systemImage: saved ? "checkmark" : "checkmark.circle")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }.buttonStyle(.borderedProminent).tint(LibraryTone.trips.color(scheme)).disabled(scores.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("\(place.source) · \(place.outline.isEmpty ? "Neighborhood point · no outline available" : "Neighborhood outline")")
                        .font(.caption).foregroundStyle(LibraryColors.secondary(scheme))
                }.padding(22)
            }.background { LibraryAtmosphere(tone: .trips) }.foregroundStyle(LibraryColors.ink(scheme))
                .navigationTitle("Neighborhood").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .onAppear {
                if let existing = NeighborhoodFeedback.matching(place, in: NeighborhoodFeedback.decode(storage)) { scores = existing.scores; note = existing.note }
            }
            .onChange(of: scores) { _, _ in saved = false }.onChange(of: note) { _, _ in saved = false }
    }
}
struct NeighborhoodHeading: View {
    @Environment(\.colorScheme) private var scheme
    let place: NeighborhoodPlace
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.3.layers.3d").font(.title2).foregroundStyle(.teal).frame(width: 52, height: 52).librarySurface(radius: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name).font(.custom("PlusJakartaSans-Bold", size: 25)).lineLimit(2)
                Text(place.city.isEmpty ? "Explore the area" : place.city).font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme))
            }
        }
    }
}
struct NeighborhoodScoreRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let metric: NeighborhoodMetric
    @Binding var score: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: metric.symbol).foregroundStyle(metric.color(scheme))
                Text(metric.title).font(.custom("PlusJakartaSans-Bold", size: 15))
                Spacer()
                if let score { Text("\(score)/5").font(.headline).monospacedDigit().foregroundStyle(metric.color(scheme)) }
            }
            Text(metric.hint).font(.caption).foregroundStyle(LibraryColors.secondary(scheme))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { score = score == value ? nil : value } } label: {
                        Text(value.formatted()).font(.custom("PlusJakartaSans-Bold", size: 15))
                            .frame(maxWidth: .infinity, minHeight: 44).background(score == value ? metric.color(scheme).opacity(0.2) : .clear, in: Circle())
                            .librarySurface(radius: 22).overlay(Circle().strokeBorder(score == value ? metric.color(scheme) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("\(metric.title), \(value) of 5").accessibilityAddTraits(score == value ? .isSelected : [])
                }
            }
        }.padding(16).librarySurface(radius: 22)
    }
}

struct VisitedCountryGroup: Identifiable {
    let id: String
    let countryCode: String?
    let visits: [VisitedPlace]
    var name: String { countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } ?? "Unknown country" }
    /// The cities in it, without the record for the country itself.
    var cities: [VisitedPlace] { visits.filter { !$0.isCountry } }
    var lived: Bool { visits.contains(where: \.isLived) }
    var coordinate: CLLocationCoordinate2D { visits[0].coordinate }
    static func groups(_ visits: [VisitedPlace]) -> [Self] {
        Dictionary(grouping: visits, by: { $0.countryCode?.uppercased() ?? "unknown:" + $0.id }).map { key, values in
            Self(id: key, countryCode: values[0].countryCode?.uppercased(), visits: values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
struct WorldCountryVisitsView: View {
    let group: VisitedCountryGroup
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @State private var visits: [VisitedPlace] = []
    @State private var selectedVisit: VisitedPlace?
    @State private var showAdd = false
    var body: some View {
        BeenSheetFrame(title: group.name, subtitle: "\(WorldGlobeView.flag(group.countryCode))  \(visits.filter { !$0.isCountry }.count) cities · \(BeenContinentName.title(WorldContinentCatalog.name(for: group.countryCode)))") {
            LazyVStack(spacing: 12) {
                ForEach(visits) { place in BeenVisitRow(place: place) { selectedVisit = place } }
            }
            Button { showAdd = true } label: {
                Label("Add a visit", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }.buttonStyle(.bordered)
        }.presentationDetents([.large])
            .onAppear { reload() }.onChange(of: storage) { _, _ in reload() }
            .sheet(item: $selectedVisit) { BeenVisitDetail(place: $0) }
            .sheet(isPresented: $showAdd) { VisitedPlacePicker(initialQuery: group.name) }
    }
    private func reload() {
        visits = VisitedPlace.decode(storage).filter { group.countryCode == nil ? group.visits.map(\.id).contains($0.id) : $0.countryCode?.uppercased() == group.countryCode }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
