import SwiftUI

// MARK: - One place, one identity

/// The key every reference to a real venue shares: pins, saves, trip pins, video mentions, notes and takes.
/// Google place IDs win; otherwise a folded "name|city" so a place found twice by name still merges.
enum PlaceKey {
    static func of(googlePlaceID: String?, name: String, city: String?) -> String {
        if let id = googlePlaceID?.trimmingCharacters(in: .whitespaces), !id.isEmpty { return "google:" + id }
        let fold = { (text: String) in
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return "name:" + fold(name) + "|" + fold(city ?? "")
    }
    static func googleID(_ key: String) -> String? { key.hasPrefix("google:") ? String(key.dropFirst(7)) : nil }
}

// MARK: - Your take

/// The one-tap answers about a place. Stored once per place (not per pin, note or video).
struct PlaceTake: Codable, Equatable {
    var been: Bool? = nil
    var gotIn: String? = nil      // PlaceTakeEntry raw value
    var tags: [String] = []       // PlaceTakeTag raw values
    var updatedAt = Date()
    var isEmpty: Bool { been == nil && gotIn == nil && tags.isEmpty }
}

enum PlaceTakeEntry: String, CaseIterable, Identifiable {
    case walkedIn = "walked_in", waited, booked, turnedAway = "turned_away"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walkedIn: "Walked in"
        case .waited: "Queued"
        case .booked: "Booked"
        case .turnedAway: "Didn’t get in"
        }
    }
    var emoji: String {
        switch self {
        case .walkedIn: "🚪"
        case .waited: "⏳"
        case .booked: "📅"
        case .turnedAway: "🙅"
        }
    }
}

enum PlaceTakeTag: String, CaseIterable, Identifiable {
    case overhyped, valueForMoney = "value_for_money", expensive, cheap, modern, traditional, mid, nothingSpecial = "nothing_special"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overhyped: "Overhyped"
        case .valueForMoney: "Value for money"
        case .expensive: "Expensive"
        case .cheap: "Cheap"
        case .modern: "Modern"
        case .traditional: "Traditional"
        case .mid: "Mid"
        case .nothingSpecial: "Nothing special"
        }
    }
    var emoji: String {
        switch self {
        case .overhyped: "🎈"
        case .valueForMoney: "💎"
        case .expensive: "💸"
        case .cheap: "🪙"
        case .modern: "✨"
        case .traditional: "🏺"
        case .mid: "😐"
        case .nothingSpecial: "🥱"
        }
    }
    var tint: Color {
        switch self {
        case .overhyped, .expensive: Sketch.coral
        case .valueForMoney, .cheap: Sketch.sage
        case .modern, .traditional: Sketch.plum
        case .mid, .nothingSpecial: Sketch.ochre
        }
    }
    /// Picking one of a pair clears the other (it can't be both cheap and expensive).
    var opposite: PlaceTakeTag? {
        switch self {
        case .expensive: .cheap
        case .cheap: .expensive
        case .modern: .traditional
        case .traditional: .modern
        default: nil
        }
    }
}

// MARK: - What everyone said

/// Counts from every Trippy user (GET /api/places/takes). Voters stay anonymous.
struct PlaceCommunity: Decodable, Equatable {
    var voters: Int
    var been: Int
    var gotIn: [String: Int]
    var tags: [String: Int]
    var videos: Int
    var tips: [String]
    enum CodingKeys: String, CodingKey { case voters, been, tags, videos, tips; case gotIn = "got_in" }

