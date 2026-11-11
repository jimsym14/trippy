import Foundation
import CoreLocation
import MapKit

// MARK: - Model

enum JourneyMode: String, Codable, CaseIterable, Identifiable {
    case plane, train, car
    var id: String { rawValue }
    var title: String { switch self { case .plane: "Plane"; case .train: "Train"; case .car: "Road trip" } }
    var verb: String { switch self { case .plane: "by plane"; case .train: "by train"; case .car: "by car" } }
    var symbol: String { switch self { case .plane: "airplane"; case .train: "tram.fill"; case .car: "car.fill" } }
}

/// A place on a journey: a catalog destination, a searched city, or an exact address to leave from.
struct JourneyPoint: Codable, Hashable {
    var name: String
    var subtitle = ""
    var latitude: Double
    var longitude: Double
    var countryCode: String?
    /// "g" overland, "f" ferry, "a" air only (see `Destination.access`).
    var access = "g"
    /// 1–3: how many days the place fills. Unknown places count as a city.
    var size = 2
    /// Day cost tier 1–4 when known from the catalog.
    var cost: Int?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(name: String, subtitle: String = "", latitude: Double, longitude: Double, countryCode: String? = nil) {
        self.name = name; self.subtitle = subtitle; self.latitude = latitude; self.longitude = longitude; self.countryCode = countryCode
        // A known destination nearby tells us how to reach it and what it costs.
        if let known = DestinationCatalog.nearest(to: coordinate, within: 45) {
            access = String(known.access); size = known.size; cost = known.cost
            if self.countryCode == nil { self.countryCode = known.countryCode }
        }
    }
    init(_ d: Destination) {
        name = d.planName; subtitle = d.name == d.planName ? d.country : "\(d.name), \(d.country)"; latitude = d.latitude; longitude = d.longitude
        countryCode = d.countryCode; access = String(d.access); size = d.size; cost = d.cost
    }
}

struct JourneyStop: Identifiable, Codable, Hashable {
    var id = UUID()
    var place: JourneyPoint
    var nights = 2
    /// The traveller set the nights by hand; rebalancing leaves them alone.
    var nightsPinned = false
    /// Keeps its position when the order is optimised (a wedding on day 3, a booked first night).
    var locked = false
}

struct JourneyLeg: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let km: Double
    let minutes: Int
    /// Euros for one traveller, one way.
    let cost: Int
    /// What the leg really uses: a ground journey flies when there is no sensible overland way.
    let mode: JourneyMode
    let ferry: Bool
    /// True when the time came from Apple Maps directions rather than an estimate.
    var measured = false

    var duration: String { JourneyEngine.duration(minutes) }
    var distance: String { km >= 100 ? "\(Int((km / 10).rounded()) * 10) km" : "\(Int(km.rounded())) km" }
}

struct JourneyDraft: Codable, Equatable {
    var name = ""
    var origin: JourneyPoint?
    var stops: [JourneyStop] = []
    var mode: JourneyMode = .train
    /// Back to where you started, or home from the last stop.
    var roundTrip = true
    var startDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    var travelers = 2
    var group = "Friends"
    var interests: Set<String> = []
    var pace = "balanced"

    var nights: Int { stops.reduce(0) { $0 + $1.nights } }
    var endDate: Date { Calendar.current.date(byAdding: .day, value: nights, to: startDate) ?? startDate }
    /// Arrival and departure day for each stop, back to back.
    var dates: [(start: Date, end: Date)] {
        var day = startDate
        return stops.map { stop in
            let end = Calendar.current.date(byAdding: .day, value: stop.nights, to: day) ?? day
            defer { day = end }
            return (day, end)
        }
    }
}

struct JourneySummary {
    let legs: [JourneyLeg]
    /// Outbound from the origin and back to it, when there is one.
    let outbound: JourneyLeg?
    let inbound: JourneyLeg?
    var allLegs: [JourneyLeg] { [outbound].compactMap { $0 } + legs + [inbound].compactMap { $0 } }
    var km: Double { allLegs.reduce(0) { $0 + $1.km } }
    var minutes: Int { allLegs.reduce(0) { $0 + $1.minutes } }
    let stayCost: Int
    let travelCost: Int
    var total: Int { stayCost + travelCost }
}

