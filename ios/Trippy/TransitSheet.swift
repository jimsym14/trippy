import CoreLocation
import MapKit
import SwiftUI

// MARK: - Getting around a city
//
// The metro, tram and funicular lines of a city drawn on the map in their own colours, and the one ticket worth
// buying for this trip. Lines come from OpenStreetMap through our server (fetched once per city, then kept);
// prices are copied from the operator's own page and shown with the day they were checked.

struct TransitAnswer: Decodable {
    struct Line: Decodable, Identifiable {
        let id: String; let mode: String; let modeTitle: String; let ref: String; let name: String
        let color: String?; let km: Double; let paths: [[[Double]]]; let stops: [[Double]]
        enum CodingKeys: String, CodingKey { case id, mode, ref, name, color, km, paths, stops; case modeTitle = "mode_title" }
        var tint: Color { color.map { Color(sketchHex: $0) } ?? Sketch.sky }
    }
    struct Ticket: Decodable, Identifiable { let id: String; let name: String; let price: Double; let kind: String; let note: String? }
    struct Tickets: Decodable {
        let city: String; let currency: String; let `operator`: String; let source: String; let checked: String
        let covers: String?; let payByCard: String?; let note: String?; let stale: Bool; let tickets: [Ticket]
        /// Who the reduced fare is for, when the operator's page lists reduced prices.
        let reducedFor: String?
        enum CodingKeys: String, CodingKey { case city, currency, `operator`, source, checked, covers, note, stale, tickets; case payByCard = "pay_by_card"; case reducedFor = "reduced_for" }
    }
    struct Option: Decodable, Identifiable {
        let label: String; let perPerson: Double; let total: Double; let airportExtra: Double; let note: String?
        let best: Bool?; let saves: Double?
        var id: String { label }
        enum CodingKeys: String, CodingKey { case label, total, note, best, saves; case perPerson = "per_person"; case airportExtra = "airport_extra" }
    }
    struct Advice: Decodable { let days: Int; let rides: Int; let travelers: Int; let airport: Bool; let options: [Option] }
    let city: String
    let lines: [Line]
    let attribution: String
    let tickets: Tickets?
    let advice: Advice?
}

struct TransitRequest: Identifiable {
    let city: String
    var coordinate: CLLocationCoordinate2D?
    var days = 3
    var travelers = 1
    var id: String { city }
}

enum TransitClient {
    static func load(_ request: TransitRequest, coordinate: CLLocationCoordinate2D, rides: Int, airport: Bool, reduced: Bool = false, baseURL: String, token: String) async throws -> TransitAnswer {
        var components = URLComponents(string: baseURL + "/api/transit")
        components?.queryItems = [("city", request.city), ("lat", String(format: "%.4f", coordinate.latitude)), ("lng", String(format: "%.4f", coordinate.longitude)),
                                  ("days", "\(request.days)"), ("rides", "\(rides)"), ("travelers", "\(request.travelers)"), ("airport", airport ? "1" : "0"), ("fare", reduced ? "reduced" : "full")]
            .map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components?.url, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        // The first look at a city draws its lines from OpenStreetMap, which can take a minute; later looks are instant.
        var call = URLRequest(url: url, timeoutInterval: 120)
        call.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        call.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { call.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        let (data, response) = try await URLSession.shared.data(for: call)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TransitAnswer.self, from: data)
    }
}

/// Screenshot checks: `-TrippyTransitDemoFile <path to a saved /api/transit reply>` shows that reply without a server.
enum TransitDemo {
    static var answer: TransitAnswer? {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "TrippyTransitDemoFile"), let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(TransitAnswer.self, from: data)
        #else
        return nil
        #endif
    }
}

struct TransitSheet: View {
    let request: TransitRequest
    let baseURL: String
    let token: String
    var preview: TransitAnswer? = nil

