import SwiftUI
import Photos
import CoreLocation

// Places from your photo library, worked out entirely on the phone.
//
// The scan reads two things per photo: when it was taken and where. It never opens the pictures, makes no
// network request and uses no paid service: place names come from the city list and country outlines bundled
// with the app. What it finds is only a suggestion; nothing is added until you tick it.
//
// Photos that are not evidence you were somewhere are thrown out before anything is suggested:
//   · screenshots, and anything from shared albums or synced from a computer
//   · taken in flight (high altitude or aircraft speed recorded in the photo)
//   · "impossible" photos: a place you could not have reached in time from where your other photos
//     put you (typically a picture someone sent you, or one you saved)
// and a place with a single photo, or one that looks like a stop on the way somewhere else, is listed
// under "Not sure" and left unticked.

// MARK: - Model

struct PhotoSample: Sendable {
    let time: Date
    let latitude: Double
    let longitude: Double
    var altitude: Double = 0
    var speed: Double = -1
    var id: String = ""
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// One uninterrupted time in a place: a trip, or part of the time you lived there.
struct StayRecord: Codable, Identifiable, Hashable, Sendable {
    var placeID: String
    var name: String
    var countryCode: String?
    var start: Date
    var end: Date
    /// Days on which a photo was taken there.
    var photoDays: Int
    var lived = false
    var id: String { "\(placeID):\(Int(start.timeIntervalSince1970))" }
    /// Nights away, counted as calendar days from first to last photo.
    var length: Int { max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 0) + 1) }
}

enum BeenStayStore {
    static let key = "trippy.been.stays.v1"
    static func decode(_ storage: String) -> [StayRecord] {
        (storage.data(using: .utf8).flatMap { try? JSONDecoder().decode([StayRecord].self, from: $0) }) ?? []
    }
    static func encode(_ stays: [StayRecord]) -> String { String(data: (try? JSONEncoder().encode(stays)) ?? Data(), encoding: .utf8) ?? "[]" }
}

struct PhotoFinding: Identifiable, Sendable {
    var place: VisitedPlace
    var stays: [StayRecord]
    var photoDays: Int
    var photos: Int
    var first: Date
    var last: Date
    /// The longest stretch that qualifies as living there, if any.
    var residence: ClosedRange<Date>?
    /// nil when the evidence is solid; otherwise why it is left unticked.
    var doubt: String?
    var samples: [String]
    var id: String { place.id }
    var longest: Int { stays.map(\.length).max() ?? 1 }
    var summary: String {
        let years = Calendar.current.component(.year, from: first), end = Calendar.current.component(.year, from: last)
        let span = years == end ? String(years) : "\(years)–\(end)"
        if residence != nil { return "\(photoDays) days with photos · \(span)" }
        let trips = stays.count
        return "\(trips) \(trips == 1 ? "trip" : "trips") · \(longest == 1 ? "1 day" : "longest \(longest) days") · \(span)"
    }
}

struct PhotoScanReport: Sendable {
    var findings: [PhotoFinding] = []
    var total = 0
    var located = 0
    var inFlight = 0
    var impossible = 0
    var atSea = 0
    var ignored: Int { inFlight + impossible }
}

// MARK: - Engine

enum PhotoTripEngine {
    /// Cities bucketed by whole degrees, so finding the nearest one looks at a handful, not all 3,000.
    private static let cityGrid: [Int: [CityEntry]] = {
        var grid: [Int: [CityEntry]] = [:]
        for city in PlaceCatalog.cities { grid[cell(city.latitude, city.longitude), default: []].append(city) }
        return grid
    }()
    private static func cell(_ lat: Double, _ lon: Double) -> Int { Int(floor(lat)) * 1000 + Int(floor(lon)) }

    private struct Spot: Hashable { let name: String; let code: String?; let latitude: Double; let longitude: Double; let country: Bool
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var place: VisitedPlace { VisitedPlace(name: name, countryCode: code, latitude: latitude, longitude: longitude, kind: country ? .country : .city) } }

