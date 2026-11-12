import SwiftUI

// MARK: - What the planner has found so far

/// One place the planner found, as streamed in its progress events.
struct PlanningFoundPlace: Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let area: String?
    let latitude: Double?
    let longitude: Double?
    let rating: Double?
    let reviews: Int?
    let website: URL?
    let imageURL: URL?

    init?(_ json: [String: Any]) {
        guard let id = json["id"] as? String, let name = json["name"] as? String, !name.isEmpty else { return nil }
        self.id = id; self.name = name
        category = json["category"] as? String ?? "attraction"
        area = (json["area"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        latitude = json["latitude"] as? Double; longitude = json["longitude"] as? Double
        rating = json["rating"] as? Double; reviews = json["reviews"] as? Int
        website = (json["website"] as? String).flatMap(URL.init(string:))
        imageURL = (json["image_url"] as? String).flatMap(URL.init(string:))
    }

    init(id: String, name: String, category: String, area: String?, latitude: Double, longitude: Double, rating: Double?, reviews: Int?) {
        self.id = id; self.name = name; self.category = category; self.area = area
        self.latitude = latitude; self.longitude = longitude; self.rating = rating; self.reviews = reviews
        website = nil; imageURL = nil
    }

    var isSight: Bool { ["attraction", "museum", "nature", "excursion"].contains(category) }
    /// Rating weighted by how many people stand behind it.
    var confidence: Double { (rating ?? 0) * min(1, sqrt(Double(reviews ?? 0) / 400)) }

    static func symbol(_ category: String) -> String {
        switch category {
        case "food": "fork.knife"; case "coffee": "cup.and.saucer.fill"; case "museum": "building.columns.fill"
        case "nature": "leaf.fill"; case "shopping": "bag.fill"; case "bar": "wineglass.fill"; case "club": "music.note"
        case "excursion": "car.fill"; default: "star.fill"
        }
    }
    static func tint(_ category: String) -> Color {
        switch category {
        case "food": Sketch.coral; case "coffee": Sketch.clay; case "museum": Sketch.plum; case "nature": Sketch.sage
        case "shopping": Sketch.ochre; case "bar", "club": Sketch.plum; default: Sketch.sky
        }
    }
}

/// A photo for a found place from the app's free sources, with a tinted placeholder.
struct FoundPlacePhoto: View {
    let place: PlanningFoundPlace
    var symbolSize: CGFloat = 22
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [PlanningFoundPlace.tint(place.category).opacity(0.32), PlanningFoundPlace.tint(place.category).opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: PlanningFoundPlace.symbol(place.category))
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(PlanningFoundPlace.tint(place.category).opacity(0.7))
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .clipped()
        .task(id: place.id) {
            let found = await PlaceImageStore.shared.image(name: place.name, latitude: place.latitude, longitude: place.longitude,
                                                           sight: place.isSight, url: place.imageURL, website: place.website)
            withAnimation(.easeOut(duration: 0.35)) { image = found }
        }
        .accessibilityHidden(true)
    }
}

/// The places the planner is finding, revealed one at a time: the newest lands as
/// a big photo card, then tucks into a strip you can tap to look again.
struct PlanningFoundFeed: View {
    let found: [PlanningFoundPlace]
    let running: Bool
    @State private var revealed = 0
    @State private var focusID: String?
    @State private var pinnedUntil: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space

    private var shown: [PlanningFoundPlace] { Array(found.prefix(revealed)) }
    private var current: PlanningFoundPlace? {
        if let focusID, let hit = shown.first(where: { $0.id == focusID }) { return hit }
        return shown.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Found so far").font(Sketch.text(17, "Bold", relativeTo: .headline))
                Spacer()
                Text("\(revealed) of \(found.count)").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                    .foregroundStyle(Sketch.inkSoft).monospacedDigit().contentTransition(.numericText())
            }
            if let current {
                hero(current)
                    .id(current.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.86, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 24)),
                        removal: .scale(scale: 0.94).combined(with: .opacity)))
            }
            strip
        }
        .task(id: found.count) { await revealNext() }
        .sensoryFeedback(.selection, trigger: revealed)
    }

    private func revealNext() async {
        if revealed == 0, !found.isEmpty { withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { revealed = 1 } }
        while revealed < found.count {
            try? await Task.sleep(for: .seconds(running ? 2.2 : 0.35))
            guard !Task.isCancelled else { return }
            // Someone looking at a place they tapped keeps it for a moment.
            if Date() < pinnedUntil { continue }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.78)) {
                focusID = nil
                revealed += 1
            }
        }
    }

    private func hero(_ place: PlanningFoundPlace) -> some View {
        ZStack(alignment: .bottomLeading) {
            FoundPlacePhoto(place: place, symbolSize: 40)
                .frame(height: 210)
                .matchedGeometryEffect(id: "photo-\(place.id)", in: space, isSource: true)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: PlanningFoundPlace.symbol(place.category)).font(.system(size: 11, weight: .bold))
                    Text(PlanningLive.categoryTitle(place.category)).font(Sketch.text(12, "Bold", relativeTo: .caption))
                }
                .padding(.horizontal, 9).frame(height: 24)
                .background(.ultraThinMaterial, in: Capsule())
                Text(place.name).font(Sketch.display(.title2, weight: .bold)).lineLimit(2)
                HStack(spacing: 10) {
                    if let rating = place.rating { Stars(value: rating) }
                    if let reviews = place.reviews, reviews > 0 {
                        Text("\(reviews.formatted(.number.notation(.compactName))) reviews").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                    }
                    if let area = place.area { Text(area).font(Sketch.text(13, relativeTo: .footnote)).lineLimit(1) }
                }
                .opacity(0.92)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.name), \(PlanningLive.categoryTitle(place.category))" + (place.rating.map { ", rated \($0.formatted(.number.precision(.fractionLength(1))))" } ?? ""))
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(shown.reversed()) { place in
                    Button {
                        pinnedUntil = .now.addingTimeInterval(6)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { focusID = place.id }
                    } label: {
                        FoundPlacePhoto(place: place, symbolSize: 16)
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(current?.id == place.id ? Sketch.ink : .clear, lineWidth: 2))
                            .scaleEffect(current?.id == place.id ? 1.04 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

private struct Stars: View {
    let value: Double
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.ochre)
            Text(value.formatted(.number.precision(.fractionLength(1)))).font(Sketch.text(13, "Bold", relativeTo: .footnote)).monospacedDigit()
        }
    }
}

