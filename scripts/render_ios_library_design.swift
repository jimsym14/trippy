// Invoked by render_ios_library_design.py with the actual extracted app components.
import SwiftUI
import AppKit
import CoreText

private struct IdentityGallery: View {
    let page: String
    @State private var appearance: MarkAppearance
    @Environment(\.colorScheme) private var scheme
    init(page: String) {
        self.page = page
        _appearance = State(initialValue: MarkAppearance(glyph: MarkGlyphCatalog.choices(page)[0].glyph, kind: MarkGlyphCatalog.kind(page), colorHex: "B18BCC"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Το δικό σου στυλ").font(.system(size: 28, weight: .bold)).foregroundStyle(LibraryColors.ink(scheme))
            HStack(spacing: 18) {
                MarkIconWell(appearance: appearance, fallback: "suitcase.rolling.fill", tone: .trips, size: 80)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Weekend in Barcelona").font(.headline)
                    Text("Εικονίδιο και χρώμα").font(.subheadline).foregroundStyle(LibraryColors.secondary(scheme))
                }
            }
            Text("Χρώμα").font(.headline)
            HStack(spacing: 10) {
                ForEach(MarkGlyphCatalog.colors, id: \.self) { color in
                    Circle().fill(LibraryColors.hex(color)).frame(width: 30, height: 30)
                }
            }
            HStack(spacing: 14) {
                ForEach(MarkGlyphCatalog.pages, id: \.self) { value in
                    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(value == page ? LibraryTone.trips.color(scheme) : LibraryColors.secondary(scheme))
                }
            }.padding(14).librarySurface(radius: 18)
            MarkGlyphGrid(page: page, choices: Array(MarkGlyphCatalog.choices(page).prefix(25)), appearance: $appearance,
                          defaultSymbol: "suitcase.rolling.fill", accent: LibraryTone.trips.color(scheme))
            Spacer(minLength: 0)
            LibraryCityHeading(city: "Barcelona", countryCode: "ES", count: 1, tone: .trips)
            LibraryTripFacts(dates: "5/12-9/12 2026", travelers: 2)
        }.foregroundStyle(LibraryColors.ink(scheme)).padding(22).frame(width: 402, height: 980, alignment: .topLeading)
            .background { LibraryAtmosphere(tone: .trips) }
    }
}

private struct StoredMarkerGallery: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 36) {
            Text("Μικρά σημεία στον χάρτη").font(.title2.bold())
            HStack(spacing: 38) {
                StoredLocationMarker(title: "Sagrada Família", appearance: nil, pinned: true)
                StoredLocationMarker(title: "Casa Batlló", appearance: nil, pinned: false)
            }
            HStack(spacing: 38) {
                StoredLocationMarker(title: "Sagrada Família", appearance: nil, pinned: true, compact: true)
                StoredLocationMarker(title: "Casa Batlló", appearance: nil, pinned: false, compact: true)
            }
            HStack(spacing: 38) {
                StoredLocationMarker(title: "", appearance: nil, pinned: true, showsTitle: false)
                StoredLocationMarker(title: "", appearance: nil, pinned: false, showsTitle: false)
            }
            Text("Pin · Save / συμπαγές / μακρινό").font(.caption)
        }.foregroundStyle(LibraryColors.ink(scheme)).padding(28).frame(width: 402, height: 360)
            .background { LibraryAtmosphere(tone: .pins) }
    }
}

@main
struct LibraryDesignRenderer {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/trippy-library-design")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.count > 2 {
            let fonts = URL(fileURLWithPath: CommandLine.arguments[2])
            for font in try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) where font.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
            }
        }
        let variants = [("light", ColorScheme.light, DynamicTypeSize.large, LibraryTone.trips),
                        ("dark", ColorScheme.dark, DynamicTypeSize.large, LibraryTone.trips),
                        ("large-text", ColorScheme.light, DynamicTypeSize.accessibility1, LibraryTone.trips)]
            + LibraryTone.allCases.flatMap { tone in
                [(tone.rawValue + "-light", ColorScheme.light, DynamicTypeSize.large, tone),
                 (tone.rawValue + "-dark", ColorScheme.dark, DynamicTypeSize.large, tone)]
            }
        for scheme in [ColorScheme.light, .dark] {
            let markerRenderer = ImageRenderer(content: StoredMarkerGallery().environment(\.colorScheme, scheme))
            markerRenderer.scale = 2
            let markerData = NSBitmapImageRep(cgImage: markerRenderer.cgImage!).representation(using: .png, properties: [:])!
            try markerData.write(to: directory.appendingPathComponent("stored-markers-\(scheme == .dark ? "dark" : "light").png"))
            for page in MarkGlyphCatalog.pages {
                let renderer = ImageRenderer(content: IdentityGallery(page: page).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = renderer.cgImage!
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                try data.write(to: directory.appendingPathComponent("identity-\(page.lowercased())-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        for (name, scheme, typeSize, tone) in variants {
            let renderer = ImageRenderer(content: LibraryDesignGallery(tone: tone).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, typeSize))
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: directory.appendingPathComponent("library-\(name).png"))
        }
    }
}
