#!/usr/bin/env python3
"""Render production Been UI with a clearly separate lightweight globe fixture.
Native Map and Liquid Glass require Simulator; the gallery uses material fallbacks.
"""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'ios/Trippy/BeenLibraryDesign.swift').read_text()
w=(ROOT/'ios/Trippy/WorldExplorer.swift').read_text()
models=w[w.index('struct VisitedPlace:'):w.index('enum WorldContinentCatalog')]+w[w.index('enum WorldContinentCatalog'):w.index('struct NeighborhoodPlace:')]+w[w.index('struct VisitedCountryGroup:'):w.index('struct WorldCountryVisitsView:')]
components=s[:s.index('struct WorldGlobeView:')]+s[s.index('enum BeenContinentName'):s.index('struct BeenCollectionSheet:')]+s[s.index('struct BeenShareArtwork:'):s.index('struct BeenShareSheet:')]+s[s.index('struct BeenVisitSearchField:'):s.index('struct BeenClusterSelection:')]
components=components.replace('.navigationBarTitleDisplayMode(.inline)', '')
a=components.index('            TextField("City or place"');b=components.index('            if loading',a)
components=components[:a]+'            Text(query.isEmpty ? "City or place" : query).font(.custom("PlusJakartaSans-Medium", size: 17)).frame(maxWidth: .infinity, alignment: .leading)\n'+components[b:]
# Native glass isn't supported by ImageRenderer. Use its production material fallback.
a=components.index('struct BeenGlassSurface:');b=components.index('struct BeenRoundButton:',a)
components=components[:a]+'''struct BeenGlassSurface: ViewModifier { var radius: CGFloat = 28
 func body(content:Content)->some View { content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:radius)) }
}
'''+components[b:]
a=components.index('struct BeenSearchGlass:');b=components.index('struct BeenSearchPrompt:',a)
components=components[:a]+'''struct BeenSearchGlass:ViewModifier { let focused:Bool
 func body(content:Content)->some View { content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:23)).overlay(RoundedRectangle(cornerRadius:23).strokeBorder(BeenPalette.amber.opacity(0.3),lineWidth:1)) }
}
'''+components[b:]
runner=r'''
import AppKit
import CoreText
struct WorldGlobeView {
 static func flag(_ code:String?)->String {
  guard let code,code.count==2 else {return "🌍"}
  return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap {UnicodeScalar($0.value+127397)}))
 }
}
let sample:[VisitedPlace] = [
 VisitedPlace(name:"Barcelona",countryCode:"ES",latitude:41.38,longitude:2.17,visitedAt:Date(timeIntervalSince1970:1764000000)),
 VisitedPlace(name:"London",countryCode:"GB",latitude:51.5,longitude:-0.12,visitedAt:Date(timeIntervalSince1970:1756000000)),
 VisitedPlace(name:"Thessaloniki",countryCode:"GR",latitude:40.63,longitude:22.94,visitedAt:Date(timeIntervalSince1970:1744000000)),
 VisitedPlace(name:"San Francisco",countryCode:"US",latitude:37.77,longitude:-122.4,visitedAt:Date(timeIntervalSince1970:1724000000)),
 VisitedPlace(name:"Tokyo",countryCode:"JP",latitude:35.68,longitude:139.65,visitedAt:Date(timeIntervalSince1970:1694000000))]
struct Gallery:View {
 let variant:String
 @Environment(\.colorScheme) private var scheme
 @State private var query="Barcelona"
 @FocusState private var focused:Bool
 var snapshot:BeenPassportSnapshot {BeenPassportSnapshot(variant == "empty" ? [] : sample)}
 var body:some View {
  VStack(alignment:.leading,spacing:20) {
   Text("Been to / \(variant)").font(.custom("PlusJakartaSans-Bold",size:30)).tracking(-1)
   if variant == "share-globe" || variant == "share-flags" {
    BeenShareCard(snapshot:snapshot,style:variant == "share-globe" ? .globe : .flags).frame(maxWidth:.infinity)
   } else if variant == "search" {
    Text("Where have you been?").font(.custom("PlusJakartaSans-Bold",size:30)).tracking(-1)
    Text("").font(.subheadline).foregroundStyle(BeenPalette.secondary(scheme))
    BeenVisitSearchField(query:$query,focused:$focused,loading:false)
    HStack { Image(systemName:"calendar");Text("Visit date");Spacer();Text("4 Nov 2026").fontWeight(.semibold)}.font(.system(size:13)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.horizontal,5)
    Text("CHOOSE A CITY").font(.system(size:10,weight:.bold)).tracking(1.4).foregroundStyle(BeenPalette.secondary(scheme))
    BeenVisitSearchResult(place:sample[0],recorded:false,action:{})
    BeenVisitSearchResult(place:VisitedPlace(name:"Barcelona",countryCode:"VE",latitude:10.13,longitude:-64.7),recorded:false,action:{})
    BeenVisitSearchResult(place:sample[1],recorded:true,action:{})
   } else if variant == "countries" {
    Text("Countries").font(.custom("PlusJakartaSans-Bold",size:30)).tracking(-1)
    ForEach(snapshot.countries) {group in BeenCountryRow(group:group,action:{})}
    Text("Cities").font(.custom("PlusJakartaSans-Bold",size:23))
    BeenVisitRow(place:sample[0],action:{})
   } else {
    HStack {Text("You have been to").font(.custom("PlusJakartaSans-Bold",size:25)).tracking(-0.6);Spacer();BeenAddVisitButton(action:{})}
    BeenShareArtwork(visits:snapshot.visits).frame(height:variant == "collapsed" ? 350 : 100).background(Color.black.opacity(scheme == .dark ? 0.8 : 0.75),in:RoundedRectangle(cornerRadius:24))
    VStack(spacing:0) {
     Capsule().fill(BeenPalette.secondary(scheme).opacity(0.3)).frame(width:34,height:4).padding(.top,10).padding(.bottom,16)
     HStack { Label("World",systemImage:"globe").font(.system(size:11,weight:.semibold)).padding(10).background(BeenPalette.amber.opacity(0.16),in:Capsule());Text("Europe").font(.system(size:11,weight:.medium)).padding(10);Spacer();Image(systemName:"plus").frame(width:44,height:44).background(BeenPalette.amber,in:Circle()).foregroundStyle(.black)}.padding(.horizontal,16)
     if variant == "collapsed" { Text("5 countries & regions · 5 cities").font(.system(size:12)).foregroundStyle(BeenPalette.secondary(scheme)).frame(maxWidth:.infinity,alignment:.leading).padding(18) }
     else { BeenPassportContents(snapshot:snapshot,onCollection:{_ in},onCountry:{_ in},onAdd:{}) }
    }.background(BeenPalette.base(scheme).opacity(0.8)).modifier(BeenGlassSurface(radius:30))
   }
  }.padding(22).frame(width:402,alignment:.topLeading).foregroundStyle(BeenPalette.ink(scheme)).background(BeenPalette.base(scheme)).environment(\.colorScheme,scheme)
 }
}
@main struct Render {
 @MainActor static func main() throws {
  let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  let fontDirectory=URL(fileURLWithPath:CommandLine.arguments[2]);for file in try FileManager.default.contentsOfDirectory(at:fontDirectory,includingPropertiesForKeys:nil) where file.pathExtension == "ttf" {CTFontManagerRegisterFontsForURL(file as CFURL,.process,nil)}
  for scheme in [ColorScheme.light,.dark] {
   for variant in ["collapsed","passport","empty","countries","search","share-globe","share-flags"] {
    let renderer=ImageRenderer(content:Gallery(variant:variant).environment(\.colorScheme,scheme));renderer.scale=2
    let data=NSBitmapImageRep(cgImage:renderer.cgImage!).representation(using:.png,properties:[:])!
    try data.write(to:output.appendingPathComponent("library-been-\(variant)-\(scheme == .dark ? "dark" : "light").png"))
   }
  }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='trippy-been-library-',dir='/tmp') as directory:
 p=Path(directory);swift=p/'Render.swift';binary=p/'render'
 swift.write_text('import SwiftUI\nimport MapKit\n'+models+components+runner)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(ROOT/'.local/library-design/modules'),'-Xfrontend','-disable-sandbox',str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(ROOT/'docs/been-design'),str(ROOT/'ios/Trippy/Resources')],check=True)
print('Rendered Been Library galleries (fixture globe, material glass fallback).')
