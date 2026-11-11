import SwiftUI
import MapKit
import CoreLocation
import CryptoKit

// MARK: - Meal and coffee blocks
//
// A plan's food and coffee stops are blocks, not fixed shops: the block says
// what and roughly where ("Lunch · around Monti"), the planner's pick is only
// the first suggestion, and a large nearby pool is one tap away. The traveller
// can re-pick, decide later, add a block or remove one.

enum SlotKind: String, Codable, CaseIterable, Identifiable {
    case coffee, lunch, dinner, drinks
    var id: String { rawValue }
    var title: String {
        switch self { case .coffee: "Coffee break"; case .lunch: "Lunch"; case .dinner: "Dinner"; case .drinks: "Drinks" }
    }
    var symbol: String {
        switch self { case .coffee: "cup.and.saucer.fill"; case .lunch, .dinner: "fork.knife"; case .drinks: "wineglass.fill" }
    }
    var category: String {
        switch self { case .coffee: "coffee"; case .lunch, .dinner: "food"; case .drinks: "bar" }
    }
    var minutes: Int {
        switch self { case .coffee: 30; case .lunch: 75; case .dinner: 90; case .drinks: 60 }
    }
    var defaultTime: String {
        switch self { case .coffee: "16:00"; case .lunch: "13:00"; case .dinner: "20:00"; case .drinks: "21:45" }
    }
    var query: String {
        switch self { case .coffee: "café"; case .lunch, .dinner: "restaurant"; case .drinks: "bar" }
    }
    var poiCategories: [MKPointOfInterestCategory] {
        switch self {
        case .coffee: [.cafe, .bakery]
        case .lunch, .dinner: [.restaurant, .foodMarket]
        case .drinks: [.nightlife, .winery, .brewery]
        }
    }
    func matches(_ category: String) -> Bool {
        switch self {
        case .coffee: ["coffee", "cafe", "bakery"].contains(category)
        case .lunch, .dinner: ["food", "restaurant"].contains(category)
        case .drinks: ["bar", "nightlife"].contains(category)
        }
    }
    var autoID: String { "slot:\(rawValue):auto" }
    func newID() -> String { "slot:\(rawValue):\(UUID().uuidString.prefix(8).lowercased())" }

    static func parse(_ id: String) -> SlotKind? {
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "slot" else { return nil }
        return SlotKind(rawValue: String(parts[1]))
    }
    /// What a planned food or drink stop stands for, by its category and time.
    static func infer(_ place: GuidePlace, time: String) -> SlotKind? {
        switch place.category {
        case "coffee": return .coffee
        case "bar", "nightlife": return .drinks
        case "food":
            guard let minutes = GuideDates.minutes(time) else { return .lunch }
            if minutes < 11 * 60 { return .coffee }
            return minutes < 16 * 60 + 30 ? .lunch : .dinner
        default: return nil
        }
    }
}

/// A place picked from the nearby pool (Apple Maps) that the plan didn't include.
struct GuideSavedPlace: Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let latitude: Double
    let longitude: Double
    var address: String?
    var url: String?
    var phone: String?

    var guidePlace: GuidePlace {
        GuidePlace(id: id, name: name, category: category, description: "", why: "", address: address,
                   url: url.flatMap(URL.init(string:)), coordinate: .init(latitude: latitude, longitude: longitude),
                   priceMin: nil, priceMax: nil, rating: nil, ratingScale: nil, reviewCount: nil,
                   reservationRequired: nil, tags: ["apple_maps"])
    }

    init(id: String, name: String, category: String, latitude: Double, longitude: Double, address: String?, url: String?) {
        self.id = id; self.name = name; self.category = category; self.latitude = latitude; self.longitude = longitude
        self.address = address; self.url = url
    }

    init(item: MKMapItem, category: String) {
        let c = item.placemark.coordinate
        let name = item.name ?? "Place"
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
        id = "mk:\(key):\(String(format: "%.4f,%.4f", c.latitude, c.longitude))"
        self.name = name; self.category = category; latitude = c.latitude; longitude = c.longitude
        address = [item.placemark.thoroughfare, item.placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        url = item.url?.absoluteString; phone = item.phoneNumber
    }
}

