import SwiftUI
import CoreLocation

// Statistics and the timeline for Been to: the facts worth knowing, then your travels laid out
// across (a ribbon of years you scroll sideways) or down (newest first).

// MARK: - Facts

struct BeenFact: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let value: String
    let detail: String
}

enum BeenFacts {
    /// One thing on the timeline: a trip, a dated visit, or the years lived somewhere.
    struct Entry: Identifiable {
        let id: String
        let place: VisitedPlace
        let start: Date
        let end: Date
        let lived: Bool
        var days: Int { max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 0) + 1) }
        var year: Int { Calendar.current.component(.year, from: start) }
    }

    /// Trips found in photos where there are any, otherwise the dates on the place itself.
    static func entries(_ snapshot: BeenPassportSnapshot, stays: [StayRecord]) -> [Entry] {
        let places = Dictionary(snapshot.visits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Entry] = []
        var covered = Set<String>()
        for stay in stays {
            guard let place = places[stay.placeID], !place.isLived else { continue }
            covered.insert(place.id)
            out.append(Entry(id: stay.id, place: place, start: stay.start, end: stay.end, lived: false))
        }
        let cityMonths = Set(snapshot.cities.compactMap { c in c.when.map { "\(c.countryCode ?? ""):\(Int($0.timeIntervalSince1970 / 2_600_000))" } })
        for place in snapshot.visits where !covered.contains(place.id) {
            guard let start = place.when else { continue }
            // A country added together with its cities would only repeat them.
            if place.isCountry, cityMonths.contains("\(place.countryCode ?? ""):\(Int(start.timeIntervalSince1970 / 2_600_000))") { continue }
            out.append(Entry(id: place.id, place: place, start: start, end: max(start, place.end ?? start), lived: place.isLived))
        }
        // Each further visit to a place is its own stop.
        for place in snapshot.visits where !place.isLived {
            for span in place.extra ?? [] {
                out.append(Entry(id: place.id + ":x\(span.id)", place: place, start: span.start, end: max(span.start, span.until ?? span.start), lived: false))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func all(_ snapshot: BeenPassportSnapshot, stays: [StayRecord]) -> [BeenFact] {
        var facts: [BeenFact] = []
        let entries = entries(snapshot, stays: stays)
        let trips = entries.filter { !$0.lived }
        let cities = snapshot.cities
        func km(_ a: VisitedPlace, _ b: VisitedPlace) -> Double { Geo.km(a.coordinate, b.coordinate) }

        let share = Double(snapshot.countryCount) / Double(BeenPassportSnapshot.worldCountries) * 100
        facts.append(BeenFact(id: "world", symbol: "globe.europe.africa.fill", title: "Of the world", value: String(format: share < 10 ? "%.1f%%" : "%.0f%%", share),
                              detail: "\(snapshot.countryCount) of 195 countries, \(snapshot.continents.count) of 6 continents"))
        if trips.count > 1 {
            let distance = zip(trips, trips.dropFirst()).reduce(0.0) { $0 + km($1.0.place, $1.1.place) }
            if distance > 500 {
                let laps = distance / 40_075
                facts.append(BeenFact(id: "distance", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", title: "Travelled", value: "\((Int(distance / 100) * 100).formatted()) km",
                                      detail: laps >= 1 ? String(format: "%.1f times round the Earth, place to place", laps) : "\(Int(laps * 100))% of the way round the Earth"))
            }
        }
        if let pair = snapshot.farthestPair, pair.2 > 200_000 {
            facts.append(BeenFact(id: "far", symbol: "arrow.left.and.right", title: "Farthest apart", value: "\(Int(pair.2 / 1000).formatted()) km", detail: "\(pair.0.name) to \(pair.1.name)"))
        }
        if let north = snapshot.northernmost, let south = snapshot.southernmost, north.id != south.id {
            facts.append(BeenFact(id: "north", symbol: "location.north.fill", title: "Furthest north", value: north.name, detail: String(format: "%.0f°N. Furthest south: %@", north.latitude, south.name)))
        }
        if cities.count > 1, let west = cities.map(\.longitude).min(), let east = cities.map(\.longitude).max() {
            let zones = max(1, Int(((east - west) / 15).rounded()) + 1)
            if zones > 1 { facts.append(BeenFact(id: "zones", symbol: "clock.fill", title: "Time zones", value: "\(min(24, zones)) of 24", detail: "Spanned between your western and eastern-most places")) }
        }
        let tripCounts = Dictionary(grouping: trips.filter { !$0.place.isCountry }, by: \.place.id).mapValues(\.count)
        if let most = tripCounts.max(by: { $0.value < $1.value }), most.value > 1, let place = trips.first(where: { $0.place.id == most.key })?.place {
            facts.append(BeenFact(id: "returned", symbol: "arrow.triangle.2.circlepath", title: "Keep going back to", value: place.name, detail: "\(most.value) separate trips"))
        }
        if let longest = trips.max(by: { $0.days < $1.days }), longest.days > 2 {
            facts.append(BeenFact(id: "longest", symbol: "tent.fill", title: "Longest trip", value: "\(longest.days) days", detail: "\(longest.place.name), \(longest.start.formatted(.dateTime.month(.abbreviated).year()))"))
        }
        let byYear = Dictionary(grouping: trips, by: \.year)
        if byYear.count > 1, let busiest = byYear.max(by: { $0.value.count < $1.value.count }) {
            let countries = Set(busiest.value.compactMap(\.place.countryCode)).count
            facts.append(BeenFact(id: "year", symbol: "calendar", title: "Busiest year", value: String(busiest.key), detail: "\(busiest.value.count) trips in \(countries) \(countries == 1 ? "country" : "countries")"))
        }
        let away = trips.filter { stays.isEmpty ? $0.days > 1 : true }.reduce(0) { $0 + $1.days }
        if away > 6 { facts.append(BeenFact(id: "days", symbol: "suitcase.fill", title: "Days away", value: away.formatted(), detail: "About \(String(format: "%.1f", Double(away) / 7)) weeks on the road")) }
        if !snapshot.lived.isEmpty {
            let years = snapshot.lived.reduce(0.0) { total, place in
                guard let start = place.when else { return total }
                return total + (place.end ?? start).timeIntervalSince(start) / 31_557_600
            }
            facts.append(BeenFact(id: "lived", symbol: "house.fill", title: "Called home", value: "\(snapshot.lived.count) \(snapshot.lived.count == 1 ? "place" : "places")",
                                  detail: years >= 1 ? String(format: "%.0f years in all: %@", years, snapshot.lived.map(\.name).prefix(3).joined(separator: ", ")) : snapshot.lived.map(\.name).prefix(3).joined(separator: ", ")))
        }
        if let first = entries.first {
            facts.append(BeenFact(id: "first", symbol: "flag.checkered", title: "Where it started", value: first.place.name, detail: first.start.formatted(.dateTime.month(.wide).year())))
        }
        let hemispheres = [cities.contains { $0.latitude >= 0 }, cities.contains { $0.latitude < 0 }, cities.contains { $0.longitude >= 0 }, cities.contains { $0.longitude < 0 }].filter { $0 }.count
        if hemispheres > 2 { facts.append(BeenFact(id: "hemi", symbol: "circle.lefthalf.filled", title: "Hemispheres", value: "\(hemispheres) of 4", detail: "North, south, east and west of the lines")) }
        return facts
    }
}

struct BeenFactGrid: View {
    let facts: [BeenFact]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: fact.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(BeenPalette.accent(scheme))
                        Text(fact.title.uppercased()).font(Sketch.eyebrow).tracking(0.6).foregroundStyle(BeenPalette.accent(scheme)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(fact.value).font(Sketch.display(.title3, weight: .bold)).lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    Text(fact.detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading).padding(14).beenSurface(radius: 20)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Timeline

struct BeenTimeline: View {
    let snapshot: BeenPassportSnapshot
    var onPlace: (VisitedPlace) -> Void
    @AppStorage(BeenStayStore.key) private var stayStorage = "[]"
    @AppStorage("trippy.been.timeline.across") private var across = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stays = BeenStayStore.decode(stayStorage)
        let entries = BeenFacts.entries(snapshot, stays: stays)
        VStack(alignment: .leading, spacing: 22) {
            if !ProcessInfo.processInfo.arguments.contains("-TrippyBeenTimelineOnly") { BeenFactGrid(facts: BeenFacts.all(snapshot, stays: stays)) }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No dates yet").font(Sketch.text(18, "Bold", relativeTo: .headline))
                    Text("Add a month or a range to a place, or scan your photos, and your years appear here.")
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(BeenPalette.secondary(scheme))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).beenSurface(radius: 24)
            } else {
                Picker("Timeline layout", selection: $across) {
                    Label("Across", systemImage: "arrow.left.and.right").tag(true)
                    Label("Down", systemImage: "arrow.up.and.down").tag(false)
                }.pickerStyle(.segmented)
                if across { TimelineRibbon(entries: entries, onPlace: onPlace).padding(.horizontal, -22) }
                else { TimelineColumn(entries: entries, onPlace: onPlace) }
            }
            if !snapshot.undated.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NO DATE · \(snapshot.undated.count)").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                    FlowLayout(spacing: 7) {
                        ForEach(snapshot.undated) { place in
                            Button { onPlace(place) } label: {
                                HStack(spacing: 6) {
                                    Text(WorldGlobeView.flag(place.countryCode)).font(.system(size: 14))
                                    Text(place.name).font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).lineLimit(1)
                                    if place.isLived { Image(systemName: "house.fill").font(.system(size: 9)).foregroundStyle(BeenLook.lived) }
                                }
                                .padding(.horizontal, 11).frame(minHeight: 36)
                                .background(Capsule().fill(BeenPalette.ink(scheme).opacity(0.06)))
                            }.buttonStyle(.plain).accessibilityHint("Add a date")
                        }
                    }
                }
            }
        }
    }
}