    /// The listed city within 25 km, else the country the point is in (found from the bundled outlines), else nothing (open sea).
    private static func spot(_ c: CLLocationCoordinate2D) -> Spot? {
        var best: (CityEntry, Double)?
        for dLat in -1...1 { for dLon in -1...1 {
            for city in cityGrid[cell(c.latitude + Double(dLat), c.longitude + Double(dLon))] ?? [] {
                let d = Geo.km(c, .init(latitude: city.latitude, longitude: city.longitude))
                if d < (best?.1 ?? 25) { best = (city, d) }
            }
        } }
        if let city = best?.0 { return Spot(name: city.name, code: city.countryCode, latitude: city.latitude, longitude: city.longitude, country: false) }
        guard let code = GlobeBorders.country(at: c)?.code, let country = PlaceCatalog.country(code),
              let lat = country.latitude, let lon = country.longitude else { return nil }
        return Spot(name: country.name, code: code, latitude: lat, longitude: lon, country: true)
    }

    private struct Run {
        var spot: Spot
        var start: Date, end: Date
        var count: Int
        var first: CLLocationCoordinate2D, last: CLLocationCoordinate2D
        var days: Set<Int>
        var ids: [String]
        var passing = false
        var span: TimeInterval { end.timeIntervalSince(start) }
        var thin: Bool { count <= 8 && span < 2 * 3600 }
    }

    /// `livedAfterDays`: how long, mostly in one place, before it is suggested as somewhere you lived.
    static func analyse(_ input: [PhotoSample], total: Int? = nil, livedAfterDays: Int = 60) -> PhotoScanReport {
        var report = PhotoScanReport(total: total ?? input.count, located: input.count)
        let calendar = Calendar.current
        func day(_ date: Date) -> Int { Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400) }

        // 1. In flight: the photo itself says so.
        let grounded = input.sorted { $0.time < $1.time }.filter { s in
            let flying = s.speed > 75 || s.altitude > 6_000 || (s.altitude > 2_800 && s.speed > 45)
            if flying { report.inFlight += 1 }
            return !flying
        }

