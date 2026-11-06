#!/usr/bin/env python3
"""Render production Been labels at local, continental and globe zoom."""
from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'ios/Trippy/TrippyApp.swift').read_text()
style=s[s.index('private enum MapCityLabelStyle'):s.index('private enum MapMarkerAppearance')]
label=s[s.index('struct MapCityLabel:'):s.index('#Preview("Map city label sizes")')]
# ImageRenderer cannot capture native Liquid Glass; render its production fallback shape.
label=label.replace('.modifier(CityNameMapPinGlass())', '.background(CityNameMapPinShape().fill(Color(hex: "53605A").opacity(0.5))).overlay(CityNameMapPinShape().stroke(.white.opacity(0.4),lineWidth:0.7))')
adapters=r'''
import AppKit
extension Color {
 init(hex: String) { let v=UInt64(hex,radix:16)!;self.init(red:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255) }
}
enum MapCityGrouping {
 static func name(_ value:String)->String { value }
 static func countryCode(in value:String)->String? { nil }
}
@main struct Render {
 @MainActor static func main() throws {
 let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
 for scheme in [ColorScheme.light,.dark] {
 let content=VStack(alignment:.leading,spacing:28) {
  ForEach([0.03,16.0,180.0],id:\.self) { span in
   VStack(alignment:.leading,spacing:16) {
    Text("Zoom span \(span.formatted())°").font(.caption).foregroundStyle(.secondary)
    MapCityLabel(city:"Barcelona",countryCode:"ES",span:span,isVisited:true)
    MapCityLabel(city:"Thessaloniki",countryCode:"GR",span:span,isVisited:true)
    MapCityLabel(city:"Newcastle upon Tyne",countryCode:"GB",span:span,isVisited:true)
    MapCityLabel(city:"San Francisco",countryCode:"US",span:span,isVisited:true)
    MapCityLabel(city:"Tokyo",countryCode:"JP",span:span,isVisited:true)
    MapCityLabel(city:"Barcelona",countryCode:"ES",span:span,isVisited:false)
    CityNameMapPinFace(city:"Barcelona",countryCode:"ES",count:2,span:span,visited:true)
    CityNameMapPinFace(city:"London",countryCode:"GB",count:nil,span:span,visited:true)
    CountryCityClusterFace(countryCode:"GR",cityCount:3,visited:true,counts:[1,2,3])
    CountryCityClusterFace(countryCode:"PL",cityCount:2,visited:false,counts:[0,0,0])
    CityMapPinSurface(city:"Barcelona",countryCode:"ES",count:nil,span:span,visited:true) {
     HStack(spacing:12) {
      Label("1",systemImage:"suitcase.rolling.fill").foregroundStyle(.purple)
      Label("2",systemImage:"mappin").foregroundStyle(.orange)
      Label("3",systemImage:"heart.fill").foregroundStyle(.pink)
     }.font(.system(size:12,weight:.bold)).padding(.top,8)
    }
   }
  }
 }.padding(28).frame(width:430,alignment:.leading).background(scheme == .dark ? Color(hex:"23303A") : Color(hex:"DCE7D5")).environment(\.colorScheme,scheme)
 let renderer=ImageRenderer(content:content);renderer.scale=2
 let data=NSBitmapImageRep(cgImage:renderer.cgImage!).representation(using:.png,properties:[:])!
 try data.write(to:output.appendingPathComponent("been-labels-\(scheme == .dark ? "dark" : "light").png"))
 }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='trippy-been-render-',dir='/tmp') as directory:
 p=Path(directory);swift=p/'Render.swift';binary=p/'render'
 swift.write_text('import SwiftUI\n'+style+label+adapters)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(ROOT/'.local/library-design/modules'),'-Xfrontend','-disable-sandbox',str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(ROOT/'docs/been-design')],check=True)
