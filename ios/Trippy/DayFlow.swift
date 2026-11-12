import Foundation

/// Deterministic day timing on the phone: no network, no model.
///
/// Stops with a fixed time (booked, or a time the traveller typed) stay where they are; every other
/// stop keeps its order and flows around them, later when it has to, never earlier. Each stop that
/// moves says why. The same file also finds a shorter walking order between the fixed points.
/// Foundation only, so `tests/ios/day_flow_check.swift` can compile it on its own.
enum DayFlow {
    struct Item: Hashable {
        let id: String
        let name: String
        /// Planned start, minutes after midnight.
        var start: Int
        let duration: Int
        /// The traveller typed this time.
        var fixed = false
        /// Tickets or a table are booked: fixed too, and said so.
        var booked = false
        var latitude: Double? = nil
        var longitude: Double? = nil
        /// The planner's own leg into this stop, kept while the stop before it is still the planner's.
        var plannedPrevious: String? = nil
        var plannedTravel: Int? = nil
        /// Sights can trade places on a shorter route; meals, blocks and fixed stops can't.
        var reorderable = true

        var isFixed: Bool { fixed || booked }
        var end: Int { start + duration }
    }

    struct Placement: Hashable {
        let id: String
        let start: Int
        /// Where it was before the day flowed.
        let planned: Int
        /// Why it moved, or why it no longer fits; nil when nothing changed.
        let reason: String?
        /// False when it clashes with a fixed stop or runs past the end of the day.
        let fits: Bool
        var moved: Bool { start != planned }
    }

    /// A limit on the day: the earliest start (after landing) or the latest end (leaving for a flight).
    struct Limit: Hashable {
        let minutes: Int
        /// "after you reach your stay", "before you leave for the airport at 14:00"
        let because: String
    }

    // MARK: Travel

    static func metres(_ a: Item, _ b: Item) -> Double? {
        guard let la = a.latitude, let oa = a.longitude, let lb = b.latitude, let ob = b.longitude else { return nil }
        let r = Double.pi / 180
        let dlat = (lb - la) * r, dlon = (ob - oa) * r
        let h = sin(dlat / 2) * sin(dlat / 2) + cos(la * r) * cos(lb * r) * sin(dlon / 2) * sin(dlon / 2)
        return 6_371_000 * 2 * asin(min(1, sqrt(h)))
    }

    /// Door to door as the planner estimates it: a walk under 2.5 km, a ride beyond.
    static func estimate(_ metres: Double) -> Int {
        if metres > 2500 { return Int((metres / 1000 / 25 * 60).rounded(.up)) + 12 }
        return Int((metres / 1000 / 4 * 60).rounded(.up)) + (metres < 1000 ? 5 : 10)
    }

    /// The planner's leg when the stop before is still the planner's, else an estimate (15 min with no coordinates).
    static func travel(_ a: Item, _ b: Item) -> Int {
        if b.plannedPrevious == a.id, let t = b.plannedTravel { return t }
        return metres(a, b).map(estimate) ?? 15
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }

    static func describe(_ fixed: Item) -> String {
        fixed.booked ? "after your \(fixed.name) booking at \(clock(fixed.start))"
                     : "after \(fixed.name) at \(clock(fixed.start)), the time you set"
    }

    // MARK: Re-flow

    /// Fixed stops keep their time. Every other stop keeps its order and starts at its planned time,
    /// or once the stop before it ends and the walk over is done, whichever is later. A stop that would
    /// run into a fixed one goes after it. Nothing moves earlier, so an untouched day stays as planned.
    static func reflow(_ items: [Item], earliest: Limit? = nil, latest: Limit? = nil) -> [Placement] {
        let ordered = items.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        var fixedQueue = ordered.filter(\.isFixed)
        let flexible = ordered.filter { !$0.isFixed }
        // Nothing to flow around and nothing outside the day: the plan stands as it is.
        let outside = flexible.contains { s in (earliest.map { s.start < $0.minutes } ?? false) || (latest.map { s.end > $0.minutes } ?? false) }
        if fixedQueue.isEmpty && !outside {
            return ordered.map { Placement(id: $0.id, start: $0.start, planned: $0.start, reason: nil, fits: true) }
        }
        var out: [Placement] = []
        var previous: Item? = nil
        var previousEnd = 0
        var previousCause: String? = nil   // why the stop before moved: passed on to what it pushes

        func emitFixed(_ f: Item) {
            var reason: String? = nil
            if let p = previous, previousEnd + travel(p, f) > f.start {
                reason = "Clashes with \(p.name), which ends at \(clock(previousEnd))"
            } else if let latest, f.end > latest.minutes {
                reason = "Runs past the time \(latest.because)"
            }
            out.append(Placement(id: f.id, start: f.start, planned: f.start, reason: reason, fits: reason == nil))
            previous = f; previousEnd = max(previousEnd, f.end); previousCause = describe(f)
        }

        for item in flexible {
            var start = item.start
            var cause: String? = nil
            if let earliest, start < earliest.minutes { start = earliest.minutes; cause = earliest.because }
            if let p = previous {
                let ready = previousEnd + travel(p, item)
                if ready > start { start = ready; cause = previousCause }
            }
            // A fixed stop it would run into (or one that already started) comes first. One it ends
            // before, with only the walk short, stays after it: a tight walk beats breakfast at noon.
            var tight: String? = nil
            if let f = fixedQueue.first, start + item.duration <= f.start, start + item.duration + travel(item, f) > f.start {
                tight = "Leaves \(max(0, f.start - start - item.duration)) min to get to \(f.name) for \(clock(f.start))"
            }
            while tight == nil, let f = fixedQueue.first, start + item.duration + travel(item, f) > f.start {
                fixedQueue.removeFirst()
                emitFixed(f)
                let ready = previousEnd + travel(f, item)
                if ready > start { start = ready; cause = describe(f) }
            }
            // A moved stop starts on a round five minutes: 11:50, not 11:49.
            if start != item.start { start = (start + 4) / 5 * 5 }
            var reason: String? = nil
            var fits = true
            if let latest, start + item.duration > latest.minutes {
                fits = false
                reason = "No time for this \(latest.because)"
            } else if start != item.start {
                reason = "Moved from \(clock(item.start)), " + (cause ?? "so there is time to get here")
                if let tight { reason! += ". " + tight }
            } else if let tight {
                reason = tight
            }
            out.append(Placement(id: item.id, start: start, planned: item.start, reason: reason, fits: fits))
            previous = item; previousEnd = start + item.duration
            previousCause = start != item.start ? cause : nil
        }
        fixedQueue.forEach(emitFixed)
        return out
    }