// MARK: - Engine

enum JourneyEngine {
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = (minutes % 60) / 5 * 5
        if h == 0 { return "\(max(m, 5)) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }

    // MARK: Legs

    /// Whether two points can sensibly be joined overland.
    static func overland(_ a: JourneyPoint, _ b: JourneyPoint, km: Double) -> Bool {
        guard a.access != "a", b.access != "a", km <= 2200 else { return false }
        let ca = WorldContinentCatalog.name(for: a.countryCode), cb = WorldContinentCatalog.name(for: b.countryCode)
        if a.countryCode == nil || b.countryCode == nil { return km <= 900 }
        // Europe and Asia share land (Istanbul, Tbilisi); nothing else here does within range.
        return ca == cb || Set([ca, cb]) == ["Europe", "Asia"] && km <= 1500
    }

    /// A door-to-door estimate. Speeds and prices are averages, meant for comparing routes, not booking.
    static func leg(from a: JourneyPoint, to b: JourneyPoint, mode requested: JourneyMode, travelers: Int = 2) -> JourneyLeg {
        let straight = Geo.km(a.coordinate, b.coordinate)
        var mode = requested
        let ground = overland(a, b, km: straight)
        if mode != .plane && !ground { mode = .plane }
        // Nobody flies 150 km.
        if mode == .plane && ground && straight < 220 { mode = .train }
        let ferry = mode != .plane && (a.access == "f" || b.access == "f") && !(a.access == "f" && b.access == "f" && straight < 60)
        var minutes: Double, cost: Double, km = straight
        switch mode {
        case .plane:
            minutes = straight / 790 * 60 + 165                       // check-in, security, transfer at both ends
            cost = 28 + straight * (straight > 3500 ? 0.055 : 0.075)
        case .train:
            km = straight * 1.22
            minutes = km / (km > 250 ? 105 : 80) * 60 + 25
            cost = max(6, km * 0.105)
        case .car:
            km = straight * 1.28
            let driving = km / (km > 120 ? 88 : 62) * 60
            minutes = driving + floor(driving / 120) * 15             // a break every two hours
            cost = km * 0.14 / Double(min(max(travelers, 1), 4))      // fuel and tolls, shared
        }
        if ferry { minutes += 180; cost += 38 }
        return JourneyLeg(from: a.name, to: b.name, km: km, minutes: Int(minutes.rounded()), cost: Int(cost.rounded()), mode: mode, ferry: ferry)
    }

    /// Real driving time and distance from Apple Maps (free), for road trips.
    static func measuredDrive(_ leg: JourneyLeg, from a: JourneyPoint, to b: JourneyPoint, travelers: Int) async -> JourneyLeg? {
        guard leg.mode == .car, !leg.ferry else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.coordinate))
        request.transportType = .automobile
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        let km = route.distance / 1000, driving = route.expectedTravelTime / 60
        var measured = JourneyLeg(from: leg.from, to: leg.to, km: km, minutes: Int((driving + floor(driving / 120) * 15).rounded()),
                                  cost: Int((km * 0.14 / Double(min(max(travelers, 1), 4))).rounded()), mode: .car, ferry: false)
        measured.measured = true
        return measured
    }

    // MARK: Order

    /// Travel minutes for an order of stops, with the trip out and (for a loop) the trip back.
    static func travelMinutes(_ draft: JourneyDraft, order: [JourneyStop]? = nil) -> Int {
        summary(for: draft, order: order).minutes
    }

    /// The order with the least travel time. Locked stops keep their place.
    /// Up to 11 stops it is exact (dynamic programming over subsets); beyond that, 2-opt and or-opt moves.
    static func bestOrder(_ draft: JourneyDraft) -> [JourneyStop] {
        let stops = draft.stops, n = stops.count
        guard n > 1 else { return stops }
        let points = stops.map(\.place)
        var between = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n { for j in 0..<n where i != j {
            between[i][j] = Double(leg(from: points[i], to: points[j], mode: draft.mode, travelers: draft.travelers).minutes)
        } }
        let out = points.map { p in draft.origin.map { Double(leg(from: $0, to: p, mode: draft.mode, travelers: draft.travelers).minutes) } ?? 0 }
        let back = points.map { p in draft.roundTrip ? (draft.origin.map { Double(leg(from: p, to: $0, mode: draft.mode, travelers: draft.travelers).minutes) } ?? 0) : 0 }
        let lockedAt: [Int: Int] = Dictionary(uniqueKeysWithValues: stops.enumerated().filter { $0.element.locked }.map { ($0.offset, $0.offset) })
        let lockedPositions = Dictionary(uniqueKeysWithValues: lockedAt.map { ($0.value, $0.key) })
        func allowed(_ stop: Int, at position: Int) -> Bool {
            if let must = lockedPositions[position] { return must == stop }
            return lockedAt[stop] == nil
        }
        func cost(_ order: [Int]) -> Double {
            var total = out[order[0]] + back[order[n - 1]]
            for k in 1..<n { total += between[order[k - 1]][order[k]] }
            return total
        }

        if n <= 11 {
            let full = 1 << n
            var best = [[Double]](repeating: [Double](repeating: .infinity, count: n), count: full)
            var parent = [[Int8]](repeating: [Int8](repeating: -1, count: n), count: full)
            for i in 0..<n where allowed(i, at: 0) { best[1 << i][i] = out[i] }
            for mask in 1..<full {
                let position = mask.nonzeroBitCount   // the next stop goes here
                guard position < n else { continue }
                for last in 0..<n where mask & (1 << last) != 0 && best[mask][last] < .infinity {
                    for next in 0..<n where mask & (1 << next) == 0 && allowed(next, at: position) {
                        let value = best[mask][last] + between[last][next]
                        if value < best[mask | (1 << next)][next] { best[mask | (1 << next)][next] = value; parent[mask | (1 << next)][next] = Int8(last) }
                    }
                }
            }
            var end = -1, bestTotal = Double.infinity
            for i in 0..<n where best[full - 1][i] + back[i] < bestTotal { bestTotal = best[full - 1][i] + back[i]; end = i }
            guard end >= 0 else { return stops }
            var order: [Int] = [], mask = full - 1, current = end
            while current >= 0 {
                order.append(current)
                let previous = Int(parent[mask][current]); mask &= ~(1 << current); current = previous
            }
            return order.reversed().map { stops[$0] }
        }

        var order = Array(0..<n)
        func valid(_ candidate: [Int]) -> Bool { candidate.enumerated().allSatisfy { allowed($0.element, at: $0.offset) } }
        var improved = true, current = cost(order)
        while improved {
            improved = false
            for i in 0..<n - 1 { for j in i + 1..<n {
                var reversed = order; reversed[i...j].reverse()                 // 2-opt
                if valid(reversed), cost(reversed) < current - 0.5 { order = reversed; current = cost(order); improved = true }
                var moved = order; let stop = moved.remove(at: i); moved.insert(stop, at: j)   // or-opt
                if valid(moved), cost(moved) < current - 0.5 { order = moved; current = cost(order); improved = true }
            } }
        }
        return order.map { stops[$0] }
    }

    // MARK: Nights

    /// Shares `total` nights between stops by how much there is to do; pinned stops keep theirs.
    static func allocate(nights total: Int, to stops: [JourneyStop]) -> [JourneyStop] {
        var result = stops
        let free = result.indices.filter { !result[$0].nightsPinned }
        guard !free.isEmpty else { return result }
        let pinned = result.filter(\.nightsPinned).reduce(0) { $0 + $1.nights }
        let pool = max(free.count, total - pinned)
        let weights = free.map { [1.0, 1.7, 2.5][min(max(result[$0].place.size, 1), 3) - 1] }
        let sum = weights.reduce(0, +)
        // Everyone gets one night, the rest by weight, leftovers to the largest remainders.
        let spare = Double(pool - free.count)
        let shares = weights.map { $0 / sum * spare }
        var given = shares.map { Int($0) }
        var left = pool - free.count - given.reduce(0, +)
        for index in shares.indices.sorted(by: { shares[$0] - Double(given[$0]) > shares[$1] - Double(given[$1]) }) where left > 0 { given[index] += 1; left -= 1 }
        for (k, index) in free.enumerated() { result[index].nights = 1 + given[k] }
        return result
    }

    // MARK: Totals

    static func summary(for draft: JourneyDraft, order: [JourneyStop]? = nil, measured: [String: JourneyLeg] = [:]) -> JourneySummary {
        let stops = order ?? draft.stops
        func make(_ a: JourneyPoint, _ b: JourneyPoint) -> JourneyLeg {
            measured[legKey(a, b, draft.mode)] ?? leg(from: a, to: b, mode: draft.mode, travelers: draft.travelers)
        }
        let legs = zip(stops, stops.dropFirst()).map { make($0.place, $1.place) }
        let outbound = draft.origin.flatMap { o in stops.first.map { make(o, $0.place) } }
        // One way still means getting home: straight from the last stop.
        let inbound = draft.origin.flatMap { o in stops.last.map { make($0.place, o) } }
        let stay = stops.reduce(0) { $0 + $1.nights * dailyCost($1.place) } * max(draft.travelers, 1)
        let travel = ([outbound].compactMap { $0 } + legs + [inbound].compactMap { $0 }).reduce(0) { $0 + $1.cost } * max(draft.travelers, 1)
        return JourneySummary(legs: legs, outbound: outbound, inbound: stops.count > 0 ? inbound : nil, stayCost: stay, travelCost: travel)
    }

    static func legKey(_ a: JourneyPoint, _ b: JourneyPoint, _ mode: JourneyMode) -> String {
        String(format: "%.3f,%.3f>%.3f,%.3f|%@", a.latitude, a.longitude, b.latitude, b.longitude, mode.rawValue)
    }

    static func dailyCost(_ point: JourneyPoint) -> Int { [55, 90, 140, 210][min(max(point.cost ?? 2, 1), 4) - 1] }

    /// Catalog places that add little travel to the route, best first.
    static func stopsOnTheWay(_ draft: JourneyDraft, taste: TasteProfile, limit: Int = 8) -> [Destination] {
        let chain = [draft.origin].compactMap { $0 } + draft.stops.map(\.place) + (draft.roundTrip ? [draft.origin].compactMap { $0 } : [])
        guard !chain.isEmpty else { return [] }
        let have = draft.stops.map(\.place)
        let reach: Double = draft.mode == .plane ? 1600 : draft.mode == .train ? 700 : 450
        return DestinationCatalog.all.compactMap { d -> (Destination, Double)? in
            let p = JourneyPoint(d)
            guard !have.contains(where: { Geo.km($0.coordinate, d.coordinate) < 40 }) else { return nil }
            guard chain.map({ Geo.km($0.coordinate, d.coordinate) }).min() ?? .infinity <= reach else { return nil }
            if draft.mode != .plane, !chain.contains(where: { overland($0, p, km: Geo.km($0.coordinate, d.coordinate)) }) { return nil }
            // Cheapest place to slot it in.
            var detour = Double.infinity
            if chain.count == 1 { detour = Double(leg(from: chain[0], to: p, mode: draft.mode).minutes) }
            for (a, b) in zip(chain, chain.dropFirst()) {
                let extra = leg(from: a, to: p, mode: draft.mode).minutes + leg(from: p, to: b, mode: draft.mode).minutes - leg(from: a, to: b, mode: draft.mode).minutes
                detour = min(detour, Double(extra))
            }
            return (d, Double(taste.match(d)) - detour / 600)
        }
        .sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

// MARK: - Taste

/// What the traveller likes, learned on the phone from what they pick. Nothing leaves the device.
struct TasteProfile: Codable, Equatable {
    /// One weight per `TripTrait`, 0…1. Everything starts in the middle.
    var weights = [Float](repeating: 0.5, count: TripTrait.allCases.count)
    var duels = 0

    private static let key = "trippy.taste.v1"
    static func load() -> TasteProfile {
        guard let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(TasteProfile.self, from: data),
              saved.weights.count == TripTrait.allCases.count else { return TasteProfile() }
        return saved
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) } }

    /// "This one, not that one": move towards what the winner has more of.
    mutating func prefer(_ winner: Destination, over loser: Destination) {
        let rate: Float = duels < 6 ? 0.22 : 0.12   // learn fast at first, then settle
        for i in weights.indices { weights[i] = min(1, max(0, weights[i] + rate * (winner.traits[i] - loser.traits[i]) / 3)) }
        duels += 1
    }
    /// A plan was made for this place: a smaller nudge the same way.
    mutating func reinforce(_ chosen: Destination) {
        for i in weights.indices { weights[i] = min(1, max(0, weights[i] + 0.05 * (chosen.traits[i] / 3 - 0.5))) }
    }

    /// 0…1: how well a place fits, as the cosine between taste and what the place offers.
    func match(_ d: Destination, boosted: Set<TripTrait> = [], history: [Float]? = nil) -> Float {
        var w = weights
        if !boosted.isEmpty { for t in TripTrait.allCases { w[t.rawValue] = boosted.contains(t) ? w[t.rawValue] + 0.9 : w[t.rawValue] * 0.45 } }
        if let history { for i in w.indices { w[i] += 0.25 * history[i] } }
        var dot: Float = 0, a: Float = 0, b: Float = 0
        for i in w.indices { dot += w[i] * d.traits[i]; a += w[i] * w[i]; b += d.traits[i] * d.traits[i] }
        return a > 0 && b > 0 ? dot / (a.squareRoot() * b.squareRoot()) : 0
    }

    /// The traits that count most right now, for explaining a pick.
    func strongest(_ d: Destination, boosted: Set<TripTrait>) -> [TripTrait] {
        TripTrait.allCases.filter { d.trait($0) >= 2 }
            .sorted { (weights[$0.rawValue] + (boosted.contains($0) ? 1 : 0)) * d.trait($0) > (weights[$1.rawValue] + (boosted.contains($1) ? 1 : 0)) * d.trait($1) }
    }
}

