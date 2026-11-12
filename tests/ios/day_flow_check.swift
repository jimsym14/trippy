// Compiled together with ios/Trippy/DayFlow.swift by tests/test_day_flow.py.
import Foundation

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}
func at(_ placements: [DayFlow.Placement], _ id: String) -> DayFlow.Placement { placements.first { $0.id == id }! }
func m(_ clock: String) -> Int { let p = clock.split(separator: ":").map { Int($0)! }; return p[0] * 60 + p[1] }

// Barcelona, Eixample: three sights a short walk apart.
let sagrada = (41.4036, 2.1744), pau = (41.4114, 2.1747), batllo = (41.3916, 2.1649), pedrera = (41.3954, 2.1619)

func item(_ id: String, _ time: String, _ minutes: Int, _ c: (Double, Double)? = nil, booked: Bool = false, fixed: Bool = false,
          reorderable: Bool = true, previous: String? = nil, travel: Int? = nil) -> DayFlow.Item {
    DayFlow.Item(id: id, name: id, start: m(time), duration: minutes, fixed: fixed, booked: booked,
                 latitude: c?.0, longitude: c?.1, plannedPrevious: previous, plannedTravel: travel, reorderable: reorderable)
}

@main
struct DayFlowCheck {
    static func main() {
        // 1. An untouched day stays exactly as planned, even where the estimate is longer than the planner's leg.
        do {
            let day = [item("Sagrada", "09:30", 120, sagrada), item("Sant Pau", "11:35", 90, pau, previous: "Sagrada", travel: 5),
                       item("Lunch", "13:15", 75, nil, reorderable: false)]
            let out = DayFlow.reflow(day)
            check(out.allSatisfy { !$0.moved && $0.reason == nil && $0.fits }, "untouched day moved: \(out)")
        }

        // 2. A booking at 14:00 pushes lunch after it and says why; what follows lunch moves with the same reason.
        do {
            let day = [item("Sant Pau", "10:00", 90, pau), item("Lunch", "13:00", 75, batllo, reorderable: false),
                       item("Sagrada", "14:00", 120, sagrada, booked: true), item("Batllo", "15:00", 60, batllo)]
            let out = DayFlow.reflow(day)
            let lunch = at(out, "Lunch"), batlloAt = at(out, "Batllo")
            check(!at(out, "Sagrada").moved && at(out, "Sagrada").fits, "the booking moved")
            check(lunch.start >= m("16:00"), "lunch should follow the booking, got \(DayFlow.clock(lunch.start))")
            check(lunch.reason?.contains("after your Sagrada booking at 14:00") == true, "lunch reason: \(lunch.reason ?? "nil")")
            check(lunch.reason?.hasPrefix("Moved from 13:00") == true, "lunch reason says where it was: \(lunch.reason ?? "nil")")
            check(batlloAt.start >= lunch.start + 75, "Batlló after lunch")
            check(batlloAt.reason?.contains("Sagrada booking") == true, "the cause carries down the day: \(batlloAt.reason ?? "nil")")
            check(out.map(\.id) == ["Sant Pau", "Sagrada", "Lunch", "Batllo"], "order \(out.map(\.id))")
        }

        // 3. A time the traveller set counts as fixed and is named as theirs.
        do {
            let day = [item("Pedrera", "10:00", 90, pedrera, fixed: true), item("Batllo", "09:30", 60, batllo)]
            let out = DayFlow.reflow(day)
            let b = at(out, "Batllo")
            check(b.start > m("11:30"), "Batlló can't fit before 10:00 with the walk, got \(DayFlow.clock(b.start))")
            check(b.reason?.contains("the time you set") == true, "reason: \(b.reason ?? "nil")")
        }

        // 4. A stop that fits before the booking stays before it.
        do {
            let day = [item("Batllo", "09:00", 60, batllo), item("Sagrada", "14:00", 120, sagrada, booked: true)]
            let out = DayFlow.reflow(day)
            check(!at(out, "Batllo").moved, "Batlló fits before the booking")
        }

        // 5. Two fixed stops that overlap are both kept and the later one is flagged.
        do {
            let day = [item("Sagrada", "10:00", 120, sagrada, booked: true), item("Pedrera", "11:00", 90, pedrera, fixed: true)]
            let out = DayFlow.reflow(day)
            let p = at(out, "Pedrera")
            check(!p.moved && !p.fits && p.reason?.hasPrefix("Clashes with Sagrada") == true, "clash: \(p)")
        }

        // 6. The departure day: what no longer fits before the airport is flagged, not silently dropped.
        do {
            let leave = DayFlow.Limit(minutes: m("14:00"), because: "before you leave for the airport at 14:00")
            let day = [item("Breakfast", "09:00", 45, batllo, reorderable: false), item("Sagrada", "10:00", 120, sagrada, booked: true),
                       item("Pedrera", "11:00", 90, pedrera)]
            let out = DayFlow.reflow(day, latest: leave)
            let p = at(out, "Pedrera")
            check(!p.fits && p.reason == "No time for this before you leave for the airport at 14:00", "late: \(p)")
            check(at(out, "Breakfast").fits && !at(out, "Breakfast").moved, "breakfast stays: \(at(out, "Breakfast"))")
            check(at(out, "Breakfast").reason == "Leaves 15 min to get to Sagrada for 10:00", "a tight walk is said: \(at(out, "Breakfast"))")
        }

        // 7. Arrival day: a later landing pushes the day, with no fixed stop at all.
        do {
            let landed = DayFlow.Limit(minutes: m("13:30"), because: "after you reach your stay")
            let day = [item("Batllo", "12:00", 60, batllo), item("Pedrera", "13:15", 90, pedrera, previous: "Batllo", travel: 10)]
            let out = DayFlow.reflow(day, earliest: landed)
            check(at(out, "Batllo").start == m("13:30") && at(out, "Batllo").reason == "Moved from 12:00, after you reach your stay", "\(at(out, "Batllo"))")
            check(at(out, "Pedrera").start == m("14:40"), "Pedrera after Batlló and the planner's 10 min, got \(DayFlow.clock(at(out, "Pedrera").start))")
        }

        // 8. Shorter route: a zig-zag between two Eixample sights and two by Sagrada is untangled.
        do {
            let day = [item("Batllo", "09:30", 60, batllo), item("Sagrada", "10:45", 60, sagrada), item("Pedrera", "12:00", 60, pedrera),
                       item("Sant Pau", "13:15", 60, pau)]
            let better = DayFlow.shorterRoute(day)
            check(better != nil, "a shorter order exists")
            if let better {
                let i = better.order
                check(abs(i.firstIndex(of: "Batllo")! - i.firstIndex(of: "Pedrera")!) == 1, "Batlló and La Pedrera together: \(i)")
                check(abs(i.firstIndex(of: "Sagrada")! - i.firstIndex(of: "Sant Pau")!) == 1, "Sagrada and Sant Pau together: \(i)")
                check(better.saved >= 10, "saves \(better.saved)")
            }
            // A booked stop in the middle splits the day: nothing crosses it.
            var anchored = day; anchored[1].booked = true
            if let around = DayFlow.shorterRoute(anchored) { check(around.order[1] == "Sagrada", "the booking keeps its place: \(around.order)") }
            // Already efficient: no suggestion.
            let neat = [item("Batllo", "09:30", 60, batllo), item("Pedrera", "10:45", 60, pedrera), item("Sagrada", "12:00", 60, sagrada)]
            check(DayFlow.shorterRoute(neat) == nil, "no suggestion for a neat day")
        }

        // 9. Leave by: three hours before the flight, and a warning when the last stop runs into it.
        do {
            let fine = DayFlow.leaveBy(departure: m("17:00"), lastEnd: m("13:00"), lastName: "Pedrera")
            check(fine.title == "Leave by 14:00 for your 17:00 flight" && !fine.late, "\(fine)")
            let late = DayFlow.leaveBy(departure: m("17:00"), lastEnd: m("14:30"), lastName: "Pedrera")
            check(late.late && late.detail.hasPrefix("Pedrera ends at 14:30"), "\(late)")
        }

        if failures > 0 { print("\(failures) failed"); exit(1) }
        print("day flow: all checks passed")
    }
}
