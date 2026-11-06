#!/usr/bin/env python3
"""Exercise the app's actual draft persistence gate without networking or UI."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ios/Trippy/TrippyApp.swift'

CHECKS = r'''
private var lifecycleBrief = TripBrief()
lifecycleBrief.startDate = "2026-11-04"; lifecycleBrief.endDate = "2026-11-08"
private var lifecycleTrip = Trip(brief: lifecycleBrief)
private let today = LibraryTripPhase.date("2026-11-04")!
precondition(LibraryTripPhase.phase(lifecycleTrip, today: today) == .upcoming)
precondition(LibraryTripPhase.phase(lifecycleTrip, today: LibraryTripPhase.date("2026-11-09")!) == .completed)
precondition(!LibraryTripPhase.lastDateHasPassed(lifecycleTrip, today: today))
precondition(LibraryTripPhase.lastDateHasPassed(lifecycleTrip, today: LibraryTripPhase.date("2026-11-09")!))
lifecycleTrip.completedAt = today
precondition(LibraryTripPhase.phase(lifecycleTrip, today: today) == .completed)
private let completedBytes = try JSONEncoder().encode(lifecycleTrip)
private let restoredCompletedTrip = try JSONDecoder().decode(Trip.self, from: completedBytes)
precondition(restoredCompletedTrip.completedAt == today)
var legacyTripJSON = try JSONSerialization.jsonObject(with: completedBytes) as! [String: Any]
legacyTripJSON.removeValue(forKey: "completedAt")
private let restoredLegacyLifecycle = try JSONDecoder().decode(Trip.self, from: JSONSerialization.data(withJSONObject: legacyTripJSON))
precondition(restoredLegacyLifecycle.completedAt == nil && restoredLegacyLifecycle.brief == lifecycleBrief)
precondition(LibraryTripPhase.date("2026-02-30") == nil)
private var flexibleTrip = Trip(brief: TripBrief())
flexibleTrip.brief.dateIsUnknown = true
precondition(LibraryTripPhase.phase(flexibleTrip, today: today) == .upcoming)
precondition(LibraryTripPhase.sorted([flexibleTrip, lifecycleTrip]).first?.id == lifecycleTrip.id)
private var earlierPast = lifecycleTrip
earlierPast.id = UUID(); earlierPast.completedAt = nil
earlierPast.brief.startDate = "2026-08-01"; earlierPast.brief.endDate = "2026-08-03"
private var recentPast = earlierPast
recentPast.id = UUID(); recentPast.brief.startDate = "2026-11-01"; recentPast.brief.endDate = "2026-11-03"
precondition(LibraryTripPhase.sorted([earlierPast, recentPast], today: today).first?.id == recentPast.id, "Completed trips nearest to today appear first")
precondition(LibraryTripPhase.phase(recentPast, today: today) == .completed)
precondition(TripDateLabel.compact(start: "2026-12-05", end: "2026-12-09", flexible: false, duration: 4) == "5/12-9/12 2026")
precondition(TripDateLabel.compact(start: "2026-11-29", end: "2026-12-03", flexible: false, duration: 4) == "29/11-3/12 2026")
precondition(TripDateLabel.compact(start: "2026-12-29", end: "2027-01-03", flexible: false, duration: 4) == "29/12 2026-3/1 2027")
precondition(TripDateLabel.compact(start: "2026-12-05", end: "2026-12-05", flexible: false, duration: 1) == "5/12 2026")
precondition(TripDateLabel.compact(start: "", end: "2026-12-09", flexible: false, duration: 4) == "9/12 2026")
precondition(TripDateLabel.compact(start: "2026-02-30", end: "invalid", flexible: false, duration: 4) == "Ημερομηνίες προς επιλογή")
precondition(TripDateLabel.compact(start: "2026-12-05", end: "2026-12-09", flexible: true, duration: 7) == "7 ημέρες · Ευέλικτες")
precondition(LibrarySourceStatus.classify("ready") == .ready)
precondition(LibrarySourceStatus.classify("needs_retrieval") == .pending)
precondition(LibrarySourceStatus.classify("needs_transcript") == .pending)
precondition(LibrarySourceStatus.classify("failed") == .review)
precondition(LibrarySourceStatus.classify("unknown") == .review, "New import states must remain visible for review")
let identity = MarkAppearance(glyph: "🇪🇸", kind: "flag", colorHex: "cf719f")
precondition(identity.validColorHex == "CF719F")
precondition(MarkAppearance(glyph: "heart", colorHex: "not-a-color").validColorHex == nil)
precondition(MarkGlyphCatalog.flag("es") == "🇪🇸" && MarkGlyphCatalog.flag("123") == "🌐")
precondition(MarkGlyphCatalog.categoryKey("Art | cafés") != MarkGlyphCatalog.categoryKey("Art cafés"))
precondition(!MarkGlyphCatalog.categoryKey("Art | cafés").contains("|"))
for page in MarkGlyphCatalog.pages {
    let choices = MarkGlyphCatalog.choices(page)
    precondition(!choices.isEmpty && Set(choices.map(\.id)).count == choices.count)
}
private var customPlace = PersonalPlace(id: "place-1", name: "My coffee spot", city: "Barcelona", address: "La Rambla", latitude: 41.38, longitude: 2.17, category: .coffee)
customPlace.appearance = identity; customPlace.customCategory = "Art | cafés"
let placeBytes = try JSONEncoder().encode(customPlace)
private let decodedPlace = try JSONDecoder().decode(PersonalPlace.self, from: placeBytes)
precondition(decodedPlace == customPlace)
var legacyPlace = try JSONSerialization.jsonObject(with: placeBytes) as! [String: Any]
legacyPlace.removeValue(forKey: "appearance"); legacyPlace.removeValue(forKey: "customCategory")
private let restoredPlace = try JSONDecoder().decode(PersonalPlace.self, from: JSONSerialization.data(withJSONObject: legacyPlace))
precondition(restoredPlace.appearance == nil && restoredPlace.customCategory == nil && restoredPlace.latitude == customPlace.latitude && restoredPlace.name == customPlace.name)
precondition(customPlace.categoryTitle == "Art | cafés")
precondition(restoredPlace.isSaved && !restoredPlace.isPinned, "Old saved places keep their saved state")
customPlace.pinned = true; customPlace.saved = false
precondition(customPlace.isPinned && !customPlace.isSaved)
let pinBytes = try JSONEncoder().encode(customPlace)
private let decodedPin = try JSONDecoder().decode(PersonalPlace.self, from: pinBytes)
precondition(decodedPin.isPinned && !decodedPin.isSaved)
customPlace.saved = true
precondition(customPlace.isPinned && customPlace.isSaved)
let sourceA = UUID(), sourceB = UUID(), noteA = UUID(), noteB = UUID(), mentionA = UUID()
let envelopeA = SharedSourceEnvelope(id: sourceA, capturedAt: .now, sourceURL: nil, sharedText: "A", attachments: [], destination: ShareDestination(mode: "places", tripID: nil, noteID: nil))
let envelopeB = SharedSourceEnvelope(id: sourceB, capturedAt: .now, sourceURL: nil, sharedText: "B", attachments: [], destination: ShareDestination(mode: "places", tripID: nil, noteID: nil))
var sources = [ImportedSocialSource(id: sourceA, envelope: envelopeA, evidence: [], state: "ready", issues: []), ImportedSocialSource(id: sourceB, envelope: envelopeB, evidence: [], state: "ready", issues: [])]
var notes = [TravelNote(id: noteA, title: "My retained note", tripID: nil, sourceIDs: [sourceA, sourceB], userText: "Keep this text", updatedAt: .now), TravelNote(id: noteB, title: "Second note", tripID: nil, sourceIDs: [sourceB], userText: "Keep B", updatedAt: .now)]
var deleted = Set<UUID>()
LibraryDeletion.video(sourceA, sources: &sources, notes: &notes, deleted: &deleted)
precondition(sources.map(\.id) == [sourceB] && deleted.contains(sourceA))
precondition(notes.count == 2 && notes[0].userText == "Keep this text" && notes[0].sourceIDs == [sourceB])
LibraryDeletion.video(sourceA, sources: &sources, notes: &notes, deleted: &deleted)
precondition(sources.count == 1 && deleted.count == 1, "Repeated deletion must not affect other sources")
var mentions = [SocialPlaceMention(id: mentionA, name: "Retained place", summary: "Keep", sourceID: sourceB, evidenceIDs: [], tripID: nil, latitude: nil, longitude: nil, noteID: noteA)]
LibraryDeletion.note(noteA, notes: &notes, places: &mentions)
precondition(notes.map(\.id) == [noteB] && mentions.count == 1 && mentions[0].noteID == nil && mentions[0].name == "Retained place")
private var trips: [Trip] = []
private var brief = TripBrief()
let empty = TripDraftPersistence.save(trips: &trips, activeID: nil, brief: brief, name: " \n ", researchStarted: false)
precondition(empty == nil && trips.isEmpty, "Opening an unnamed form cannot create a saved trip")
brief.destination = "Barcelona"
brief.duration = 7
precondition(TripDraftPersistence.save(trips: &trips, activeID: nil, brief: brief, name: "", researchStarted: false) == nil)
precondition(trips.isEmpty, "A destination alone must not save an unnamed draft")
let namedID = TripDraftPersistence.save(trips: &trips, activeID: nil, brief: brief, name: "  Summer break  ", researchStarted: false)!
precondition(trips.count == 1 && trips[0].title == "Summer break")
precondition(trips[0].brief == brief, "Naming preserves all form fields")
trips[0].appearance = identity; trips[0].savedPins = [customPlace]
brief.notes = "Museums and coffee"
let updatedID = TripDraftPersistence.save(trips: &trips, activeID: namedID, brief: brief, name: "", researchStarted: false)
precondition(updatedID == namedID && trips.count == 1)
precondition(trips[0].customName == "Summer break", "Clearing the field must not strip a saved trip's name")
precondition(trips[0].brief.notes == brief.notes)
precondition(trips[0].appearance == identity && trips[0].savedPins == [customPlace], "Editing a brief preserves custom trip and pin identities")
TripDraftPersistence.save(trips: &trips, activeID: namedID, brief: brief, name: "City break", researchStarted: false)
precondition(trips.count == 1 && trips[0].title == "City break")
private var researchDraft = TripBrief(); researchDraft.destination = " Rome "; researchDraft.duration = 9
let researchID = TripDraftPersistence.save(trips: &trips, activeID: nil, brief: researchDraft, name: "", researchStarted: true)!
precondition(trips.count == 2 && trips[0].customName == "Trip · Rome")
precondition(trips[0].brief == researchDraft, "Starting research cannot reset destination, dates or preferences")
TripDraftPersistence.save(trips: &trips, activeID: researchID, brief: researchDraft, name: "", researchStarted: true)
precondition(trips.count == 2, "Retrying research must update the same trip")
precondition(TripDraftPersistence.defaultName(for: TripBrief()) == "My trip")
let bytes = try JSONEncoder().encode(trips)
private let decoded = try JSONDecoder().decode([Trip].self, from: bytes)
precondition(decoded == trips && decoded.allSatisfy { !$0.title.isEmpty && $0.customName != nil })
TripStorage.save(trips)
precondition(TripStorage.load() == trips)
private var legacyTrip = Trip(brief: researchDraft)
legacyTrip.customName = "  "
TripStorage.save([legacyTrip])
private let migrated = TripStorage.load()
precondition(migrated.count == 1 && migrated[0].id == legacyTrip.id && migrated[0].brief == legacyTrip.brief)
precondition(migrated[0].customName == "Rome", "Existing unnamed trips must get names without losing content")
precondition(TripStorage.load() == migrated, "Name migration must be idempotent")
testDefaults.removeObject(forKey: TripStorage.key)
print("PASS: trip lifecycle/proximity sorting/completion persistence, date labels, icon/color/category choices, legacy saved-place decoding, custom identities, unnamed drafts, naming, autosave, research and storage round trip")
'''

def main():
    source = SOURCE.read_text()
    brief = source[source.index('private struct TripBrief:'):source.index('private struct TripPreferenceOption:')]
    trip = source[source.index('private struct Trip:'):source.index('private struct ScheduleItemEdit:')]
    storage = source[source.index('private enum TripStorage {'):source.index('private enum BridgeTokenStore {')]
    storage = storage.replace('UserDefaults.standard', 'testDefaults')
    shared_models = (ROOT / 'ios/Shared/SharedInbox.swift').read_text().split('// One immutable envelope per share.', 1)[0]
    personal_place = source[source.index('private struct PersonalPlace:'):source.index('private enum PersonalPlaceStorage')]
    stubs = '\n'.join(f'private struct {name}: Codable, Equatable {{}}' for name in
                     ('StoredPlaceCoordinate', 'ScheduleItemEdit', 'TripBudgetEntry'))
    with tempfile.TemporaryDirectory(prefix='trippy-draft-checks-', dir='/tmp') as folder:
        folder = Path(folder)
        swift = folder / 'checks.swift'
        swift.write_text('import Foundation\nimport CoreLocation\nprivate enum MapPlaceCategory: String, Codable { case other, coffee }\nprivate enum SearchPlaceKind: String, Codable { case place, area }\nprivate extension String { var nonEmpty: String? { isEmpty ? nil : self } }\n' + stubs + '\n' + shared_models + brief + personal_place + trip + '\nprivate let testDefaults = UserDefaults(suiteName: \"trippy.draft-tests.\\(UUID().uuidString)\")!\n' + storage + CHECKS)
        binary = folder / 'checks'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / '.local/library-design/modules'), str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

if __name__ == '__main__':
    main()
