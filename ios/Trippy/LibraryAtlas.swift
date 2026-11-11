import CoreLocation
import SwiftUI

// MARK: - One index for everything you keep
//
// Pins, must-dos, trip pins, video mentions, notes and takes are stored where they always were. The atlas is
// the index over them: one entry per real place (PlaceKey), with every record that points at it, and the same
// links read backwards (video → places, note → place, trip → places). Every Library tab reads this one index,
// so a place never shows up once under Pins and again under "From your videos".

/// One stored pin: a place in General or in a trip.
struct AtlasPin: Identifiable {
    var id: String { recordID }
    let recordID: String          // what the map focuses and the map filter matches
    let placeID: String           // the stored record's own id
    let name: String
    let city: String
    let address: String
    let category: String
    let symbol: String
    let tint: Color
    let glyph: MarkAppearance?
    let googlePlaceID: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    let mustDo: Bool
    let tripID: UUID?
    let tripTitle: String?
    let sourceIDs: [UUID]
    let savedAt: Date
}

/// A saved video, as the other tabs need to show it.
struct AtlasVideo: Identifiable {
    let id: UUID
    let title: String
    let author: String?
    let cover: URL?
    let city: String
    let isTips: Bool
    let tripID: UUID?
}

struct AtlasTrip: Identifiable { let id: UUID; let title: String; let city: String }

struct AtlasPlace: Identifiable {
    let id: String                       // canonical PlaceKey
    var takeKey: String                  // the key takes and place notes are stored under
    var name: String
    var city: String
    var neighborhood: String?
    var address: String
    var category: String
    var symbol: String
    var tint: Color
    var glyph: MarkAppearance?
    var countryCode: String?
    var googlePlaceID: String?
    var coordinate: CLLocationCoordinate2D?
    var summary: String?
    var moments: [SocialMoment] = []
    var pins: [AtlasPin] = []
    var mentionIDs: [UUID] = []
    var videoIDs: [UUID] = []
    var noteID: UUID?
    var take: PlaceTake?
    var trips: [AtlasTrip] = []
    var addedAt: Date
    var search = ""

    var mustDo: Bool { pins.contains(where: \.mustDo) }
    var isOnMap: Bool { !pins.isEmpty }
    var been: Bool { take?.been == true }
    var recordIDs: [String] { pins.map(\.recordID) }
}

struct AtlasNote: Identifiable {
    /// place: one venue. tips: general advice for a city. guide: a whole video, place by place. own: written by you.
    enum Kind { case place, tips, guide, own }
    let id: UUID
    let title: String
    let kind: Kind
    let preview: String
    let updatedAt: Date
    let city: String
    let placeKey: String?
    /// Every place the note covers: one for a place note, all of a video's places for a guide.
    let placeKeys: [String]
    let videoIDs: [UUID]
    let trip: AtlasTrip?
}

struct LibraryAtlas {
    private(set) var places: [AtlasPlace] = []
    private(set) var notes: [AtlasNote] = []
    private(set) var videos: [UUID: AtlasVideo] = [:]
    private var index: [String: Int] = [:]
    private var alias: [String: String] = [:]
    private(set) var placeKeysByVideo: [UUID: [String]] = [:]
    private(set) var noteIDsByVideo: [UUID: [UUID]] = [:]

    func place(_ key: String?) -> AtlasPlace? {
        guard let key, let slot = index[alias[key] ?? key] else { return nil }
        return places[slot]
    }
    func places(inVideo id: UUID) -> [AtlasPlace] { (placeKeysByVideo[id] ?? []).compactMap(place) }
    func places(inTrip id: UUID) -> [AtlasPlace] { places.filter { $0.trips.contains { $0.id == id } } }

