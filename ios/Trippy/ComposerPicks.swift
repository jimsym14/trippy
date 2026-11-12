import SwiftUI
import MapKit

// MARK: - Model

/// Where the setup gets the traveller's saves: set by the app when it opens the setup (kept out of the app's
/// main view expression, which is at the compiler's limit).
@MainActor enum ComposerSaves {
    static var provider: ((String) -> [PickInfo])?
}

/// A place the setup can suggest for "Must-see places": one of the traveller's saves, or recommended for the city.
/// Everything known about it travels with it, so any card can open to all of it.
struct PickInfo: Identifiable, Hashable {
    enum Source: Hashable { case save, recommended }
    var id: String { place.name }          // the composer identifies must-sees by name
    var place: ComposerPlace
    var source: Source
    /// The city key the save belongs to (saves only), matched against the typed destination.
    var cityKey = ""
    /// One line: the creator's summary, a guide line or Wikidata's description.
    var summary = ""
    var whyGo: [String] = []
    var tips: [String] = []
    var mustTry: [String] = []
    var goodToKnow: [String] = []
    var price: String? = nil
    var vibes: [String] = []
    /// The videos it came from, with their links.
    var videos: [Video] = []
    var pinned = false
    /// Wikipedia language editions (recommended places), a free measure of how well known it is.
    var fame = 0
    var wikiTitle: String? = nil

    struct Video: Hashable { let title: String; let url: URL? }

    static func == (a: PickInfo, b: PickInfo) -> Bool { a.id == b.id && a.source == b.source }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(source) }

    var hasInfo: Bool { !summary.isEmpty || !whyGo.isEmpty || !tips.isEmpty || !mustTry.isEmpty || !goodToKnow.isEmpty }
    /// The first thing worth reading on a card.
    var teaser: String { summary.nilIfEmpty ?? whyGo.first ?? tips.first ?? mustTry.first.map { "Try: \($0)" } ?? "" }

    var kind: PickKind { PickKind(category: place.category) }

    /// Saves with the most to go on first: something to read, then pinned, then in more videos, then more tips.
    static func rankSaves(_ saves: [PickInfo]) -> [PickInfo] {
        saves.sorted {
            ($0.hasInfo ? 1 : 0, $0.pinned ? 1 : 0, $0.videos.count, $0.tips.count + $0.whyGo.count + $0.mustTry.count, $1.place.name)
                > ($1.hasInfo ? 1 : 0, $1.pinned ? 1 : 0, $1.videos.count, $1.tips.count + $1.whyGo.count + $1.mustTry.count, $0.place.name)
        }
    }

    /// How many saves to tick by default: about two a day, never fewer than four or more than twelve.
    static func defaultCount(days: Int) -> Int { min(12, max(4, days * 2)) }
}

/// The kinds the setup groups places by.
enum PickKind: String, CaseIterable, Identifiable {
    case sights, museums, nature, food, bars, shops, other
    var id: String { rawValue }
    init(category: String) {
        switch category.lowercased() {
        case "museum", "museums": self = .museums
        case "nature", "park", "parks", "outdoors": self = .nature
        case "food", "restaurant", "coffee", "cafe", "brunch", "market": self = .food
        case "bar", "bars", "nightlife", "club": self = .bars
        case "shopping", "shop": self = .shops
        case "attraction", "sights", "sight", "landmark": self = .sights
        default: self = .other
        }
    }
    var title: String {
        switch self {
        case .sights: "Sights"; case .museums: "Museums"; case .nature: "Parks & views"; case .food: "Food & markets"
        case .bars: "Bars"; case .shops: "Shops"; case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .sights: "building.columns"; case .museums: "paintpalette"; case .nature: "leaf"; case .food: "fork.knife"
        case .bars: "wineglass"; case .shops: "bag"; case .other: "mappin"
        }
    }
    var isSight: Bool { [.sights, .museums, .nature].contains(self) }
}

// MARK: - Card

