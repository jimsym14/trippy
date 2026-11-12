import SwiftUI
import MapKit

/// The trip plan as one editable page: facts, days, map, bookings, calculators
/// and a checklist. Unknown prices and hours stay visibly unknown.
struct TripGuideView: View {
    let input: GuideInput
    var onClose: () -> Void
    var onOpenDetails: (() -> Void)? = nil
    var onEditBrief: (() -> Void)? = nil
    var onShowMap: (() -> Void)? = nil

    @State private var model = GuideModel()
    @State private var edits = GuideEdits()
    @State private var holidays: [GuideHoliday] = []
    @State private var holidayState = "Loading holidays…"
    @State private var editingDays = false
    @State private var showCustomize = false
    @State private var showFacts = false
    @State private var loaded = false
    @State private var undo: GuideEdits?
    @State private var undoTask: Task<Void, Never>?
    @State private var scrolledID: Block?
    @State private var mode: GuideMode = {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "TrippyGuideMode"), let saved = GuideMode(rawValue: name) { return saved }
        #endif
        return .plan
    }()
    @State private var scrollAnchor: UnitPoint = .top
    /// The mode picker has scrolled away: the chapters bar takes its place at the top.
    @State private var showChapters = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ctx: GuideContext { GuideContext(model: model, edits: edits, input: input, holidays: holidays) }
    private var tint: Color { Sketch.pigment(edits.pigment) }

    /// What changed in "Flights and stay" since the plan was made (the plan used the brief and its base).
    private var planInputsChanged: [String]? {
        guard loaded else { return nil }
        func same(_ a: String, _ b: String) -> Bool {
            a.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
                == b.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        }
        var out: [String] = []
        let usedStay = input.plannedStay.nilIfEmpty ?? model.base?.name ?? ""
        if !edits.flight.stayName.isEmpty, !same(edits.flight.stayName, usedStay) { out.append("stay: \(edits.flight.stayName)") }
        if !edits.flight.arrivalTime.isEmpty, !same(edits.flight.arrivalTime, input.plannedArrival) { out.append("arrival \(edits.flight.arrivalTime)") }
        if !edits.flight.departureTime.isEmpty, !same(edits.flight.departureTime, input.plannedDeparture) { out.append("leaving \(edits.flight.departureTime)") }
        return out.isEmpty ? nil : out
    }

    enum Block: Hashable { case section(GuideSection), daysHeading, day(String) }

    var body: some View {
        NavigationStack {
            ScrollView {
                let ctx = self.ctx
                VStack(alignment: .leading, spacing: 36) {
                    GuideHeader(ctx: ctx, tint: tint, flight: $edits.flight, showFacts: $showFacts)
                    if let changed = planInputsChanged, let onEditBrief {
                        PlanOutdatedBanner(changes: changed, tint: tint, onUpdate: onEditBrief)
                    }
                    GuideModePicker(mode: $mode, tint: tint,
                                    mustSeeLeft: MustSeeView.items(ctx).filter { !edits.checklistDone.contains("seen|" + $0.id) }.count)
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .named("guidePage")).maxY < 0 } action: { gone in
                            if gone != showChapters { withAnimation(reduceMotion ? nil : .snappy) { showChapters = gone } }
                        }
                    switch mode {
                    case .map: GuideMapMode(ctx: ctx).transition(.opacity)
                    case .mustSee:
                        MustSeeView(ctx: ctx, edits: $edits, onAdd: { placeID, date in append(placeID, to: date, ctx: ctx) },
                                    onShowDay: { date in withAnimation(reduceMotion ? nil : .smooth) { mode = .plan }
                                        Task { try? await Task.sleep(for: .milliseconds(250)); scrolledID = .day(date) } })
                            .transition(.opacity)
                    case .plan:
                    ForEach(blocks(ctx), id: \.self) { block in
                        switch block {
                        case .section(let section): sectionView(section, ctx: ctx)
                        case .daysHeading:
                            VStack(alignment: .leading, spacing: 10) {
                                SketchHeading(title: GuideSection.days.title, icon: .clock, tint: tint)
                                if editingDays {
                                    Text("Reorder, retime or swap stops. Your edits stay when the plan refreshes.")
                                        .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft)
                                }
                                CommunityTipsBlock(tips: ctx.model.tripWideTips, tint: tint)
                                DidntFitSection(items: ctx.didntFit, notes: ctx.model.videoNotes) { placeID, date in append(placeID, to: date, ctx: ctx) }
                            }
                        case .day(let date):
                            if let day = ctx.days.first(where: { $0.date == date }) {
                                DayView(day: day, ctx: ctx, edits: $edits, editing: editingDays, beforeRemove: rememberForUndo)
                                if day.date == ctx.days.last?.date {
                                    DayTripSection(ctx: ctx)
                                    LeftOutSection(items: ctx.leftOut) { placeID, date in append(placeID, to: date, ctx: ctx) }
                                }
                            }
                        }
                    }
                    }
                    Text("Times and prices are suggestions from sources. Anything marked “Check” is unconfirmed.")
                        .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkFaint).padding(.bottom, 48)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20).padding(.top, 4)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
                // The page is exactly as wide as the screen: no child can widen it
                // and make it drift sideways while scrolling.
                .containerRelativeFrame(.horizontal)
                .clipped()
            }
            .coordinateSpace(name: "guidePage")
            .overlay(alignment: .top) {
                if showChapters && mode == .plan {
                    ChaptersBar(chapters: chapters(ctx), current: currentChapter, tint: tint) { block in
                        scrollAnchor = .top
                        withAnimation(reduceMotion ? nil : .smooth) { scrolledID = block }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollPosition(id: $scrolledID, anchor: scrollAnchor)
            .scrollDismissesKeyboard(.interactively)
            .animation(reduceMotion ? nil : .snappy, value: mode)
            .overlay(alignment: .bottom) { undoBar }
            .keyboardDismissButton()
            .animation(reduceMotion ? nil : .snappy, value: undo != nil)
            .background(PaperBackground())
            .toolbar { toolbar }
            .toolbarBackground(Sketch.paper, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCustomize) { GuideCustomizeSheet(edits: $edits) }
            .sheet(isPresented: $showFacts) { GuideFactsSheet(edits: $edits, input: input) }
            #if DEBUG
            .task { if UserDefaults.standard.bool(forKey: "TrippyGuideFacts") { try? await Task.sleep(for: .seconds(1)); showFacts = true } }
            .task {
                // `-TrippyGuideDay 1 [-TrippyGuideEdit YES]` scrolls to a day for screenshots.
                if let name = UserDefaults.standard.string(forKey: "TrippyGuideSection"), let section = GuideSection(rawValue: name) {
                    try? await Task.sleep(for: .seconds(1.5)); scrolledID = section == .days ? .daysHeading : .section(section); return
                }
                let n = UserDefaults.standard.integer(forKey: "TrippyGuideDay")
                guard n > 0 else { return }
                try? await Task.sleep(for: .seconds(1.5))
                editingDays = UserDefaults.standard.bool(forKey: "TrippyGuideEdit")
                if UserDefaults.standard.bool(forKey: "TrippyGuideBottom") { scrollAnchor = .bottom }
                if model.days.indices.contains(n - 1) { scrolledID = .day(model.days[n - 1].date) }
            }
            #endif
        }
        .tint(tint)
        .foregroundStyle(Sketch.ink)
        .task {
            guard !loaded else { return }
            loaded = true
            model = GuideModel(json: input.research)
            edits = GuideEditsStore.load(input.tripID, travelers: input.travelers)
            // Trips made before the composer saved them: show what the plan was made with.
            if edits.flight.arrivalTime.isEmpty { edits.flight.arrivalTime = input.plannedArrival }
            if edits.flight.departureTime.isEmpty { edits.flight.departureTime = input.plannedDeparture }
            if edits.flight.stayName.isEmpty, let base = model.base {
                edits.flight.stayName = input.plannedStay.nilIfEmpty ?? base.name
                edits.flight.stayLatitude = base.latitude; edits.flight.stayLongitude = base.longitude
            }
            #if DEBUG
            // `-TrippyGuideDemoBook "<date>|<placeID>|HH:MM"`: book a stop at that time (day re-flow checks; use a demo trip).
            if let book = UserDefaults.standard.string(forKey: "TrippyGuideDemoBook")?.split(separator: "|").map(String.init), book.count == 3 {
                edits.booked.insert(book[1]); edits.times["\(book[0])|\(book[1])"] = book[2]
            }
            if let leave = UserDefaults.standard.string(forKey: "TrippyGuideDemoLeave") { edits.flight.departureTime = leave }
            #endif
            if let found = await GuideHolidayService.load(destination: input.destination, dates: model.days.map(\.date)) {
                holidays = found
                holidayState = found.isEmpty ? "No public holidays on these dates." : ""
            } else {
                holidayState = "Couldn’t load holidays. Check your connection."
            }
        }
        .onChange(of: edits) { _, value in if loaded { GuideEditsStore.save(value, id: input.tripID) } }
        .task(id: edits.flight.stayName) { await locateStay() }
    }

    /// Adds a place at the end of a day (the day re-sorts by time).
    private func append(_ placeID: String, to date: String, ctx: GuideContext) {
        let ids = ctx.days.first { $0.date == date }?.stops.map(\.itemID) ?? []
        guard !ids.contains(placeID) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { edits.order[date] = ids + [placeID] }
    }

    /// The stay's name becomes a point on the map, so every day can start there.
    private func locateStay() async {
        let name = edits.flight.stayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { edits.flight.stayLatitude = nil; edits.flight.stayLongitude = nil; return }
        try? await Task.sleep(for: .milliseconds(900))   // wait until typing pauses
        guard !Task.isCancelled else { return }
        let query = name.localizedCaseInsensitiveContains(input.destination) ? name : "\(name), \(input.destination)"
        guard let found = try? await CLGeocoder().geocodeAddressString(query).first?.location?.coordinate, !Task.isCancelled else { return }
        edits.flight.stayLatitude = found.latitude; edits.flight.stayLongitude = found.longitude
    }

    @ViewBuilder private var undoBar: some View {
        if undo != nil {
            Button {
                if let undo { edits = undo }
                undo = nil
            } label: {
                HStack(spacing: 10) {
                    Text("Stop removed").foregroundStyle(Sketch.paper.opacity(0.75))
                    Text("Undo").foregroundStyle(Sketch.paper)
                }
                .font(Sketch.text(15, "Bold", relativeTo: .body))
                .padding(.horizontal, 22).frame(minHeight: 50)
                .background(Capsule().fill(Sketch.ink))
            }
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { onClose() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { editingDays.toggle() }
            } label: { Text(editingDays ? "Done" : "Edit").font(Sketch.text(15, "SemiBold", relativeTo: .body)) }
            Menu {
                Button("Flights and stay", systemImage: "airplane") { showFacts = true }
                Button("Customize page", systemImage: "slider.horizontal.3") { showCustomize = true }
                ShareLink(item: ctx.shareText) { Label("Share as text", systemImage: "square.and.arrow.up") }
                if let onShowMap { Button("Show on map", systemImage: "map") { onShowMap() } }
                if let onEditBrief { Button("Change request", systemImage: "pencil") { onEditBrief() } }
                if let onOpenDetails { Button("Sources and details", systemImage: "doc.text.magnifyingglass") { onOpenDetails() } }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
        }
    }

    /// The page's chapters for the bar: each day by its date, each section by its short name.
    private func chapters(_ ctx: GuideContext) -> [ChaptersBar.Chapter] {
        blocks(ctx).compactMap { block in
            switch block {
            case .daysHeading: return nil
            case .day(let date): return .init(block: block, title: GuideDates.format(date, "EEE d"), isDay: true)
            case .section(let section): return .init(block: block, title: section.title, isDay: false)
            }
        }
    }
    /// The chapter being read: the block at the top, or the first day while on the days heading.
    private var currentChapter: Block? {
        if scrolledID == .daysHeading, let first = model.days.first { return .day(first.date) }
        return scrolledID
    }

    private func blocks(_ ctx: GuideContext) -> [Block] {
        edits.sections.filter { !edits.hidden.contains($0) }.flatMap { section -> [Block] in
            section == .days ? [.daysHeading] + ctx.days.map { .day($0.date) } : [.section(section)]
        }
    }

    private func rememberForUndo() {
        undo = edits
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { undo = nil }
        }
    }

    private func icon(_ section: GuideSection) -> TrippyIcon {
        switch section {
        case .glance: .list; case .map, .areas: .map; case .calendar: .calendar; case .days: .clock; case .book: .ticket
        case .tickets: .ticket; case .transport: .tram; case .food: .fork; case .budget: .euro; case .checklist: .check
        case .unknowns: .question
        }
    }

    @ViewBuilder private func sectionView(_ section: GuideSection, ctx: GuideContext) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SketchHeading(title: section.title, icon: icon(section), tint: tint)
            switch section {
            case .glance:
                GlanceSection(ctx: ctx) { date in withAnimation(reduceMotion ? nil : .smooth) { scrolledID = .day(date) } }
            case .map:
                GuideMap(days: ctx.days, height: 280, interactive: true, base: ctx.base)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .areas:
                AreasSection(ctx: ctx) { placeID, date in append(placeID, to: date, ctx: ctx) }
            case .calendar: CalendarSection(ctx: ctx, status: holidayState)
            case .days: EmptyView()
            case .book: BookSection(ctx: ctx, edits: $edits)
            case .tickets: TicketsSection(ctx: ctx, edits: $edits)
            case .transport: TransportSection(ctx: ctx, edits: $edits)
            case .food:
                if !ctx.model.scene.isEmpty { SceneSection(scene: ctx.model.scene, ctx: ctx) }
                FoodSection(ctx: ctx)
            case .budget: BudgetSection(ctx: ctx, edits: $edits, tint: tint)
            case .checklist: ChecklistSection(ctx: ctx, edits: $edits)
            case .unknowns: UnknownsSection(ctx: ctx)
            }
        }
    }
}