    /// Builds the index. `style` turns a category name into its symbol and colour; `mentionCity` resolves a
    /// mention's city through its trip or video when it has none of its own.
    init(pins: [AtlasPin], mentions: [SocialPlaceMention], videos: [AtlasVideo], notes: [TravelNote],
         takes: [String: PlaceTake], trips: [AtlasTrip], mentionCity: (SocialPlaceMention) -> String,
         style: (String) -> (symbol: String, tint: Color, title: String)) {
        self.videos = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tripByID = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The same venue found once by Google ID and once by name is one place. Two different Google IDs that
        // happen to share a name (two branches) stay apart.
        func canonical(googleID: String?, name: String, city: String) -> (key: String, takeKey: String) {
            let nameKey = PlaceKey.of(googlePlaceID: nil, name: name, city: city)
            let googleKey = googleID?.trimmingCharacters(in: .whitespaces).nonEmptyAtlas.map { "google:" + $0 }
            let takeKey = googleKey ?? nameKey
            if let googleKey, let known = alias[googleKey] { alias[nameKey] = alias[nameKey] ?? known; return (known, takeKey) }
            if let known = alias[nameKey] {
                if let googleKey, known.hasPrefix("google:"), known != googleKey { alias[googleKey] = googleKey; return (googleKey, takeKey) }
                if let googleKey { alias[googleKey] = known }
                return (known, takeKey)
            }
            let key = googleKey ?? nameKey
            alias[nameKey] = key
            if let googleKey { alias[googleKey] = key }
            return (key, takeKey)
        }
        func slot(_ key: String, _ make: () -> AtlasPlace) -> Int {
            if let found = index[key] { return found }
            places.append(make()); index[key] = places.count - 1
            return places.count - 1
        }
        func add(_ id: UUID, to list: inout [UUID]) { if !list.contains(id) { list.append(id) } }

        for pin in pins {
            let keys = canonical(googleID: pin.googlePlaceID, name: pin.name, city: pin.city)
            let at = slot(keys.key) {
                AtlasPlace(id: keys.key, takeKey: keys.takeKey, name: pin.name, city: pin.city, address: pin.address, category: pin.category,
                           symbol: pin.symbol, tint: pin.tint, glyph: pin.glyph, countryCode: pin.countryCode, googlePlaceID: pin.googlePlaceID,
                           coordinate: .init(latitude: pin.latitude, longitude: pin.longitude), addedAt: pin.savedAt)
            }
            places[at].pins.append(pin)
            places[at].addedAt = max(places[at].addedAt, pin.savedAt)
            if places[at].googlePlaceID == nil, let id = pin.googlePlaceID { places[at].googlePlaceID = id; places[at].takeKey = keys.takeKey }
            for source in pin.sourceIDs { add(source, to: &places[at].videoIDs) }
            if let tripID = pin.tripID, let trip = tripByID[tripID], !places[at].trips.contains(where: { $0.id == tripID }) { places[at].trips.append(trip) }
        }
        var keyByMention: [UUID: String] = [:]
        for mention in mentions {
            let city = mentionCity(mention)
            let keys = canonical(googleID: mention.googlePlaceID, name: mention.name, city: city)
            let look = style(mention.category ?? "")
            let at = slot(keys.key) {
                AtlasPlace(id: keys.key, takeKey: keys.takeKey, name: mention.name, city: city, address: mention.address ?? "", category: look.title,
                           symbol: look.symbol, tint: look.tint, countryCode: mention.countryCode, googlePlaceID: mention.googlePlaceID,
                           coordinate: mention.latitude.flatMap { lat in mention.longitude.map { .init(latitude: lat, longitude: $0) } },
                           addedAt: .distantPast)
            }
            keyByMention[mention.id] = keys.key
            places[at].mentionIDs.append(mention.id)
            if self.videos[mention.sourceID] != nil { add(mention.sourceID, to: &places[at].videoIDs) }
            if places[at].neighborhood == nil { places[at].neighborhood = mention.neighborhood?.nonEmptyAtlas }
            if places[at].summary == nil { places[at].summary = mention.summary.nonEmptyAtlas }
            if places[at].countryCode == nil { places[at].countryCode = mention.countryCode }
            if places[at].moments.isEmpty, let moments = mention.moments { places[at].moments = moments }
            if let tripID = mention.tripID, let trip = tripByID[tripID], !places[at].trips.contains(where: { $0.id == tripID }) { places[at].trips.append(trip) }
        }
        // Only videos that are still in the library count as links.
        for at in places.indices { places[at].videoIDs.removeAll { self.videos[$0] == nil } }

        for note in notes {
            let isGuide = note.kind == "guide"
            var key = isGuide ? nil : note.placeKey.map { alias[$0] ?? $0 }
            if isGuide {
                // A guide points at every place of its video and is never "the" note of any one of them.
                let covered = (note.linkedPlaceIDs ?? []).compactMap { alias[$0] ?? (index[$0] == nil ? nil : $0) }
                let linkedVideos = note.sourceIDs.filter { self.videos[$0] != nil }
                let trip = note.tripID.flatMap { tripByID[$0] }
                let body = (note.fromSources ?? [:]).sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n").atlasPreview
                self.notes.append(AtlasNote(id: note.id, title: note.title, kind: .guide,
                                            preview: note.userText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAtlas ?? body,
                                            updatedAt: note.updatedAt, city: note.city?.nonEmptyAtlas ?? trip?.city ?? "", placeKey: nil,
                                            placeKeys: covered.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
                                            videoIDs: linkedVideos, trip: trip))
                for video in linkedVideos { noteIDsByVideo[video, default: []].append(note.id) }
                continue
            }
            if key == nil, let mention = note.placeMentionID { key = keyByMention[mention] }
            if key == nil, let mention = mentions.first(where: { $0.noteID == note.id }) { key = keyByMention[mention.id] }
            if key == nil, let linked = note.linkedPlaces?.first {
                key = alias[PlaceKey.of(googlePlaceID: linked.googlePlaceID, name: linked.name, city: nil)]
                    ?? pins.first { $0.placeID == linked.id }.map { canonical(googleID: $0.googlePlaceID, name: $0.name, city: $0.city).key }
            }
            if let found = key, index[found] == nil { key = nil }
            let trip = note.tripID.flatMap { tripByID[$0] }
            let kind: AtlasNote.Kind = note.kind == "tips" ? .tips : (key != nil || note.kind == "place" ? .place : .own)
            let fromVideos = (note.fromSources ?? [:]).sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n").atlasPreview
            let preview = note.userText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAtlas ?? fromVideos
            let linkedVideos = note.sourceIDs.filter { self.videos[$0] != nil }
            let city = note.city?.nonEmptyAtlas ?? key.flatMap { index[$0] }.map { places[$0].city } ?? trip?.city ?? ""
            self.notes.append(AtlasNote(id: note.id, title: note.title, kind: kind, preview: preview, updatedAt: note.updatedAt, city: city,
                                        placeKey: key, placeKeys: key.map { [$0] } ?? [], videoIDs: linkedVideos, trip: trip))
            for video in linkedVideos { noteIDsByVideo[video, default: []].append(note.id) }
            if let key, let at = index[key] {
                if places[at].noteID == nil { places[at].noteID = note.id }
                for video in linkedVideos { add(video, to: &places[at].videoIDs) }
            }
        }
        for at in places.indices {
            let place = places[at]
            places[at].take = takes[place.takeKey] ?? takes[place.id] ?? takes[PlaceKey.of(googlePlaceID: nil, name: place.name, city: place.city)]
            for video in place.videoIDs { placeKeysByVideo[video, default: []].append(place.id) }
            let note = self.notes.first { $0.id == place.noteID }
            // Everything a search should find a place by: its own words and the words of what links to it.
            places[at].search = ([place.name, place.city, place.neighborhood ?? "", place.category, place.address, place.summary ?? "", note?.preview ?? ""]
                + place.videoIDs.compactMap { self.videos[$0] }.flatMap { [$0.title, $0.author ?? ""] }
                + place.trips.map(\.title) + (place.take?.tags ?? [])).joined(separator: " ")
        }
    }
}