        // 2. Name each photo's place, remembering answers for photos taken close together.
        var known: [Int: Spot?] = [:]
        var runs: [Run] = []
        for s in grounded {
            let key = Int((s.latitude * 50).rounded()) * 100_000 + Int((s.longitude * 50).rounded())
            let found: Spot?
            if let cached = known[key] { found = cached } else { found = spot(s.coordinate); known[key] = found }
            guard let found else { report.atSea += 1; continue }
            if var last = runs.last, last.spot == found {
                last.end = s.time; last.count += 1; last.last = s.coordinate; last.days.insert(day(s.time))
                if last.ids.count < 3 { last.ids.append(s.id) }
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(spot: found, start: s.time, end: s.time, count: 1, first: s.coordinate, last: s.coordinate, days: [day(s.time)], ids: [s.id]))
            }
        }

        // 3. Impossible photos. Getting from one run of photos to the next faster than an airliner means one of
        //    the two was not taken by you there; the one with less behind it goes. Repeat until nothing changes.
        func tooFast(_ a: Run, _ b: Run) -> Bool {
            let km = Geo.km(a.last, b.first)
            return km > 150 && km / max(b.start.timeIntervalSince(a.end) / 3600, 0.02) > 950
        }
        func weight(_ r: Run) -> Double { Double(r.count) + r.span / 600 + Double(r.days.count) * 20 }
        for _ in 0..<4 {
            var drop = Set<Int>()
            for i in runs.indices where runs[i].thin {
                let before = i > 0 && tooFast(runs[i - 1], runs[i]) && weight(runs[i - 1]) > weight(runs[i])
                let after = i + 1 < runs.count && tooFast(runs[i], runs[i + 1]) && weight(runs[i + 1]) > weight(runs[i])
                if before || after { drop.insert(i) }
            }
            guard !drop.isEmpty else { break }
            report.impossible += drop.reduce(0) { $0 + runs[$1].count }
            var merged: [Run] = []
            for (i, run) in runs.enumerated() where !drop.contains(i) {
                if var last = merged.last, last.spot == run.spot {
                    last.end = run.end; last.count += run.count; last.last = run.last; last.days.formUnion(run.days)
                    merged[merged.count - 1] = last
                } else { merged.append(run) }
            }
            runs = merged
        }

        // 4. Passing through: a few photos in one moment, between two other places far apart, within a day.
        for i in runs.indices where i > 0 && i + 1 < runs.count {
            let run = runs[i], a = runs[i - 1], b = runs[i + 1]
            if run.count <= 6, run.span < 40 * 60, a.spot != run.spot, b.spot != run.spot,
               Geo.km(a.last, b.first) > 300, b.start.timeIntervalSince(a.end) < 18 * 3600 { runs[i].passing = true }
        }

        // 5. Stays: time in a place until you are next seen more than 150 km away (a day trip nearby doesn't end it),
        //    or until six weeks pass with no photo there.
        struct Stay { var spot: Spot; var start: Date; var end: Date; var days: Set<Int>; var photos: Int; var ids: [String]; var passing: Bool }
        var stays: [Stay] = []
        var open: [Spot: Int] = [:]
        for run in runs {
            for (spot, index) in open where spot != run.spot {
                if Geo.km(spot.coordinate, run.first) > 150 || run.start.timeIntervalSince(stays[index].end) > 45 * 86_400 { open[spot] = nil }
            }
            if let index = open[run.spot], run.start.timeIntervalSince(stays[index].end) <= 45 * 86_400 {
                stays[index].end = run.end; stays[index].days.formUnion(run.days); stays[index].photos += run.count
                stays[index].passing = stays[index].passing && run.passing
                if stays[index].ids.count < 3 { stays[index].ids += run.ids.prefix(3 - stays[index].ids.count) }
            } else {
                open[run.spot] = stays.count
                stays.append(Stay(spot: run.spot, start: run.start, end: run.end, days: run.days, photos: run.count, ids: run.ids, passing: run.passing))
            }
        }

        // 6. One finding per place.
        let allDays = Set(runs.flatMap(\.days))
        let citiesFound = Set(stays.filter { !$0.spot.country }.compactMap(\.spot.code))
        for (spot, list) in Dictionary(grouping: stays, by: \.spot) {
            // A country on its own is only suggested when no city in it was found.
            if spot.country, let code = spot.code, citiesFound.contains(code) { continue }
            let ordered = list.sorted { $0.start < $1.start }
            let days = ordered.reduce(into: Set<Int>()) { $0.formUnion($1.days) }
            let photos = ordered.reduce(0) { $0 + $1.photos }
            let place = spot.place

            // Lived there: stays linked by absences of under 30 days, lasting long enough, with most of your
            // photo days in that period spent there. Many short trips far apart never link up.
            var residence: ClosedRange<Date>?
            var chain: [Stay] = []
            func close() {
                guard let first = chain.first, let last = chain.last else { return }
                let length = last.end.timeIntervalSince(first.start) / 86_400
                let there = chain.reduce(into: Set<Int>()) { $0.formUnion($1.days) }
                let everywhere = allDays.filter { $0 >= day(first.start) && $0 <= day(last.end) }.count
                if length >= Double(livedAfterDays), there.count >= 8, Double(there.count) / Double(max(1, everywhere)) >= 0.5,
                   length > (residence.map { $0.upperBound.timeIntervalSince($0.lowerBound) / 86_400 } ?? 0) {
                    residence = first.start...last.end
                }
                chain = []
            }
            for stay in ordered {
                if let last = chain.last, stay.start.timeIntervalSince(last.end) > 30 * 86_400 { close() }
                chain.append(stay)
            }
            close()

            var doubt: String?
            let longestMoment = ordered.map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
            if ordered.allSatisfy(\.passing) { doubt = "Looks like a stop on the way somewhere else" }
            else if days.count < 2 && photos == 1 { doubt = "Only 1 photo" }
            else if days.count < 2 && (photos < 4 || longestMoment < 30 * 60) { doubt = "Only \(photos) photos, taken within minutes" }

            let records = ordered.filter { !$0.passing || doubt != nil }.map {
                StayRecord(placeID: place.id, name: place.name, countryCode: place.countryCode, start: $0.start, end: $0.end, photoDays: $0.days.count)
            }
            report.findings.append(PhotoFinding(place: place, stays: records, photoDays: days.count, photos: photos,
                                                first: ordered[0].start, last: ordered.map(\.end).max() ?? ordered[0].end,
                                                residence: residence, doubt: doubt, samples: Array(ordered.flatMap(\.ids).prefix(3))))
        }
        report.findings.sort { ($0.residence != nil ? 1 : 0, $0.last) > ($1.residence != nil ? 1 : 0, $1.last) }
        return report
    }

    /// Date and location of every photo and video in the user's own library. Nothing else is read.
    static func librarySamples() async -> (samples: [PhotoSample], total: Int) {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = [.typeUserLibrary]   // not shared albums, not synced from a computer
            options.predicate = NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let assets = PHAsset.fetchAssets(with: options)
            var samples: [PhotoSample] = []
            samples.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let location = asset.location, let date = asset.creationDate, CLLocationCoordinate2DIsValid(location.coordinate),
                      abs(location.coordinate.latitude) > 0.0001 || abs(location.coordinate.longitude) > 0.0001 else { return }
                samples.append(PhotoSample(time: date, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                           altitude: location.verticalAccuracy >= 0 ? location.altitude : 0, speed: location.speed, id: asset.localIdentifier))
            }
            return (samples, assets.count)
        }.value
    }

    #if DEBUG
    /// A made-up library that exercises every rule: home, a year abroad, repeat short trips, a saved photo,
    /// a window-seat photo, a motorway stop and a single stray picture.
    static var demoSamples: [PhotoSample] {
        var out: [PhotoSample] = []
        let calendar = Calendar(identifier: .gregorian)
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .now }
        func add(_ date: Date, _ lat: Double, _ lon: Double, n: Int = 3, altitude: Double = 0, speed: Double = -1) {
            for i in 0..<n { out.append(PhotoSample(time: date.addingTimeInterval(Double(i) * 900), latitude: lat + Double(i) * 0.002, longitude: lon, altitude: altitude, speed: speed, id: "")) }
        }
        let athens = (37.98, 23.73), sofia = (42.70, 23.32), berlin = (52.52, 13.40), paris = (48.86, 2.35), rome = (41.90, 12.50)
        // Home in Athens, a photo every week or so, 2019 to 2024.
        var week = at(2019, 1, 5)
        while week < at(2024, 10, 1) {
            let away = week >= at(2021, 3, 1) && week <= at(2021, 11, 20)
            if !away { add(week, athens.0, athens.1) }
            week = week.addingTimeInterval(8 * 86_400)
        }
        // Nine months in Berlin, with a fortnight back in Athens in the middle.
        var d = at(2021, 3, 2)
        while d < at(2021, 11, 20) {
            if d >= at(2021, 7, 10) && d <= at(2021, 7, 24) { add(d, athens.0, athens.1) } else { add(d, berlin.0, berlin.1) }
            d = d.addingTimeInterval(5 * 86_400)
        }
        // Sofia, again and again, never longer than five days.
        for (y, m) in [(2019, 4), (2019, 10), (2020, 2), (2022, 5), (2023, 3), (2023, 12), (2024, 6)] {
            for day in 12...15 { add(at(y, m, day), sofia.0, sofia.1) }
        }
        for day in 3...9 { add(at(2022, 9, day), paris.0, paris.1, n: 5) }
        for day in 18...21 { add(at(2023, 6, day), rome.0, rome.1, n: 4) }
        // A photo a friend sent from Tokyo, dated in the middle of an ordinary Athens day.
        add(at(2023, 2, 9, 10), athens.0, athens.1); add(at(2023, 2, 9, 12), 35.68, 139.69, n: 1); add(at(2023, 2, 9, 14), athens.0, athens.1)
        // Out of the window on the way to Paris.
        add(at(2022, 9, 3, 8), 45.1, 12.2, n: 2, altitude: 10_400, speed: 230)
        // One stray picture in Lisbon, and a motorway stop near Niš on the drive to Sofia.
        add(at(2020, 8, 14), 38.72, -9.14, n: 1)
        add(at(2024, 6, 11, 9), athens.0, athens.1); add(at(2024, 6, 11, 17), 43.32, 21.90, n: 2); add(at(2024, 6, 12, 7), sofia.0, sofia.1)
        return out
    }
    #endif
}

