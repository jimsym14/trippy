import Foundation
import CoreLocation

struct GuideInput {
    let tripID: UUID
    let title: String
    let destination: String
    let startDate: String
    let endDate: String
    let travelers: Int
    let research: String
    var travelMode = "plane"
}

struct ResolvedStop: Identifiable, Hashable {
    var id: String { key }
    let key: String            // "date|itemID"
    let itemID: String         // what the day's order stores: a place id or a "slot:kind:…" id
    let place: GuidePlace
    let time: String
    let durationMinutes: Int
    let travelMinutes: Int?
    let alternatives: [GuidePlace]
    let note: String
    let added: Bool
    var why = ""
    var tip = ""
    var slot: ResolvedSlot? = nil
    /// Minutes from the base, on the day's first stop.
    var fromBaseMinutes: Int? = nil
    /// Names of the sights seen in the same visit.
    var includes: [String] = []
}

/// One tap that improves a day; the traveller can always ignore it.
struct GuideSuggestion: Identifiable, Hashable {
    enum Action: Hashable { case addBlock(SlotKind), addPlace(String), restore(String) }
    let id: String
    let text: String
    let detail: String
    let symbol: String
    let action: Action
}

/// A meal or coffee block: a kind, the area it fits in, and the place picked for it (if any).
struct ResolvedSlot: Hashable {
    let kind: SlotKind
    let latitude: Double?
    let longitude: Double?
    let pickedID: String?      // nil = decide later
    let suggestedID: String?   // the planner's own pick
}

struct ResolvedDay: Identifiable, Hashable {
    var id: String { date }
    let index: Int
    let date: String
    let title: String
    let subtitle: String
    let stops: [ResolvedStop]
    let holiday: GuideHoliday?
    var areaIDs: [String] = []
}

struct ChecklistItem: Identifiable, Hashable {
    let id: String
    let text: String
    let group: String
    let custom: Bool
}

/// Everything the guide shows, derived from the plan and the traveler's edits.
struct GuideContext {
    let model: GuideModel
    let edits: GuideEdits
    let input: GuideInput
    let holidays: [GuideHoliday]
    let days: [ResolvedDay]

    let base: GuideBase?

    init(model: GuideModel, edits: GuideEdits, input: GuideInput, holidays: [GuideHoliday]) {
        self.model = model; self.edits = edits; self.input = input; self.holidays = holidays
        // The stay the traveller typed wins over the one the plan was made from.
        if let lat = edits.flight.stayLatitude, let lon = edits.flight.stayLongitude, !edits.flight.stayName.isEmpty {
            base = GuideBase(name: edits.flight.stayName, latitude: lat, longitude: lon)
        } else { base = model.base }
        let base = self.base
        days = model.days.map { GuideContext.resolve($0, model: model, edits: edits, holidays: holidays, base: base) }
    }