private extension String {
    /// A note's video text as a preview: without the "From @creator" line (the chip says it) and without blank lines.
    var atlasPreview: String {
        split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("From ") }.joined(separator: "\n")
    }
    var nonEmptyAtlas: String? { let text = trimmingCharacters(in: .whitespacesAndNewlines); return text.isEmpty ? nil : text }
}

// MARK: - What the views can ask the app to do

struct AtlasActions {
    var showOnMap: (AtlasPlace) -> Void = { _ in }
    var toggleMustDo: (AtlasPlace) -> Void = { _ in }
    var putOnMap: (AtlasPlace) -> Void = { _ in }
    var openVideo: (UUID) -> Void = { _ in }
    var openNote: (UUID) -> Void = { _ in }
    var writeNote: (AtlasPlace) -> Void = { _ in }
    var openTrip: (UUID) -> Void = { _ in }
    var customize: (AtlasPlace) -> Void = { _ in }
    var remove: (AtlasPlace) -> Void = { _ in }
    var deleteNote: (UUID) -> Void = { _ in }
    var newNote: () -> Void = {}
    var findPlace: () -> Void = {}
    var openPlace: (String) -> Void = { _ in }
    var take: (String) -> Binding<PlaceTake> = { _ in .constant(PlaceTake()) }
    var appendNote: (AtlasPlace, String) -> Void = { _, _ in }
    var flag: (String) -> String? = { _ in nil }
}

// MARK: - Small shared pieces

/// A link to something else you keep: tap it and you are there.
struct AtlasLink: View {
    let symbol: String
    let text: String
    var tint: Color = Sketch.inkSoft
    var filled = false
    var action: (() -> Void)? = nil
    var body: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).lineLimit(1)
        }
        .foregroundStyle(filled ? Sketch.paper : tint)
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.12)))
        .contentShape(Capsule())
        if let action {
            Button { TrippyHaptics.light(); action() } label: { label }.buttonStyle(SketchPressStyle())
        } else { label }
    }
}

