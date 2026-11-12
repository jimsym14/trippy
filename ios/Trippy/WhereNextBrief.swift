import SwiftUI

// MARK: - The brief: the real questions first
//
// "Where next?" starts by asking what the trip is: who it is for, when it could happen, what it should feel
// like. Each answer decides which question is worth asking next (snow is only asked about when the dates
// could have any). The answers become a `WhereNextQuery`; nothing here calls a network or a model.

enum TripRegion: String, Codable, CaseIterable, Identifiable {
    case near, europe, far, anywhere
    var id: String { rawValue }
    var title: String {
        switch self { case .near: "Close to home"; case .europe: "In Europe"; case .far: "Far away"; case .anywhere: "Anywhere" }
    }
    var detail: String {
        switch self {
        case .near: "Five hours door to door at most"; case .europe: "Any country in Europe"
        case .far: "Another continent"; case .anywhere: "Wherever fits best"
        }
    }
    var symbol: String { switch self { case .near: "house"; case .europe: "globe.europe.africa"; case .far: "airplane.departure"; case .anywhere: "globe" } }
}

enum TripSetting: String, Codable, CaseIterable, Identifiable {
    case city, countryside, coast, mountains
    var id: String { rawValue }
    var title: String {
        switch self { case .city: "A city"; case .countryside: "Villages & countryside"; case .coast: "Coast & islands"; case .mountains: "Mountains" }
    }
    var symbol: String { switch self { case .city: "building.2"; case .countryside: "leaf"; case .coast: "beach.umbrella"; case .mountains: "mountain.2" } }
}

enum TripClimate: String, Codable, CaseIterable, Identifiable {
    case snow, sun, mild
    var id: String { rawValue }
    var title: String { switch self { case .snow: "Snow"; case .sun: "Warm sun"; case .mild: "Mild & fresh" } }
    var symbol: String { switch self { case .snow: "snowflake"; case .sun: "sun.max"; case .mild: "cloud.sun" } }
}

// MARK: - What the catalog knows about weather and setting

extension Destination {
    /// Places with lifts and pistes in their winter.
    var skiArea: Bool {
        ["Chamonix", "Innsbruck", "Zermatt", "Lucerne & Alps", "Cortina & Dolomites", "Zakopane & Tatras", "Salzburg", "Rovaniemi & Lapland",
         "Vancouver & Rockies", "Takayama & Japanese Alps", "Queenstown & South Island"].contains(name)
    }
    func climate(_ month: Int) -> MonthClimate? {
        guard (1...12).contains(month) else { return nil }
        return DestinationClimate.table[id]?[month - 1]
    }
    func snowLikely(_ month: Int) -> Bool {
        guard let c = climate(month) else { return false }
        return c.snow >= 10 || (skiArea && c.high <= 8)
    }
    /// 0…1: how well a month there matches the weather asked for. With nothing asked, every month is equal.
    func climateFit(_ wanted: TripClimate?, month: Int) -> Double {
        guard let wanted else { return 0.5 }
        guard let c = climate(month) else { return 0.6 }
        switch wanted {
        case .snow:
            if snowLikely(month) && skiArea { return 1 }
            return c.snow >= 20 ? 1 : c.snow >= 8 ? 0.75 : c.high <= 3 ? 0.6 : c.high <= 8 ? 0.3 : 0.05
        case .sun:
            let dry = c.wetDays <= 12
            return c.high >= 26 ? (dry ? 1 : 0.75) : c.high >= 22 ? 0.85 : c.high >= 18 ? 0.5 : c.high >= 14 ? 0.25 : 0.05
        case .mild:
            return (16...25).contains(c.high) ? 1 : (12...28).contains(c.high) ? 0.6 : 0.2
        }
    }
    /// "About 24° by day in February": typical weather from the bundled averages, never a forecast.
    func weatherLine(_ month: Int, wanted: TripClimate?) -> String? {
        guard let c = climate(month) else { return nil }
        let name = TripMonth.names[month - 1]
        // Mountain towns sit well below the slopes the averages are measured on, so no temperature is claimed for them.
        if snowLikely(month) { return skiArea ? "Snow likely in \(name)" : "Snow likely in \(name), about \(c.high)° by day" }
        return "About \(c.high)° by day in \(name)" + (c.wetDays >= 18 ? ", often wet" : "")
    }
    /// 0…1: how much of this kind of place it is.
    func settingFit(_ setting: TripSetting) -> Double {
        switch setting {
        case .city: return [0.2, 0.8, 1][size - 1]
        case .countryside: return min(1, Double(trait(.quiet) + trait(.nature)) / 6 * [1, 0.7, 0.3][size - 1] + 0.1)
        case .coast: return Double(trait(.beach)) / 3
        case .mountains: return skiArea ? 1 : min(1, Double(trait(.nature) + trait(.adventure)) / 6) * (trait(.beach) >= 2 ? 0.5 : 1)
        }
    }
}