/// A fixed-size card for a horizontal row: the row never grows the page, however many places there are.
/// Tapping the card opens everything known; the round button picks or unpicks it.
struct SavePickCard: View {
    let info: PickInfo
    let picked: Bool
    var tint: Color = Sketch.ochre
    let toggle: () -> Void
    let open: () -> Void

    static let width: CGFloat = 176

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlacePhoto(name: info.place.name, latitude: info.place.latitude, longitude: info.place.longitude,
                       sight: info.kind.isSight, symbol: info.kind.symbol, tint: tint,
                       imageURL: info.place.imageURL.flatMap(URL.init(string:)))
                .frame(width: Self.width, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(picked ? Sketch.sage : .clear, lineWidth: 2.5))
                .overlay(alignment: .bottomLeading) { badge.padding(6) }
            Text(info.place.name).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            Text(info.teaser.nilIfEmpty ?? info.kind.title).font(Sketch.text(12, relativeTo: .caption))
                .foregroundStyle(info.teaser.isEmpty ? Sketch.inkFaint : Sketch.inkSoft)
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .overlay(alignment: .topTrailing) {
            Button(action: toggle) {
                Image(systemName: picked ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, picked ? Sketch.sage : Color.black.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(picked ? "Remove \(info.place.name)" : "Add \(info.place.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens what's known about it")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if !info.videos.isEmpty || info.pinned {
            Label(info.pinned ? "Pinned" : info.videos.count == 1 ? "1 video" : "\(info.videos.count) videos",
                  systemImage: info.pinned ? "pin.fill" : "play.fill")
                .font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.55)))
        }
    }
}

/// The last card of a row: everything, searchable, in a sheet.
struct SeeAllCard: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").font(.system(size: 22, weight: .semibold))
                Text("See all \(count)").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Text("Search and sort by kind").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
            .foregroundStyle(Sketch.ink)
            .frame(width: 132, height: 104)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.paperDeep))
        }
        .buttonStyle(SketchPressStyle())
    }
}

// MARK: - Detail