/// Years side by side: trips as flags above the line, the places you lived as bars under it.
private struct TimelineRibbon: View {
    let entries: [BeenFacts.Entry]
    var onPlace: (VisitedPlace) -> Void
    @Environment(\.colorScheme) private var scheme
    private let yearWidth: CGFloat = 300, chip: CGFloat = 58, lane: CGFloat = 60

    private var firstYear: Int { entries.map(\.year).min() ?? 2020 }
    private var lastYear: Int { max(Calendar.current.component(.year, from: .now), Calendar.current.component(.year, from: entries.map(\.end).max() ?? .now)) }
    private func x(_ date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (CGFloat((c.year ?? firstYear) - firstYear) + (CGFloat((c.month ?? 1) - 1) + CGFloat((c.day ?? 1) - 1) / 31) / 12) * yearWidth + 24
    }
    /// Puts each item on the first row where it doesn't cover the one before.
    private func lanes(_ items: [BeenFacts.Entry], width: (BeenFacts.Entry) -> CGFloat, limit: Int) -> [(BeenFacts.Entry, Int)] {
        var ends: [CGFloat] = []
        return items.map { item in
            let start = x(item.start)
            if let free = ends.firstIndex(where: { $0 + 4 <= start }) { ends[free] = start + width(item); return (item, free) }
            if ends.count < limit { ends.append(start + width(item)); return (item, ends.count - 1) }
            let least = ends.indices.min { ends[$0] < ends[$1] } ?? 0
            ends[least] = start + width(item); return (item, least)
        }
    }

