import CoreLocation
import MapKit
import SwiftUI

// MARK: - The plan screen's smaller pieces
//
// What makes a plan read like one a friend wrote: why each stop is there and where it came from, honest free
// time, how to get between two stops, and a day out when the trip has room for one. Nothing here calls a model.

// MARK: Where a stop came from

/// "You saved this", "In 3 videos", "Well known": the reason this stop is in *your* plan, at a glance.
struct StopSources: View {
    let place: GuidePlace
    var body: some View {
        let items: [(String, String, Color)] = [
            place.personal ? ("heart.fill", "You saved this", Sketch.coral) : nil,
            place.videoCount > 1 ? ("play.fill", "In \(place.videoCount) videos", Sketch.plum)
                : place.videoCount == 1 || place.fromVideo ? ("play.fill", "From a video", Sketch.plum) : nil,
            place.fromWikivoyage ? ("book.closed.fill", "In the travel guide", Sketch.sky) : nil,
            place.fame >= 10 ? ("star.fill", "Well known", Sketch.ochre) : nil,
            place.reservationRequired == true ? ("ticket.fill", "Book ahead", Sketch.clay) : nil,
        ].compactMap { $0 }
        if !items.isEmpty {
            BubbleFlow(spacing: 5) {
                ForEach(items.prefix(3), id: \.1) { symbol, text, tint in SketchTag(text: text, tint: tint, symbol: symbol) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Free time

/// A gap of an hour or more is shown for what it is, with one easy thing to do with it.
struct FreeTimeRow: View {
    let minutes: Int
    let color: Color
    let idea: GuidePlace?
    var onAdd: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DottedTrail().stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1, 5])).frame(width: 58, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Label("\(DirectionsFormat.duration(TimeInterval(minutes * 60))) free", systemImage: "hourglass")
                    .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                if let idea, let onAdd {
                    Button(action: onAdd) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("Add \(idea.name)").font(Sketch.text(13, "Bold", relativeTo: .footnote)).lineLimit(1)
                            if !idea.reason.isEmpty { Text(idea.reason).font(Sketch.text(12, relativeTo: .caption)).opacity(0.7).lineLimit(1) }
                        }
                        .foregroundStyle(color).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Capsule().fill(color.opacity(0.1)))
                    }
                    .buttonStyle(SketchPressStyle())
                } else {
                    Text("Room to wander, rest or sit somewhere.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Getting between two stops

/// Links for trips we hold no timetable for: a cross-border train, a coach, a ferry. Each opens a service that does.
enum LongDistanceLinks {
    struct Item: Identifiable { let id: String; let title: String; let detail: String; let symbol: String; let url: URL }
    static func items(from: String, to: String, fromCoordinate: CLLocationCoordinate2D?, toCoordinate: CLLocationCoordinate2D?) -> [Item] {
        var out: [Item] = []
        func path(_ text: String) -> String {
            (text.split(separator: ",").first.map(String.init) ?? text).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        }
        if let url = URL(string: "https://www.rome2rio.com/map/\(path(from))/\(path(to))") {
            out.append(Item(id: "rome2rio", title: "Compare train, bus, ferry and flight", detail: "Rome2Rio: every way to make this trip, with operators", symbol: "arrow.triangle.branch", url: url))
        }
        if let a = fromCoordinate, let b = toCoordinate,
           let url = URL(string: "https://maps.apple.com/?saddr=\(a.latitude),\(a.longitude)&daddr=\(b.latitude),\(b.longitude)&dirflg=r") {
            out.append(Item(id: "apple", title: "Public transport in Apple Maps", detail: "Departures and changes, where Apple has them", symbol: "tram.fill", url: url))
        }
        return out
    }
}

/// The dotted line between two stops. Past twenty minutes it opens the lines that make the hop.
struct TravelLegRow: View {
    let minutes: Int
    let color: Color
    let from: GuidePlace
    let to: GuidePlace
    let input: GuideInput
    @State private var open = false
    var body: some View {
        let long = minutes >= 20 && from.coordinate != nil && to.coordinate != nil
        HStack(spacing: 10) {
            DottedTrail().stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1, 5])).frame(width: 58, height: long ? 44 : 26)
            if long {
                Button { open = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tram.fill").font(.system(size: 11, weight: .bold))
                        Text("~\(minutes) min · see the lines").font(Sketch.text(12, "Bold", relativeTo: .caption))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(color).padding(.horizontal, 12).frame(minHeight: 44).background(Capsule().fill(color.opacity(0.1)))
                }
                .buttonStyle(SketchPressStyle()).accessibilityLabel("About \(minutes) minutes to \(to.name). Show the lines.")
            } else {
                Text("~\(minutes) min walk").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
                    .accessibilityLabel("About \(minutes) minutes on foot to the next stop")
            }
        }
        .sheet(isPresented: $open) {
            TravelLegSheet(from: from, to: to, minutes: minutes, input: input)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        }
    }
}

