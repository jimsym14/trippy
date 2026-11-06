#!/usr/bin/env python3
"""Exercise the native map's production membership/count presentation model."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'ios/Trippy/BeenGlobeMap.swift').read_text()
model=source[source.index('struct GeneralMapMarker:'):source.index('#if DEBUG\n// Opt-in')]
checks=r'''
func city(_ id:String,_ name:String,_ country:String, trips:Set<String> = [],pins:Set<String> = [],saves:Set<String> = [],visited:Bool = false)->GeneralMapMarker {
 GeneralMapMarker(id:id,latitude:41,longitude:2,city:name,countryCode:country,visited:visited,isCity:true,symbol:"airplane",emoji:nil,baseMemberIDs:["trip-record"],placeMemberIDs:["pin-record","save-record"],tripIDs:trips,pinIDs:pins,saveIDs:saves)
}
let barcelona=city("b","Barcelona","ES",trips:["trip-1"],pins:["pin-1","pin-2"],saves:["save-1"],visited:true)
let madrid=city("m","Madrid","ES")
let paris=city("p","Paris","FR")
let merged=GeneralMapMarkerPresentation([barcelona,madrid,paris],local:false)
precondition(merged.cityCount==3 && merged.trips==1 && merged.pins==2 && merged.saves==1 && merged.visited)
precondition(GeneralMapMarkerPresentation([barcelona,barcelona],local:false).pins==2,"Repeated native cluster members never inflate counts")
precondition(GeneralMapMarkerPresentation([city("alias","BARCELÓNA","es"),barcelona],local:false).cityCount==1,"Aliases/country casing identify one city")
precondition(GeneralMapMarkerPresentation([city("another","Barcelona","VE"),barcelona],local:false).cityCount==2,"Different countries remain distinct cities inside a blob")
let pin=GeneralMapMarker(id:"pin",latitude:41,longitude:2,city:"Barcelona",name:"My cafe",countryCode:"ES",visited:false,isCity:false,symbol:"mappin",emoji:nil,baseMemberIDs:["pin-record"],placeMemberIDs:[],tripIDs:[],pinIDs:["pin-1"],saveIDs:[])
let local=GeneralMapMarkerPresentation([barcelona,pin],local:true)
precondition(local.cityCount==1 && local.trips==1 && local.pins==1 && local.saves==0,"Only physically attached points contribute to local city counters")
precondition(GeneralMapMarkerPresentation([barcelona,pin],local:false).pins==2,"Regional point membership deduplicates city and place annotations")
precondition(barcelona.members(local:true)==["trip-record"] && barcelona.members(local:false)==["trip-record","pin-record","save-record"])
precondition(pin.members(local:true)==["pin-record"] && pin.name=="My cafe")
precondition(GeneralMapMarkerPresentation([pin],local:true).isPoint)
precondition(!GeneralMapMarkerPresentation([barcelona],local:false).isPoint)
precondition(GeneralMapMarkerPresentation([],local:false).cityCount==0)
let filtered=GeneralMapMarkerPresentation([city("filter","Barcelona","ES",trips:["trip-1"])],local:false)
precondition(filtered.trips==1 && filtered.pins==0 && filtered.saves==0)
print("PASS: native city identities, multi-country blobs, filtered/attached counts, deduplication, exact local/regional member routing and place-name preservation")
'''
with tempfile.TemporaryDirectory(prefix='trippy-native-map-',dir='/tmp') as d:
 p=Path(d);swift=p/'Checks.swift';binary=p/'checks'
 swift.write_text('import Foundation\nimport MapKit\n'+model+checks)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.local/library-design/modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
