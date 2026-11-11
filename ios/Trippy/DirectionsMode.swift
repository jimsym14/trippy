import MapKit
import SwiftUI

// MARK: - Model

/// One end of a trip: where you are now, or a place.
enum DirectionsEndpoint: Equatable {
    case currentLocation
    case place(name: String, coordinate: CLLocationCoordinate2D)

    var title: String {
        switch self {
        case .currentLocation: "My location"
        case .place(let name, _): name
        }
    }
    static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.currentLocation, .currentLocation): true
        case let (.place(n1, c1), .place(n2, c2)): n1 == n2 && c1.latitude == c2.latitude && c1.longitude == c2.longitude
        default: false
        }
    }
}

enum DirectionsTransport: String, CaseIterable, Identifiable {
    case car, walk, transit, cycle
    var id: String { rawValue }
    /// Cycling routes need iOS 18; older phones don't see the mode.
    static var allCases: [DirectionsTransport] {
        if #available(iOS 18.0, *) { return [.car, .walk, .transit, .cycle] }
        return [.car, .walk, .transit]
    }
    var title: String { switch self { case .car: "Drive"; case .walk: "Walk"; case .transit: "Transit"; case .cycle: "Cycle" } }
    var symbol: String { switch self { case .car: "car.fill"; case .walk: "figure.walk"; case .transit: "tram.fill"; case .cycle: "bicycle" } }
    var mapKit: MKDirectionsTransportType {
        switch self {
        case .car: return .automobile
        case .walk: return .walking
        case .transit: return .transit
        case .cycle:
            if #available(iOS 18.0, *) { return .cycling }
            return .walking
        }
    }
    var launchMode: String {
        switch self {
        case .car: return MKLaunchOptionsDirectionsModeDriving
        case .walk: return MKLaunchOptionsDirectionsModeWalking
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        case .cycle:
            if #available(iOS 18.0, *) { return MKLaunchOptionsDirectionsModeCycling }
            return MKLaunchOptionsDirectionsModeWalking
        }
    }
}

/// The lines that stop near both ends of a trip (GET /api/transit/between): a direct line when there is one.
struct TransitBetween: Decodable, Equatable {
    struct Line: Decodable, Identifiable, Equatable {
        let id: String; let mode: String; let modeTitle: String; let ref: String; let color: String?; let international: Bool
        enum CodingKeys: String, CodingKey { case id, mode, ref, color, international; case modeTitle = "mode_title" }
        var symbol: String {
            switch mode { case "bus", "trolleybus", "coach": "bus.fill"; case "train": "train.side.front.car"; case "ferry": "ferry.fill"; default: "tram.fill" }
        }
    }
    let direct: [Line]
    let from: [Line]
    let to: [Line]
    let known: Bool
}

enum DirectionsTiming: String, CaseIterable, Identifiable {
    case now, departAt, arriveBy
    var id: String { rawValue }
    var title: String { switch self { case .now: "Leave now"; case .departAt: "Leave at"; case .arriveBy: "Arrive by" } }
}

/// Routes from Apple Maps (MapKit). Driving and walking draw full routes with alternatives; Apple only gives
/// public transport as an arrival time in third-party apps, so Transit shows the time and opens Apple Maps for the
/// lines and stops.
@MainActor
final class DirectionsModel: ObservableObject {
    @Published var from: DirectionsEndpoint = .currentLocation
    @Published var to: DirectionsEndpoint = .currentLocation
    @Published var transport: DirectionsTransport = .car
    @Published var timing: DirectionsTiming = .now
    @Published var date = Date()
    @Published private(set) var routes: [MKRoute] = []
    @Published var selected = 0
    @Published private(set) var etas: [DirectionsTransport: MKDirections.ETAResponse] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    /// Transit only: the lines serving both ends, from OpenStreetMap through our server.
    @Published private(set) var lines: TransitBetween?
    @Published private(set) var linesLoading = false
    private var task: Task<Void, Never>?
    private var linesTask: Task<Void, Never>?

    func coordinate(_ endpoint: DirectionsEndpoint, location: CLLocation?) -> CLLocationCoordinate2D? {
        switch endpoint { case .currentLocation: location?.coordinate; case .place(_, let coordinate): coordinate }
    }