// MARK: - Sheet

struct PhotoScanSheet: View {
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @AppStorage(BeenStayStore.key) private var stayStorage = "[]"
    @AppStorage("trippy.been.livedAfterDays") private var livedAfter = 60
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var phase = Phase.intro
    @State private var samples: [PhotoSample] = []
    @State private var total = 0
    @State private var report = PhotoScanReport()
    @State private var chosen: Set<String> = []
    @State private var asLived: Set<String> = []
    @State private var showUnsure = false
    enum Phase { case intro, scanning, results, denied }

    private static let thresholds = [(14, "2 weeks"), (30, "1 month"), (60, "2 months"), (90, "3 months"), (180, "6 months")]

    var body: some View {
        BeenSheetFrame(title: phase == .results ? "From your photos" : "Find places from photos",
                       subtitle: phase == .results ? resultLine : "") {
            switch phase {
            case .intro: intro
            case .scanning:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Reading dates and locations…").font(Sketch.text(15, "SemiBold", relativeTo: .body))
                    Text("On this iPhone only.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(BeenPalette.secondary(scheme))
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            case .results: results
            case .denied:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trippy can’t see your photos.").font(Sketch.text(18, "Bold", relativeTo: .headline))
                    Text("Allow photo access in Settings to scan them. You can also keep adding places by hand.")
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(BeenPalette.secondary(scheme))
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        .buttonStyle(.borderedProminent).tint(BeenPalette.accent(scheme))
                }.padding(20).beenSurface(radius: 24)
            }
        }
        .presentationDetents([.large])
        .safeAreaInset(edge: .bottom) { if phase == .results && !chosen.isEmpty { addBar } }
        .onChange(of: livedAfter) { _, _ in if phase == .results { analyse() } }
        #if DEBUG
        .task {
            // `-TrippyPhotoScanDemo`: run the rules on a made-up library (the simulator has no real one to speak of).
            if ProcessInfo.processInfo.arguments.contains("-TrippyPhotoScanDemo"), phase == .intro {
                samples = PhotoTripEngine.demoSamples; total = samples.count + 412; analyse()
            }
        }
        #endif
    }

