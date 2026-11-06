#!/usr/bin/env python3
"""Render the production neighborhood feedback components with explicit preview fixtures."""
from pathlib import Path
import subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parents[1]
app=(ROOT/'ios/Trippy/TrippyApp.swift').read_text()
world=(ROOT/'ios/Trippy/WorldExplorer.swift').read_text()
geo=app[app.index('struct GeoBoundaryPoint:'):app.index('private struct GeoBoundaryMetadata:')]
models=world[:world.index('struct NeighborhoodDetailView:')]
statlas=(ROOT/'ios/Trippy/Statlas.swift').read_text()
models+=statlas[:statlas.index('actor StatlasRepository')]
ui=world[world.index('struct NeighborhoodHeading:'):world.index('struct VisitedPlacePicker:')]+statlas[statlas.index('struct StatlasContextContent:'):statlas.index('struct NativeLookAroundCard:')]
lib=app[app.index('enum LibrarySourceStatus:'):app.index('private enum TripDateLabel {')]+app.split('// MARK: - Library design components',1)[1]
output=Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/trippy-neighborhood-design').resolve()
renderer=r'''
import AppKit
import CoreText
struct FeedbackGallery: View {
 let filled: Bool
 @Environment(\.colorScheme) private var scheme
 @State private var scores: [String:Int]
 init(filled:Bool) { self.filled=filled; _scores=State(initialValue:filled ? ["safety":4,"budget":3,"family":2,"nightlife":5] : [:]) }
 let place = NeighborhoodPlace(id:"preview",name:"El Born",latitude:41.38,longitude:2.17,city:"Barcelona")
 var body: some View {
  VStack(alignment:.leading,spacing:18) {
   NeighborhoodHeading(place:place)
   StatlasContextContent(context:filled ? StatlasCityContext(name:"Barcelona",country:"Spain",safety:89.8,cost:158.2,bars:797) : nil,loading:false,failed:false)
   Text("Η δική σου εμπειρία").font(.custom("PlusJakartaSans-Bold",size:21))
   Text("Προσωπικό feedback · επίλεξε μόνο όσα γνωρίζεις.").font(.subheadline).foregroundStyle(.secondary)
   ForEach(NeighborhoodMetric.allCases) { metric in
    NeighborhoodScoreRow(metric:metric,score:Binding(get:{ scores[metric.rawValue] },set:{ scores[metric.rawValue]=$0 }))
   }
   Text("Preview fixture · Apple Maps περιοχή / STATLAS πόλη").font(.caption).foregroundStyle(.secondary)
  }.foregroundStyle(LibraryColors.ink(scheme)).padding(22).frame(width:402)
   .background { LibraryAtmosphere(tone:.trips) }
   .onAppear { if filled { scores=["safety":4,"budget":3,"family":2,"nightlife":5] } }
 }
}
@main struct Render {
 @MainActor static func main() throws {
  let folder=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let fonts=URL(fileURLWithPath:CommandLine.arguments[2])
  for font in try FileManager.default.contentsOfDirectory(at:fonts,includingPropertiesForKeys:nil) where font.pathExtension=="ttf" { CTFontManagerRegisterFontsForURL(font as CFURL,.process,nil) }
  for scheme in [ColorScheme.light,.dark] {
   for filled in [false,true] {
    let renderer=ImageRenderer(content:FeedbackGallery(filled:filled).environment(\.colorScheme,scheme));renderer.scale=2
    let data=NSBitmapImageRep(cgImage:renderer.cgImage!).representation(using:.png,properties:[:])!
    try data.write(to:folder.appendingPathComponent("neighborhood-\(scheme == .dark ? "dark" : "light")-\(filled ? "rated" : "empty").png"))
   }
  }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='trippy-neighborhood-render-',dir='/tmp') as directory:
 p=Path(directory);swift=p/'Render.swift';binary=p/'render'
 swift.write_text('import Foundation\nimport MapKit\nimport SwiftUI\n'+geo+models+ui+lib+renderer)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(ROOT/'.local/library-design/modules'),'-Xfrontend','-disable-sandbox',str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(output),str(ROOT/'ios/Trippy/Resources')],check=True)
print(output)