struct TravelLegSheet: View {
    let from: GuidePlace
    let to: GuidePlace
    let minutes: Int
    let input: GuideInput
    @State private var lines: TransitBetween?
    @State private var loading = true
    @State private var showTickets = false

    private var km: Double {
        guard let a = from.coordinate, let b = to.coordinate else { return 0 }
        return Geo.km(a, b)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GETTING THERE").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                    Text("\(from.name) → \(to.name)").font(Sketch.display(.title2, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("About \(minutes) min · \(km >= 1 ? String(format: "%.1f km", km) : "\(Int(km * 1000)) m") apart")
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                }
                if loading {
                    HStack(spacing: 10) { ProgressView(); Text("Looking up the lines… a new part of town can take a minute.") }
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                } else if let lines, lines.known, !lines.direct.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lines.direct.count == 1 ? "ONE LINE GOES STRAIGHT THERE" : "THESE GO STRAIGHT THERE").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.sage)
                        BubbleFlow(spacing: 6) {
                            ForEach(lines.direct.prefix(16)) { line in
                                HStack(spacing: 5) {
                                    Image(systemName: line.symbol).font(.system(size: 11, weight: .bold))
                                    Text(line.ref).font(Sketch.text(14, "ExtraBold", relativeTo: .subheadline))
                                }
                                .foregroundStyle(.white).padding(.horizontal, 10).frame(minHeight: 32)
                                .background(Capsule().fill(line.color.map { Color(sketchHex: $0) } ?? Sketch.inkSoft))
                                .accessibilityLabel("\(line.modeTitle) \(line.ref)")
                            }
                        }
                        Text("They stop within a short walk of both places. Lines © OpenStreetMap contributors.")
                            .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                } else if let lines, lines.known {
                    Text("No single line links these two. \(lines.from.count) stop near \(from.name) and \(lines.to.count) near \(to.name), with a change between them.")
                        .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Couldn't look up the lines right now.").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                }
                VStack(spacing: 0) {
                    Button { showTickets = true } label: { row("Which ticket to buy", "Prices for this trip's days and travellers", "ticket.fill") }
                        .buttonStyle(SketchPressStyle())
                    ForEach(LongDistanceLinks.items(from: km > 60 ? from.name : "", to: to.name, fromCoordinate: from.coordinate, toCoordinate: to.coordinate)
                        .filter { km > 60 || $0.id == "apple" }) { item in
                        Divider()
                        Link(destination: item.url) { row(item.title, item.detail, item.symbol) }
                    }
                }
                .padding(.horizontal, 14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
            }
            .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 24)
        }
        .background(PaperBackground()).foregroundStyle(Sketch.ink).tint(Sketch.clay)
        .task { await load() }
        .sheet(isPresented: $showTickets) {
            TransitSheet(request: TransitRequest(city: input.destination, coordinate: from.coordinate,
                                                 days: max(1, (GuideDates.daysBetween(input.startDate, input.endDate) ?? 0) + 1), travelers: max(1, input.travelers)),
                         baseURL: input.bridgeURL, token: input.bridgeToken)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sketch.clay).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(Sketch.ink).multilineTextAlignment(.leading)
                Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.inkFaint)
        }
        .frame(minHeight: 58).contentShape(Rectangle())
    }

    private func load() async {
        defer { loading = false }
        guard let a = from.coordinate, let b = to.coordinate, !input.bridgeToken.isEmpty,
              var components = URLComponents(string: input.bridgeURL + "/api/transit/between") else { return }
        components.queryItems = [URLQueryItem(name: "from", value: String(format: "%.4f,%.4f", a.latitude, a.longitude)),
                                 URLQueryItem(name: "to", value: String(format: "%.4f,%.4f", b.latitude, b.longitude))]
        guard let url = components.url else { return }
        var request = URLRequest(url: url, timeoutInterval: 150)
        request.setValue("Bearer \(input.bridgeToken)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        lines = try? JSONDecoder().decode(TransitBetween.self, from: data)
    }
}

// MARK: A day out