// MARK: - Where next

struct WhereNextQuery: Equatable {
    var origin: JourneyPoint?
    /// 1–12, or nil for any time.
    var month: Int? = Calendar.current.component(.month, from: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
    var days = 5
    /// Euros per person per day, or nil for no limit.
    var budget: Int?
    /// nil lets each pick use whatever is quickest.
    var mode: JourneyMode?
    var newPlacesOnly = true
    var travelers = 2
    var wants: Set<TripTrait> = []
    // Answers from the brief (WhereNextBrief.swift). The defaults change nothing.
    /// Every month the trip could fall in. Empty means `month` alone (or any time).
    var months: Set<Int> = []
    var region: TripRegion = .anywhere
    var setting: TripSetting?
    var climate: TripClimate?
    var ski = false
    /// False when the traveller doesn't mind going back somewhere: being new then earns nothing.
    var noveltyCounts = true

    /// The months to judge a place by.
    var window: Set<Int> { months.isEmpty ? Set(month.map { [$0] } ?? []) : months }
}

struct Recommendation: Identifiable, Equatable {
    let destination: Destination
    /// 0…1 overall.
    let score: Double
    let leg: JourneyLeg?
    let reasons: [String]
    let caution: String?
    /// Rough total for everyone: getting there and back plus the days.
    let total: Int
    var id: String { destination.id }
    var percent: Int { Int((score * 100).rounded()) }
    static func == (a: Recommendation, b: Recommendation) -> Bool { a.id == b.id && a.score == b.score }
}

enum WhereNextEngine {
    private static let monthNames = TripMonth.names