/// The well a place sits in everywhere: its category colour and symbol, or the look you gave it.
struct AtlasWell: View {
    let symbol: String
    let tint: Color
    var glyph: MarkAppearance? = nil
    var size: CGFloat = 40
    var mustDo = false
    var body: some View {
        let color = glyph?.validColorHex.map { Color(sketchHex: $0) } ?? tint
        ZStack {
            Circle().fill(color.opacity(0.14))
            if let glyph, glyph.kind != "icon" { Text(glyph.glyph).font(.system(size: size * 0.46)) }
            else { Image(systemName: glyph?.glyph ?? symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(color) }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if mustDo {
                Image(systemName: "heart.fill").font(.system(size: size * 0.24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: size * 0.44, height: size * 0.44).background(Sketch.coral, in: Circle())
                    .overlay(Circle().strokeBorder(Sketch.card, lineWidth: 1.5)).offset(x: 3, y: 3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Numbers at the top of a tab, with a thread that draws itself between them: everything here is connected.
struct AtlasSummary: View {
    struct Stat: Identifiable { let id: String; let value: String; let label: String }
    let stats: [Stat]
    var tint: Color = Sketch.clay
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.value).font(Sketch.text(22, "ExtraBold", relativeTo: .title2)).foregroundStyle(Sketch.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                    Text(stat.label).font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 22)
        .background(alignment: .bottom) {
            AtlasThread(count: stats.count).trim(from: 0, to: drawn ? 1 : 0)
                .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1, 5]))
                .frame(height: 10).padding(.horizontal, 16).padding(.bottom, 8)
                .accessibilityHidden(true)
        }
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .animation(.snappy, value: stats.map(\.value))
        .onAppear {
            if reduceMotion { drawn = true } else { withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { drawn = true } }
        }
    }
}

/// A dotted line that dips under each number in turn.
private struct AtlasThread: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(max(1, count))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for index in 0..<max(1, count) {
            let start = rect.minX + CGFloat(index) * step
            path.addQuadCurve(to: CGPoint(x: start + step * 0.5, y: rect.midY), control: CGPoint(x: start + step * 0.25, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: start + step, y: rect.midY), control: CGPoint(x: start + step * 0.75, y: rect.minY))
        }
        return path
    }
}

/// Filter chips with counts; the ink capsule slides to the one you pick.
struct AtlasFilterBar<Value: Hashable>: View {
    struct Choice: Identifiable { let value: Value; let title: String; let symbol: String; let count: Int; var id: Value { value } }
    let choices: [Choice]
    @Binding var selection: Value
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(choices) { choice in
                    let on = selection == choice.value
                    Button {
                        TrippyHaptics.selection()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8)) { selection = choice.value }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: choice.symbol).font(.system(size: 11, weight: .bold)).symbolEffect(.bounce, value: on)
                            Text(choice.title).font(Sketch.text(13, "Bold", relativeTo: .footnote))
                            Text("\(choice.count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit().opacity(0.6)
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(on ? Sketch.paper : Sketch.inkSoft)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background { if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "pick", in: space) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(SketchPressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityLabel("\(choice.title), \(choice.count)")
                }
            }
            .padding(4)
            .background(Capsule().fill(Sketch.card).shadow(color: .black.opacity(0.06), radius: 8, y: 3))
            .padding(.horizontal, 22).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -22).padding(.vertical, -6)
    }
}

/// Rows rise into place one after another when a tab or filter changes.
private struct AtlasRise: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true }
                else { withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(min(order, 8)) * 0.04)) { shown = true } }
            }
    }
}
extension View { func atlasRise(_ order: Int) -> some View { modifier(AtlasRise(order: order)) } }

