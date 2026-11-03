"""Check native storage compatibility without launching a simulator or touching UserDefaults."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'ios/Trippy/TrippyApp.swift').read_text()
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]
models = '\n'.join([
    'import Foundation\nimport MapKit',
    section('private struct TripBrief:', 'private struct DestinationHoliday:'),
    section('private struct Trip: Codable', 'private enum TripStorage'),
    section('private extension String {', 'private enum PersonalPlaceStorage'),
])
checks = r'''
let original = #"""
{"id":"12345678-1234-1234-1234-123456789ABC","brief":{"destination":"Barcelona","notes":"Keep this note","travelers":3,"dietaryNeeds":["Vegan"]},"research":"{\"unknown_future_field\":{\"preserve\":true}}","updatedAt":100,"scheduleOrderByDate":{"day-1":["stop|day-1|2","place|p1"]},"reactionsByItemID":{"p1":"like"},"mapCoordinatesByPlaceID":{"p1":{"latitude":41.38,"longitude":2.17,"source":"manual","matchedAt":100}},"scheduleEditsByItemID":{"p1":{"time":"10:45","costPerPerson":"12"}},"checklistDoneIDs":["task1"],"budgetEntries":[{"id":"12345678-1234-1234-1234-123456789ABC","title":"Tickets","amount":"36","basis":"group"}]}
"""#
let decoder = JSONDecoder()
var trip = try decoder.decode(Trip.self, from: Data(original.utf8))
precondition(trip.customName == nil && trip.title == "Barcelona", "Old trips must load without a new name")
let roundTrip = try decoder.decode(Trip.self, from: JSONEncoder().encode(trip))
precondition(roundTrip == trip, "Every old field and opaque research must survive re-encoding")
trip.customName = "  Our autumn escape  "
precondition(trip.title == "Our autumn escape")
let renamed = try decoder.decode(Trip.self, from: JSONEncoder().encode(trip))
precondition(renamed == trip && renamed.research == roundTrip.research)
precondition(renamed.scheduleOrderByDate == roundTrip.scheduleOrderByDate)
precondition(renamed.mapCoordinatesByPlaceID == roundTrip.mapCoordinatesByPlaceID)
precondition(renamed.checklistDoneIDs == roundTrip.checklistDoneIDs)
trip.customName = "   "
precondition(trip.title == "Barcelona")
let place = PersonalPlace(id: "apple:example", name: "Example", city: "Barcelona", address: "User selection", latitude: 41.38, longitude: 2.17, category: .coffee)
let saved = try decoder.decode([PersonalPlace].self, from: JSONEncoder().encode([place]))
precondition(saved == [place], "Personal saves must round-trip independently from trips")
print("PASS: old-trip migration, opaque research, edits/order/coordinates/checklist/budget retention, rename and personal-save round-trip")
'''
social_checks = r'''
let shareID = UUID()
let tripID = UUID()
let noteID = UUID()
let envelope = SharedSourceEnvelope(id: shareID, capturedAt: .now, sourceURL: "https://www.tiktok.com/@example/photo/1234", sharedText: "Caption Καφές", attachments: [], destination: ShareDestination(mode: "note", tripID: tripID, noteID: noteID))
precondition(envelope.mediaKind == "unknown", "A URL alone does not confirm slideshow/video type")
let recoveredEnvelope = try decoder.decode(SharedSourceEnvelope.self, from: JSONEncoder().encode(envelope))
precondition(recoveredEnvelope == envelope && recoveredEnvelope.destination.noteID == noteID)
let note = TravelNote(id: noteID, title: "My travel note", tripID: tripID, sourceIDs: [shareID], userText: "Keep my own text", updatedAt: .now)
let recoveredNote = try decoder.decode(TravelNote.self, from: JSONEncoder().encode(note))
precondition(recoveredNote == note)
let evidence = SourceEvidenceBlock(id: "slide1", origin: "slide_ocr", text: "Όλο το κείμενο\nCafe Example — branch unclear", attachmentID: UUID(), order: 0)
let recoveredEvidence = try decoder.decode(SourceEvidenceBlock.self, from: JSONEncoder().encode(evidence))
precondition(recoveredEvidence == evidence)
print("PASS: share/target/note/evidence round-trip and URL-only media uncertainty")
'''
out = ROOT / '.local/ui-map-first'
out.mkdir(parents=True, exist_ok=True)
swift = out / 'StorageCheck.swift'
swift.write_text(models + (ROOT / 'ios/Shared/SharedInbox.swift').read_text() + '\ndo {\n' + checks + social_checks + '\n} catch { fatalError(String(describing: error)) }\n')
binary = out / 'storage-check'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(out / 'host-module-cache'), str(swift), '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
