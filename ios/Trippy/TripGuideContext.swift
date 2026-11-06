import Foundation

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
    let key: String            // "date|placeID"
    let place: GuidePlace
    let time: String
    let durationMinutes: Int
    let travelMinutes: Int?
    let alternatives: [GuidePlace]
    let note: String
    let added: Bool
}

struct ResolvedDay: Identifiable, Hashable {
    var id: String { date }
    let index: Int
    let date: String
    let title: String
    let subtitle: String
    let stops: [ResolvedStop]
    let holiday: GuideHoliday?
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

    init(model: GuideModel, edits: GuideEdits, input: GuideInput, holidays: [GuideHoliday]) {
        self.model = model; self.edits = edits; self.input = input; self.holidays = holidays
        days = model.days.map { GuideContext.resolve($0, model: model, edits: edits, holidays: holidays) }
    }

    static func resolve(_ day: GuideDay, model: GuideModel, edits: GuideEdits, holidays: [GuideHoliday]) -> ResolvedDay {
        let original = Dictionary(day.stops.map { ($0.placeID, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = edits.order[day.date] ?? day.stops.map(\.placeID)
        var clock = DateTimeCursor()
        var stops: [ResolvedStop] = []
        for id in ids {
            guard let place = model.places[id] else { continue }
            let base = original[id]
            let key = "\(day.date)|\(id)"
            let duration = base?.durationMinutes ?? (place.isFood ? 75 : 90)
            let proposed = edits.times[key] ?? base?.time ?? clock.next(after: stops.last)
            stops.append(ResolvedStop(key: key, place: place, time: proposed, durationMinutes: duration,
                                      travelMinutes: stops.isEmpty ? nil : base?.travelMinutes,
                                      alternatives: (base?.alternatives ?? []).compactMap { model.places[$0] },
                                      note: edits.notes[key] ?? "", added: base == nil))
        }
        stops.sort { (GuideDates.minutes($0.time) ?? 0) < (GuideDates.minutes($1.time) ?? 0) }
        let sights = stops.filter { !$0.place.isFood }.map(\.place.name)
        let food = stops.filter { $0.place.isFood }.map(\.place.name)
        // Two names read as a title; more becomes a list.
        let title = edits.dayTitles[day.date]?.nilIfEmpty
            ?? (sights.isEmpty ? (stops.isEmpty ? "Free day" : food.prefix(2).joined(separator: " & ")) : sights.prefix(2).joined(separator: " & "))
        let subtitle = food.isEmpty ? "\(stops.count) stops" : "Eat at " + food.joined(separator: ", ")
        return ResolvedDay(index: day.index, date: day.date, title: title, subtitle: subtitle, stops: stops,
                           holiday: holidays.first { $0.date == day.date })
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
        return days.flatMap(\.stops).map(\.place).filter { seen.insert($0.id).inserted }
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