// MARK: - Head to head

/// Two close options in the same category, side by side, with the reason one
/// edges ahead. Tap to see the next pair.
struct PlanningHeadToHead: View {
    let found: [PlanningFoundPlace]
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The two best-loved places in each category that has at least two.
    private var pairs: [(PlanningFoundPlace, PlanningFoundPlace)] {
        Dictionary(grouping: found.filter { $0.rating != nil }, by: \.category)
            .sorted { $0.key < $1.key }
            .compactMap { _, places in
                let top = places.sorted { $0.confidence > $1.confidence }
                return top.count >= 2 ? (top[0], top[1]) : nil
            }
    }

    var body: some View {
        let pairs = pairs
        if !pairs.isEmpty {
            let pair = pairs[index % pairs.count]
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Close call").font(Sketch.text(17, "Bold", relativeTo: .headline))
                    Spacer()
                    if pairs.count > 1 {
                        Text("\(index % pairs.count + 1)/\(pairs.count)").font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
                            .foregroundStyle(Sketch.inkSoft).monospacedDigit()
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    side(pair.0, against: pair.1, leads: true)
                    Text("vs").font(Sketch.display(.headline, weight: .bold)).foregroundStyle(Sketch.inkFaint).padding(.top, 30)
                    side(pair.1, against: pair.0, leads: false)
                }
                Text(verdict(pair.0, pair.1)).font(Sketch.text(14, "Medium", relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(pair.0.id + pair.1.id)
            .transition(reduceMotion ? .opacity : .push(from: .trailing))
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { index += 1 } }
            .task(id: pairs.count) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(7))
                    guard !Task.isCancelled, pairs.count > 1 else { continue }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { index += 1 }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(pairs.count > 1 ? "Tap for the next comparison" : "")
        }
    }

    private func side(_ place: PlanningFoundPlace, against other: PlanningFoundPlace, leads: Bool) -> some View {
        let maxReviews = Double(max(place.reviews ?? 0, other.reviews ?? 0, 1))
        return VStack(alignment: .leading, spacing: 8) {
            FoundPlacePhoto(place: place, symbolSize: 18)
                .frame(height: 76).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if leads {
                        Image(systemName: "crown.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(Circle().fill(Sketch.coral)).padding(6)
                    }
                }
            Text(place.name).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).lineLimit(2, reservesSpace: true)
            meter(label: (place.rating ?? 0).formatted(.number.precision(.fractionLength(1))) + " stars",
                  fraction: ((place.rating ?? 0) - 3) / 2, tint: Sketch.ochre)
            meter(label: "\((place.reviews ?? 0).formatted(.number.notation(.compactName))) reviews",
                  fraction: Double(place.reviews ?? 0) / maxReviews, tint: Sketch.sage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meter(label: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            GeometryReader { bar in
                Capsule().fill(Sketch.paperDeep)
                    .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: bar.size.width * max(0.04, min(1, fraction))) }
            }
            .frame(height: 6)
        }
    }

    private func verdict(_ a: PlanningFoundPlace, _ b: PlanningFoundPlace) -> String {
        let ra = a.rating ?? 0, rb = b.rating ?? 0, na = a.reviews ?? 0, nb = b.reviews ?? 0
        if ra >= rb && na >= nb { return "\(a.name) rates higher and more people stand behind it." }
        if ra < rb { return "\(b.name) rates a touch higher, but \(a.name) has far more reviews, so it's the safer pick." }
        return "\(a.name) rates higher. \(b.name) is busier, so book ahead if you want both."
    }
}

// MARK: - Brand type

/// "trippy" set the same way everywhere it is written out.
struct TrippyWordmarkText: View {
    var size: CGFloat = 20
    var body: some View {
        Text("trippy")
            .font(.custom("PlusJakartaSans-ExtraBold", size: size, relativeTo: .headline))
            .tracking(-size * 0.02)
            .accessibilityLabel("Trippy")
    }
}