// MARK: - Header

private struct GuideHeader: View {
    let ctx: GuideContext
    let tint: Color
    @Binding var flight: GuideFlight
    @Binding var showFacts: Bool
    @FocusState private var focus: Field?
    enum Field: Hashable { case arrive, leave, stay }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(ctx.days.count) DAYS · \(ctx.people) \(ctx.people == 1 ? "TRAVELER" : "TRAVELERS")")
                        .font(Sketch.eyebrow).tracking(1).foregroundStyle(tint)
                    Text(ctx.input.title).font(Sketch.display(.title, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let first = ctx.days.first?.date, let last = ctx.days.last?.date {
                        Text("\(GuideDates.format(first, "EEE d MMM")) – \(GuideDates.format(last, "EEE d MMM")) \(GuideDates.format(last, "yyyy"))")
                            .font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                DoodleView(doodle: .suggested(title: ctx.input.title, city: ctx.input.destination), tint: tint)
                    .frame(width: 76, height: 76)
            }
            essentials
        }
        .onChange(of: focus) { old, _ in
            // "12" becomes "12:00" when the field is left, not while typing.
            if old == .arrive { flight.arrivalTime = TimeShorthand.normalize(flight.arrivalTime) }
            if old == .leave { flight.departureTime = TimeShorthand.normalize(flight.departureTime) }
        }
    }

