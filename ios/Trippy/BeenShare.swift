import SwiftUI
import MapKit

enum BeenShareStyle: String, CaseIterable, Identifiable {
    case globe = "Globe", passport = "Passport", flags = "Flags", poster = "Poster"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .globe: "globe.europe.africa"; case .passport: "seal"; case .flags: "flag.2.crossed"; case .poster: "textformat.size" }
    }
}
enum BeenShareFormat: String, CaseIterable, Identifiable {
    case story = "Story", square = "Square"
    var id: String { rawValue }
    var size: CGSize { self == .story ? CGSize(width: 360, height: 640) : CGSize(width: 360, height: 360) }
}
enum BeenShareTheme: String, CaseIterable, Identifiable {
    case night = "Night", paper = "Paper"
    var id: String { rawValue }
    var background: [Color] { self == .night ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.03, green: 0.035, blue: 0.045)] : [Color(red: 0.98, green: 0.96, blue: 0.92), Color(red: 0.94, green: 0.91, blue: 0.85)] }
    var ink: Color { self == .night ? .white : Color(red: 0.12, green: 0.11, blue: 0.1) }
    var soft: Color { ink.opacity(0.6) }
    var accent: Color { self == .night ? BeenPalette.amber : Color(red: 0.75, green: 0.38, blue: 0.2) }
}

struct BeenShareCard: View {
    let snapshot: BeenPassportSnapshot
    var style: BeenShareStyle = .globe
    var format: BeenShareFormat = .story
    var theme: BeenShareTheme = .night
    var globe: UIImage? = nil
    var scopeTitle = ""

    var body: some View {
        let size = format.size
        VStack(alignment: .leading, spacing: format == .story ? 18 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("been to").font(.system(size: format == .story ? 30 : 22, weight: .light, design: .serif)).italic().foregroundStyle(theme.accent)
                Spacer()
                if !scopeTitle.isEmpty { Text(scopeTitle.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(theme.soft) }
            }
            artwork.frame(maxWidth: .infinity, maxHeight: .infinity)
            stats
            HStack {
                Text("TRIPPY").font(.system(size: 9, weight: .heavy)).tracking(3)
                Spacer()
                if let first = snapshot.years.last, let last = snapshot.years.first {
                    Text(first == last ? String(first) : "\(first) – \(last)").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(theme.soft)
        }
        .padding(format == .story ? 28 : 22)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(theme.ink)
        .background(LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var artwork: some View {
        switch style {
        case .globe:
            ZStack {
                Circle().fill(RadialGradient(colors: [theme.accent.opacity(0.28), .clear], center: .center, startRadius: 10, endRadius: 190))
                if let globe { Image(uiImage: globe).resizable().scaledToFit().shadow(color: .black.opacity(0.35), radius: 18, y: 10) }
                else { Circle().fill(theme.ink.opacity(0.06)).overlay(Circle().strokeBorder(theme.ink.opacity(0.15))) }
            }
        case .passport: PassportStamps(snapshot: snapshot, theme: theme, limit: format == .story ? 15 : 8)
        case .flags: FlagWall(snapshot: snapshot, theme: theme, limit: format == .story ? 20 : 10)
        case .poster: PosterNumbers(snapshot: snapshot, theme: theme, story: format == .story)
        }
    }

    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            metric(snapshot.countryCount, snapshot.countryCount == 1 ? "country" : "countries")
            metric(snapshot.visits.count, snapshot.visits.count == 1 ? "city" : "cities")
            metric(snapshot.continents.count, snapshot.continents.count == 1 ? "continent" : "continents")
        }
    }
    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(.system(size: format == .story ? 30 : 24, weight: .bold, design: .serif)).foregroundStyle(theme.accent)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.soft)
        }
    }
}

/// Country codes as ink stamps with the year of the first visit.
private struct PassportStamps: View {
    let snapshot: BeenPassportSnapshot
    let theme: BeenShareTheme
    let limit: Int
    var body: some View {
        let groups = Array(snapshot.countries.sorted { firstYear($0) < firstYear($1) }.prefix(limit))
        let palette: [Color] = [theme.accent, Color(CountryPalette.recent), Color(CountryPalette.continent("South America")), Color(CountryPalette.continent("North America")), Color(CountryPalette.heat)]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                let color = palette[index % palette.count]
                let round = index % 3 != 1
                VStack(spacing: 1) {
                    Text(group.countryCode ?? "—").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text(String(firstYear(group))).font(.system(size: 8, weight: .bold)).tracking(1)
                    Text("\(group.visits.count) \(group.visits.count == 1 ? "CITY" : "CITIES")").font(.system(size: 6, weight: .bold)).tracking(0.8)
                }
                .foregroundStyle(color)
                .frame(width: 78, height: round ? 78 : 64)
                .overlay {
                    if round { Circle().strokeBorder(color, lineWidth: 2).overlay(Circle().strokeBorder(color.opacity(0.4), lineWidth: 1).padding(4)) }
                    else { RoundedRectangle(cornerRadius: 8).strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 2])) }
                }
                .rotationEffect(.degrees(Double((index * 47) % 26) - 13))
                .opacity(0.92)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
    private func firstYear(_ group: VisitedCountryGroup) -> Int {
        group.visits.map { Calendar.current.component(.year, from: $0.visitedAt) }.min() ?? 0
    }
}