    // MARK: Shorter route

    struct Reorder: Hashable {
        /// The whole day's ids in the new order.
        let order: [String]
        /// Minutes of walking or riding saved.
        let saved: Int
        /// The first two sights that change places, for the button: ("Casa Batlló", "La Pedrera").
        let first: (String, String)
        static func == (a: Reorder, b: Reorder) -> Bool { a.order == b.order && a.saved == b.saved }
        func hash(into h: inout Hasher) { h.combine(order); h.combine(saved) }
    }

    /// Sights between two fixed points (a meal, a booking, the stay) visited in the order that walks least.
    /// Runs of up to six sights are tried every way round; nothing is suggested under `atLeast` minutes saved.
    static func shorterRoute(_ items: [Item], start home: Item? = nil, atLeast: Int = 10) -> Reorder? {
        let ordered = items.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        func leg(_ a: Item?, _ b: Item?) -> Int {
            guard let a, let b else { return 0 }
            return metres(a, b).map(estimate) ?? 0
        }
        var result: [Item] = []
        var saved = 0
        var swapped: (String, String)? = nil
        var index = 0
        while index < ordered.count {
            guard ordered[index].reorderable && !ordered[index].isFixed && ordered[index].latitude != nil else {
                result.append(ordered[index]); index += 1; continue
            }
            var run: [Item] = []
            while index < ordered.count, ordered[index].reorderable, !ordered[index].isFixed, ordered[index].latitude != nil {
                run.append(ordered[index]); index += 1
            }
            let before = result.last ?? home
            let after = index < ordered.count ? ordered[index] : nil
            func cost(_ seq: [Item]) -> Int {
                var total = leg(before, seq.first), last = seq.first
                for s in seq.dropFirst() { total += leg(last, s); last = s }
                return total + leg(last, after)
            }
            var best = run, bestCost = cost(run)
            if run.count >= 2 && run.count <= 6 {
                for candidate in permutations(run) {
                    let c = cost(candidate)
                    // Ties keep the planned order: only a real saving changes the day.
                    if c < bestCost { best = candidate; bestCost = c }
                }
            }
            let gain = cost(run) - bestCost
            if gain > 0 {
                saved += gain
                if swapped == nil, let i = run.indices.first(where: { run[$0].id != best[$0].id }) {
                    swapped = (best[i].name, run[i].name)
                }
            }
            result += best
        }
        guard saved >= atLeast, let swapped else { return nil }
        return Reorder(order: result.map(\.id), saved: saved, first: swapped)
    }

    static func permutations(_ items: [Item]) -> [[Item]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[Item]] in
            var rest = items; let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    // MARK: Leaving and arriving

    /// Two hours at the airport and about one to get there: the planner stops the last day three hours before a flight.
    static let airportMinutes = 180

    /// "Leave by 14:00 for your 17:00 flight", with what it is made of and what still runs into it.
    static func leaveBy(departure: Int, lastEnd: Int?, lastName: String?) -> (title: String, detail: String, late: Bool) {
        let leave = departure - airportMinutes
        let title = "Leave by \(clock(leave)) for your \(clock(departure)) flight"
        if let lastEnd, let lastName, lastEnd > leave {
            return (title, "\(lastName) ends at \(clock(lastEnd)). Cut it short or drop it: you need about an hour to the airport and two hours there.", true)
        }
        return (title, "About an hour to the airport and two hours there. Collect your bags from the stay before.", false)
    }
}