// MARK: - Answers

struct WhereNextBrief: Codable, Equatable {
    enum Who: String, Codable, CaseIterable, Identifiable {
        case solo, couple, friends, family
        var id: String { rawValue }
        var title: String { switch self { case .solo: "Just me"; case .couple: "A trip for two"; case .friends: "Friends"; case .family: "Family" } }
        var symbol: String { switch self { case .solo: "person"; case .couple: "heart"; case .friends: "person.3"; case .family: "figure.2.and.child.holdinghands" } }
        var travelers: Int { switch self { case .solo: 1; case .couple: 2; case .friends: 4; case .family: 4 } }
    }
    enum When: String, Codable { case anytime, months, dates }

    var who: Who?
    var when = When.anytime
    var months: Set<Int> = []
    /// "After the 15th": a start with no end means the eight weeks that follow.
    var from: Date?
    var to: Date?
    var days = 5
    var climate: TripClimate?
    var ski = false
    var setting: TripSetting?
    var wants: Set<Int> = []          // TripTrait raw values
    var region = TripRegion.anywhere
    var somethingNew: Bool?
    var budget: Int?
    var mode: JourneyMode?
    var finished = false

    private static let key = "trippy.wherenext.brief.v1"
    static func load() -> WhereNextBrief {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(WhereNextBrief.self, from: $0) } ?? WhereNextBrief()
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) } }

    /// Every month the trip could fall in. Empty means any time.
    var window: Set<Int> {
        switch when {
        case .anytime: return []
        case .months: return months
        case .dates:
            guard let from else { return [] }
            let calendar = Calendar.current
            let end = to ?? calendar.date(byAdding: .day, value: 56, to: from) ?? from
            var out: Set<Int> = [], day = from
            while day.timeIntervalSince(end) <= 0, out.count < 12 {
                out.insert(calendar.component(.month, from: day))
                day = calendar.date(byAdding: .day, value: 14, to: day) ?? end.addingTimeInterval(1)
            }
            out.insert(calendar.component(.month, from: end))
            return out
        }
    }
    /// Could these dates have snow or real heat somewhere? Decides whether the weather question is worth asking.
    var couldBeWinter: Bool { window.isEmpty || !window.isDisjoint(with: [11, 12, 1, 2, 3]) }

    var whenText: String {
        switch when {
        case .anytime: return "Any time"
        case .months:
            let sorted = months.sorted()
            return sorted.isEmpty ? "Any time" : sorted.count <= 3 ? sorted.map { TripMonth.short[$0 - 1] }.joined(separator: ", ") : "\(sorted.count) months"
        case .dates:
            guard let from else { return "Any time" }
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB"))
            return to.map { "\(from.formatted(style)) – \($0.formatted(style))" } ?? "After \(from.formatted(style))"
        }
    }

    /// The answers as the engine's query. Where the traveller leaves from stays as it was.
    func apply(to query: inout WhereNextQuery) {
        let window = window
        query.months = window
        query.month = window.count == 1 ? window.first : nil
        query.days = days
        if let who { query.travelers = who.travelers }
        var wants = Set(self.wants.compactMap(TripTrait.init(rawValue:)))
        switch who { case .couple: wants.insert(.romance); case .family: wants.insert(.family); default: break }
        query.wants = wants
        query.region = region
        query.setting = setting
        query.climate = climate
        query.ski = ski && climate == .snow
        query.newPlacesOnly = somethingNew == true
        query.noveltyCounts = somethingNew == true
        query.budget = budget
        query.mode = mode
    }
}

// MARK: - The questions