    private var resultLine: String {
        "\(total.formatted()) photos read · \(report.located.formatted()) had a location" + (report.ignored > 0 ? " · \(report.ignored) ignored" : "")
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Stays on this iPhone", systemImage: "lock.shield.fill").font(Sketch.text(18, "Bold", relativeTo: .headline)).foregroundStyle(BeenLook.lived)
                point("calendar.badge.clock", "Only each photo’s date and location are read. The pictures themselves are not analysed.")
                point("iphone", "Everything is worked out here, on the phone. No upload, no account, no cost. It works in Airplane Mode.")
                point("map", "Place names come from a list inside the app, so your locations are not sent anywhere to be looked up.")
                point("checklist", "You get a list to review. Nothing is added until you tick it, and you can remove it again later.")
            }
            .padding(18).beenSurface(radius: 24)
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT IT LEAVES OUT").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                point("airplane", "Photos taken in flight.")
                point("square.and.arrow.down", "Photos you saved or were sent: a place you couldn’t have reached in time is ignored.")
                point("questionmark.circle", "A single photo somewhere, or a quick stop on the way: listed as “Not sure”, unticked.")
            }
            .padding(18).beenSurface(radius: 24, inset: true)
            Button { Task { await scan() } } label: {
                Label("Scan my photos", systemImage: "sparkle.magnifyingglass").font(Sketch.text(16, "Bold", relativeTo: .headline))
                    .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(BeenPalette.base(scheme)).background(Capsule().fill(BeenPalette.ink(scheme)))
            }
            .buttonStyle(SketchPressStyle())
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(BeenPalette.accent(scheme)).frame(width: 22)
            Text(text).font(Sketch.text(14, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let lived = report.findings.filter { $0.residence != nil && $0.doubt == nil }
        let trips = report.findings.filter { $0.residence == nil && $0.doubt == nil }
        let unsure = report.findings.filter { $0.doubt != nil }
        if report.findings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No places found.").font(Sketch.text(18, "Bold", relativeTo: .headline))
                Text(report.located == 0 ? "None of your photos have a location saved with them." : "Your photos with a location didn’t match a place.")
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(BeenPalette.secondary(scheme))
            }.padding(20).beenSurface(radius: 24)
        }
        if report.ignored > 0 {
            Label("Ignored \(report.inFlight) taken in flight and \(report.impossible) that were saved or sent to you.", systemImage: "eye.slash")
                .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal, 4)
        }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Counts as lived after").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Text("Mostly in one place for this long. Shorter stays are trips, however many.")
                    .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker("Counts as lived after", selection: $livedAfter) { ForEach(Self.thresholds, id: \.0) { Text($0.1).tag($0.0) } }
                .pickerStyle(.menu).tint(BeenPalette.accent(scheme))
        }
        .padding(.horizontal, 16).padding(.vertical, 10).beenSurface(radius: 20, inset: true)
        if !lived.isEmpty { group("Lived", lived) }
        if !trips.isEmpty { group("Trips", trips) }
        if !unsure.isEmpty {
            Button { withAnimation(.snappy) { showUnsure.toggle() } } label: {
                HStack {
                    Text("NOT SURE · \(unsure.count)").font(Sketch.eyebrow).tracking(0.8)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).rotationEffect(.degrees(showUnsure ? 180 : 0))
                }
                .foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showUnsure { VStack(spacing: 8) { ForEach(unsure) { row($0) } } }
        }
    }

    private func group(_ title: String, _ items: [PhotoFinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title.uppercased()) · \(items.count)").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(BeenPalette.secondary(scheme))
                Spacer()
                let all = items.allSatisfy { chosen.contains($0.id) }
                Button(all ? "Untick all" : "Tick all") { if all { chosen.subtract(items.map(\.id)) } else { chosen.formUnion(items.map(\.id)) } }
                    .font(Sketch.text(12, "Bold", relativeTo: .caption)).frame(minHeight: 44)
            }.padding(.horizontal, 4)
            ForEach(items) { row($0) }
        }
    }

    private func row(_ finding: PhotoFinding) -> some View {
        let on = chosen.contains(finding.id), lived = asLived.contains(finding.id)
        var shown = finding.place; shown.lived = lived ? true : nil
        let had = VisitedPlace.decode(storage).contains { $0.id == finding.id }
        return HStack(spacing: 12) {
            Button {
                TrippyHaptics.selection()
                if on { chosen.remove(finding.id) } else { chosen.insert(finding.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                        .foregroundStyle(on ? BeenLook.lived : BeenPalette.secondary(scheme))
                    PlaceMark(place: shown, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(finding.place.name).font(Sketch.text(15, "Bold", relativeTo: .subheadline)).lineLimit(1)
                            if had { Text("ON MAP").font(.system(size: 8, weight: .heavy)).tracking(0.6).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(BeenPalette.ink(scheme).opacity(0.08))) }
                        }
                        Text(finding.doubt ?? finding.summary).font(Sketch.text(12, relativeTo: .caption))
                            .foregroundStyle(BeenPalette.secondary(scheme)).lineLimit(2).multilineTextAlignment(.leading)
                        if finding.doubt == nil && finding.residence == nil && finding.longest >= 14 {
                            Text("Long stay").font(Sketch.text(10, "Bold", relativeTo: .caption2)).foregroundStyle(BeenPalette.accent(scheme))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(finding.place.name), \(finding.doubt ?? finding.summary)").accessibilityAddTraits(on ? .isSelected : [])
            if !finding.place.isCountry {
                // Your call, always: flip a trip to "lived" or back.
                Button {
                    TrippyHaptics.selection()
                    if lived { asLived.remove(finding.id) } else { asLived.insert(finding.id) }
                } label: {
                    Label(lived ? "Lived" : "Trip", systemImage: lived ? "house.fill" : "suitcase.fill")
                        .font(Sketch.text(11, "Bold", relativeTo: .caption2)).padding(.horizontal, 9).frame(minHeight: 34)
                        .foregroundStyle(lived ? Color.white : BeenPalette.ink(scheme))
                        .background(Capsule().fill(lived ? BeenLook.lived : BeenPalette.ink(scheme).opacity(0.07)))
                }
                .buttonStyle(.plain).frame(minHeight: 44)
                .accessibilityLabel(lived ? "Marked as lived. Change to trip" : "Marked as trip. Change to lived")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 66).beenSurface(radius: 20)
        .opacity(on ? 1 : 0.72)
    }

    private var addBar: some View {
        Button { apply() } label: {
            Text("Add \(chosen.count) \(chosen.count == 1 ? "place" : "places")").font(Sketch.text(16, "Bold", relativeTo: .headline))
                .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(BeenPalette.base(scheme)).background(Capsule().fill(BeenPalette.ink(scheme)))
        }
        .buttonStyle(SketchPressStyle()).padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
        .background(BeenPalette.base(scheme).opacity(0.96))
    }

    // MARK: Work

    private func scan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { phase = .denied; return }
        phase = .scanning
        let loaded = await PhotoTripEngine.librarySamples()
        samples = loaded.samples; total = loaded.total
        analyse()
    }

    private func analyse() {
        let input = samples, count = total, days = livedAfter
        Task {
            let result = await Task.detached(priority: .userInitiated) { PhotoTripEngine.analyse(input, total: count, livedAfterDays: days) }.value
            report = result
            chosen = Set(result.findings.filter { $0.doubt == nil }.map(\.id))
            asLived = Set(result.findings.filter { $0.residence != nil && $0.doubt == nil }.map(\.id))
            withAnimation(.snappy) { phase = .results }
        }
    }

    private func apply() {
        var records = VisitedPlace.decode(storage)
        var stays = BeenStayStore.decode(stayStorage)
        for finding in report.findings where chosen.contains(finding.id) {
            let lived = asLived.contains(finding.id)
            var place = records.first { $0.id == finding.id } ?? finding.place
            // Dates you typed in yourself are kept; everything else follows the photos.
            if place.dated != true || place.auto == true {
                if lived, let range = finding.residence ?? Optional(finding.first...finding.last) {
                    place.setWhen(range.lowerBound, until: range.upperBound, ongoing: Date.now.timeIntervalSince(range.upperBound) < 45 * 86_400)
                } else {
                    place.setWhen(finding.first, until: finding.last)
                }
                place.auto = true
            }
            place.lived = lived ? true : nil
            place.days = finding.photoDays
            place.trips = finding.stays.count
            records = VisitedPlace.saving(place, in: records)
            stays.removeAll { $0.placeID == finding.id }
            stays += finding.stays.map { var s = $0; s.lived = lived; return s }
        }
        storage = VisitedPlace.encode(records)
        stayStorage = BeenStayStore.encode(stays)
        TrippyHaptics.selection()
        dismiss()
    }
}