    /// Looks up the lines for the current two ends. The first look at a neighbourhood can take a minute.
    func loadLines(location: CLLocation?, baseURL: String, token: String) {
        linesTask?.cancel()
        guard transport == .transit, !token.isEmpty, let a = coordinate(from, location: location), let b = coordinate(to, location: location),
              var components = URLComponents(string: baseURL + "/api/transit/between") else { lines = nil; linesLoading = false; return }
        components.queryItems = [URLQueryItem(name: "from", value: String(format: "%.4f,%.4f", a.latitude, a.longitude)),
                                 URLQueryItem(name: "to", value: String(format: "%.4f,%.4f", b.latitude, b.longitude))]
        guard let url = components.url else { return }
        lines = nil; linesLoading = true
        linesTask = Task {
            var request = URLRequest(url: url, timeoutInterval: 150)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
            let found = (try? await URLSession.shared.data(for: request)).flatMap { data, response in
                (response as? HTTPURLResponse)?.statusCode == 200 ? try? JSONDecoder().decode(TransitBetween.self, from: data) : nil
            }
            guard !Task.isCancelled else { return }
            lines = found; linesLoading = false
        }
    }

    var route: MKRoute? { routes.indices.contains(selected) ? routes[selected] : nil }
    var usesCurrentLocation: Bool {
        if case .currentLocation = from { return true }
        if case .currentLocation = to { return true }
        return false
    }

    func swap() { (from, to) = (to, from) }

    func recalculate(location: CLLocation?) {
        task?.cancel()
        task = Task { await calculate(location: location) }
    }

    func clear() { task?.cancel(); routes = []; etas = [:]; error = nil; loading = false }

    private func item(_ endpoint: DirectionsEndpoint, location: CLLocation?) -> MKMapItem? {
        switch endpoint {
        case .currentLocation:
            guard let location else { return nil }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate)); item.name = "My location"; return item
        case .place(let name, let coordinate):
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate)); item.name = name; return item
        }
    }

    private func request(_ transport: DirectionsTransport, location: CLLocation?) -> MKDirections.Request? {
        guard let source = item(from, location: location), let destination = item(to, location: location) else { return nil }
        let request = MKDirections.Request()
        request.source = source; request.destination = destination
        request.transportType = transport.mapKit
        request.requestsAlternateRoutes = transport != .transit
        switch timing {
        case .now: break
        case .departAt: request.departureDate = date
        case .arriveBy: request.arrivalDate = date
        }
        return request
    }

    private func calculate(location: CLLocation?) async {
        guard from != to else { routes = []; error = "Pick two different places."; return }
        guard request(transport, location: location) != nil else {
            routes = []; error = from == .currentLocation || to == .currentLocation ? "Finding your location…" : nil; return
        }
        loading = true; error = nil
        defer { if !Task.isCancelled { loading = false } }
        // Times for every mode, for the chips.
        await withTaskGroup(of: (DirectionsTransport, MKDirections.ETAResponse?).self) { group in
            for mode in DirectionsTransport.allCases {
                guard let request = request(mode, location: location) else { continue }
                group.addTask { (mode, try? await MKDirections(request: request).calculateETA()) }
            }
            var found: [DirectionsTransport: MKDirections.ETAResponse] = [:]
            for await (mode, response) in group { if let response { found[mode] = response } }
            if !Task.isCancelled { etas = found }
        }
        guard !Task.isCancelled else { return }
        if transport == .transit {
            routes = []; selected = 0
            if etas[.transit] == nil { error = "No public transport times here. Try Apple Maps." }
            return
        }
        guard let request = request(transport, location: location) else { return }
        do {
            let response = try await MKDirections(request: request).calculate()
            guard !Task.isCancelled else { return }
            routes = Array(response.routes.prefix(3)); selected = 0
            if routes.isEmpty { error = "Apple Maps found no \(transport.title.lowercased()) route." }
        } catch {
            guard !Task.isCancelled else { return }
            routes = []; self.error = "Apple Maps couldn’t find a \(transport.title.lowercased()) route."
        }
    }

    /// Hands the same trip (mode and time) to Apple Maps.
    func openInAppleMaps(location: CLLocation?) {
        var items: [MKMapItem] = []
        if from == .currentLocation { items.append(.forCurrentLocation()) } else if let item = item(from, location: location) { items.append(item) }
        if to == .currentLocation { items.append(.forCurrentLocation()) } else if let item = item(to, location: location) { items.append(item) }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: transport.launchMode])
    }
}