    var body: some View {
        let trips = lanes(entries.filter { !$0.lived }, width: { _ in chip }, limit: 4)
        let homes = lanes(entries.filter(\.lived), width: { max(96, x($0.end) - x($0.start)) }, limit: 2)
        let rows = (trips.map(\.1).max() ?? 0) + 1, homeRows = homes.isEmpty ? 0 : (homes.map(\.1).max() ?? 0) + 1
        let axis = CGFloat(rows) * lane + 8
        let width = CGFloat(lastYear - firstYear + 1) * yearWidth + 48
        // Opens on your latest trip, not on the empty months since.
        let latest = (trips.map { x($0.0.start) + chip }.max() ?? width) + 70
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                // An offset view still sits at the left edge for scrolling, so the marker is spaced out in a row instead.
                HStack(spacing: 0) { Color.clear.frame(width: min(width - 1, latest), height: 1); Color.clear.frame(width: 1, height: 1).id("latest") }
                // Year bands and month ticks.
                ForEach(firstYear...lastYear, id: \.self) { year in
                    let left = CGFloat(year - firstYear) * yearWidth + 24
                    Rectangle().fill(BeenPalette.ink(scheme).opacity((year - firstYear) % 2 == 0 ? 0.035 : 0))
                        .frame(width: yearWidth, height: axis + 34 + CGFloat(homeRows) * 40).offset(x: left)
                    Text(String(year)).font(Sketch.text(13, "ExtraBold", relativeTo: .footnote)).monospacedDigit()
                        .foregroundStyle(BeenPalette.ink(scheme)).offset(x: left + 6, y: axis + 8)
                    ForEach(0..<12, id: \.self) { month in
                        Rectangle().fill(BeenPalette.ink(scheme).opacity(month == 0 ? 0.5 : 0.18))
                            .frame(width: month == 0 ? 2 : 1, height: month == 0 ? 12 : 6)
                            .offset(x: left + CGFloat(month) / 12 * yearWidth, y: axis - (month == 0 ? 6 : 3))
                    }
                }
                Rectangle().fill(BeenPalette.ink(scheme).opacity(0.35)).frame(width: width, height: 2).offset(y: axis - 1)
                ForEach(trips, id: \.0.id) { entry, row in
                    let top = axis - CGFloat(row + 1) * lane
                    // The stem ties a flag to its month on the line.
                    Rectangle().fill(BeenPalette.amber.opacity(0.7)).frame(width: 1.5, height: axis - top - 30).offset(x: x(entry.start) + chip / 2 - 0.75, y: top + 30)
                    Button { onPlace(entry.place) } label: {
                        VStack(spacing: 2) {
                            Text(WorldGlobeView.flag(entry.place.countryCode)).font(.system(size: 19))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(BeenPalette.base(scheme)))
                                .overlay(Circle().strokeBorder(Color(uiColor: BeenLook.heat(entry.place.heat)), lineWidth: 2.5))
                            Text(entry.place.name).font(Sketch.text(10, "Bold", relativeTo: .caption2)).lineLimit(1).frame(width: chip)
                        }
                    }
                    .buttonStyle(.plain).offset(x: x(entry.start), y: top)
                    .accessibilityLabel("\(entry.place.name), \(entry.start.formatted(.dateTime.month(.wide).year())), \(entry.days) days")
                }
                ForEach(homes, id: \.0.id) { entry, row in
                    Button { onPlace(entry.place) } label: {
                        // The name repeats every year, so a long bar is labelled wherever you have scrolled to.
                        let length = max(96, x(entry.end) - x(entry.start))
                        HStack(spacing: 0) {
                            ForEach(0..<max(1, Int(length / yearWidth) + 1), id: \.self) { _ in
                                HStack(spacing: 5) {
                                    Image(systemName: "house.fill").font(.system(size: 10, weight: .bold))
                                    Text(entry.place.name).font(Sketch.text(11, "Bold", relativeTo: .caption2)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, 9).frame(width: min(length, yearWidth))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: length, height: 30, alignment: .leading).clipped()
                        .background(Capsule().fill(BeenLook.lived)).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).offset(x: x(entry.start), y: axis + 34 + CGFloat(row) * 38)
                    .accessibilityLabel("Lived in \(entry.place.name), \(entry.place.whenText)")
                }
            }
            .frame(width: width, height: axis + 38 + CGFloat(homeRows) * 40, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .onAppear { DispatchQueue.main.async { proxy.scrollTo("latest", anchor: .trailing) } }
        }
    }
}