    /// When you land, when you leave and where you stay, on one line: they shape the first day, the last day and
    /// where every day starts. While one is empty the plan suggests it, and a tap fills it in.
    private var essentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                timeField("Land", symbol: "airplane.arrival", text: $flight.arrivalTime, field: .arrive)
                timeField("Leave", symbol: "airplane.departure", text: $flight.departureTime, field: .leave)
                VStack(alignment: .leading, spacing: 0) {
                    Text("STAY").font(Sketch.eyebrow).tracking(0.8).foregroundStyle(Sketch.inkSoft)
                    TextField("Area or hotel", text: $flight.stayName)
                        .font(Sketch.text(15, "Bold", relativeTo: .body)).focused($focus, equals: .stay)
                        .submitLabel(.done).textContentType(.addressCityAndState)
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focus == .stay ? tint : Sketch.rule, lineWidth: focus == .stay ? 1.5 : 0.7))
                Button { showFacts = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                        .frame(width: 44, height: 54).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.1)))
                }
                .buttonStyle(SketchPressStyle()).accessibilityLabel("Flights, stay map and booking")
            }
            let hints = suggestions
            if !hints.isEmpty {
                BubbleFlow(spacing: 6) {
                    ForEach(hints) { hint in
                        Button { TrippyHaptics.light(); withAnimation(.snappy) { hint.apply() } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: hint.symbol).font(.system(size: 10, weight: .bold))
                                Text(hint.text).font(Sketch.text(12, "Bold", relativeTo: .caption))
                            }
                            .foregroundStyle(tint).padding(.horizontal, 11).frame(minHeight: 44)
                            .background(Capsule().strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(SketchPressStyle()).accessibilityHint(hint.why)
                    }
                }
                Text(hints[0].why).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            let yours = ctx.model.places.values.filter(\.personal).count
            let videos = ctx.model.places.values.filter { $0.videoCount > 0 || $0.fromVideo }.count
            if yours + videos > 0 {
                // What makes this plan yours, in one line.
                let parts = [yours > 0 ? "\(yours) \(yours == 1 ? "place" : "places") you saved" : nil, videos > 0 ? "\(videos) from videos" : nil].compactMap { $0 }
                Label("Built around " + parts.joined(separator: " and "), systemImage: "person.crop.circle.badge.checkmark")
                    .font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
            }
        }
    }

    private struct Hint: Identifiable { let id: String; let symbol: String; let text: String; let why: String; let apply: () -> Void }
    /// What to put in the empty fields, worked out from the plan itself.
    private var suggestions: [Hint] {
        var out: [Hint] = []
        if flight.stayName.trimmingCharacters(in: .whitespaces).isEmpty {
            // The parts of town the plan spends most days in make the shortest mornings.
            let areas = ctx.model.areas.filter { !$0.name.isEmpty && !$0.name.lowercased().hasPrefix("around ") }
                .sorted { ($0.days.count, $0.importance) > ($1.days.count, $1.importance) }.prefix(3)
            for area in areas {
                out.append(Hint(id: "stay:" + area.id, symbol: "bed.double.fill", text: "Stay in \(area.name)",
                                why: "Suggested bases: the areas your days spend the most time in.") { flight.stayName = area.name })
            }
        }
        if flight.arrivalTime.isEmpty, let first = ctx.days.first?.stops.first, let start = GuideDates.minutes(first.time), start >= 180 {
            let by = GuideDates.clock(start - 90)
            out.append(Hint(id: "land", symbol: "airplane.arrival", text: "Land by \(by)", why: "Day 1 starts at \(first.time); landing by \(by) keeps all of it.") { flight.arrivalTime = by })
        }
        if flight.departureTime.isEmpty, let last = ctx.days.last?.stops.last, let start = GuideDates.minutes(last.time) {
            let after = GuideDates.clock(min(23 * 60 + 30, start + last.durationMinutes + 180))
            out.append(Hint(id: "leave", symbol: "airplane.departure", text: "Leave after \(after)", why: "The last day runs to \(GuideDates.clock(start + last.durationMinutes)); a flight after \(after) keeps it whole.") { flight.departureTime = after })
        }
        return out
    }

    private func timeField(_ title: String, symbol: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(Sketch.inkSoft)
            TextField("--:--", text: text)
                .font(Sketch.text(16, "Bold", relativeTo: .body)).monospacedDigit()
                .keyboardType(.numbersAndPunctuation).focused($focus, equals: field).submitLabel(.done)
        }
        .padding(.horizontal, 12).frame(width: 78, height: 54, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focus == field ? tint : Sketch.rule, lineWidth: focus == field ? 1.5 : 0.7))
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) time")
    }
}

// MARK: - Overview

private struct GlanceSection: View {
    let ctx: GuideContext
    let jump: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(ctx.days) { day in
                Button { jump(day.date) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        DateBlock(date: day.date, tint: Sketch.dayColor(day.index))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.title).font(Sketch.text(16, "Bold", relativeTo: .headline)).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(day.subtitle).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                                .multilineTextAlignment(.leading)
                            if let holiday = day.holiday { SketchTag(text: holiday.name, tint: Sketch.plum).padding(.top, 3) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(SketchPressStyle())
                .accessibilityLabel("\(GuideDates.long(day.date)): \(day.title)")
                .accessibilityHint("Jump to this day")
                if day.index < ctx.days.count - 1 { Divider().overlay(Sketch.rule) }
            }
        }
        .sketchCard(padding: 14)
    }
}

struct DateBlock: View {
    let date: String
    var tint: Color = Sketch.clay
    var body: some View {
        VStack(spacing: 0) {
            Text(GuideDates.weekday(date)).font(Sketch.eyebrow).tracking(0.6)
            Text(GuideDates.dayNumber(date)).font(Sketch.display(.title2, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .frame(width: 50, height: 54)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
        .accessibilityHidden(true)
    }
}

// MARK: - Map

struct GuideMap: View {
    let days: [ResolvedDay]
    var height: CGFloat = 220
    var interactive = false
    var base: GuideBase? = nil
    var body: some View {
        let points = days.flatMap { day in day.stops.compactMap { s in s.place.coordinate.map { (day, s, $0) } } }
        Group {
            if points.isEmpty {
                ZStack {
                    Sketch.paperDeep
                    VStack(spacing: 8) {
                        DoodleView(doodle: .map, tint: Sketch.sky).frame(width: 52, height: 52)
                        Text("No locations yet").font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft)
                    }
                }
            } else {
                Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
                    if let base {
                        // Each day leaves from the base: a faint line to its first stop.
                        ForEach(days) { day in
                            if let first = day.stops.first?.place.coordinate {
                                MapPolyline(coordinates: [base.coordinate, first])
                                    .stroke(Sketch.dayColor(day.index).opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5]))
                            }
                        }
                        Annotation(base.name, coordinate: base.coordinate, anchor: .bottom) {
                            BasePin()
                        }
                        .annotationTitles(interactive ? .automatic : .hidden)
                    }
                    ForEach(days) { day in
                        let coords = day.stops.compactMap(\.place.coordinate)
                        if coords.count > 1 {
                            MapPolyline(coordinates: coords)
                                .stroke(Sketch.dayColor(day.index).opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
                        }
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, item in
                        let (day, stop, coordinate) = item
                        Annotation(stop.place.name, coordinate: coordinate, anchor: .center) {
                            let number = (day.stops.firstIndex(of: stop) ?? 0) + 1
                            Text(number.formatted()).font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).frame(width: 22, height: 22)
                                .background(Circle().fill(Sketch.dayColor(day.index)))
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                        .annotationTitles(interactive ? .automatic : .hidden)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
            }
        }
        .frame(height: height)
        .overlay(alignment: .topLeading) {
            if days.count > 1 {
                HStack(spacing: 5) {
                    ForEach(days) { day in
                        Text(GuideDates.weekday(day.date)).font(Sketch.eyebrow).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4).background(Capsule().fill(Sketch.dayColor(day.index)))
                    }
                }
                .padding(10).accessibilityHidden(true)
            }
        }
    }
}

/// The stay: an ink house pin that stands out from the numbered stops.
struct BasePin: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "house.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Sketch.ink))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Triangle().fill(Sketch.ink).frame(width: 10, height: 6)
        }
        .accessibilityLabel("Your stay")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: .init(x: rect.minX, y: rect.minY)); p.addLine(to: .init(x: rect.maxX, y: rect.minY)); p.addLine(to: .init(x: rect.midX, y: rect.maxY)); p.closeSubpath() }
    }
}

