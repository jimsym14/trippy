#!/usr/bin/env python3
"""Exercise production Been geometry preparation with dense, tiny and dateline rings."""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
app=(ROOT/'ios/Trippy/TrippyApp.swift').read_text()
source=(ROOT/'ios/Trippy/BeenMapPresentation.swift').read_text()
geo=app[app.index('struct GeoBoundaryPoint:'):app.index('private struct GeoBoundaryMetadata:')]
simplify=app[app.index('    private static func normalized(_ value: String)', app.index('actor GeoBoundaryRepository')):app.index('\nprivate struct PinCelebrationView:')]
models=source[:source.index('struct BeenBoundaryMapLayer')]+source[source.index('struct MapCityScreenFootprint'):]
checks=r'''
@main struct Checks {
 static func main() async {
  var ring=(0..<5000).map { i in
   let a=Double(i)*2*Double.pi/5000
   return GeoBoundaryPoint(latitude: 40+sin(a)*4, longitude: -3+cos(a)*4)
  };ring.append(ring[0])
  let tiny=[GeoBoundaryPoint(latitude:40,longitude:0),.init(latitude:40.001,longitude:0),.init(latitude:40.001,longitude:0.001),.init(latitude:40,longitude:0)]
  let lines=[GeoBoundaryLine(id:"main-fill",points:ring,style:.fill),.init(id:"main-outline",points:ring,style:.outline),.init(id:"tiny-fill",points:tiny,style:.fill),.init(id:"hatch",points:Array(ring.prefix(2)),style:.texture)]
  let wrongScope=Data(#"{"features":[{"properties":{"shapeName":"Westminster"},"geometry":{"type":"Polygon","coordinates":[[[-1,50],[1,50],[1,52],[-1,52],[-1,50]]]}}]}"#.utf8)
  precondition(GeoBoundaryRepository.matchingBoundary(in:wrongScope,names:["london","greater london"],center:.init(latitude:51.5,longitude:0),includeTexture:false,requireNameMatch:true)==nil,"An unnamed containing borough must not become the city surface")
  let namedScope=Data(String(data:wrongScope,encoding:.utf8)!.replacingOccurrences(of:"Westminster",with:"Greater London").utf8)
  precondition(GeoBoundaryRepository.matchingBoundary(in:namedScope,names:["london","greater london"],center:.init(latitude:51.5,longitude:0),includeTexture:false,requireNameMatch:true) != nil,"Named Greater London is accepted")
  func city(_ id:String,_ code:String,_ x:Double,_ y:Double,_ latitude:Double=40,_ longitude:Double=20)->MapCityScreenFootprint {
    .init(id:id,countryCode:code,point:.init(x:x,y:y),size:.init(width:100,height:30),latitude:latitude,longitude:longitude)
  }
  let cityInput=[city("athens","GR",100,100),city("thessaloniki","GR",140,120),city("plovdiv","BG",110,110),city("london","GB",400,400)]
  let clusters=MapCountryCityClustering.groups(cityInput)
  precondition(clusters.count==1 && clusters[0].countryCode=="" && clusters[0].memberIDs==["athens","plovdiv","thessaloniki"],"Overlapping city blobs merge across borders without losing members")
  precondition(MapCountryCityClustering.groups([city("a","GR",0,0),city("b","GR",300,0)]).isEmpty,"Distinct cities remain independent")
  let chain=MapCountryCityClustering.groups([city("a","GR",0,0),city("b","GR",90,0),city("c","GR",180,0)])
  precondition(chain.count==1 && chain[0].memberIDs.count==3,"Connected overlapping city pins form one group")
  let panned=cityInput.map{MapCityScreenFootprint(id:$0.id,countryCode:$0.countryCode,point:.init(x:$0.point.x+1000,y:$0.point.y-700),size:$0.size,latitude:$0.latitude,longitude:$0.longitude)}
  precondition(MapCountryCityClustering.groups(panned)==clusters,"Panning preserves cluster identity and geographical anchor")
  precondition(MapCountryCityClustering.groups(Array(cityInput.reversed()))==clusters,"Input order does not reshuffle groups")
  let wrapped=MapCountryCityClustering.groups([city("a","FJ",0,0,0,179),city("b","FJ",20,0,0,-179)])
  precondition(abs(wrapped[0].longitude)>179,"A wrapped country cluster stays at the dateline")
  let start=Date()
  let prepared=await BeenBoundaryPreparation.shared.prepare(lines,city:false)
  let firstElapsed=Date().timeIntervalSince(start)
  let far=prepared[.world]!,close=prepared[.local]!
  precondition(far.fills.count==1 && close.fills.count==2,"Subpixel islands are culled only at distant zoom")
  precondition(far.fills[0].points.count<=64 && close.fills[0].points.count<=480)
  precondition(far.fills[0].points.first==far.fills[0].points.last,"Polygon closure survives simplification")
  precondition(far.fills[0].id==close.fills[0].id,"LOD changes preserve native map identity")
  precondition(BeenBoundaryDetail.at(span:1) == .local && BeenBoundaryDetail.at(span:8) == .regional && BeenBoundaryDetail.at(span:40) == .world)
  precondition(prepared.values.allSatisfy{$0.textures.isEmpty},"Country overlays never contain hatches")
  let hatched=await BeenBoundaryPreparation.shared.prepare(lines,city:false,includeCountryHatches:true)
  precondition(hatched[.world]!.textures.count==1,"The country crossing-lines option works at far zoom")
  let city=await BeenBoundaryPreparation.shared.prepare(lines,city:true)
  precondition(city[.world]!.fills.isEmpty && city[.regional]!.textures.isEmpty && city[.local]!.textures.count==1,"City geometry/hatches are local only")
  let dateline=[GeoBoundaryPoint(latitude:0,longitude:179.99),.init(latitude:0.01,longitude:-179.99),.init(latitude:0.01,longitude:179.99),.init(latitude:0,longitude:179.99)]
  precondition(BeenBoundaryPreparation.extent(dateline)<0.03,"Dateline islands are not treated as 360-degree polygons")
  let cachedStart=Date();let again=await BeenBoundaryPreparation.shared.prepare(lines,city:false)
  precondition(again[.world]!.fills[0].points==far.fills[0].points)
  print("PASS: cross-border overlap clustering, pan/order/dateline stability, named scopes, LOD budgets, hatch options, ring closure and island culling")
  print("Dense fixture: \(ring.count) → \(far.fills[0].points.count) far vertices; prepare \(firstElapsed)s; cached \(Date().timeIntervalSince(cachedStart))s")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='trippy-been-tests-',dir='/tmp') as folder:
 p=Path(folder);swift=p/'Checks.swift';binary=p/'checks'
 swift.write_text('import Foundation\nimport MapKit\nimport SwiftUI\n'+geo+'struct GeoBoundaryRepository {\n'+simplify+models+checks)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(ROOT/'.local/library-design/modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