    @State private var answer: TransitAnswer?
    @State private var failed = false
    @State private var loading = true
    @State private var rides = 4
    @State private var airport = false
    @State private var reduced = false
    @State private var focus: String?
    @State private var camera = MapCameraPosition.automatic
    @State private var drawn = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [TransitAnswer.Line] { (answer?.lines ?? []).filter { focus == nil || $0.id == focus } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GETTING AROUND").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                        Text(request.city.split(separator: ",").first.map(String.init) ?? request.city).font(Sketch.display(.largeTitle, weight: .bold))
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 44).raisedCircle() }
                        .buttonStyle(SketchPressStyle()).accessibilityLabel("Close")
                }
                map
                if let answer {
                    if answer.lines.isEmpty { note("No metro or tram lines found here. Buses and walking do the work in this city.") } else { lineKey(answer.lines) }
                    if let tickets = answer.tickets, let advice = answer.advice { ticketAdvice(tickets, advice) }
                    else { note("We haven't checked ticket prices for this city yet, so none are shown rather than guessed.") }
                    if !answer.attribution.isEmpty {
                        Text("Lines \(answer.attribution)").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
                    }
                } else if failed {
                    note("Couldn't load this city's transport. Check the connection and try again.")
                    Button("Try again") { Task { await load() } }.font(Sketch.text(15, "Bold", relativeTo: .body)).frame(minHeight: 44)
                } else {
                    HStack(spacing: 10) { ProgressView(); Text("Drawing the lines… the first look at a city can take a minute.") }
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                }
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 30)
        }
        .background(PaperBackground()).foregroundStyle(Sketch.ink).tint(Sketch.clay)
        .task { await load() }
        .onChange(of: rides) { _, _ in Task { await load(quiet: true) } }
        .onChange(of: airport) { _, _ in Task { await load(quiet: true) } }
        .onChange(of: reduced) { _, _ in Task { await load(quiet: true) } }
        .sensoryFeedback(.selection, trigger: focus)
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(shown) { line in
                ForEach(Array(line.paths.enumerated()), id: \.offset) { _, path in
                    MapPolyline(coordinates: path.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil })
                        .stroke(line.tint, style: StrokeStyle(lineWidth: focus == nil ? 4 : 6, lineCap: .round, lineJoin: .round))
                }
                if focus != nil {
                    ForEach(Array(line.stops.enumerated()), id: \.offset) { _, stop in
                        if stop.count == 2 {
                            Annotation("", coordinate: .init(latitude: stop[0], longitude: stop[1]), anchor: .center) {
                                Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().strokeBorder(line.tint, lineWidth: 2.5))
                            }
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .opacity(drawn || reduceMotion ? 1 : 0.4).animation(.easeOut(duration: 0.6), value: drawn)
        .accessibilityLabel("Map of \(shown.count) transit lines")
    }

    // MARK: Lines

    private func lineKey(_ lines: [TransitAnswer.Line]) -> some View {
        let modes = Dictionary(grouping: lines, by: \.modeTitle)
        let order = lines.map(\.modeTitle).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(order, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 8) {
                    StudioHeading(title: mode, count: modes[mode]?.count)
                    BubbleFlow(spacing: 8) {
                        ForEach(modes[mode] ?? []) { line in
                            let on = focus == line.id
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { focus = on ? nil : line.id; camera = .automatic }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(line.ref).font(Sketch.text(14, "ExtraBold", relativeTo: .subheadline)).foregroundStyle(.white)
                                        .padding(.horizontal, 9).frame(minWidth: 34, minHeight: 28).background(Capsule().fill(line.tint))
                                    if on { Text("\(line.stops.count) stops · \(Int(line.km.rounded())) km").font(Sketch.text(12, "SemiBold", relativeTo: .caption)).transition(.opacity) }
                                }
                                .padding(.horizontal, 6).frame(minHeight: 44)
                                .background(Capsule().fill(on ? line.tint.opacity(0.16) : Sketch.paperDeep))
                            }
                            .buttonStyle(SketchPressStyle()).accessibilityLabel("\(mode) \(line.ref), \(line.stops.count) stops").accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            Text(focus == nil ? "Tap a line to see it alone, with its stops." : "Tap it again to see every line.")
                .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
        }
    }

    // MARK: Tickets

    private func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(2)).locale(Locale(identifier: "en_IE")))
    }

    private func ticketAdvice(_ tickets: TransitAnswer.Tickets, _ advice: TransitAnswer.Advice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The ticket to buy").font(Sketch.display(.title2, weight: .bold))
            VStack(spacing: 0) {
                Stepper(value: $rides, in: 1...10) {
                    Text("\(rides) \(rides == 1 ? "ride" : "rides") a day").font(Sketch.text(15, "SemiBold", relativeTo: .body)).contentTransition(.numericText())
                }.frame(minHeight: 50)
                if tickets.tickets.contains(where: { $0.kind.hasPrefix("airport") }) {
                    Divider()
                    Toggle("Airport, there and back", isOn: $airport).font(Sketch.text(15, "SemiBold", relativeTo: .body)).frame(minHeight: 50)
                }
                if let who = tickets.reducedFor {
                    Divider()
                    Toggle(isOn: $reduced) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reduced fare").font(Sketch.text(15, "SemiBold", relativeTo: .body))
                            Text(who).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
            if let best = advice.options.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("BEST FOR \(advice.days) \(advice.days == 1 ? "DAY" : "DAYS")").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.sage)
                        Spacer()
                        if let saves = best.saves, saves >= 0.5 { SketchTag(text: "Saves \(money(saves, tickets.currency)) each", tint: Sketch.sage, symbol: "arrow.down") }
                    }
                    Text(best.label).font(Sketch.display(.title3, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(money(best.perPerson, tickets.currency)).font(Sketch.text(26, "ExtraBold", relativeTo: .title)).monospacedDigit().contentTransition(.numericText())
                        Text(advice.travelers > 1 ? "each · \(money(best.total, tickets.currency)) for \(advice.travelers)" : "per person")
                            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                    }
                    if best.airportExtra > 0 { Label("Includes \(money(best.airportExtra, tickets.currency)) for the airport both ways", systemImage: "airplane").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
                    if let note = best.note { Text(note).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.sage.opacity(0.5), lineWidth: 1.2))
                .animation(.snappy, value: best.label)
            }
            if advice.options.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(advice.options.dropFirst().enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline) {
                            Text(option.label).font(Sketch.text(14, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(money(option.perPerson, tickets.currency)).font(Sketch.text(14, "Bold", relativeTo: .subheadline)).monospacedDigit()
                        }.frame(minHeight: 46)
                    }
                }
                .padding(.horizontal, 14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
            }
            VStack(alignment: .leading, spacing: 6) {
                if let covers = tickets.covers { Label(covers, systemImage: "checkmark.circle") }
                if let card = tickets.payByCard { Label(card, systemImage: "creditcard") }
                if let note = tickets.note { Label(note, systemImage: "info.circle") }
            }
            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            if let link = URL(string: tickets.source) {
                Link(destination: link) {
                    Label("Prices from \(tickets.operator), checked \(tickets.checked)" + (tickets.stale ? " · may have changed" : ""), systemImage: "arrow.up.right")
                        .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(tickets.stale ? Sketch.ochre : Sketch.inkFaint)
                        .frame(minHeight: 44, alignment: .leading).multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
    }

    private func load(quiet: Bool = false) async {
        if let preview { answer = preview; loading = false; drawn = true; return }
        if !quiet { failed = false; loading = true }
        var coordinate = request.coordinate
        if coordinate == nil { coordinate = try? await CLGeocoder().geocodeAddressString(request.city).first?.location?.coordinate }
        guard let coordinate else { failed = answer == nil; loading = false; return }
        do {
            let fresh = try await TransitClient.load(request, coordinate: coordinate, rides: rides, airport: airport, reduced: reduced, baseURL: baseURL, token: token)
            withAnimation(reduceMotion ? nil : .snappy) { answer = fresh }
            drawn = true
        } catch { failed = answer == nil }
        loading = false
    }
}