// MARK: - Holidays

private struct CalendarSection: View {
    let ctx: GuideContext
    let status: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(ctx.days) { day in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(GuideDates.short(day.date)).font(Sketch.text(13, "Bold", relativeTo: .footnote)).frame(width: 82, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            if let holiday = day.holiday {
                                Text(holiday.name).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).foregroundStyle(Sketch.plum)
                                Text("Public holiday. Small shops may close; book timed entries ahead.")
                                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                            } else {
                                Text("Regular day").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                            }
                            ForEach(ctx.model.calendar.filter { $0.date == day.date }) { row in
                                Text(row.detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    if day.index < ctx.days.count - 1 { Divider().overlay(Sketch.rule) }
                }
            }
            .sketchCard(padding: 14)
            if !status.isEmpty { Text(status).font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft) }
            if !ctx.model.events.isEmpty {
                Text("Events").font(Sketch.text(15, "Bold", relativeTo: .headline))
                ForEach(ctx.model.events) { event in InfoRowView(row: event, symbol: "sparkles") }
            }
        }
    }
}

struct InfoRowView: View {
    let row: GuideInfoRow
    var symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Sketch.plum).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(Sketch.text(15, "SemiBold", relativeTo: .body))
                if let date = row.date { Text(date).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft) }
                if !row.detail.isEmpty { Text(row.detail).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft) }
                if let url = row.url { Link("Official site", destination: url).font(Sketch.text(13, "SemiBold", relativeTo: .footnote)) }
            }
            Spacer(minLength: 0)
            if let price = row.price { Text(Euro.text(price)).font(Sketch.text(14, "Bold", relativeTo: .body)).monospacedDigit() }
        }
    }
}

// MARK: - Days

