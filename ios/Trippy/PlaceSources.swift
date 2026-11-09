import SwiftUI
import MapKit
import GooglePlacesSwift

// Where a place card's information comes from, kept inside the EEA terms:
// • Apple MapKit gives name, category, address, phone and website as data we may lay out ourselves (free).
// • Google content appears only through the Places UI Kit block, which the terms allow next to any map.
//   We store nothing from Google except the place ID.
// • Apple's own place card (iOS 18) shows Apple's ratings, hours and photos on request (free).

/// Loads the app's Google key for the Places UI Kit once, from the bridge (it lives in Render, not in the repo).
@MainActor final class GooglePlacesKit {
    static let shared = GooglePlacesKit()
    private(set) var isReady = false
    private var loading: Task<Bool, Never>?
    private let storageKey = "trippy.googlePlacesIOSKey"

    func prepare(baseURL: String, token: String) async -> Bool {
        if isReady { return true }
        if let stored = UserDefaults.standard.string(forKey: storageKey), !stored.isEmpty {
            isReady = PlacesClient.provideAPIKey(stored); return isReady
        }
        if let loading { return await loading.value }
        let task = Task { () -> Bool in
            guard !token.isEmpty, let url = URL(string: baseURL + "/api/places/ios-key") else { return false }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String,
                  !key.isEmpty else { return false }
            UserDefaults.standard.set(key, forKey: storageKey)
            return PlacesClient.provideAPIKey(key)
        }
        loading = task
        let ready = await task.value
        isReady = ready
        loading = nil
        return ready
    }

    /// Google bills each UI Kit load; the bridge counts it for the dashboard and the cost calculator.
    func reportLoad(baseURL: String, token: String) {
        guard !token.isEmpty, let url = URL(string: baseURL + "/api/places/kit-load") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        Task.detached { _ = try? await URLSession.shared.data(for: request) }
    }

    /// Free Google place ID for a place we already know (IDs-only search, no Google content returned).
    func matchPlaceID(name: String, coordinate: CLLocationCoordinate2D, baseURL: String, token: String) async -> String? {
        guard !token.isEmpty, var components = URLComponents(string: baseURL + "/api/places/match") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: name),
                                 URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                                 URLQueryItem(name: "lng", value: String(coordinate.longitude))]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["placeID"] as? String
    }
}

/// Google's rating, price and open-now line, drawn by Google's UI Kit in our colours and type.
struct GooglePlaceBlock: View {
    let placeID: String
    let baseURL: String
    let token: String
    @State private var query: PlaceDetailsQuery
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme

    init(placeID: String, baseURL: String, token: String) {
        self.placeID = placeID; self.baseURL = baseURL; self.token = token
        _query = State(initialValue: PlaceDetailsQuery(identifier: .placeID(placeID)))
    }

    var body: some View {
        if !failed {
            PlaceDetailsCompactView(orientation: .vertical, query: $query,
                                    configuration: PlaceDetailsCompactConfiguration(
                                        content: [.name(false), .address(false), .type(false), .media(lightbox: false),
                                                  .rating(), .price(), .openNowStatus(), .accessibleEntranceIcon()],
                                        preferTruncation: true, theme: theme)) { result in
                if result.place == nil { failed = true }
                GooglePlacesKit.shared.reportLoad(baseURL: baseURL, token: token)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Google Maps rating and opening status")
        }
    }

    private var theme: PlacesMaterialTheme {
        var theme = PlacesMaterialTheme()
        var color = PlacesMaterialColor()
        color.surface = Sketch.card
        color.outlineDecorative = Sketch.rule
        color.onSurface = AppPalette.ink
        color.onSurfaceVariant = AppPalette.secondaryInk
        color.starRating = Sketch.ochre
        color.disabledSurface = Sketch.rule
        color.positive = Sketch.sage
        color.negative = Sketch.coral
        color.primary = Sketch.coral
        color.info = Sketch.sky
        color.secondaryContainer = Sketch.paperDeep
        color.onSecondaryContainer = AppPalette.ink
        theme.color = color
        var font = PlacesMaterialFont()
        font.titleSmall = Font.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline)
        font.labelLarge = Font.custom("PlusJakartaSans-SemiBold", size: 13, relativeTo: .subheadline)
        font.bodyMedium = Font.custom("PlusJakartaSans-Medium", size: 13, relativeTo: .footnote)
        font.bodySmall = Font.custom("PlusJakartaSans-Medium", size: 12, relativeTo: .caption)
        font.labelMedium = Font.custom("PlusJakartaSans-Medium", size: 11, relativeTo: .caption2)
        theme.font = font
        var shape = PlacesMaterialShape()
        shape.cornerRadius = 18
        shape.cornerRadiusCard = 18
        shape.cornerRadiusThumbnail = 12
        shape.cornerRadiusButton = 99
        theme.shape = shape
        return theme
    }
}

/// Apple's data for a pin: the Apple place itself when we can find it nearby, for our own layout
/// and for Apple's place card.
enum ApplePlaceLookup {
    static func mapItem(name: String, coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = [.pointOfInterest, .address]
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        func folded(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let target = folded(name)
        let scored = items.compactMap { item -> (MKMapItem, Double)? in
            let metres = origin.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
            let itemName = folded(item.name ?? "")
            let nameMatches = !itemName.isEmpty && (itemName == target || itemName.contains(target) || target.contains(itemName))
            guard metres < (nameMatches ? 400 : 60) else { return nil }
            return (item, metres - (nameMatches ? 1_000 : 0))
        }
        return scored.min { $0.1 < $1.1 }?.0
    }

    /// A readable category for the chip, from Apple's point-of-interest category.
    static func categoryName(_ item: MKMapItem) -> String {
        guard let raw = item.pointOfInterestCategory?.rawValue else { return "" }
        let name = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        return name.unicodeScalars.reduce("") { text, scalar in
            CharacterSet.uppercaseLetters.contains(scalar) && !text.isEmpty ? text + " " + String(scalar) : text + String(scalar)
        }
    }
}

/// The quiet "Apple Maps" button that opens Apple's own place card on top of ours.
struct AppleMapsCardButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppPalette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(Sketch.card)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Maps").font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(AppPalette.ink)
                    Text("Ratings, hours and photos").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Sketch.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityHint("Opens Apple Maps' card for this place")
    }
}

/// Presents Apple's place card where the system supports it (iOS 18 and later).
struct AppleMapsCardSheet: ViewModifier {
    @Binding var item: MKMapItem?
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapItemDetailSheet(item: $item, displaysMap: false)
        } else {
            content
        }
    }
}