/// Everything known about a place, whatever kind it is: what the videos and guides say, tips, what to try,
/// what to know, price, and Wikipedia's summary for well-known sights (fetched only when this opens; free).
struct PickDetailView: View {
    let info: PickInfo
    let picked: Bool
    let toggle: () -> Void
    @State private var wiki: String?
    @State private var loadingWiki = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // What it is and what's said about it first, readable at half height; the photo follows.
                HStack(alignment: .top, spacing: 14) {
                    PlacePhoto(name: info.place.name, latitude: info.place.latitude, longitude: info.place.longitude,
                               sight: info.kind.isSight, symbol: info.kind.symbol, tint: Sketch.ochre,
                               imageURL: info.place.imageURL.flatMap(URL.init(string:)))
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.place.name).font(Sketch.display(.title2, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Label(subtitle, systemImage: info.kind.symbol).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !info.summary.isEmpty {
                    Text(info.summary).font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                group("Why go", "sparkles", info.whyGo)
                group("Tips", "lightbulb", info.tips)
                group("Must try", "fork.knife", info.mustTry)
                group("Good to know", "info.circle", info.goodToKnow)
                if let price = info.price?.nilIfEmpty {
                    Label(price, systemImage: "eurosign.circle").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                }
                if !info.vibes.isEmpty {
                    BubbleFlow(spacing: 6) { ForEach(info.vibes, id: \.self) { SketchTag(text: $0, tint: Sketch.plum) } }
                }
                if info.wikiTitle != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FROM WIKIPEDIA").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.sky)
                        if let wiki { Text(wiki).font(Sketch.text(15, relativeTo: .body)).foregroundStyle(Sketch.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                        else if loadingWiki { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                        else { Text("No summary available.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint) }
                    }
                }
                if !info.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FROM YOUR VIDEOS").font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.plum)
                        ForEach(info.videos, id: \.self) { video in
                            Button { if let url = video.url { openURL(url) } } label: {
                                Label(video.title, systemImage: "play.rectangle").font(Sketch.text(14, relativeTo: .subheadline))
                                    .foregroundStyle(video.url == nil ? Sketch.inkSoft : Sketch.ink).lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            }
                            .buttonStyle(.plain).disabled(video.url == nil)
                        }
                    }
                }
                if !info.place.address.isEmpty || info.place.latitude != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if !info.place.address.isEmpty {
                            Label(info.place.address, systemImage: "mappin").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        }
                        if let lat = info.place.latitude, let lon = info.place.longitude {
                            Button("Open in Maps", systemImage: "map") {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: lat, longitude: lon)))
                                item.name = info.place.name; item.openInMaps()
                            }
                            .font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).frame(minHeight: 44)
                        }
                    }
                }
                if !info.hasInfo && info.wikiTitle == nil && info.videos.isEmpty {
                    Text("Nothing more is known about it yet. It still counts as a must-see if you pick it.")
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                }
            }
            .padding(20)
        }
        .background(PaperBackground())
        .safeAreaInset(edge: .bottom) {
            Button(action: toggle) {
                Label(picked ? "Picked · tap to remove" : "Add to must-see", systemImage: picked ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(Sketch.text(16, "Bold", relativeTo: .headline)).frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Sketch.paper)   // dark text on the light dark-mode greens, light text in light mode
            }
            .buttonStyle(.borderedProminent).tint(picked ? Sketch.sage : Sketch.clay)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.bar)
        }
        .task(id: info.wikiTitle) { await loadWiki() }
    }

    private var subtitle: String {
        var parts = [info.kind.title]
        if info.source == .save { parts.append(info.pinned ? "Pinned by you" : "Saved by you") }
        if info.fame >= 40 { parts.append("Very well known") } else if info.fame >= 20 { parts.append("Well known") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func group(_ title: String, _ symbol: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title.uppercased(), systemImage: symbol).font(Sketch.eyebrow).tracking(1).foregroundStyle(Sketch.clay)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Sketch.inkFaint)
                        Text(line).font(Sketch.text(15, relativeTo: .body)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Wikipedia's lead paragraph, only when the sheet opens (free, no key).
    private func loadWiki() async {
        guard let title = info.wikiTitle, wiki == nil else { return }
        loadingWiki = true; defer { loadingWiki = false }
        let path = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)") else { return }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        request.setValue("Trippy/0.1 (trip planner prototype)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        wiki = (json["extract"] as? String)?.nilIfEmpty
    }
}

// MARK: - See all

/// Every save or recommendation, searchable and grouped by kind; each row opens its details.
struct PickListSheet: View {
    let title: String
    let items: [PickInfo]
    @Binding var picked: [ComposerPlace]
    /// Saves only: tick the best N again, or none.
    var bestCount: Int? = nil
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private func isPicked(_ info: PickInfo) -> Bool { picked.contains { $0.name == info.place.name } }
    private func toggle(_ info: PickInfo) {
        withAnimation(.snappy) {
            if isPicked(info) { picked.removeAll { $0.name == info.place.name } } else { picked.append(info.place) }
        }
    }
    private var filtered: [PickInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return items }
        return items.filter { ($0.place.name + " " + $0.teaser).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                let pickedCount = items.filter(isPicked).count
                Section {
                    Text("\(pickedCount) of \(items.count) picked. Picked places are planned first; the rest stay ideas.")
                        .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                }
                ForEach(PickKind.allCases) { kind in
                    let rows = filtered.filter { $0.kind == kind }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { info in
                                NavigationLink(value: info) { row(info) }
                            }
                        } header: {
                            Label("\(kind.title) · \(rows.count)", systemImage: kind.symbol)
                        }
                    }
                }
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .searchable(text: $query, prompt: "Search \(items.count) places")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PickInfo.self) { info in
                PickDetailView(info: info, picked: isPicked(info)) { toggle(info) }
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let bestCount {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Pick the best \(bestCount)", systemImage: "star") { pickBest(bestCount) }
                            Button("Pick none", systemImage: "circle.slash", role: .destructive) { pickBest(0) }
                        } label: { Text("Pick") }
                    }
                }
            }
        }
    }

    private func pickBest(_ n: Int) {
        withAnimation(.snappy) {
            let names = Set(items.map(\.place.name))
            picked.removeAll { names.contains($0.name) }
            picked.append(contentsOf: items.prefix(n).map(\.place))
        }
    }

    private func row(_ info: PickInfo) -> some View {
        let on = isPicked(info)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.place.name).font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                    if info.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Sketch.coral).accessibilityLabel("Pinned") }
                    if !info.videos.isEmpty { Image(systemName: "play.fill").font(.caption2).foregroundStyle(Sketch.plum).accessibilityLabel("From videos") }
                }
                if !info.teaser.isEmpty {
                    Text(info.teaser).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button { toggle(info) } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle").font(.title3)
                    .foregroundStyle(on ? Sketch.sage : Sketch.inkFaint).contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(on ? "Remove \(info.place.name)" : "Add \(info.place.name)")
        }
        .listRowBackground(Sketch.paper)
    }
}