private struct DayView: View {
    let day: ResolvedDay
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    let editing: Bool
    var beforeRemove: () -> Void = {}
    private var color: Color { Sketch.dayColor(day.index) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DateBlock(date: day.date, tint: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GuideDates.long(day.date)).font(Sketch.text(12, "SemiBold", relativeTo: .caption)).foregroundStyle(color)
                    if editing {
                        TextField(day.title, text: Binding(get: { edits.dayTitles[day.date] ?? "" },
                                                            set: { edits.dayTitles[day.date] = $0 }))
                            .font(Sketch.display(.title3)).textFieldStyle(.plain)
                            .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Sketch.paperDeep))
                    } else {
                        Text(day.title).font(Sketch.display(.title3)).fixedSize(horizontal: false, vertical: true)
                    }
                    AreaTags(areas: ctx.areas(of: day), tint: color)
                    if let holiday = day.holiday { SketchTag(text: holiday.name, tint: Sketch.plum) }
                }
            }
            if day.stops.contains(where: { $0.place.coordinate != nil }) {
                GuideMap(days: [day], height: 150, base: ctx.base).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if editing {
                SuggestionStrip(suggestions: ctx.suggestions(for: day), tint: color, apply: apply)
            } else if !day.stops.contains(where: { $0.slot == nil && !$0.place.isFood }) {
                // Free day: easy ideas to pick from, nothing forced.
                SuggestionStrip(suggestions: ctx.freeDayIdeas(for: day), tint: color, apply: apply)
            } else if let route = ctx.shorterRoute(for: day) {
                // A day that zig-zags: one tap puts the sights in walking order.
                SuggestionStrip(suggestions: [route], tint: color, apply: apply)
            }
            VStack(alignment: .leading, spacing: 0) {
                if day.stops.isEmpty {
                    // A free day says so, and what the ideas above are for.
                    VStack(alignment: .leading, spacing: 4) {
                        Label("A free day", systemImage: "sun.max").font(Sketch.text(15, "Bold", relativeTo: .subheadline))
                        Text(editing ? "Add a stop or a meal below."
                             : ctx.base != nil ? "Nothing planned yet. The ideas above are close to \(ctx.base!.name); tap one to add it."
                             : "Nothing planned yet. Tap an idea above to add it, or keep the day open.")
                            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
                if let base = ctx.base, !day.stops.isEmpty {
                    BaseStartRow(base: base, minutes: day.stops.first?.fromBaseMinutes, tint: color)
                }
                ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                    if index > 0, let gap = freeMinutes(before: index), gap >= 60 {
                        let idea = editing ? nil : ctx.unusedInAreas(of: day).first
                        FreeTimeRow(minutes: gap, color: color, idea: idea, onAdd: idea.map { place in
                            { apply(GuideSuggestion(id: "gap|\(place.id)", text: place.name, detail: "", symbol: "plus", action: .addPlace(place.id))) }
                        })
                    }
                    if let travel = stop.travelMinutes, index > 0 {
                        TravelLegRow(minutes: travel, color: color, from: day.stops[index - 1].place, to: stop.place, input: ctx.input)
                    }
                    if let warning = ctx.timingWarning(stop, day: day) {
                        Label(warning, systemImage: "exclamationmark.triangle").font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                            .foregroundStyle(Sketch.coral).padding(.leading, 70).padding(.top, 6)
                    }
                    if stop.slot != nil, let flow = stop.flowNote {
                        // Meal and drink blocks say why they moved, or that they no longer fit, like stops do.
                        Label(flow, systemImage: stop.fits ? "arrow.turn.down.right" : "exclamationmark.triangle")
                            .font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                            .foregroundStyle(stop.fits ? Sketch.inkSoft : Sketch.coral)
                            .fixedSize(horizontal: false, vertical: true).padding(.leading, 70).padding(.top, 6)
                    }
                    if let slot = stop.slot {
                        SlotRow(stop: stop, slot: slot, color: color, editing: editing, planPlaces: Array(ctx.model.places.values),
                                time: fixedTime(stop),
                                onPick: { pick(stop, $0) }, onMove: { move(stop, by: $0) }, onRemove: { remove(stop) },
                                neighbors: [day.stops[safe: index - 1], day.stops[safe: index + 1]].compactMap { $0?.place }
                                    .filter { !$0.isSlotPlaceholder },
                                base: ctx.base, videoNotes: slot.pickedID.flatMap { ctx.model.videoNotes[$0] } ?? [])
                    } else {
                        StopRow(stop: stop, color: color, editing: editing, booked: edits.booked.contains(stop.place.id),
                                note: Binding(get: { edits.notes[stop.key] ?? "" }, set: { edits.notes[stop.key] = $0.nilIfEmpty }),
                                time: fixedTime(stop),
                                onMove: { move(stop, by: $0) }, onRemove: { remove(stop) }, onSwap: { swap(stop, with: $0) },
                                communityTips: ctx.model.communityTips(for: stop.place.id),
                                videoNotes: ctx.model.videoNotes[stop.place.id] ?? [],
                                onRelease: stop.fixedTime ? { release(stop) } : nil)
                            .atlasRise(index)
                    }
                }
            }
            if let leave = ctx.leaveBy(for: day) { LeaveByRow(title: leave.title, detail: leave.detail, late: leave.late) }
            if editing { addMenu }
        }
    }

    /// A time typed here is the traveller's: it stays put and the rest of the day flows around it.
    private func fixedTime(_ stop: ResolvedStop) -> Binding<String> {
        Binding(get: { edits.times[stop.key] ?? stop.time },
                set: { edits.times[stop.key] = $0; edits.fixedTimes.insert(stop.key) })
    }
    /// Back to the planner's time: the stop flows with the day again.
    private func release(_ stop: ResolvedStop) {
        edits.fixedTimes.remove(stop.key); edits.times[stop.key] = nil
    }

    /// Minutes with nothing in them before a stop: after the last one ended and the walk over.
    private func freeMinutes(before index: Int) -> Int? {
        let previous = day.stops[index - 1], next = day.stops[index]
        guard let ended = GuideDates.minutes(previous.time), let starts = GuideDates.minutes(next.time) else { return nil }
        return starts - (ended + previous.durationMinutes) - (next.travelMinutes ?? 0)
    }
    private var ids: [String] { day.stops.map(\.itemID) }
    private func apply(_ suggestion: GuideSuggestion) {
        withAnimation(.snappy) {
            switch suggestion.action {
            case .addBlock(let kind): addBlock(kind)
            case .addPlace(let id), .restore(let id): if !ids.contains(id) { setOrder(ids + [id]) }
            case .reorder(let order): reorder(order)
            }
        }
    }
    private func setOrder(_ new: [String]) { edits.order[day.date] = new }
    /// A shorter walk: the same clock times, handed out in the new order (fixed stops keep their place and time).
    private func reorder(_ order: [String]) {
        let times = day.stops.map(\.time)
        let byID = Dictionary(day.stops.map { ($0.itemID, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, time) in zip(order, times) {
            guard let stop = byID[id], stop.time != time, !stop.fixedTime else { continue }
            edits.times[stop.key] = time
        }
        setOrder(order)
    }
    private func move(_ stop: ResolvedStop, by delta: Int) {
        var list = ids
        guard let i = list.firstIndex(of: stop.itemID), list.indices.contains(i + delta) else { return }
        // Swap clock times too, so the day still reads top to bottom.
        let other = day.stops[i + delta]
        edits.times[stop.key] = other.time; edits.times[other.key] = stop.time
        list.swapAt(i, i + delta); setOrder(list)
    }
    private func remove(_ stop: ResolvedStop) { beforeRemove(); setOrder(ids.filter { $0 != stop.itemID }) }
    private func swap(_ stop: ResolvedStop, with place: GuidePlace) {
        edits.times["\(day.date)|\(place.id)"] = stop.time
        setOrder(ids.map { $0 == stop.itemID ? place.id : $0 })
    }
    /// Re-pick a block's place; nil keeps the block open ("decide on the day").
    private func pick(_ stop: ResolvedStop, _ option: SlotOption?) {
        if let saved = option?.saved { edits.extraPlaces[saved.id] = saved }
        edits.slotPicks[stop.key] = option?.id ?? ""
        if edits.order[day.date] == nil { setOrder(ids) }   // keep an automatic coffee break once touched
    }
    private func addBlock(_ kind: SlotKind) {
        let id = kind.newID()
        edits.times["\(day.date)|\(id)"] = suggestedTime(for: kind)
        setOrder(ids + [id])
    }
    /// A free moment near the block's usual time, after whatever runs then.
    private func suggestedTime(for kind: SlotKind) -> String {
        guard let target = GuideDates.minutes(kind.defaultTime) else { return kind.defaultTime }
        let busy = day.stops.compactMap { stop -> ClosedRange<Int>? in
            guard let start = GuideDates.minutes(stop.time) else { return nil }
            return start...(start + stop.durationMinutes)
        }
        guard let clash = busy.first(where: { $0.contains(target) }) else { return kind.defaultTime }
        return GuideDates.clock(clash.upperBound + 10)
    }
    private var addMenu: some View {
        let used = Set(ctx.days.flatMap(\.stops).map(\.place.id))
        let pool = ctx.model.orderedPlaces.filter { !used.contains($0.id) }
        let present = Set(day.stops.compactMap(\.slot?.kind))
        return Menu {
            Section("A block, pick the place later") {
                ForEach(SlotKind.allCases) { kind in
                    Button(present.contains(kind) ? "Another \(kind.title.lowercased())" : kind.title, systemImage: kind.symbol) { addBlock(kind) }
                }
            }
            Section("Sights") { ForEach(pool.filter { !$0.isFood }.prefix(12)) { p in Button(p.name) { setOrder(ids + [p.id]) } } }
        } label: {
            Label("Add a stop", systemImage: "plus").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
        }
    }
}

private struct StopRow: View {
    let stop: ResolvedStop
    let color: Color
    let editing: Bool
    let booked: Bool
    @Binding var note: String
    @Binding var time: String
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    let onSwap: (GuidePlace) -> Void
    /// Traveller tips about this stop (its name, its area or what it is), from the plan's community matches.
    var communityTips: [GuideCommunityTip] = []
    /// What the videos behind this stop say about it.
    var videoNotes: [GuideVideoNote] = []
    /// Lets a typed time go, so the stop flows with the day again.
    var onRelease: (() -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                if editing {
                    TextField("10:00", text: $time).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.center)
                        .frame(width: 58, height: 34).background(RoundedRectangle(cornerRadius: 8).fill(Sketch.paperDeep))
                        .onSubmit { time = TimeShorthand.normalize(time) }
                } else {
                    Text(stop.time).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                }
                Text("\(stop.durationMinutes) min").font(Sketch.text(11, relativeTo: .caption2)).foregroundStyle(Sketch.inkFaint)
                if stop.fixedTime || stop.booked {
                    Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                        .accessibilityLabel(stop.booked ? "Booked time" : "Time you set")
                }
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 5) {
                if stop.place.coordinate != nil {
                    PlacePhoto(place: stop.place, tint: color).frame(height: 132).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, 4)
                }
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: stop.place.symbol).foregroundStyle(color).imageScale(.small)
                        Text(stop.place.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if booked { Image(systemName: "checkmark.seal.fill").foregroundStyle(Sketch.sage).accessibilityLabel("Booked") }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Show less" : "Show more")
                Text(meta).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                if let flow = stop.flowNote {
                    // Why the day moved this stop, or why it no longer fits.
                    Label(flow, systemImage: stop.fits ? "arrow.turn.down.right" : "exclamationmark.triangle")
                        .font(Sketch.text(12, "SemiBold", relativeTo: .caption))
                        .foregroundStyle(stop.fits ? Sketch.inkSoft : Sketch.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StopSources(place: stop.place)
                if !stop.includes.isEmpty {
                    Label("With " + ListFormatter.localizedString(byJoining: stop.includes), systemImage: "square.stack.3d.up")
                        .font(Sketch.text(13, "Medium", relativeTo: .footnote)).foregroundStyle(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !stop.why.isEmpty {
                    Text(stop.why).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.ink.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !stop.place.plainWhy.isEmpty {
                    Text(stop.place.plainWhy).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !stop.place.shortDescription.isEmpty {
                    // Every stop says why it is here: with no note or reason, what the place is.
                    Text(stop.place.shortDescription).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !stop.tip.isEmpty {
                    Label(stop.tip, systemImage: "lightbulb").font(Sketch.text(13, "Medium", relativeTo: .footnote))
                        .foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
                }
                if !editing && !videoNotes.isEmpty {
                    VideoSaysBlock(notes: videoNotes, expandedByDefault: expanded).padding(.top, 2)
                }
                if !editing {
                    ForEach(communityTips) { CommunityTipCard(tip: $0).padding(.top, 4) }
                }
                if expanded || editing { details }
                if editing { editControls }
                else if !note.isEmpty {
                    Text(note).font(Sketch.text(14, "Medium", relativeTo: .subheadline)).foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var meta: String {
        var parts = [stop.place.categoryLabel]
        if let rating = stop.place.rating { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var details: some View {
        if !stop.place.shortDescription.isEmpty, !(stop.why.isEmpty && stop.place.plainWhy.isEmpty) {
            Text(stop.place.shortDescription).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
        }
        if let address = stop.place.address {
            Label(address, systemImage: "mappin").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
        }
        HStack(spacing: 16) {
            if let url = stop.place.url { Link("Website", destination: url) }
            if let c = stop.place.coordinate {
                Button("Directions") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: c)); item.name = stop.place.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }
            }
        }
        .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).frame(minHeight: 32)
    }

    @ViewBuilder private var editControls: some View {
        TextField("Note, e.g. booked for 10:30", text: $note, axis: .vertical).font(Sketch.text(14, relativeTo: .subheadline))
            .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Sketch.paperDeep))
        HStack(spacing: 4) {
            iconButton("arrow.up", "Move up") { onMove(-1) }
            iconButton("arrow.down", "Move down") { onMove(1) }
            if let onRelease { iconButton("pin.slash", "Let this time move", action: onRelease) }
            if !stop.alternatives.isEmpty {
                Menu {
                    ForEach(stop.alternatives) { alt in Button(alt.name) { onSwap(alt) } }
                } label: { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 44, height: 44) }
                    .accessibilityLabel("Swap for an alternative")
            }
            Spacer()
            iconButton("trash", "Remove", role: .destructive, action: onRemove)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(label)
    }
}

/// Chapters while scrolling a long plan: the days and sections in a row that follows you, the current one filled.
private struct ChaptersBar: View {
    struct Chapter: Identifiable, Hashable {
        var id: TripGuideView.Block { block }
        let block: TripGuideView.Block
        let title: String
        let isDay: Bool
    }
    let chapters: [Chapter]
    let current: TripGuideView.Block?
    let tint: Color
    let go: (TripGuideView.Block) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chapters) { chapter in
                        let on = chapter.block == current
                        Button { go(chapter.block) } label: {
                            Text(chapter.title).font(Sketch.text(13, on ? "Bold" : "SemiBold", relativeTo: .footnote))
                                .foregroundStyle(on ? Color.white : chapter.isDay ? Sketch.ink : Sketch.inkSoft)
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .background(Capsule().fill(on ? tint : Color.clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(chapter.block)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .onChange(of: current) { _, now in
                guard let now else { return }
                withAnimation(.snappy) { proxy.scrollTo(now, anchor: .center) }
            }
        }
        .background(Capsule().fill(Sketch.paper).shadow(color: .black.opacity(0.12), radius: 8, y: 3))
        .overlay(Capsule().strokeBorder(Sketch.ink.opacity(0.08)))
        .padding(.horizontal, 16).padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chapters")
    }
}

/// The last stop of the trip: when to leave for the flight, and what still runs into it.
private struct LeaveByRow: View {
    let title: String
    let detail: String
    let late: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "airplane.departure").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(late ? Sketch.coral : Sketch.ink))
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Text(detail).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(late ? Sketch.coral : Sketch.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Book ahead

private struct BookSection: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ctx.priorities.isEmpty && ctx.model.bookingTasks.isEmpty {
                Text("Nothing here needs a timed booking.").font(Sketch.hand(.callout)).foregroundStyle(Sketch.inkSoft)
            }
            ForEach(Array(ctx.priorities.enumerated()), id: \.element.id) { index, place in
                let done = edits.booked.contains(place.id)
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        if done { edits.booked.remove(place.id) } else { edits.booked.insert(place.id) }
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title2)
                            .foregroundStyle(done ? Sketch.sage : Sketch.inkFaint).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(done ? "Booked" : "Mark as booked")
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(place.name).font(Sketch.text(16, "Bold", relativeTo: .headline)).strikethrough(done, color: Sketch.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            if index == 0 && !done { SketchTag(text: "First", tint: Sketch.coral) }
                        }
                        Text([ctx.dateOf(place).map(GuideDates.short), "timed entry", "official site only"].compactMap { $0 }.joined(separator: " · "))
                            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                        if let url = place.url { Link("Tickets", destination: url).font(Sketch.text(13, "SemiBold", relativeTo: .footnote)) }
                    }
                    Spacer(minLength: 0)
                }
                .sketchCard(padding: 12)
            }
            ForEach(ctx.model.bookingTasks) { task in InfoRowView(row: task, symbol: "calendar.badge.clock").sketchCard(padding: 12) }
        }
    }
}