    /// What past visits say about taste: the average of the known places already visited.
    static func history(_ visits: [VisitedPlace]) -> [Float]? {
        let known = visits.compactMap { DestinationCatalog.nearest(to: $0.coordinate, within: 60) }
        guard known.count >= 2 else { return nil }
        var mean = [Float](repeating: 0, count: TripTrait.allCases.count)
        for d in known { for i in mean.indices { mean[i] += d.traits[i] / 3 / Float(known.count) } }
        return mean
    }

    /// Picks the leg a traveller would really take when they have no preference.
    static func bestLeg(from origin: JourneyPoint, to d: Destination, mode: JourneyMode?, travelers: Int) -> JourneyLeg {
        let target = JourneyPoint(d)
        if let mode { return JourneyEngine.leg(from: origin, to: target, mode: mode, travelers: travelers) }
        let plane = JourneyEngine.leg(from: origin, to: target, mode: .plane, travelers: travelers)
        let train = JourneyEngine.leg(from: origin, to: target, mode: .train, travelers: travelers)
        // The train wins when it is about as quick: no airport, city centre to city centre.
        return train.mode == .train && Double(train.minutes) <= Double(plane.minutes) * 1.2 ? train : plane
    }

    /// `only` scores a single named place instead of the whole catalog (the "somewhere in mind" check).
    static func recommend(_ query: WhereNextQuery, taste: TasteProfile, visits: [VisitedPlace], limit: Int = 10, only: Destination? = nil) -> [Recommendation] {
        let history = history(visits)
        let visitedCountries = Set(visits.compactMap { $0.countryCode?.uppercased() })
        let visitedContinents = Set(visitedCountries.map { WorldContinentCatalog.name(for: $0) })
        // How long a trip out is worth it: three quarters of an hour of travel per day away.
        let comfortable = Double(query.days) * 45 + 60

        var scored: [Recommendation] = []
        for d in only.map({ [$0] }) ?? DestinationCatalog.all {
            let beenThere = visits.contains { Geo.km($0.coordinate, d.coordinate) < 40 }
            if beenThere && query.newPlacesOnly { continue }
            // Where in the world: a hard choice, so places outside it are left out.
            let homeContinent = WorldContinentCatalog.name(for: query.origin?.countryCode ?? "GR")
            switch query.region {
            case .europe: if d.continent != "Europe" { continue }
            case .far: if d.continent == homeContinent { continue }
            case .near, .anywhere: break
            }
            if query.ski && !d.skiArea { continue }
            var leg: JourneyLeg?
            var travelFit = 0.7
            if let origin = query.origin {
                if Geo.km(origin.coordinate, d.coordinate) < 60 { continue }   // that's home
                let l = bestLeg(from: origin, to: d, mode: query.mode, travelers: query.travelers)
                if let wanted = query.mode, l.mode != wanted { continue }       // not reachable that way
                let ratio = Double(l.minutes) / comfortable
                if ratio > 2.4 { continue }
                travelFit = ratio <= 1 ? 1 : max(0, 1 - (ratio - 1) / 1.4)
                if query.region == .near && l.minutes > 300 { continue }   // "close to home": five hours door to door at most
                leg = l
            } else if query.mode != nil && d.access == "a" { continue }

            let tasteFit = Double(taste.match(d, boosted: query.wants, history: history))
            // With a window of months the place is judged by its best month in it, and that month is the one named.
            var seasonFit = 0.7
            let window = query.window
            var bestMonth = query.month
            if !window.isEmpty {
                func fit(_ month: Int) -> Double {
                    let near = d.months.contains(month == 12 ? 1 : month + 1) || d.months.contains(month == 1 ? 12 : month - 1)
                    return d.months.contains(month) ? 1 : near ? 0.55 : 0.12
                }
                // Among equally good months, the one that suits the weather asked for.
                bestMonth = window.sorted().max { (fit($0), d.climateFit(query.climate, month: $0)) < (fit($1), d.climateFit(query.climate, month: $1)) }
                seasonFit = bestMonth.map(fit) ?? 0.7
            }
            // What the brief asked for beyond taste: the kind of place, and the weather.
            var asked: [Double] = []
            if let setting = query.setting { asked.append(d.settingFit(setting)) }
            if let climate = query.climate, let month = bestMonth {
                let fit = d.climateFit(climate, month: month)
                if fit < 0.15 { continue }   // snow was asked for and it is 28° there, or the reverse
                asked.append(fit)
            }
            if query.ski { asked.append(bestMonth.map { d.snowLikely($0) ? 1 : 0.2 } ?? 0.6) }
            var budgetFit = 0.75
            if let budget = query.budget {
                let ratio = Double(d.dailyCost) / Double(budget)
                budgetFit = ratio <= 1 ? 1 : max(0, 1 - (ratio - 1) * 1.6)
            }
            let newCountry = !visitedCountries.contains(d.countryCode)
            let novelty = !query.noveltyCounts ? 0.6 : beenThere ? 0 : newCountry ? (visitedContinents.contains(d.continent) || visitedCountries.isEmpty ? 0.85 : 1) : 0.5
            // A two-week trip to a village, or a weekend in a place that needs a week, fits less well.
            let wantedDays = [2.5, 4, 6.5][d.size - 1]
            let lengthFit = max(0.4, 1 - abs(Double(query.days) - wantedDays) / 12)

            var score = 0.4 * tasteFit + 0.19 * seasonFit + 0.13 * budgetFit + 0.13 * travelFit + 0.09 * novelty + 0.06 * lengthFit
            if !asked.isEmpty { score = 0.72 * score + 0.28 * asked.reduce(0, +) / Double(asked.count) }

            var reasons: [String] = []
            let strong = taste.strongest(d, boosted: query.wants).prefix(2).map(\.short)
            if !strong.isEmpty { reasons.append("Strong on " + strong.joined(separator: " and ")) }
            if let month = bestMonth, d.months.contains(month) { reasons.append("At its best in \(monthNames[month - 1])") }
            if let month = bestMonth, let weather = d.weatherLine(month, wanted: query.climate) { reasons.append(weather) }
            if let leg { reasons.append("\(leg.duration) \(leg.mode.verb)" + (leg.ferry ? " and ferry" : "")) }
            if newCountry && !visitedCountries.isEmpty && query.noveltyCounts { reasons.append("A new country for you") }
            var caution: String?
            if let month = bestMonth, seasonFit < 0.5 { caution = "Not its best time in \(monthNames[month - 1])" }
            else if let budget = query.budget, d.dailyCost > budget { caution = "Around €\(d.dailyCost) a day, above your €\(budget)" }
            let total = (d.dailyCost * query.days + (leg?.cost ?? 0) * 2) * max(query.travelers, 1)
            scored.append(Recommendation(destination: d, score: score, leg: leg, reasons: reasons, caution: caution, total: total))
        }

        if only != nil { return scored }
        // Maximal marginal relevance: each next pick is good and unlike the ones already chosen.
        func similarity(_ a: Destination, _ b: Destination) -> Double {
            var dot: Float = 0, x: Float = 0, y: Float = 0
            for i in a.traits.indices { dot += a.traits[i] * b.traits[i]; x += a.traits[i] * a.traits[i]; y += b.traits[i] * b.traits[i] }
            let alike = Double(dot / max(0.001, x.squareRoot() * y.squareRoot()))
            return min(1, 0.55 * alike + (a.countryCode == b.countryCode ? 0.35 : 0) + (Geo.km(a.coordinate, b.coordinate) < 200 ? 0.2 : 0))
        }
        var pool = scored.sorted { $0.score > $1.score }.prefix(60).map { $0 }
        var chosen: [Recommendation] = []
        while chosen.count < limit, !pool.isEmpty {
            let index = pool.indices.max { a, b in
                func value(_ r: Recommendation) -> Double { 0.74 * r.score - 0.26 * (chosen.map { similarity($0.destination, r.destination) }.max() ?? 0) }
                return value(pool[a]) < value(pool[b])
            }!
            chosen.append(pool.remove(at: index))
        }
        return chosen
    }