    var headline: String? {
        var parts: [String] = []
        if videos > 1 { parts.append("in \(videos) videos") }
        if been > 0 { parts.append("\(been) been") }
        let entered = (gotIn["walked_in"] ?? 0) + (gotIn["booked"] ?? 0) + (gotIn["waited"] ?? 0)
        let total = entered + (gotIn["turned_away"] ?? 0)
        if total >= 2 { parts.append("\(Int((Double(entered) / Double(total) * 100).rounded()))% got in") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var topTags: [(PlaceTakeTag, Int)] {
        tags.compactMap { key, count in PlaceTakeTag(rawValue: key).map { ($0, count) } }.sorted { $0.1 > $1.1 }
    }
}

enum PlaceTakesClient {
    private struct Response: Decodable { let places: [String: PlaceCommunity] }

    static func fetch(googleIDs: [String], baseURL: String, token: String) async -> [String: PlaceCommunity] {
        let ids = Array(Set(googleIDs)).prefix(60)
        guard !ids.isEmpty, !token.isEmpty, var components = URLComponents(string: baseURL + "/api/places/takes") else { return [:] }
        components.queryItems = [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]
        guard let url = components.url else { return [:] }
        var request = URLRequest(url: url, timeoutInterval: 12)
        authorize(&request, token: token)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        return (try? JSONDecoder().decode(Response.self, from: data).places) ?? [:]
    }

    static func send(_ take: PlaceTake, googleID: String, baseURL: String, token: String) async -> PlaceCommunity? {
        guard !token.isEmpty, let url = URL(string: baseURL + "/api/places/takes") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        authorize(&request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["place_id": googleID, "tags": take.tags]
        if let been = take.been { body["been"] = been }
        if let gotIn = take.gotIn { body["got_in"] = gotIn }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.places[googleID]
    }

    private static func authorize(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
    }
}

// MARK: - Notes written for you

/// The text a video contributes to a place note or a tips note. One section per video, replaced on re-read.
enum AutoNote {
    static func placeSection(_ place: SocialPlaceMention, source: ImportedSocialSource) -> String {
        var lines: [String] = []
        let who = source.envelope.tiktok?.authorHandle.map { "@" + $0 } ?? "a saved video"
        lines.append("From \(who)" + (source.displayTitle.map { " — \($0)" } ?? ""))
        if let tldr = place.summary.nonEmptyNote { lines.append(tldr) }
        if let moments = place.moments, !moments.isEmpty {
            lines.append("")
            lines += moments.map { "\($0.at.nonEmptyNote.map { "[\($0)] " } ?? "")\($0.text)" }
        }
        func list(_ title: String, _ items: [String]?) {
            guard let items, !items.isEmpty else { return }
            lines.append("")
            lines.append(title)
            lines += items.map { "• " + $0 }
        }
        list("Must try", place.mustTry)
        list("Pro tips", place.proTips)
        list("Good to know", place.goodToKnow)
        if let price = place.priceHint?.nonEmptyNote { lines.append(""); lines.append("Price: " + price) }
        return lines.joined(separator: "\n")
    }

    static func tipsSection(_ source: ImportedSocialSource) -> String {
        let who = source.envelope.tiktok?.authorHandle.map { "@" + $0 } ?? "a saved video"
        var lines = ["From \(who)"]
        if let summary = source.summary?.nonEmptyNote { lines.append(summary) }
        for tip in source.tips ?? [] {
            lines.append("")
            lines.append((tip.at?.nonEmptyNote.map { "[\($0)] " } ?? "") + tip.title)
            if let detail = tip.detail.nonEmptyNote { lines.append(detail) }
        }
        return lines.joined(separator: "\n")
    }

    /// "Dimitri's notes: …" appended to the note without opening it.
    static func appending(_ text: String, to body: String, owner: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return body }
        let entry = "\(owner)'s notes: \(clean)"
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry : body + "\n\n" + entry
    }

    static var ownerName: String {
        let name = UserDefaults.standard.string(forKey: ProfileStore.nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? "My"
    }
}

private extension String {
    var nonEmptyNote: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - The card

/// Everything in one go: been? got in? how was it? plus a line for the note. Every answer is one tap,
/// nothing is required, and answers save as you tap.
struct PlaceQuickTakeCard: View {
    let placeName: String
    @Binding var take: PlaceTake
    var community: PlaceCommunity? = nil
    var subtitle: String? = nil
    var summary: String? = nil
    /// The caption timeline for this place in the video ("0:12 — best carbonara in town").
    var moments: [SocialMoment] = []
    var onAppendNote: ((String) -> Void)? = nil
    var onOpenNote: (() -> Void)? = nil
    var onOpenLink: (() -> Void)? = nil
    @State private var sentPulse = false
    @State private var showAllMoments = false
    @State private var flowOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(placeName).font(Sketch.text(17, "ExtraBold", relativeTo: .headline)).foregroundStyle(Sketch.ink).lineLimit(2)
                    if let subtitle { Text(subtitle).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
                }
                Spacer(minLength: 8)
                if let onOpenLink {
                    Button(action: onOpenLink) {
                        Image(systemName: "map").font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.ink)
                            .frame(width: 34, height: 34).background(Sketch.paperDeep, in: Circle())
                    }.buttonStyle(BubblePressStyle()).accessibilityLabel("Show \(placeName) on the map")
                }
            }

            if let summary {
                Text(summary).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.ink).fixedSize(horizontal: false, vertical: true)
            }
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(moments.prefix(showAllMoments ? moments.count : 3).enumerated()), id: \.offset) { _, moment in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(moment.at).font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit()
                                .foregroundStyle(Sketch.plum).frame(minWidth: 34, alignment: .leading)
                            Text(moment.text).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if moments.count > 3 {
                        Button(showAllMoments ? "Less" : "+\(moments.count - 3) more") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showAllMoments.toggle() }
                        }.font(Sketch.text(12, "Bold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Capsule().fill(Sketch.plum.opacity(0.35)).frame(width: 2) }
            }
            HStack(spacing: 8) {
                Button { flowOpen = true } label: {
                    HStack(spacing: 8) {
                        Text(takeEmoji).font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(take.isEmpty ? "Your take" : "Your take · edit").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                            Text(takeLine).font(Sketch.text(11, relativeTo: .caption2)).lineLimit(1)
                                .foregroundStyle(take.isEmpty ? Color.white.opacity(0.85) : Sketch.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(take.isEmpty ? Color.white : Sketch.ink)
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(take.isEmpty ? Sketch.coral : Sketch.paperDeep))
                    .shadow(color: take.isEmpty ? Sketch.coral.opacity(0.3) : .clear, radius: 8, y: 4)
                }
                .buttonStyle(BubblePressStyle()).accessibilityLabel("Your take on \(placeName)")
                if let onOpenNote {
                    Button(action: onOpenNote) {
                        Label(sentPulse ? "Added" : "Note", systemImage: sentPulse ? "checkmark" : "note.text")
                            .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.ink)
                            .padding(.horizontal, 14).frame(minHeight: 46).background(Sketch.paperDeep, in: Capsule())
                            .contentTransition(.symbolEffect(.replace))
                    }.buttonStyle(BubblePressStyle()).accessibilityLabel("Open the note to edit it")
                }
            }

            if let community, community.voters + community.videos > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if let headline = community.headline {
                        Label(headline, systemImage: "person.3.fill").font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                            .foregroundStyle(Sketch.inkSoft)
                    }
                    ForEach(community.tips.prefix(3), id: \.self) { tip in
                        Text("• " + tip).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.ink)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Sketch.paperDeep.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
        .animation(.spring(response: 0.38, dampingFraction: 0.68), value: take)
        .task { if CommunityDemo.opensTakeFlow { try? await Task.sleep(for: .milliseconds(900)); flowOpen = true } }
        .sheet(isPresented: $flowOpen) {
            PlaceTakeFlow(placeName: placeName, take: $take, community: community,
                          onAppendNote: onAppendNote.map { append in { text in append(text); pulseAdded() } },
                          onOpenNote: onOpenNote.map { open in { flowOpen = false; Task { try? await Task.sleep(for: .milliseconds(450)); open() } } })
                .presentationDetents([.height(470), .large]).presentationCornerRadius(32).presentationDragIndicator(.visible)
        }
    }
    private var takeEmoji: String {
        if take.been == false { return "👀" }
        if take.gotIn == PlaceTakeEntry.turnedAway.rawValue { return "🙅" }
        if let first = take.tags.first.flatMap(PlaceTakeTag.init(rawValue:)) { return first.emoji }
        return take.been == true ? "✅" : "💬"
    }
    private var takeLine: String {
        if take.isEmpty { return "Been? Got in? How was it? — 10 seconds" }
        var parts: [String] = []
        if take.been == false { parts.append("Not yet") }
        if take.been == true { parts.append("Been") }
        if let entry = take.gotIn.flatMap(PlaceTakeEntry.init(rawValue:)) { parts.append(entry.title) }
        parts += take.tags.compactMap(PlaceTakeTag.init(rawValue:)).map(\.title)
        return parts.joined(separator: " · ")
    }
    private func pulseAdded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { sentPulse = true }
        Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { sentPulse = false } }
    }

}