// MARK: - Tickets

private struct TicketsSection: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    @State private var openRow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach($edits.fares) { $fare in
                    HStack(spacing: 10) {
                        TextField("Type", text: $fare.name).font(Sketch.text(15, relativeTo: .body))
                        Text("\(fare.count)").font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                        Stepper("\(fare.name): \(fare.count)", value: $fare.count, in: 0...20).labelsHidden()
                    }
                    .frame(minHeight: 48)
                    Divider().overlay(Sketch.rule)
                }
                Menu {
                    ForEach(["Student", "Over 65", "Child", "Adult"], id: \.self) { name in
                        Button(name) { edits.fares.append(GuideFare(name: name, count: 1)) }
                    }
                } label: {
                    Label("Add traveler type", systemImage: "plus").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .sketchCard(padding: 14)

            VStack(spacing: 0) {
                ForEach(ctx.ticketed) { place in
                    row(place)
                    Divider().overlay(Sketch.rule)
                }
                HStack {
                    Text("Total").font(Sketch.text(15, "Bold", relativeTo: .headline))
                    Spacer()
                    Text(Euro.text(ctx.ticketsDisplay)).font(Sketch.display(.title3, weight: .bold)).monospacedDigit()
                }
                .padding(.top, 12)
                if ctx.ticketsUnknown > 0 {
                    Text("\(ctx.ticketsUnknown) without a known price. Tap one to add it.")
                        .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .sketchCard(padding: 14)
        }
    }

    private func row(_ place: GuidePlace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { openRow = openRow == place.id ? nil : place.id } } label: {
                HStack {
                    Text(place.name).font(Sketch.text(15, "SemiBold", relativeTo: .body)).multilineTextAlignment(.leading)
                    Spacer()
                    Text(ctx.ticketTotal(place).map(Euro.text) ?? "Check").font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                        .foregroundStyle(ctx.ticketTotal(place) == nil ? Sketch.inkFaint : Sketch.ink)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if openRow == place.id {
                ForEach(edits.fares.filter { $0.count > 0 }) { fare in
                    HStack {
                        Text("\(fare.name) × \(fare.count)").font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                        Spacer()
                        TextField("€ each", value: Binding(get: { ctx.price(place, fare: fare) },
                                                            set: { edits.prices[place.id, default: [:]][fare.id.uuidString] = $0 }),
                                  format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 96)
                            .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Sketch.paperDeep))
                    }
                }
                Button("Free entry") {
                    for fare in edits.fares { edits.prices[place.id, default: [:]][fare.id.uuidString] = 0 }
                }
                .font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).frame(minHeight: 44)
            }
        }
    }
}