    /// Two places that differ a lot, so one answer says the most about taste.
    static func duel(from picks: [Recommendation], round: Int) -> (Destination, Destination)? {
        let pool = picks.map(\.destination)
        guard pool.count >= 2 else { return nil }
        var pairs: [(Destination, Destination, Float)] = []
        for i in pool.indices { for j in pool.indices where j > i {
            let distance = zip(pool[i].traits, pool[j].traits).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }
            pairs.append((pool[i], pool[j], distance))
        } }
        let ranked = pairs.sorted { $0.2 > $1.2 }
        let pick = ranked[round % min(ranked.count, 8)]
        return (pick.0, pick.1)
    }

    /// A multi-stop route around one pick: nearby places that fit, in the quickest order, nights shared out.
    static func route(around anchor: Destination, query: WhereNextQuery, mode: JourneyMode, taste: TasteProfile, visits: [VisitedPlace]) -> JourneyDraft {
        var draft = JourneyDraft()
        draft.origin = query.origin; draft.mode = mode; draft.travelers = query.travelers
        draft.name = mode == .car ? "\(anchor.name) road trip" : mode == .train ? "\(anchor.name) by rail" : "\(anchor.name) and around"
        let wanted = min(5, max(2, query.days / 3))
        let reach: Double = mode == .plane ? 900 : mode == .train ? 650 : 420
        let history = history(visits)
        var stops = [JourneyPoint(anchor)]
        var pool = DestinationCatalog.all.filter { d in
            d.id != anchor.id && Geo.km(anchor.coordinate, d.coordinate) <= reach
                && (mode == .plane || JourneyEngine.overland(JourneyPoint(anchor), JourneyPoint(d), km: Geo.km(anchor.coordinate, d.coordinate)))
                && !(query.newPlacesOnly && visits.contains { Geo.km($0.coordinate, d.coordinate) < 40 })
                && (query.month.map { m in d.months.contains(m) || d.months.contains(m % 12 + 1) } ?? true)
        }
        while stops.count < wanted, !pool.isEmpty {
            // Greedy insertion: the best fit for the least extra travel.
            let index = pool.indices.max { a, b in
                func value(_ d: Destination) -> Double {
                    let p = JourneyPoint(d)
                    let extra = stops.map { JourneyEngine.leg(from: $0, to: p, mode: mode).minutes }.min() ?? 0
                    return Double(taste.match(d, boosted: query.wants, history: history)) - Double(extra) / 500
                        - (stops.contains { Geo.km($0.coordinate, d.coordinate) < 60 } ? 1 : 0)
                }
                return value(pool[a]) < value(pool[b])
            }!
            stops.append(JourneyPoint(pool.remove(at: index)))
        }
        draft.stops = stops.map { JourneyStop(place: $0) }
        draft.stops = JourneyEngine.bestOrder(draft)
        draft.stops = JourneyEngine.allocate(nights: max(draft.stops.count, query.days - 1), to: draft.stops)
        if let month = query.month {
            var parts = Calendar.current.dateComponents([.year, .month], from: .now)
            if (parts.month ?? 1) >= month { parts.year = (parts.year ?? 2026) + 1 }
            parts.month = month; parts.day = 10
            if let date = Calendar.current.date(from: parts) { draft.startDate = date }
        }
        return draft
    }
}