enum BriefStep: Int, CaseIterable {
    case who, when, length, weather, ski, setting, mood, region, novelty, extras
    var title: String {
        switch self {
        case .who: "Who is it for?"; case .when: "When could it be?"; case .length: "For how long?"
        case .weather: "What weather?"; case .ski: "Skiing?"; case .setting: "What kind of place?"
        case .mood: "What should it be about?"; case .region: "How far?"; case .novelty: "Somewhere new?"; case .extras: "Anything else?"
        }
    }
    var hint: String {
        switch self {
        case .who: "It changes what a good place is."
        case .when: "Stay loose if you like: a place is judged by its best month in your window."
        case .length: "Roughly is fine."
        case .weather: "From typical weather for your dates, not a forecast."
        case .ski: "Only places with lifts and pistes."
        case .setting: "Pick one, or skip for a mix."
        case .mood: "Pick as many as you like."
        case .region: "You can change this any time."
        case .novelty: "If not, the countries you've been to stop mattering."
        case .extras: "Both are optional."
        }
    }
}

struct WhereNextBriefView: View {
    @Binding var brief: WhereNextBrief
    var onDone: () -> Void
    @State private var step: BriefStep

    /// `start` opens one question directly (tapping an answer on the Where next page).
    init(brief: Binding<WhereNextBrief>, start: BriefStep? = nil, onDone: @escaping () -> Void) {
        _brief = brief; self.onDone = onDone
        var first = start ?? .who
        #if DEBUG
        // Screenshot checks: `-TrippyWhereNextBriefStep 3` opens that question.
        if start == nil, let saved = BriefStep(rawValue: UserDefaults.standard.integer(forKey: "TrippyWhereNextBriefStep")) { first = saved }
        #endif
        _step = State(initialValue: first)
    }
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only the questions that matter for the answers so far.
    private var steps: [BriefStep] {
        BriefStep.allCases.filter { step in
            switch step {
            case .weather: brief.couldBeWinter || !brief.window.isDisjoint(with: [5, 6, 7, 8, 9])
            case .ski: brief.climate == .snow
            default: true
            }
        }
    }
    private var position: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(position + 1) of \(steps.count)").font(Sketch.text(13, "Bold", relativeTo: .footnote)).monospacedDigit()
                    .foregroundStyle(Sketch.inkSoft).contentTransition(.numericText())
                Spacer(minLength: 8)
                Button(brief.finished ? "Done" : "Skip") { finish() }
                    .font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(brief.finished ? Sketch.clay : Sketch.inkSoft)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint(brief.finished ? "Keeps your answers and shows the places" : "Skips the questions and shows places")
            }
            .padding(.horizontal, 22).padding(.top, 12)
            HStack(spacing: 5) {
                ForEach(steps, id: \.self) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Sketch.clay : Sketch.rule).frame(height: 4)
                }
            }
            .animation(.snappy, value: step).padding(.horizontal, 22).padding(.top, 4)
            .accessibilityElement().accessibilityLabel("Question \(position + 1) of \(steps.count)")
            VerticalPage {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title).font(Sketch.display(.largeTitle, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text(step.hint).font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) { question }
                }
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                                                                  removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 12) {
                if position > 0 {
                    Button { go(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).frame(width: 54, height: 54).raisedCircle()
                    }.buttonStyle(SketchPressStyle()).accessibilityLabel("Back")
                }
                SketchPrimaryButton(title: position == steps.count - 1 ? "Show me places" : "Next",
                                    symbol: position == steps.count - 1 ? "sparkles" : nil, enabled: answered) { go(1) }
                    .animation(.snappy, value: answered)
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16)
        }
        .background(PaperBackground()).foregroundStyle(Sketch.ink).tint(Sketch.clay)
        .sensoryFeedback(.selection, trigger: step)
    }

    private func go(_ by: Int) {
        let next = position + by
        guard steps.indices.contains(next) else { finish(); return }
        forward = by > 0
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { step = steps[next] }
    }
    private func finish() { brief.finished = true; brief.save(); onDone() }

    /// Tapping an answer only selects it; Next moves on, so a wrong tap is easy to fix.
    private func choose(_ change: () -> Void) {
        withAnimation(.snappy) { change() }
    }
    /// Questions without a sensible default wait for an answer before Next works.
    private var answered: Bool {
        switch step {
        case .who: brief.who != nil
        case .novelty: brief.somethingNew != nil
        case .when: brief.when != .months || !brief.months.isEmpty
        default: true
        }
    }

    @ViewBuilder private var question: some View {
        switch step {
        case .who:
            ForEach(WhereNextBrief.Who.allCases) { who in
                row(who.title, symbol: who.symbol, on: brief.who == who) { choose { brief.who = who } }
            }
        case .when:
            Picker("When", selection: $brief.when) {
                Text("Any time").tag(WhereNextBrief.When.anytime); Text("Some months").tag(WhereNextBrief.When.months); Text("Dates").tag(WhereNextBrief.When.dates)
            }.pickerStyle(.segmented)
            switch brief.when {
            case .anytime:
                note("We'll look at every month and tell you when each place is at its best.")
            case .months:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        let on = brief.months.contains(month)
                        Button { withAnimation(.snappy) { if on { brief.months.remove(month) } else { brief.months.insert(month) } } } label: {
                            Text(TripMonth.short[month - 1]).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                                .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(on ? Sketch.paper : Sketch.ink)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Sketch.ink : Sketch.paperDeep))
                        }.buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            case .dates:
                VStack(spacing: 0) {
                    DatePicker("Not before", selection: Binding(get: { brief.from ?? .now }, set: { brief.from = $0; if let to = brief.to, to < $0 { brief.to = nil } }),
                               in: Date.now..., displayedComponents: .date).frame(minHeight: 52)
                    Divider()
                    Toggle("Back by a date", isOn: Binding(get: { brief.to != nil }, set: { on in
                        brief.to = on ? Calendar.current.date(byAdding: .day, value: 21, to: brief.from ?? .now) : nil
                    })).frame(minHeight: 52)
                    if brief.to != nil {
                        Divider()
                        DatePicker("Back by", selection: Binding(get: { brief.to ?? .now }, set: { brief.to = $0 }), in: (brief.from ?? .now)..., displayedComponents: .date)
                            .frame(minHeight: 52)
                    }
                }
                .font(Sketch.text(15, "SemiBold", relativeTo: .body)).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
                .onAppear { if brief.from == nil { brief.from = .now } }
                note(brief.to == nil ? "With no end date we look at the eight weeks after it." : "Any trip that fits between these dates.")
            }
        case .length:
            ForEach([(3, "A weekend"), (5, "4–5 days"), (7, "A week"), (10, "About 10 days"), (14, "Two weeks")], id: \.0) { days, title in
                row(title, symbol: "calendar", on: brief.days == days) { choose { brief.days = days } }
            }
            Stepper(value: $brief.days, in: 2...30) { Text("Exactly \(brief.days) days").font(Sketch.text(15, "SemiBold", relativeTo: .body)) }
                .padding(.horizontal, 14).frame(minHeight: 52).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
        case .weather:
            ForEach(TripClimate.allCases.filter { $0 != .snow || brief.couldBeWinter }) { climate in
                row(climate.title, symbol: climate.symbol, on: brief.climate == climate) { choose { brief.climate = climate } }
            }
            row("Don't mind", symbol: "circle.dashed", on: brief.climate == nil) { choose { brief.climate = nil } }
        case .ski:
            row("Yes, skiing", symbol: "figure.skiing.downhill", on: brief.ski) { choose { brief.ski = true } }
            row("Just the snow", symbol: "snowflake", on: !brief.ski) { choose { brief.ski = false } }
        case .setting:
            ForEach(TripSetting.allCases) { setting in
                row(setting.title, symbol: setting.symbol, on: brief.setting == setting) { choose { brief.setting = setting } }
            }
            row("A mix", symbol: "square.grid.2x2", on: brief.setting == nil) { choose { brief.setting = nil } }
        case .mood:
            let offered: [TripTrait] = {
                switch brief.who {
                case .couple: [.romance, .food, .culture, .quiet, .nature, .nightlife, .adventure, .shopping]
                case .family: [.family, .nature, .beach, .culture, .food, .adventure]
                case .friends: [.nightlife, .food, .adventure, .beach, .culture, .nature, .shopping]
                default: [.culture, .food, .nature, .adventure, .nightlife, .quiet, .beach, .shopping]
                }
            }()
            BubbleFlow(spacing: 8) {
                ForEach(offered) { trait in
                    let on = brief.wants.contains(trait.rawValue)
                    Button { withAnimation(.snappy) { if on { brief.wants.remove(trait.rawValue) } else { brief.wants.insert(trait.rawValue) } } } label: {
                        Label(trait.title, systemImage: trait.symbol).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                            .padding(.horizontal, 14).frame(minHeight: 46).foregroundStyle(on ? Sketch.paper : Sketch.ink)
                            .background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
                    }.buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        case .region:
            ForEach(TripRegion.allCases) { region in
                row(region.title, detail: region.detail, symbol: region.symbol, on: brief.region == region) { choose { brief.region = region } }
            }
        case .novelty:
            row("Yes, somewhere I haven't been", symbol: "sparkles", on: brief.somethingNew == true) { choose { brief.somethingNew = true } }
            row("I don't mind", symbol: "circle.dashed", on: brief.somethingNew == false) { choose { brief.somethingNew = false } }
        case .extras:
            VStack(alignment: .leading, spacing: 10) {
                Text("BUDGET PER PERSON, PER DAY").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                BubbleFlow(spacing: 8) {
                    ForEach([Int?.none, 60, 100, 150, 220], id: \.self) { budget in
                        pill(budget.map { "≤ €\($0)" } ?? "Any", on: brief.budget == budget) { brief.budget = budget }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("GETTING THERE").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                BubbleFlow(spacing: 8) {
                    pill("Any way", on: brief.mode == nil) { brief.mode = nil }
                    ForEach(JourneyMode.allCases) { mode in pill(mode.title, on: brief.mode == mode) { brief.mode = mode } }
                }
            }
            .padding(.top, 8)
            note("Once you pick a place you can turn it into a rail or road journey with stops.")
        }
    }

    private func row(_ title: String, detail: String? = nil, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(on ? Sketch.paper : Sketch.clay)
                    .frame(width: 40, height: 40).background(Circle().fill(on ? Sketch.paper.opacity(0.16) : Sketch.clay.opacity(0.12)))
                    .symbolEffect(.bounce, value: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Sketch.text(16, "Bold", relativeTo: .body)).lineLimit(2).multilineTextAlignment(.leading)
                    if let detail { Text(detail).font(Sketch.text(13, relativeTo: .footnote)).opacity(0.75).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 4)
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).transition(.scale.combined(with: .opacity)) }
            }
            .foregroundStyle(on ? Sketch.paper : Sketch.ink)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(on ? Sketch.ink : Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Sketch.rule.opacity(on ? 0 : 0.8), lineWidth: 0.7))
        }
        .buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).lineLimit(1).fixedSize().padding(.horizontal, 16).frame(minHeight: 46)
                .foregroundStyle(on ? Sketch.paper : Sketch.ink).background(Capsule().fill(on ? Sketch.ink : Sketch.paperDeep))
        }.buttonStyle(SketchPressStyle()).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func note(_ text: String) -> some View {
        Text(text).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - "I have somewhere in mind"

/// How an idea of the traveller's own holds up against their answers, with better-fitting places nearby.
struct IdeaVerdict: Identifiable {
    enum Level { case good, fair, poor }
    let destination: Destination
    /// 0…100, on the same scale as the picks.
    let percent: Int
    let level: Level
    let reasons: [String]
    let problems: [String]
    /// When it is the second idea: how it combines with the first.
    let link: String?
    let alternatives: [Recommendation]
    var id: String { destination.id }
}

extension WhereNextEngine {
    /// Scores one place the traveller named, says what works and what doesn't, and offers places that fit better.
    /// `after` is the idea before it, so "Prague, then Warsaw" is judged as a pair.
    static func assess(_ idea: Destination, after previous: Destination?, query: WhereNextQuery, taste: TasteProfile, visits: [VisitedPlace]) -> IdeaVerdict {
        // Its score with only the soft preferences, so a hard "no" below still shows how close it is.
        var relaxed = query
        relaxed.region = .anywhere; relaxed.ski = false; relaxed.newPlacesOnly = false; relaxed.mode = nil
        let softClimate = relaxed.climate; relaxed.climate = nil
        let scored = recommend(relaxed, taste: taste, visits: visits, limit: 1, only: idea).first
        var percent = scored?.percent ?? 30
        var problems: [String] = []
        let home = WorldContinentCatalog.name(for: query.origin?.countryCode ?? "GR")
        if query.region == .europe && idea.continent != "Europe" { problems.append("It isn't in Europe") }
        if query.region == .far && idea.continent == home { problems.append("It isn't far away: same continent as home") }
        if query.ski && !idea.skiArea { problems.append("No ski area there") }
        if query.newPlacesOnly && visits.contains(where: { Geo.km($0.coordinate, idea.coordinate) < 40 }) { problems.append("You've been there, and you asked for somewhere new") }
        if let climate = softClimate {
            let months = query.window.isEmpty ? Set(1...12) : query.window
            let best = months.map { idea.climateFit(climate, month: $0) }.max() ?? 0.6
            if best < 0.5 { problems.append(climate == .snow ? "Little or no snow there on your dates" : "\(climate.title) is unlikely there on your dates") }
            percent = Int(Double(percent) * (0.6 + 0.4 * best))
        }
        if let setting = query.setting, idea.settingFit(setting) < 0.4 { problems.append("Not really \(setting.title.lowercased()), which you asked for") }
        if scored == nil, let origin = query.origin, Geo.km(origin.coordinate, idea.coordinate) >= 60 {
            problems.append("The journey is long for \(query.days) days")
        }
        if let caution = scored?.caution { problems.append(caution) }
        percent = max(5, percent - 12 * problems.filter { !$0.hasPrefix("Not its best") && !$0.hasPrefix("Around") }.count)

        // As a pair: is the hop between them worth it, and do both fit in the days?
        var link: String?
        if let previous {
            let leg = bestLeg(from: JourneyPoint(previous), to: idea, mode: query.mode, travelers: query.travelers)
            // The least each place deserves, plus the time lost moving between them.
            let needed = [2.0, 3, 4][previous.size - 1] + [2.0, 3, 4][idea.size - 1] + Double(leg.minutes) / 600
            link = "\(leg.duration) \(leg.mode.verb) from \(previous.name)"
            if leg.minutes > 420 { problems.append("A long hop from \(previous.name): \(leg.duration) \(leg.mode.verb)"); percent -= 12 }
            if needed > Double(query.days) + 1.5 { problems.append("The two need about \(Int(needed.rounded())) days; you have \(query.days)"); percent -= 10 }
        }
        percent = min(99, max(5, percent))

        // Better fits: around the first idea when this is a second stop, otherwise anywhere.
        var pool = recommend(query, taste: taste, visits: visits, limit: 12).filter { $0.id != idea.id && $0.id != previous?.id && $0.percent > percent }
        if let previous {
            pool = DestinationCatalog.all.filter { d in
                d.id != idea.id && d.id != previous.id && bestLeg(from: JourneyPoint(previous), to: d, mode: query.mode, travelers: query.travelers).minutes <= 270
            }.compactMap { recommend(query, taste: taste, visits: visits, limit: 1, only: $0).first }.filter { $0.percent > percent }.sorted { $0.score > $1.score }
        }
        let level: IdeaVerdict.Level = percent >= 70 && problems.isEmpty ? .good : percent >= 52 ? .fair : .poor
        return IdeaVerdict(destination: idea, percent: percent, level: level, reasons: scored?.reasons ?? [], problems: problems, link: link,
                           alternatives: Array(pool.prefix(3)))
    }
}

struct IdeaCheckSection: View {
    let query: WhereNextQuery
    let taste: TasteProfile
    let visits: [VisitedPlace]
    var onPick: (Recommendation) -> Void
    @State private var text = ""
    @State private var ideas: [Destination] = []
    @FocusState private var typing: Bool

    private var matches: [Destination] {
        let key = text.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard key.count >= 2 else { return [] }
        return DestinationCatalog.all.filter { d in
            !ideas.contains(d) && (d.name + " " + d.country).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(key)
        }.prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Have somewhere in mind?").font(Sketch.display(.title3))
                Text("Add a place, or two to combine. We'll say how it fits what you asked for.")
                    .font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sketch.inkFaint)
                TextField(ideas.isEmpty ? "Prague, Lofoten, Kyoto…" : "Add a second stop", text: $text).focused($typing).submitLabel(.done)
                    .autocorrectionDisabled().font(Sketch.text(16, relativeTo: .body))
                    .onSubmit { if let first = matches.first { add(first) } }
            }
            .padding(.horizontal, 14).frame(minHeight: 50).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Sketch.rule.opacity(0.8), lineWidth: 0.7))
            .opacity(ideas.count >= 2 ? 0.4 : 1).disabled(ideas.count >= 2)
            if !matches.isEmpty {
                BubbleFlow(spacing: 8) {
                    ForEach(matches) { d in
                        Button { add(d) } label: {
                            Text("\(d.flag) \(d.name)").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).padding(.horizontal, 14).frame(minHeight: 44)
                                .background(Capsule().fill(Sketch.paperDeep))
                        }.buttonStyle(SketchPressStyle())
                    }
                }
            } else if text.count >= 3 {
                Text("Not in our list of places yet. Try a nearby city or region.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            }
            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                IdeaCard(verdict: WhereNextEngine.assess(idea, after: index > 0 ? ideas[index - 1] : nil, query: query, taste: taste, visits: visits),
                         onRemove: { withAnimation(.snappy) { ideas.removeAll { $0 == idea } } }, onPick: onPick)
                    .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.horizontal, 20)
        #if DEBUG
        .onAppear {
            // Screenshot checks: `-TrippyWhereNextIdeas "Prague,Warsaw"`.
            if let names = UserDefaults.standard.string(forKey: "TrippyWhereNextIdeas") { ideas = names.split(separator: ",").compactMap { DestinationCatalog.named(String($0)) } }
        }
        #endif
    }
    private func add(_ d: Destination) {
        TrippyHaptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ideas.append(d) }
        text = ""; typing = false
    }
}