/// A nearby town or city worth a day, offered only when the trip has a day to spare for it.
struct DayTripIdea: Identifiable {
    let destination: Destination
    let leg: JourneyLeg
    let reasons: [String]
    var id: String { destination.id }
}

enum DayTripPlanner {
    /// The rule, in order: the city itself must leave a spare day (a big city wants four days, a town two);
    /// the place must be reachable overland in two hours each way (two and a half on a week or longer), so the
    /// day isn't spent travelling; among those, the ones that fit the traveller's taste and the month come first,
    /// and two near each other are never both offered.
    static func ideas(city: String, days: Int, month: Int?, taste: TasteProfile, limit: Int = 2) -> [DayTripIdea] {
        guard let home = DestinationCatalog.named(city) else { return [] }
        let needed = [2, 3, 4][home.size - 1]
        guard days - needed >= 1 else { return [] }
        let reach = days >= 7 ? 150 : 120
        let origin = JourneyPoint(home)
        var scored: [(DayTripIdea, Double)] = []
        for d in DestinationCatalog.all where d.id != home.id && d.access != "a" {
            let km = Geo.km(home.coordinate, d.coordinate)
            guard km > 25, km < 330 else { continue }
            let train = JourneyEngine.leg(from: origin, to: JourneyPoint(d), mode: .train)
            let car = JourneyEngine.leg(from: origin, to: JourneyPoint(d), mode: .car)
            let leg = train.mode == .train && train.minutes <= car.minutes + 20 ? train : car
            guard leg.mode != .plane, leg.minutes <= reach else { continue }
            let season = month.map { d.months.contains($0) ? 1.0 : 0.4 } ?? 0.8
            // A day out should be a change: what this place has that the base city has less of.
            let contrast = zip(d.traits, home.traits).map { max(0, Double($0 - $1)) }.reduce(0, +) / 9
            let score = 0.45 * Double(taste.match(d)) + 0.25 * season + 0.2 * min(1, contrast) + 0.1 * (1 - Double(leg.minutes) / Double(reach))
            var reasons = ["\(leg.duration) \(leg.mode.verb) each way"]
            let different = TripTrait.allCases.filter { d.trait($0) >= 2 && d.trait($0) > home.trait($0) }.sorted { d.trait($0) > d.trait($1) }.prefix(2).map(\.short)
            if !different.isEmpty { reasons.append("More " + different.joined(separator: " and ") + " than \(home.name)") }
            if let month, let weather = d.weatherLine(month, wanted: nil) { reasons.append(weather) }
            if d.countryCode != home.countryCode { reasons.append("Another country: \(d.country)") }
            scored.append((DayTripIdea(destination: d, leg: leg, reasons: reasons), score))
        }
        var out: [DayTripIdea] = []
        for (idea, _) in scored.sorted(by: { $0.1 > $1.1 }) where out.count < limit {
            if out.contains(where: { Geo.km($0.destination.coordinate, idea.destination.coordinate) < 60 }) { continue }
            out.append(idea)
        }
        return out
    }
}

struct DayTripSection: View {
    let ctx: GuideContext
    var body: some View {
        let month = ctx.days.first.flatMap { Int($0.date.dropFirst(5).prefix(2)) }
        let ideas = DayTripPlanner.ideas(city: ctx.input.destination, days: ctx.days.count, month: month, taste: TasteProfile.load())
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SketchHeading(title: "A day out?", icon: .map, tint: Sketch.sky)
                Text("Your \(ctx.days.count) days leave room for one. Close enough to be back for dinner.")
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(idea.destination.flag) \(idea.destination.name)").font(Sketch.display(.title3, weight: .bold))
                            Spacer(minLength: 6)
                            Label(idea.leg.duration, systemImage: idea.leg.mode.symbol).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.sky)
                        }
                        ForEach(idea.reasons, id: \.self) { reason in
                            Label { Text(reason) } icon: { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.sage) }
                                .font(Sketch.text(14, relativeTo: .subheadline))
                        }
                        HStack(spacing: 14) {
                            ForEach(LongDistanceLinks.items(from: ctx.input.destination, to: idea.destination.planName, fromCoordinate: ctx.base?.coordinate, toCoordinate: idea.destination.coordinate)) { link in
                                Link(destination: link.url) {
                                    Label(link.id == "apple" ? "Apple Maps" : "Ways to get there", systemImage: link.symbol)
                                        .font(Sketch.text(13, "Bold", relativeTo: .footnote)).frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    .sketchCard(padding: 16)
                    .atlasRise(index)
                }
                Text("Travel times are estimates; check the timetable before you go.").font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint)
            }
        }
    }
}