// MARK: - One question at a time

/// Been? → Got in? → How was it? → Anything to add? Each answer moves on by itself.
/// "Not yet" and "Didn't get in" end it there: nothing more to ask.
struct PlaceTakeFlow: View {
    let placeName: String
    @Binding var take: PlaceTake
    var community: PlaceCommunity? = nil
    var onAppendNote: ((String) -> Void)? = nil
    var onOpenNote: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .been
    @State private var forward = true
    @State private var draft = ""
    @FocusState private var typing: Bool

    enum Step: Int, CaseIterable { case been, gotIn, vibe, note, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(visibleSteps, id: \.self) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Sketch.coral : Sketch.rule)
                        .frame(width: item == step ? 26 : 8, height: 8)
                }
                Spacer()
                if step != .done && step != .been {
                    Button("Back") { go(Step(rawValue: step.rawValue - 1) ?? .been, forward: false) }
                        .font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            Text(placeName).font(Sketch.text(13, "Bold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(1)
            ZStack(alignment: .topLeading) {
                page.id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Sketch.paper.ignoresSafeArea())
        .clipped()
        .onAppear { step = .been }
    }

    private var visibleSteps: [Step] {
        if take.been == false { return [.been] }
        if take.gotIn == PlaceTakeEntry.turnedAway.rawValue { return [.been, .gotIn] }
        return onAppendNote == nil ? [.been, .gotIn, .vibe] : [.been, .gotIn, .vibe, .note]
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .been:
            question("Have you been?", hint: community.flatMap { $0.been > 0 ? "\($0.been) travellers have" : nil }) {
                big("Been", emoji: "✅", on: take.been == true, tint: Sketch.sage) {
                    take.been = true; touch(); go(.gotIn)
                }
                big("Not yet", emoji: "👀", on: take.been == false, tint: Sketch.inkSoft) {
                    take.been = false; take.gotIn = nil; take.tags = []; touch(); go(.done)
                }
            }
        case .gotIn:
            question("Did you get in?", hint: community?.headline) {
                ForEach(PlaceTakeEntry.allCases) { entry in
                    big(entry.title, emoji: entry.emoji, on: take.gotIn == entry.rawValue, tint: entry == .turnedAway ? Sketch.coral : Sketch.sage) {
                        take.gotIn = entry.rawValue
                        if entry == .turnedAway { take.tags = [] }
                        touch(); go(entry == .turnedAway ? .done : .vibe)
                    }
                }
            }
        case .vibe:
            VStack(alignment: .leading, spacing: 16) {
                question("How was it?", hint: "Pick all that fit") {
                    ForEach(PlaceTakeTag.allCases) { tag in
                        TakeBubble(title: tag.title, emoji: tag.emoji, on: take.tags.contains(tag.rawValue), tint: tag.tint,
                                   count: community?.tags[tag.rawValue]) { toggle(tag) }
                    }
                }
                primary(take.tags.isEmpty ? "Skip" : "Next") { go(onAppendNote == nil ? .done : .note) }
            }
        case .note:
            VStack(alignment: .leading, spacing: 14) {
                Text("Anything to remember?").font(Sketch.text(26, "ExtraBold", relativeTo: .title)).foregroundStyle(Sketch.ink)
                Text("Goes into the place’s note as “\(AutoNote.ownerName)'s notes”.").font(Sketch.text(13, relativeTo: .footnote))
                    .foregroundStyle(Sketch.inkSoft)
                TextField("Order the burnt leek, sit outside…", text: $draft, axis: .vertical)
                    .font(Sketch.text(16, relativeTo: .body)).lineLimit(2...5).focused($typing)
                    .padding(14).background(Sketch.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
                HStack(spacing: 10) {
                    primary(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Done" : "Add & finish") {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { onAppendNote?(text); draft = "" }
                        typing = false; go(.done)
                    }
                    if let onOpenNote {
                        Button(action: onOpenNote) {
                            Label("Open note", systemImage: "note.text").font(Sketch.text(15, "Bold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                                .padding(.horizontal, 16).frame(minHeight: 50).background(Sketch.paperDeep, in: Capsule())
                        }.buttonStyle(BubblePressStyle())
                    }
                }
            }
        case .done:
            VStack(spacing: 14) {
                Text(take.been == false ? "👀" : take.gotIn == PlaceTakeEntry.turnedAway.rawValue ? "🫶" : "🎉").font(.system(size: 56))
                    .keyframeAnimator(initialValue: 0.4, trigger: step) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
                        SpringKeyframe(1.2, duration: 0.25, spring: .bouncy); SpringKeyframe(1.0, duration: 0.25)
                    }
                Text(take.been == false ? "Saved for later" : take.gotIn == PlaceTakeEntry.turnedAway.rawValue ? "Noted — that helps others plan" : "Thanks! That’s your take")
                    .font(Sketch.text(20, "ExtraBold", relativeTo: .title3)).foregroundStyle(Sketch.ink).multilineTextAlignment(.center)
                Text("Shared anonymously with the community and used to plan trips.").font(Sketch.text(13, relativeTo: .footnote))
                    .foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.center)
                primary("Close") { dismiss() }
            }
            .frame(maxWidth: .infinity)
            .task { TrippyHaptics.success() }
        }
    }

    private func question<Content: View>(_ title: String, hint: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Sketch.text(26, "ExtraBold", relativeTo: .title)).foregroundStyle(Sketch.ink)
            if let hint { Text(hint).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
            BubbleFlow(spacing: 10) { content() }
        }
    }

    private func big(_ title: String, emoji: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        TakeBubble(title: title, emoji: emoji, on: on, tint: tint, count: nil, large: true, action: action)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(16, "Bold", relativeTo: .body)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50).background(Sketch.ink, in: Capsule())
        }.buttonStyle(BubblePressStyle())
    }

    private func go(_ next: Step, forward: Bool = true) {
        self.forward = forward
        Task { @MainActor in
            if forward { try? await Task.sleep(for: .milliseconds(260)) } // let the tapped bubble pop first
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { step = next }
        }
    }
    private func touch() { take.updatedAt = .now }
    private func toggle(_ tag: PlaceTakeTag) {
        if let index = take.tags.firstIndex(of: tag.rawValue) { take.tags.remove(at: index) }
        else {
            take.tags.append(tag.rawValue)
            if let opposite = tag.opposite { take.tags.removeAll { $0 == opposite.rawValue } }
        }
        touch()
    }
}