enum DirectionsFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    static func distance(_ meters: CLLocationDistance) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    }
    static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

// MARK: - Top: from, to, mode, time

struct DirectionsTopPanel: View {
    @ObservedObject var model: DirectionsModel
    let onPick: (Bool) -> Void          // true = picking the start
    @Namespace private var modes
    @Namespace private var timing
    /// Modes and time fold away under the two places.
    @State private var optionsOpen = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if optionsOpen {
                endpoints.transition(.move(edge: .top).combined(with: .opacity))
                modeRow.transition(.opacity)
                timeRow.transition(.opacity)
            } else {
                // Retracted: one row with the modes and when.
                HStack(spacing: 8) {
                    compactModes
                    Spacer(minLength: 0)
                    timingMenu(compact: true)
                    if model.timing != .now { dayAndTime }
                }
                .transition(.opacity)
            }
            Button {
                TrippyHaptics.selection()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { optionsOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if !optionsOpen {
                        Text("\(model.from.title) → \(model.to.title)").font(Sketch.text(11, "SemiBold", relativeTo: .caption2)).lineLimit(1)
                    }
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).rotationEffect(.degrees(optionsOpen ? 0 : 180))
                }
                .foregroundStyle(Sketch.inkSoft).frame(maxWidth: .infinity, minHeight: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(optionsOpen ? "Shrink the directions panel" : "Show start and destination")
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height < -20, optionsOpen { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { optionsOpen = false } }
            else if value.translation.height > 20, !optionsOpen { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { optionsOpen = true } }
        })
    }

    private var endpoints: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                endpointRow(model.from, start: true)
                Rectangle().fill(Sketch.rule).frame(height: 0.7).padding(.leading, 48).padding(.trailing, 56)
                endpointRow(model.to, start: false)
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.paperDeep.opacity(0.75)))
            // Swap sits on the line between start and destination.
            Button {
                TrippyHaptics.selection()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { model.swap() }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Sketch.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Sketch.card))
                    .overlay(Circle().strokeBorder(Sketch.rule, lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .buttonStyle(BubblePressStyle()).padding(.trailing, 10)
            .accessibilityLabel("Swap start and destination")
        }
    }

    /// Three small icon segments for the retracted row.
    private var compactModes: some View {
        HStack(spacing: 2) {
            ForEach(DirectionsTransport.allCases) { mode in
                let on = model.transport == mode
                Button {
                    TrippyHaptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { model.transport = mode }
                } label: {
                    Image(systemName: mode.symbol).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                        .frame(width: 40, height: 32)
                        .background { if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "mode", in: modes) } }
                }
                .buttonStyle(.plain).accessibilityLabel(mode.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(Sketch.paperDeep.opacity(0.75)))
    }

    /// One button for Leave now / Leave at / Arrive by.
    private func timingMenu(compact: Bool) -> some View {
        Menu {
            Picker("When", selection: Binding(get: { model.timing }, set: { value in
                TrippyHaptics.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.timing = value }
            })) {
                Label("Leave now", systemImage: "clock").tag(DirectionsTiming.now)
                Label("Leave at…", systemImage: "arrow.up.right.circle").tag(DirectionsTiming.departAt)
                Label("Arrive by…", systemImage: "flag.checkered").tag(DirectionsTiming.arriveBy)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 11, weight: .bold))
                Text(model.timing.title).font(Sketch.text(12, "Bold", relativeTo: .caption)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Sketch.ink).padding(.horizontal, 10).frame(height: 32)
            .background(Capsule().fill(compact ? Sketch.paperDeep.opacity(0.75) : Sketch.card))
        }
    }

    private var dayAndTime: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(0..<7, id: \.self) { offset in
                    Button(dayTitle(offset)) { model.date = moved(model.date, toDayOffset: offset) }
                }
            } label: {
                Label(dayTitle(dayOffset(model.date)), systemImage: "calendar").font(Sketch.text(12, "Bold", relativeTo: .caption))
                    .foregroundStyle(Sketch.ink).padding(.horizontal, 8).frame(height: 32)
            }
            DatePicker("Time", selection: $model.date, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.compact).scaleEffect(0.86, anchor: .trailing).frame(height: 32)
        }
        .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
    }

    /// When, contained in one small box.
    private var timeRow: some View {
        HStack(spacing: 6) {
            timingMenu(compact: false)
            Spacer(minLength: 0)
            if model.timing != .now { dayAndTime }
            if model.loading { ProgressView().controlSize(.small) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.paperDeep.opacity(0.75)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.timing)
    }

    private var timingSummary: String {
        switch model.timing {
        case .now: "Leave now"
        case .departAt: "Leave \(DirectionsFormat.clock(model.date))"
        case .arriveBy: "Arrive \(DirectionsFormat.clock(model.date))"
        }
    }

    private var modeRow: some View {
        HStack(spacing: 6) {
            ForEach(DirectionsTransport.allCases) { mode in
                let on = model.transport == mode
                Button {
                    TrippyHaptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { model.transport = mode }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol).font(.system(size: 13, weight: .bold))
                        Text(model.etas[mode].map { DirectionsFormat.duration($0.expectedTravelTime) } ?? mode.title)
                            .font(Sketch.text(13, "Bold", relativeTo: .footnote)).monospacedDigit().lineLimit(1)
                    }
                    .foregroundStyle(on ? Sketch.paper : Sketch.ink)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if on { Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "mode", in: modes) }
                        else { Capsule().fill(Sketch.paperDeep.opacity(0.75)) }
                    }
                }
                .buttonStyle(BubblePressStyle())
                .accessibilityLabel(mode.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func dayOffset(_ date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0)
    }
    private func dayTitle(_ offset: Int) -> String {
        switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        default: (Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now).formatted(.dateTime.weekday(.abbreviated))
        }
    }
    private func moved(_ date: Date, toDayOffset offset: Int) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? date
    }

    private func endpointRow(_ endpoint: DirectionsEndpoint, start: Bool) -> some View {
        Button { onPick(start) } label: {
            HStack(spacing: 12) {
                Image(systemName: endpoint == .currentLocation ? "location.fill" : start ? "circle.circle" : "mappin.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(endpoint == .currentLocation ? Color.blue : start ? Sketch.inkSoft : Sketch.coral)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(start ? "From" : "To").font(Sketch.text(10, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft)
                    Text(endpoint.title).font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.ink).lineLimit(1)
                }
                Spacer(minLength: 56)
            }
            .padding(.horizontal, 12).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(start ? "From" : "To") \(endpoint.title). Change")
    }
}

