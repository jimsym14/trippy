#!/usr/bin/env python3
"""Compile production matching against captured public API responses (no network)."""
from pathlib import Path
import subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'ios/Trippy/Statlas.swift').read_text()
models = source[:source.index('actor StatlasRepository')]
checks = r''' 
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let map = try JSONDecoder().decode(StatlasMapResponse.self, from: Data(contentsOf: folder.appendingPathComponent("statlas-map.json")))
let search = try JSONDecoder().decode(StatlasSearchResponse.self, from: Data(contentsOf: folder.appendingPathComponent("statlas-cities.json")))
let barcelona = StatlasCityContext.match(points: map.points, latitude: 41.38879, longitude: 2.15899, countryCode: "ES")!
precondition(barcelona.name == "Barcelona" && barcelona.country == "Spain")
precondition(barcelona.safety == 89.8 && barcelona.cost == 158.2 && barcelona.bars == 797)
precondition(StatlasCityContext.match(points: map.points, latitude: 41.38, longitude: 2.17, countryCode: "VE") == nil, "Country homonyms must never cross continents")
precondition(StatlasCityContext.match(points: map.points, latitude: 0, longitude: 0, countryCode: nil) == nil, "Distant cities cannot supply a local rating")
precondition(StatlasCityContext.match(points: map.points, latitude: 999, longitude: 0, countryCode: nil) == nil)
let fallback = StatlasCityContext.match(cities: search.cities, name: "Bárcelona", countryCode: "ES")!
precondition(fallback.country == "Spain" && fallback.cost == 158.2 && fallback.safety == nil && fallback.bars == nil, "Search-only cost data cannot invent other indices")
precondition(StatlasCityContext.match(cities: search.cities, name: "Barcelona", countryCode: nil) == nil, "Coordinate-free search requires country disambiguation")
let missing = StatlasPoint(s: "test", n: "Test", c: "Spain", lat: 41.38, lon: 2.17, v: ["safety-index": 120, "cost-of-living-index": -1, "bars": 0])
let context = StatlasCityContext.match(points: [missing], latitude: 41.38, longitude: 2.17, countryCode: "ES")!
precondition(context.safety == nil && context.cost == nil && context.bars == nil, "Invalid indices or zero amenity coverage stay unavailable")
precondition(StatlasPoint(s: "bad", n: "Bad", c: "Spain", lat: 0, lon: 0, v: ["bars": .infinity]).metric("bars") == nil)
print("PASS: real STATLAS decoding, coordinate/country matching, homonyms, search fallback and absent/invalid coverage")
'''
with tempfile.TemporaryDirectory(prefix='trippy-statlas-tests-', dir='/tmp') as folder:
 p=Path(folder); swift=p/'Checks.swift'; binary=p/'checks'
 swift.write_text(models+checks)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.local/library-design/modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(ROOT/'scripts/fixtures')],check=True)
