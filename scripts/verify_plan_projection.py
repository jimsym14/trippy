"""Exercise the production plan projection with synthetic trips; no live storage/network."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'ios/Trippy/TrippyApp.swift').read_text()

def declaration(marker):
    start = source.index(marker)
    # Declarations below have balanced braces, including interpolation closures.
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor].replace('private ', '')

methods = [
    'private func recordValue(', 'private func dayActivities(',
    'private func scheduleDateKey(', 'private func scheduleIDs(',
    'private func scheduledStop(', 'private func scheduledPlace(',
    'private func placeCoordinate(', 'private func coordinateFromRecord(',
    'private func numericValue(', 'private func planRouteLegs(',
    'private func planCoordinate(', 'private func costAmount(', 'private func planNumber(', 'private func priceLabel(',
]
models = source[source.index('private struct TripBrief:'):source.index('private struct DestinationHoliday:')]
models += source[source.index('private struct Trip: Codable'):source.index('private enum TripStorage')]
models += declaration('private struct TripRouteLeg:')
models += '\n' + declaration('private extension String {')
models = models.replace('private ', '')
program = 'import Foundation\nimport MapKit\n' + models + '\nstruct Projection {\n'
program += '''var activeTrip: Trip? = nil
var placeRecords: [[String: Any]] = []
var routePreviewMode = "walking"
var resolvedCoordinates: [String: CLLocationCoordinate2D] = [:]
'''
program += '\n'.join(declaration(method) for method in methods) + '\n}\n'
program += r'''
var p = Projection()
p.placeRecords = [
    ["id": "a", "coordinates": ["latitude": 41.38, "longitude": 2.17]],
    ["id": "b", "coordinates": ["latitude": 41.39, "longitude": 2.18]],
    ["id": "c", "coordinates": ["latitude": 41.40, "longitude": 2.19]],
    ["id": "missing", "coordinates": ["latitude": NSNull(), "longitude": NSNull()]]
]
func day(_ ids: [String]) -> [String: Any] { ["date": "2026-12-05", "stops": ids.map { ["place_id": $0] }] }
precondition(p.planRouteLegs(day(["a", "missing", "b"]), index: 0).isEmpty, "Never bridge an unlocated stop")
precondition(p.planRouteLegs(day(["a"]), index: 0).isEmpty, "One stop has no inter-stop leg")
let legs = p.planRouteLegs(day(["a", "b", "c"]), index: 2)
precondition(legs.count == 2 && legs.allSatisfy { $0.day == 2 && $0.walking }, "Route order belongs to one day")
let transit: [String: Any] = ["date": "2026-12-05", "stops": [["place_id": "a"], ["place_id": "b", "transport_mode": "metro"]]]
precondition(p.planRouteLegs(transit, index: 0).isEmpty, "Don't turn transit into walking geometry")
p.routePreviewMode = "driving"
precondition(p.planRouteLegs(day(["a", "b"]), index: 0).allSatisfy { !$0.walking })
let driving: [String: Any] = ["date": "2026-12-05", "stops": [["place_id": "a"], ["place_id": "b", "transport_mode": "walking"]]]
precondition(p.planRouteLegs(driving, index: 0).allSatisfy { $0.walking }, "Explicit mode takes precedence")
let decoder = JSONDecoder()
p.activeTrip = try decoder.decode(Trip.self, from: Data(#"{"id":"12345678-1234-1234-1234-123456789ABC","brief":{},"updatedAt":100,"scheduleOrderByDate":{"2026-12-05":["place|c","place|a"]}}"#.utf8))
let reordered = p.planRouteLegs(day(["a", "b", "c"]), index: 0)
precondition(reordered.count == 1 && reordered[0].from.latitude == 41.40 && reordered[0].to.latitude == 41.38)
p.activeTrip = nil
p.resolvedCoordinates["stop|2026-12-05|0"] = CLLocationCoordinate2D(latitude: 41.38, longitude: 2.17)
let anonymous: [String: Any] = ["date": "2026-12-05", "stops": [["activity": "User stop"], ["place_id": "b"]]]
precondition(p.planRouteLegs(anonymous, index: 0).count == 1, "Explicitly selected stop pins route correctly")
precondition(p.costAmount(NSNull()) == "—")
precondition(p.costAmount(["min": NSNull(), "max": NSNull()]) == "—", "No available-details placeholder")
precondition(p.costAmount(["per_person_eur": NSNull()]) == "—", "Null is never a subtotal")
precondition(p.costAmount(0) == "€0", "A known zero remains free")
precondition(p.costAmount(["min": 18]).contains("18"), "Preserve one-sided minimum")
precondition(p.costAmount(["max": 25]).contains("25"), "Preserve one-sided maximum")
precondition(p.costAmount(["min": 18, "max": 25, "currency": "USD"]).contains("USD"))
precondition(p.priceLabel(["price": ["min": 29, "max": NSNull(), "currency": "EUR"]]).contains("29"), "Retain a known venue starting price")

var trip = Trip(brief: TripBrief())
let oldDocument: [String: Any] = ["schema_version": "trippy-research-v1", "places": [["id": "a"], ["id": "b"], ["id": "missing"]], "sources": [["id": "old-source"]], "itinerary": ["days": [day(["a", "b", "missing"])]]]
trip.research = String(data: try JSONSerialization.data(withJSONObject: oldDocument), encoding: .utf8)
trip.scheduleOrderByDate = ["2026-12-05": ["stop|2026-12-05|2", "stop|2026-12-05|0"]]
trip.scheduleEditsByItemID = ["stop|2026-12-05|0": ScheduleItemEdit(time: "11:30", costPerPerson: "0"), "stop|2026-12-05|2": ScheduleItemEdit(time: "09:30")]
trip.reactionsByItemID = ["stop|2026-12-05|0": "like", "place|a": "like"]
let newDocument: [String: Any] = ["places": [["id": "a"], ["id": "b"], ["id": "c"]], "itinerary": ["days": [day(["b", "c", "a"])]]]
let reconciled = PlanImportReconciliation.apply(newDocument, to: &trip)
precondition(trip.scheduleOrderByDate?["2026-12-05"] == ["stop|2026-12-05|3", "stop|2026-12-05|2", "stop|2026-12-05|1"], "Retain order and omitted anchor, append fresh proposal, preserve removal")
precondition(trip.scheduleEditsByItemID?["stop|2026-12-05|2"]?.time == "11:30", "Rebind edit by place, never previous index")
precondition(trip.scheduleEditsByItemID?["stop|2026-12-05|2"]?.costPerPerson == "0", "Keep explicit user zero")
precondition(trip.scheduleEditsByItemID?["stop|2026-12-05|3"]?.time == "09:30")
precondition(trip.reactionsByItemID?["stop|2026-12-05|2"] == "like")
precondition((reconciled["places"] as? [[String: Any]])?.contains { $0["id"] as? String == "missing" } == true)
precondition(reconciled["delivery_status"] as? String == "partial", "Local edits need feasibility review")
trip.research = String(data: try JSONSerialization.data(withJSONObject: reconciled), encoding: .utf8)
let repeated = PlanImportReconciliation.apply(reconciled, to: &trip)
precondition(trip.scheduleOrderByDate?["2026-12-05"]?.count == 3, "Repeated import must not duplicate proposals")
precondition(((repeated["itinerary"] as? [String: Any])?["days"] as? [[String: Any]])?.count == 1)
print("PASS: import retains identity, order, removed stop, missing anchor, edit, reaction, repeat import")
print("PASS: missing-pin breaks, one-day order, explicit transport, edited order, user pin, null/free/partial price projections")
'''
folder = ROOT / '.local/plan-redesign'
folder.mkdir(parents=True, exist_ok=True)
path = folder / 'PlanProjectionCheck.swift'
path.write_text(program)
binary = folder / 'plan-projection-check'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / '.local/ui-map-first/host-module-cache'), str(path), '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