#if DEBUG
extension PickInfo {
    /// Sample saves for screenshots: a mix of kinds, some with lots from their videos and some with nothing.
    static func demoSaves(_ n: Int, city: String) -> [PickInfo] {
        let names = ["Bar del Pla", "El Xampanyet", "Bunkers del Carmel", "Can Paixano", "Mercat de Sant Antoni", "Federal Café",
                     "Palau de la Música", "Hospital de Sant Pau", "La Cova Fumada", "Satan's Coffee", "Parc del Laberint",
                     "Casa Vicens", "Quimet & Quimet", "Paradiso", "Granja M. Viader", "Platja de la Mar Bella", "El Born CCM",
                     "Bodega 1900", "Mirador de l'Alcalde", "Libreria Altaïr", "Two Schmucks", "Nomad Coffee", "Museu Picasso",
                     "Bar Cañete", "Tibidabo", "Fundació Miró", "Els Quatre Gats", "La Pepita", "Sunset at Turó de la Rovira",
                     "Mercat de la Llibertat", "Bar Mut", "CaixaForum", "Teleférico de Montjuïc", "Chök", "Cal Pep", "Jardins de Laribal"]
        let kinds = ["bar", "bar", "nature", "bar", "food", "coffee", "attraction", "attraction", "food", "coffee", "nature",
                     "attraction", "food", "bar", "coffee", "nature", "museum", "bar", "nature", "shopping", "bar", "coffee",
                     "museum", "food", "nature", "museum", "food", "food", "nature", "food", "food", "museum", "attraction",
                     "food", "food", "nature"]
        return (0..<min(n, names.count)).map { i in
            var info = PickInfo(place: ComposerPlace(name: names[i], latitude: 41.385 + Double(i % 7) / 300, longitude: 2.17 + Double(i % 5) / 300,
                                                     category: kinds[i]), source: .save)
            if i % 3 != 2 {
                info.summary = ["Tiny vermouth bar the creator calls the best in El Born.", "Locals queue here for the bombas; go before 13:00.",
                                "The best free view of the city at sunset, a short climb from the bus."][i % 3 == 0 ? 0 : 1]
                info.tips = ["Go on a weekday", "Cash only"]
                info.videos = Array(repeating: Video(title: "48 hours in Barcelona", url: URL(string: "https://www.tiktok.com/@trippy/video/1")), count: 1 + i % 3)
            }
            if i % 4 == 0 { info.mustTry = ["Patatas bravas", "Vermut de la casa"]; info.goodToKnow = ["Closed on Mondays"]; info.price = "€€" }
            info.pinned = i % 5 == 0
            return info
        }
    }
}
#endif

extension View {
    /// A sideways row inside a card: it scrolls to the card's edges and is clipped there, never drawn over the border.
    /// (The setup's cards have 14 pt of padding.)
    func cardEdgeRow(inset: CGFloat = 14) -> some View {
        padding(.horizontal, -inset).contentMargins(.horizontal, inset, for: .scrollContent)
    }
}