// MARK: - Getting around

private struct TransportSection: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    @State private var showTransit = false
    private var city: String { ctx.input.destination.split(separator: ",").first.map(String.init) ?? ctx.input.destination }
    var body: some View {
        let legs = ctx.days.flatMap(\.stops).compactMap(\.travelMinutes)
        let longLegs = legs.filter { $0 >= 30 }.count
        VStack(alignment: .leading, spacing: 12) {
            // The city's metro, tram and rail lines on a map, and the ticket worth buying for these days.
            Button { TrippyHaptics.light(); showTransit = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "tram.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(Sketch.paper)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sketch.sky))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Metro & tram map").font(Sketch.text(17, "Bold", relativeTo: .headline))
                        Text("Lines in \(city) and the ticket to buy for \(ctx.days.count) \(ctx.days.count == 1 ? "day" : "days")")
                            .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SketchPressStyle())
            .sketchCard(padding: 14)
            .accessibilityHint("Opens the transit map")
            if !legs.isEmpty {
                HStack(spacing: 14) {
                    stat("\(legs.reduce(0, +))", "min walking")
                    stat("\(longLegs)", longLegs == 1 ? "leg over 30 min" : "legs over 30 min")
                    Spacer()
                }
                .sketchCard(padding: 14)
            }
            ForEach(ctx.model.transport) { option in InfoRowView(row: option, symbol: "tram").sketchCard(padding: 12) }
            VStack(spacing: 0) {
                ForEach($edits.transportLines) { $line in
                    HStack {
                        TextField("Item", text: $line.label).font(Sketch.text(15, relativeTo: .body))
                        TextField("€ total", value: $line.amount, format: .number).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 96)
                            .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Sketch.paperDeep))
                    }
                    .frame(minHeight: 48)
                    Divider().overlay(Sketch.rule)
                }
                HStack {
                    Button { edits.transportLines.append(GuideCostLine(label: "")) } label: { Label("Add item", systemImage: "plus") }
                        .font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).frame(minHeight: 44)
                    Spacer()
                    Text(Euro.text(ctx.transportKnown)).font(Sketch.text(16, "Bold", relativeTo: .headline)).monospacedDigit()
                }
            }
            .sketchCard(padding: 14)
            Text("Walking times are estimated from distance.").font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkFaint)
        }
        .sheet(isPresented: $showTransit) {
            TransitSheet(request: TransitRequest(city: ctx.input.destination,
                                                 coordinate: ctx.base.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                                                 days: max(1, ctx.days.count), travelers: max(1, ctx.people)),
                         baseURL: ctx.input.bridgeURL, token: ctx.input.bridgeToken, preview: TransitDemo.answer)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Sketch.display(.title2, weight: .bold)).monospacedDigit()
            Text(label).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
        }
        .frame(minWidth: 110, alignment: .leading)
    }
}

// MARK: - Food

private struct FoodSection: View {
    let ctx: GuideContext
    var body: some View {
        VStack(spacing: 0) {
            if ctx.foodPlaces.isEmpty { Text("No food stops yet.").font(Sketch.hand(.callout)).foregroundStyle(Sketch.inkSoft) }
            ForEach(Array(ctx.foodPlaces.enumerated()), id: \.element.id) { index, place in
                HStack(alignment: .top, spacing: 12) {
                    TrippyIconView(icon: .fork, size: 18).foregroundStyle(Sketch.sage)
                        .frame(width: 36, height: 36).background(Circle().fill(Sketch.sage.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).font(Sketch.text(16, "Bold", relativeTo: .headline))
                        Text(foodMeta(place)).font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkSoft)
                        if !place.shortDescription.isEmpty {
                            Text(place.shortDescription).font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                if index < ctx.foodPlaces.count - 1 { Divider().overlay(Sketch.rule) }
            }
        }
        .sketchCard(padding: 14)
    }
    private func foodMeta(_ place: GuidePlace) -> String {
        var parts: [String] = [place.categoryLabel]
        if let date = ctx.dateOf(place) { parts.append(GuideDates.short(date)) }
        if let r = place.rating { parts.append("★ \(r.formatted(.number.precision(.fractionLength(1))))" + (place.reviewCount.map { " (\($0))" } ?? "")) }
        if let a = place.priceMin, let b = place.priceMax { parts.append("\(Euro.text(a))–\(Euro.text(b))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Budget

private struct BudgetSection: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    let tint: Color
    var body: some View {
        VStack(spacing: 0) {
            line("Stay", trailing: AnyView(amountField($edits.stayTotal, prompt: "€ total")))
            line("Tickets", detail: ctx.ticketsUnknown > 0 ? "\(ctx.ticketsUnknown) not priced" : nil, value: ctx.ticketsDisplay)
            line("Getting around", value: ctx.transportKnown)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Food").font(Sketch.text(15, relativeTo: .body))
                    Spacer()
                    Text(Euro.text(ctx.foodTotal)).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit()
                }
                Slider(value: $edits.foodPerPersonDay, in: 10...120, step: 5) { Text("Food per person per day") }
                Text("\(Euro.text(edits.foodPerPersonDay)) per person per day")
                    .font(Sketch.hand(.caption)).foregroundStyle(Sketch.inkSoft)
            }
            .padding(.vertical, 10)
            Divider().overlay(Sketch.rule)
            line("Coffee and extras", trailing: AnyView(amountField($edits.extras, prompt: "€ total")))
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimate").font(Sketch.text(15, "Bold", relativeTo: .headline))
                    Text("\(Euro.text(ctx.budgetTotal / Double(ctx.people))) per person, excluding flights")
                        .font(Sketch.hand(.footnote)).foregroundStyle(Sketch.inkSoft)
                }
                Spacer()
                Text(Euro.text(ctx.budgetTotal)).font(Sketch.display(.title, weight: .bold)).monospacedDigit().foregroundStyle(tint)
            }
            .padding(.top, 14)
        }
        .sketchCard(padding: 16)
    }

    private func line(_ title: String, detail: String? = nil, value: Double? = nil, trailing: AnyView? = nil) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Sketch.text(15, relativeTo: .body))
                    if let detail { Text(detail).font(Sketch.hand(.caption)).foregroundStyle(Sketch.inkFaint) }
                }
                Spacer()
                if let trailing { trailing } else { Text(Euro.text(value)).font(Sketch.text(15, "Bold", relativeTo: .body)).monospacedDigit() }
            }
            .frame(minHeight: 48)
            Divider().overlay(Sketch.rule)
        }
    }

    private func amountField(_ value: Binding<Double?>, prompt: String) -> some View {
        TextField(prompt, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .frame(width: 96).padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Sketch.paperDeep))
    }
}

// MARK: - Checklist