private struct TakeBubble: View {
    let title: String
    let emoji: String
    let on: Bool
    let tint: Color
    let count: Int?
    var large = false
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            TrippyHaptics.selection()
            action()
            taps += 1
        } label: {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: large ? 22 : 14)).scaleEffect(on ? 1.18 : 1).rotationEffect(.degrees(on ? -8 : 0))
                Text(title).font(Sketch.text(large ? 17 : 13, on ? "Bold" : "SemiBold", relativeTo: .footnote))
                if let count, count > 0 {
                    Text("\(count)").font(Sketch.text(11, "Bold", relativeTo: .caption2)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((on ? Color.white : tint).opacity(on ? 0.25 : 0.14), in: Capsule())
                }
            }
            .foregroundStyle(on ? Color.white : Sketch.ink)
            .padding(.horizontal, large ? 18 : 12).frame(minHeight: large ? 56 : 36)
            .background(Capsule().fill(on ? tint : Sketch.paperDeep))
            .overlay(Capsule().strokeBorder(on ? Color.clear : tint.opacity(0.28), lineWidth: 1))
            .shadow(color: on ? tint.opacity(0.35) : .clear, radius: 6, y: 3)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: taps) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
            SpringKeyframe(0.84, duration: 0.08)
            SpringKeyframe(1.1, duration: 0.16, spring: .bouncy)
            SpringKeyframe(1.0, duration: 0.2)
        }
        .buttonStyle(BubblePressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: on)
    }
}

struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Left-aligned wrapping row for bubbles.
struct BubbleFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