// MARK: - Saved journeys

/// A journey that was turned into trips: one trip per stop, in order.
struct SavedJourney: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mode: JourneyMode
    var origin: String?
    var tripIDs: [UUID]
    var cities: [String]
    var startDate: String
    var endDate: String
}

enum JourneyStore {
    private static let key = "trippy.journeys.v1"
    static func load() -> [SavedJourney] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedJourney].self, from: $0) } ?? []
    }
    static func save(_ journeys: [SavedJourney]) {
        if let data = try? JSONEncoder().encode(journeys) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func add(_ journey: SavedJourney) { save([journey] + load()) }
    /// Without trips that no longer exist; journeys left with fewer than two stops go.
    static func pruned(_ all: [SavedJourney], keeping tripIDs: Set<UUID>) -> [SavedJourney] {
        all.compactMap { j -> SavedJourney? in
            var j = j
            let keep = j.tripIDs.indices.filter { tripIDs.contains(j.tripIDs[$0]) }
            guard keep.count >= 2 else { return nil }
            j.cities = keep.compactMap { $0 < j.cities.count ? j.cities[$0] : nil }; j.tripIDs = keep.map { j.tripIDs[$0] }
            return j
        }
    }
}

/// English month names, whatever the phone's language (the app's text is English).
enum TripMonth {
    private static let formatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); return f }()
    static let names: [String] = formatter.monthSymbols
    static let short: [String] = formatter.shortMonthSymbols
}