struct AtlasCityHeader: View {
    let city: String
    let flag: String?
    let count: Int
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let flag { Text(flag).font(.system(size: 18)) }
            Text(city.isEmpty ? "Somewhere" : city).font(Sketch.display(.title3)).foregroundStyle(Sketch.ink).lineLimit(1)
            Text("\(count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit().foregroundStyle(Sketch.inkSoft)
                .padding(.horizontal, 7).padding(.vertical, 2).background(Sketch.paperDeep, in: Capsule())
            Spacer(minLength: 4)
            if let detail { Text(detail).font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint).lineLimit(1) }
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

// MARK: - A place, once

struct AtlasPlaceRow: View {
    let place: AtlasPlace
    let atlas: LibraryAtlas
    let actions: AtlasActions
    var showsCity = false
    @State private var beat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AtlasWell(symbol: place.symbol, tint: place.tint, glyph: place.glyph, mustDo: place.mustDo)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: place.mustDo)
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name).font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(meta).font(Sketch.text(12, "Medium", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                if let summary = place.summary {
                    Text(summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                        .multilineTextAlignment(.leading).padding(.top, 1)
                }
                if hasLinks { links.padding(.top, 3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                beat += 1; TrippyHaptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { place.isOnMap ? actions.toggleMustDo(place) : actions.putOnMap(place) }
            } label: {
                Image(systemName: place.isOnMap ? (place.mustDo ? "heart.fill" : "heart") : "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(place.mustDo ? Sketch.coral : Sketch.inkFaint)
                    .symbolEffect(.bounce, value: beat).contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(SketchPressStyle())
            .opacity(place.isOnMap || place.coordinate != nil ? 1 : 0)
            .disabled(!place.isOnMap && place.coordinate == nil)
            .accessibilityLabel(place.isOnMap ? (place.mustDo ? "Remove must do" : "Mark as must do") : "Pin on the map")
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { TrippyHaptics.light(); actions.openPlace(place.id) }
        .contextMenu {
            Button("Open", systemImage: "rectangle.portrait.and.arrow.forward") { actions.openPlace(place.id) }
            if place.isOnMap {
                Button("Show on map", systemImage: "map") { actions.showOnMap(place) }
                Button("Icon & category", systemImage: "paintpalette") { actions.customize(place) }
            } else if place.coordinate != nil { Button("Pin on the map", systemImage: "mappin.and.ellipse") { actions.putOnMap(place) } }
            Button(place.noteID == nil ? "Write a note" : "Open note", systemImage: "note.text") {
                if let note = place.noteID { actions.openNote(note) } else { actions.writeNote(place) }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { actions.remove(place) }
        }
        .accessibilityElement(children: .contain)
    }

    private var meta: String {
        var parts: [String] = []
        if let hood = place.neighborhood { parts.append(hood) }
        else if showsCity, !place.city.isEmpty { parts.append(place.city) }
        else if !place.address.isEmpty { parts.append(place.address) }
        parts.append(place.category)
        return parts.joined(separator: " · ")
    }
    private var hasLinks: Bool {
        !place.videoIDs.isEmpty || place.noteID != nil || place.take != nil || !place.trips.isEmpty || !place.isOnMap
    }
    private var links: some View {
        BubbleFlow(spacing: 6) {
            if !place.videoIDs.isEmpty {
                AtlasLink(symbol: "play.fill", text: place.videoIDs.count == 1 ? "1 video" : "\(place.videoIDs.count) videos", tint: Sketch.plum) {
                    if place.videoIDs.count == 1 { actions.openVideo(place.videoIDs[0]) } else { actions.openPlace(place.id) }
                }
            }
            if let note = place.noteID { AtlasLink(symbol: "note.text", text: "Note", tint: Sketch.ochre) { actions.openNote(note) } }
            if let take = place.take {
                AtlasLink(symbol: take.been == true ? "checkmark" : "bubble.left.fill",
                          text: take.been == true ? (take.tags.first.flatMap(PlaceTakeTag.init(rawValue:))?.title ?? "Been") : "Your take", tint: Sketch.sage) {
                    actions.openPlace(place.id)
                }
            }
            ForEach(place.trips.prefix(2)) { trip in
                AtlasLink(symbol: "airplane", text: trip.title, tint: Sketch.sky) { actions.openTrip(trip.id) }
            }
            if !place.isOnMap { AtlasLink(symbol: place.coordinate == nil ? "questionmark" : "mappin.slash", text: place.coordinate == nil ? "No location yet" : "Not pinned", tint: Sketch.inkFaint) }
        }
    }
}

// MARK: - Pins tab

enum AtlasPlaceFilter: String, CaseIterable, Identifiable {
    case all, mustDo, videos, noted, trips, been
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"; case .mustDo: "Must do"; case .videos: "From videos"; case .noted: "Noted"; case .trips: "In trips"; case .been: "Been"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"; case .mustDo: "heart.fill"; case .videos: "play.fill"; case .noted: "note.text"
        case .trips: "airplane"; case .been: "checkmark"
        }
    }
    func keeps(_ place: AtlasPlace) -> Bool {
        switch self {
        case .all: true
        case .mustDo: place.mustDo
        case .videos: !place.videoIDs.isEmpty
        case .noted: place.noteID != nil
        case .trips: !place.trips.isEmpty
        case .been: place.been
        }
    }
}

struct AtlasPlacesView: View {
    let atlas: LibraryAtlas
    /// Already narrowed by search, city, type and the map's own filter.
    let places: [AtlasPlace]
    let singleCity: Bool
    let actions: AtlasActions
    @AppStorage("trippy.atlas.places.filter") private var filterName = AtlasPlaceFilter.all.rawValue
    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let preview = 5

    private var filter: Binding<AtlasPlaceFilter> {
        Binding(get: { AtlasPlaceFilter(rawValue: filterName) ?? .all }, set: { filterName = $0.rawValue })
    }

    var body: some View {
        let shown = places.filter(filter.wrappedValue.keeps)
        let groups = Self.cities(shown)
        VStack(alignment: .leading, spacing: 20) {
            AtlasSummary(stats: [
                .init(id: "places", value: "\(places.count)", label: places.count == 1 ? "Place" : "Places"),
                .init(id: "must", value: "\(places.filter(\.mustDo).count)", label: "Must do"),
                .init(id: "cities", value: "\(Set(places.map { $0.city.lowercased() }).count)", label: "Cities"),
                .init(id: "linked", value: "\(places.filter { !$0.videoIDs.isEmpty || $0.noteID != nil }.count)", label: "Linked"),
            ], tint: Sketch.clay)
            AtlasFilterBar(choices: AtlasPlaceFilter.allCases.compactMap { item in
                let count = places.filter(item.keeps).count
                return item == .all || count > 0 ? AtlasFilterBar<AtlasPlaceFilter>.Choice(value: item, title: item.title, symbol: item.symbol, count: count) : nil
            }, selection: filter)
            if groups.isEmpty {
                LibraryEmptyState(title: places.isEmpty ? "Nothing pinned yet" : "Nothing under \(filter.wrappedValue.title)",
                                  message: places.isEmpty ? "Pin a place on the map or share a video: its spots land here." : "",
                                  tone: .pins, actionTitle: "Find a place", action: actions.findPlace)
            }
            ForEach(Array(groups.enumerated()), id: \.element.key) { order, group in
                let open = expanded.contains(group.key) || group.places.count <= preview + 1
                VStack(alignment: .leading, spacing: 4) {
                    if !singleCity {
                        AtlasCityHeader(city: group.city, flag: actions.flag(group.city), count: group.places.count, detail: Self.mix(group.places))
                            .padding(.bottom, 4)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array((open ? group.places : Array(group.places.prefix(preview))).enumerated()), id: \.element.id) { row, place in
                            if row > 0 { Rectangle().fill(Sketch.rule.opacity(0.7)).frame(height: 0.7).padding(.leading, 52) }
                            AtlasPlaceRow(place: place, atlas: atlas, actions: actions)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if group.places.count > preview + 1 {
                            Rectangle().fill(Sketch.rule.opacity(0.7)).frame(height: 0.7)
                            Button {
                                TrippyHaptics.selection()
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                                    if open { expanded.remove(group.key) } else { expanded.insert(group.key) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(open ? "Show fewer" : "Show all \(group.places.count)").font(Sketch.text(13, "Bold", relativeTo: .footnote))
                                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open ? 180 : 0))
                                }
                                .foregroundStyle(Sketch.clay).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(SketchPressStyle())
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
                }
                .atlasRise(order)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: filterName)
    }

    struct CityGroup { let key: String; let city: String; let places: [AtlasPlace] }
    /// Cities by how much you keep there; inside a city must-dos first, then newest.
    static func cities(_ places: [AtlasPlace]) -> [CityGroup] {
        let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "" }
        return Dictionary(grouping: places) { fold($0.city) }.map { key, items in
            CityGroup(key: key, city: items.first?.city.split(separator: ",").first.map(String.init) ?? "",
                      places: items.sorted { ($0.mustDo ? 1 : 0, $0.addedAt, $1.name) > ($1.mustDo ? 1 : 0, $1.addedAt, $0.name) })
        }.sorted { ($0.places.count, $1.city) > ($1.places.count, $0.city) }
    }
    /// "4 food · 2 coffee": what a city's places are, at a glance.
    static func mix(_ places: [AtlasPlace]) -> String? {
        let counts = Dictionary(grouping: places, by: \.category).map { ($0.key, $0.value.count) }.sorted { ($0.1, $1.0) > ($1.1, $0.0) }
        guard counts.count > 1 else { return nil }
        return counts.prefix(2).map { "\($0.1) \($0.0.lowercased())" }.joined(separator: " · ")
    }
}

// MARK: - Notes tab

enum AtlasNoteFilter: String, CaseIterable, Identifiable {
    case all, guides, places, tips, own
    var id: String { rawValue }
    var title: String { switch self { case .all: "All"; case .guides: "Guides"; case .places: "Places"; case .tips: "Tips"; case .own: "Yours" } }
    var symbol: String {
        switch self { case .all: "square.grid.2x2.fill"; case .guides: "list.bullet.rectangle.fill"; case .places: "mappin"; case .tips: "lightbulb.fill"; case .own: "pencil" }
    }
    func keeps(_ note: AtlasNote) -> Bool {
        switch self {
        case .all: true; case .guides: note.kind == .guide; case .places: note.kind == .place; case .tips: note.kind == .tips; case .own: note.kind == .own
        }
    }
}

struct AtlasNoteRow: View {
    let note: AtlasNote
    let atlas: LibraryAtlas
    let actions: AtlasActions
    /// What kind of note it is, in a few words: "Tips from 2 videos", "6 places with tips".
    private var detail: String {
        switch note.kind {
        case .tips: note.videoIDs.count > 1 ? " · Tips from \(note.videoIDs.count) videos" : " · Tips"
        case .guide: " · \(note.placeKeys.count) \(note.placeKeys.count == 1 ? "place" : "places") with tips"
        default: ""
        }
    }
    var body: some View {
        let place = atlas.place(note.placeKey)
        let covered = note.kind == .guide ? note.placeKeys.compactMap(atlas.place) : []
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                switch note.kind {
                case .place: AtlasWell(symbol: place?.symbol ?? "mappin", tint: place?.tint ?? Sketch.clay, glyph: place?.glyph, size: 36, mustDo: place?.mustDo ?? false)
                case .tips: AtlasWell(symbol: "lightbulb.fill", tint: Sketch.ochre, size: 36)
                case .guide: AtlasWell(symbol: "list.bullet.rectangle.fill", tint: Sketch.plum, size: 36)
                case .own: AtlasWell(symbol: "pencil", tint: Sketch.sage, size: 36)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink).lineLimit(2).multilineTextAlignment(.leading)
                    Text(note.updatedAt.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en"))) + (place.map { " · " + $0.category } ?? detail))
                        .font(Sketch.text(12, "Medium", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(note.preview.isEmpty ? "Empty note" : note.preview).font(Sketch.text(14, relativeTo: .subheadline))
                .foregroundStyle(note.preview.isEmpty ? Sketch.inkFaint : Sketch.inkSoft).lineSpacing(3).lineLimit(3).multilineTextAlignment(.leading)
            if place != nil || !covered.isEmpty || !note.videoIDs.isEmpty || note.trip != nil {
                BubbleFlow(spacing: 6) {
                    if let place { AtlasLink(symbol: place.symbol, text: place.name, tint: place.tint) { actions.openPlace(place.id) } }
                    ForEach(covered.prefix(3)) { item in AtlasLink(symbol: item.symbol, text: item.name, tint: item.tint) { actions.openPlace(item.id) } }
                    if covered.count > 3 { AtlasLink(symbol: "mappin", text: "+\(covered.count - 3)", tint: Sketch.clay) }
                    ForEach(note.videoIDs.prefix(2), id: \.self) { id in
                        AtlasLink(symbol: "play.fill", text: atlas.videos[id]?.author.map { "@" + $0 } ?? "Video", tint: Sketch.plum) { actions.openVideo(id) }
                    }
                    if note.videoIDs.count > 2 { AtlasLink(symbol: "play.fill", text: "+\(note.videoIDs.count - 2)", tint: Sketch.plum) }
                    if let trip = note.trip { AtlasLink(symbol: "airplane", text: trip.title, tint: Sketch.sky) { actions.openTrip(trip.id) } }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { TrippyHaptics.light(); actions.openNote(note.id) }
        .contextMenu {
            Button("Open", systemImage: "square.and.pencil") { actions.openNote(note.id) }
            if let place { Button("Open \(place.name)", systemImage: "mappin") { actions.openPlace(place.id) } }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.deleteNote(note.id) }
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}

struct AtlasNotesView: View {
    let atlas: LibraryAtlas
    /// Already narrowed by search and city, newest first.
    let notes: [AtlasNote]
    let actions: AtlasActions
    @AppStorage("trippy.atlas.notes.filter") private var filterName = AtlasNoteFilter.all.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filter: Binding<AtlasNoteFilter> {
        Binding(get: { AtlasNoteFilter(rawValue: filterName) ?? .all }, set: { filterName = $0.rawValue })
    }
    var body: some View {
        let shown = notes.filter(filter.wrappedValue.keeps)
        let groups = Dictionary(grouping: shown) { $0.city.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "" }
            .sorted { ($0.key.isEmpty ? 1 : 0, $1.value.count, $0.key) < ($1.key.isEmpty ? 1 : 0, $0.value.count, $1.key) }
        VStack(alignment: .leading, spacing: 20) {
            AtlasSummary(stats: [
                .init(id: "notes", value: "\(notes.count)", label: notes.count == 1 ? "Note" : "Notes"),
                .init(id: "places", value: "\(Set(notes.flatMap(\.placeKeys)).count)", label: "Places"),
                .init(id: "videos", value: "\(Set(notes.flatMap(\.videoIDs)).count)", label: "Videos"),
                .init(id: "own", value: "\(notes.filter { $0.kind == .own }.count)", label: "Yours"),
            ], tint: Sketch.ochre)
            HStack(spacing: 10) {
                AtlasFilterBar(choices: AtlasNoteFilter.allCases.compactMap { item in
                    let count = notes.filter(item.keeps).count
                    return item == .all || count > 0 ? AtlasFilterBar<AtlasNoteFilter>.Choice(value: item, title: item.title, symbol: item.symbol, count: count) : nil
                }, selection: filter)
            }
            if shown.isEmpty {
                LibraryEmptyState(title: notes.isEmpty ? "A place for your ideas" : "Nothing under \(filter.wrappedValue.title)",
                                  message: notes.isEmpty ? "Videos write a note for every place they mention. Yours go here too." : "",
                                  tone: .notes, actionTitle: "New note", action: actions.newNote)
            }
            ForEach(Array(groups.enumerated()), id: \.element.key) { order, group in
                VStack(alignment: .leading, spacing: 10) {
                    AtlasCityHeader(city: group.key.isEmpty ? "Personal" : group.key, flag: group.key.isEmpty ? nil : actions.flag(group.key), count: group.value.count)
                    ForEach(group.value) { note in AtlasNoteRow(note: note, atlas: atlas, actions: actions) }
                }
                .atlasRise(order)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: filterName)
    }
}

// MARK: - Everything about one place

struct AtlasPlaceSheet: View {
    let place: AtlasPlace
    let atlas: LibraryAtlas
    let actions: AtlasActions
    @Environment(\.dismiss) private var dismiss
    @State private var beat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    AtlasWell(symbol: place.symbol, tint: place.tint, glyph: place.glyph, size: 56, mustDo: place.mustDo)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: place.mustDo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name).font(Sketch.display(.title2, weight: .bold)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
                        Text(([place.neighborhood, place.city.isEmpty ? nil : (actions.flag(place.city).map { $0 + " " } ?? "") + place.city, place.category] as [String?])
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Sketch.text(13, "Medium", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                        if !place.address.isEmpty { Text(place.address).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if place.isOnMap { action("Map", "map.fill", Sketch.ink, filled: true) { dismiss(); actions.showOnMap(place) } }
                    else if place.coordinate != nil { action("Pin it", "mappin.and.ellipse", Sketch.ink, filled: true) { actions.putOnMap(place) } }
                    if place.isOnMap {
                        action(place.mustDo ? "Must do" : "Must do?", place.mustDo ? "heart.fill" : "heart", Sketch.coral, filled: place.mustDo) {
                            beat += 1; withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { actions.toggleMustDo(place) }
                        }
                    }
                    action(place.noteID == nil ? "Note" : "Open note", "note.text", Sketch.ochre, filled: false) {
                        dismiss()
                        if let note = place.noteID { actions.openNote(note) } else { actions.writeNote(place) }
                    }
                }
                connections
                PlaceQuickTakeCard(placeName: place.name, take: actions.take(place.takeKey), summary: place.summary, moments: place.moments,
                                   onAppendNote: { actions.appendNote(place, $0) })
                if !place.videoIDs.isEmpty {
                    section("In your videos", count: place.videoIDs.count) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(place.videoIDs.compactMap { atlas.videos[$0] }) { video in
                                    Button { dismiss(); actions.openVideo(video.id) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            StudioCover(url: video.cover).frame(width: 104, height: 148)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            Text(video.title).font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.ink).lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            if let author = video.author { Text("@" + author).font(Sketch.text(11, "Medium", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1) }
                                        }.frame(width: 104, alignment: .leading)
                                    }.buttonStyle(SketchPressStyle())
                                }
                            }.padding(.horizontal, 22)
                        }.scrollIndicators(.hidden).padding(.horizontal, -22)
                    }
                }
                if let note = atlas.notes.first(where: { $0.id == place.noteID }), !note.preview.isEmpty {
                    section("Your note", count: nil) {
                        Button { dismiss(); actions.openNote(note.id) } label: {
                            Text(note.preview).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).lineSpacing(3)
                                .lineLimit(6).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
                                .overlay(alignment: .leading) { Capsule().fill(Sketch.ochre.opacity(0.7)).frame(width: 3).padding(.vertical, 12).padding(.leading, 5) }
                        }.buttonStyle(SketchPressStyle())
                    }
                }
                if place.pins.count > 0 {
                    section("Kept in", count: nil) {
                        BubbleFlow(spacing: 6) {
                            if place.pins.contains(where: { $0.tripID == nil }) { AtlasLink(symbol: "mappin", text: "Your map", tint: Sketch.clay) { dismiss(); actions.showOnMap(place) } }
                            ForEach(place.trips) { trip in AtlasLink(symbol: "airplane", text: trip.title, tint: Sketch.sky) { dismiss(); actions.openTrip(trip.id) } }
                        }
                    }
                }
                Button(role: .destructive) { dismiss(); actions.remove(place) } label: {
                    Label(place.isOnMap ? "Remove from your places" : "Forget this place", systemImage: "trash")
                        .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.coral).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(SketchPressStyle())
            }
            .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 30)
        }
        .background(Sketch.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    /// The place in the middle, and a line out to each kind of thing that points at it.
    private var connections: some View {
        let items: [(String, String, Color, Int)] = [
            ("play.fill", "Videos", Sketch.plum, place.videoIDs.count), ("note.text", "Note", Sketch.ochre, place.noteID == nil ? 0 : 1),
            ("airplane", "Trips", Sketch.sky, place.trips.count), ("bubble.left.fill", "Take", Sketch.sage, place.take == nil ? 0 : 1)]
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    ZStack {
                        Circle().fill(item.3 > 0 ? item.2.opacity(0.16) : Sketch.paperDeep)
                        Image(systemName: item.0).font(.system(size: 12, weight: .bold)).foregroundStyle(item.3 > 0 ? item.2 : Sketch.inkFaint)
                    }.frame(width: 34, height: 34)
                    Text(item.3 > 1 ? "\(item.3) \(item.1)" : item.1).font(Sketch.text(11, "SemiBold", relativeTo: .caption2))
                        .foregroundStyle(item.3 > 0 ? Sketch.ink : Sketch.inkFaint).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .atlasRise(index)
            }
        }
        .padding(.vertical, 12)
        .background(alignment: .top) {
            Rectangle().fill(Sketch.rule).frame(height: 1).padding(.horizontal, 40).padding(.top, 29)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Linked to \(place.videoIDs.count) videos, \(place.trips.count) trips\(place.noteID == nil ? "" : ", a note")\(place.take == nil ? "" : ", your take")")
    }

    private func action(_ title: String, _ symbol: String, _ tint: Color, filled: Bool, _ run: @escaping () -> Void) -> some View {
        Button { TrippyHaptics.light(); run() } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).symbolEffect(.bounce, value: beat).contentTransition(.symbolEffect(.replace))
                Text(title).font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(filled ? Sketch.paper : tint).frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.12)))
        }.buttonStyle(SketchPressStyle())
    }
    private func section<Content: View>(_ title: String, count: Int?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioHeading(title: title, count: count)
            content()
        }
    }
}