extension GuidePlace {
    /// Stand-in shown while a block has no place picked yet.
    static func slot(id: String, kind: SlotKind, latitude: Double?, longitude: Double?) -> GuidePlace {
        GuidePlace(id: id, name: kind.title, category: kind.category, description: "", why: "", address: nil, url: nil,
                   coordinate: latitude.flatMap { lat in longitude.map { .init(latitude: lat, longitude: $0) } },
                   priceMin: nil, priceMax: nil, rating: nil, ratingScale: nil, reviewCount: nil,
                   reservationRequired: nil, tags: ["slot"])
    }
    var isSlotPlaceholder: Bool { tags.contains("slot") }
}

// MARK: - Time shorthand

/// "12" → "12:00", "930" → "09:30", "7pm" → "19:00", "18.45" → "18:45".
/// Anything it can't read is returned unchanged.
enum TimeShorthand {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return raw }
        var pm = false, am = false
        for suffix in ["pm", "p.m.", "μμ", "μ.μ."] where text.hasSuffix(suffix) { pm = true; text = String(text.dropLast(suffix.count)) }
        for suffix in ["am", "a.m.", "πμ", "π.μ."] where text.hasSuffix(suffix) { am = true; text = String(text.dropLast(suffix.count)) }
        text = text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(whereSeparator: { ":.h, ".contains($0) }).map(String.init)
        var hour: Int?, minute = 0
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) { hour = h; minute = m }
        else if parts.count == 1, parts[0].allSatisfy(\.isNumber) {
            let d = parts[0]
            switch d.count {
            case 1, 2: hour = Int(d)
            case 3: hour = Int(d.prefix(1)); minute = Int(d.suffix(2)) ?? 0
            case 4: hour = Int(d.prefix(2)); minute = Int(d.suffix(2)) ?? 0
            default: break
            }
        }
        guard var h = hour else { return raw }
        if pm && h < 12 { h += 12 }
        if am && h == 12 { h = 0 }
        guard (0..<24).contains(h), (0..<60).contains(minute) else { return raw }
        return String(format: "%02d:%02d", h, minute)
    }
}

// MARK: - Finding a booking in mail

/// Most people don't remember their flight times; their mailbox does.
enum MailSearch {
    static func bookingQuery(city: String, mode: String) -> String {
        let words = mode == "train" ? "(train OR ticket OR booking OR reservation)"
            : mode == "car" ? "(rental OR booking OR reservation)"
            : "(flight OR boarding OR e-ticket OR itinerary OR booking)"
        return city.isEmpty ? "\(words) newer_than:1y" : "\(words) \"\(city)\" newer_than:1y"
    }
    static func gmailURL(_ query: String) -> URL? {
        let allowed = CharacterSet.urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "#"))
        return URL(string: "https://mail.google.com/mail/u/0/#search/" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""))
    }
}

/// "Find it in Gmail" plus a copy of the same search for any other mail app.
struct FindBookingMenu: View {
    let city: String
    let mode: String
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    var body: some View {
        let query = MailSearch.bookingQuery(city: city, mode: mode)
        Menu {
            Button("Search Gmail", systemImage: "envelope.badge") { if let url = MailSearch.gmailURL(query) { openURL(url) } }
            Button("Copy search for Mail", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = query.replacingOccurrences(of: " newer_than:1y", with: "")
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "envelope.open").font(.system(size: 12, weight: .bold))
                Text(copied ? "Search copied" : "Find my booking in mail")
            }
            .font(Sketch.text(13, "SemiBold", relativeTo: .footnote))
            .padding(.horizontal, 14).frame(minHeight: 40).raisedCapsule()
        }
        .accessibilityHint("Opens a mail search for your \(mode == "train" ? "train" : "flight") booking")
    }
}

// MARK: - Place photos from free sources

