import MapKit
import SwiftUI

/// What sits under the middle of the map or globe once you've zoomed in: a country, or a city when you're close.
struct ZoomAddTarget: Equatable {
    enum Level { case country, city }
    let level: Level
    let name: String
    let countryCode: String
    let coordinate: CLLocationCoordinate2D

    static func == (a: Self, b: Self) -> Bool { a.level == b.level && a.name == b.name && a.countryCode == b.countryCode }

    var place: VisitedPlace { VisitedPlace(name: name, countryCode: countryCode, latitude: coordinate.latitude, longitude: coordinate.longitude, kind: level == .country ? .country : .city, dated: false) }

    func isAdded(in visits: [VisitedPlace]) -> Bool {
        switch level {
        case .country: visits.contains { $0.countryCode?.uppercased() == countryCode }
        case .city: visits.contains { !$0.isCountry && VisitedPlace.normalized($0.name) == VisitedPlace.normalized(name) && $0.countryCode?.uppercased() == countryCode }
        }
    }

    /// Asks Apple's geocoder what is under `center`. One request per settled view (the geocoder is rate limited).
    static func resolve(_ center: CLLocationCoordinate2D, level: Level) async -> ZoomAddTarget? {
        guard CLLocationCoordinate2DIsValid(center),
              let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: center.latitude, longitude: center.longitude),
                                                                        preferredLocale: Locale(identifier: "en")).first,
              let code = mark.isoCountryCode?.uppercased() else { return nil }
        if level == .city, let city = mark.locality ?? mark.subAdministrativeArea {
            return ZoomAddTarget(level: .city, name: city, countryCode: code, coordinate: mark.location?.coordinate ?? center)
        }
        let name = Locale(identifier: "en").localizedString(forRegionCode: code) ?? mark.country ?? code
        let point = PlaceCatalog.country(code).flatMap { c in c.latitude.flatMap { lat in c.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } } ?? center
        return ZoomAddTarget(level: .country, name: name, countryCode: code, coordinate: point)
    }
}

/// A minimal round "+" that pops in over the zoomed-in place; tap to add it (or see that it's already yours).
struct ZoomAddBubble: View {
    let target: ZoomAddTarget
    let added: Bool
    let action: () -> Void
    @State private var taps = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(added ? Sketch.sage : Sketch.ink)
                    Image(systemName: added ? "checkmark" : "plus").font(.system(size: 16, weight: .heavy)).foregroundStyle(Sketch.paper)
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(target.name).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.ink).lineLimit(1)
                    Text(added ? "Visited" : target.level == .city ? "Add city" : "Add country")
                        .font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                        .contentTransition(.opacity)
                }
                Text(WorldGlobeView.flag(target.countryCode)).font(.system(size: 18))
            }
            .padding(.leading, 5).padding(.trailing, 14).frame(height: 46)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        }
        .buttonStyle(BubblePressStyle())
        .keyframeAnimator(initialValue: 1.0, trigger: taps) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
            SpringKeyframe(0.82, duration: 0.08)
            SpringKeyframe(1.12, duration: 0.18, spring: .bouncy)
            SpringKeyframe(1, duration: 0.22)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: added)
        .accessibilityLabel(added ? "\(target.name), visited" : "Add \(target.name)")
        .transition(.scale(scale: 0.3, anchor: .bottom).combined(with: .opacity))
    }
}

/// A settled view to look up: the rounded centre and how close we are.
struct ZoomProbe: Equatable, Hashable {
    let latitude: Double
    let longitude: Double
    let level: ZoomAddTarget.Level
    var center: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