private struct ChecklistSection: View {
    let ctx: GuideContext
    @Binding var edits: GuideEdits
    @State private var draft = ""
    var body: some View {
        let items = ctx.checklist
        let groups = items.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        let done = items.filter { edits.checklistDone.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(done), total: Double(max(items.count, 1))) {
                Text("\(done) of \(items.count) done").font(Sketch.text(13, "SemiBold", relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft)
            }
            .tint(Sketch.sage)
            ForEach(groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.uppercased()).font(Sketch.eyebrow).tracking(0.8).foregroundStyle(Sketch.inkFaint)
                    ForEach(items.filter { $0.group == group }) { item in
                        let isDone = edits.checklistDone.contains(item.id)
                        Button {
                            if isDone { edits.checklistDone.remove(item.id) } else { edits.checklistDone.insert(item.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: isDone ? "checkmark.square.fill" : "square").font(.title3)
                                    .foregroundStyle(isDone ? Sketch.sage : Sketch.inkFaint)
                                Text(item.text).font(Sketch.text(15, relativeTo: .body)).strikethrough(isDone, color: Sketch.inkFaint)
                                    .foregroundStyle(isDone ? Sketch.inkSoft : Sketch.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isDone ? .isSelected : [])
                        .contextMenu {
                            if item.custom, let index = edits.customChecklist.firstIndex(of: item.text) {
                                Button("Delete", systemImage: "trash", role: .destructive) { edits.customChecklist.remove(at: index) }
                            }
                        }
                    }
                }
            }
            HStack {
                TextField("Add an item", text: $draft).font(Sketch.text(15, relativeTo: .body)).submitLabel(.done).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Add")
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Sketch.paperDeep))
        }
        .sketchCard(padding: 16)
    }
    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        edits.customChecklist.append(text); draft = ""
    }
}

// MARK: - Not yet checked

private struct UnknownsSection: View {
    let ctx: GuideContext
    var body: some View {
        let points: [String] = [
            "Opening hours for these exact dates",
            ctx.ticketsUnknown > 0 ? "Entry prices for \(ctx.ticketsUnknown) sights" : nil,
            ctx.model.transport.isEmpty ? "Local transport fares" : nil,
            ctx.model.events.isEmpty ? "Seasonal events and markets" : nil,
            "Walking times (estimated from distance)",
        ].compactMap { $0 }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Sketch.ochre).frame(width: 6, height: 6)
                    Text(point).font(Sketch.text(14, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sketchCard(tint: Sketch.ochre, padding: 16)
    }
}

// MARK: - Sheets

private struct GuideCustomizeSheet: View {
    @Binding var edits: GuideEdits
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Accent") {
                    HStack(spacing: 8) {
                        ForEach(Sketch.pigments, id: \.0) { name, color in
                            Button { edits.pigment = name } label: {
                                Circle().fill(color).frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Sketch.ink, lineWidth: edits.pigment == name ? 2.5 : 0).padding(-4))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain).accessibilityLabel(name.capitalized)
                            .accessibilityAddTraits(edits.pigment == name ? .isSelected : [])
                        }
                    }
                }
                Section {
                    ForEach(edits.sections) { section in
                        Toggle(section.title, isOn: Binding(get: { !edits.hidden.contains(section) },
                                                            set: { if $0 { edits.hidden.remove(section) } else { edits.hidden.insert(section) } }))
                    }
                    .onMove { edits.sections.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("Sections") } footer: { Text("Drag to reorder. Turn off what you don’t need.") }
                Section { Button("Reset layout") { edits.sections = GuideSection.allCases; edits.hidden = [] } }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct GuideFactsSheet: View {
    @Binding var edits: GuideEdits
    let input: GuideInput
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showStayMap = false
    private var city: String { input.destination.trimmingCharacters(in: .whitespaces) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    link(TripLinks.travelTitle(mode: input.travelMode, city: city),
                         symbol: input.travelMode == "train" ? "tram.fill" : input.travelMode == "car" ? "car.fill" : "airplane",
                         url: TripLinks.travel(mode: input.travelMode, city: city, start: input.startDate, end: input.endDate))
                    Menu {
                        ForEach(MailSearch.Kind.allCases) { kind in
                            Button(kind.title(mode: input.travelMode), systemImage: kind.symbol) {
                                MailSearch.open(MailSearch.query(kind, city: city, mode: input.travelMode))
                            }
                        }
                    } label: { Label("Find my bookings in Gmail", systemImage: "envelope.open") }
                    Button { showStayMap = true } label: { Label("Where to stay", systemImage: "safari") }
                    link("Stays on Booking.com", symbol: "bed.double", url: stayURL(airbnb: false))
                    link("Homes on Airbnb", symbol: "house", url: stayURL(airbnb: true))
                } header: { Text("Find") } footer: { Text("Opens with your city, dates and travelers filled in. Gmail opens (the app if you have it) with a search for booking confirmations about \(city.isEmpty ? "your trip" : city); the search is also copied for any other mail app.") }
                Section("Arrival") {
                    TextField("Flight, e.g. ATH 16:40 → BCN 18:45", text: $edits.flight.outbound, axis: .vertical)
                    TextField("Landing time, e.g. 18:45", text: $edits.flight.arrivalTime).keyboardType(.numbersAndPunctuation)
                        .onSubmit { edits.flight.arrivalTime = TimeShorthand.normalize(edits.flight.arrivalTime) }
                }
                Section("Return") {
                    TextField("Flight, e.g. BCN 19:40 → ATH 23:30", text: $edits.flight.inbound, axis: .vertical)
                    TextField("Take-off time, e.g. 19:40", text: $edits.flight.departureTime).keyboardType(.numbersAndPunctuation)
                        .onSubmit { edits.flight.departureTime = TimeShorthand.normalize(edits.flight.departureTime) }
                }
                Section("Stay") {
                    TextField("Name", text: $edits.flight.stayName)
                    TextField("Address", text: $edits.flight.stayAddress).textContentType(.fullStreetAddress)
                    TextField("Total cost (€)", value: $edits.stayTotal, format: .number).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Flights and stay").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { normalizeTimes(); dismiss() } } }
            .onDisappear(perform: normalizeTimes)
        }
        .sheet(isPresented: $showStayMap) {
            StayHeatmapView(city: city) { area in edits.flight.stayName = area }
                .presentationDragIndicator(.visible)
        }
    }
    private func normalizeTimes() {
        edits.flight.arrivalTime = TimeShorthand.normalize(edits.flight.arrivalTime)
        edits.flight.departureTime = TimeShorthand.normalize(edits.flight.departureTime)
    }
    private func stayURL(airbnb: Bool) -> URL? {
        TripLinks.stay(area: edits.flight.stayName, city: city, start: input.startDate, end: input.endDate, travelers: input.travelers, airbnb: airbnb)
    }
    private func link(_ title: String, symbol: String, url: URL?) -> some View {
        Button { if let url { openURL(url) } } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .disabled(city.isEmpty || url == nil)
    }
}


/// The traveller changed their stay or flight times after the plan was made: the days still assume the old ones.
private struct PlanOutdatedBanner: View {
    let changes: [String]
    let tint: Color
    let onUpdate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("The plan still uses your old details").font(Sketch.text(14, "Bold", relativeTo: .subheadline))
                Text("New " + ListFormatter.localizedString(byJoining: changes) + ".")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Update plan", action: onUpdate).font(Sketch.text(14, "SemiBold", relativeTo: .subheadline))
                .buttonStyle(.borderedProminent).tint(tint).frame(minHeight: 44)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }
}