/// Wikipedia (for sights), then Apple Look Around, then a small map. All free,
/// cached on disk, at most three lookups at a time.
actor PlaceImageStore {
    static let shared = PlaceImageStore()
    private var memory: [String: UIImage] = [:]
    private var misses: Set<String> = []
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("place-images-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func key(name: String, latitude: Double?, longitude: Double?) -> String {
        let raw = "\(name.lowercased())|\(latitude.map { String(format: "%.4f", $0) } ?? "")|\(longitude.map { String(format: "%.4f", $0) } ?? "")"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    func cached(_ key: String) -> UIImage? { memory[key] }

    func image(name: String, latitude: Double?, longitude: Double?, sight: Bool, url: URL? = nil, website: URL? = nil) async -> UIImage? {
        let key = Self.key(name: name, latitude: latitude, longitude: longitude)
        if let hit = memory[key] { return hit }
        if misses.contains(key) { return nil }
        let file = directory.appendingPathComponent(key + ".jpg")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { memory[key] = image; return image }
        await acquire()
        defer { release() }
        var found: UIImage?
        if let url, let (data, _) = try? await URLSession.shared.data(for: Self.request(url)) { found = UIImage(data: data) }
        if found == nil, let latitude, let longitude {
            let c = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            // Real photos first: Wikipedia for sights, the venue's own website photo for
            // cafés, restaurants and bars. The street-level 3D view only when neither exists.
            if sight { found = await Self.wikipedia(name: name, coordinate: c) }
            if found == nil, let website { found = await Self.websitePhoto(website) }
            if found == nil { found = await Self.lookAround(c) }
            if found == nil { found = await Self.mapSnapshot(c) }
        }
        guard let found else { misses.insert(key); return nil }
        memory[key] = found
        if let data = found.jpegData(compressionQuality: 0.78) { try? data.write(to: file) }
        return found
    }

    private func acquire() async {
        if running < 3 { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Trippy/1.0 (iOS travel planner)", forHTTPHeaderField: "User-Agent")
        return request
    }
    private static func folded(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    /// A Wikipedia article near the place whose title shares a real word with its name.
    private static func wikipedia(name: String, coordinate: CLLocationCoordinate2D) async -> UIImage? {
        let words = Set(folded(name).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 })
        guard !words.isEmpty else { return nil }
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "generator", value: "geosearch"), .init(name: "ggscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            .init(name: "ggsradius", value: "400"), .init(name: "ggslimit", value: "10"),
            .init(name: "prop", value: "pageimages"), .init(name: "piprop", value: "thumbnail"), .init(name: "pithumbsize", value: "480"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Trippy/1.0 (iOS travel planner)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (root["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] else { return nil }
        let match = pages.values.first { page in
            let title = folded(page["title"] as? String ?? "")
            return page["thumbnail"] != nil && words.contains { title.contains($0) }
        }
        guard let source = (match?["thumbnail"] as? [String: Any])?["source"] as? String, let imageURL = URL(string: source),
              let (imageData, _) = try? await URLSession.shared.data(from: imageURL) else { return nil }
        return UIImage(data: imageData)
    }
    /// The picture a venue publishes for link previews (`og:image` / `twitter:image`) on its own website.
    private static func websitePhoto(_ site: URL) async -> UIImage? {
        guard ["http", "https"].contains(site.scheme ?? ""),
              let (data, response) = try? await URLSession.shared.data(for: request(site)),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        let pattern = #"<meta[^>]+(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image)["'][^>]*>"#
        guard let tag = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]).map({ String(html[$0]) }),
              let content = tag.range(of: #"content=["']([^"']+)["']"#, options: .regularExpression).map({ String(tag[$0]) }) else { return nil }
        let raw = content.dropFirst(9).dropLast().replacingOccurrences(of: "&amp;", with: "&")
        guard let imageURL = URL(string: raw, relativeTo: site)?.absoluteURL, imageURL.scheme == "https",
              let (bytes, imageResponse) = try? await URLSession.shared.data(for: request(imageURL)),
              (imageResponse.mimeType ?? "").hasPrefix("image/"), let image = UIImage(data: bytes),
              // Logos and icons are not photos of the place.
              image.size.width >= 300, image.size.height >= 160 else { return nil }
        return image
    }
    private static func lookAround(_ coordinate: CLLocationCoordinate2D) async -> UIImage? {
        guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 480, height: 320)
        return try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
    }
    @MainActor private static func mapSnapshot(_ coordinate: CLLocationCoordinate2D) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 380, longitudinalMeters: 380)
        options.size = CGSize(width: 240, height: 160)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let point = snapshot.point(for: coordinate)
        return UIGraphicsImageRenderer(size: options.size).image { _ in
            snapshot.image.draw(at: .zero)
            let dot = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
            UIColor.white.setFill(); UIBezierPath(ovalIn: dot.insetBy(dx: -2.5, dy: -2.5)).fill()
            UIColor(red: 0.87, green: 0.35, blue: 0.29, alpha: 1).setFill(); UIBezierPath(ovalIn: dot).fill()
        }
    }
}

/// A place's preview image, with a tinted symbol while it loads or when none exists.
struct PlacePhoto: View {
    let name: String
    let latitude: Double?
    let longitude: Double?
    var sight = false
    var symbol = "photo"
    var tint: Color = Sketch.inkSoft
    var imageURL: URL? = nil
    var website: URL? = nil
    @State private var image: UIImage?
    private var key: String { PlaceImageStore.key(name: name, latitude: latitude, longitude: longitude) }
    var body: some View {
        // The image is an overlay so it fills the frame it's given without widening it.
        Rectangle().fill(tint.opacity(0.12))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                } else {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint.opacity(0.7))
                }
            }
            .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            guard latitude != nil || imageURL != nil else { return }
            let found = await PlaceImageStore.shared.image(name: name, latitude: latitude, longitude: longitude, sight: sight, url: imageURL,
                                                           website: website)
            withAnimation(.easeOut(duration: 0.2)) { image = found }
        }
    }
}

