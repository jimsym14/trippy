#!/usr/bin/env python3
"""Run the real visit/feedback models and STATLAS matching without network or Simulator."""
from pathlib import Path
import subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
app = (ROOT/'ios/Trippy/TrippyApp.swift').read_text()
source = (ROOT/'ios/Trippy/WorldExplorer.swift').read_text()
geo = app[app.index('struct GeoBoundaryPoint:'):app.index('private struct GeoBoundaryMetadata:')]
models = source[:source.index('struct NeighborhoodDetailView:')] + source[source.index('struct VisitedCountryGroup:'):source.index('struct WorldCountryVisitsView:')]
design = (ROOT/'ios/Trippy/BeenLibraryDesign.swift').read_text()
models += design[design.index('struct BeenPassportSnapshot {'):design.index('enum BeenPalette {')]
checks = r'''
let place = VisitedPlace(name: "Barcelona", countryCode: "ES", latitude: 41.38, longitude: 2.17)
precondition(VisitedPlace.decode("[]").isEmpty, "No visit is inferred from trip planning")
precondition(VisitedPlace.decode("broken").isEmpty)
let visits = VisitedPlace.adding(place, to: [])
precondition(VisitedPlace.adding(place, to: visits).count == 1)
precondition(VisitedPlace.decode(VisitedPlace.encode(visits)) == visits)
let madrid = VisitedPlace(name:"Madrid",countryCode:"ES",latitude:40.42,longitude:-3.7)
let countryGroups = VisitedCountryGroup.groups([place,madrid])
precondition(countryGroups.count == 1 && countryGroups[0].visits.count == 2, "The globe renders one country marker for multiple city visits")
precondition(VisitedCountryGroup.groups([]).isEmpty)
let passport = BeenPassportSnapshot([place, madrid])
precondition(passport.countryCount == 1 && passport.visits.count == 2)
precondition(passport.continents == ["Europe"])
precondition(passport.countries(in: "Asia").isEmpty)
precondition(passport.countries(in: "Europe").count == 1)
precondition(BeenPassportSnapshot().countryCount == 0 && BeenPassportSnapshot().continents.isEmpty)
let unknown = VisitedPlace(name: "Unknown city", countryCode: nil, latitude: 0, longitude: 0)
precondition(BeenPassportSnapshot([unknown]).countryCount == 0, "Unknown countries never inflate coverage")
var lowercase = madrid; lowercase.countryCode = "es"
precondition(VisitedCountryGroup.groups([place, lowercase]).count == 1, "ISO casing never splits a country")
let calendar = Calendar(identifier: .gregorian)
var old = place; old.visitedAt = calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!
var recent = madrid; recent.visitedAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
let chronology = BeenPassportSnapshot([old, recent])
precondition(chronology.visits.first?.id == recent.id && chronology.years == [2026, 2024])
precondition(chronology.shareText.contains("2 cities"))
let invalid = VisitedPlace(name: "Invalid", countryCode: nil, latitude: 999, longitude: 999)
precondition(VisitedPlace.decode(VisitedPlace.encode([invalid])).isEmpty)
let born = NeighborhoodPlace(id: "apple:born", name: "El Born", latitude: 41.38, longitude: 2.17, city: "Barcelona")
var rating = NeighborhoodFeedback(neighborhood: born)
precondition(rating.scores.isEmpty, "Missing feedback remains unrated")
rating.scores = ["safety": 4, "budget": 2]
let saved = NeighborhoodFeedback.saving(rating, in: [])
precondition(NeighborhoodFeedback.decode(NeighborhoodFeedback.encode(saved)) == saved)
precondition(NeighborhoodFeedback.saving(rating, in: saved).count == 1)
var appleBorn = born; appleBorn = NeighborhoodPlace(id: "apple:born", name: "El Born", latitude: 41.3801, longitude: 2.1701, source: "Apple Maps")
precondition(NeighborhoodFeedback.matching(appleBorn, in: saved) == rating, "Nearby provider aliases share personal feedback")
var dirty = rating; dirty.scores = ["safety": 99, "family": 3, "unknown": 2]
precondition(NeighborhoodFeedback.decode(NeighborhoodFeedback.encode([dirty]))[0].scores == ["family": 3], "Invalid metrics or scores cannot become ratings")
precondition(NeighborhoodMetric.allCases.count == 4)
print("PASS: explicit visits, passport totals/filtering/chronology, deduplication/persistence, unrated defaults and personal feedback aliases/validation")
'''
with tempfile.TemporaryDirectory(prefix='trippy-world-tests-',dir='/tmp') as folder:
 p=Path(folder); swift=p/'WorldChecks.swift'; binary=p/'world-checks'
 swift.write_text('import Foundation\nimport MapKit\nimport SwiftUI\n'+geo+models+checks)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.local/library-design/modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
