#!/usr/bin/env python3
"""Render the production trip collection and cards with isolated fixture data."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'ios/Trippy/TrippyApp.swift').read_text()
components=s[s.index('enum LibrarySourceStatus:'):s.index('private enum TripDateLabel {')]+s.split('// MARK: - Identity design components',1)[1].split('// MARK: - Identity editor',1)[0]+s.split('// MARK: - Library design components',1)[1]
collection=s[s.index('    private var libraryTripsCollection:'):s.index('    private var libraryAddSymbol:')]
row=s[s.index('    func libraryTripRow('):s.index('    private var tripIdentityEditor:')].replace('QuietPressStyle()', '.plain')
phase=s[s.index('private enum LibraryTripPhase:'):s.index('// One persistence gate')].replace('private enum','enum')
fixture=r'''
import AppKit
import CoreText
struct TripBrief:Equatable {
 var destination:String;var startDate:String;var endDate:String;var travelers:Int = 2;var dateIsUnknown = false
 var libraryDateSummary:String { TripDateLabel.compact(start:startDate,end:endDate,flexible:dateIsUnknown,duration:4) }
}
struct Trip:Identifiable,Equatable {
 var id=UUID();var brief:TripBrief;var title:String;var research:String? = nil;var completedAt:Date? = nil;var updatedAt=Date();var appearance:MarkAppearance? = nil
}
enum TripStorage {static func save(_ values:[Trip]) {}}
enum MapCityGrouping {
 static func key(_ city:String)->String {name(city).lowercased()}
 static func name(_ city:String)->String {city.split(separator:",").first.map(String.init) ?? city}
 static func countryCode(in city:String)->String? {city.split(separator:",").last.map {String($0).trimmingCharacters(in:.whitespaces)} }
}
extension String {var nonEmpty:String? {isEmpty ? nil:self}}
struct TripGallery:View {
 @Environment(\.colorScheme) var libraryScheme
 @State var trips:[Trip] = [
 Trip(brief:.init(destination:"Barcelona, ES",startDate:"2026-12-05",endDate:"2026-12-09"),title:"Barcelona, after hours",research:"{}"),
 Trip(brief:.init(destination:"Barcelona, ES",startDate:"2027-02-10",endDate:"2027-02-14",travelers:4),title:"A long weekend away"),
 Trip(brief:.init(destination:"Lisbon, PT",startDate:"2026-09-05",endDate:"2026-09-09"),title:"A little Lisbon"),
 Trip(brief:.init(destination:"Rome, IT",startDate:"2026-06-05",endDate:"2026-06-09"),title:"Rome, well travelled",research:"{}",completedAt:.now)]
 @State var tripIdentityTarget:UUID?;@State var showTripIdentity=false
 var reduceMotion=true
 var libraryInk:Color {LibraryColors.ink(libraryScheme)}
 var libraryMuted:Color {LibraryColors.secondary(libraryScheme)}
 var libraryAccent:Color {LibraryTone.trips.color(libraryScheme)}
 var libraryQuery="";var libraryCity:String? = nil
 var filteredLibraryTrips:[Trip] {trips}
 func libraryCountryCode(_ city:String)->String? {MapCityGrouping.countryCode(in:city)}
 func startNewTrip() {}
 func selectMapTrip(_ trip:Trip) {}
 func editTrip(_ trip:Trip) {}
 func deleteTrip(_ id:UUID) {}
 func socialPlaceVideoCarousel(city:String)->some View {EmptyView()}
 var body:some View {
 VStack(alignment:.leading,spacing:24) {
 Label("Library",systemImage:"books.vertical.fill").font(.custom("PlusJakartaSans-ExtraBold",size:32))
 HStack {Text("These are your trips").font(.custom("PlusJakartaSans-Bold",size:24));Spacer();Image(systemName:"plus").frame(width:44,height:44).librarySurface(radius:22)}
 libraryTripsCollection
 }.foregroundStyle(libraryInk).padding(22).frame(width:402).background {LibraryAtmosphere(tone:.trips)}
 }
'''
runner=r'''
}
@main struct Render {
 @MainActor static func main() throws {
  let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  for file in try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:CommandLine.arguments[2]),includingPropertiesForKeys:nil) where file.pathExtension == "ttf" {CTFontManagerRegisterFontsForURL(file as CFURL,.process,nil)}
  for scheme in [ColorScheme.light,.dark] {
   let renderer=ImageRenderer(content:TripGallery().environment(\.colorScheme,scheme));renderer.scale=2
   try NSBitmapImageRep(cgImage:renderer.cgImage!).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("trips-\(scheme == .dark ? "dark" : "light").png"))
  }
 }
}
'''
date=s[s.index('private enum TripDateLabel {'):s.index('private struct TripPreferenceOption:')]
# Date helper ends before TripPreferenceOption but includes TripBrief? use balanced declaration.
a=s.index('private enum TripDateLabel {');depth=0;b=a
for i in range(s.index('{',a),len(s)):
 if s[i]=='{':depth+=1
 if s[i]=='}':
  depth-=1
  if depth==0:b=i+1;break
date=s[a:b]
with tempfile.TemporaryDirectory(prefix='trippy-trip-gallery-',dir='/tmp') as d:
 p=Path(d); swift=p/'Render.swift';binary=p/'render'
 swift.write_text('import SwiftUI\n'+components+date+fixture.split('struct TripGallery:View')[0]+phase+'struct TripGallery:View'+fixture.split('struct TripGallery:View')[1]+collection+row+runner)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-Xfrontend','-disable-sandbox','-module-cache-path',str(ROOT/'.local/library-design/modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(ROOT/'docs/library-design'),str(ROOT/'ios/Trippy/Resources')],check=True)
print('Rendered production trip cards/sections with fixture data.')