extension PlacePhoto {
    init(place: GuidePlace, tint: Color = Sketch.inkSoft) {
        self.init(name: place.name, latitude: place.coordinate?.latitude, longitude: place.coordinate?.longitude,
                  sight: !place.isFood, symbol: place.symbol, tint: tint, website: place.url)
    }
}

// MARK: - Area names

/// "Monti", "Trastevere": the neighbourhood of a point, from the on-device geocoder.
actor AreaNamer {
    static let shared = AreaNamer()
    private var names: [String: String] = [:]
    private var last: Task<String, Never>?
    /// One lookup at a time: the geocoder cancels overlapping requests.
    func name(latitude: Double, longitude: Double) async -> String? {
        let key = String(format: "%.3f,%.3f", latitude, longitude)
        if let hit = names[key] { return hit.nilIfEmpty }
        let previous = last
        let task = Task { () -> String in
            _ = await previous?.value
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)).first
            return placemark?.subLocality ?? placemark?.thoroughfare ?? ""
        }
        last = task
        let name = await task.value
        names[key] = name
        return name.nilIfEmpty
    }
}

struct AreaLabel: View {
    let latitude: Double?
    let longitude: Double?
    @State private var name: String?
    var body: some View {
        // Always a Text, so the lookup below runs even before a name exists.
        Text(name.map { "around \($0)" } ?? "")
            .task(id: "\(latitude ?? 0),\(longitude ?? 0)") {
                guard let latitude, let longitude else { return }
                name = await AreaNamer.shared.name(latitude: latitude, longitude: longitude)
            }
    }
}

// MARK: - The option pool

/// The traveller's saved map places (the same store the map uses), read-only here.
enum SavedPins {
    struct Pin: Decodable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        let category: String
        var address: String?
        var websiteURL: String?
        var saved: Bool?
        /// The plan category a saved place can fill: a saved café is a coffee break.
        var slotCategory: String? {
            switch category {
            case "Coffee", "Brunch": "coffee"
            case "Food", "Street food", "Burger", "Seafood", "Vegan": "food"
            case "Bars", "Clubs": "bar"
            default: nil
            }
        }
        var place: GuideSavedPlace {
            GuideSavedPlace(id: "pin:" + id, name: name, category: slotCategory ?? "food", latitude: latitude, longitude: longitude,
                            address: address?.nilIfEmpty, url: websiteURL)
        }
    }
    static func all() -> [Pin] {
        guard let data = UserDefaults.standard.data(forKey: "trippy.native.personalPlaces.v1"),
              let pins = try? JSONDecoder().decode([Pin].self, from: data) else { return [] }
        return pins.filter { $0.saved != false }
    }
}

struct SlotOption: Identifiable, Hashable {
    var id: String { place.id }
    let place: GuidePlace
    let saved: GuideSavedPlace?
    let metres: Double?
    let fromPlan: Bool
    var walk: String? { metres.map { $0 < 60 ? "right here" : "\(max(1, Int(($0 / 80).rounded()))) min walk" } }
}

@MainActor final class SlotOptionsModel: ObservableObject {
    @Published var options: [SlotOption] = []
    @Published var loading = false
    private static var cache: [String: [SlotOption]] = [:]