    /// A rough door-to-door time: walking under 2.5 km, a ride beyond (as the planner estimates).
    static func minutes(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Int {
        let metres = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return metres > 2500 ? Int((metres / 1000 / 25 * 60).rounded(.up)) + 12 : Int((metres / 1000 / 4 * 60).rounded(.up)) + 10
    }

    func areas(of day: ResolvedDay) -> [GuideArea] { day.areaIDs.compactMap { id in model.areas.first { $0.id == id } } }

    /// Planner stops the traveller removed and didn't move to another day.
    var leftOut: [(date: String, place: GuidePlace)] {
        let present = Set(days.flatMap { $0.stops.map(\.itemID) })
        var out: [(String, GuidePlace)] = []
        for day in model.days where edits.order[day.date] != nil {
            for stop in day.stops where !present.contains(stop.placeID) {
                if let place = model.places[stop.placeID] { out.append((day.date, place)) }
            }
        }
        return out
    }

    /// Unused places in the day's own areas, best known first.
    func unusedInAreas(of day: ResolvedDay) -> [GuidePlace] {
        let used = Set(days.flatMap { $0.stops.map(\.place.id) })
        return areas(of: day).flatMap(\.placeIDs).filter { !used.contains($0) }.compactMap { model.places[$0] }
            .sorted { ($0.fame, $0.name) > ($1.fame, $1.name) }
    }

    /// A free or food-only day still gets something easy to do: the best-known sights
    /// nobody planned, closest to the stay first. They are ideas, never added on their own.
    func freeDayIdeas(for day: ResolvedDay) -> [GuideSuggestion] {
        let included = Set(model.days.flatMap { $0.stops.flatMap(\.includes) })
        let used = Set(days.flatMap { $0.stops.map(\.place.id) }).union(included)
        let home = base.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        func metres(_ p: GuidePlace) -> Double {
            guard let home, let c = p.coordinate else { return 5_000 }
            return home.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }
        let pool = model.places.values.filter { !used.contains($0.id) && !$0.isFood && $0.coordinate != nil && !$0.isSlotPlaceholder }
        let ranked = pool.sorted { (Double($0.fame) - metres($0) / 60, $0.name) > (Double($1.fame) - metres($1) / 60, $1.name) }
        return ranked.prefix(4).map { place in
            let walk = home != nil ? "\(max(1, Int((metres(place) / 80).rounded()))) min from your stay" : place.categoryLabel
            return GuideSuggestion(id: "idea|\(place.id)", text: place.name,
                                   detail: place.reason.isEmpty ? walk : "\(place.reason) · \(walk)",
                                   symbol: place.symbol, action: .addPlace(place.id))
        }
    }

    /// At most three gentle suggestions for a day, most useful first.
    func suggestions(for day: ResolvedDay) -> [GuideSuggestion] {
        var out: [GuideSuggestion] = []
        for (date, place) in leftOut where date == day.date {
            out.append(.init(id: "restore|\(place.id)", text: "Put back \(place.name)", detail: "You removed it", symbol: "arrow.uturn.backward", action: .restore(place.id)))
        }
        let kinds = Set(day.stops.compactMap(\.slot?.kind))
        let starts = day.stops.compactMap { GuideDates.minutes($0.time) }
        let span = (starts.min() ?? 0, (starts.max() ?? 0))
        if !kinds.contains(.lunch), span.0 < 13 * 60, span.1 > 14 * 60 {
            out.append(.init(id: "lunch", text: "Add lunch", detail: "Nothing to eat at midday", symbol: SlotKind.lunch.symbol, action: .addBlock(.lunch)))
        }
        if !kinds.contains(.dinner), span.1 >= 17 * 60 {
            out.append(.init(id: "dinner", text: "Add dinner", detail: "The evening has no meal", symbol: SlotKind.dinner.symbol, action: .addBlock(.dinner)))
        }
        let sights = day.stops.filter { $0.slot == nil && !$0.place.isFood }.count
        if sights < 3, let next = unusedInAreas(of: day).first {
            let area = areas(of: day).first { $0.placeIDs.contains(next.id) }?.name
            out.append(.init(id: "add|\(next.id)", text: "Add \(next.name)", detail: area.map { "Also in \($0)" } ?? "Close by", symbol: "plus", action: .addPlace(next.id)))
        }
        return Array(out.prefix(3))
    }

    /// The day's order of item ids, with an afternoon coffee break added when the plan has none.
    static func baseOrder(_ day: GuideDay, model: GuideModel) -> [String] {
        var ids = day.stops.map(\.placeID)
        let hasBreak = day.stops.contains { ["coffee", "bar", "nightlife"].contains(model.places[$0.placeID]?.category ?? "") }
        guard !hasBreak, ids.count >= 2 else { return ids }
        // After the first sight that ends mid-afternoon, before the next stop.
        for (i, stop) in day.stops.enumerated().dropLast() {
            guard let place = model.places[stop.placeID], !place.isFood, let start = GuideDates.minutes(stop.time) else { continue }
            let end = start + stop.durationMinutes
            if (14 * 60 + 30)...(17 * 60 + 30) ~= end { ids.insert(SlotKind.coffee.autoID, at: i + 1); break }
        }
        return ids
    }

    static func place(_ id: String, model: GuideModel, edits: GuideEdits) -> GuidePlace? {
        model.places[id] ?? edits.extraPlaces[id]?.guidePlace
    }

    static func resolve(_ day: GuideDay, model: GuideModel, edits: GuideEdits, holidays: [GuideHoliday], base: GuideBase? = nil) -> ResolvedDay {
        let original = Dictionary(day.stops.map { ($0.placeID, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = edits.order[day.date] ?? baseOrder(day, model: model)
        // Coordinates of real stops, for placing open blocks between their neighbours.
        let anchors: [String: (Double, Double)] = Dictionary(ids.compactMap { id -> (String, (Double, Double))? in
            guard SlotKind.parse(id) == nil, let c = model.places[id]?.coordinate else { return nil }
            return (id, (c.latitude, c.longitude))
        }, uniquingKeysWith: { a, _ in a })
        func between(_ index: Int) -> (Double, Double)? {
            let before = ids[..<index].reversed().compactMap { anchors[$0] }.first
            let after = ids[(index + 1)...].compactMap { anchors[$0] }.first
            switch (before, after) {
            case let (a?, b?): return ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }
        var clock = DateTimeCursor()
        var stops: [ResolvedStop] = []
        for (index, id) in ids.enumerated() {
            let key = "\(day.date)|\(id)"
            let base = original[id]
            if let kind = SlotKind.parse(id) {
                // An open block: the traveller's pick, or a placeholder in the area between stops.
                let center = between(index)
                let pickedID = edits.slotPicks[key]?.nilIfEmpty
                let picked = pickedID.flatMap { place($0, model: model, edits: edits) }
                let shown = picked ?? GuidePlace.slot(id: id, kind: kind, latitude: center?.0, longitude: center?.1)
                let time = edits.times[key] ?? (id == SlotKind.coffee.autoID ? clock.next(after: stops.last) : kind.defaultTime)
                stops.append(ResolvedStop(key: key, itemID: id, place: shown, time: time, durationMinutes: kind.minutes,
                                          travelMinutes: nil, alternatives: [], note: edits.notes[key] ?? "", added: true,
                                          slot: ResolvedSlot(kind: kind, latitude: center?.0, longitude: center?.1, pickedID: pickedID, suggestedID: nil)))
                continue
            }
            guard let planned = model.places[id] else { continue }
            let time = edits.times[key] ?? base?.time ?? clock.next(after: stops.last)
            var slot: ResolvedSlot? = nil
            var shown = planned
            if let kind = SlotKind.infer(planned, time: time) {
                // The planner's restaurant is a suggestion inside a block the traveller can re-pick.
                let pick = edits.slotPicks[key]
                let pickedID = pick == nil ? planned.id : pick!.nilIfEmpty
                let center = between(index) ?? planned.coordinate.map { ($0.latitude, $0.longitude) }
                shown = pickedID.flatMap { place($0, model: model, edits: edits) }
                    ?? GuidePlace.slot(id: id, kind: kind, latitude: center?.0, longitude: center?.1)
                slot = ResolvedSlot(kind: kind, latitude: center?.0, longitude: center?.1, pickedID: pickedID, suggestedID: planned.id)
            }
            let duration = base?.durationMinutes ?? slot?.kind.minutes ?? (planned.isFood ? 75 : 90)
            stops.append(ResolvedStop(key: key, itemID: id, place: shown, time: time, durationMinutes: duration,
                                      travelMinutes: stops.isEmpty ? nil : base?.travelMinutes,
                                      alternatives: (base?.alternatives ?? []).compactMap { model.places[$0] },
                                      note: edits.notes[key] ?? "", added: base == nil,
                                      why: shown.id == planned.id ? (base?.why ?? "") : "", tip: shown.id == planned.id ? (base?.tip ?? "") : "",
                                      slot: slot,
                                      includes: shown.id == planned.id ? (base?.includes ?? []).compactMap { model.places[$0]?.name } : []))
        }
        stops.sort { (GuideDates.minutes($0.time) ?? 0) < (GuideDates.minutes($1.time) ?? 0) }
        // The day starts at the base: the planner's own estimate, else one from the distance.
        if let base, !stops.isEmpty, let first = stops.first?.place.coordinate {
            let planned = original[stops[0].itemID].flatMap { $0.fromBase ? $0.travelMinutes : nil }
            stops[0].fromBaseMinutes = planned ?? minutes(from: base.coordinate, to: first)
        }
        let sights = stops.filter { $0.slot == nil && !$0.place.isFood }.map(\.place.name)
        let food = stops.filter { $0.slot != nil || $0.place.isFood }.map { $0.slot?.pickedID == nil ? ($0.slot?.kind.title ?? $0.place.name) : $0.place.name }
        // Two names read as a title; more becomes a list.
        let title = edits.dayTitles[day.date]?.nilIfEmpty ?? day.theme.nilIfEmpty
            ?? (sights.isEmpty ? (stops.isEmpty ? "Free day" : food.prefix(2).joined(separator: " & ")) : sights.prefix(2).joined(separator: " & "))
        let subtitle = day.summary.nilIfEmpty ?? (food.isEmpty ? "\(stops.count) stops" : "Eat at " + food.joined(separator: ", "))
        return ResolvedDay(index: day.index, date: day.date, title: title, subtitle: subtitle, stops: stops,
                           holiday: holidays.first { $0.date == day.date }, areaIDs: day.areaIDs)
    }

    struct DateTimeCursor {
        func next(after previous: ResolvedStop?) -> String {
            guard let previous, let start = GuideDates.minutes(previous.time) else { return "10:00" }
            return GuideDates.clock(start + previous.durationMinutes + 20)
        }
    }

    var people: Int { max(1, edits.fares.reduce(0) { $0 + $1.count }) }
    var plannedPlaces: [GuidePlace] {
        var seen = Set<String>()
        return days.flatMap(\.stops).filter { $0.slot == nil || $0.slot?.pickedID != nil }.map(\.place).filter { seen.insert($0.id).inserted }
    }
    var sights: [GuidePlace] { plannedPlaces.filter { !$0.isFood }.sorted { $0.fame > $1.fame } }
    /// Sights that may charge entry; parks and squares are left out of the calculator.
    var ticketed: [GuidePlace] { sights.filter { !["nature", "outdoors"].contains($0.category) } }
    var foodPlaces: [GuidePlace] { plannedPlaces.filter(\.isFood) }

    /// Big, famous or reservation-required sights: the ones worth booking first.
    var priorities: [GuidePlace] {
        sights.filter { $0.reservationRequired == true || ($0.isSight && $0.fame >= 20) }
    }
    func dateOf(_ place: GuidePlace) -> String? { days.first { $0.stops.contains { $0.place.id == place.id } }?.date }

    // Tickets: a price per fare type for each sight, defaulting to the source price.
    func price(_ place: GuidePlace, fare: GuideFare) -> Double? {
        if let edited = edits.prices[place.id]?[fare.id.uuidString] { return edited }
        if let a = place.priceMin, let b = place.priceMax, a == b { return a }
        return nil
    }
    func ticketTotal(_ place: GuidePlace) -> Double? {
        var total = 0.0
        for fare in edits.fares where fare.count > 0 {
            guard let p = price(place, fare: fare) else { return nil }
            total += p * Double(fare.count)
        }
        return total
    }
    var ticketsKnown: Double { ticketed.compactMap(ticketTotal).reduce(0, +) }
    var ticketsUnknown: Int { ticketed.filter { ticketTotal($0) == nil }.count }
    /// nil while nothing is priced yet, so the page never shows a misleading 0 €.
    var ticketsDisplay: Double? { ticketsUnknown == ticketed.count && !ticketed.isEmpty ? nil : ticketsKnown }

    /// Stops that collide with the flight times the traveler entered.
    func timingWarning(_ stop: ResolvedStop, day: ResolvedDay) -> String? {
        guard let start = GuideDates.minutes(stop.time) else { return nil }
        if day.index == 0, let landing = GuideDates.minutes(edits.flight.arrivalTime), start < landing + 90 {
            return "Before you reach your stay (landing \(edits.flight.arrivalTime))"
        }
        if day.index == days.count - 1, let takeoff = GuideDates.minutes(edits.flight.departureTime),
           start + stop.durationMinutes > takeoff - 180 {
            return "Too close to your \(edits.flight.departureTime) flight"
        }
        return nil
    }
    var transportKnown: Double { edits.transportLines.compactMap(\.amount).reduce(0, +) }
    var foodTotal: Double { edits.foodPerPersonDay * Double(people) * Double(max(days.count, 1)) }
    var budgetTotal: Double { (edits.stayTotal ?? 0) + ticketsKnown + transportKnown + foodTotal + (edits.extras ?? 0) }

    var checklist: [ChecklistItem] {
        var items: [ChecklistItem] = []
        for place in priorities {
            let when = dateOf(place).map { " for \(GuideDates.short($0))" } ?? ""
            items.append(ChecklistItem(id: "book|\(place.id)", text: "Book \(place.name)\(when)", group: "Bookings", custom: false))
        }
        if !edits.flight.stayName.isEmpty || edits.stayTotal == nil {
            items.append(ChecklistItem(id: "stay", text: edits.flight.stayName.isEmpty ? "Book your stay" : "Confirm your stay at \(edits.flight.stayName)",
                                       group: "Bookings", custom: false))
        }
        for day in days where day.holiday != nil {
            items.append(ChecklistItem(id: "hours|\(day.date)", text: "Check opening hours for \(GuideDates.short(day.date)) (\(day.holiday!.name))",
                                       group: "Before you go", custom: false))
        }
        items.append(ChecklistItem(id: "transfer", text: "Choose airport transfers", group: "Before you go", custom: false))
        items.append(ChecklistItem(id: "offline", text: "Save tickets and maps offline", group: "Before you go", custom: false))
        for (i, text) in edits.customChecklist.enumerated() {
            items.append(ChecklistItem(id: "custom|\(i)|\(text)", text: text, group: "Your items", custom: true))
        }
        return items
    }

    /// Plain-text version for sharing or pasting into notes.
    var shareText: String {
        var lines = ["\(input.title) · \(input.startDate) – \(input.endDate)", ""]
        for day in days {
            lines.append("\(GuideDates.short(day.date)) — \(day.title)")
            for stop in day.stops { lines.append("  \(stop.time)  \(stop.place.name)") }
            lines.append("")
        }
        lines.append("Checklist:")
        lines += checklist.map { (edits.checklistDone.contains($0.id) ? "[x] " : "[ ] ") + $0.text }
        return lines.joined(separator: "\n")
    }
}

enum Euro {
    static func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "EUR").locale(Locale(identifier: "en_IE")).precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }
}