private struct IdeaCard: View {
    let verdict: IdeaVerdict
    var onRemove: () -> Void
    var onPick: (Recommendation) -> Void
    private var tint: Color { switch verdict.level { case .good: Sketch.sage; case .fair: Sketch.ochre; case .poor: Sketch.coral } }
    private var headline: String {
        switch verdict.level { case .good: "A good fit"; case .fair: "Could work"; case .poor: "Not a great fit" }
    }
    var body: some View {
        let d = verdict.destination
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.uppercased()).font(Sketch.eyebrow).tracking(0.9).foregroundStyle(tint)
                    Text("\(d.flag) \(d.name)").font(Sketch.display(.title3, weight: .bold))
                    if let link = verdict.link { Label(link, systemImage: "arrow.triangle.swap").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
                }
                Spacer(minLength: 4)
                Text("\(verdict.percent)").font(Sketch.text(20, "ExtraBold", relativeTo: .title3)).monospacedDigit().foregroundStyle(tint)
                    .frame(width: 52, height: 52).background(Circle().fill(tint.opacity(0.14))).contentTransition(.numericText())
                    .accessibilityLabel("\(verdict.percent) percent match")
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.inkSoft).frame(width: 44, height: 44) }
                    .accessibilityLabel("Remove \(d.name)")
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(verdict.reasons.prefix(3), id: \.self) { reason in
                    Label { Text(reason) } icon: { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Sketch.sage) }
                }
                ForEach(verdict.problems, id: \.self) { problem in
                    Label { Text(problem) } icon: { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Sketch.ochre) }
                }
            }
            .font(Sketch.text(14, relativeTo: .subheadline))
            if !verdict.alternatives.isEmpty {
                Divider()
                Text(verdict.link == nil ? "FITS BETTER" : "BETTER WITH IT").font(Sketch.eyebrow).tracking(0.9).foregroundStyle(Sketch.inkFaint)
                BubbleFlow(spacing: 8) {
                    ForEach(verdict.alternatives) { pick in
                        Button { onPick(pick) } label: {
                            HStack(spacing: 6) {
                                Text("\(pick.destination.flag) \(pick.destination.name)").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                                Text("\(pick.percent)").font(Sketch.text(12, "Bold", relativeTo: .caption)).monospacedDigit().foregroundStyle(Sketch.sage)
                            }
                            .padding(.horizontal, 13).frame(minHeight: 44).background(Capsule().fill(Sketch.paperDeep))
                        }.buttonStyle(SketchPressStyle()).accessibilityLabel("\(pick.destination.name), \(pick.percent) percent match")
                    }
                }
            }
        }
        .sketchCard(padding: 16)
    }
}