// MARK: - Bottom: the routes

struct DirectionsRoutesCard: View {
    @ObservedObject var model: DirectionsModel
    let onAppleMaps: () -> Void
    let onClose: () -> Void
    /// Loads the transit lines for the current ends (the map owns the server address and the location).
    var onTransitLines: () -> Void = {}
    enum Size { case mini, normal, routes }
    /// Starts at its normal size; drag down to a strip, up for the other routes.
    @State private var size: Size = .normal
    @State private var showSteps = false
    @GestureState private var pull: CGFloat = 0

    private var time: TimeInterval? { model.transport == .transit ? model.etas[.transit]?.expectedTravelTime : model.route?.expectedTravelTime }
    private var detail: String {
        if model.transport == .transit, let eta = model.etas[.transit] {
            return "Arrive \(DirectionsFormat.clock(eta.expectedArrivalDate)) · lines in Apple Maps"
        }
        guard let route = model.route else { return model.error ?? (model.loading ? "Finding routes…" : "") }
        let arrival = DirectionsFormat.clock(Date().addingTimeInterval(route.expectedTravelTime))
        return [DirectionsFormat.distance(route.distance), route.name.isEmpty ? nil : "via \(route.name)", model.timing == .now ? "arrive \(arrival)" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Sketch.inkSoft.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 8).padding(.bottom, size == .mini ? 6 : 8)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .onTapGesture { step(size == .mini ? .normal : size == .normal ? .mini : .normal) }
                .accessibilityLabel("Resize route card").accessibilityAddTraits(.isButton)
            if size == .mini {
                HStack(spacing: 10) {
                    Image(systemName: model.transport.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.inkSoft)
                    Text(time.map(DirectionsFormat.duration) ?? "–").font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                    Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                    Spacer(minLength: 4)
                    roundButton("arrow.triangle.turn.up.right.diamond.fill", label: "Go in Apple Maps", filled: true, side: 38, action: onAppleMaps)
                }
                .padding(.horizontal, 18).padding(.bottom, 8)
                .transition(.opacity)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(time.map(DirectionsFormat.duration) ?? "–").font(Sketch.text(26, "ExtraBold", relativeTo: .title2))
                                .monospacedDigit().foregroundStyle(Sketch.ink).lineLimit(1).fixedSize().contentTransition(.numericText())
                            if model.routes.count > 1 {
                                Button { step(size == .routes ? .normal : .routes) } label: {
                                    HStack(spacing: 3) {
                                        Text("\(model.routes.count) routes")
                                        Image(systemName: "chevron.up").rotationEffect(.degrees(size == .routes ? 180 : 0))
                                    }
                                    .font(Sketch.text(11, "Bold", relativeTo: .caption2)).foregroundStyle(Sketch.inkSoft).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(Sketch.paperDeep, in: Capsule())
                                }.buttonStyle(BubblePressStyle())
                            }
                        }
                        Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
                        if let route = model.route, route.transportType == .automobile { tollLine(route) }
                        // What Apple says about the route: a border crossing, a ferry, a seasonal closure.
                        if let route = model.route, model.transport != .transit {
                            ForEach(route.advisoryNotices.prefix(2), id: \.self) { notice in
                                Label(notice, systemImage: "exclamationmark.circle.fill").font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                                    .foregroundStyle(Sketch.ochre).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if model.route != nil {
                        roundButton("list.bullet", label: "Steps", filled: false, side: 50) { showSteps = true }
                    }
                    roundButton("arrow.triangle.turn.up.right.diamond.fill", label: "Go in Apple Maps", filled: true, side: 50, action: onAppleMaps)
                }
                .padding(.horizontal, 18).padding(.bottom, 12)
                .transition(.opacity)
            }
            if model.transport == .transit && size != .mini { transitLines.padding(.horizontal, 18).padding(.bottom, 12).transition(.opacity) }
            if size == .routes && model.routes.count > 1 {
                VStack(spacing: 4) {
                    ForEach(Array(model.routes.enumerated()), id: \.offset) { index, route in
                        Button {
                            TrippyHaptics.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.selected = index; size = .normal }
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(index == model.selected ? Sketch.sage : Sketch.rule).frame(width: 8, height: 8)
                                Text(route.name.isEmpty ? "Route \(index + 1)" : route.name).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                                    .foregroundStyle(Sketch.ink).lineLimit(1)
                                Spacer(minLength: 6)
                                if route.transportType == .automobile && route.hasTolls {
                                    Image(systemName: "eurosign.circle.fill").font(.system(size: 12)).foregroundStyle(Sketch.ochre).accessibilityLabel("Tolls")
                                }
                                Text(DirectionsFormat.distance(route.distance)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).fixedSize()
                                Text(DirectionsFormat.duration(route.expectedTravelTime)).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                                    .monospacedDigit().fixedSize().foregroundStyle(index == model.selected ? Sketch.sage : Sketch.ink)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(index == model.selected ? Sketch.sage.opacity(0.1) : .clear))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        // Attached to the bottom edge (the tab bar is hidden here): top corners round, the material runs under the home indicator.
        .background(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous).fill(.regularMaterial)
            .shadow(color: .black.opacity(0.12), radius: 14, y: -3).ignoresSafeArea(edges: .bottom))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous).inset(by: -60).offset(y: 60))
        .offset(y: max(0, pull) * 0.35)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Sketch.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.regularMaterial))
                    .overlay(Circle().strokeBorder(Sketch.rule.opacity(0.7), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(BubblePressStyle())
            .padding(.trailing, 14).offset(y: -52)
            .accessibilityLabel("Close directions")
        }
        .gesture(DragGesture(minimumDistance: 10)
            .updating($pull) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let dy = value.predictedEndTranslation.height
                if dy < -30 { step(size == .mini ? .normal : (model.routes.count > 1 ? .routes : .normal)) }
                else if dy > 30 { step(size == .routes ? .normal : .mini) }
            })
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: size)
        .animation(.snappy, value: model.selected)
        .onChange(of: model.transport) { _, _ in if size == .routes { size = .normal } }
        .task(id: "\(model.transport.rawValue)|\(model.from.title)|\(model.to.title)") { if model.transport == .transit { onTransitLines() } }
        .task(id: model.route) {
            #if DEBUG
            if model.route != nil, ProcessInfo.processInfo.arguments.contains("-TrippyDirectionsSteps") { try? await Task.sleep(for: .seconds(1)); showSteps = true }
            #endif
        }
        .sheet(isPresented: $showSteps) { if let route = model.route { DirectionsStepsSheet(route: route, toll: DirectionsToll.estimate(route)) } }
    }

    /// Transit: the lines that stop near both ends, so "take the M2 or bus 040" is answered here. Changes and
    /// departure times are Apple's to give, one tap away.
    @ViewBuilder private var transitLines: some View {
        if model.linesLoading {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking up the lines here… a new area can take a minute.") }
                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
        } else if let lines = model.lines, lines.known {
            VStack(alignment: .leading, spacing: 8) {
                Text(lines.direct.isEmpty ? "NO DIRECT LINE" : lines.direct.count == 1 ? "DIRECT LINE" : "DIRECT LINES").font(Sketch.eyebrow).tracking(0.9)
                    .foregroundStyle(lines.direct.isEmpty ? Sketch.ochre : Sketch.sage)
                if lines.direct.isEmpty {
                    Text("\(lines.from.count) \(lines.from.count == 1 ? "line stops" : "lines stop") near the start and \(lines.to.count) near the end, with a change between them. Apple Maps has the connection.")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(lines.direct.prefix(14)) { line in
                                HStack(spacing: 4) {
                                    Image(systemName: line.symbol).font(.system(size: 10, weight: .bold))
                                    Text(line.ref).font(Sketch.text(13, "ExtraBold", relativeTo: .footnote))
                                }
                                .foregroundStyle(.white).padding(.horizontal, 9).frame(minHeight: 28)
                                .background(Capsule().fill(line.color.map { Color(sketchHex: $0) } ?? Sketch.inkSoft))
                                .accessibilityLabel("\(line.modeTitle) \(line.ref)")
                            }
                        }
                    }
                    Text("These stop within a short walk of both ends. Times and platforms are in Apple Maps. Lines © OpenStreetMap contributors.")
                        .font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Tolls ≈ €4.20" (Greece, estimated) or "No tolls", on its own line so nothing else wraps.
    private func tollLine(_ route: MKRoute) -> some View {
        let estimate = DirectionsToll.estimate(route)
        return Label(route.hasTolls ? (estimate.map { "Tolls ≈ \($0) · estimate" } ?? "Tolls on this route") : "No tolls",
                     systemImage: route.hasTolls ? "eurosign.circle.fill" : "checkmark.circle")
            .font(Sketch.text(11, "Bold", relativeTo: .caption2)).lineLimit(1)
            .foregroundStyle(route.hasTolls ? Sketch.ochre : Sketch.sage)
    }

    private func step(_ next: Size) {
        TrippyHaptics.selection()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { size = next }
    }

    private func roundButton(_ symbol: String, label: String, filled: Bool, side: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: side * 0.34, weight: .bold))
                .foregroundStyle(filled ? Sketch.paper : Sketch.ink)
                .frame(width: side, height: side).background(Circle().fill(filled ? Sketch.ink : Sketch.paperDeep))
        }.buttonStyle(BubblePressStyle()).accessibilityLabel(label)
    }
}