    func load(kind: SlotKind, latitude: Double?, longitude: Double?, planPlaces: [GuidePlace]) async {
        let center = latitude.flatMap { lat in longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        let key = "\(kind.rawValue)|\(latitude.map { String(format: "%.3f", $0) } ?? "")|\(longitude.map { String(format: "%.3f", $0) } ?? "")"
        if let hit = Self.cache[key] { options = hit; return }
        func metres(_ c: CLLocationCoordinate2D?) -> Double? {
            guard let center, let c else { return nil }
            return center.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }
        // Places the traveller saved (from TikTok, a search, a friend) lead; then the planner's own candidates.
        let pins = SavedPins.all().filter { $0.slotCategory.map(kind.matches) ?? false }.map { pin -> SlotOption in
            var place = pin.place.guidePlace
            place.reason = "Saved by you"
            return SlotOption(place: place, saved: pin.place, metres: metres(place.coordinate), fromPlan: true)
        }.filter { ($0.metres ?? .infinity) < 2000 }
        let pinNames = Set(pins.map { $0.place.name.lowercased() })
        var result = pins.sorted { ($0.metres ?? .infinity) < ($1.metres ?? .infinity) } + planPlaces.filter { kind.matches($0.category) && !pinNames.contains($0.name.lowercased()) }
            .map { SlotOption(place: $0, saved: nil, metres: metres($0.coordinate), fromPlan: true) }
            .filter { ($0.metres ?? 0) < 1300 }
            .sorted { ($0.metres ?? .infinity) < ($1.metres ?? .infinity) }
        options = result
        guard let center else { return }
        loading = true
        let filter = MKPointOfInterestFilter(including: kind.poiCategories)
        let nearby = MKLocalPointsOfInterestRequest(center: center.coordinate, radius: 700)
        nearby.pointOfInterestFilter = filter
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = kind.query
        search.region = MKCoordinateRegion(center: center.coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600)
        search.resultTypes = .pointOfInterest
        search.pointOfInterestFilter = filter
        async let a = try? MKLocalSearch(request: nearby).start()
        async let b = try? MKLocalSearch(request: search).start()
        let items = ((await a)?.mapItems ?? []) + ((await b)?.mapItems ?? [])
        func folded(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter) }
        var seen = Set(result.map { folded($0.place.name) })
        for item in items {
            // Natural-language search can drift (parking, hotels); keep the block's own kinds.
            guard let category = item.pointOfInterestCategory, kind.poiCategories.contains(category) else { continue }
            let saved = GuideSavedPlace(item: item, category: kind.category)
            guard seen.insert(folded(saved.name)).inserted else { continue }
            let distance = metres(.init(latitude: saved.latitude, longitude: saved.longitude))
            guard (distance ?? 0) < 1100 else { continue }
            result.append(SlotOption(place: saved.guidePlace, saved: saved, metres: distance, fromPlan: false))
        }
        let curated = result.filter(\.fromPlan)
        let more = result.filter { !$0.fromPlan }.sorted { ($0.metres ?? .infinity) < ($1.metres ?? .infinity) }
        options = curated + more.prefix(40)
        Self.cache[key] = options
        loading = false
    }
}

// MARK: - Block row

struct SlotRow: View {
    let stop: ResolvedStop
    let slot: ResolvedSlot
    let color: Color
    let editing: Bool
    let planPlaces: [GuidePlace]
    @Binding var time: String
    let onPick: (SlotOption?) -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    /// The stops before and after this block, and the stay: context on the options map.
    var neighbors: [GuidePlace] = []
    var base: GuideBase? = nil
    @StateObject private var pool = SlotOptionsModel()
    @State private var showAll = false
    /// How many recommendations are showing; "Show more" adds three.
    @State private var shown = 3
    #if DEBUG
    @MainActor static var debugOpened = false
    #endif