/// Newest first, one rail down the page with a stop for every trip.
private struct TimelineColumn: View {
    let entries: [BeenFacts.Entry]
    var onPlace: (VisitedPlace) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let years = Dictionary(grouping: entries, by: \.year)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(years.keys.sorted(by: >), id: \.self) { year in
                let items = (years[year] ?? []).sorted { $0.start > $1.start }
                HStack(alignment: .firstTextBaseline) {
                    Text(String(year)).font(.custom("PlusJakartaSans-ExtraBold", size: 30, relativeTo: .title)).tracking(-1).foregroundStyle(BeenPalette.accent(scheme))
                    Spacer()
                    Text("\(items.count) \(items.count == 1 ? "stop" : "stops")").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                .padding(.top, 14).padding(.bottom, 8)
                ForEach(items) { entry in
                    Button { onPlace(entry.place) } label: {
                        HStack(spacing: 12) {
                            PlaceMark(place: entry.place, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.place.name).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).multilineTextAlignment(.leading)
                                Text(label(entry)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme))
                            }
                            Spacer(minLength: 4)
                            if entry.lived { Text("LIVED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(BeenLook.lived) }
                            else if entry.days > 1 { Text("\(entry.days)d").font(Sketch.text(12, "Bold", relativeTo: .caption)).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme)) }
                        }
                        .padding(.horizontal, 12).frame(minHeight: 60).beenSurface(radius: 18)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 34).padding(.vertical, 5)
                    .background(alignment: .leading) { Rectangle().fill(BeenPalette.ink(scheme).opacity(0.16)).frame(width: 2).padding(.leading, 12) }
                    .overlay(alignment: .leading) {
                        Circle().fill(entry.lived ? BeenLook.lived : Color(uiColor: BeenLook.heat(entry.place.heat)))
                            .frame(width: 12, height: 12).overlay(Circle().strokeBorder(BeenPalette.base(scheme), lineWidth: 2)).padding(.leading, 7)
                    }
                }
            }
        }
    }
    private func label(_ entry: BeenFacts.Entry) -> String {
        if entry.lived { return entry.place.whenText }
        let start = entry.start.formatted(.dateTime.day().month(.abbreviated))
        return entry.days > 1 ? "\(start) – \(entry.end.formatted(.dateTime.day().month(.abbreviated)))" : entry.start.formatted(.dateTime.month(.wide))
    }
}