private struct FlagWall: View {
    let snapshot: BeenPassportSnapshot
    let theme: BeenShareTheme
    let limit: Int
    var body: some View {
        let groups = Array(snapshot.countries.sorted { $0.visits.count > $1.visits.count }.prefix(limit))
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(groups) { group in
                    VStack(spacing: 4) {
                        Image(uiImage: GeneralMapMarkerView.flagImage(group.countryCode) ?? UIImage()).resizable().scaledToFill()
                            .frame(width: 46, height: 46).clipShape(Circle())
                            .overlay(Circle().strokeBorder(theme.ink.opacity(0.85), lineWidth: 1.5))
                        Text(group.countryCode ?? "").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.soft)
                    }
                }
            }
            if snapshot.countryCount > limit {
                Text("+ \(snapshot.countryCount - limit) more").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct PosterNumbers: View {
    let snapshot: BeenPassportSnapshot
    let theme: BeenShareTheme
    let story: Bool
    var body: some View {
        let share = Double(snapshot.countryCount) / Double(BeenPassportSnapshot.worldCountries)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Int((share * 100).rounded()))%").font(.system(size: story ? 120 : 76, weight: .bold, design: .serif)).foregroundStyle(theme.accent)
                .minimumScaleFactor(0.6)
            Text("of the world’s countries").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.soft)
            if story {
                VStack(spacing: 7) {
                    ForEach(BeenContinentName.all, id: \.self) { name in
                        let have = snapshot.continentCounts[name] ?? 0
                        let total = WorldContinentCatalog.count(name)
                        HStack(spacing: 8) {
                            Text(BeenContinentName.title(name)).font(.system(size: 10, weight: .semibold)).frame(width: 72, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.ink.opacity(0.08))
                                    Capsule().fill(Color(CountryPalette.continent(name))).frame(width: max(4, geo.size.width * CGFloat(have) / CGFloat(max(total, 1))))
                                }
                            }
                            .frame(height: 6)
                            Text("\(have)/\(total)").font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(theme.soft).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct BeenShareSheet: View {
    let snapshot: BeenPassportSnapshot
    var texture: UIImage? = nil
    var scopeTitle = ""
    @State private var style: BeenShareStyle = .globe
    @State private var format: BeenShareFormat = .story
    @State private var theme: BeenShareTheme = .night
    @State private var globe: UIImage?
    @State private var export: Image?
    @State private var ownTexture: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BeenSheetFrame(title: "Share", subtitle: "") {
            VStack(spacing: 18) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(BeenShareStyle.allCases) { option in
                            Button { style = option } label: {
                                Label(option.rawValue, systemImage: option.symbol).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                                    .padding(.horizontal, 14).frame(height: 38)
                                    .foregroundStyle(style == option ? Sketch.paper : BeenPalette.ink(scheme))
                                    .background(Capsule().fill(style == option ? Sketch.ink : BeenPalette.ink(scheme).opacity(0.06)))
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(style == option ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    Picker("Format", selection: $format) { ForEach(BeenShareFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Picker("Theme", selection: $theme) { ForEach(BeenShareTheme.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
                card.scaleEffect(previewScale, anchor: .top)
                    .frame(width: format.size.width * previewScale, height: format.size.height * previewScale)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .frame(maxWidth: .infinity)
                    .animation(.snappy, value: format)
                if let export {
                    ShareLink(item: export, preview: SharePreview("Been to", image: export)) {
                        Label("Share image", systemImage: "square.and.arrow.up").font(Sketch.text(16, "Bold", relativeTo: .headline))
                            .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(Sketch.paper)
                            .background(Capsule().fill(Sketch.ink))
                    }
                } else {
                    ProgressView().frame(height: 52)
                }
                ShareLink(item: snapshot.shareText) {
                    Label("Share as text", systemImage: "text.alignleft").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .presentationDetents([.large])
        .task { await prepareGlobe() }
        .task(id: "\(style.rawValue):\(format.rawValue):\(theme.rawValue):\(globe != nil)") { renderExport() }
    }

    private var previewScale: CGFloat { format == .story ? 0.78 : 0.92 }
    private var card: BeenShareCard { BeenShareCard(snapshot: snapshot, style: style, format: format, theme: theme, globe: globe, scopeTitle: scopeTitle) }

    @MainActor private func prepareGlobe() async {
        var image = texture
        if image == nil {
            image = await GlobeTextureBuilder.shared.texture(key: GlobeTextureKey(dark: true, satellite: false, style: "share:\(snapshot.countries.map(\.id).joined())"),
                                                            shapes: nil, visits: snapshot.visits)
        }
        let center = snapshot.visits.isEmpty ? CLLocationCoordinate2D(latitude: 35, longitude: 15)
            : CLLocationCoordinate2D(latitude: snapshot.visits.map(\.latitude).reduce(0, +) / Double(snapshot.visits.count),
                                     longitude: snapshot.visits.map(\.longitude).reduce(0, +) / Double(snapshot.visits.count))
        globe = GlobeSnapshot.render(texture: image, center: center)
    }

    @MainActor private func renderExport() {
        export = nil
        let renderer = ImageRenderer(content: card); renderer.scale = 3
        if let image = renderer.uiImage { export = Image(uiImage: image) }
    }
}