    private var picked: Bool { slot.pickedID != nil }
    /// The other choices, best first: places you saved, then the planner's with a reason, then the nearest.
    private var others: [SlotOption] {
        pool.options.filter { $0.id != slot.pickedID }.sorted { a, b in
            func rank(_ o: SlotOption) -> (Int, Double) {
                (o.place.reason == "Saved by you" ? 0 : o.fromPlan && !o.place.plainWhy.isEmpty ? 1 : o.fromPlan ? 2 : 3, o.metres ?? 9_999)
            }
            return rank(a) < rank(b)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                if editing {
                    TextField("13:00", text: $time).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.center)
                        .frame(width: 58, height: 34).background(RoundedRectangle(cornerRadius: 8).fill(Sketch.paperDeep))
                        .onSubmit { time = TimeShorthand.normalize(time) }
                } else {
                    Text(stop.time).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                }
                Text("\(stop.durationMinutes) min").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: slot.kind.symbol).font(.system(size: 11, weight: .bold))
                    Text(slot.kind.title.uppercased()).tracking(0.8)
                    AreaLabel(latitude: slot.latitude, longitude: slot.longitude)
                        .foregroundStyle(Sketch.inkSoft).textCase(nil).tracking(0)
                }
                .font(Sketch.text(11, "Bold", relativeTo: .caption)).foregroundStyle(color).lineLimit(1)
                .accessibilityElement(children: .combine)

                Button { showAll = true } label: { pickCard }
                    .buttonStyle(SketchPressStyle())
                    .accessibilityHint("Shows all nearby options")

                if !others.isEmpty { recommendations }
                if editing {
                    HStack(spacing: 4) {
                        iconButton("arrow.up", "Move up") { onMove(-1) }
                        iconButton("arrow.down", "Move down") { onMove(1) }
                        Spacer()
                        iconButton("trash", "Remove \(slot.kind.title.lowercased())", role: .destructive, action: onRemove)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .task(id: "\(slot.kind.rawValue)|\(slot.latitude ?? 0)|\(slot.longitude ?? 0)") {
            await pool.load(kind: slot.kind, latitude: slot.latitude, longitude: slot.longitude, planPlaces: planPlaces)
        }
        #if DEBUG
        .task {
            // `-TrippyGuideBlockSheet lunch` opens the first such block's options for screenshots.
            guard let kind = UserDefaults.standard.string(forKey: "TrippyGuideBlockSheet"), kind == slot.kind.rawValue,
                  !SlotRow.debugOpened else { return }
            SlotRow.debugOpened = true
            try? await Task.sleep(for: .seconds(6)); showAll = true
        }
        #endif
        .sheet(isPresented: $showAll) {
            SlotOptionsSheet(kind: slot.kind, latitude: slot.latitude, longitude: slot.longitude, options: pool.options,
                             loading: pool.loading, pickedID: slot.pickedID, suggestedID: slot.suggestedID, color: color,
                             neighbors: neighbors, base: base) { choice in
                onPick(choice); showAll = false
            }
        }
    }

    @ViewBuilder private var pickCard: some View {
        HStack(spacing: 12) {
            if picked {
                PlacePhoto(place: stop.place, tint: color).frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: slot.kind.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(picked ? stop.place.name : "Decide on the day")
                    .font(Sketch.text(15, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(cardDetail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                if !stop.why.isEmpty {
                    Text(stop.why).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.inkFaint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(picked ? Sketch.rule : color.opacity(0.5), style: StrokeStyle(lineWidth: picked ? 0.8 : 1.2, dash: picked ? [] : [5, 4])))
        .contentShape(Rectangle())
    }

    private var cardDetail: String {
        let count = pool.options.count
        if !picked { return count > 0 ? "Pick one below, or leave it for the day" : "Pick a place now or on the day" }
        var parts: [String] = []
        if stop.place.id == slot.suggestedID { parts.append("Planner's pick") }
        else if stop.place.tags.contains("apple_maps") { parts.append("Your pick") }
        if let option = pool.options.first(where: { $0.id == stop.place.id }), let walk = option.walk { parts.append(walk) }
        if let rating = stop.place.rating { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }

    /// Three places with the reason for each, one tap to choose. "Show more" brings the next three; the map has all.
    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(picked ? "OR TRY" : "RECOMMENDED").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint).padding(.bottom, 4)
            ForEach(Array(others.prefix(shown).enumerated()), id: \.element.id) { index, option in
                if index > 0 { Divider().overlay(Sketch.rule).padding(.leading, 60) }
                Button { TrippyHaptics.light(); withAnimation(.snappy) { onPick(option) } } label: {
                    HStack(spacing: 12) {
                        PlacePhoto(place: option.place, tint: color).frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.place.name).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink).lineLimit(1)
                            Text(why(option)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(color)
                    }
                    .frame(minHeight: 60).contentShape(Rectangle())
                }
                .buttonStyle(SketchPressStyle())
                .accessibilityLabel("Choose \(option.place.name). \(why(option))")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            BubbleFlow(spacing: 8) {
                if others.count > shown {
                    chip("Show more", "chevron.down") { withAnimation(.snappy) { shown += 3 } }
                }
                chip("On the map", "map") { showAll = true }
                if picked { chip("Leave open", "circle.dashed") { withAnimation(.snappy) { onPick(nil) } } }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card.opacity(0.6)))
    }

    /// Why this one: the strongest thing we know about it, then how far it is.
    private func why(_ option: SlotOption) -> String {
        var parts: [String] = []
        if !option.place.plainWhy.isEmpty { parts.append(option.place.plainWhy) }
        else if option.place.fromWikivoyage { parts.append("In the travel guide") }
        else if option.place.fromVideo || option.place.videoCount > 0 { parts.append("From a video") }
        else if option.fromPlan { parts.append("On the planner's shortlist") }
        if let walk = option.walk { parts.append(walk) }
        if let rating = option.place.rating { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.isEmpty ? option.place.categoryLabel : parts.joined(separator: " · ")
    }

    private func chip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(color)
                .lineLimit(1).fixedSize().padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().fill(color.opacity(0.1)))
        }.buttonStyle(SketchPressStyle())
    }

    private func iconButton(_ symbol: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(label)
    }
}

/// A small card in the "nearby" strip: photo, name, walk.
private struct OptionTile: View {
    let option: SlotOption
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PlacePhoto(place: option.place, tint: tint).frame(width: 118, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if option.fromPlan {
                        Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Circle().fill(tint)).padding(5)
                    }
                }
            Text(option.place.name).font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.ink)
                .lineLimit(1)
            Text(option.walk ?? " ").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint).lineLimit(1)
        }
        .frame(width: 118, alignment: .leading)
    }
}