/// Free toll estimate for Greek motorways: about 6.5 cents per km on the tolled distance, at least one Attiki Odos
/// passage (€2.80). Apple doesn't say which part of a route is tolled, so this uses the whole driving distance and is
/// labelled as an estimate; only for trips that start and end in Greece.
enum DirectionsToll {
    static func estimate(_ route: MKRoute) -> String? {
        guard route.transportType == .automobile, route.hasTolls else { return nil }
        let points = route.polyline.points()
        let count = route.polyline.pointCount
        guard count > 1, inGreece(points[0].coordinate), inGreece(points[count - 1].coordinate) else { return nil }
        let euros = max(2.8, route.distance / 1000 * 0.065)
        return euros.formatted(.currency(code: "EUR").precision(.fractionLength(euros < 10 ? 2 : 0)))
    }
    private static func inGreece(_ c: CLLocationCoordinate2D) -> Bool {
        // Mainland and islands, trimmed away from Turkey's coast and Albania/North Macedonia/Bulgaria in the north.
        (34.7...41.75).contains(c.latitude) && (19.3...28.3).contains(c.longitude)
            && !(c.latitude > 40.9 && c.longitude > 26.6) && !(c.latitude > 41.0 && c.longitude < 23.0)
    }
}

/// Turn-by-turn steps from Apple Maps for the chosen route.
struct DirectionsStepsSheet: View {
    let route: MKRoute
    let toll: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: route.transportType == .walking ? "figure.walk" : "car.fill").font(.title2.weight(.semibold))
                            .foregroundStyle(Sketch.ink).frame(width: 48, height: 48).background(Sketch.paperDeep, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(DirectionsFormat.duration(route.expectedTravelTime)) · \(DirectionsFormat.distance(route.distance))").font(.headline)
                            Text(route.name.isEmpty ? "Route" : "via \(route.name)").font(.subheadline).foregroundStyle(Sketch.inkSoft)
                            if let toll { Text("Tolls ≈ \(toll) (estimate)").font(.caption).foregroundStyle(Sketch.ochre) }
                        }
                    }.padding(.vertical, 4)
                }
                Section("Steps") {
                    let steps = route.steps.filter { !$0.instructions.isEmpty }
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.caption.weight(.bold)).frame(width: 26, height: 26).background(Sketch.paperDeep, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.instructions).font(.subheadline.weight(.medium))
                                if step.distance > 0 { Text(DirectionsFormat.distance(step.distance)).font(.caption).foregroundStyle(Sketch.inkSoft) }
                            }
                        }.padding(.vertical, 2)
                    }
                    if steps.isEmpty { Text("No step-by-step directions for this route.").foregroundStyle(Sketch.inkSoft) }
                }
            }
            .navigationTitle("Steps").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