// MARK: - All options

/// All options for one block on one map: the area, the stops around it and the
/// stay for context; numbered pins match the cards below. A list with search is
/// one tap away for when you know what you want.
struct SlotOptionsSheet: View {
    let kind: SlotKind
    let latitude: Double?
    let longitude: Double?
    let options: [SlotOption]
    let loading: Bool
    let pickedID: String?
    let suggestedID: String?
    let color: Color
    var neighbors: [GuidePlace] = []
    var base: GuideBase? = nil
    let onChoose: (SlotOption?) -> Void
    @State private var query = ""
    @State private var focused: String?
    @State private var showList = false
    @State private var camera: MapCameraPosition = .automatic
    @Environment(\.dismiss) private var dismiss

    private var filtered: [SlotOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { $0.place.name.localizedCaseInsensitiveContains(q) || ($0.place.address ?? "").localizedCaseInsensitiveContains(q) }
    }
    /// Plan picks first, then nearest: the order of pins and cards.
    private var ranked: [SlotOption] { Array(filtered.prefix(30)) }

    var body: some View {
        NavigationStack {
            Group {
                if showList { list } else { mapAndCards }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(kind.title).font(Sketch.text(16, "Bold", relativeTo: .headline))
                        AreaLabel(latitude: latitude, longitude: longitude).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation(.snappy) { showList.toggle() } } label: {
                        Image(systemName: showList ? "map" : "list.bullet")
                    }
                    .accessibilityLabel(showList ? "Show map" : "Show list")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { onChoose(nil) } label: {
                    Label(pickedID == nil ? "Deciding on the day" : "Decide on the day instead", systemImage: "clock")
                        .font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(Sketch.paperDeep))
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
                .accessibilityHint("Keeps the block without a place")
            }
        }
        .tint(color)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = pickedID ?? ranked.first?.id }
    }

    // MARK: Map + cards

    private var mapAndCards: some View {
        VStack(spacing: 0) {
            Map(position: $camera, selection: $focused) {
                if let latitude, let longitude {
                    MapCircle(center: .init(latitude: latitude, longitude: longitude), radius: 450)
                        .foregroundStyle(color.opacity(0.08)).stroke(color.opacity(0.35), lineWidth: 1)
                }
                if let base {
                    Annotation(base.name, coordinate: base.coordinate, anchor: .bottom) { BasePin() }
                }
                ForEach(Array(neighbors.enumerated()), id: \.offset) { _, place in
                    if let c = place.coordinate {
                        Annotation(place.name, coordinate: c) {
                            Image(systemName: place.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Circle().fill(Sketch.inkSoft))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        }
                    }
                }
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, option in
                    if let c = option.place.coordinate {
                        Annotation(option.place.name, coordinate: c) {
                            OptionPin(number: index + 1, selected: focused == option.id, chosen: option.id == pickedID,
                                      fromPlan: option.fromPlan, tint: color)
                        }
                        .tag(option.id)
                        .annotationTitles(focused == option.id ? .visible : .hidden)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(maxHeight: .infinity)
            if loading && options.isEmpty {
                ProgressView("Looking around…").padding()
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, option in
                            OptionCard(option: option, number: index + 1, chosen: option.id == pickedID,
                                       suggested: option.id == suggestedID, tint: color) { onChoose(option) }
                                .id(option.id)
                                .onTapGesture { withAnimation(.snappy) { focused = option.id } }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focused, anchor: .center)
                .frame(height: 252)
                .onChange(of: focused) { _, id in
                    // Keep the focused card and pin together, whichever was tapped.
                    if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            let planned = filtered.filter(\.fromPlan)
            if !planned.isEmpty {
                Section("Recommended for this plan") { ForEach(planned) { row($0) } }
            }
            let nearby = filtered.filter { !$0.fromPlan }
            Section {
                ForEach(nearby) { row($0) }
                if loading { HStack { ProgressView(); Text("Looking around…").foregroundStyle(Sketch.inkSoft) } }
                else if nearby.isEmpty { Text("No other places found nearby.").foregroundStyle(Sketch.inkSoft) }
            } header: { Text("More nearby") } footer: { Text("Nearby places from Apple Maps.") }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search \(options.count) places")
    }

    private func row(_ option: SlotOption) -> some View {
        Button { onChoose(option) } label: {
            HStack(spacing: 12) {
                PlacePhoto(place: option.place, tint: color).frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.place.name).font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                    Text(OptionCard.detail(option, suggested: option.id == suggestedID)).font(Sketch.text(12, relativeTo: .caption))
                        .foregroundStyle(Sketch.inkSoft).lineLimit(2)
                }
                Spacer(minLength: 4)
                if option.id == pickedID { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(color) }
            }
            .frame(minHeight: 60)
        }
        .accessibilityAddTraits(option.id == pickedID ? .isSelected : [])
    }
}

/// A numbered option on the block map.
private struct OptionPin: View {
    let number: Int
    let selected: Bool
    let chosen: Bool
    let fromPlan: Bool
    let tint: Color
    var body: some View {
        Text("\(number)").font(.system(size: selected ? 13 : 11, weight: .heavy, design: .rounded)).monospacedDigit()
            .foregroundStyle(selected || chosen ? .white : tint)
            .frame(width: selected ? 32 : 24, height: selected ? 32 : 24)
            .background(Circle().fill(selected || chosen ? tint : Sketch.card))
            .overlay(Circle().strokeBorder(fromPlan ? tint : Sketch.rule, lineWidth: fromPlan ? 2 : 1))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
            .animation(.snappy, value: selected)
    }
}

/// A large card for one option: photo, what it is, how far, and choose.
private struct OptionCard: View {
    let option: SlotOption
    let number: Int
    let chosen: Bool
    let suggested: Bool
    let tint: Color
    let onChoose: () -> Void
    static func detail(_ option: SlotOption, suggested: Bool) -> String {
        var parts: [String] = []
        if option.place.reason == "Saved by you" { parts.append("Saved by you") }
        else if suggested { parts.append("Planner's pick") } else if option.fromPlan { parts.append("Fits your plan") }
        if let walk = option.walk { parts.append(walk) }
        if let rating = option.place.rating { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlacePhoto(place: option.place, tint: tint).frame(width: 260, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(number)").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(tint)).padding(8)
                }
            Text(option.place.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.ink).lineLimit(1)
            Text(Self.detail(option, suggested: suggested)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            if let address = option.place.address {
                Text(address).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).lineLimit(1)
            }
            Button(action: onChoose) {
                Text(chosen ? "Chosen" : "Choose").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                    .foregroundStyle(chosen ? tint : .white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(chosen ? tint.opacity(0.12) : tint))
            }
            .buttonStyle(SketchPressStyle())
            .accessibilityLabel(chosen ? "\(option.place.name), chosen" : "Choose \(option.place.name)")
        }
        .padding(10)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(chosen ? tint : Sketch.rule, lineWidth: chosen ? 2 : 0.7))
    }
}

extension Array {
    /// nil instead of a crash for an index outside the array.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