// MARK: - Choosing a start or destination

struct DirectionsPlacePicker: View {
    let title: String
    let near: CLLocationCoordinate2D?
    let onPick: (DirectionsEndpoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @StateObject private var completer = DirectionsCompleter()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Button { onPick(.currentLocation); dismiss() } label: {
                    Label("My location", systemImage: "location.fill").foregroundStyle(Color.blue).frame(minHeight: 40)
                }
                if let home = HomeAddress.current {
                    Button { Task { await chooseHome(home) } } label: {
                        Label { VStack(alignment: .leading, spacing: 1) { Text("Home"); Text(home).font(.caption).foregroundStyle(Sketch.inkSoft) } }
                            icon: { Image(systemName: "house.fill").foregroundStyle(Sketch.sage) }
                            .frame(minHeight: 40)
                    }
                }
                ForEach(completer.results, id: \.self) { result in
                    Button { Task { await choose(result) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).foregroundStyle(Sketch.ink)
                            if !result.subtitle.isEmpty { Text(result.subtitle).font(.caption).foregroundStyle(Sketch.inkSoft) }
                        }.frame(minHeight: 40, alignment: .leading)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Apple Maps")
            .onChange(of: query) { _, value in completer.search(value, near: near) }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func chooseHome(_ address: String) async {
        guard let mark = try? await CLGeocoder().geocodeAddressString(address).first, let location = mark.location else { return }
        onPick(.place(name: "Home", coordinate: location.coordinate))
        dismiss()
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else { return }
        onPick(.place(name: item.name ?? completion.title, coordinate: item.placemark.coordinate))
        dismiss()
    }
}

@MainActor
final class DirectionsCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    override init() { super.init(); completer.delegate = self; completer.resultTypes = [.address, .pointOfInterest] }
    func search(_ text: String, near: CLLocationCoordinate2D?) {
        if let near { completer.region = MKCoordinateRegion(center: near, latitudinalMeters: 60_000, longitudinalMeters: 60_000) }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { results = [] } else { completer.queryFragment = text }
    }
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

/// The map tells the app's root that directions are open, so the tab bar steps aside.
struct DirectionsActiveKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The optional home address from setup. Kept only on this phone ("trippy.local." is never uploaded).
enum HomeAddress {
    static let key = "trippy.local.homeAddress"
    static var current: String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
