import SwiftUI
import UIKit
import MapKit
import CoreLocation
import AVFoundation
import UniformTypeIdentifiers
import WebKit
import Security

@main
struct TrippyApp: App {
    var body: some Scene {
        WindowGroup {
            TripFlowView()
        }
    }
}

private enum TripStage: Equatable {
    case library
    case brief
    case workspace
}

private enum ResearchLayer: String, CaseIterable, Identifiable {
    case foundation = "Foundation"
    case dateVerification = "Ημερομηνίες"
    case itinerary = "Πρόγραμμα"
    case targetedRefresh = "Επανέρευνα"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundation: "1 · Ανακάλυψη"
        case .dateVerification: "2 · Έλεγχος"
        case .itinerary: "3 · Σύνθεση"
        case .targetedRefresh: "4 · Ανανέωση"
        }
    }
    var detail: String {
        switch self {
        case .foundation: "Ευρύ pool υποψηφίων, περιοχών και βασικών πηγών."
        case .dateVerification: "Έλεγχος κάθε χώρου και περιορισμού στις ακριβείς ημερομηνίες."
        case .itinerary: "Σύνδεση επιβεβαιωμένων επιλογών σε ρεαλιστικές ημέρες και διαδρομές."
        case .targetedRefresh: "Νέα αναζήτηση μόνο για τα πεδία και τις αλλαγές που ζητάς."
        }
    }
}

private struct TripBrief: Codable, Equatable {
    var destination = ""
    var startDate = ""
    var endDate = ""
    var dateContext: [String] = []
    var dateIsUnknown = false
    var duration = 4
    var travelers = 2
    var group = "Φίλοι"
    var vibes: Set<String> = ["Πόλη"]
    var interests: Set<String> = []
    var preferenceTags: Set<String> = []
    var budget = ""
    var budgetBasis = "ανά άτομο"
    var budgetIncludes: Set<String> = []
    var notes = ""
    var dietaryNeeds: Set<String> = []
    var mobility: Set<String> = []
    var stayStyle: String = "Boutique / Hotel"

    var title: String { destination.isEmpty ? "Νέο ταξίδι" : destination }
    var dateSummary: String {
        if dateIsUnknown { return "Ευέλικτες ημερομηνίες" }
        if !startDate.isEmpty || !endDate.isEmpty {
            return [startDate, endDate].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        return "Ημερομηνίες προς επιλογή"
    }

    enum CodingKeys: String, CodingKey {
        case destination, startDate, endDate, dateContext, dateIsUnknown, duration, travelers, group, vibes, interests, preferenceTags, budget, budgetBasis, budgetIncludes, notes, dietaryNeeds, mobility, stayStyle
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        dateContext = try c.decodeIfPresent([String].self, forKey: .dateContext) ?? []
        dateIsUnknown = try c.decodeIfPresent(Bool.self, forKey: .dateIsUnknown) ?? false
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 4
        travelers = try c.decodeIfPresent(Int.self, forKey: .travelers) ?? 2
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Φίλοι"
        vibes = try c.decodeIfPresent(Set<String>.self, forKey: .vibes) ?? ["Πόλη"]
        let savedInterests = try c.decodeIfPresent(Set<String>.self, forKey: .interests) ?? []
        var tags = try c.decodeIfPresent(Set<String>.self, forKey: .preferenceTags) ?? []
        let legacyInterestMap: [String: (String, String?)] = [
            "Φαγητό": ("food", nil), "Αξιοθέατα": ("sights", nil), "Μουσεία": ("sights", "museums"),
            "Bars": ("nightlife", "bars"), "Clubs": ("nightlife", "clubs"), "Αγορές": ("shopping", nil),
            "Εκδρομές": ("outdoors", "day_trips"), "Events": ("events", nil), "Vegan": ("food", "vegan_food"),
            "Καφές": ("coffee", nil)
        ]
        var normalizedInterests = Set<String>()
        for value in savedInterests {
            if let (group, tag) = legacyInterestMap[value] {
                normalizedInterests.insert(group)
                if let tag { tags.insert(tag) }
            } else {
                normalizedInterests.insert(value)
            }
        }
        interests = normalizedInterests
        preferenceTags = tags
        budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? ""
        budgetBasis = try c.decodeIfPresent(String.self, forKey: .budgetBasis) ?? "ανά άτομο"
        budgetIncludes = try c.decodeIfPresent(Set<String>.self, forKey: .budgetIncludes) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dietaryNeeds = try c.decodeIfPresent(Set<String>.self, forKey: .dietaryNeeds) ?? []
        mobility = try c.decodeIfPresent(Set<String>.self, forKey: .mobility) ?? []
        stayStyle = try c.decodeIfPresent(String.self, forKey: .stayStyle) ?? "Boutique / Hotel"
    }
}

private struct TripPreferenceOption: Identifiable {
    let id: String
    let title: String
    let category: String
    let overtureFamilies: [String]
    let videoCategories: [String]
    var children: [TripPreferenceOption] = []
}

private enum TripPreferenceCatalog {
    // These stable IDs map UI choices to Overture's published family taxonomy and
    // the category IDs extracted from the Barcelona video research set.
    static let groups: [TripPreferenceOption] = [
        .init(id: "food", title: "Φαγητό & γεύσεις", category: "food", overtureFamilies: ["food"], videoCategories: ["food"], children: [
            .init(id: "tapas", title: "Tapas", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "catalan_food", title: "Καταλανική κουζίνα", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "seafood", title: "Θαλασσινά", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "street_food", title: "Street food", category: "food", overtureFamilies: ["food"], videoCategories: ["food"]),
            .init(id: "vegan_food", title: "Vegan επιλογές", category: "food", overtureFamilies: ["food"], videoCategories: ["food", "dietary"]),
            .init(id: "desserts", title: "Γλυκά & παγωτό", category: "food", overtureFamilies: ["food", "coffee"], videoCategories: ["food", "coffee"])
        ]),
        .init(id: "nightlife", title: "Nightlife", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars", "clubs"], children: [
            .init(id: "bars", title: "Bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "cocktail_bars", title: "Cocktail bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "wine_bars", title: "Wine bars", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "pubs", title: "Pubs", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"]),
            .init(id: "clubs", title: "Clubs", category: "clubs", overtureFamilies: ["nightlife"], videoCategories: ["clubs"]),
            .init(id: "live_music", title: "Live μουσική", category: "bars", overtureFamilies: ["nightlife"], videoCategories: ["bars"])
        ]),
        .init(id: "coffee", title: "Καφές & brunch", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee", "food"], children: [
            .init(id: "specialty_coffee", title: "Specialty coffee", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee"]),
            .init(id: "bakeries", title: "Φούρνοι & αρτοποιεία", category: "coffee", overtureFamilies: ["coffee"], videoCategories: ["coffee", "food"]),
            .init(id: "brunch", title: "Brunch", category: "food", overtureFamilies: ["coffee", "food"], videoCategories: ["food", "coffee"])
        ]),
        .init(id: "sights", title: "Αξιοθέατα & πολιτισμός", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights", "museums"], children: [
            .init(id: "museums", title: "Μουσεία", category: "museums", overtureFamilies: ["sights"], videoCategories: ["museums"]),
            .init(id: "architecture", title: "Αρχιτεκτονική", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "gaudi", title: "Gaudí", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "historic_places", title: "Ιστορικά σημεία", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "churches", title: "Εκκλησίες & βασιλικές", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"]),
            .init(id: "art_galleries", title: "Γκαλερί τέχνης", category: "sights", overtureFamilies: ["sights"], videoCategories: ["sights"])
        ]),
        .init(id: "outdoors", title: "Φύση & παραλία", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"], children: [
            .init(id: "parks", title: "Πάρκα & κήποι", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"]),
            .init(id: "beaches", title: "Παραλίες", category: "outdoors", overtureFamilies: ["outdoors"], videoCategories: ["outdoors"]),
            .init(id: "viewpoints", title: "Θέα & ηλιοβασίλεμα", category: "outdoors", overtureFamilies: ["outdoors", "sights"], videoCategories: ["outdoors", "sights"]),
            .init(id: "day_trips", title: "Ημερήσιες εκδρομές", category: "day_trips", overtureFamilies: ["outdoors", "transport"], videoCategories: ["day_trips"])
        ]),
        .init(id: "shopping", title: "Αγορές & μικρά μαγαζιά", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"], children: [
            .init(id: "markets", title: "Τοπικές αγορές", category: "shopping", overtureFamilies: ["shopping", "food"], videoCategories: ["shopping", "food"]),
            .init(id: "vintage", title: "Vintage & second hand", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"]),
            .init(id: "bookshops", title: "Βιβλιοπωλεία", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"]),
            .init(id: "local_design", title: "Τοπικό design & χειροτεχνία", category: "shopping", overtureFamilies: ["shopping"], videoCategories: ["shopping"])
        ]),
        .init(id: "events", title: "Events & δραστηριότητες", category: "events", overtureFamilies: ["sights", "nightlife", "other"], videoCategories: ["events", "tickets"], children: [
            .init(id: "concerts", title: "Συναυλίες", category: "events", overtureFamilies: ["nightlife"], videoCategories: ["events"]),
            .init(id: "festivals", title: "Φεστιβάλ", category: "events", overtureFamilies: ["sights", "nightlife"], videoCategories: ["events"]),
            .init(id: "exhibitions", title: "Εκθέσεις", category: "events", overtureFamilies: ["sights"], videoCategories: ["events", "museums"]),
            .init(id: "sports", title: "Αθλητικά events", category: "events", overtureFamilies: ["sights", "outdoors"], videoCategories: ["events"])
        ])
    ]

    static func filters(interests: Set<String>, tags: Set<String>) -> [[String: Any]] {
        groups.flatMap { group in [group] + group.children }
            .filter { interests.contains($0.id) || tags.contains($0.id) }
            .map { option in
                ["id": option.id, "label": option.title, "category": option.category,
                 "overture_families": option.overtureFamilies, "video_categories": option.videoCategories]
            }
    }
}

private struct DestinationHoliday: Identifiable {
    let id = UUID()
    let date: DateComponents  // year, month, day
    let name: String
    let localName: String
    let kind: HolidayKind

    enum HolidayKind: String {
        case publicHoliday = "public_holiday"
        case localCelebration = "local_celebration"
        case festival = "festival"
        case event = "event"

        var symbol: String {
            switch self {
            case .publicHoliday: return "building.columns"
            case .localCelebration: return "sparkles"
            case .festival: return "party.popper"
            case .event: return "calendar.badge.clock"
            }
        }

        var color: Color {
            switch self {
            case .publicHoliday: return Color(hex: "FF685B")
            case .localCelebration: return Color(hex: "FFBE55")
            case .festival: return Color(hex: "A97BFF")
            case .event: return Color(hex: "477461")
            }
        }
    }
}

private struct DestinationSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let query: String
}

@MainActor
private final class DestinationSearchCompleter: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var onResults: (([MKLocalSearchCompletion]) -> Void)?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func search(_ query: String, onResults: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onResults = onResults
        completer.queryFragment = query
    }

    func cancel() {
        onResults = nil
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onResults?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        onResults?([])
    }
}

private struct PillFlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Item {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (items: [Item], height: CGFloat) {
        var items: [Item] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let rawIdeal = subview.sizeThatFits(.unspecified).width
            let idealWidth = rawIdeal.isFinite ? max(0, rawIdeal) : width
            let itemWidth = min(idealWidth, width)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let itemHeight = size.height.isFinite ? max(0, size.height) : 0
            items.append(Item(index: index, origin: CGPoint(x: x, y: y), size: CGSize(width: itemWidth, height: itemHeight)))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, itemHeight)
        }
        return (items, items.isEmpty ? 0 : y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }.filter(\.isFinite)
        let idealWidth = max(0, idealWidths.max() ?? 0)
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(0, proposedWidth ?? idealWidth)
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width.isFinite ? max(0, bounds.width) : 0
        for item in arrange(subviews, width: width).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                      anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
    }
}

// One value keeps the two endpoints consistent during a SwiftUI transaction.
private struct TripCalendarSelection: Equatable {
    private(set) var start: Date?
    private(set) var end: Date?

    func selecting(_ date: Date, calendar: Calendar = .current) -> Self {
        if start == nil || end != nil {
            return Self(start: date, end: nil)
        }
        guard let start else { return Self(start: date, end: nil) }
        // Comparing civil components does not resolve a midnight interval.
        // A later time on the arrival day still starts a new selection.
        let tapped = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let arrival = calendar.dateComponents([.era, .year, .month, .day], from: start)
        let tappedDay = (tapped.era ?? 0, tapped.year ?? 0, tapped.month ?? 0, tapped.day ?? 0)
        let arrivalDay = (arrival.era ?? 0, arrival.year ?? 0, arrival.month ?? 0, arrival.day ?? 0)
        return tappedDay <= arrivalDay ? Self(start: date, end: nil) : Self(start: start, end: date)
    }

    var nights: Int { nightCount(calendar: .current) }

    func nightCount(calendar: Calendar) -> Int {
        guard let start, let end, end > start,
              let first = calendar.ordinality(of: .day, in: .era, for: start),
              let last = calendar.ordinality(of: .day, in: .era, for: end),
              last > first else { return 0 }
        // Count civil days, including DST transitions. This avoids the date
        // interval DateComponents calculation on the second-selection path.
        return last - first
    }
}

// Draft dates belong to the sheet. A day tap must not invalidate the entire
// TripFlowView (maps, form, storage observers and all its sheet builders).
private struct TripCalendarSheet: View {
    let destination: String
    let calendarHolidays: [DestinationHoliday]
    let isLoadingHolidays: Bool
    let holidayStatus: String
    let onYearChange: (Date) -> Void
    let onApply: (Date, Date, Int) -> Void
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: TripCalendarSelection
    @State private var calendarDisplayedMonth: Date

    init(destination: String, start: Date?, end: Date?, holidays: [DestinationHoliday],
         isLoading: Bool, status: String, onYearChange: @escaping (Date) -> Void,
         onApply: @escaping (Date, Date, Int) -> Void, onCancel: @escaping () -> Void) {
        self.destination = destination
        self.calendarHolidays = holidays
        self.isLoadingHolidays = isLoading
        self.holidayStatus = status
        self.onYearChange = onYearChange
        self.onApply = onApply
        self.onCancel = onCancel
        _selection = State(initialValue: TripCalendarSelection(start: start, end: end))
        _calendarDisplayedMonth = State(initialValue: start ?? Date())
    }

    private var calendarRangeStart: Date? { selection.start }
    private var calendarRangeEnd: Date? { selection.end }
    private var calendarNightCount: Int { selection.nights }

    var body: some View {
        VStack(spacing: 0) {
            calendarContent
            calendarFooter
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { NSLog("[TrippyCalendar selection-v3] opened") }
        .onChange(of: selection) { _, _ in
            NSLog("[TrippyCalendar selection-v3] selection observed after view update")
        }
        .onChange(of: calendarDisplayedMonth) { old, new in
            if Calendar.current.component(.year, from: old) != Calendar.current.component(.year, from: new) {
                onYearChange(new)
            }
        }
    }

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ημερομηνίες ταξιδιού")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .foregroundStyle(AppPalette.ink)
                    Text(destination)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                HStack(spacing: 12) {
                    calendarSelectionLabel("ΑΦΙΞΗ", date: calendarRangeStart, active: calendarRangeStart == nil)
                    Image(systemName: "arrow.right").foregroundStyle(AppPalette.secondaryInk)
                    calendarSelectionLabel("ΑΝΑΧΩΡΗΣΗ", date: calendarRangeEnd, active: calendarRangeStart != nil && calendarRangeEnd == nil)
                }
                .padding(15)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 16) {
                    HStack {
                        calendarMonthArrow(-1)
                        Spacer(minLength: 8)
                        Text(calendarDisplayedMonth, format: .dateTime.month(.wide).year())
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundStyle(AppPalette.ink)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        calendarMonthArrow(1)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(calendarWeekdayLabels.enumerated()), id: \.offset) { _, weekday in
                            Text(weekday.prefix(2))
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // A month has at most six rows. Eager rows keep the sheet's
                    // layout stable when the range changes during an animation.
                    let days = daysForDisplayedMonth()
                    VStack(spacing: 6) {
                        ForEach(0..<((days.count + 6) / 7), id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { column in
                                    let index = row * 7 + column
                                    if index < days.count, let day = days[index] {
                                        calendarDayButton(day)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity).frame(height: 44)
                                    }
                                }
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76), value: selection)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendarDisplayedMonth)
                }
                .padding(15)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if isLoadingHolidays { ProgressView().tint(AppPalette.brand).controlSize(.small) }
                        else { Image(systemName: "calendar.badge.clock").foregroundStyle(AppPalette.brand) }
                        Text(isLoadingHolidays ? "Φόρτωση αργιών…" : "Στο ημερολόγιο")
                            .font(.custom("PlusJakartaSans-Bold", size: 13))
                            .foregroundStyle(AppPalette.ink)
                    }
                    ForEach(holidaysForDisplayedMonth) { holiday in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(holiday.date.day ?? 0)")
                                .font(.custom("PlusJakartaSans-Bold", size: 12))
                                .foregroundStyle(holiday.kind.color)
                                .frame(width: 30, height: 30)
                                .background(holiday.kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(holiday.localName)
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                                    .foregroundStyle(AppPalette.ink)
                                Text(holiday.name)
                                    .font(.custom("PlusJakartaSans-Regular", size: 10))
                                    .foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: holiday.kind.symbol).foregroundStyle(holiday.kind.color)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !isLoadingHolidays && holidaysForDisplayedMonth.isEmpty {
                        Text(calendarHolidays.isEmpty ? holidayStatus : "Δεν καταγράφονται αργίες αυτόν τον μήνα.")
                            .font(.custom("PlusJakartaSans-Regular", size: 12))
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    if !calendarHolidays.isEmpty {
                        Link("Πηγή αργιών: Nager.Date", destination: URL(string: "https://date.nager.at")!)
                            .font(.custom("PlusJakartaSans-SemiBold", size: 10))
                            .foregroundStyle(AppPalette.brand)
                    }
                    Text("Οι αργίες δεν σημαίνουν αυτόματα κλείσιμο χώρων. Οι τοπικές εκδηλώσεις ελέγχονται στην έρευνα.")
                        .font(.custom("PlusJakartaSans-Regular", size: 10))
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var calendarFooter: some View {
            VStack(spacing: 12) {
                Text(verbatim: calendarSelectionSummary)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 20)
                HStack(spacing: 12) {
                    Button("Άκυρο", action: onCancel)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 90, height: 48)
                        .background(AppPalette.surface, in: Capsule())
                    Button {
                        guard let start = selection.start, let end = selection.end,
                              selection.nights > 0 else { return }
                        NSLog("[TrippyCalendar selection-v3] applying selection")
                        onApply(start, end, selection.nights)
                    } label: {
                        Text("Εφαρμογή ημερομηνιών")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppPalette.brand, in: Capsule())
                    }
                    .disabled(calendarNightCount < 1)
                    .opacity(calendarNightCount < 1 ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppPalette.canvas)
            // Day selection animates only the grid, never sheet safe-area layout.
            .transaction { $0.animation = nil }
    }

    private var calendarSelectionSummary: String {
        guard selection.start != nil else { return "Διάλεξε ημερομηνία άφιξης" }
        guard selection.end != nil else { return "Τώρα διάλεξε αναχώρηση" }
        let nights = selection.nights
        return "\(nights) διανυκτερεύσεις · \(nights + 1) ημέρες"
    }

    private func calendarSelectionLabel(_ title: String, date: Date?, active: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.custom("PlusJakartaSans-SemiBold", size: 9))
                .tracking(1)
                .foregroundStyle(active ? AppPalette.brand : AppPalette.secondaryInk)
            if let date {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.custom("PlusJakartaSans-Bold", size: 16))
                    .foregroundStyle(AppPalette.ink)
            } else {
                Text("Επίλεξε")
                    .font(.custom("PlusJakartaSans-Bold", size: 16))
                    .foregroundStyle(active ? AppPalette.brand : AppPalette.secondaryInk)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 68)
        .padding(.vertical, 10)
        .background(active ? AppPalette.brand.opacity(0.06) : AppPalette.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? AppPalette.brand.opacity(0.3) : AppPalette.secondaryInk.opacity(0.12), lineWidth: 1))
    }

    private func calendarMonthArrow(_ direction: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                calendarDisplayedMonth = Calendar.current.date(byAdding: .month, value: direction, to: calendarDisplayedMonth) ?? calendarDisplayedMonth
            }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppPalette.ink)
                .frame(width: 44, height: 44)
                .background(AppPalette.canvas, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Προηγούμενος μήνας" : "Επόμενος μήνας")
    }

    private var calendarWeekdayLabels: [String] {
        let calendar = Calendar.current
        let labels = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(labels[first...] + labels[..<first])
    }

    private var holidaysForDisplayedMonth: [DestinationHoliday] {
        let components = Calendar.current.dateComponents([.year, .month], from: calendarDisplayedMonth)
        return calendarHolidays.filter {
            $0.date.year == components.year && $0.date.month == components.month
        }.sorted { ($0.date.day ?? 0) < ($1.date.day ?? 0) }
    }

    private func calendarDayButton(_ date: Date) -> some View {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let isStart = calendarRangeStart.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
        let isEnd = calendarRangeEnd.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
        let isInRange: Bool = {
            guard let start = calendarRangeStart, let end = calendarRangeEnd else { return false }
            return (date > start || isStart) && (date < end || isEnd)
        }()
        let holiday = calendarHolidays.first {
            $0.date.year == components.year && $0.date.month == components.month && $0.date.day == components.day
        }
        return Button {
            let choosingReturn = selection.start != nil && selection.end == nil
            NSLog("[TrippyCalendar selection-v3] tap begin: %@", choosingReturn ? "return" : "arrival")
            let currentSelection = selection
            let nextSelection = currentSelection.selecting(date)
            NSLog("[TrippyCalendar selection-v3] next selection calculated")
            selection = nextSelection
            NSLog("[TrippyCalendar selection-v3] tap state committed")
        } label: {
            VStack(spacing: 2) {
                Text("\(components.day ?? 0)")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                    .foregroundStyle(isStart || isEnd ? Color.white : AppPalette.ink)
                Circle()
                    .fill(holiday?.kind.color ?? Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isStart || isEnd ? AppPalette.brand :
                    (isInRange ? AppPalette.brand.opacity(0.12) : Color.clear),
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(holiday.map { "\(components.day ?? 0), \($0.localName)" } ?? "\(components.day ?? 0)")
    }

    private func daysForDisplayedMonth() -> [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: calendarDisplayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday else { return [] }
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0
        return Array(repeating: nil, count: leading) + (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }.map { Optional($0) }
    }

}

private struct HolidayLocation {
    let query: String
    let countryCode: String
    let regionCode: String?
    let displayName: String
}

private struct PublicHolidayResponse: Decodable {
    let date: String
    let localName: String
    let name: String
    let global: Bool
    let counties: [String]?
    let types: [String]
}

private struct ResearchOperation: Identifiable {
    let step: Int
    var detail: String
    var id: Int { step }
    var title: String {
        switch step {
        case 1: "Σύνδεση"
        case 2: "Ανακάλυψη"
        case 3: "Έλεγχος επιλογών"
        case 4: "Σύνθεση προγράμματος"
        default: "Αποθήκευση"
        }
    }
    var symbol: String {
        switch step {
        case 1: "network"
        case 2: "globe.europe.africa"
        case 3: "checkmark.shield"
        case 4: "map"
        default: "tray.and.arrow.down"
        }
    }
    static let planned = [
        ResearchOperation(step: 1, detail: "Συνδεόμαστε με την υπηρεσία έρευνας."),
        ResearchOperation(step: 2, detail: "Βρίσκουμε μέρη που ταιριάζουν σε εσένα."),
        ResearchOperation(step: 3, detail: "Ελέγχουμε ημερομηνίες, ωράρια και ανάγκες."),
        ResearchOperation(step: 4, detail: "Οργανώνουμε ημέρες, διαδρομές και κόστος."),
        ResearchOperation(step: 5, detail: "Κρατάμε το πλάνο και τις επιλογές σου.")
    ]
    static func completedPhases(_ values: [Int]) -> Set<Int> {
        Set(values.filter { (2...4).contains($0) })
    }
    static func phase(serverStep: String, task: String) -> Int? {
        if serverStep == "searching_web" || serverStep == "synthesizing_patch" {
            return task.hasPrefix("selected-checks-") ? 3 : 2
        }
        if serverStep == "composing" { return task == "source_based_draft" ? 2 : 4 }
        return nil
    }
}

private enum ResearchRequestStage: String {
    case preflight, start, status
}

private enum ResearchRequestError: Error, Equatable {
    case missingJob
    case httpStatus(Int, ResearchRequestStage)
    case invalidResponse(ResearchRequestStage)
    case configurationUnavailable([String])

    var requiresNewJob: Bool { self == .missingJob }
    var message: String {
        switch self {
        case .missingJob:
            return "Η υπηρεσία δεν βρίσκει πλέον αυτό το αίτημα, συνήθως μετά από επανεκκίνηση ή ενημέρωση. Μπορείς να ξεκινήσεις νέα έρευνα. Το πλάνο και οι επιλογές που έχεις αποθηκεύσει διατηρούνται."
        case .configurationUnavailable:
            return "Η υπηρεσία έρευνας δεν έχει ολοκληρώσει τη ρύθμισή της. Χρειάζεται έλεγχος των ρυθμίσεων πριν ξεκινήσει νέα έρευνα."
        case .httpStatus(let status, _):
            if [408, 429, 500, 502, 503, 504].contains(status) {
                return "Η υπηρεσία έρευνας δεν είναι διαθέσιμη αυτή τη στιγμή. Το αποθηκευμένο αίτημα διατηρείται· έλεγξε ξανά την κατάστασή του σε λίγο."
            }
            if status == 401 || status == 403 { return "Η υπηρεσία δεν επέτρεψε την πρόσβαση. Χρειάζεται έλεγχος της σύνδεσης της εφαρμογής με την υπηρεσία." }
            if status == 422 { return "Η υπηρεσία δεν δέχτηκε τα στοιχεία του ταξιδιού. Έλεγξε τον προορισμό και τις ημερομηνίες." }
            return "Η υπηρεσία απάντησε με σφάλμα. Χρειάζεται έλεγχος της σύνδεσης ή της έκδοσής της."
        case .invalidResponse:
            return "Η υπηρεσία απάντησε χωρίς έγκυρα στοιχεία έρευνας. Χρειάζεται έλεγχος της έκδοσής της. Το αποθηκευμένο αίτημα διατηρείται."
        }
    }
    var diagnostic: String {
        switch self {
        case .missingJob: "status: HTTP 404, job_not_found"
        case .httpStatus(let status, let stage): "\(stage.rawValue): HTTP \(status)"
        case .invalidResponse(let stage): "\(stage.rawValue): invalid_response"
        case .configurationUnavailable(let fields): "preflight: configuration_required\n" + fields.joined(separator: "\n")
        }
    }
}

private enum ResearchTransport {
    static func checkedJSON(_ data: Data, response: URLResponse, stage: ResearchRequestStage, checkResearchReadiness: Bool = true) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else { throw ResearchRequestError.invalidResponse(stage) }
        if stage == .status && http.statusCode == 404 { throw ResearchRequestError.missingJob }
        let accepted = stage == .start ? [200, 202] : [200]
        guard accepted.contains(http.statusCode) else { throw ResearchRequestError.httpStatus(http.statusCode, stage) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResearchRequestError.invalidResponse(stage)
        }
        if stage == .preflight && checkResearchReadiness && object["research_ready"] as? Bool == false {
            let fields = (object["configuration_issues"] as? [String] ?? []).filter {
                !$0.isEmpty && $0.count <= 80 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
            }
            throw ResearchRequestError.configurationUnavailable(fields)
        }
        return object
    }
    static func shouldRetryStatus(_ error: Error) -> Bool {
        if case ResearchRequestError.httpStatus(let code, .status) = error {
            return [408, 429, 500, 502, 503, 504].contains(code)
        }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
    }
    // Only read-only polling is retried. A research POST is dispatched once.
    static func status(url: URL,
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
        pause: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> [String: Any] {
        let delays: [Double] = [2, 4, 8]
        for attempt in 0...delays.count {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 60
            do {
                let (data, response) = try await transport(request)
                return try checkedJSON(data, response: response, stage: .status)
            } catch {
                guard shouldRetryStatus(error), attempt < delays.count else { throw error }
                try await pause(delays[attempt])
            }
        }
        throw ResearchRequestError.invalidResponse(.status)
    }
}

private enum ResearchDiagnostics {
    static func phaseStates(_ root: [String: Any]) -> [Int: String] {
        let report = root["pipeline_report"] as? [String: Any] ?? [:]
        let diagnostics = root["diagnostics"] as? [String: Any] ?? [:]
        let raw = report["phase_states"] as? [String: String] ?? diagnostics["phase_states"] as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard ["2", "3", "4"].contains(key), let phase = Int(key), ["completed", "failed", "skipped", "empty"].contains(value) else { return nil }
            return (phase, value)
        })
    }
    static func phaseDetail(_ state: String?) -> String? {
        switch state {
        case "failed": "Απέτυχε · δες τα στοιχεία υποστήριξης"
        case "skipped": "Παραλείφθηκε · δες τα στοιχεία έρευνας"
        case "empty": "Δεν προέκυψαν στάσεις για το πρόγραμμα"
        default: nil
        }
    }
    static func identifier(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 120,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.$[]".contains($0)) }) else { return nil }
        return text
    }
    static func summary(_ root: [String: Any]) -> String? {
        let report = root["pipeline_report"] as? [String: Any] ?? [:]
        let diagnostics = root["diagnostics"] as? [String: Any] ?? report["diagnostics"] as? [String: Any] ?? [:]
        guard !report.isEmpty || !diagnostics.isEmpty else { return nil }
        var lines: [String] = []
        if let support = identifier(root["support_id"] ?? report["support_id"]) { lines.append("Support ID: " + support) }
        if let build = identifier(root["build_commit"] ?? report["build_commit"]) { lines.append("Build: " + build) }
        if let count = diagnostics["completed_provider_stages"] as? Int { lines.append("Ολοκληρωμένες κλήσεις/στάδια: \(count)") }
        if let count = diagnostics["place_count"] as? Int ?? report["places_researched"] as? Int { lines.append("Επιλογές: \(count)") }
        if let count = diagnostics["scheduled_stops"] as? Int ?? report["scheduled_stops"] as? Int { lines.append("Στάσεις: \(count)") }
        if let elapsed = diagnostics["elapsed_seconds"] as? Double, elapsed.isFinite, (0...86400).contains(elapsed) { lines.append("Διάρκεια: \(Int(elapsed)) δευτ.") }
        for (phase, state) in phaseStates(root).sorted(by: { $0.key < $1.key }) { lines.append("Βήμα \(phase): \(state)") }
        let failures = report["failed_stages"] as? [[String: Any]] ?? []
        if let failure = diagnostics["last_failure"] as? [String: Any] ?? failures.first {
            lines.append("Αποτυχία:")
            for key in ["task", "stage", "code", "error_type", "field_path", "parameter", "reason"] {
                if let value = identifier(failure[key]) { lines.append("\(key): \(value)") }
            }
            if let status = failure["http_status"] as? Int, (100...599).contains(status) { lines.append("HTTP: \(status)") }
        }
        for event in (diagnostics["events"] as? [[String: Any]] ?? []).suffix(12) {
            let parts = ["event", "task", "stage", "reason"].compactMap { identifier(event[$0]) }
            if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    static func hasPlaces(_ root: [String: Any]) -> Bool {
        !(root["places"] as? [[String: Any]] ?? []).isEmpty
    }
}

private struct Trip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var brief: TripBrief
    var research: String? = nil
    var researchJobID: String? = nil
    var researchBridgeURL: String? = nil
    mutating func forgetResearchJob(matching id: String) {
        guard researchJobID == id else { return }
        researchJobID = nil
        researchBridgeURL = nil
    }
    var updatedAt = Date()
    var scheduleOrderByDate: [String: [String]]? = nil
    var reactionsByItemID: [String: String]? = nil
    var mapCoordinatesByPlaceID: [String: StoredPlaceCoordinate]? = nil
    var scheduleEditsByItemID: [String: ScheduleItemEdit]? = nil
    var checklistDoneIDs: Set<String>? = nil
    var budgetEntries: [TripBudgetEntry]? = nil
    var customName: String? = nil
    var savedPins: [PersonalPlace]? = nil
    var title: String { customName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? brief.title }

}

private struct ScheduleItemEdit: Codable, Equatable {
    var time: String? = nil
    var costPerPerson: String? = nil
}

private struct TripBudgetEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String = "Νέα δαπάνη"
    var amount: String = ""
    var basis: String = "group"
}

private struct StoredPlaceCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let source: String
    let matchedAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

@MainActor
private final class CurrentLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var failureMessage: String?

    private let manager = CLLocationManager()
    private var requestPending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        failureMessage = nil
        requestPending = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            requestPending = false
            failureMessage = "Ενεργοποίησε την Πρόσβαση τοποθεσίας για το Trippy από τις Ρυθμίσεις του iPhone."
        @unknown default:
            requestPending = false
            failureMessage = "Δεν είναι διαθέσιμη η πρόσβαση στην τρέχουσα τοποθεσία."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard requestPending else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            requestPending = false
            failureMessage = "Ενεργοποίησε την Πρόσβαση τοποθεσίας για το Trippy από τις Ρυθμίσεις του iPhone."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        requestPending = false
        guard let freshLocation = locations.last, freshLocation.horizontalAccuracy >= 0 else {
            failureMessage = "Το iPhone δεν επέστρεψε έγκυρη τοποθεσία. Δοκίμασε ξανά σε λίγο."
            return
        }
        location = freshLocation
        failureMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requestPending = false
        failureMessage = "Δεν ήταν δυνατή η λήψη της τοποθεσίας. Έλεγξε το GPS και δοκίμασε ξανά."
    }
}

// Stored stop indexes belong to one research document. Rebind them by place,
// preserving user choices before replacing that document.
private enum PlanImportReconciliation {
    static func apply(_ incoming: [String: Any], to trip: inout Trip) -> [String: Any] {
        guard let data = trip.research?.data(using: .utf8),
              let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return incoming }
        func days(_ root: [String: Any]) -> [[String: Any]] {
            (root["itinerary"] as? [String: Any])?["days"] as? [[String: Any]] ?? []
        }
        func stops(_ day: [String: Any]) -> [[String: Any]] {
            (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
        }
        func date(_ day: [String: Any], _ index: Int) -> String { day["date"] as? String ?? "day-\(index + 1)" }
        var result = incoming
        var newDays = days(incoming)
        var places = incoming["places"] as? [[String: Any]] ?? []
        let oldPlaces = old["places"] as? [[String: Any]] ?? []
        var retainedIDs = Set<String>()
        var mapping: [String: String] = [:]
        var pending: [[String: Any]] = []
        for (oldIndex, oldDay) in days(old).enumerated() {
            let key = date(oldDay, oldIndex)
            let oldStops = stops(oldDay)
            let oldIDs = oldStops.indices.map { "stop|\(key)|\($0)" }
            let order = trip.scheduleOrderByDate?[key]
            let edited = oldIDs.filter { trip.scheduleEditsByItemID?[$0] != nil || trip.reactionsByItemID?[$0] != nil || trip.mapCoordinatesByPlaceID?[$0] != nil }
            guard order != nil || !edited.isEmpty else { continue }
            let newIndex: Int
            if let index = newDays.enumerated().first(where: { date($0.element, $0.offset) == key })?.offset { newIndex = index }
            else { newIndex = newDays.count; newDays.append(["date": key, "stops": []]) }
            var newStops = stops(newDays[newIndex])
            var claimed = Set<Int>()
            // Only referenced old stops need migration. Anonymous anchors retain their
            // old contents and are explicitly pending rather than binding by index.
            for id in Set((order ?? []) + edited).sorted() where id.hasPrefix("stop|") {
                guard let oldStopIndex = Int(id.split(separator: "|").last ?? ""), oldStops.indices.contains(oldStopIndex) else { continue }
                let oldStop = oldStops[oldStopIndex]
                let placeID = oldStop["place_id"] as? String
                let target: Int
                if let placeID, let index = newStops.indices.first(where: { !claimed.contains($0) && newStops[$0]["place_id"] as? String == placeID }) { target = index }
                else {
                    target = newStops.count
                    var retained = oldStop
                    retained["retained_user_anchor"] = true
                    newStops.append(retained)
                    if let placeID { retainedIDs.insert(placeID) }
                }
                claimed.insert(target)
                mapping[id] = "stop|\(key)|\(target)"
            }
            if let order {
                var rebound = order.map { mapping[$0] ?? $0 }
                for id in order where id.hasPrefix("place|") { retainedIDs.insert(String(id.dropFirst(6))) }
                let selectedPlaces = Set(rebound.compactMap { id -> String? in
                    if id.hasPrefix("place|") { return String(id.dropFirst(6)) }
                    guard let i = Int(id.split(separator: "|").last ?? ""), newStops.indices.contains(i) else { return nil }
                    return newStops[i]["place_id"] as? String
                })
                let previousPlaces = Set(oldStops.compactMap { $0["place_id"] as? String })
                // Append fresh proposals, while preserving deliberate removals.
                for i in newStops.indices {
                    guard let pid = newStops[i]["place_id"] as? String,
                          !selectedPlaces.contains(pid), !previousPlaces.contains(pid) else { continue }
                    rebound.append("stop|\(key)|\(i)")
                }
                trip.scheduleOrderByDate?[key] = rebound
            }
            newDays[newIndex].removeValue(forKey: "activities")
            newDays[newIndex].removeValue(forKey: "items")
            newDays[newIndex]["stops"] = newStops
            pending.append(["code": "local_schedule_needs_review", "date": key])
        }
        let oldEdits = trip.scheduleEditsByItemID ?? [:]
        trip.scheduleEditsByItemID = Dictionary(oldEdits.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let oldReactions = trip.reactionsByItemID ?? [:]
        trip.reactionsByItemID = Dictionary(oldReactions.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let oldPins = trip.mapCoordinatesByPlaceID ?? [:]
        trip.mapCoordinatesByPlaceID = Dictionary(oldPins.map { (mapping[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        // Preserve saved place references even when a research pass omits them.
        retainedIDs.formUnion(oldReactions.keys.filter { $0.hasPrefix("place|") }.map { String($0.dropFirst(6)) })
        retainedIDs.formUnion((trip.mapCoordinatesByPlaceID ?? [:]).keys.filter { !$0.hasPrefix("stop|") })
        for place in oldPlaces {
            guard let id = place["id"] as? String, retainedIDs.contains(id), !places.contains(where: { $0["id"] as? String == id }) else { continue }
            var retained = place; retained["retained_from_previous_research"] = true; places.append(retained)
        }
        if !pending.isEmpty {
            var itinerary = result["itinerary"] as? [String: Any] ?? [:]
            itinerary["days"] = newDays; result["itinerary"] = itinerary
            var validation = result["plan_validation"] as? [String: Any] ?? [:]
            validation["pending"] = (validation["pending"] as? [[String: Any]] ?? []) + pending
            validation["status"] = "partial"; result["plan_validation"] = validation
            result["delivery_status"] = "partial"
        }
        result["places"] = places
        if places.count > (incoming["places"] as? [[String: Any]] ?? []).count {
            let sources = incoming["sources"] as? [[String: Any]] ?? []
            result["sources"] = sources + (old["sources"] as? [[String: Any]] ?? []).filter { row in
                !sources.contains { $0["id"] as? String == row["id"] as? String }
            }
        }
        return result
    }
}

private enum TripStorage {
    static let key = "trippy.native.trips.v1"

    static func load() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let trips = try? JSONDecoder().decode([Trip].self, from: data) else { return [] }
        return trips
    }

    static func save(_ trips: [Trip]) {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum BridgeTokenStore {
    private static let service = "com.dimitrisymeonidis.trippy.bridge"
    private static let account = "places-access-token"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    static func save(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var entry = query
        entry[kSecValueData as String] = Data(value.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(entry as CFDictionary, nil)
    }
}

private enum PlacesConnectionState {
    case idle
    case checking
    case connected
    case missingToken
    case rejectedToken
    case missingGoogleKey
    case rateLimited
    case gatewayError(String)
    case googleError(String)
}

private struct PlacesGatewayHealthResponse: Decodable {
    let gateway: String?
    let googlePlaces: String?
    let error: String?
    let errorCode: String?
    let message: String?
}

private struct TripFlowView: View {
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @AppStorage("trippy.bridgeHost") private var bridgeHost = "https://trippy-research-89fm.onrender.com/"
    @State private var bridgeToken = BridgeTokenStore.load()
    @State private var trips = TripStorage.load()
    @State private var rootTab = "map"
    @State private var librarySection = "Trips"
    @State private var libraryCity: String?
    @State private var libraryQuery = ""
    @State private var librarySearchVisible = false
    @State private var showTripMapFilters = false
    @State private var focusedSavedPlaceID: String?
    @State private var savedPlaces = PersonalPlaceStorage.load()
    @State private var cityCoordinates: [String: StoredPlaceCoordinate] = PersonalPlaceStorage.loadCities()
    @State private var showTripDetails = false
    @State private var detailsDetent: PresentationDetent = .height(116)
    @State private var showRenameTrip = false
    @State private var tripNameDraft = ""
    @State private var routePreviewMode = "walking"
    @State private var selectedMapDay: Int?
    @State private var mapLayers: Set<String> = ["planned", "recommended", "saved"]
    @State private var mapCategories = Set(MapPlaceCategory.allCases)

    @State private var brief = TripBrief()
    @State private var activeTripID: UUID?
    @State private var selectedCard = 0
    @State private var selectedScrollID: Int? = 0
    @State private var stage: TripStage = .library
    @State private var briefStep = 0
    @State private var briefProgress: CGFloat = 0
    @State private var cardDrag: CGFloat = 0
    @State private var briefReveal: CGFloat = 0
    @State private var isRevealingBrief = false
    @State private var gestureTripID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var interfaceTypeSize
    @Environment(\.scenePhase) private var appScenePhase
    @State private var socialSources = SocialLibraryStore.load().sources
    @State private var socialPlaces = SocialLibraryStore.load().places
    @State private var travelNotes = SocialLibraryStore.load().notes
    @State private var selectedSocialSource: ImportedSocialSource?
    @State private var selectedTravelNoteID: UUID?
    @State private var processingShares = false
    @State private var importSourceURL = ""
    @State private var showImportLink = false
    @State private var showAddSocialPlace = false
    @State private var socialPlaceName = ""
    @State private var socialPlaceSummary = ""
    @State private var socialEvidenceID = ""
    @State private var socialPlaceSourceID: UUID?
    @State private var socialPlaceCity = ""
    @State private var importLinkError: String?
    @State private var importText = ""
    @State private var importError: String?
    @State private var toast: String?
    @State private var showPromptSheet = false
    @State private var showResearchFileImporter = false
    @State private var pace = 0.35
    @State private var selectedRegion = "Ευρώπη"
    @State private var workspaceTab = "Πρόγραμμα"
    @State private var planPlaceQuery = ""
    @State private var planPlaceCategory: MapPlaceCategory? = nil
    @State private var planLikedOnly = false
    @State private var showBridgeSettings = false
    @State private var showPlacesSettings = false
    @State private var placesConnectionState: PlacesConnectionState = .idle
    @State private var expandedDayIndices: Set<Int> = []
    @State private var expandedScheduleItemIDs: Set<String> = []
    @State private var expandedPlanPlaceIDs: Set<String> = []
    @State private var locatingPlanItemID: String?
    @State private var selectedScheduleDayIndex: Int? = nil
    @State private var activeScheduleDate: String?
    @State private var alternativesForItemID: String?
    @State private var resolvedCoordinates: [String: CLLocationCoordinate2D] = [:]
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var isResolvingCoordinates = false
    @State private var pendingPrompt: String?
    @State private var selectedResearchLayer: ResearchLayer = .foundation
    @State private var isResearching = false
    @State private var showLiveResearchSheet = false
    @State private var completedResearchSteps: Set<Int> = []
    @State private var researchNeedsServiceUpdate = false
    @State private var researchOpenSettingsAfterDismiss = false
    @State private var researchSaved = false
    @State private var researchPartial = false
    @State private var researchDestination = ""
    @State private var researchResultTripID: UUID?
    @State private var liveResearchStep = 1
    @State private var liveResearchError: String? = nil
    @State private var liveResearchDiagnostic: String? = nil
    @State private var researchNeedsNewRequest = false
    @State private var researchPhaseStates: [Int: String] = [:]
    @State private var liveResearchTask: Task<Void, Never>? = nil
    @State private var calendarDisplayedMonth = Date()
    @State private var destinationSuggestions: [DestinationSuggestion] = []
    @State private var destinationSearchTask: Task<Void, Never>?
    @State private var destinationCompleter = DestinationSearchCompleter()
    @State private var destinationConfirmedQuery = ""
    @FocusState private var destinationFieldFocused: Bool
    @State private var showCalendarPicker = false
    @State private var calendarHolidays: [DestinationHoliday] = []
    @State private var isLoadingHolidays = false
    @State private var holidayStatus = "Επίλεξε προορισμό για να φορτωθούν οι αργίες."
    @State private var resolvedDestination = ""
    @State private var holidayCache: [String: [DestinationHoliday]] = [:]
    @State private var resolvedHolidayLocation: HolidayLocation?
    @State private var holidayTask: Task<Void, Never>?
    @State private var researchOperations: [ResearchOperation] = []
    @State private var recoverableResearch: [String: Any]?
    @State private var recoveryContext: [String: Any] = [:]

    private var prompt: String {
        pendingPrompt ?? ResearchPrompt.make(
            layer: selectedResearchLayer,
            brief: brief,
            existingResearch: activeTrip?.research,
            selectedRegion: selectedRegion,
            pace: pace < 0.34 ? "χαλαρός" : (pace > 0.66 ? "εντατικός" : "ισορροπημένος")
        )
    }
    private var activeTrip: Trip? { trips.first(where: { $0.id == activeTripID }) }
    private var bridgeBaseURL: String {
        let endpoint = bridgeHost.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint.lowercased().hasPrefix("https://") || endpoint.lowercased().hasPrefix("http://") {
            return endpoint
        }
        return "http://\(endpoint):8080"
    }

    var body: some View {
        ZStack {
            AppPalette.canvas.ignoresSafeArea()
            if stage == .brief {
                briefScreen
                    .background(AppPalette.canvas)
                    .transition(.move(edge: .bottom))
            } else {
                TabView(selection: $rootTab) {
                    Group {
                        if stage == .workspace { tripMapWorkspace } else { personalMapHome }
                    }
                    .tag("map")
                    .tabItem { Label("Map", systemImage: "map") }
                    modernLibrary
                        .tag("library")
                        .tabItem { Label("Library", systemImage: "square.stack") }
                }
                .tint(AppPalette.brand)
            }
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppPalette.inverseInk)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(AppPalette.ink, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: brief.destination) { _, destination in
            if !brief.dateContext.isEmpty { brief.dateContext = [] }
            if destination.trimmingCharacters(in: .whitespacesAndNewlines) != destinationConfirmedQuery {
                searchDestinations(destination)
            } else {
                destinationSuggestions = []
            }
            resolvedHolidayLocation = nil
            resolvedDestination = ""
            calendarHolidays = []
            loadHolidays(for: destination, debounce: true)
        }
        .onChange(of: stage) { _, new in
            if new == .brief { briefStep = 0; showTripDetails = false; loadHolidays(for: brief.destination) }
            if new == .workspace { rootTab = "map"; selectedMapDay = nil }

        }
        .task { syncShareTargets(); await importSharedSources() }
        .onChange(of: appScenePhase) { _, phase in if phase == .active { Task { await importSharedSources() } } }
        .onChange(of: trips) { _, _ in syncShareTargets() }
        .onChange(of: socialSources) { _, _ in persistSocialLibrary() }
        .onChange(of: socialPlaces) { _, _ in persistSocialLibrary() }
        .onChange(of: travelNotes) { _, _ in persistSocialLibrary(); syncShareTargets() }
        .onChange(of: bridgeToken) { _, value in BridgeTokenStore.save(value) }
        .sheet(item: $selectedSocialSource) { source in socialSourceDetail(source) }
        .sheet(isPresented: Binding(get: { selectedTravelNoteID != nil }, set: { if !$0 { selectedTravelNoteID = nil } })) {
            if let id = selectedTravelNoteID { travelNoteDetail(id) }
        }
        .sheet(isPresented: $showImportLink) { importLinkSheet }
        .onChange(of: rootTab) { _, tab in if tab == "library" { showTripDetails = false; showTripMapFilters = false } }
        .onChange(of: savedPlaces) { _, places in PersonalPlaceStorage.save(places) }
        .alert("Όνομα ταξιδιού", isPresented: $showRenameTrip) {
            TextField("Το όνομα του ταξιδιού σου", text: $tripNameDraft)
            Button("Αποθήκευση") {
                if let index = trips.firstIndex(where: { $0.id == activeTripID }) {
                    trips[index].customName = tripNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    TripStorage.save(trips)
                }
            }
            Button("Ακύρωση", role: .cancel) { }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .animation(reduceMotion ? nil : .spring(response: 0.68, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.48, dampingFraction: 0.78), value: selectedCard)
        .sheet(isPresented: $showPromptSheet) { promptSheet }
        .sheet(isPresented: $showBridgeSettings) { bridgeSettingsSheet }
        .sheet(isPresented: $showPlacesSettings) { placesSettingsSheet }
        .fullScreenCover(isPresented: $showLiveResearchSheet, onDismiss: {
            if researchOpenSettingsAfterDismiss {
                researchOpenSettingsAfterDismiss = false
                showBridgeSettings = true
            }
        }) { liveResearchSheet }
        .sheet(isPresented: $showCalendarPicker) { calendarPickerSheet }
        .alert("Δεν έγινε εισαγωγή της έρευνας", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "Έλεγξε το JSON και δοκίμασε ξανά.") }
        .fileImporter(isPresented: $showResearchFileImporter, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    importText = try String(contentsOf: url, encoding: .utf8)
                    importResearch()
                    if importError == nil { showPromptSheet = false }
                } catch {
                    importError = "Δεν ήταν δυνατή η ανάγνωση του αρχείου. Δοκίμασε UTF-8 αρχείο .json."
                }
            case .failure:
                importError = "Δεν ήταν δυνατή η επιλογή του αρχείου."
            }
        }
    }

    private var library: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .firstTextBaseline) {
                    Text("Τα ταξίδια σου")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .tracking(-0.7)
                        .foregroundStyle(AppPalette.ink)
                    Spacer()
                    Text(tripCountLabel)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                carousel(size: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 11) {
                    pageIndicator
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text(cardDrag > 30 ? "Πάτησε τον κάδο για διαγραφή" : "↑ Brief · ↓ Διαγραφή")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                    }
                    .foregroundStyle(AppPalette.secondaryInk)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background {
                        if #available(iOS 26.0, *) {
                            Capsule().fill(.ultraThinMaterial)
                        } else {
                            Capsule().fill(AppPalette.surface.opacity(0.82))
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.bottom, 18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(AppPalette.canvas)
            .safeAreaPadding(.top, 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var topBar: some View {
        HStack {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 38)
                .accessibilityLabel("trippy")
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { darkMode.toggle() }
            } label: {
                Image(systemName: darkMode ? "sun.max" : "moon")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 40, height: 40)
                    .modifier(AdaptiveGlassControl(shape: .circle))
            }
            .accessibilityLabel(darkMode ? "Φωτεινή εμφάνιση" : "Σκούρα εμφάνιση")
            if !trips.isEmpty {
                Button {
                    startNewTrip()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 42, height: 42)
                        .modifier(AdaptiveGlassControl(shape: .circle))
                }
                .accessibilityLabel("Νέο ταξίδι")
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
    }

    private var tripCountLabel: String { "\(trips.count) \(trips.count == 1 ? "ταξίδι" : "ταξίδια")" }

    private func carousel(size: CGSize) -> some View {
        let cardWidth = min(size.width * 0.76, 330)
        let cardHeight = min(size.height * 0.72, cardWidth * 1.34)
        // Global coordinates do not change when the carousel moves under the finger.
        let cardGesture = DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard stage == .library, !isRevealingBrief, !trips.isEmpty,
                      gestureTripID != nil || abs(value.translation.height) > abs(value.translation.width) * 1.25 else { return }
                if gestureTripID == nil, trips.indices.contains(selectedCard) {
                    let trip = trips[selectedCard]
                    gestureTripID = trip.id
                    activeTripID = trip.id
                    brief = trip.brief
                }
                let vertical = value.translation.height
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if vertical < 0 {
                        cardDrag = 0
                        briefReveal = min(1, -vertical / max(size.height, 1))
                    } else {
                        briefReveal = 0
                        cardDrag = min(160, vertical * 0.8)
                    }
                }
            }
            .onEnded { value in
                guard !isRevealingBrief, gestureTripID != nil else { return }
                let upward = -value.translation.height
                let predicted = -value.predictedEndTranslation.height
                if upward > size.height * 0.22 || (upward > 65 && predicted > size.height * 0.45) {
                    finishBriefReveal()
                } else {
                    withAnimation(.smooth(duration: 0.38, extraBounce: 0)) {
                        briefReveal = 0
                        cardDrag = value.translation.height > 65 ? 100 : 0
                    }
                    gestureTripID = nil
                }
            }

        return Group {
            if trips.isEmpty {
                Button {
                    startNewTrip()
                } label: {
                    VStack(spacing: 18) {
                        Image(systemName: "plus")
                            .font(.system(size: 31, weight: .light))
                            .foregroundStyle(AppPalette.brand)
                            .frame(width: 88, height: 88)
                            .background(AppPalette.surface, in: Circle())
                            .modifier(AdaptiveGlassControl(shape: .circle))
                        Text("Νέο ταξίδι")
                            .font(.custom("PlusJakartaSans-Bold", size: 16))
                            .foregroundStyle(AppPalette.ink)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Δημιουργία νέου ταξιδιού")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                            ZStack(alignment: .top) {
                                if index == selectedCard && cardDrag > 0 {
                                    Button(role: .destructive) { deleteTrip(trip.id) } label: {
                                        Label("Διαγραφή ταξιδιού", systemImage: "trash.fill")
                                            .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 20)
                                            .frame(height: 52)
                                            .background(Color(hex: "C94B43"), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(min(1, cardDrag / 70))
                                    .offset(y: -12)
                                    .accessibilityLabel("Διαγραφή του ταξιδιού \(trip.brief.title)")
                                }
                                tripCard(trip, width: cardWidth, height: cardHeight, isActive: index == selectedCard)
                                    .offset(y: index == selectedCard ? cardDrag : 0)
                            }
                                .frame(width: cardWidth, height: cardHeight)
                                .id(index)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.91)
                                        .opacity(phase.isIdentity ? 1 : 0.70)
                                        .offset(y: phase.isIdentity ? 0 : 12)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedScrollID, anchor: .center)
                .onChange(of: selectedScrollID) { _, value in
                    if let value {
                        selectedCard = value
                        cardDrag = 0
                        gestureTripID = nil
                    }
                }
                .safeAreaPadding(.horizontal, max(0, (size.width - cardWidth) / 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(cardGesture)
    }

    @ViewBuilder
    private func tripCard(_ trip: Trip, width: CGFloat, height: CGFloat, isActive: Bool) -> some View {
        VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        TripCover(vibe: trip.brief.vibes.first ?? "Πόλη", destination: trip.brief.destination)
                            .frame(height: height * 0.73)
                        LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                            .frame(height: height * 0.73)
                        if trip.research != nil {
                            Label("Έτοιμο", systemImage: "checkmark.circle.fill")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(.black.opacity(0.25), in: Capsule())
                                .padding(14)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trip.brief.title)
                                .font(.custom("PlusJakartaSans-ExtraBold", size: 19))
                                .tracking(-0.5)
                                .foregroundStyle(AppPalette.ink)
                                .lineLimit(1)
                            Spacer()

                        }
                        Text(trip.brief.dateIsUnknown ? "\(trip.brief.duration) ημέρες · Ευέλικτες" : trip.brief.dateSummary)
                            .font(.custom("PlusJakartaSans-Regular", size: 11))
                            .foregroundStyle(AppPalette.secondaryInk)
                        HStack(spacing: 6) {
                            HStack(spacing: -5) {
                                ForEach(0..<min(trip.brief.travelers, 3), id: \.self) { _ in
                                    Circle().fill(AppPalette.avatarColors[trip.brief.travelers % AppPalette.avatarColors.count])
                                        .frame(width: 17, height: 17)
                                        .overlay(Circle().stroke(AppPalette.surface, lineWidth: 1.5))
                                }
                            }
                            Text("\(trip.brief.travelers) άτομα")
                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                            Text("·")
                            Text(trip.brief.group)
                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                            Spacer()
                        }
                        Text(trip.brief.vibes.sorted().joined(separator: " · "))
                            .font(.custom("PlusJakartaSans-Medium", size: 10))
                            .foregroundStyle(AppPalette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 11)
                    .padding(.bottom, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(AppPalette.surface)
                }
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Button { editTrip(trip) } label: { Label("Επεξεργασία brief", systemImage: "pencil") }
                        Button(role: .destructive) { deleteTrip(trip.id) } label: { Label("Διαγραφή ταξιδιού", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.35), in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Επιλογές για \(trip.brief.title)")
                    .padding(12)
                }
                .shadow(color: AppPalette.ink.opacity(isActive ? 0.15 : 0.09), radius: isActive ? 22 : 14, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 25))
            .onTapGesture {
                guard cardDrag == 0, briefReveal == 0, !isRevealingBrief else { return }
                activeTripID = trip.id
                brief = trip.brief
                withAnimation { stage = trip.research == nil ? .brief : .workspace }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Άνοιγμα ταξιδιού") {
                activeTripID = trip.id
                brief = trip.brief
                stage = trip.research == nil ? .brief : .workspace
            }
            .accessibilityAction(named: "Επεξεργασία brief") { editTrip(trip) }
            .accessibilityAction(named: "Διαγραφή ταξιδιού") { deleteTrip(trip.id) }
    }

    private var pageIndicator: some View {
        Group {
            if trips.isEmpty {
                EmptyView()
            } else if trips.count <= 8 {
                HStack(spacing: 5) {
                    ForEach(trips.indices, id: \.self) { index in
                        Capsule().fill(index == selectedCard ? AppPalette.ink : Color(hex: "E8C8B9"))
                            .frame(width: index == selectedCard ? 18 : 6, height: 6)
                    }
                }
            } else {
                Text("\(selectedCard + 1) / \(trips.count)")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .accessibilityLabel(trips.isEmpty ? "Δεν υπάρχουν ταξίδια" : "Ταξίδι \(selectedCard + 1) από \(trips.count)")
    }

    private var briefScreen: some View {
        VStack(spacing: 0) {
            HStack {
                stageHeader(title: "", back: activeTrip?.research == nil ? .library : .workspace)
                Menu {
                    Button("Εισαγωγή έρευνας", systemImage: "doc.badge.arrow.up") { pendingPrompt = nil; showPromptSheet = true }
                    Button("Σύνδεση έρευνας", systemImage: "network") { showBridgeSettings = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.padding(.trailing, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(briefStep == 0 ? "Πάμε να σχεδιάσουμε το ταξίδι" : briefStepTitles[briefStep])
                            .font(.custom("PlusJakartaSans-ExtraBold", size: 29))
                            .tracking(-0.9)
                            .foregroundStyle(AppPalette.ink)
                        Text(briefStepSubtitles[briefStep])
                            .font(.custom("PlusJakartaSans-Regular", size: 14))
                            .foregroundStyle(AppPalette.secondaryInk)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ΒΗΜΑ \(briefStep + 1) ΑΠΟ 4")
                                .font(.custom("PlusJakartaSans-Bold", size: 10))
                                .tracking(1.2)
                                .foregroundStyle(AppPalette.secondaryInk)
                            Spacer()
                            Text(briefStepTitles[briefStep])
                                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                .foregroundStyle(AppPalette.brand)
                        }
                        HStack(spacing: 5) {
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index <= briefStep ? AppPalette.accent : AppPalette.secondaryInk.opacity(0.14))
                                    .frame(height: 4)
                            }
                        }
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: briefStep)
                    }

                    if briefStep == 0 {
                        VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Πού θέλεις να πας;")
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(AppPalette.ink)
                            TextField("Πόλη ή χώρα", text: $brief.destination)
                                .focused($destinationFieldFocused)
                                .font(.custom("PlusJakartaSans-Medium", size: 15))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    destinationSearchTask?.cancel()
                                    destinationSuggestions = []
                                    loadHolidays(for: brief.destination)
                                }
                            if !brief.destination.isEmpty {
                                Button { brief.destination = "" } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
                            }
                        }
                        .padding(.horizontal, 15).frame(height: 52)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
                        if !destinationSuggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(destinationSuggestions) { suggestion in
                                    Button {
                                        destinationSearchTask?.cancel()
                                        destinationCompleter.cancel()
                                        destinationSuggestions = []
                                        destinationConfirmedQuery = suggestion.query.trimmingCharacters(in: .whitespacesAndNewlines)
                                        brief.destination = suggestion.query
                                        brief.dateContext = []
                                        loadHolidays(for: suggestion.query)
                                    } label: {
                                        HStack(spacing: 11) {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(AppPalette.brand)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.title)
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                                                    .foregroundStyle(AppPalette.ink)
                                                Text(suggestion.subtitle)
                                                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                    .foregroundStyle(AppPalette.secondaryInk)
                                            }
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if suggestion.id != destinationSuggestions.last?.id {
                                        Divider().overlay(Color(hex: "EADFD5")).padding(.leading, 34)
                                    }
                                }
                            }
                            .padding(.horizontal, 13)
                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
                        }
                        if !brief.destination.isEmpty {
                            HStack(spacing: 8) {
                                if isLoadingHolidays { ProgressView().controlSize(.small).tint(AppPalette.brand) }
                                else { Image(systemName: resolvedDestination.isEmpty ? "globe" : "checkmark.circle.fill").foregroundStyle(AppPalette.brand) }
                                Text(resolvedDestination.isEmpty ? holidayStatus : resolvedDestination)
                                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                                    .foregroundStyle(AppPalette.secondaryInk)
                                Spacer()
                                Button("Επιβεβαίωση") { loadHolidays(for: brief.destination) }
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                    .foregroundStyle(AppPalette.brand)
                                    .frame(minHeight: 44)
                            }
                        }
                        PillFlowLayout {
                            ForEach(["Ευρώπη", "Ασία", "Αμερική", "Οπουδήποτε"], id: \.self) { region in
                                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { selectedRegion = region } } label: { choicePill(region, selected: selectedRegion == region) }
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selectedRegion)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Πότε;")
                        PillFlowLayout {
                            Button { withAnimation { brief.dateIsUnknown = false } } label: { choicePill("Συγκεκριμένες", selected: !brief.dateIsUnknown) }
                            Button { withAnimation { brief.dateIsUnknown = true } } label: { choicePill("Ευέλικτες", selected: brief.dateIsUnknown) }
                            Button { withAnimation { brief.dateIsUnknown = true; brief.startDate = ""; brief.endDate = ""; brief.dateContext = [] } } label: { choicePill("Δεν ξέρω", selected: brief.dateIsUnknown && brief.startDate.isEmpty) }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: brief.dateIsUnknown)
                        if !brief.dateIsUnknown {
                            Button {
                                destinationFieldFocused = false
                                calendarDisplayedMonth = parseISODate(brief.startDate) ?? Date()
                                loadHolidays(for: brief.destination)
                                showCalendarPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AppPalette.brand.opacity(0.08))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "calendar")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(AppPalette.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        if brief.startDate.isEmpty && brief.endDate.isEmpty {
                                            Text("Επιλογή ημερομηνιών")
                                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                                .foregroundStyle(AppPalette.ink)
                                            Text("Πάτησε για ημερολόγιο με αργίες")
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(AppPalette.secondaryInk)
                                        } else {
                                            Text("\(brief.startDate) — \(brief.endDate)")
                                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                                .foregroundStyle(AppPalette.ink)
                                            let nights = calendarNightCount
                                            Text(nights > 0 ? "\(nights) διανυκτερεύσεις · \(nights + 1) ημέρες" : "Πάτησε για αλλαγή")
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(AppPalette.secondaryInk)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppPalette.secondaryInk)
                                }
                                .padding(14)
                                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            if !brief.dateContext.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label("Στις ημερομηνίες σου", systemImage: "calendar.badge.clock")
                                        .font(.custom("PlusJakartaSans-Bold", size: 12))
                                        .foregroundStyle(AppPalette.ink)
                                    ForEach(Array(brief.dateContext.prefix(3).enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "sparkle")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(AppPalette.brand)
                                                .padding(.top, 2)
                                            Text(item)
                                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                                .foregroundStyle(AppPalette.secondaryInk)
                                        }
                                    }
                                    if brief.dateContext.count > 3 {
                                        Text("+\(brief.dateContext.count - 3) ακόμη")
                                            .font(.custom("PlusJakartaSans-Medium", size: 10))
                                            .foregroundStyle(AppPalette.secondaryInk)
                                    }
                                    Text("Θα δοθούν στην έρευνα ως ημερολογιακό πλαίσιο· το AI θα επαληθεύσει ωράρια και λειτουργία ανά χώρο.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 10))
                                        .foregroundStyle(AppPalette.secondaryInk)
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                        }
                        if brief.dateIsUnknown {
                            HStack {
                                Text("Διάρκεια").font(.custom("PlusJakartaSans-Medium", size: 13))
                                Spacer()
                                counter(value: $brief.duration, range: 1...30, suffix: "ημ.")
                            }
                            .padding(13).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Ποιοι ταξιδεύουν;")
                        PillFlowLayout {
                            ForEach(["Μόνος/η", "Ζευγάρι", "Φίλοι", "Οικογένεια", "Δουλειά"], id: \.self) { group in
                                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.group = group } } label: { choicePill(group, selected: brief.group == group) }
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: brief.group)
                        HStack {
                            Text("Άτομα").font(.custom("PlusJakartaSans-Medium", size: 13))
                            Spacer()
                            counter(value: $brief.travelers, range: 1...20, suffix: "")
                        }
                        .padding(13).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 15))
                    }
                        }
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    if briefStep == 1 { preferencesStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                    if briefStep == 2 { budgetStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                    if briefStep == 3 { finalBriefStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
                briefStepFooter
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .background(AppPalette.canvas)
        .onChange(of: brief) { _, _ in saveDraft() }
    }

    private var briefStepTitles: [String] {
        ["Βασικά", "Προτιμήσεις", "Κόστος", "Σχόλια & έρευνα"]
    }

    private var briefStepSubtitles: [String] {
        [
            "Πρώτα η πόλη, οι ημερομηνίες και η παρέα.",
            "Διάλεξε ό,τι ταιριάζει· οι λεπτομέρειες ανοίγουν καθώς επιλέγεις.",
            "Προαιρετικά, όρισε budget και τι θέλεις να περιλαμβάνει.",
            "Πρόσθεσε δικές σου οδηγίες και διάλεξε τρόπο έρευνας."
        ]
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Τι ατμόσφαιρα προτιμάς;")
                PillFlowLayout {
                    ForEach(["Πόλη", "Φύση", "Παραλία", "Πολιτισμός"], id: \.self) { vibe in
                        let selected = brief.vibes.contains(vibe)
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                                if selected { brief.vibes.remove(vibe) } else { brief.vibes.insert(vibe) }
                            }
                        } label: { choicePill(vibe, selected: selected).scaleEffect(selected ? 1.025 : 1) }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.36, dampingFraction: 0.78), value: brief.vibes)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Τι θέλεις να ζήσεις;")
                Text(destinationPreferenceSummary)
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(AppPalette.secondaryInk)
                PillFlowLayout(spacing: 8) {
                    ForEach(TripPreferenceCatalog.groups) { group in
                        let selected = brief.interests.contains(group.id)
                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                if selected {
                                    brief.interests.remove(group.id)
                                    brief.preferenceTags.subtract(group.children.map(\.id))
                                } else {
                                    brief.interests.insert(group.id)
                                }
                            }
                        } label: {
                            choicePill(group.title, selected: selected)
                                .scaleEffect(selected ? 1.025 : 1)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: brief.interests)
            }

            ForEach(TripPreferenceCatalog.groups.filter { brief.interests.contains($0.id) && !$0.children.isEmpty }) { group in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.custom("PlusJakartaSans-Bold", size: 13))
                            .foregroundStyle(AppPalette.ink)
                    }
                    PillFlowLayout(spacing: 8) {
                        ForEach(group.children) { option in
                            let selected = brief.preferenceTags.contains(option.id)
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                                    if selected { brief.preferenceTags.remove(option.id) }
                                    else { brief.preferenceTags.insert(option.id) }
                                }
                            } label: {
                                choicePill(option.title, selected: selected)
                                    .scaleEffect(selected ? 1.035 : 1)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.84).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: brief.preferenceTags)
                }
                .padding(14)
                .background(AppPalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ρυθμός")
                HStack(spacing: 10) {
                    Text("Χαλαρά").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    Slider(value: $pace, in: 0...1).tint(AppPalette.accent)
                    Text("Γεμάτες μέρες").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Διατροφή & αλλεργίες")
                chipGrid(options: ["Vegan", "Χορτοφαγική", "Χωρίς γλουτένη", "Halal", "Χωρίς ξηρούς καρπούς", "Lactose-free"], selection: $brief.dietaryNeeds)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Κινητικότητα & πρόσβαση")
                chipGrid(options: ["Walkable", "Προσβάσιμο", "Καρότσι", "Χωρίς σκάλες"], selection: $brief.mobility)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Πού θέλεις να μείνεις;")
                PillFlowLayout {
                    ForEach(["Boutique / Hotel", "Apartment / Airbnb", "Hostal", "Value for Money"], id: \.self) { style in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.stayStyle = style }
                        } label: { choicePill(style, selected: brief.stayStyle == style) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AppPalette.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: brief.interests)
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Ποιο είναι το budget σου;")
                HStack(spacing: 8) {
                    ForEach(["ανά άτομο", "για όλους"], id: \.self) { basis in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) { brief.budgetBasis = basis }
                        } label: {
                            choicePill(basis == "ανά άτομο" ? "Ανά άτομο" : "Συνολικά για την παρέα", selected: brief.budgetBasis == basis)
                        }
                        .buttonStyle(.plain)
                    }
                }
                inputField("Προαιρετικό ανώτατο ποσό", placeholder: "π.χ. 800 €", text: $brief.budget)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Τι να υπολογίσει;")
                Text("Επίλεξε τι περιλαμβάνει το ποσό σου. Αν το αφήσεις κενό, θα ζητήσουμε ξεχωριστές εκτιμήσεις.")
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(AppPalette.secondaryInk)
                chipGrid(options: ["Διαμονή", "Μεταφορά προς την πόλη", "Μετακινήσεις στην πόλη", "Φαγητό", "Εισιτήρια & δραστηριότητες"], selection: $brief.budgetIncludes)
            }
        }
        .padding(16)
        .background(AppPalette.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var finalBriefStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Τι άλλο να ξέρουμε;")
                Text("Περιορισμοί, αγαπημένα, πράγματα που θέλεις να αποφύγεις ή οτιδήποτε κάνει το ταξίδι δικό σου.")
                    .font(.custom("PlusJakartaSans-Regular", size: 12))
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            TextField("Γράψε με τον δικό σου τρόπο…", text: $brief.notes, axis: .vertical)
                .font(.custom("PlusJakartaSans-Regular", size: 14))
                .lineLimit(5...9)
                .padding(15)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Πώς θέλεις να γίνει η έρευνα;")
                Button { startLiveResearch() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isResearching ? "Η αυτόματη έρευνα ξεκίνησε…" : "Αυτόματη έρευνα")
                                .font(.custom("PlusJakartaSans-Bold", size: 14))
                            Text("Το Trippy ψάχνει και οργανώνει τις προτάσεις")
                                .font(.custom("PlusJakartaSans-Regular", size: 10))
                                .opacity(0.84)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isResearching || brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    selectedResearchLayer = .foundation
                    pendingPrompt = nil
                    showPromptSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(AppPalette.canvas, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Χειροκίνητη έρευνα")
                                .font(.custom("PlusJakartaSans-Bold", size: 14))
                                .foregroundStyle(AppPalette.ink)
                            Text("Αντιγραφή prompt ή εισαγωγή δικού σου JSON")
                                .font(.custom("PlusJakartaSans-Regular", size: 10))
                                .foregroundStyle(AppPalette.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.brand)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(isResearching)
            }
        }
        .padding(16)
        .background(AppPalette.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var briefStepFooter: some View {
        VStack(spacing: 10) {
            if briefStep < 3 {
                Button {
                    guard briefStep != 0 || !brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) { briefStep += 1 }
                } label: {
                    HStack {
                        Spacer()
                        Text(briefStep == 0 ? "Συνέχεια στις προτιμήσεις" : "Συνέχεια")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(height: 52)
                    .background(AppPalette.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(briefStep == 0 && brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(briefStep == 0 && brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)
            } else {
                Button {
                    pendingPrompt = nil
                    showPromptSheet = true
                } label: {
                    Label("Εισαγωγή έρευνας που έχεις ήδη", systemImage: "doc.badge.arrow.up")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isResearching)
            }
            if briefStep > 0 {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { briefStep -= 1 }
                } label: {
                    Text("Πίσω")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var destinationPreferenceSummary: String {
        if brief.destination.localizedCaseInsensitiveContains("barcelona") || brief.destination.localizedCaseInsensitiveContains("βαρκελών") {
            return "Βαρκελώνη · επιλογές από τον κατάλογο σημείων και θεματικές ταξιδιωτικών βίντεο."
        }
        return "Οι επιλογές κατευθύνουν την αναζήτηση σε τοπικά σημεία και σχετικές ταξιδιωτικές πηγές."
    }

    private var promptSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Έτοιμο για έρευνα")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .foregroundStyle(AppPalette.ink)
                    Text("Αντέγραψε το prompt στο ChatGPT. Όταν ολοκληρώσει, επικόλλησε εδώ την απάντηση JSON.")
                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                        .foregroundStyle(AppPalette.secondaryInk)
                    if pendingPrompt == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Επίπεδο έρευνας")
                                .font(.custom("PlusJakartaSans-Bold", size: 13))
                                .foregroundStyle(AppPalette.ink)
                            ForEach(ResearchLayer.allCases) { layer in
                                Button { selectedResearchLayer = layer } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selectedResearchLayer == layer ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(selectedResearchLayer == layer ? AppPalette.brand : AppPalette.secondaryInk)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(layer.title).font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                                            Text(layer.detail).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedResearchLayer == layer ? AppPalette.brand.opacity(0.08) : AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selectedResearchLayer == layer ? AppPalette.brand.opacity(0.32) : AppPalette.ink.opacity(0.05), lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text(prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                    Button { copyPrompt() } label: {
                        Label("Αντιγραφή prompt", systemImage: "doc.on.doc")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(AppPalette.brand, in: Capsule()).foregroundStyle(.white)
                    }
                    Button { showResearchFileImporter = true } label: {
                        Label("Εισαγωγή αρχείου JSON", systemImage: "doc.badge.arrow.up")
                            .font(.custom("PlusJakartaSans-Bold", size: 14))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(AppPalette.surface, in: Capsule()).foregroundStyle(AppPalette.ink)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Απάντηση από ChatGPT").font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                        TextEditor(text: $importText)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 160)
                            .padding(8)
                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .topLeading) {
                                if importText.isEmpty {
                                    Text("Επικόλλησε εδώ το JSON…").font(.caption).foregroundStyle(AppPalette.secondaryInk.opacity(0.7)).padding(.horizontal, 13).padding(.vertical, 17).allowsHitTesting(false)
                                }
                            }
                    }
                    Button {
                        importResearch()
                        if importError == nil { showPromptSheet = false }
                    } label: {
                        Text("Άνοιγμα ταξιδιού").font(.custom("PlusJakartaSans-Bold", size: 15))
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color(hex: "FF6B5D"), in: Capsule()).foregroundStyle(.white)
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(importText.isEmpty ? 0.48 : 1)
                }
                .padding(22)
            }
            .background(AppPalette.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Έγινε") { showPromptSheet = false }.foregroundStyle(AppPalette.brand)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func dateInput(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.custom("PlusJakartaSans-SemiBold", size: 10)).foregroundStyle(AppPalette.secondaryInk)
            TextField("ΗΗ / ΜΜ", text: text).font(.custom("PlusJakartaSans-Medium", size: 13))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
    }

    private func choicePill(_ title: String, selected: Bool) -> some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").frame(width: 12)
                Text(title)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .hidden()
            Text(title)
                .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .offset(x: selected ? 8 : 0)
        }
        .overlay(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .frame(width: 12)
                .opacity(selected ? 1 : 0)
        }
        .foregroundStyle(selected ? AppPalette.inverseInk : AppPalette.ink)
        .padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
            .background(selected ? AppPalette.brand : AppPalette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? .clear : AppPalette.secondaryInk.opacity(0.16), lineWidth: 1))
        .contentShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selected)
    }

    private func counter(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 10) {
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                Image(systemName: "minus").font(.caption.weight(.bold)).foregroundStyle(AppPalette.ink).frame(width: 28, height: 28).background(AppPalette.canvas, in: Circle())
            }
            Text("\(value.wrappedValue) \(suffix)").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink).frame(minWidth: 42)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(AppPalette.ink).frame(width: 28, height: 28).background(AppPalette.canvas, in: Circle())
            }
        }
    }

    private func vibeIcon(_ vibe: String) -> String {
        switch vibe {
        case "Πόλη": return "building.2"
        case "Φύση": return "mountain.2"
        case "Παραλία": return "water.waves"
        default: return "building.columns"
        }
    }

    private var workspace: some View {
        TabView(selection: $workspaceTab) {
            ForEach(["Πρόγραμμα", "Χάρτης", "Μέρη", "Κόστη"], id: \.self) { tab in
                Group {
                    if tab == "Πρόγραμμα" {
                        scheduleList
                    } else if tab == "Χάρτης" {
                        fullScreenMap
                    } else {
                        ScrollView { workspacePage(tab) }
                    }
                }.background(AppPalette.canvas)
                .tag(tab)
                .tabItem { Label(tab, systemImage: workspaceSymbol(tab)) }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas)
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let itemID = alternativesForItemID { alternativesSheet(itemID: itemID) }
        }
        .task { await resolvePlaceCoordinates() }
    }

    private var scheduleList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !showTripDetails { scheduleDayPicker }
                if let index = selectedScheduleDayIndex, dayRecords.indices.contains(index) {
                    planDayContent(dayRecords[index], index: index)
                } else { overviewDashboard }
            }
            .padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(AppPalette.canvas)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func planDayContent(_ day: [String: Any], index: Int) -> some View {
        let date = scheduleDateKey(day, index: index)
        let ids = scheduleIDs(day, index: index)
        let points = mapPoints(for: day, index: index)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recordValue(day, keys: ["theme"]) ?? "Η ημέρα σου").font(PlanType.title)
                Text("\(planDate(recordValue(day, keys: ["date"]) ?? "")) · \(ids.count) στάσεις · πρόταση")
                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if !ids.isEmpty {
                PlanRouteMap(points: points, legs: planRouteLegs(day, index: index),
                             fallback: destinationCoordinate, missingCount: ids.count - points.count)
                    .id("\(activeTripID?.uuidString ?? ""):\(index)")
                if !dayIssues(day, index: index).isEmpty {
                    DisclosureGroup("Χρειάζεται έλεγχο · \(dayIssues(day, index: index).count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(dayIssues(day, index: index), id: \.self) { Text($0).font(PlanType.detail) }
                            Button("Αναζήτηση σημείων στον χάρτη") { Task { await resolvePlaceCoordinates() } }
                                .frame(minHeight: 44).disabled(isResolvingCoordinates)
                        }.padding(.top, 12)
                    }.font(PlanType.detail).tint(AppPalette.ink)
                }
                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { order, itemID in
                        scheduleRow(itemID: itemID, date: date, day: day)
                        if order < ids.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
            } else {
                Text("Δεν έχουν προταθεί στάσεις για αυτή την ημέρα.")
                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
            }
            Button { activeScheduleDate = date } label: {
                Label("Πρόσθεσε στάση", systemImage: "plus").font(PlanType.heading)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(AppPalette.inverseInk).background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
            if costAmount(day["estimated_day_cost_per_person_eur"]) != "—" { dayCostSummary(day) }
            if let alternative = recordValue(day, keys: ["alternative"]) {
                DisclosureGroup("Εναλλακτική ημέρας") { Text(alternative).font(PlanType.body).padding(.top, 12) }
                    .font(PlanType.detail).tint(AppPalette.ink)
            }
            if let flexibility = recordValue(day, keys: ["flex_time"]) {
                DisclosureGroup("Ελεύθερος χρόνος") { Text(flexibility).font(PlanType.body).padding(.top, 12) }
                    .font(PlanType.detail).tint(AppPalette.ink)
            }
        }.foregroundStyle(AppPalette.ink)
    }

    private func planDate(_ value: String) -> String {
        guard let date = parseISODate(value) else { return value.isEmpty ? "Ευέλικτη ημέρα" : value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "el_GR")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private func dayIssues(_ day: [String: Any], index: Int) -> [String] {
        let ids = scheduleIDs(day, index: index)
        let checks = records(["date_checks"])
        let date = recordValue(day, keys: ["date"]) ?? ""
        var issues: [String] = []
        for id in ids {
            let place = scheduledPlace(id, day: day)
            let stop = scheduledStop(id, day: day) ?? [:]
            let title = place.flatMap(recordTitle) ?? activityTitle(stop)
            if planCoordinate(id, day: day) == nil {
                issues.append("\(title): λείπει το ακριβές σημείο για οδηγίες.")
            }
            if activeTrip?.scheduleEditsByItemID?[id]?.time?.nonEmpty == nil && recordValue(stop, keys: ["time", "start_time"]) == nil {
                issues.append("\(title): δεν έχει προταθεί ώρα επίσκεψης.")
            }
            let placeID = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? recordValue(stop, keys: ["place_id"])
            let check = checks.first { recordValue($0, keys: ["entity_id"]) == placeID && recordValue($0, keys: ["local_date"]) == date }
            if recordValue(check, keys: ["status"]) != "confirmed" {
                issues.append("\(title): \(recordValue(check, keys: ["status"]) == "closed" ? "αναφέρεται κλειστό — διάλεξε άλλη στάση." : "το ωράριο και η διαθεσιμότητα της ημέρας χρειάζονται επιβεβαίωση.")")
            }
        }
        let pending = (researchRoot["plan_validation"] as? [String: Any])?["pending"] as? [[String: Any]] ?? []
        for item in pending where recordValue(item, keys: ["date"]) == date || item["date"] == nil {
            let messages = ["route_preview_required": "Χρειάζεται έλεγχος μετακίνησης στον χάρτη.",
                "time_or_route_conflict": "Οι ώρες ή η μετακίνηση συγκρούονται· χρειάζεται αλλαγή σειράς ή ώρας.",
                "hard_requirement_pending": "Δεν έχει επιβεβαιωθεί ένας απαραίτητος περιορισμός σου.",
                "custom_instructions_need_review": "Έλεγξε ότι καλύπτονται οι προσωπικές οδηγίες σου.",
                "local_schedule_needs_review": "Οι δικές σου επιλογές διατηρήθηκαν· έλεγξε ξανά ώρες, μετακινήσεις και κόστος.",
                "selected_category_unscheduled": "Μια επιλεγμένη κατηγορία δεν έχει ενταχθεί στις ημέρες.",
                "event_time_and_location_need_review": "Οι εκδηλώσεις χρειάζονται ακριβές σημείο και ώρα πριν ενταχθούν στο πρόγραμμα.",
                "budget_coverage_pending": "Οι γνωστές τιμές δεν αρκούν ακόμη για έλεγχο του συνολικού budget."]
            if let code = recordValue(item, keys: ["code"]), let message = messages[code], !issues.contains(message) { issues.append(message) }
        }
        return issues
    }

    private func planRouteLegs(_ day: [String: Any], index: Int) -> [TripRouteLeg] {
        let ids = scheduleIDs(day, index: index)
        guard ids.count > 1 else { return [] }
        return (1..<ids.count).compactMap { order in
            guard let from = planCoordinate(ids[order - 1], day: day), let to = planCoordinate(ids[order], day: day) else { return nil }
            let mode = recordValue(scheduledStop(ids[order], day: day), keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
            guard mode == nil || ["walk", "walking", "foot", "drive", "driving", "car"].contains(mode!) else { return nil }
            return TripRouteLeg(id: "\(ids[order - 1]):\(ids[order])", day: index, from: from, to: to,
                                walking: mode == nil ? routePreviewMode == "walking" : ["walk", "walking", "foot"].contains(mode!))
        }
    }

    private func planCoordinate(_ id: String, day: [String: Any]) -> CLLocationCoordinate2D? {
        scheduledPlace(id, day: day).flatMap(placeCoordinate) ?? scheduledStop(id, day: day).flatMap(coordinateFromRecord) ?? resolvedCoordinates[id] ?? activeTrip?.mapCoordinatesByPlaceID?[id]?.coordinate
    }

    private func openPlanDirections(_ id: String, day: [String: Any]) {
        let stop = scheduledStop(id, day: day) ?? [:]
        let name = scheduledPlace(id, day: day).flatMap(recordTitle) ?? activityTitle(stop)
        guard let coordinate = planCoordinate(id, day: day) else {
            var components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: "\(name), \(brief.destination)")]
            if let url = components.url { UIApplication.shared.open(url) }
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate)); item.name = name
        let mode = recordValue(stop, keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
        let driving = ["drive", "driving", "car"].contains(mode ?? routePreviewMode)
        let transit = ["transit", "metro", "bus", "train", "public_transport"].contains(mode ?? "")
        let dayIndex = dayRecords.enumerated().first { $0.element["date"] as? String == day["date"] as? String }?.offset ?? selectedScheduleDayIndex ?? 0
        let ids = scheduleIDs(day, index: dayIndex)
        var items = [item]
        if let order = ids.firstIndex(of: id), order > 0, let from = planCoordinate(ids[order - 1], day: day) {
            let origin = MKMapItem(placemark: MKPlacemark(coordinate: from))
            origin.name = scheduledPlace(ids[order - 1], day: day).flatMap(recordTitle) ?? "Προηγούμενη στάση"
            items.insert(origin, at: 0)
        }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: transit ? MKLaunchOptionsDirectionsModeTransit : (driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking)])
    }

    private var scheduleDayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                scheduleTab("Όλο το ταξίδι", subtitle: "", selected: selectedScheduleDayIndex == nil) { selectedScheduleDayIndex = nil; selectedMapDay = nil }
                ForEach(dayRecords.indices, id: \.self) { index in
                    scheduleTab("Ημέρα \(index + 1)", subtitle: "", selected: selectedScheduleDayIndex == index) { selectedScheduleDayIndex = index; selectedMapDay = index }
                }
            }
        }.scrollIndicators(.hidden)
    }
    private func scheduleTab(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PlanType.detail).foregroundStyle(selected ? AppPalette.inverseInk : AppPalette.ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(selected ? AppPalette.brand : AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var overviewDashboard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Το ταξίδι σου").font(PlanType.title)
                Text("\(dayRecords.count) ημέρες · \(placeRecords.count) επιλογές").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if let quality = researchRoot["quality_report"] as? [String: Any], recordValue(quality, keys: ["status"]) != "ready" {
                DisclosureGroup("Η έρευνα χρειάζεται συμπλήρωση") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(quality["gaps"] as? [String] ?? [], id: \.self) { Text($0).font(PlanType.body) }
                    }.padding(.top, 12)
                }.font(PlanType.detail)
            }
            if let diagnostics = ResearchDiagnostics.summary(researchRoot) {
                DisclosureGroup("Στοιχεία έρευνας και υποστήριξης") {
                    Text(diagnostics).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding(.top, 12)
                    Button("Αντιγραφή στοιχείων") { UIPasteboard.general.string = diagnostics }
                        .font(PlanType.detail).padding(.top, 8)
                }.font(PlanType.detail)
            }
            if dayRecords.isEmpty { Text("Δεν υπάρχει ακόμη ημερήσιο πρόγραμμα. Οι διαθέσιμες επιλογές βρίσκονται στα Μέρη.").font(PlanType.body) }
            VStack(spacing: 0) {
                ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                    Button { selectedScheduleDayIndex = index; selectedMapDay = index } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Text(String(index + 1)).font(PlanType.heading).frame(width: 32, height: 32)
                                .background(AppPalette.brand.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recordValue(day, keys: ["theme"]) ?? "Ημέρα \(index + 1)").font(PlanType.heading)
                                Text("\(planDate(recordValue(day, keys: ["date"]) ?? "")) · \(scheduleIDs(day, index: index).count) στάσεις")
                                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                                if scheduleIDs(day, index: index).isEmpty { Text("Χρειάζεται πρόγραμμα").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                                else if !dayIssues(day, index: index).isEmpty { Text("Χρειάζεται έλεγχο").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).padding(.top, 8)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 16).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if index < dayRecords.count - 1 { Divider() }
                }
            }
            DisclosureGroup("Σύνοψη και εποχικές συμβουλές") {
                VStack(alignment: .leading, spacing: 16) {
                    Text(overviewText).font(PlanType.body)
                    ForEach((researchRoot["overview"] as? [String: Any])?["seasonal_notes"] as? [String] ?? [], id: \.self) {
                        Text($0).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.padding(.top, 16)
            }.font(PlanType.heading)
            DisclosureGroup("Εκκρεμότητες πριν το ταξίδι") { checklistContent.padding(.top, 16) }.font(PlanType.heading)
        }.foregroundStyle(AppPalette.ink).tint(AppPalette.ink)
    }

    private func selectedDayPage(_ index: Int) -> some View {
        planDayContent(dayRecords[index], index: index)
    }

    private func dayMap(points: [ResearchMapPoint], title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "map").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                Spacer()
                Text("Apple Maps · 3D όπου διατίθεται").font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.secondaryInk)
            }
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                ForEach(points) { point in Marker(point.title, coordinate: point.coordinate).tint(AppPalette.brand) }
                if points.isEmpty, let destinationCoordinate {
                    Marker(brief.destination.isEmpty ? "Προορισμός" : brief.destination, coordinate: destinationCoordinate).tint(AppPalette.accent)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
            .overlay(alignment: .bottomLeading) {
                if points.isEmpty {
                    Text(destinationCoordinate == nil ? "Οι στάσεις θα εμφανιστούν μόλις βρεθούν οι συντεταγμένες." : "Εμφανίζεται ο προορισμός· οι στάσεις θα προστεθούν όταν επιβεβαιωθούν.")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7).background(.regularMaterial, in: Capsule()).padding(9)
                }
            }
            .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }.padding(11).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dayCostSummary(_ day: [String: Any]) -> some View {
        HStack {
            Text("Εκτίμηση / άτομο").font(PlanType.detail)
            Spacer()
            Text(costAmount(day["estimated_day_cost_per_person_eur"])).font(PlanType.heading)
        }.foregroundStyle(AppPalette.ink)
    }

    private var tripHero: some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(vibe: brief.vibes.first ?? "Πόλη", destination: brief.destination)
                .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(brief.title).font(.custom("PlusJakartaSans-ExtraBold", size: 22)).foregroundStyle(.white)
                Text("\(brief.dateSummary) · \(brief.travelers) άτομα · \(brief.group)")
                    .font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(.white.opacity(0.9))
            }.padding(14)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    private func workspaceSymbol(_ tab: String) -> String {
        switch tab {
        case "Χάρτης": return "map"
        case "Μέρη": return "bookmark"
        case "Κόστη": return "eurosign.circle"
        default: return "list.bullet"
        }
    }

    private func workspacePage(_ tab: String) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            ZStack(alignment: .bottom) {
                TripCover(vibe: brief.vibes.first ?? "Πόλη", destination: brief.destination)
                    .frame(height: 285)
                LinearGradient(colors: [.black.opacity(0.05), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(brief.title)
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .tracking(-0.7)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(brief.dateSummary)
                        Text("·")
                        Text("\(brief.travelers) άτομα")
                        Text("·")
                        Text(brief.group)
                    }
                    .font(.custom("PlusJakartaSans-Regular", size: 11))
                    .foregroundStyle(AppPalette.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17).padding(.vertical, 14)
                .background(AppPalette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 21, topTrailingRadius: 21, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .overlay(alignment: .top) {
                HStack {
                    Button { withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) { stage = .library } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppPalette.ink).frame(width: 40, height: 40)
                            .modifier(AdaptiveGlassControl(shape: .circle))
                    }
                    Spacer()
                    Button { withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) { stage = .brief } } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppPalette.ink).frame(width: 40, height: 40)
                            .modifier(AdaptiveGlassControl(shape: .circle))
                    }
                    .accessibilityLabel("Επεξεργασία brief")
                }
                .padding(15)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let quality = researchRoot["quality_report"] as? [String: Any],
               quality["status"] as? String == "partial" {
                DisclosureGroup {
                    ForEach(Array((quality["gaps"] as? [String] ?? []).enumerated()), id: \.offset) { _, gap in
                        Text(gap)
                            .font(.custom("PlusJakartaSans-Regular", size: 11))
                            .foregroundStyle(AppPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } label: {
                    Label("Η έρευνα έχει ελλείψεις", systemImage: "exclamationmark.circle")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 13))
                        .foregroundStyle(AppPalette.ink)
                }
                .padding(14)
                .background(AppPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            switch tab {
            case "Χάρτης":
                mapContent
            case "Μέρη":
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Το pool σου").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                        Spacer()
                        Text("\(placeRecords.count) επιλογές").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    ForEach(Array(placeRecords.enumerated()), id: \.offset) { index, place in placeCard(place, index: index) }
                    if placeRecords.isEmpty { emptyResearchMessage }
                }
            case "Κόστη":
                VStack(alignment: .leading, spacing: 13) {
                    Text("Κόστη και κρατήσεις").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                    metricCard("€\(budgetTotal(for: "person").formatted(.number.precision(.fractionLength(0...2))))", label: "Σύνολο ανά άτομο · δικές σου καταχωρίσεις", symbol: "eurosign.circle")
                    analyticalCostTable
                    infoPanel("Εισιτήρια και κρατήσεις", symbol: "ticket") { ticketContent }
                    infoPanel("Μετακινήσεις", symbol: "tram") { transportContent }
                    infoPanel("Αργίες και ωράρια", symbol: "calendar") { calendarContent }
                    budgetCalculator
                    checklistContent
                    sourcesSection
                }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Το πρόγραμμά σου").font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                        Spacer()
                        Text("\(dayRecords.count) ημέρες").font(.custom("PlusJakartaSans-Medium", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    if dayRecords.isEmpty {
                        dashboardSection("Σύνοψη έρευνας", symbol: "sparkles") {
                            Text(overviewText).font(.custom("PlusJakartaSans-Regular", size: 13)).foregroundStyle(AppPalette.secondaryInk)
                            emptyResearchMessage
                        }
                    }
                    ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                        scheduleDay(day, index: index)
                    }
                    if !dayRecords.isEmpty { checklistContent; sourcesSection }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
    }

    private var fullScreenMap: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                    ForEach(mapPoints) { point in
                        let order = plannedMapLabels[point.id]
                        Marker(order.map { "\($0) · \(point.title)" } ?? point.title, coordinate: point.coordinate)
                            .tint(AppPalette.brand)
                    }
                    if mapPoints.isEmpty, let destinationCoordinate {
                        Marker(brief.destination, coordinate: destinationCoordinate).tint(AppPalette.accent)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea(edges: .top)

                VStack(alignment: .leading, spacing: 5) {
                    Text(mapHeaderTitle)
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 22))
                        .tracking(-0.5)
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                    Text(mapHeaderSubtitle)
                        .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                        .foregroundStyle(AppPalette.secondaryInk)
                        .lineLimit(1)
                    Text(mapTripSentence)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 15, y: 7)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(AppPalette.canvas)
        }
    }

    private var mapHeaderTitle: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        return recordValue(mapOverview, keys: ["title"]) ?? brief.destination
    }

    private var mapHeaderSubtitle: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        return recordValue(mapOverview, keys: ["subtitle"]) ?? brief.dateSummary
    }

    private var mapTripSentence: String {
        let mapOverview = researchRoot["map_overview"] as? [String: Any]
        if let sentence = recordValue(mapOverview, keys: ["trip_sentence", "summary"]), !sentence.isEmpty { return sentence }
        return overviewText
    }

    private var mapContent: some View {
        dayMap(points: mapPoints.map { point in
            let order = plannedMapLabels[point.id]
            return ResearchMapPoint(id: point.id, title: order.map { "\($0) · \(point.title)" } ?? point.title, latitude: point.latitude, longitude: point.longitude)
        }, title: "Όλο το ταξίδι · \(mapPoints.count) σημεία")
    }

    private var emptyResearchMessage: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Η έρευνα δεν περιλαμβάνει αυτή την ενότητα.")
                .font(.custom("PlusJakartaSans-SemiBold", size: 13)).foregroundStyle(AppPalette.ink)
            Text("Μπορείς να δημιουργήσεις νέο prompt από το brief και να εισαγάγεις ενημερωμένο αποτέλεσμα.")
                .font(.custom("PlusJakartaSans-Regular", size: 12)).foregroundStyle(AppPalette.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var sourcesSection: some View {
        dashboardSection("Πηγές και ενημέρωση", symbol: "link") {
            ForEach(Array(sourceRecords.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordTitle(source) ?? recordValue(source, keys: ["name", "url"]) ?? "Πηγή")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
                    if let url = recordValue(source, keys: ["url", "source_url", "source_page_url"]), let link = URL(string: url) {
                        Link(url, destination: link).font(.custom("PlusJakartaSans-Regular", size: 11)).lineLimit(1)
                    }
                    if let checked = recordValue(source, keys: ["checked_at", "last_verified", "updated_at"]) {
                        Text("Ελέγχθηκε: \(checked)").font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }
            if sourceRecords.isEmpty { Text("Δεν βρέθηκε λίστα πηγών στην απάντηση.").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
        }
    }

    private func scheduleDay(_ day: [String: Any], index: Int) -> some View {
        let date = scheduleDateKey(day, index: index)
        let ids = scheduleIDs(day, index: index)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dayTitle(day, index: index)).font(.custom("PlusJakartaSans-Bold", size: 15)).foregroundStyle(AppPalette.ink)
                    Text(recordValue(day, keys: ["theme"]) ?? "Ελεύθερη ημέρα")
                        .font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                Button { activeScheduleDate = date } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppPalette.ink).frame(width: 36, height: 36)
                        .background(Color(hex: "FFE0D2"), in: Circle())
                }
                .accessibilityLabel("Πρόσθεσε στάση στην \(dayTitle(day, index: index))")
            }
            .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 8)

            if ids.isEmpty {
                Button { activeScheduleDate = date } label: {
                    Label("Πρόσθεσε μέρη από το pool", systemImage: "plus.circle")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.brand)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                }.buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(ids, id: \.self) { itemID in
                        scheduleRow(itemID: itemID, date: date, day: day)
                            .draggable(itemID)
                            .dropDestination(for: String.self) { dragged, _ in
                                guard let source = dragged.first else { return false }
                                moveScheduleItem(source, before: itemID, date: date, day: day, index: index)
                                return true
                            }
                        if itemID != ids.last { Divider().padding(.leading, 42) }
                    }
                }
            }
            if let alternative = recordValue(day, keys: ["alternative"]), !alternative.isEmpty {
                Text(alternative).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    .padding(.horizontal, 13).padding(.vertical, 10)
            }
        }
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Color(hex: "E9DDD2"), lineWidth: 0.7))
    }

    private func scheduleRow(itemID: String, date: String, day: [String: Any]) -> some View {
        let stop = scheduledStop(itemID, day: day) ?? [:]
        let place = scheduledPlace(itemID, day: day)
        let edit = activeTrip?.scheduleEditsByItemID?[itemID]
        let name = place.flatMap(recordTitle) ?? activityTitle(stop)
        let index = dayRecords.firstIndex { scheduleDateKey($0, index: 0) == date } ?? 0
        let ids = scheduleIDs(day, index: index)
        let order = ids.firstIndex(of: itemID) ?? 0
        let expanded = expandedScheduleItemIDs.contains(itemID)
        let time = edit?.time?.nonEmpty ?? recordValue(stop, keys: ["time", "start_time"]) ?? "Χωρίς ώρα"
        let duration = recordValue(stop, keys: ["duration_minutes"]) ?? place.flatMap { recordValue($0, keys: ["average_visit_minutes"]) }
        return HStack(alignment: .top, spacing: 12) {
            Text(String(order + 1)).font(PlanType.detail).foregroundStyle(AppPalette.brand)
                .frame(width: 32, height: 32).background(AppPalette.brand.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(duration.map { "\(time) · \($0) λεπτά" } ?? time).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        Text(name).font(PlanType.heading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button(expanded ? "Κλείσιμο λεπτομερειών" : "Λεπτομέρειες και επεξεργασία", systemImage: "pencil") {
                            if expanded { expandedScheduleItemIDs.remove(itemID) } else { expandedScheduleItemIDs.insert(itemID) }
                        }
                        Button("Δες άλλες επιλογές", systemImage: "arrow.triangle.swap") { alternativesForItemID = itemID }
                        Button("Μετακίνηση πάνω", systemImage: "arrow.up") { movePlanStop(itemID, day: day, index: index, offset: -1) }.disabled(order == 0)
                        Button("Μετακίνηση κάτω", systemImage: "arrow.down") { movePlanStop(itemID, day: day, index: index, offset: 1) }.disabled(order == ids.count - 1)
                        Button("Αφαίρεση στάσης", systemImage: "trash", role: .destructive) { removeScheduleItem(itemID, date: date, day: day) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Επιλογές για \(name)")
                }
                if let instruction = recordValue(stop, keys: ["instructions", "notes", "description"])
                    ?? place.flatMap({ recordValue($0, keys: ["why_recommended", "description"]) }) {
                    Text(instruction).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk).lineLimit(expanded ? nil : 3)
                }
                HStack(spacing: 16) {
                    Button { if planCoordinate(itemID, day: day) == nil { locatingPlanItemID = itemID } else { openPlanDirections(itemID, day: day) } } label: {
                        Label(planCoordinate(itemID, day: day) == nil ? "Επίλεξε σημείο" : "Οδηγίες", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(PlanType.detail).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                    if let amount = edit?.costPerPerson?.nonEmpty ?? recordValue(stop, keys: ["estimated_cost_per_person_eur"]) {
                        Text("€\(amount) / άτομο").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                    } else if let place, priceLabel(place) != "Τιμή μη επιβεβαιωμένη" {
                        Text(priceLabel(place)).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Προτεινόμενη επίσκεψη · η κράτηση επιβεβαιώνεται χωριστά.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        editField("Ώρα", text: scheduleEditBinding(itemID, field: .time), prompt: "09:30")
                        editField("Δική σου εκτίμηση / άτομο (€)", text: scheduleEditBinding(itemID, field: .cost), prompt: "—", keyboard: .decimalPad)
                        if let address = place.flatMap({ recordValue($0, keys: ["address", "area"]) }) { Text(address).font(PlanType.body) }
                        if let place { activityInsights(place) }
                        if let url = place.flatMap({ recordValue($0, keys: ["official_url", "source_url", "url"]) }).flatMap(URL.init(string:)) {
                            Link("Επίσημη σελίδα", destination: url).font(PlanType.detail).frame(minHeight: 44)
                        }
                    }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.foregroundStyle(AppPalette.ink).padding(.vertical, 16)
    }

    private func movePlanStop(_ id: String, day: [String: Any], index: Int, offset: Int) {
        var ids = scheduleIDs(day, index: index)
        guard let from = ids.firstIndex(of: id), ids.indices.contains(from + offset) else { return }
        ids.swapAt(from, from + offset)
        setScheduleOrder(ids, date: scheduleDateKey(day, index: index))
    }

    private func activityInsights(_ place: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if priceLabel(place) != "Τιμή μη επιβεβαιωμένη" { Text("Τιμή: \(priceLabel(place))").font(PlanType.body) }
            else { Text("Δεν έχει επιβεβαιωθεί τιμή.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
            if ratingLabel(place) != "—" { Text("Βαθμολογία: \(ratingLabel(place))").font(PlanType.body) }
            if let duration = recordValue(place, keys: ["average_visit_minutes"]) { Text("Διάρκεια επίσκεψης: \(duration) λεπτά").font(PlanType.body) }
            if let reservation = recordValue(place, keys: ["reservation_required"]) { Text("Κράτηση: \(reservation)").font(PlanType.body) }
            if let best = recordValue(place, keys: ["best_time"]) { Text("Προτεινόμενη ώρα: \(best)").font(PlanType.body) }
            if let dietary = place["dietary_options"] as? [String], !dietary.isEmpty { Text(dietary.joined(separator: " · ")).font(PlanType.body) }
            if let bestFor = place["best_for"] as? [String], !bestFor.isEmpty { Text("Ταιριάζει σε: \(bestFor.joined(separator: " · "))").font(PlanType.body) }
            if let popularity = recordValue(place, keys: ["popularity"]) { Text(popularity).font(PlanType.body) }
            if let tags = place["tags"] as? [String], !tags.isEmpty {
                DisclosureGroup("Χαρακτηριστικά") { Text(tags.joined(separator: " · ")).font(PlanType.body).padding(.top, 12) }.font(PlanType.detail)
            }
            let ids = Set(place["source_ids"] as? [String] ?? [])
            let sources = sourceRecords.filter { recordValue($0, keys: ["id"]).map(ids.contains) ?? false }
            if !sources.isEmpty {
                DisclosureGroup("Πηγές για το μέρος") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                            if let url = recordValue(source, keys: ["url"]).flatMap(URL.init(string:)) {
                                Link(recordValue(source, keys: ["publisher", "title"]) ?? url.host ?? "Πηγή", destination: url).font(PlanType.detail).frame(minHeight: 44)
                            }
                        }
                    }.padding(.top, 12)
                }.font(PlanType.detail)
            }
            if let checked = recordValue(place, keys: ["checked_at", "last_verified"]) { Text("Έλεγχος στοιχείων: \(planDate(checked))").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
        }
    }

    private enum ScheduleEditField { case time, cost }
    private func scheduleEditBinding(_ id: String, field: ScheduleEditField) -> Binding<String> {
        Binding(get: {
            let edit = activeTrip?.scheduleEditsByItemID?[id]
            switch field { case .time: return edit?.time ?? ""; case .cost: return edit?.costPerPerson ?? "" }
        }, set: { value in
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
            var edits = trips[index].scheduleEditsByItemID ?? [:]
            var edit = edits[id] ?? ScheduleItemEdit()
            switch field { case .time: edit.time = value; case .cost: edit.costPerPerson = value }
            edits[id] = edit; trips[index].scheduleEditsByItemID = edits; trips[index].updatedAt = .now; TripStorage.save(trips)
        })
    }
    private func editField(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            TextField(prompt, text: text).font(PlanType.body).keyboardType(keyboard)
                .frame(minHeight: 44).padding(.horizontal, 12).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 10))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var analyticalCostTable: some View {
        let costs = researchRoot["costs"] as? [String: Any] ?? [:]
        let rows: [(String, String, String)] = [
            ("Ταξίδι", costAmount(costs["per_person_estimate"]), "ανά άτομο"),
            ("Ταξίδι", costAmount(costs["group_estimate"]), "ομάδα"),
            ("Διαμονή", costAmount((costs["lodging_estimate"] as? [String: Any])?["group_total_eur"]), "ομάδα"),
            ("Διαμονή", costAmount((costs["lodging_estimate"] as? [String: Any])?["per_room_per_night_eur"]), "δωμάτιο / βράδυ"),
            ("Μεταφορές και αξιοθέατα", costAmount((costs["transport_and_attractions_subtotal"] as? [String: Any])?["per_person_eur"]), "ανά άτομο"),
            ("Φαγητό", costAmount((costs["food_estimate"] as? [String: Any])?["per_person_per_day_eur"]), "ανά άτομο / ημέρα")
        ]
        return VStack(alignment: .leading, spacing: 16) {
            Text("Ο προϋπολογισμός σου").font(PlanType.title)
            ForEach(Array(rows.filter { $0.1 != "—" }.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) { Text(row.0).font(PlanType.heading); Text(row.2).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk) }
                    Spacer(); Text(row.1).font(PlanType.heading)
                }
            }
            if rows.allSatisfy({ $0.1 == "—" }) {
                Text("Δεν υπάρχει ακόμη συνολική εκτίμηση. Δες τις γνωστές τιμές εισιτηρίων παρακάτω ή πρόσθεσε τις δικές σου δαπάνες.")
                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
            }
            if let subtotal = costs["known_scheduled_price_subtotal"] as? [String: Any], costAmount(subtotal) != "—" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Γνωστές τιμές στάσεων: \(costAmount(subtotal))").font(PlanType.heading)
                    Text("Ενδεικτικό σενάριο ενηλίκου · δεν είναι συνολικό κόστος ταξιδιού.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                }
            }
            DisclosureGroup("Τι περιλαμβάνεται και τι λείπει") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.filter { $0.1 == "—" }.enumerated()), id: \.offset) { _, row in Text("\(row.0) (\(row.2)): δεν βρέθηκε εκτίμηση.").font(PlanType.body) }
                    if let methodology = recordValue(costs, keys: ["methodology"]) { Text(methodology).font(PlanType.body) }
                }.padding(.top, 12)
            }.font(PlanType.detail)
        }.foregroundStyle(AppPalette.ink).tint(AppPalette.ink)
    }

    private func costAmount(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        if let object = value as? [String: Any] {
            let currency = recordValue(object, keys: ["currency"]) ?? "EUR"
            let symbol = currency == "EUR" ? "€" : "\(currency) "
            let minimum = numericValue(object, keys: ["min"])
            let maximum = numericValue(object, keys: ["max"])
            if let minimum, let maximum { return minimum == maximum ? "\(symbol)\(planNumber(minimum))" : "\(symbol)\(planNumber(minimum))–\(maximum.formatted())" }
            if let minimum { return "από \(symbol)\(planNumber(minimum))" }
            if let maximum { return "έως \(symbol)\(planNumber(maximum))" }
            for key in ["per_person_eur", "per_person_per_day_eur", "group_total_eur"] {
                if let amount = numericValue(object, keys: [key]) { return "\(symbol)\(planNumber(amount))" }
            }
            return "—"
        }
        if let number = value as? NSNumber { return "€\(planNumber(number.doubleValue))" }
        if let text = value as? String, let amount = Double(text.replacingOccurrences(of: ",", with: ".")), amount.isFinite { return "€\(planNumber(amount))" }
        return "—"
    }
    private func planNumber(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func budgetTotal(for basis: String) -> Double {
        (activeTrip?.budgetEntries ?? []).filter { $0.basis == basis }
            .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }.reduce(0, +)
    }
    private var budgetCalculator: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Υπολογιστής ταξιδιού", systemImage: "plus.forwardslash.minus")
                .font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            Text("Κατέγραψε δικά σου ποσά και ξεχώρισε κόστος ανά άτομο από κόστος ομάδας.")
                .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Δαπάνη").font(.caption.weight(.semibold)); Spacer(); Text("Ποσό (€)").font(.caption.weight(.semibold)) }
                .foregroundStyle(AppPalette.secondaryInk)
            ForEach(activeTrip?.budgetEntries ?? []) { entry in
                HStack(spacing: 8) {
                    TextField("Κατηγορία", text: budgetEntryBinding(entry.id, field: .title))
                        .font(.system(size: 12, weight: .medium))
                    TextField("0", text: budgetEntryBinding(entry.id, field: .amount)).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(width: 88).font(.system(size: 12, weight: .semibold))
                    Menu {
                        Button("Ανά άτομο") { setBudgetBasis(entry.id, basis: "person") }
                        Button("Ομάδα") { setBudgetBasis(entry.id, basis: "group") }
                    } label: {
                        Text(entry.basis == "person" ? "/ άτομο" : "ομάδα").font(.system(size: 9, weight: .semibold)).foregroundStyle(AppPalette.brand)
                    }
                    Button(role: .destructive) { updateBudgetEntries { $0.removeAll { $0.id == entry.id } } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(AppPalette.secondaryInk)
                    }.buttonStyle(.plain)
                }.padding(10).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
            Button { updateBudgetEntries { $0.append(TripBudgetEntry()) } } label: {
                Label("Προσθήκη δαπάνης", systemImage: "plus").font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.brand)
            }.buttonStyle(.plain)
            HStack { Text("Ανά άτομο"); Spacer(); Text("€\(budgetTotal(for: "person").formatted(.number.precision(.fractionLength(2))))").fontWeight(.bold) }
                .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink).padding(.top, 3)
            HStack { Text("Για όλη την ομάδα"); Spacer(); Text("€\(budgetTotal(for: "group").formatted(.number.precision(.fractionLength(2))))").fontWeight(.bold) }
                .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
            Text("Οι δικές σου καταχωρίσεις μένουν χωριστά από τις εκτιμήσεις της έρευνας.")
                .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
        }
    }
    private enum BudgetEditField: Equatable { case title, amount }
    private func budgetEntryBinding(_ id: UUID, field: BudgetEditField) -> Binding<String> {
        Binding(get: {
            (activeTrip?.budgetEntries ?? []).first(where: { $0.id == id }).map { field == .title ? $0.title : $0.amount } ?? ""
        }, set: { value in
            updateBudgetEntries { entries in
                guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
                if field == .title { entries[index].title = value } else { entries[index].amount = value }
            }
        })
    }
    private func updateBudgetEntries(_ mutation: (inout [TripBudgetEntry]) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var entries = trips[index].budgetEntries ?? []
        mutation(&entries); trips[index].budgetEntries = entries; trips[index].updatedAt = .now; TripStorage.save(trips)
    }
    private func setBudgetBasis(_ id: UUID, basis: String) {
        updateBudgetEntries { entries in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].basis = basis
        }
    }
    private var ticketContent: some View {
        let tickets = records(["ticket_options", "tickets", "booking_options"])
        return VStack(alignment: .leading, spacing: 16) {
            if tickets.isEmpty { Text("Δεν βρέθηκαν τιμές εισιτηρίων.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(tickets.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(recordTitle(item) ?? "Επιλογή \(index + 1)").font(PlanType.heading)
                    if costAmount(item["price_per_person_eur"]) != "—" { Text("\(costAmount(item["price_per_person_eur"])) / άτομο").font(PlanType.body) }
                    if costAmount(item["group_price_eur"]) != "—" { Text("\(costAmount(item["group_price_eur"])) για την ομάδα").font(PlanType.body) }
                    if let notes = recordValue(item, keys: ["notes", "description"]) { Text(notes).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
                    if let url = recordValue(item, keys: ["booking_url", "official_url"]).flatMap(URL.init(string:)) {
                        Link("Επίσημη κράτηση", destination: url).font(PlanType.detail).frame(minHeight: 44)
                    }
                    Divider()
                }
            }
        }.foregroundStyle(AppPalette.ink)
    }
    private var transportContent: some View {
        let options = records(["transport_options", "transport"])
        return VStack(alignment: .leading, spacing: 8) {
            if options.isEmpty { Text("Δεν υπάρχουν δομημένες επιλογές μετακίνησης.").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                VStack(alignment: .leading, spacing: 6) {
                    Text(recordTitle(option) ?? "Επιλογή \(index + 1)").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                    HStack { Text(recordValue(option, keys: ["best_for"]) ?? "Κατάλληλο για"); Spacer(); Text(priceLabel(option)) }
                        .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    if let checked = recordValue(option, keys: ["checked_at"]) { Text("Ελέγχθηκε \(checked)").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk) }
                    if let url = recordValue(option, keys: ["official_url", "url"]).flatMap(URL.init(string:)) { Link("Επίσημες πληροφορίες", destination: url).font(.system(size: 10, weight: .semibold)) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var calendarContent: some View {
        let checks = records(["calendar_checks", "holiday_checks", "opening_hours_checks"])
        let dateChecks = records(["date_checks"])
        return VStack(alignment: .leading, spacing: 8) {
            if checks.isEmpty && dateChecks.isEmpty { Text("Δεν συμπεριλήφθηκαν συγκεκριμένοι έλεγχοι αργιών, χώρων ή ωραρίων.").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(AppPalette.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(recordValue(check, keys: ["date"]) ?? "Ημερομηνία μη διαθέσιμη") · \(recordValue(check, keys: ["name", "day", "title"]) ?? "Έλεγχος \(index + 1)")")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.ink)
                        Text("\(recordValue(check, keys: ["status"]) ?? "Δεν επιβεβαιώθηκε") · \(recordValue(check, keys: ["details", "note"]) ?? "Χωρίς επιπλέον λεπτομέρειες")")
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
            ForEach(Array(dateChecks.enumerated()), id: \.offset) { index, check in
                let entityID = recordValue(check, keys: ["entity_id", "place_id", "event_id"])
                let entity = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == entityID })
                let name = entity.flatMap { recordValue($0, keys: ["name", "title"]) } ?? recordValue(check, keys: ["entity_name"]) ?? "Χώρος ή event \(index + 1)"
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: recordValue(check, keys: ["status"]) == "confirmed" ? "checkmark.seal" : "questionmark.circle")
                        .foregroundStyle(recordValue(check, keys: ["status"]) == "confirmed" ? Color(hex: "477461") : Color(hex: "D88A27"))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(recordValue(check, keys: ["local_date", "date"]) ?? "Ημερομηνία άγνωστη") · \(name)")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 11)).foregroundStyle(AppPalette.ink)
                        let details = [recordValue(check, keys: ["status"]), recordValue(check, keys: ["opening_status"]), recordValue(check, keys: ["holiday_or_event"]), recordValue(check, keys: ["ticket_status"]), recordValue(check, keys: ["reservation_status"]), recordValue(check, keys: ["details", "note"])].compactMap { $0 }.filter { !$0.isEmpty }
                        Text(details.isEmpty ? "Δεν υπάρχουν λεπτομέρειες επαλήθευσης." : details.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        if let checked = recordValue(check, keys: ["checked_at"]) { Text("Ελέγχθηκε \(checked)").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk) }
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }
    private var checklistContent: some View {
        let tasks = records(["booking_tasks", "checklist", "things_to_book"])
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Πριν φύγεις", systemImage: "checklist").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                Spacer()
                Text("\((activeTrip?.checklistDoneIDs ?? []).count) / \(tasks.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(AppPalette.brand)
            }
            if tasks.isEmpty {
                Text("Δεν υπάρχουν εργασίες κράτησης στο research.").font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                    let id = recordValue(task, keys: ["id", "task_id"]) ?? "task-\(index)-\(recordValue(task, keys: ["task", "title"]) ?? "")"
                    let done = (activeTrip?.checklistDoneIDs ?? []).contains(id)
                    VStack(alignment: .leading, spacing: 6) {
                        Button { toggleChecklist(id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19)).foregroundStyle(done ? AppPalette.brand : AppPalette.secondaryInk).padding(.top, 1)
                                Text(recordValue(task, keys: ["task", "title", "name"]) ?? "Εργασία \(index + 1)")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(done ? AppPalette.secondaryInk : AppPalette.ink)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        HStack(spacing: 8) {
                            if let priority = recordValue(task, keys: ["priority"]) {
                                Text(priority.uppercased()).font(.system(size: 8, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(Color(hex: "FFE7D9"), in: Capsule()).foregroundStyle(AppPalette.brand)
                            }
                            if let urgency = recordValue(task, keys: ["urgency_score"]).flatMap(Int.init), (1...10).contains(urgency) {
                                let urgencyColor = urgency >= 8 ? Color(hex: "D94A38") : (urgency >= 5 ? Color(hex: "D88A27") : Color(hex: "527968"))
                                HStack(spacing: 2) {
                                    ForEach(0..<min(3, max(1, Int(ceil(Double(urgency) / 3.4)))), id: \.self) { _ in
                                        Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                                    }
                                    Text("\(urgency)/10").font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                                }
                                .foregroundStyle(urgencyColor)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(urgencyColor.opacity(0.10), in: Capsule())
                                .accessibilityLabel("Επείγον \(urgency) από 10")
                            }
                            if let due = recordValue(task, keys: ["due_date", "deadline"]) {
                                Label(due, systemImage: "calendar").font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            if let url = recordValue(task, keys: ["url", "booking_url"]).flatMap(URL.init(string:)) {
                                Link(destination: url) { Label("Άνοιγμα κράτησης", systemImage: "arrow.up.right").font(.system(size: 9, weight: .semibold)) }
                                    .lineLimit(1)
                            }
                        }
                        if let reason = recordValue(task, keys: ["urgency_reason"]), !reason.isEmpty {
                            Text(reason).font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
            if let warnings = researchRoot["warnings"] as? [Any], !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Σημειώσεις έρευνας").font(.system(size: 10, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                    ForEach(Array(warnings.prefix(8).enumerated()), id: \.offset) { _, warning in
                        Label(warningText(warning), systemImage: "exclamationmark.circle")
                            .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 4)
            }
        }.padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
    private func toggleChecklist(_ id: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var done = trips[index].checklistDoneIDs ?? []
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        trips[index].checklistDoneIDs = done; trips[index].updatedAt = .now; TripStorage.save(trips)
    }

    private func reactionButton(_ symbol: String, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? AppPalette.brand : AppPalette.secondaryInk.opacity(0.72))
                .frame(width: 24, height: 22)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func addToDaySheet(date: String) -> some View {
        NavigationStack {
            List {
                ForEach(Array(placeRecords.enumerated()), id: \.offset) { index, place in
                    Button { addPlaceToDay(place, date: date); activeScheduleDate = nil } label: {
                        HStack(spacing: 12) {
                            Image(systemName: MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "").symbol)
                                .font(.title3).foregroundStyle(AppPalette.brand).frame(width: 32, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recordTitle(place) ?? "Επιλογή \(index + 1)").font(PlanType.heading).foregroundStyle(AppPalette.ink)
                                Text("\(recordValue(place, keys: ["category", "type"]) ?? "Πρόταση") · \(ratingLabel(place))")
                                    .font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(AppPalette.brand)
                        }.padding(.vertical, 3)
                    }.listRowBackground(AppPalette.surface)
                }
            }
            .scrollContentBackground(.hidden).background(AppPalette.canvas)
            .navigationTitle("Πρόσθεσε στη μέρα")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Τέλος") { activeScheduleDate = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func alternativesSheet(itemID: String) -> some View {
        let currentDay = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(itemID) }?.element ?? [:]
        let current = scheduledPlace(itemID, day: currentDay)
        let ranked = alternativePlaces(for: itemID)
        return NavigationStack {
            List {
                if let current {
                    Section("Αντικαθιστά") { Text(recordTitle(current) ?? "Τρέχουσα στάση").foregroundStyle(AppPalette.secondaryInk) }
                }
                Section("Άλλες επιλογές") {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { index, place in
                        Button {
                            replaceScheduleItem(itemID, with: place)
                            alternativesForItemID = nil
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "").symbol)
                                .font(.title3).foregroundStyle(AppPalette.brand).frame(width: 32, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recordTitle(place) ?? "Επιλογή").font(PlanType.heading).foregroundStyle(AppPalette.ink)
                                    Text(alternativeReason(place, for: current)).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                                    Text("\(priceLabel(place)) · \(ratingLabel(place))").font(PlanType.detail).foregroundStyle(AppPalette.brand)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.swap").foregroundStyle(AppPalette.brand)
                            }.padding(.vertical, 3)
                        }.listRowBackground(AppPalette.surface)
                    }
                    if ranked.isEmpty { Text("Δεν υπάρχουν άλλες επιλογές στο pool. Ζήτησε από το ChatGPT να επεκτείνει την έρευνα για αυτή την κατηγορία και περιοχή.").font(.footnote).foregroundStyle(AppPalette.secondaryInk) }
                }
                Section {
                    Button {
                        openAlternativeResearch(itemID)
                    } label: {
                        Label("Αναζήτηση περισσότερων επιλογών", systemImage: "magnifyingglass")
                            .font(PlanType.heading).foregroundStyle(AppPalette.brand)
                    }
                } footer: {
                    Text("Θα παραχθεί στοχευμένο prompt. Η απάντηση προστίθεται στο υπάρχον pool χωρίς να αντικαταστήσει το πρόγραμμα.")
                }
            }
            .scrollContentBackground(.hidden).background(AppPalette.canvas)
            .navigationTitle("Εναλλακτικές")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Τέλος") { alternativesForItemID = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func dayActivities(_ day: [String: Any]) -> [[String: Any]] {
        (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
    }
    private func scheduleDateKey(_ day: [String: Any], index: Int) -> String {
        recordValue(day, keys: ["date"]) ?? "day-\(index + 1)"
    }
    private func scheduleIDs(_ day: [String: Any], index: Int) -> [String] {
        let date = scheduleDateKey(day, index: index)
        if let saved = activeTrip?.scheduleOrderByDate?[date] { return saved }
        return dayActivities(day).indices.map { "stop|\(date)|\($0)" }
    }
    private func scheduledStop(_ id: String, day: [String: Any]) -> [String: Any]? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "stop", let index = Int(parts[2]) else { return nil }
        let stops = dayActivities(day)
        return stops.indices.contains(index) ? stops[index] : nil
    }
    private func scheduledPlace(_ id: String, day: [String: Any]) -> [String: Any]? {
        if id.hasPrefix("place|") {
            let placeID = String(id.dropFirst("place|".count))
            return placeRecords.first { recordValue($0, keys: ["id", "place_id"]) == placeID }
        }
        guard let placeID = scheduledStop(id, day: day).flatMap({ recordValue($0, keys: ["place_id"]) }) else { return nil }
        return placeRecords.first { recordValue($0, keys: ["id", "place_id"]) == placeID }
    }
    private func setScheduleOrder(_ order: [String], date: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var orders = trips[index].scheduleOrderByDate ?? [:]
        orders[date] = order
        trips[index].scheduleOrderByDate = orders
        trips[index].updatedAt = .now
        TripStorage.save(trips)
    }
    private func addPlaceToDay(_ place: [String: Any], date: String) {
        guard let placeID = recordValue(place, keys: ["id", "place_id"]),
              let located = dayRecords.enumerated().first(where: { scheduleDateKey($0.element, index: $0.offset) == date }) else { return }
        let current = scheduleIDs(located.element, index: located.offset)
        let id = "place|\(placeID)"
        guard !current.contains(id), !current.contains(where: { scheduledPlace($0, day: located.element).flatMap { recordValue($0, keys: ["id", "place_id"]) } == placeID }) else { showToast("Αυτό το μέρος υπάρχει ήδη στην ημέρα"); return }
        setScheduleOrder(current + [id], date: date)
    }
    private func removeScheduleItem(_ itemID: String, date: String, day: [String: Any]) {
        guard let located = dayRecords.enumerated().first(where: { scheduleDateKey($0.element, index: $0.offset) == date }) else { return }
        setScheduleOrder(scheduleIDs(day, index: located.offset).filter { $0 != itemID }, date: date)
    }
    private func moveScheduleItem(_ source: String, before target: String, date: String, day: [String: Any], index: Int) {
        var ids = scheduleIDs(day, index: index)
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target), from != to else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            ids.remove(at: from)
            let insertionIndex = ids.firstIndex(of: target) ?? min(to, ids.count)
            ids.insert(source, at: insertionIndex)
            setScheduleOrder(ids, date: date)
        }
    }
    private func setReaction(_ reaction: String, for itemID: String) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var reactions = trips[index].reactionsByItemID ?? [:]
        let newValue = reactions[itemID] == reaction ? nil : reaction
        reactions[itemID] = newValue
        if let day = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) })?.element,
           let placeID = scheduledPlace(itemID, day: day).flatMap({ recordValue($0, keys: ["id", "place_id"]) }) {
            reactions["place|\(placeID)"] = newValue
        }
        trips[index].reactionsByItemID = reactions
        trips[index].updatedAt = .now
        TripStorage.save(trips)
    }
    private func replaceScheduleItem(_ itemID: String, with place: [String: Any]) {
        guard let newID = recordValue(place, keys: ["id", "place_id"]),
              let located = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) }) else { return }
        let day = located.element
        let index = located.offset
        guard let position = scheduleIDs(day, index: index).firstIndex(of: itemID) else { return }
        let date = scheduleDateKey(day, index: index)
        var order = scheduleIDs(day, index: index)
        order[position] = "place|\(newID)"
        setScheduleOrder(order, date: date)
    }
    private func alternativePlaces(for itemID: String) -> [[String: Any]] {
        let day = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(itemID) }?.element ?? [:]
        let current = scheduledPlace(itemID, day: day)
        let currentID = current.flatMap { recordValue($0, keys: ["id", "place_id"]) }
        let currentCategory = current.flatMap { recordValue($0, keys: ["category", "type", "kind"]) }
        let currentTags = Set(current?["tags"] as? [String] ?? [])
        let origin = currentID.flatMap { resolvedCoordinates[$0] } ?? current.flatMap(placeCoordinate)
        let scheduledIDs = Set(dayRecords.enumerated().flatMap { index, day in
            scheduleIDs(day, index: index).compactMap { id in
                scheduledPlace(id, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) }
            }
        })
        return placeRecords.filter { recordValue($0, keys: ["id", "place_id"]) != currentID }
            .sorted { lhs, rhs in
                let lhsID = recordValue(lhs, keys: ["id", "place_id"]).map { "place|\($0)" }
                let rhsID = recordValue(rhs, keys: ["id", "place_id"]).map { "place|\($0)" }
                return alternativeScore(lhs, category: currentCategory, tags: currentTags, origin: origin) + reactionScore(lhsID) > alternativeScore(rhs, category: currentCategory, tags: currentTags, origin: origin) + reactionScore(rhsID)
            }
            .filter { place in
                guard let id = recordValue(place, keys: ["id", "place_id"]) else { return false }
                return !scheduledIDs.contains(id) || id == currentID
            }
    }
    private func alternativeScore(_ place: [String: Any], category: String?, tags: Set<String>, origin: CLLocationCoordinate2D?) -> Double {
        var score = 0.0
        let candidateCategory = recordValue(place, keys: ["category", "type", "kind"]) ?? ""
        if !candidateCategory.isEmpty, let category,
           candidateCategory.localizedCaseInsensitiveContains(category) || category.localizedCaseInsensitiveContains(candidateCategory) { score += 8 }
        let candidateTags = Set(place["tags"] as? [String] ?? [])
        score += Double(candidateTags.intersection(tags).count) * 2.5
        if let origin, let coordinate = placeCoordinate(place) {
            let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            score += max(0, 8 - meters / 1500)
        }
        if let rating = place["rating"] as? [String: Any], let value = rating["value"] as? NSNumber { score += value.doubleValue }
        if let reviews = place["rating"] as? [String: Any], let count = reviews["review_count"] as? NSNumber { score += min(3, log10(max(1, count.doubleValue))) }
        return score
    }
    private func reactionScore(_ itemID: String?) -> Double {
        guard let itemID else { return 0 }
        switch activeTrip?.reactionsByItemID?[itemID] {
        case "like": return 5
        case "dislike": return -12
        default: return 0
        }
    }
    private func alternativeReason(_ place: [String: Any], for current: [String: Any]?) -> String {
        if let current, let origin = placeCoordinate(current), let coordinate = placeCoordinate(place) {
            let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance < 1000 { return "\(Int(distance.rounded())) m από την τρέχουσα στάση" }
            if distance < 10_000 { return "\(String(format: "%.1f", distance / 1000)) km από την τρέχουσα στάση" }
        }
        if let currentCategory = current.flatMap({ recordValue($0, keys: ["category", "type", "kind"]) }),
           let category = recordValue(place, keys: ["category", "type", "kind"]), category == currentCategory { return "Ίδια κατηγορία · ταιριάζει στο πρόγραμμα" }
        if let currentArea = current.flatMap({ recordValue($0, keys: ["area", "neighborhood", "address"]) }),
           let area = recordValue(place, keys: ["area", "neighborhood", "address"]), currentArea == area { return "Κοντινή περιοχή · παρόμοια επιλογή" }
        return recordValue(place, keys: ["category", "type", "kind"]) ?? "Σχετική επιλογή από το pool"
    }
    private func placeCoordinate(_ place: [String: Any]) -> CLLocationCoordinate2D? {
        let id = recordValue(place, keys: ["id", "place_id"])
        // Fresh coordinates in the research must replace a stale search cache.
        if let coordinate = coordinateFromRecord(place) { return coordinate }
        if let id, let resolved = resolvedCoordinates[id], CLLocationCoordinate2DIsValid(resolved) { return resolved }
        if let id, let stored = activeTrip?.mapCoordinatesByPlaceID?[id], CLLocationCoordinate2DIsValid(stored.coordinate) { return stored.coordinate }
        return nil
    }

    private func dayCard(_ day: [String: Any], index: Int) -> some View {
        let isExpanded = expandedDayIndices.contains(index)
        let activities = (day["activities"] ?? day["stops"] ?? day["items"]) as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    if isExpanded { expandedDayIndices.remove(index) }
                    else { expandedDayIndices.insert(index) }
                }
            } label: {
                HStack(spacing: 11) {
                    TripCover(vibe: brief.vibes.first ?? "Πόλη", destination: brief.destination)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayTitle(day, index: index))
                            .font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                        Text(recordSummary(day))
                            .font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            if isExpanded && !activities.isEmpty {
                Divider().overlay(Color(hex: "EADFD5")).padding(.horizontal, 12)
                VStack(spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.offset) { _, activity in
                        HStack(alignment: .top, spacing: 10) {
                            Text(recordValue(activity, keys: ["time", "start_time"]) ?? "·")
                                .font(.custom("PlusJakartaSans-Bold", size: 10)).foregroundStyle(AppPalette.accent).frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activityTitle(activity)).font(.custom("PlusJakartaSans-SemiBold", size: 12)).foregroundStyle(AppPalette.ink)
                                Text(recordSummary(activity)).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "plus").font(.caption.weight(.medium)).foregroundStyle(AppPalette.secondaryInk)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                    }
                }
            }
        }
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color(hex: "E9DDD2"), lineWidth: 0.7))
    }

    private func placeCard(_ place: [String: Any], index: Int) -> some View {
        let id = recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)"
        let expanded = expandedPlanPlaceIDs.contains(id)
        let saved = activeTrip?.reactionsByItemID?["place|\(id)"] == "like"
        let category = MapPlaceCategory.classify(recordValue(place, keys: ["category", "type", "kind"]) ?? "")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: category.symbol).font(.title3).foregroundStyle(AppPalette.brand).frame(width: 32, height: 44)
                Button {
                    if expanded { expandedPlanPlaceIDs.remove(id) } else { expandedPlanPlaceIDs.insert(id) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recordTitle(place) ?? "Επιλογή \(index + 1)").font(PlanType.heading)
                        Text(category.rawValue).font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                        if let reason = recordValue(place, keys: ["why_recommended"]) { Text(reason).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk).lineLimit(expanded ? nil : 2) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Ανοίγει λεπτομέρειες και προσθήκη στο πρόγραμμα")
                Button { setReaction("like", for: "place|\(id)") } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(saved ? "Αφαίρεση από αγαπημένα" : "Κράτα την επιλογή")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageURL = recordValue(place, keys: ["image_url", "photo_url"]) {
                        PlaceImage(title: recordTitle(place) ?? "", imageURL: imageURL).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                        if let attribution = recordValue(place, keys: ["image_attribution"]) { Text(attribution).font(PlanType.detail) }
                    }
                    Text(recordSummary(place)).font(PlanType.body)
                    activityInsights(place)
                    if let url = recordValue(place, keys: ["official_url", "source_url", "url"]).flatMap(URL.init(string:)) {
                        Link("Επίσημη σελίδα", destination: url).font(PlanType.detail).frame(minHeight: 44)
                    }
                    if !dayRecords.isEmpty {
                        Menu {
                            ForEach(dayRecords.indices, id: \.self) { dayIndex in
                                Button("Ημέρα \(dayIndex + 1) · \(planDate(recordValue(dayRecords[dayIndex], keys: ["date"]) ?? ""))") {
                                    addPlaceToDay(place, date: scheduleDateKey(dayRecords[dayIndex], index: dayIndex))
                                }
                            }
                        } label: { Label("Πρόσθεσε σε ημέρα", systemImage: "plus").font(PlanType.heading).frame(minHeight: 44) }
                    }
                }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Divider()
        }.foregroundStyle(AppPalette.ink)
    }

    @ViewBuilder private func stageHeader(title: String, back: TripStage) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation { stage = back } } label: {
                Image(systemName: "arrow.left").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.ink).frame(width: 42, height: 42)
                    .modifier(AdaptiveGlassControl(shape: .circle))
            }
            if !title.isEmpty {
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(AppPalette.ink).lineLimit(1)
            }
            Spacer()
            if back == .library && stage != .brief {
                Button { withAnimation { darkMode.toggle() } } label: {
                    Image(systemName: darkMode ? "sun.max" : "moon").foregroundStyle(AppPalette.ink).frame(width: 42, height: 42).modifier(AdaptiveGlassControl(shape: .circle))
                }
            }
        }
        .padding(.horizontal, 20).frame(height: 50)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputField(_ title: String, placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
            TextField(placeholder, text: text, axis: axis)
                .font(.body).padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipGrid(options: [String], selection: Binding<Set<String>>) -> some View {
        PillFlowLayout {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue.contains(option)
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        if selected { selection.wrappedValue.remove(option) }
                        else { selection.wrappedValue.insert(option) }
                    }
                } label: {
                    choicePill(option, selected: selected)
                        .scaleEffect(selected ? 1.035 : 1)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: selection.wrappedValue)
    }

    private func dashboardSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12, content: content).padding(.top, 10)
        } label: {
            Label(title, systemImage: symbol).font(.headline.weight(.semibold)).foregroundStyle(AppPalette.ink)
        }
        .tint(AppPalette.accent)
        .padding(16)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func infoPanel<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func metricCard(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent)
                        Text(value).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(AppPalette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(AppPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func createTrip(from initialBrief: TripBrief = TripBrief()) {
        briefStep = 0
        resolvedCoordinates = [:]; destinationCoordinate = nil
        selectedMapDay = nil; selectedScheduleDayIndex = nil
        activeScheduleDate = nil; alternativesForItemID = nil
        showTripDetails = false
        let trip = Trip(brief: initialBrief)
        trips.insert(trip, at: 0)
        activeTripID = trip.id
        brief = trip.brief
        selectedCard = 0
        selectedScrollID = 0
        TripStorage.save(trips)
    }

    private func startNewTrip() {
        guard stage != .brief else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
            createTrip()
            stage = .brief
        }
    }

    private func editTrip(_ trip: Trip) {
        activeTripID = trip.id
        brief = trip.brief
        cardDrag = 0
        openBrief()
    }

    private func deleteTrip(_ id: UUID) {
        guard trips.contains(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            trips.removeAll { $0.id == id }
            cardDrag = 0
            briefReveal = 0
            gestureTripID = nil
            selectedCard = min(selectedCard, max(0, trips.count - 1))
            selectedScrollID = trips.isEmpty ? nil : selectedCard
            if activeTripID == id {
                activeTripID = nil; brief = TripBrief(); stage = .library
                showTripDetails = false; resolvedCoordinates = [:]; destinationCoordinate = nil
            }
        }
        TripStorage.save(trips)
    }

    private func finishBriefReveal() {
        isRevealingBrief = true
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.42, extraBounce: 0)
        withAnimation(animation, completionCriteria: .removed) {
            briefReveal = 1
            cardDrag = 0
        } completion: {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // The same brief is already in its final position; only enable interaction.
                stage = .brief
                briefReveal = 0
                gestureTripID = nil
                isRevealingBrief = false
            }
        }
    }

    private func openBrief() {
        briefStep = 0
        withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) { stage = .brief }
    }

    private func saveDraft() {
        guard let id = activeTripID, let index = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[index].brief = brief
        trips[index].updatedAt = .now
        TripStorage.save(trips)
    }

    private func copyPrompt() {
        UIPasteboard.general.string = prompt
        showToast("Το prompt αντιγράφηκε")
    }

    private func openAlternativeResearch(_ itemID: String) {
        guard let located = dayRecords.enumerated().first(where: { scheduleIDs($0.element, index: $0.offset).contains(itemID) }) else { return }
        let place = scheduledPlace(itemID, day: located.element)
        let stop = scheduledStop(itemID, day: located.element)
        let activity = stop.flatMap { recordValue($0, keys: ["activity", "title", "name"]) }
        pendingPrompt = ResearchPrompt.makeAlternatives(
            brief: brief,
            currentPlace: place,
            activity: activity,
            placePool: placeRecords,
            reactions: activeTrip?.reactionsByItemID ?? [:],
            selectedRegion: selectedRegion
        )
        alternativesForItemID = nil
        showPromptSheet = true
    }

    private func importResearch() {
        guard let (source, parsedObject) = Self.parseResearchJSON(importText) else {
            importError = "Δεν βρέθηκε έγκυρο αντικείμενο JSON. Επικόλλησε όλη την απάντηση ή εισήγαγε το αρχείο .json που δημιούργησε το ChatGPT."
            return
        }
        var object = parsedObject
        var sourceToStore = source
        if object["schema_version"] as? String == "trippy-research-patch-v2" {
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }),
                  let existing = trips[index].research,
                  let existingData = existing.data(using: .utf8),
                  var merged = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                importError = "Χρειάζεται να εισαγάγεις πρώτα το Foundation JSON πριν από έλεγχο ή σύνθεση patch."
                return
            }
            for (key, value) in object["set"] as? [String: Any] ?? [:] { merged[key] = value }
            for (key, value) in object["replace"] as? [String: Any] ?? [:] { merged[key] = value }
            for (key, incomingRows) in object["upsert"] as? [String: [[String: Any]]] ?? [:] {
                var rows = merged[key] as? [[String: Any]] ?? []
                for incoming in incomingRows {
                    guard let id = recordValue(incoming, keys: ["id", "place_id", "event_id", "task_id"]) else { continue }
                    if let index = rows.firstIndex(where: { recordValue($0, keys: ["id", "place_id", "event_id", "task_id"]) == id }) {
                        rows[index].merge(incoming) { _, new in new }
                    } else {
                        rows.append(incoming)
                    }
                }
                merged[key] = rows
            }
            let newWarnings = object["warnings"] as? [[String: Any]] ?? []
            if !newWarnings.isEmpty { merged["warnings"] = (merged["warnings"] as? [[String: Any]] ?? []) + newWarnings }
            object = merged
            guard let mergedData = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
                  let mergedString = String(data: mergedData, encoding: .utf8) else {
                importError = "Το patch δεν μπόρεσε να συγχωνευτεί με την υπάρχουσα έρευνα."
                return
            }
            sourceToStore = mergedString
        } else if object["schema_version"] as? String == "trippy-research-patch-v1" {
            guard let index = trips.firstIndex(where: { $0.id == activeTripID }),
                  let existing = trips[index].research,
                  let existingData = existing.data(using: .utf8),
                  var merged = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                importError = "Το αποτέλεσμα είναι ενημέρωση pool, αλλά δεν υπάρχει προηγούμενη έρευνα για να επεκταθεί."
                return
            }
            for (patchKey, targetKey) in [("add_places", "places"), ("add_sources", "sources")] {
                let existingRows = merged[targetKey] as? [[String: Any]] ?? []
                let newRows = object[patchKey] as? [[String: Any]] ?? []
                var seen = Set(existingRows.compactMap { recordValue($0, keys: ["id", "place_id"]) })
                merged[targetKey] = existingRows + newRows.filter { row in
                    guard let id = recordValue(row, keys: ["id", "place_id"]) else { return false }
                    return seen.insert(id).inserted
                }
            }
            let oldWarnings = merged["warnings"] as? [[String: Any]] ?? []
            let newWarnings = object["warnings"] as? [[String: Any]] ?? []
            merged["warnings"] = oldWarnings + newWarnings
            object = merged
            guard let mergedData = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
                  let mergedString = String(data: mergedData, encoding: .utf8) else {
                importError = "Δεν μπόρεσα να συνδυάσω το νέο pool με την υπάρχουσα έρευνα."
                return
            }
            sourceToStore = mergedString
        } else if object["schema_version"] == nil || object["schema_version"] as? String != "trippy-research-v1" {
            importError = "Το αρχείο είναι έγκυρο JSON, αλλά δεν ταιριάζει με το αναμενόμενο Trippy schema ή patch."
            return
        }
        if activeTripID == nil { createTrip() }
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        object = PlanImportReconciliation.apply(object, to: &trips[index])
        guard let reconciledData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let reconciledSource = String(data: reconciledData, encoding: .utf8) else {
            importError = "Δεν μπόρεσα να διατηρήσω τις επιλογές σου κατά την εισαγωγή."
            return
        }
        sourceToStore = reconciledSource
        trips[index].research = sourceToStore
        trips[index].brief = brief
        trips[index].updatedAt = .now
        TripStorage.save(trips)
        pendingPrompt = nil
        withAnimation { stage = .workspace }
    }

    private func startLiveResearch() {
        guard !isResearching, !brief.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activeTripID == nil { createTrip(from: brief) }
        guard let requestedTripID = activeTripID, let requestedTripIndex = trips.firstIndex(where: { $0.id == requestedTripID }) else { return }
        let researchBaseURL = trips[requestedTripIndex].researchBridgeURL ?? bridgeBaseURL
        let resumableJobID = trips[requestedTripIndex].researchJobID
        if resumableJobID == nil { trips[requestedTripIndex].brief = brief; TripStorage.save(trips) }
        completedResearchSteps = []
        researchNeedsServiceUpdate = false
        researchSaved = false
        researchPartial = false
        researchDestination = brief.destination
        researchResultTripID = requestedTripID
        isResearching = true
        liveResearchError = nil
        liveResearchDiagnostic = nil
        researchNeedsNewRequest = false
        researchPhaseStates = [:]
        recoverableResearch = nil
        liveResearchStep = 1
        researchOperations = [ResearchOperation(step: 1, detail: "Συνδεόμαστε με την υπηρεσία έρευνας…")]
        showLiveResearchSheet = true

        let briefContext: [String: Any] = [
            "destination": brief.destination,
            "date_range": [
                "arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                "dates_unknown": brief.dateIsUnknown,
                "duration_days": brief.duration
            ] as [String: Any],
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget": brief.budget,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "dietary_needs": brief.dietaryNeeds.sorted(),
            "mobility_requirements": brief.mobility.sorted(),
            "stay_style": brief.stayStyle,
            "custom_instructions": brief.notes,
            "existing_places": Array(placeRecords.prefix(150)),
            "existing_sources": Array(sourceRecords.prefix(150)),
            "excluded_place_ids": (activeTrip?.reactionsByItemID ?? [:]).compactMap { key, value in
                value == "dislike" && key.hasPrefix("place|") ? String(key.dropFirst(6)) : nil
            },
            "pace": pace < 0.34 ? "χαλαρός" : (pace > 0.66 ? "εντατικός" : "ισορροπημένος")
        ]

        liveResearchTask = Task {
            var requestStage = ResearchRequestStage.preflight
            var activeJobID = resumableJobID
            do {
                // Check compatibility before starting either paid AI request.
                guard let preflightURL = URL(string: "\(researchBaseURL)/api/status") else { throw URLError(.badURL) }
                var preflight = URLRequest(url: preflightURL, cachePolicy: .reloadIgnoringLocalCacheData)
                preflight.timeoutInterval = 60
                let (statusData, preflightResponse) = try await URLSession.shared.data(for: preflight)
                try Task.checkCancellation()
                let status = try ResearchTransport.checkedJSON(statusData, response: preflightResponse, stage: .preflight, checkResearchReadiness: resumableJobID == nil)
                guard (status["api_version"] as? Int ?? 0) >= 3,
                      (status["research_contract_version"] as? Int ?? 0) >= 4,
                      status["result_schema"] as? String == "trippy-research-v1" else {
                    await MainActor.run {
                        researchNeedsServiceUpdate = true
                        if status["step"] as? String == "completed", let result = status["result"] as? [String: Any] {
                            recoverableResearch = result
                            recoveryContext = status["request_context"] as? [String: Any] ?? briefContext
                            researchOperations = []
                            liveResearchError = "Η υπηρεσία χρειάζεται ενημέρωση. Μπορείς να ανακτήσεις το υπάρχον πλάνο χωρίς νέα έρευνα."
                        } else {
                            liveResearchError = "Η υπηρεσία δεν έχει ακόμη τη νέα έκδοση του σχεδιαστή. Η έρευνα δεν ξεκίνησε και δεν έγινε χρέωση."
                        }
                        isResearching = false
                    }
                    return
                }
                await MainActor.run {
                    completedResearchSteps.insert(1)
                    recordResearchOperation(2, detail: resumableJobID == nil ? "Αναζητούμε επιλογές για το ταξίδι σου…" : "Ανακτούμε την αποθηκευμένη έρευνα…")
                }
                let jobID: String
                requestStage = .start
                if let existingJobID = resumableJobID { jobID = existingJobID }
                else {
                guard let url = URL(string: "\(researchBaseURL)/api/research") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: briefContext)

                let (startData, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 409 {
                    await MainActor.run {
                        liveResearchError = "Υπάρχει ήδη έρευνα σε εξέλιξη στην υπηρεσία. Περίμενε να ολοκληρωθεί και δοκίμασε ξανά."
                        liveResearchDiagnostic = "start: HTTP 409, research_already_running"
                        isResearching = false
                    }
                    return
                }

                let started = try ResearchTransport.checkedJSON(startData, response: response, stage: .start)
                guard
                      let createdJobID = started["job_id"] as? String, UUID(uuidString: createdJobID) != nil else {
                    throw URLError(.cannotParseResponse)
                }
                jobID = createdJobID
                activeJobID = createdJobID
                await MainActor.run {
                    if let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                        trips[index].researchJobID = jobID; trips[index].researchBridgeURL = researchBaseURL
                        TripStorage.save(trips)
                    }
                }
                }
                requestStage = .status
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1.5))
                    guard let statusURL = URL(string: "\(researchBaseURL)/api/status?job_id=\(jobID)") else { throw URLError(.badURL) }
                    let json = try await ResearchTransport.status(url: statusURL)
                    try Task.checkCancellation()

                    let isRunning = json["is_running"] as? Bool ?? false
                    let step = json["step"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    let result = json["result"] as? [String: Any]
                    let currentTask = json["current_task"] as? String ?? ""
                    let completedPhases = json["completed_research_phases"] as? [Int] ?? []
                    let serverErrorCode = json["error_code"] as? String ?? "research_failed"

                    await MainActor.run {
                        completedResearchSteps = ResearchOperation.completedPhases(completedPhases).union([1])
                        researchPhaseStates = ResearchDiagnostics.phaseStates(json)
                        if let phase = ResearchOperation.phase(serverStep: step, task: currentTask) {
                            recordResearchOperation(phase, detail: msg)
                        }
                        else if !isRunning && (step == "completed" || step == "partial") {
                            researchPartial = step == "partial"
                            recordResearchOperation(5, detail: "Αποθηκεύουμε το πλάνο σου…")
                            if let result {
                                finishLiveResearch(result, context: briefContext, targetTripID: requestedTripID)
                            } else {
                                liveResearchError = "Η υπηρεσία ολοκλήρωσε την έρευνα χωρίς έγκυρο αποτέλεσμα. Δοκίμασε ξανά."
                                isResearching = false
                            }
                        } else if step == "error" || step == "interrupted" {
                            if let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                                trips[index].forgetResearchJob(matching: jobID)
                                TripStorage.save(trips)
                            }
                            researchNeedsNewRequest = true
                            liveResearchError = step == "interrupted" ? "Η έρευνα διακόπηκε στην υπηρεσία. Μπορείς να ξεκινήσεις νέα έρευνα. Το αποθηκευμένο πλάνο και οι επιλογές σου διατηρούνται." : (msg.isEmpty ? "Η υπηρεσία δεν μπόρεσε να ολοκληρώσει την έρευνα. Μπορείς να ξεκινήσεις νέο αίτημα." : msg)
                            if serverErrorCode.count < 100 && serverErrorCode.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_") }) {
                                liveResearchDiagnostic = "status: " + serverErrorCode + "\n" + (ResearchDiagnostics.summary(json) ?? "")
                            }
                            isResearching = false
                        }
                    }

                    if !isRunning && (step == "completed" || step == "partial") { break }
                    if step == "error" || step == "interrupted" { break }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let failure = error as? ResearchRequestError {
                        liveResearchError = failure.message
                        liveResearchDiagnostic = failure.diagnostic
                        if failure.requiresNewJob, let activeJobID,
                           let index = trips.firstIndex(where: { $0.id == requestedTripID }) {
                            trips[index].forgetResearchJob(matching: activeJobID)
                            TripStorage.save(trips)
                            researchNeedsNewRequest = true
                        }
                    } else {
                        let code = (error as? URLError)?.code.rawValue ?? (error as NSError).code
                        liveResearchDiagnostic = "\(requestStage.rawValue): \(type(of: error)), code \(code)"
                        if (error as? URLError)?.code == .notConnectedToInternet {
                            liveResearchError = "Δεν υπάρχει σύνδεση στο διαδίκτυο. Η έρευνα που έχει ήδη ξεκινήσει διατηρείται στην υπηρεσία· δοκίμασε ξανά όταν συνδεθείς."
                        } else {
                            liveResearchError = "Η υπηρεσία δεν απάντησε εγκαίρως ή διακόπηκε η σύνδεση. Η έρευνα μπορεί να συνεχίζεται· έλεγξε ξανά την κατάστασή της."
                        }
                    }
                    isResearching = false
                }
            }
        }
    }

    private func cancelLiveResearch() {
        liveResearchTask?.cancel()
        liveResearchTask = nil
        isResearching = false
        showLiveResearchSheet = false
    }

    // The old bridge returns a self-contained candidate pool in a patch envelope.
    // Recover it only in the live pipeline; manual update patches still require a foundation.
    private static func foundationFromLiveResult(_ result: [String: Any], context: [String: Any]) -> [String: Any] {
        guard result["schema_version"] as? String == "trippy-research-patch-v2" else { return result }
        var foundation: [String: Any] = [
            "schema_version": "trippy-research-v1", "trip_context": context,
            "overview": [:], "map_overview": [:], "calendar_checks": [], "date_checks": [],
            "places": [], "events": [], "itinerary": ["days": []], "map_views": [],
            "transport_options": [], "ticket_options": [], "costs": [:], "booking_tasks": [],
            "sources": [], "warnings": [], "assumptions": []
        ]
        for section in ["set", "replace", "upsert"] {
            for (key, value) in result[section] as? [String: Any] ?? [:] where key != "schema_version" {
                foundation[key] = value
            }
        }
        var tripContext = foundation["trip_context"] as? [String: Any] ?? context
        if let destination = foundation["destination"] as? String { tripContext["destination"] = destination }
        foundation["trip_context"] = tripContext
        var warnings = result["warnings"] as? [[String: Any]] ?? []
        warnings.append(["id": "legacy-bridge-recovery", "severity": "info", "message": "Ανακτήθηκε το υπάρχον αποτέλεσμα χωρίς νέα έρευνα. Περιλαμβάνει μόνο τα δεδομένα που επέστρεψε η υπηρεσία· δεν δημιουργήθηκε επιπλέον πρόγραμμα."])
        foundation["warnings"] = warnings
        return foundation
    }

    private func finishLiveResearch(_ result: [String: Any], context: [String: Any], recover: Bool = false, targetTripID: UUID? = nil) {
        let document = recover ? Self.foundationFromLiveResult(result, context: context) : result
        liveResearchDiagnostic = ResearchDiagnostics.summary(document)
        researchPhaseStates = ResearchDiagnostics.phaseStates(document)
        guard ResearchDiagnostics.hasPlaces(document) else {
            completedResearchSteps.remove(4)
            researchPhaseStates[4] = "empty"
            liveResearchError = "Δεν δημιουργήθηκε πλάνο: η έρευνα δεν επέστρεψε επιλογές. Το προηγούμενο πλάνο και οι αλλαγές σου διατηρούνται."
            isResearching = false
            researchNeedsNewRequest = true
            if let index = trips.firstIndex(where: { $0.id == (targetTripID ?? activeTripID) }) {
                trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil
                TripStorage.save(trips)
            }
            return
        }
        completedResearchSteps = ResearchOperation.completedPhases((document["pipeline_report"] as? [String: Any])?["completed_research_phases"] as? [Int] ?? []).union(recover ? [] : [1])
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              let text = String(data: data, encoding: .utf8) else {
            liveResearchError = "Το αποτέλεσμα δεν μπόρεσε να διαβαστεί."
            isResearching = false
            return
        }
        if recover, let destination = (document["trip_context"] as? [String: Any])?["destination"] as? String {
            brief.destination = destination
        }
        if let targetTripID, targetTripID != activeTripID {
            guard let index = trips.firstIndex(where: { $0.id == targetTripID }) else {
                liveResearchError = "Το ταξίδι της έρευνας έχει αφαιρεθεί."; isResearching = false; return
            }
            let reconciled = PlanImportReconciliation.apply(document, to: &trips[index])
            guard let data = try? JSONSerialization.data(withJSONObject: reconciled), let stored = String(data: data, encoding: .utf8) else {
                liveResearchError = "Το αποτέλεσμα δεν μπόρεσε να αποθηκευτεί."; isResearching = false; return
            }
            trips[index].research = stored; trips[index].updatedAt = .now
            trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil
            TripStorage.save(trips); isResearching = false; liveResearchError = nil
            researchSaved = true; researchPartial = reconciled["delivery_status"] as? String != "ready"
            completedResearchSteps.insert(5)
            return
        }
        importText = text
        importError = nil
        importResearch()
        isResearching = false
        if let error = importError {
            liveResearchError = error
            importError = nil
        } else {
            if let index = trips.firstIndex(where: { $0.id == (targetTripID ?? activeTripID) }) {
                trips[index].researchJobID = nil; trips[index].researchBridgeURL = nil; TripStorage.save(trips)
            }
            recoverableResearch = nil
            liveResearchError = nil
            if recover { recordResearchOperation(5, detail: "Το αποτέλεσμα ανακτήθηκε και αποθηκεύτηκε.") }
            researchSaved = true
            let storedData = activeTrip?.research?.data(using: .utf8)
            let storedDocument = storedData.flatMap { data -> [String: Any]? in
                try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            researchPartial = storedDocument?["delivery_status"] as? String != "ready"
            completedResearchSteps.insert(5)
        }
    }

    private func recordResearchOperation(_ step: Int, detail: String) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)) {
            liveResearchStep = step
            if let index = researchOperations.firstIndex(where: { $0.step == step }) {
                researchOperations[index].detail = detail
            } else {
                researchOperations.append(ResearchOperation(step: step, detail: detail))
            }
        }
    }

    private var liveResearchSheet: some View {
        ResearchProgressScreen(
            destination: researchDestination,
            operations: researchOperations,
            currentStep: liveResearchStep,
            completedSteps: completedResearchSteps,
            running: isResearching,
            saved: researchSaved,
            partial: researchPartial,
            error: liveResearchError,
            needsServiceUpdate: researchNeedsServiceUpdate,
            canRecover: recoverableResearch != nil,
            resuming: trips.first(where: { $0.id == researchResultTripID })?.researchJobID != nil,
            needsNewRequest: researchNeedsNewRequest,
            diagnostic: liveResearchDiagnostic,
            phaseStates: researchPhaseStates,
            onClose: { cancelLiveResearch() },
            onRetry: { startLiveResearch() },
            onSettings: { researchOpenSettingsAfterDismiss = true; cancelLiveResearch() },
            onRecover: {
                if let result = recoverableResearch { finishLiveResearch(result, context: recoveryContext, recover: true) }
            },
            onOpenPlan: {
                cancelLiveResearch()
                if let id = researchResultTripID, let trip = trips.first(where: { $0.id == id }) { selectMapTrip(trip) }
                showTripDetails = true
            }
        )
    }

    private var calendarNightCount: Int {
        TripCalendarSelection(start: parseISODate(brief.startDate), end: parseISODate(brief.endDate)).nights
    }

    private func holidayContext(start: Date, end: Date, holidays: [DestinationHoliday]) -> [String] {
        let firstDay = isoDate(start)
        let lastDay = isoDate(end)
        guard lastDay > firstDay else { return [] }
        return holidays.compactMap { holiday -> (date: String, text: String)? in
            guard let year = holiday.date.year,
                  let month = holiday.date.month,
                  let day = holiday.date.day,
                  (1...12).contains(month), (1...31).contains(day) else { return nil }
            let holidayDate = String(format: "%04d-%02d-%02d", year, month, day)
            guard holidayDate >= firstDay, holidayDate <= lastDay else { return nil }
            let kind = holiday.kind == .publicHoliday ? "εθνική αργία" : "τοπική αργία"
            return (holidayDate, "\(holidayDate) · \(holiday.localName) (\(holiday.name), \(kind))")
        }
        .sorted { $0.date < $1.date }
        .map(\.text)
    }

    private var calendarPickerSheet: some View {
        TripCalendarSheet(
            destination: resolvedDestination.isEmpty ? brief.title : resolvedDestination,
            start: parseISODate(brief.startDate), end: parseISODate(brief.endDate),
            holidays: calendarHolidays, isLoading: isLoadingHolidays, status: holidayStatus,
            onYearChange: { month in
                calendarDisplayedMonth = month
                loadHolidays(for: brief.destination)
            },
            onApply: { start, end, nights in
                var updatedBrief = brief
                updatedBrief.startDate = isoDate(start)
                updatedBrief.endDate = isoDate(end)
                updatedBrief.dateIsUnknown = false
                updatedBrief.duration = nights + 1
                updatedBrief.dateContext = holidayContext(start: start, end: end, holidays: calendarHolidays)
                brief = updatedBrief
                showCalendarPicker = false
            },
            onCancel: { showCalendarPicker = false }
        )
    }

    private func searchDestinations(_ text: String) {
        destinationSearchTask?.cancel()
        destinationCompleter.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            destinationSuggestions = []
            return
        }
        destinationSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            destinationCompleter.search(query) { [query] completions in
                guard brief.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(query) == .orderedSame else { return }
                var seen = Set<String>()
                destinationSuggestions = completions.compactMap { completion in
                    let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    let fullQuery = [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                    let key = fullQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    guard seen.insert(key).inserted else { return nil }
                    return DestinationSuggestion(id: key, title: title, subtitle: subtitle, query: fullQuery)
                }.prefix(8).map { $0 }
            }
        }
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private func loadHolidays(for destination: String, debounce: Bool = false) {
        holidayTask?.cancel()
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            calendarHolidays = []
            isLoadingHolidays = false
            holidayStatus = "Επίλεξε προορισμό για να φορτωθούν οι αργίες."
            return
        }
        let year = Calendar.current.component(.year, from: calendarDisplayedMonth)
        isLoadingHolidays = true
        holidayStatus = "Αναζήτηση προορισμού και αργιών…"
        holidayTask = Task { @MainActor in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(900)) }
                try Task.checkCancellation()
                let location: HolidayLocation
                if let cachedLocation = resolvedHolidayLocation, cachedLocation.query == query {
                    location = cachedLocation
                } else {
                    let placemarks = try await CLGeocoder().geocodeAddressString(query)
                    try Task.checkCancellation()
                    guard let placemark = placemarks.first, let country = placemark.isoCountryCode else {
                        holidayStatus = "Δεν αναγνωρίστηκε ο προορισμός. Δοκίμασε πόλη και χώρα."
                        isLoadingHolidays = false
                        return
                    }
                    let region = placemark.administrativeArea?.uppercased()
                    location = HolidayLocation(query: query, countryCode: country, regionCode: region.map { "\(country)-\($0)" },
                                               displayName: [placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", "))
                    resolvedHolidayLocation = location
                }
                resolvedDestination = location.displayName
                let cacheKey = "\(location.countryCode)|\(location.regionCode ?? "")|\(year)"
                if let cached = holidayCache[cacheKey] {
                    calendarHolidays = cached
                    holidayStatus = cached.isEmpty ? "Δεν βρέθηκαν αργίες για αυτόν τον προορισμό." : "Οι αργίες είναι έτοιμες."
                    isLoadingHolidays = false
                    return
                }
                guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(location.countryCode)") else { return }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 204 || http.statusCode == 404 {
                    holidayCache[cacheKey] = []
                    calendarHolidays = []
                    holidayStatus = "Δεν υπάρχουν δεδομένα αργιών για αυτή τη χώρα. Μπορείς να επιλέξεις ημερομηνίες κανονικά."
                    isLoadingHolidays = false
                    return
                }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                let entries = try JSONDecoder().decode([PublicHolidayResponse].self, from: data)
                let holidays = entries.filter { entry in
                    entry.types.contains("Public") && (entry.global || location.regionCode.map { entry.counties?.contains($0) == true } == true)
                }.compactMap { entry -> DestinationHoliday? in
                    guard let date = parseISODate(entry.date) else { return nil }
                    return DestinationHoliday(date: Calendar.current.dateComponents([.year, .month, .day], from: date),
                                              name: entry.name, localName: entry.localName,
                                              kind: entry.global ? .publicHoliday : .localCelebration)
                }
                holidayCache[cacheKey] = holidays
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { calendarHolidays = holidays }
                holidayStatus = holidays.isEmpty ? "Δεν βρέθηκαν αργίες για αυτόν τον προορισμό." : "Οι αργίες είναι έτοιμες."
                isLoadingHolidays = false
            } catch {
                guard !Task.isCancelled else { return }
                calendarHolidays = []
                isLoadingHolidays = false
                holidayStatus = "Οι αργίες δεν είναι διαθέσιμες αυτή τη στιγμή. Μπορείς να επιλέξεις ημερομηνίες κανονικά."
            }
        }
    }

    private static func parseResearchJSON(_ input: String) -> (String, [String: Any])? {
        var text = input.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let firstLineEnd = text.firstIndex(of: "\n")
            if let firstLineEnd, let closing = text.range(of: "```", options: .backwards), closing.lowerBound > firstLineEnd {
                text = String(text[text.index(after: firstLineEnd)..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0 { end = text.index(after: index); break }
            }
        }
        guard let end else { return nil }
        let json = String(text[start..<end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json, object)
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { withAnimation { toast = nil } } }
    }

    private var researchRoot: [String: Any] {
        guard let raw = activeTrip?.research, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private var placeRecords: [[String: Any]] {
        let keys = ["places", "place_options", "restaurants", "attractions", "bars", "clubs", "museums"]
        var seen = Set<String>()
        return keys.flatMap { key -> [[String: Any]] in
            if let values = researchRoot[key] as? [[String: Any]] { return values }
            if let object = researchRoot[key] as? [String: Any], let values = object["items"] as? [[String: Any]] { return values }
            return []
        }.filter { place in
            let identity = (recordValue(place, keys: ["id", "place_id"]) ?? recordTitle(place) ?? UUID().uuidString).lowercased()
            return seen.insert(identity).inserted
        }
    }
    private var dayRecords: [[String: Any]] {
        if let itinerary = researchRoot["itinerary"] as? [String: Any],
           let days = itinerary["days"] as? [[String: Any]] { return days }
        if let days = records(["days", "day_plans"]).first { return days["days"] as? [[String: Any]] ?? [days] }
        return []
    }
    private var sourceRecords: [[String: Any]] { records(["sources", "references"]) }
    private var mapPoints: [ResearchMapPoint] {
        let places = placeRecords.enumerated().compactMap { index, place -> ResearchMapPoint? in
            guard let coordinate = placeCoordinate(place), (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else { return nil }
            return ResearchMapPoint(id: recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)", title: recordTitle(place) ?? "Μέρος", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let knownIDs = Set(places.map(\.id))
        let itineraryStops = dayRecords.enumerated().flatMap { dayIndex, day in
            scheduleIDs(day, index: dayIndex).enumerated().compactMap { stopIndex, itemID -> ResearchMapPoint? in
                guard let stop = scheduledStop(itemID, day: day), let coordinate = coordinateFromRecord(stop) else { return nil }
                let placeID = recordValue(stop, keys: ["place_id"])
                let id = placeID ?? itemID
                guard !knownIDs.contains(id) else { return nil }
                return ResearchMapPoint(id: id, title: "\(dayIndex + 1).\(stopIndex + 1) · \(recordValue(stop, keys: ["activity", "name", "title"]) ?? "Στάση")", latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
        var seen = Set<String>()
        return (places + itineraryStops).filter { seen.insert($0.id).inserted }
    }
    private var plannedMapLabels: [String: String] {
        var labels: [String: String] = [:]
        for (dayIndex, day) in dayRecords.enumerated() {
            for (stopIndex, itemID) in scheduleIDs(day, index: dayIndex).enumerated() {
                guard let place = scheduledPlace(itemID, day: day),
                      let placeID = recordValue(place, keys: ["id", "place_id"]) else { continue }
                labels[placeID] = "\(dayIndex + 1).\(stopIndex + 1)"
            }
        }
        return labels
    }
    private func mapPoints(for day: [String: Any], index: Int) -> [ResearchMapPoint] {
        scheduleIDs(day, index: index).enumerated().compactMap { stopIndex, itemID in
            let place = scheduledPlace(itemID, day: day)
            let stop = scheduledStop(itemID, day: day)
            guard let coordinate = planCoordinate(itemID, day: day) else { return nil }
            let id = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID
            let title = place.flatMap(recordTitle) ?? stop.flatMap { recordValue($0, keys: ["activity", "name", "title"]) } ?? "Στάση"
            return ResearchMapPoint(id: id, title: "\(stopIndex + 1) · \(title)", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
    private func coordinateFromRecord(_ record: [String: Any]) -> CLLocationCoordinate2D? {
        let raw = record["coordinates"] as? [String: Any] ?? record["location"] as? [String: Any] ?? record
        guard let lat = numericValue(raw, keys: ["latitude", "lat"]), let lon = numericValue(raw, keys: ["longitude", "lng", "lon"]), (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private func resolvePlaceCoordinates() async {
        let tripID = activeTripID
        let destination = brief.destination
        let places = placeRecords
        isResolvingCoordinates = true
        defer { if activeTripID == tripID { isResolvingCoordinates = false } }
        func current() -> Bool { !Task.isCancelled && activeTripID == tripID && brief.destination == destination }
        if destinationCoordinate == nil, !destination.isEmpty {
            destinationCoordinate = cityCoordinates[destination]?.coordinate
            if destinationCoordinate == nil {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = destination
                let search = MKLocalSearch(request: request)
                let response = try? await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
                guard current() else { return }
                destinationCoordinate = response?.mapItems.first?.placemark.coordinate
            }
        }
        guard current() else { return }
        for (id, stored) in activeTrip?.mapCoordinatesByPlaceID ?? [:] { resolvedCoordinates[id] = stored.coordinate }
        for place in places {
            guard current() else { return }
            guard placeCoordinate(place) == nil, let id = recordValue(place, keys: ["id", "place_id"]), let name = recordTitle(place) else { continue }
            let address = recordValue(place, keys: ["address", "area", "neighborhood"])
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = [name, address, destination].compactMap { $0 }.joined(separator: ", ")
            if let center = destinationCoordinate { request.region = .init(center: center, span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4)) }
            let search = MKLocalSearch(request: request)
            let response = try? await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
            guard current() else { return }
            // Auto-locate only an unambiguous exact venue name near the destination.
            // Multiple branches and loose search matches require a user's pin selection.
            let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = response?.mapItems.filter { item in
                guard let center = destinationCoordinate,
                      item.name?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) == normalized else { return false }
                return CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)) < 60000
            } ?? []
            if matches.count == 1, let item = matches.first {
                resolvedCoordinates[id] = item.placemark.coordinate
                storeResolvedCoordinate(id: id, coordinate: item.placemark.coordinate)
            }
        }
    }
    private func storeResolvedCoordinate(id: String, coordinate: CLLocationCoordinate2D) {
        guard let index = trips.firstIndex(where: { $0.id == activeTripID }) else { return }
        var coordinates = trips[index].mapCoordinatesByPlaceID ?? [:]
        coordinates[id] = StoredPlaceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, source: "Apple Maps", matchedAt: .now)
        trips[index].mapCoordinatesByPlaceID = coordinates
        TripStorage.save(trips)
    }
    private func numericValue(_ record: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = record[key] as? NSNumber { return value.doubleValue }
            if let value = record[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }
    private var overviewText: String { recordValue(researchRoot["overview"], keys: ["summary", "description", "text"]) ?? (researchRoot["overview"] as? String) ?? "Η έρευνα εισήχθη. Άνοιξε τις ενότητες για να δεις τις διαθέσιμες πληροφορίες." }
    private var costSummary: String {
        guard let value = researchRoot["costs"] ?? researchRoot["cost_summary"] else { return "Δεν βρέθηκε δομημένη σύνοψη κόστους." }
        let fields: [(String, String)] = [
            ("Ανά άτομο", "per_person_estimate"), ("Για την ομάδα", "group_estimate"),
            ("Διαμονή", "lodging_estimate"), ("Μεταφορές και αξιοθέατα", "transport_and_attractions_subtotal"),
            ("Φαγητό", "food_estimate")
        ]
        guard let object = value as? [String: Any] else { return readableValue(value) }
        let rows = fields.compactMap { title, key -> String? in
            guard let amount = object[key] else { return nil }
            return "\(title): \(readableValue(amount))"
        }
        return rows.isEmpty ? readableValue(value) : rows.joined(separator: "\n")
    }

    private func records(_ keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = researchRoot[key] as? [[String: Any]] { return array }
            if let object = researchRoot[key] as? [String: Any], let nested = object["items"] as? [[String: Any]] { return nested }
        }
        return []
    }

    private func recordTitle(_ record: [String: Any]) -> String? { recordValue(record, keys: ["name", "title", "label", "date"]) }
    private func recordSummary(_ record: [String: Any]) -> String {
        recordValue(record, keys: ["description", "summary", "theme", "notes", "address", "area", "time", "details", "activity"]) ?? "Οι λεπτομέρειες υπάρχουν στο εισαγόμενο αποτέλεσμα έρευνας."
    }
    private func recordValue(_ record: Any?, keys: [String]) -> String? {
        guard let dictionary = record as? [String: Any] else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if let value = dictionary[key], !(value is NSNull), !(value is [String: Any]), !(value is [Any]) { return String(describing: value) }
        }
        return nil
    }
    private func dayTitle(_ day: [String: Any], index: Int) -> String {
        let date = recordValue(day, keys: ["date"])
        let weekday = recordValue(day, keys: ["day_name", "weekday"])
        let prefix = weekday ?? "Ημέρα \(index + 1)"
        return [prefix, date].compactMap { $0 }.joined(separator: " · ")
    }
    private func activityTitle(_ activity: [String: Any]) -> String {
        if let activityName = recordValue(activity, keys: ["activity", "name", "title"]) { return activityName }
        if let placeID = recordValue(activity, keys: ["place_id"]),
           let place = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == placeID }),
           let name = recordTitle(place) { return name }
        return "Στάση"
    }
    private func ratingLabel(_ place: [String: Any]) -> String {
        guard let rating = place["rating"] as? [String: Any],
              let value = numericValue(rating, keys: ["value"]), (0...5).contains(value),
              numericValue(rating, keys: ["scale", "out_of"]) ?? 5 == 5 else { return "—" }
        let platform = recordValue(rating, keys: ["platform"])
        let count = recordValue(rating, keys: ["review_count"]).map { "\($0) κριτικές" }
        return ["\(planNumber(value))/5", platform, count].compactMap { $0 }.joined(separator: " · ")
    }
    private func priceLabel(_ place: [String: Any]) -> String {
        if let price = place["price"] as? [String: Any] {
            let amount = costAmount(price)
            return amount == "—" ? "Τιμή μη επιβεβαιωμένη" : amount
        }
        return recordValue(place, keys: ["price", "cost", "price_range"]) ?? "Τιμή μη επιβεβαιωμένη"
    }
    private func warningText(_ item: Any) -> String {
        if let text = item as? String { return text }
        return recordValue(item, keys: ["message", "text", "warning", "title"]) ?? readableValue(item)
    }
    private func readableValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if value is NSNull { return "Δεν επιβεβαιώθηκε" }
        if let array = value as? [Any] { return array.map(readableValue).joined(separator: ", ") }
        if let object = value as? [String: Any] {
            let preferred = ["min", "max", "currency", "per_person_per_day_eur", "group_total_eur", "note", "basis", "includes", "excludes"]
            let ordered = preferred.compactMap { key -> String? in
                guard let item = object[key], !(item is NSNull) else { return nil }
                return "\(key): \(readableValue(item))"
            }
            return ordered.isEmpty ? "Διαθέσιμες λεπτομέρειες" : ordered.joined(separator: " · ")
        }
        return String(describing: value)
    }
}

private struct ResearchMapPoint: Identifiable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private struct PlaceImage: View {
    let title: String
    let imageURL: String?
    @State private var wikipediaImageURL: URL?
    @State private var explicitImageFailed = false

    private var explicitURL: URL? { imageURL.flatMap(URL.init(string:)) }
    private var displayedURL: URL? { explicitImageFailed ? wikipediaImageURL : (explicitURL ?? wikipediaImageURL) }
    private var wikipediaArticleURL: URL? {
        guard let slug = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(slug)")
    }

    var body: some View {
        ZStack {
            if let displayedURL {
                AsyncImage(url: displayedURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder.task {
                            if explicitURL != nil && !explicitImageFailed {
                                explicitImageFailed = true
                                await loadWikipediaImage()
                            }
                        }
                    } else {
                        placeholder.overlay { ProgressView().tint(AppPalette.brand) }
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: title) { if explicitURL == nil { await loadWikipediaImage() } }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "FFE0D2"), Color(hex: "F4BD78"), Color(hex: "9BBFB0")], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "sparkles")
                .font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.9))
        }
    }

    @MainActor private func loadWikipediaImage() async {
        guard wikipediaImageURL == nil,
              let slug = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)") else { return }
        var request = URLRequest(url: url)
        request.setValue("TrippyTravelPlanner/1.0 (iOS; image attribution: Wikimedia/Wikipedia)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(WikipediaPageSummary.self, from: data),
              let thumbnail = response.thumbnail?.source else { return }
        wikipediaImageURL = thumbnail
    }
}

private struct WikipediaPageSummary: Decodable {
    struct Thumbnail: Decodable { let source: URL? }
    let thumbnail: Thumbnail?
}

private struct TripCover: View {
    let vibe: String
    let destination: String

    private var assetName: String {
        let value = destination.lowercased()
        if value.contains("santorini") { return "TripSantorini" }
        if value.contains("tokyo") || value.contains("kyoto") || value.contains("ιαπων") { return "TripKyoto" }
        if value.contains("lisbon") || value.contains("lisboa") { return "TripLisbon" }
        if value.contains("bali") { return "TripBali" }
        if value.contains("rome") || value.contains("ρωμ") { return "TripRome" }
        if value.contains("new york") || value.contains("νέα υόρκη") { return "TripNewYork" }
        switch vibe {
        case "Θάλασσα", "Παραλία": return "TripSantorini"
        case "Φύση", "Πεζοπορία": return "TripBali"
        case "Κουλτούρα": return "TripKyoto"
        default: return "TripLisbon"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct BrandWordmark: View {
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    var size: CGFloat = 23

    var body: some View {
        Image(darkMode ? "BrandWordmarkDark" : "BrandWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: size * 6.3, height: size * 2.22)
            .accessibilityLabel("trippy")
    }
}

private enum AppPalette {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.07, green: 0.12, blue: 0.10, alpha: 1) : UIColor(red: 0.976, green: 0.957, blue: 0.929, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.20, blue: 0.17, alpha: 1) : UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1) : UIColor(red: 0.06, green: 0.16, blue: 0.12, alpha: 1)
    })
    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.73, green: 0.80, blue: 0.76, alpha: 1) : UIColor(red: 0.38, green: 0.40, blue: 0.39, alpha: 1)
    })
    static let inverseInk = Color.white
    static let brand = Color(hex: "102A22")
    static let accent = Color(hex: "FF685B")
    static let art = Color(hex: "FFBE55")
    static let avatarColors: [Color] = [Color(hex: "FF685B"), Color(hex: "FFBE55"), Color(hex: "FFCDBD"), Color(hex: "477461")]
}

private struct AdaptiveGlassControl: ViewModifier {
    enum ShapeKind {
        case circle
        case capsule
        case rounded
    }

    let shape: ShapeKind
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("trippy.native.glassTint") private var glassTint = "auto"

    private var selectedGlassTint: Color? {
        switch glassTint {
        case "forest": return Color(hex: "477461")
        case "coral": return AppPalette.accent
        case "amber": return AppPalette.art
        case "sage": return Color(hex: "AFC9B9")
        default: return nil
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            let glass = Glass.regular.tint(selectedGlassTint).interactive()
            switch shape {
            case .circle:
                content.glassEffect(glass, in: Circle())
            case .capsule:
                content.glassEffect(glass, in: Capsule())
            case .rounded:
                content.glassEffect(glass, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
        } else {
            switch shape {
            case .circle:
                content
                    .background(AppPalette.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(AppPalette.ink.opacity(0.06), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            case .capsule:
                content
                    .background(AppPalette.surface.opacity(0.94), in: Capsule())
                    .overlay(Capsule().stroke(AppPalette.ink.opacity(0.06), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            case .rounded:
                content
                    .background(AppPalette.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(AppPalette.ink.opacity(0.06), lineWidth: 0.7))
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 9, y: 4)
            }
        }
    }
}

private enum ResearchPrompt {
    static func make(layer: ResearchLayer, brief: TripBrief, existingResearch: String?, selectedRegion: String, pace: String) -> String {
        if layer == .foundation {
            return make(from: brief) + """


            ΣΤΑΘΕΡΟ ΠΛΑΙΣΙΟ ΓΙΑ ΚΑΘΕ ΕΡΕΥΝΗΤΙΚΟ ΒΗΜΑ
            Εφάρμοσε όλους τους περιορισμούς, προτιμήσεις και custom_instructions του brief σε κάθε αναζήτηση, κατάταξη, επιλογή πηγής, έλεγχο ημερομηνίας και πρόταση προγράμματος. Δεν είναι διακοσμητικά metadata. Αν υπάρχει σύγκρουση, κράτησε πρώτα ρητούς περιορισμούς/αποκλεισμούς, μετά τις δηλωμένες προτιμήσεις και τέλος τις δικές σου υποθέσεις. Κατέγραψε unresolved_conflicts και assumptions αντί να επινοείς απάντηση.
            Προτιμώμενη περιοχή: \(selectedRegion). Ρυθμός: \(pace).

            FOUNDATION / ΕΠΙΠΕΔΟ 1 — ΕΥΡΕΙΑ ΑΝΑΚΑΛΥΨΗ
            Δημιούργησε πρώτα ευρύ αλλά σχετικό foundation pool για τον/τους προορισμούς, τις περιοχές, τις κατηγορίες και το προφίλ ταξιδιού. Για κάθε υποψήφιο κατέγραψε γιατί ταιριάζει, ποια προτίμηση ικανοποιεί, βασική θέση/περιοχή, πηγή, και ποια facts πρέπει να επαληθευτούν αργότερα. Απόφυγε διπλότυπα και αδύναμες επιλογές. Μην επινοήσεις ότι είναι ανοιχτό/διαθέσιμο σε ημερομηνία που δεν έχει ελεγχθεί.
            Δημιούργησε εσωτερικό work matrix destination × area × selected category, κάλυψε τις περιοχές με ξεχωριστά discovery batches και έπειτα ένωσε/αφαίρεσε διπλότυπα. Κράτησε ποικιλία (κλασικά, highly-rated/popular, local, distinctive και value-for-quality επιλογές όπου ταιριάζουν στις προτιμήσεις), όχι πολλά αντίγραφα του ίδιου τύπου.
            Ακόμη και σε αυτό το επίπεδο, χρησιμοποίησε γνωστές ημερομηνίες ταξιδιού για να αποκλείσεις προφανείς ασυμβατότητες και να σημειώσεις τι απαιτεί ακριβή έλεγχο. Μην παρουσιάσεις το foundation ως τελικό επιβεβαιωμένο πρόγραμμα.
            Επέστρεψε πλήρες trippy-research-v1 JSON. Για κάθε claim βάλε πηγή/checked_at ή σαφές unknown/status. Το επόμενο επίπεδο θα κάνει ημερολογιακή επαλήθευση πάνω σε αυτά τα ids.
            """
        }

        let briefContext: [String: Any] = [
            "destination": brief.destination.isEmpty ? NSNull() : brief.destination as Any,
            "date_range": ["arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                           "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                           "dates_unknown": brief.dateIsUnknown,
                           "duration_days": brief.duration],
            "date_calendar_context": brief.dateContext,
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(), "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "custom_instructions": brief.notes.isEmpty ? NSNull() : brief.notes as Any,
            "preferred_region": selectedRegion, "pace": pace
        ]
        let contextData = (try? JSONSerialization.data(withJSONObject: briefContext, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"
        let foundationJSON = existingResearch ?? "Δεν έχει εισαχθεί foundation JSON ακόμη. Μην προσποιηθείς ότι υπάρχει· ζήτησε πρώτα το Επίπεδο 1."
        let globalRules = """
        ΚΑΘΟΛΙΚΟΙ ΚΑΝΟΝΕΣ — ΙΣΧΥΟΥΝ ΓΙΑ ΚΑΘΕ ΕΡΩΤΗΜΑ ΚΑΙ ΚΑΘΕ ΠΕΔΙΟ
        1. Εφάρμοσε σε κάθε αναζήτηση όλες τις παρακάτω πληροφορίες: destination, ακριβές date range, traveler count/group, vibes, selected interests, budget ως πλαίσιο, preferred area, pace και custom_instructions. Μην αγνοήσεις περιορισμό επειδή δεν επαναλαμβάνεται σε κάθε εγγραφή.
        2. Για κάθε μέρος ή event που προτείνεις/διατηρείς, έλεγξε καταλληλότητα στις ακριβείς τοπικές ημερομηνίες που σχετίζονται με το πρόγραμμα. Χρησιμοποίησε επίσημες πηγές για αργίες, ειδικό ωράριο, εβδομαδιαία κλεισίματα, προσωρινές διακοπές, απαιτούμενη κράτηση, εισιτήρια, event dates και μεταφορές. Μια γενική πληροφορία «συνήθως ανοικτό» δεν αποδεικνύει λειτουργία συγκεκριμένη ημερομηνία.
        3. Έλεγξε αργίες και τοπικές γιορτές ανά χώρα/περιοχή/δήμο και ανά ημερομηνία. Μην συμπεραίνεις ότι όλα κλείνουν ή ανοίγουν λόγω αργίας· επαλήθευσε κάθε σχετικό χώρο ξεχωριστά. Τα events απαιτούν ημερομηνία, venue και επίσημη/διοργανωτική πηγή για status confirmed. Διαχώρισε confirmed, candidate, not_found και not_checked.
        4. Πρόσθεσε calendar_checks ανά ημερομηνία και date_checks ανά σχετικό place/event, με local_date, status, τι ακριβώς ελέγχθηκε, source_ids και checked_at. Μην αφήνεις έλλειψη δεδομένων να μετατραπεί σε θετική υπόθεση.
        5. Για κρατήσεις, tasks και urgency αξιολόγησε κάθε destination × ημερομηνία/ημερομηνίες × συγκεκριμένο αντικείμενο. Συμπερίλαβε ακριβή deadline μόνο αν επιβεβαιώνεται. Urgency 9–10 μόνο με επίσημη προθεσμία, πραγματική date-specific απαίτηση ή τεκμηριωμένη περιορισμένη διαθεσιμότητα· διαφορετικά χαμηλότερο score και σαφής χαρακτηρισμός ως planning recommendation.
        6. Διατήρησε distinctions: confirmed price vs estimate, official vs secondary source, date-specific vs general fact, user constraint vs model inference. Ποτέ μη μαντεύεις. Αν δεν βρίσκεις, γράψε not_found/not_checked και τι αναζήτηση έκανες.
        7. Πριν από output, έλεγξε consistency: τοπική ζώνη ώρας, inclusive ημέρες vs διανυκτερεύσεις, ημέρα εβδομάδας, όλες οι ημερομηνίες του range, source/id references, constraints και αποκλεισμούς.
        8. Οργάνωσε εσωτερικά την εργασία σε batches destination × area × selected category. Κάνε πρώτα ευρείες αναζητήσεις ανά περιοχή/κατηγορία, μετά στοχευμένο verification ανά candidate και ημερομηνία. Παράλληλοποίησε μόνο ανεξάρτητα batches, επαναχρησιμοποίησε την ίδια επίσημη πηγή για πολλές ημερομηνίες όταν καλύπτει όλες, κάνε deduplication ανά stable identity και κράτα coverage/gaps ανά batch. Μην επαναλαμβάνεις το ίδιο query για κάθε μέρα ή κάθε πεδίο.
        9. Μην κάνεις crawl όλο τον ιστό. Διάλεξε σχετικές περιοχές και ποικιλία υποψηφίων ανά ενεργή κατηγορία με εύρος προσαρμοσμένο στη διάρκεια και στα διαθέσιμα στοιχεία. Δώσε προτεραιότητα σε direct official/provider sources και χρησιμοποίησε γενική αναζήτηση για discovery ή gap-filling.
        """

        let layerInstructions: String
        switch layer {
        case .foundation:
            layerInstructions = ""
        case .dateVerification:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 2 — ΕΠΑΛΗΘΕΥΣΗ FOUNDATION ΑΝΑ ΗΜΕΡΟΜΗΝΙΑ
            Πάρε το παρακάτω foundation ως σύνολο υπαρχόντων candidates και όχι ως αληθές εκ προοιμίου. Μην ξανακάνεις γενική αναζήτηση από την αρχή. Για κάθε place/event του pool, επαλήθευσε τα facts που αλλάζουν με ημερομηνία και όσα κρίσιμα πεδία λείπουν (official URL, διεύθυνση, coords, ticket/price, image/source όπου είναι ανακτήσιμα). Έλεγξε κάθε σχετική ημερομηνία του range: αργίες, τοπικά events, ειδικά ωράρια, κλεισίματα, απαιτήσεις προκράτησης και μεταφορές. Σύνδεσε κάθε αποτέλεσμα με υπάρχον stable id. Πρόσθεσε νέα επιλογή μόνο αν το foundation έχει ουσιαστικό κενό.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2: set για ενημερώσεις overview/map_overview αν χρειάζεται, upsert για places/events/sources/booking_tasks, replace για calendar_checks, date_checks και warnings. Μην αλλάξεις user-owned δεδομένα και μη διαγράψεις records. Κάθε ενημερωμένο fact να έχει source_ids και checked_at. Για κάθε booking task αξιολόγησε destination + related item + due date/ημερομηνία ταξιδιού.
            """
        case .itinerary:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 3 — ΗΜΕΡΗΣΙΑ ΣΥΝΘΕΣΗ ΜΕ ΕΛΕΓΜΕΝΑ ΔΕΔΟΜΕΝΑ
            Σύνθεσε πρόγραμμα μόνο αφού λάβεις υπόψη date_checks/calendar_checks του foundation. Σε κάθε μέρα, έλεγξε ότι κάθε stop ταιριάζει στην ομάδα, τα vibes, τα must/avoid, διατροφή, budget και ρυθμό. Επιβεβαίωσε ότι ο χώρος λειτουργεί τη συγκεκριμένη ημέρα και ώρα· μην τοποθετείς κλειστό/μη επιβεβαιωμένο χώρο σαν βέβαιο. Ομαδοποίησε γεωγραφικά stops, υπολόγισε ρεαλιστικούς χρόνους μετακίνησης, κενά/γεύματα και ευέλικτη εναλλακτική. Δείξε αργίες/events στο σωστό day και προσαρμόζεις πλάνο μόνο με πηγές. Κράτησε σταθερά ids και σύνδεσε stops με map_views.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2: replace itinerary, map_views και calendar_checks μόνο αν τα επανέλεγξες· set overview/map_overview/costs· upsert booking_tasks και sources. Μη ξαναγράψεις places ή άσχετα στοιχεία. Δήλωσε κενά/αντιφάσεις στα warnings.
            """
        case .targetedRefresh:
            layerInstructions = """
            ΕΠΙΠΕΔΟ 4 — ΣΤΟΧΕΥΜΕΝΗ ΕΠΑΝΑΝΑΖΗΤΗΣΗ
            Διάβασε τις custom_instructions ως αίτημα αλλαγής και εντόπισε το μικρότερο σωστό scope. Εφάρμοσε και πάλι όλους τους global περιορισμούς και ακριβείς ημερομηνίες. Έλεγξε ξανά μόνο τα facts που επηρεάζονται, μαζί με εξαρτήσεις τους (π.χ. αλλαγή ημερομηνίας → weekday/αργία/ωράριο/event/εισιτήριο/task/map/day cost). Διατήρησε pinned/user-edited πρόγραμμα και IDs. Μην επαναφέρεις disliked επιλογές. Επισήμανε conflicts και δώσε reason/source.
            ΕΠΙΣΤΡΕΨΕ trippy-research-patch-v2 με μόνο τα αλλαγμένα πεδία: set, replace και upsert. Μην αντικαταστήσεις ολόκληρο το foundation. Αν δεν επαληθεύεται αλλαγή, διατήρησε παλιά τιμή και πρόσθεσε warning με status not_found/not_checked.
            """
        }

        let researchJSON = foundationJSON
        return """
        Είσαι ερευνητής ταξιδιών και επιμελητής τεκμηριωμένων δεδομένων για το Trippy. Αυτό είναι σταδιακή έρευνα: ενημέρωσε το foundation χωρίς να χάνεις προέλευση ή αβεβαιότητα.

        TRIP BRIEF — ΟΙ ΠΡΟΤΙΜΗΣΕΙΣ ΚΑΙ ΠΕΡΙΟΡΙΣΜΟΙ ΕΙΝΑΙ ΔΕΣΜΕΥΤΙΚΟΙ
        \(contextJSON)

        \(globalRules)

        \(layerInstructions)

        ΥΠΑΡΧΟΝ FOUNDATION / SOURCE OF TRUTH ΓΙΑ ΤΑ ΗΔΗ ΓΝΩΣΤΑ (JSON)
        \(researchJSON)

        ΣΥΜΒΟΛΑΙΟ PATCH
        Για patch-v2 επέστρεψε ακριβώς:
        {"schema_version":"trippy-research-patch-v2","set":{},"replace":{},"upsert":{"places":[],"events":[],"sources":[],"booking_tasks":[]},"warnings":[]}
        `set` περιέχει top-level αντικείμενα για merge/replace (π.χ. costs, map_overview). `replace` περιέχει ολόκληρες λίστες/αντικείμενα που υπολογίστηκαν ξανά (π.χ. calendar_checks, date_checks, itinerary, map_views). `upsert` κάνει merge με βάση stable id και κρατάει άγνωστα υπάρχοντα fields. Χρησιμοποίησε μόνο keys του ζητούμενου επιπέδου. Μην στείλεις άδειες λίστες για να σβήσεις δεδομένα εκτός αν το επίπεδο ζητά ρητά replace.
        Κάθε date_check: {"id":"place-id|YYYY-MM-DD","entity_id":"stable-id","entity_type":"place|event|transport","local_date":"YYYY-MM-DD","status":"confirmed|closed|candidate|not_found|not_checked","opening_status":null,"holiday_or_event":null,"ticket_status":null,"reservation_status":null,"details":"","source_ids":[],"checked_at":"YYYY-MM-DD"}.
        Κάθε booking_task: {"id":"stable-id","destination":"","local_date":null,"related_place_id":null,"event_id":null,"type":"booking|ticket|transport|document|check|reminder","urgency_score":1,"urgency_reason":"","urgency_basis":"official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional","urgency_confidence":"high|medium|low","due_date":null,"task":"","url":null,"source_ids":[],"status":""}.
        Επέστρεψε μόνο έγκυρο JSON, χωρίς markdown ή πρόλογο. Έλεγξε ότι οι ημερομηνίες, τα stable ids, οι πηγές και οι εφαρμοσμένοι περιορισμοί είναι συνεπή. Αν δεν υπάρχει Foundation JSON για επίπεδα 2–4, σταμάτησε και ζήτησε πρώτα το επίπεδο 1.
        """
    }

    static func make(from brief: TripBrief) -> String {
        let context: [String: Any] = [
            "destination": brief.destination.isEmpty ? NSNull() : brief.destination as Any,
            "dates": ["arrival": brief.startDate.isEmpty ? NSNull() : brief.startDate as Any,
                      "departure": brief.endDate.isEmpty ? NSNull() : brief.endDate as Any,
                      "unknown": brief.dateIsUnknown,
                      "duration_days": brief.duration],
            "date_calendar_context": brief.dateContext,
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "dietary_needs": brief.dietaryNeeds.sorted(),
            "mobility_requirements": brief.mobility.sorted(),
            "stay_style": brief.stayStyle,
            "custom_instructions": brief.notes.isEmpty ? NSNull() : brief.notes as Any
        ]
        let data = (try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        Είσαι ερευνητής ταξιδιών που τεκμηριώνει κάθε χρήσιμη πληροφορία. Κάνε τρέχουσα έρευνα στον ιστό για το ταξίδι παρακάτω. Το Trippy εισάγει το αποτέλεσμα αυτόματα, οπότε προτεραιότητα έχουν η ακρίβεια, η πληρότητα και η αυστηρή συμβατότητα δεδομένων.

        ΤΑΞΙΔΙΩΤΙΚΟ BRIEF
        \(json)

        ΚΑΝΟΝΕΣ ΕΡΕΥΝΑΣ ΚΑΙ ΠΟΙΟΤΗΤΑΣ
        - Προτίμησε επίσημες πηγές χώρων, συγκοινωνιών, διοργανωτών και δήμων για ωράρια, κλεισίματα, εισιτήρια και δρομολόγια.
        - Κατάταξε τα μέρη πρώτα με βάση ποιότητα, φήμη και συνάφεια με το ταξίδι. Χρησιμοποίησε το budget ως πλαίσιο· μην προτείνεις χαμηλής ποιότητας επιλογές μόνο επειδή είναι φθηνές.
        - Αναζήτησε ευρύ pool χωριστά από το προτεινόμενο πρόγραμμα. Προσάρμοσε τον αριθμό επιλογών στη διάρκεια, στις επιλεγμένες κατηγορίες, στην ποικιλία του προορισμού και στην ποιότητα των διαθέσιμων τεκμηρίων. Μην χρησιμοποιείς σταθερό στόχο ανά κατηγορία, μην συμπληρώνεις με αδύναμες προτάσεις και μην ερευνάς κατηγορίες που ο χρήστης δεν επέλεξε.
        - Σεβάσου τις custom_instructions και τις επιλεγμένες προτιμήσεις. Ερμήνευσε budget, ποιότητα/φήμη, δημοτικότητα, τοπικότητα, πρωτοτυπία και εγγύτητα ως ξεχωριστές διαστάσεις. Μην υποθέτεις ότι το φθηνότερο είναι καλύτερο ή ότι ένα υψηλό rating αποδεικνύει καταλληλότητα.
        - Για κάθε μέρος αναζήτησε απευθείας λειτουργικό URL εικόνας που αντιστοιχεί στο συγκεκριμένο μέρος (κατά προτίμηση επίσημη σελίδα/πηγή ή Wikimedia/Wikipedia με σχετική εικόνα). Αν δεν επιβεβαιώνεται άμεσο image URL, βάλε null· μην βάζεις URL αναζήτησης ή γενική εικόνα πόλης. Πρόσθεσε image_source_url και image_attribution αν είναι διαθέσιμα.
        - Για κάθε μέρος δώσε σταθερό μοναδικό id, category, name, description, address, coordinates {latitude, longitude, status}, price {min, max, currency, basis}, rating {value, platform, review_count}, tags, image_url, official_url, source_ids, checked_at και status_on_travel_dates. Βάλε null στα επιμέρους άγνωστα πεδία και εξήγησε την αβεβαιότητα στο status.
        - Η περιγραφή κάθε μέρους πρέπει να είναι χρήσιμη για απόφαση, όχι διαφημιστική: εξήγησε συγκεκριμένα γιατί ταιριάζει ή δεν ταιριάζει στο group, ποιότητα/δημοτικότητα, εμπειρία και trade-offs έναντι κοντινών επιλογών. Πρόσθεσε why_recommended, best_for, cuisine, dietary_options, popularity, average_visit_minutes, best_time και reservation_required ως δομημένα πεδία όπου τεκμηριώνονται. Συμπερίλαβε πλήθος/πλατφόρμα αξιολογήσεων και σύγκρινε αξία με ποιότητα, όχι μόνο τιμή.
        - Για πληροφορίες που είναι ανακτήσιμες από επίσημες σελίδες ή δημόσιες καταχωρίσεις (εικόνες, διεύθυνση, συντεταγμένες, ratings/review counts), κάνε στοχευμένη αναζήτηση ανά μέρος. Μην αφήνεις πεδία κενά πριν δοκιμάσεις σχετική αναζήτηση. Μην επινοήσεις τιμή, βαθμολογία, πλήθος κριτικών, συντεταγμένες, ωράριο, URL εικόνας, κράτηση ή κατάσταση λειτουργίας. Μη χρησιμοποιείς null για να κρύψεις ότι δεν έγινε έλεγχος: γράψε καθαρά τι δεν επιβεβαιώθηκε.
        - Ξεχώρισε ημερολογιακές ημέρες από διανυκτερεύσεις. Με συγκεκριμένες ημερομηνίες, υπολόγισε duration_days ως πλήθος ημερομηνιών μαζί με άφιξη και αναχώρηση και nights ως διαφορά ημερομηνιών· μην αντιγράψεις ασύμβατες τιμές από το brief. Το itinerary.days να έχει ακριβώς μία εγγραφή ανά ημερομηνία από άφιξη έως αναχώρηση, με ημερομηνία ISO, αριθμό ημέρας, theme, stops, alternative, flex_time και estimated_day_cost_per_person_eur. Στις ημέρες άφιξης/αναχώρησης λάβε υπόψη άγνωστες ώρες πτήσης και μην υπερφορτώνεις το πρόγραμμα.
        - Κάθε stop να έχει time, place_id (ή null αν δεν είναι συγκεκριμένο μέρος), activity, travel_time_minutes, estimated_cost_per_person_eur και source_ids. Μην αλλάζεις τα ids μεταξύ places, highlights, stops, map_views και booking_tasks.
        - Κάθε itinerary day να έχει map_view_id και κάθε map_view να αντιστοιχεί σε συγκεκριμένη ημέρα ή θεματική διαδρομή με place_ids στην ίδια σειρά με το πρόγραμμα. Το app δημιουργεί ημερήσιο χάρτη από τις συντεταγμένες των stops.
        - Κράτησε ώρα, κόστος ανά άτομο, place_id και source_ids σε ξεχωριστά πεδία ανά stop, όχι μόνο σε περιγραφικό κείμενο. Βάλε σαφή βάση κόστους ή null όταν δεν τεκμηριώνεται.
        - Δημιούργησε booking_tasks μόνο για ενέργειες που είναι πραγματικά χρήσιμες ή αναγκαίες για αυτόν τον προορισμό και τις συγκεκριμένες ημερομηνίες. Για κάθε task δώσε σταθερό id, destination, related place_id ή event_id, τύπο (booking|ticket|transport|document|check|reminder), due_date/deadline αν τεκμηριώνεται, official URL, status, urgency_score ακέραιο 1–10, urgency_reason, urgency_basis (official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional), urgency_confidence (high|medium|low) και source_ids. Το 10 σημαίνει τεκμηριωμένη άμεση ανάγκη/κίνδυνο να χαθεί κρίσιμη διαθεσιμότητα· μην αποδίδεις υψηλό score επειδή απλώς «καλό είναι να κλείσετε νωρίς». Αν δεν βρέθηκε τεκμήριο για scarcity/deadline, βάλε χαμηλότερη βαθμολογία, εξήγησε ότι είναι σύσταση και μην επινοείς προθεσμία. Ξεχώρισε τις πραγματικά κρίσιμες ενέργειες από προαιρετικές υπενθυμίσεις.
        - Παράγαγε map_overview με title, subtitle και μία σύντομη trip_sentence για το πάνω overlay της σελίδας χάρτη. Να είναι συγκεκριμένα στον προορισμό και στο ταξίδι, αλλά να μην περιέχουν μη τεκμηριωμένα πραγματολογικά claims. Το app θα χρησιμοποιήσει αυτά τα πεδία δυναμικά, όχι κείμενο προορισμού hardcoded.
        - Για το date range επέστρεψε calendar_checks ανά σχετική ημερομηνία για αργίες/τοπικές γιορτές/ωράρια και events ως χωριστές εγγραφές με κατηγορία (concert, festival, public_holiday, local_celebration, exhibition, performing_arts, sport, seasonal_market, nightlife, other), ακριβείς τοπικές ημερομηνίες/ώρες όταν είναι διαθέσιμες, venue/place_id, status, source_ids και checked_at. Δημόσια αργία δεν σημαίνει αυτομάτως ότι ένας χώρος είναι κλειστός. Ξεχώρισε confirmed από candidate/not_found.
        - Οι κάρτες places να έχουν τεκμηριωμένα tags για κουζίνα/διατροφή, τύπο γεύματος ή δραστηριότητας, δημοτικότητα και καταλληλότητα για την ομάδα. Μην κρύβεις κρίσιμα στοιχεία μόνο στο description.
        - Σύνδεσε places ↔ itinerary stops ↔ ημερήσιους χάρτες ↔ ticket_options ↔ booking_tasks ↔ sources με σταθερά ids. Κάθε ωράριο/τιμή να έχει source_ids και checked_at.
        - Έλεγξε αργίες, εβδομαδιαία κλεισίματα και ειδικά ωράρια για κάθε ημερομηνία ταξιδιού από επίσημη πηγή. Δήλωσε σαφώς αν το κλείσιμο/ωράριο επιβεβαιώθηκε, δεν επιβεβαιώθηκε ή δεν βρέθηκε.
        - Οι ημερομηνίες και οι προτιμήσεις ισχύουν σε ΟΛΟ το research: για κάθε υποψήφιο place/event/transport, εφάρμοσε τους περιορισμούς του brief και έλεγξε ό,τι εξαρτάται από τις συγκεκριμένες ημερομηνίες. Παράγαγε date_checks με ένα record ανά σχετικό entity και local_date, ώστε αργίες, weekday, ωράριο, closure, event, εισιτήριο και δυνατότητα κράτησης να μην κρύβονται σε γενικές περιγραφές. Μην ισχυριστείς date-specific availability χωρίς πηγή.
        - Συμπερίλαβε κόστη ανά άτομο και ομάδα, νόμισμα, βάση υπολογισμού, τι περιλαμβάνουν/εξαιρούν και σαφή διάκριση επιβεβαιωμένων τιμών από εκτιμήσεις.
        - Κάθε source_ids πρέπει να υπάρχει στο sources και κάθε place_id να υπάρχει στο places. Κάθε source να έχει id, url, publisher, type, checked_at και supports. Προτίμησε άμεσες σελίδες πηγών, όχι αρχικές σελίδες ή γενικά αποτελέσματα αναζήτησης.

        ΑΠΑΙΤΟΥΜΕΝΟ ΣΥΜΒΟΛΑΙΟ ΕΞΟΔΟΥ
        Επέστρεψε ένα μόνο JSON object με όλα τα παρακάτω top-level keys και ακριβώς αυτό το schema_version:
        {"schema_version":"trippy-research-v1","trip_context":{},"overview":{"summary":"","seasonal_notes":[],"recommended_highlights":[{"place_id":"","reason":"","source_ids":[]}]},"map_overview":{"title":"","subtitle":"","trip_sentence":""},"calendar_checks":[{"id":"","date":"YYYY-MM-DD","day":"","status":"","details":"","source_ids":[]}],"date_checks":[{"id":"place-id|YYYY-MM-DD","entity_id":"","entity_type":"place|event|transport","local_date":"YYYY-MM-DD","status":"confirmed|closed|candidate|not_found|not_checked","opening_status":null,"holiday_or_event":null,"ticket_status":null,"reservation_status":null,"details":"","source_ids":[],"checked_at":"YYYY-MM-DD"}],"places":[{"id":"","category":"","name":"","description":"","why_recommended":"","best_for":[],"cuisine":null,"dietary_options":[],"popularity":null,"average_visit_minutes":null,"best_time":null,"reservation_required":null,"address":null,"coordinates":{"latitude":null,"longitude":null,"status":""},"price":{"min":null,"max":null,"currency":null,"basis":""},"rating":{"value":null,"platform":null,"review_count":null},"tags":[],"image_url":null,"image_source_url":null,"image_attribution":null,"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","status_on_travel_dates":""}],"events":[{"id":"","name":"","category":"","date_start":null,"date_end":null,"venue":null,"description":"","price":{"min":null,"max":null,"currency":null},"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","confidence":""}],"itinerary":{"days":[{"date":"YYYY-MM-DD","day":1,"theme":"","map_view_id":null,"stops":[{"time":null,"place_id":null,"activity":"","travel_time_minutes":null,"estimated_cost_per_person_eur":null,"source_ids":[]}],"alternative":"","flex_time":"","estimated_day_cost_per_person_eur":{"min":null,"max":null}}]},"map_views":[{"id":"","title":"","date":null,"place_ids":[],"map_url":null,"note":""}],"transport_options":[{"id":"","name":"","best_for":"","price":{"min":null,"max":null,"currency":null,"basis":""},"group_cost_estimate_eur":{"min":null,"max":null},"limitations":[],"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD"}],"ticket_options":[{"id":"","name":"","price_per_person_eur":null,"group_price_eur":null,"booking_url":null,"notes":"","source_ids":[]}],"costs":{"currency":"EUR","methodology":"","per_person_estimate":{"min":null,"max":null,"includes":[],"excludes":[]},"group_estimate":{"min":null,"max":null,"currency":"EUR","includes":[],"excludes":[]},"lodging_estimate":{"per_room_per_night_eur":null,"group_total_eur":null,"note":""},"transport_and_attractions_subtotal":{"per_person_eur":null,"group_eur":null,"basis":""},"food_estimate":{"per_person_per_day_eur":null,"group_total_eur":null,"basis":""}},"booking_tasks":[{"id":"","destination":"","local_date":null,"type":"booking|ticket|transport|document|check|reminder","urgency_score":1,"urgency_reason":"","urgency_basis":"official_deadline|verified_limited_availability|date_specific_requirement|planning_recommendation|optional","urgency_confidence":"high|medium|low","due_date":null,"task":"","place_id":null,"event_id":null,"url":null,"source_ids":[],"status":""}],"sources":[{"id":"S01","url":"","publisher":"","type":"","checked_at":"YYYY-MM-DD","supports":[]}],"warnings":[{"id":"W01","severity":"","message":""}],"assumptions":[]}

        ΜΟΡΦΟΠΟΙΗΣΗ ΚΑΙ ΤΕΛΙΚΟΣ ΕΛΕΓΧΟΣ
        - Μην χρησιμοποιήσεις markdown fences, σχόλια, trailing commas, NaN ή Infinity. Χρησιμοποίησε μόνο διπλά εισαγωγικά σε keys/strings και null για άγνωστες τιμές.
        - Μην παραλείψεις top-level keys. Για λίστα χωρίς αποτελέσματα επέστρεψε []. Για άγνωστα scalar fields επέστρεψε null.
        - Πριν την τελική απάντηση, έλεγξε ότι το JSON γίνεται parse, τα ids/πηγές συνδέονται, οι ημερομηνίες και τα πλήθη ημερών συμφωνούν και το αποτέλεσμα δεν είναι κομμένο.
        - Η απάντηση πρέπει να είναι όλο το JSON από το πρώτο { έως το τελευταίο }, χωρίς πρόλογο ή επίλογο. Αν η διεπαφή υποστηρίζει δημιουργία αρχείου, επισύναψε και αρχείο `trippy-research.json` με ακριβώς το ίδιο JSON. Μην αντικαταστήσεις το JSON κείμενο με σύνοψη ή μόνο με αρχείο.
        """
    }

    static func makeAlternatives(brief: TripBrief, currentPlace: [String: Any]?, activity: String?, placePool: [[String: Any]], reactions: [String: String], selectedRegion: String) -> String {
        func value(_ record: [String: Any], _ keys: [String]) -> String? {
            for key in keys {
                if let text = record[key] as? String, !text.isEmpty { return text }
                if let item = record[key], !(item is NSNull), !(item is [String: Any]), !(item is [Any]) { return String(describing: item) }
            }
            return nil
        }
        func jsonString(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        }
        let current: [String: Any] = [
            "activity": activity as Any? ?? NSNull(),
            "place": currentPlace.map { place in
                ["id": value(place, ["id", "place_id"]) as Any? ?? NSNull(),
                 "name": value(place, ["name", "title", "label"]) as Any? ?? NSNull(),
                 "category": value(place, ["category", "type", "kind"]) as Any? ?? NSNull(),
                 "description": value(place, ["description", "summary", "notes"]) as Any? ?? "",
                 "address": value(place, ["address", "area", "neighborhood"]) as Any? ?? NSNull(),
                 "tags": place["tags"] as? [String] ?? [],
                 "rating": place["rating"] ?? NSNull(),
                 "coordinates": place["coordinates"] ?? NSNull()] as [String: Any]
            } ?? NSNull(),
            "destination": brief.destination,
            "date_range": [brief.startDate, brief.endDate],
            "group": brief.group,
            "budget": brief.budget as Any? ?? NSNull(),
            "budget_basis": brief.budgetBasis,
            "budget_includes": brief.budgetIncludes.sorted(),
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "preference_tags": brief.preferenceTags.sorted(),
            "catalog_filters": TripPreferenceCatalog.filters(interests: brief.interests, tags: brief.preferenceTags),
            "preferred_region": selectedRegion
        ]
        let pool = placePool.map { place -> [String: Any] in
            let id = value(place, ["id", "place_id"])
            return ["id": id as Any? ?? NSNull(),
             "name": value(place, ["name", "title", "label"]) as Any? ?? NSNull(),
             "category": value(place, ["category", "type", "kind"]) as Any? ?? NSNull(),
             "address": value(place, ["address", "area", "neighborhood"]) as Any? ?? NSNull(),
             "tags": place["tags"] as? [String] ?? [],
             "rating": place["rating"] ?? NSNull(),
             "user_reaction": id.flatMap { reactions["place|\($0)"] } as Any? ?? NSNull()]
        }
        return """
        Κάνε στοχευμένη, ενημερωμένη έρευνα για κοντινές εναλλακτικές στο ταξίδι. Μην ξαναγράψεις ή αντικαταστήσεις το πρόγραμμα. Το Trippy θα συγχωνεύσει το patch στο υπάρχον pool και θα κρατήσει το πρόγραμμα και τις αλλαγές του χρήστη.

        ΠΛΑΙΣΙΟ ΚΑΙ ΣΤΑΣΗ ΠΡΟΣ ΑΝΤΙΚΑΤΑΣΤΑΣΗ
        \(jsonString(current))

        ΗΔΗ ΥΠΑΡΧΟΝ POOL — ΜΗΝ ΕΠΑΝΑΛΑΒΕΙΣ ΑΥΤΑ ΤΑ IDS Ή ΤΑ ΙΔΙΑ ΜΕΡΗ
        \(jsonString(pool))

        ΒΡΕΣ 8 ΝΕΕΣ ΕΠΙΛΟΓΕΣ ΤΗΣ ΙΔΙΑΣ ΚΑΤΗΓΟΡΙΑΣ, ΠΡΟΤΙΜΗΣΕ ΣΕΙΡΑ:
        1. Απόσταση έως περίπου 2 km από την τρέχουσα στάση, αν υπάρχουν επαληθεύσιμες τοποθεσίες.
        2. Ίδια γειτονιά/περιοχή, ίδιο είδος εμπειρίας και συμβατότητα με το group, vibe, dietary needs και budget.
        3. Αν δεν υπάρχουν αρκετές κοντινές επιλογές, διεύρυνε την ακτίνα με σαφή αναφορά στην απόσταση.
        Κατάταξε με βάση φήμη, ποιότητα, rating και πλήθος κριτικών· το budget είναι φίλτρο/πλαίσιο, όχι υποκατάστατο ποιότητας. Σεβάσου τις προηγούμενες αντιδράσεις στο pool: μην επαναφέρεις επιλογή με user_reaction "dislike".

        ΕΠΑΛΗΘΕΥΣΗ
        Για κάθε καινούργιο μέρος έλεγξε επίσημη σελίδα, διεύθυνση, συντεταγμένες, εικόνα και τιμή/ratings όπου γίνεται. Κατέγραψε άμεσο URL εικόνας μόνο αν οδηγεί σε εικόνα αυτού του μέρους, μαζί με image_source_url και image_attribution. Μη μαντεύεις: βάλε null και εξήγησε το κενό. Σύνδεσε κάθε ισχυρισμό με source id και βάλε checked_at.

        ΕΠΕΣΤΡΕΨΕ ΜΟΝΟ ΕΝΑ ΕΓΚΥΡΟ JSON OBJECT PATCH, ΧΩΡΙΣ MARKDOWN:
        {"schema_version":"trippy-research-patch-v1","add_places":[{"id":"unique_stable_id","category":"","name":"","description":"","address":null,"coordinates":{"latitude":null,"longitude":null,"status":""},"price":{"min":null,"max":null,"currency":null,"basis":""},"rating":{"value":null,"platform":null,"review_count":null},"tags":[],"image_url":null,"image_source_url":null,"image_attribution":null,"official_url":null,"source_ids":[],"checked_at":"YYYY-MM-DD","status_on_travel_dates":""}],"add_sources":[{"id":"S-new-01","url":"","publisher":"","type":"","checked_at":"YYYY-MM-DD","supports":[]}],"warnings":[]}
        Το add_places να έχει μόνο νέα μέρη. Κάθε source_ids πρέπει να υπάρχει σε add_sources ή στις ήδη υπάρχουσες πηγές. Έλεγξε ότι το JSON γίνεται parse και μην προσθέτεις πρόλογο/επίλογο.
        """
    }
}

#Preview {
    TripFlowView()
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Map-first navigation
private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum MapPlaceCategory: String, CaseIterable, Codable, Identifiable {
    case sights = "Αξιοθέατα", restaurants = "Φαγητό", coffee = "Καφές"
    case brunch = "Brunch", bars = "Μπαρ", groceries = "Προμήθειες", metro = "Μετρό", other = "Άλλα"
    case streetFood = "Street food", burgers = "Burger", seafood = "Θαλασσινά", vegan = "Vegan"
    case shopping = "Shopping", touristShops = "Τοπικά μαγαζιά", parks = "Πάρκα", clubs = "Clubs"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sights: return "building.columns"
        case .restaurants, .streetFood, .burgers, .seafood, .vegan: return "fork.knife"
        case .coffee: return "cup.and.saucer"
        case .brunch: return "sun.horizon"
        case .bars: return "wineglass"
        case .shopping: return "bag"
        case .touristShops: return "storefront"
        case .parks: return "leaf"
        case .clubs: return "music.note"
        case .groceries: return "basket"
        case .metro: return "tram"
        case .other: return "mappin"
        }
    }
    var tint: Color {
        switch self {
        case .sights: return Color(hex: "E88752")
        case .restaurants, .streetFood, .burgers, .seafood, .vegan: return Color(hex: "E56C52")
        case .coffee, .brunch: return Color(hex: "A96D45")
        case .bars, .clubs: return Color(hex: "B16E62")
        case .groceries: return Color(hex: "7E9A69")
        case .metro: return Color(hex: "718A83")
        case .shopping, .touristShops: return Color(hex: "D4A34F")
        case .parks: return Color(hex: "6F9B70")
        case .other: return AppPalette.brand
        }
    }
    static func classify(_ text: String) -> Self {
        let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if ["street food", "streetfood"].contains(where: text.contains) { return .streetFood }
        if ["burger"].contains(where: text.contains) { return .burgers }
        if ["seafood", "fish", "θαλασσι"].contains(where: text.contains) { return .seafood }
        if ["vegan", "plant based"].contains(where: text.contains) { return .vegan }
        if ["brunch", "breakfast", "πρωιν"].contains(where: text.contains) { return .brunch }
        if ["cafe", "coffee", "καφε"].contains(where: text.contains) { return .coffee }
        if ["club", "nightclub", "night life"].contains(where: text.contains) { return .clubs }
        if ["park", "garden", "πάρκ", "κηπ"].contains(where: text.contains) { return .parks }
        if ["souvenir", "tourist shop", "gift shop"].contains(where: text.contains) { return .touristShops }
        if ["shopping", "mall", "clothing", "retail"].contains(where: text.contains) { return .shopping }
        if ["bar", "pub", "nightlife", "μπαρ"].contains(where: text.contains) { return .bars }
        if ["grocery", "supermarket", "supplies", "προμηθ"].contains(where: text.contains) { return .groceries }
        if ["metro", "subway", "transit", "μετρο"].contains(where: text.contains) { return .metro }
        if ["restaurant", "food", "dining", "εστια", "φαγη"].contains(where: text.contains) { return .restaurants }
        if ["sight", "museum", "landmark", "attraction", "αξιοθ", "μουσει"].contains(where: text.contains) { return .sights }
        return .other
    }
}

private enum SearchPlaceKind: String, Codable { case area, attraction, place }

private enum MapSearchFilter: String, CaseIterable, Identifiable {
    case all, places, cities, food, cafes, sights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Όλα"
        case .places: "Μέρη"
        case .cities: "Πόλεις & περιοχές"
        case .food: "Φαγητό"
        case .cafes: "Καφέ"
        case .sights: "Αξιοθέατα"
        }
    }
    func includes(_ place: PersonalPlace) -> Bool {
        switch self {
        case .all: true
        case .places: place.searchKind != .area
        case .cities: place.searchKind == .area
        case .food: [.restaurants, .streetFood, .burgers, .seafood, .vegan, .brunch].contains(place.category)
        case .cafes: place.category == .coffee
        case .sights: place.category == .sights || place.searchKind == .attraction
        }
    }
}

private struct GooglePlacePhoto: Decodable, Identifiable {
    let name: String
    let authorAttributions: [GooglePlaceAttribution]?
    let googleMapsURL: String?
    var id: String { name }
}
private struct GooglePlaceAttribution: Decodable, Identifiable {
    let displayName: String
    let uri: String?
    let photoUri: String?
    var id: String { uri ?? displayName }
}
private struct GooglePlaceReview: Decodable, Identifiable {
    let rating: Double?
    let text: String
    let relativeTime: String
    let authorName: String
    let authorURL: String?
    let authorPhotoURL: String?
    let googleMapsURL: String?
    let visitDate: GooglePlaceVisitDate?
    var id: String { googleMapsURL ?? "\(authorName)-\(relativeTime)" }
}
private struct GooglePlaceVisitDate: Decodable {
    let year: Int?
    let month: Int?
}
private struct GooglePlaceDetails: Decodable {
    let placeID: String
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let primaryType: String
    let rating: Double?
    let reviewCount: Int?
    let openNow: Bool?
    let openingHours: [String]
    let phoneNumber: String?
    let websiteURL: String?
    let googleMapsURL: String?
    let summary: String
    let photos: [GooglePlacePhoto]
    let reviews: [GooglePlaceReview]
}
private struct GooglePlaceSearchResponse: Decodable {
    struct Place: Decodable, Identifiable {
        let placeID: String
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let primaryType: String
        let isArea: Bool?
        let boundaryLevel: String?
        let types: [String]?
        let city: String?
        let countryCode: String?
        let latitudeSpan: Double?
        let longitudeSpan: Double?
        var id: String { placeID }
    }
    let places: [Place]
}
private struct GooglePlacesRequestError: Decodable {
    let errorCode: String?
    let message: String?
    let error: String?
}

private struct PersonalPlace: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var city: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: MapPlaceCategory
    var searchKind: SearchPlaceKind? = nil
    var boundaryCountryCode: String? = nil
    var searchLatitudeSpan: Double? = nil
    var searchLongitudeSpan: Double? = nil
    var boundaryLevel: String? = nil
    var searchTypes: [String]? = nil
    var phoneNumber: String? = nil
    var websiteURL: String? = nil
    var googlePlaceID: String? = nil
    var savedAt = Date()
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private enum PersonalPlaceStorage {
    static let key = "trippy.native.personalPlaces.v1"
    static let citiesKey = "trippy.native.cityCoordinates.v1"
    static func load() -> [PersonalPlace] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PersonalPlace].self, from: data)) ?? []
    }
    static func save(_ places: [PersonalPlace]) {
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func loadCities() -> [String: StoredPlaceCoordinate] {
        guard let data = UserDefaults.standard.data(forKey: citiesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: StoredPlaceCoordinate].self, from: data)) ?? [:]
    }
    static func saveCities(_ values: [String: StoredPlaceCoordinate]) {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: citiesKey) }
    }
}

private struct MapTripChoice: Identifiable {
    let id: UUID
    let title: String
}
private struct MapNoteChoice: Identifiable {
    let id: UUID
    let title: String
    let tripID: UUID?
}
private struct TikTokPlaceCluster: Identifiable {
    let id: String
    let title: String
    let city: String
    let mentions: [SocialPlaceMention]
}

private struct WorkspaceMapPin: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let layer: String
    let category: MapPlaceCategory
    var city: String = ""
    var address: String = ""
    var badge: String?
    var searchKind: SearchPlaceKind = .place
    var boundaryCountryCode: String? = nil
    var searchLatitudeSpan: Double? = nil
    var searchLongitudeSpan: Double? = nil
    var boundaryLevel: String? = nil
    var phoneNumber: String? = nil
    var websiteURL: String? = nil
    var googlePlaceID: String? = nil
    var personalPlace: PersonalPlace {
        PersonalPlace(id: id, name: name, city: city, address: address,
                      latitude: coordinate.latitude, longitude: coordinate.longitude, category: category,
                      searchKind: searchKind, boundaryCountryCode: boundaryCountryCode,
                      searchLatitudeSpan: searchLatitudeSpan, searchLongitudeSpan: searchLongitudeSpan,
                      boundaryLevel: boundaryLevel,
                      phoneNumber: phoneNumber, websiteURL: websiteURL, googlePlaceID: googlePlaceID)
    }
}

private struct MapPlaceLevel: Identifiable, Equatable {
    let id: String
    let title: String
    let minimumSpan: CLLocationDegrees
    let fontSize: CGFloat
}

private struct GeoBoundaryPoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private enum GeoBoundaryLineStyle: String, Codable, Sendable {
    case outline
    case fill
    case texture
}

private struct GeoBoundaryLine: Codable, Identifiable, Sendable {
    let id: String
    let points: [GeoBoundaryPoint]
    let style: GeoBoundaryLineStyle
}

private struct GeoBoundaryMetadata: Decodable {
    let boundaryISO: String?
    let boundaryName: String?
    let boundaryType: String?
    let simplifiedGeometryGeoJSON: String?
}

private actor GeoBoundaryRepository {
    static let shared = GeoBoundaryRepository()
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TrippyGeoBoundaries", isDirectory: true)
    private var catalog: [GeoBoundaryMetadata]?
    private var renderedCache: [String: [GeoBoundaryLine]] = [:]

    func boundary(countryISO2: String?, countryNames: [String], placeNames: [String], levelID: String,
                  center: GeoBoundaryPoint) async throws -> [GeoBoundaryLine]? {
        var countryKey = countryNames.map(Self.normalized).filter { !$0.isEmpty }
        if let countryISO2 {
            let englishName = Locale(identifier: "en").localizedString(forRegionCode: countryISO2)
            if let englishName { countryKey.append(Self.normalized(englishName)) }
            countryKey += Self.countryAliases[countryISO2, default: []].map(Self.normalized)
        }
        guard !countryKey.isEmpty else { return nil }

        let countries = try await countryCatalog()
        guard let country = countries.first(where: {
            guard let name = $0.boundaryName else { return false }
            return countryKey.contains(Self.normalized(name))
        }), let iso3 = country.boundaryISO else { return nil }

        let names = placeNames.map(Self.normalized).filter { !$0.isEmpty }
        let cellKey = "\(Int((center.latitude * 40).rounded()))_\(Int((center.longitude * 40).rounded()))"
        let cacheKey = "v3_\(iso3)_\(levelID)_\(cellKey)_\(names.sorted().joined(separator: "_"))"
        if let cached = renderedCache[cacheKey] { return cached }
        if let data = cachedData(named: "shape_\(cacheKey).json"),
           let lines = try? JSONDecoder().decode([GeoBoundaryLine].self, from: data) {
            renderedCache[cacheKey] = lines
            return lines
        }

        for adminLevel in Self.adminLevels(for: levelID) {
            try Task.checkCancellation()
            let metadataURL = URL(string: "https://www.geoboundaries.org/api/current/gbOpen/\(iso3)/ADM\(adminLevel)/")!
            guard let metadataData = try? await data(from: metadataURL, cacheName: "metadata_\(iso3)_ADM\(adminLevel).json"),
                  let metadata = Self.decodeMetadata(metadataData),
                  let geoJSONURL = metadata.simplifiedGeometryGeoJSON.flatMap(URL.init(string:)),
                  let geoJSON = try? await data(from: geoJSONURL, cacheName: "geojson_\(iso3)_ADM\(adminLevel).json"),
                  let lines = Self.matchingBoundary(in: geoJSON, names: names, center: center) else { continue }

            renderedCache[cacheKey] = lines
            if let encoded = try? JSONEncoder().encode(lines) { write(encoded, named: "shape_\(cacheKey).json") }
            return lines
        }
        return nil
    }

    private func countryCatalog() async throws -> [GeoBoundaryMetadata] {
        if let catalog { return catalog }
        let url = URL(string: "https://www.geoboundaries.org/api/current/gbOpen/ALL/ADM0/")!
        let data = try await data(from: url, cacheName: "catalog_ADM0.json")
        let values = Self.decodeMetadataList(data)
        guard !values.isEmpty else { throw URLError(.cannotDecodeContentData) }
        catalog = values
        return values
    }

    private static let countryAliases: [String: [String]] = [
        "US": ["United States of America"], "GB": ["UK"], "RU": ["Russian Federation"],
        "KR": ["South Korea", "Korea, Republic of"], "KP": ["North Korea", "Korea, Democratic People's Republic of"],
        "VN": ["Viet Nam"], "IR": ["Iran, Islamic Republic of"], "SY": ["Syrian Arab Republic"],
        "BO": ["Bolivia, Plurinational State of"], "VE": ["Venezuela, Bolivarian Republic of"],
        "TZ": ["United Republic of Tanzania"], "MD": ["Republic of Moldova"], "CZ": ["Czech Republic"],
        "CI": ["Cote d'Ivoire"], "MK": ["Macedonia"], "PS": ["State of Palestine"],
        "LA": ["Lao People's Democratic Republic"], "BN": ["Brunei Darussalam"],
        "FM": ["Federated States of Micronesia"], "CD": ["Democratic Republic of the Congo"],
        "CG": ["Republic of the Congo"]
    ]

    private func data(from url: URL, cacheName: String) async throws -> Data {
        if let data = cachedData(named: cacheName) { return data }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 25)
        request.setValue("Trippy iOS map boundaries", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        write(data, named: cacheName)
        return data
    }

    private func cachedData(named name: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(name))
    }

    private func write(_ data: Data, named name: String) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
        } catch { /* The in-memory result remains usable when the cache is unavailable. */ }
    }

    private static func decodeMetadata(_ data: Data) -> GeoBoundaryMetadata? {
        if let item = try? JSONDecoder().decode(GeoBoundaryMetadata.self, from: data) { return item }
        return decodeMetadataList(data).first
    }

    private static func decodeMetadataList(_ data: Data) -> [GeoBoundaryMetadata] {
        if let list = try? JSONDecoder().decode([GeoBoundaryMetadata].self, from: data) { return list }
        if let item = try? JSONDecoder().decode(GeoBoundaryMetadata.self, from: data) { return [item] }
        return []
    }

    private static func adminLevels(for levelID: String) -> [Int] {
        switch levelID {
        case "country": return [0]
        case "region": return [1, 2]
        case "district": return [2, 1]
        case "city": return [3, 2, 1]
        case "area": return [3, 2]
        default: return []
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func matchingBoundary(in data: Data, names: [String], center: GeoBoundaryPoint) -> [GeoBoundaryLine]? {
        guard let collection = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = collection["features"] as? [[String: Any]] else { return nil }
        var containing: [(nameMatches: Bool, lines: [GeoBoundaryLine])] = []
        for (featureIndex, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }
            let props = feature["properties"] as? [String: Any] ?? [:]
            let shapeName = (props["shapeName"] as? String).map(normalized) ?? ""
            let nameMatches = !shapeName.isEmpty && names.contains(shapeName)
            let polygons = polygonRings(type: type, coordinates: coordinates)
            guard !polygons.isEmpty,
                  polygons.contains(where: { polygonContains(center, rings: $0) }) else { continue }
            let lines = linesFor(polygons: polygons, featureIndex: featureIndex)
            if !lines.isEmpty {
                containing.append((nameMatches, lines))
                if nameMatches { return lines }
            }
        }
        return containing.first?.lines
    }

    private static func linesFor(polygons: [[[GeoBoundaryPoint]]], featureIndex: Int) -> [GeoBoundaryLine] {
        var result: [GeoBoundaryLine] = []
        let texturedPolygons = Set(polygons.indices.sorted {
            polygonExtentArea(polygons[$0]) > polygonExtentArea(polygons[$1])
        }.prefix(24))
        for (polygonIndex, polygon) in polygons.enumerated() {
            for (ringIndex, ring) in polygon.enumerated() {
                let points = simplify(ring)
                guard points.count >= 4 else { continue }
                if ringIndex == 0 {
                    result.append(GeoBoundaryLine(id: "\(featureIndex)-\(polygonIndex)-fill", points: points, style: .fill))
                }
                result.append(GeoBoundaryLine(id: "\(featureIndex)-\(polygonIndex)-\(ringIndex)-outline", points: points, style: .outline))
            }
            if texturedPolygons.contains(polygonIndex) {
                result += textureLines(in: polygon, featureIndex: featureIndex, polygonIndex: polygonIndex)
            }
        }
        return result
    }

    private static func polygonExtentArea(_ rings: [[GeoBoundaryPoint]]) -> Double {
        guard let points = rings.first, !points.isEmpty else { return 0 }
        let latitudes = points.map(\.latitude), longitudes = points.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else { return 0 }
        return (maxLatitude - minLatitude) * (maxLongitude - minLongitude)
    }

    private static func textureLines(in polygon: [[GeoBoundaryPoint]], featureIndex: Int, polygonIndex: Int) -> [GeoBoundaryLine] {
        guard let outer = polygon.first, outer.count >= 4 else { return [] }
        let points = simplify(outer)
        let latitudeValues = points.map(\.latitude)
        let longitudeValues = points.map(\.longitude)
        guard let minLatitude = latitudeValues.min(), let maxLatitude = latitudeValues.max(),
              let minLongitude = longitudeValues.min(), let maxLongitude = longitudeValues.max() else { return [] }
        let meanLatitude = (minLatitude + maxLatitude) / 2 * .pi / 180
        let longitudeScale = max(0.08, abs(cos(meanLatitude)))
        let minX = minLongitude * longitudeScale, maxX = maxLongitude * longitudeScale
        let minY = minLatitude, maxY = maxLatitude
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return [] }
        let spacing = span / 17
        var lines: [GeoBoundaryLine] = []
        var offset = minX - maxY
        let endOffset = maxX - minY
        var lineIndex = 0
        while offset <= endOffset {
            let endpoints = diagonalEndpoints(offset: offset, minX: minX, maxX: maxX, minY: minY, maxY: maxY, longitudeScale: longitudeScale)
            if let start = endpoints.first, let end = endpoints.last, start != end {
                for (segmentIndex, segment) in clippedSegments(from: start, to: end, polygon: polygon, longitudeScale: longitudeScale).enumerated() {
                    lines.append(GeoBoundaryLine(
                        id: "\(featureIndex)-\(polygonIndex)-hatch-\(lineIndex)-\(segmentIndex)",
                        points: segment,
                        style: .texture
                    ))
                }
            }
            offset += spacing
            lineIndex += 1
        }
        return lines
    }

    private static func diagonalEndpoints(offset: Double, minX: Double, maxX: Double, minY: Double, maxY: Double,
                                          longitudeScale: Double) -> [GeoBoundaryPoint] {
        var endpoints: [GeoBoundaryPoint] = []
        func add(x: Double, y: Double) {
            guard x >= minX - 1e-10, x <= maxX + 1e-10, y >= minY - 1e-10, y <= maxY + 1e-10 else { return }
            let point = GeoBoundaryPoint(latitude: y, longitude: x / longitudeScale)
            if !endpoints.contains(where: { abs($0.latitude - point.latitude) < 1e-9 && abs($0.longitude - point.longitude) < 1e-9 }) {
                endpoints.append(point)
            }
        }
        add(x: offset + minY, y: minY)
        add(x: offset + maxY, y: maxY)
        add(x: minX, y: minX - offset)
        add(x: maxX, y: maxX - offset)
        guard endpoints.count >= 2 else { return [] }
        return Array(endpoints.prefix(2))
    }

    private static func clippedSegments(from start: GeoBoundaryPoint, to end: GeoBoundaryPoint,
                                        polygon: [[GeoBoundaryPoint]], longitudeScale: Double) -> [[GeoBoundaryPoint]] {
        var cuts = [0.0, 1.0]
        for ring in polygon {
            guard ring.count > 1 else { continue }
            for index in ring.indices {
                let a = ring[index]
                let b = ring[(index + 1) % ring.count]
                if let t = intersectionParameter(start, end, a, b, longitudeScale: longitudeScale) { cuts.append(t) }
            }
        }
        cuts.sort()
        var uniqueCuts: [Double] = []
        for cut in cuts where uniqueCuts.last.map({ abs($0 - cut) > 1e-7 }) ?? true { uniqueCuts.append(cut) }
        guard uniqueCuts.count > 1 else { return [] }
        var segments: [[GeoBoundaryPoint]] = []
        for index in 0..<(uniqueCuts.count - 1) {
            let lower = uniqueCuts[index], upper = uniqueCuts[index + 1]
            guard upper - lower > 1e-7 else { continue }
            let midpoint = interpolate(start, end, (lower + upper) / 2)
            guard polygonContains(midpoint, rings: polygon) else { continue }
            segments.append([interpolate(start, end, lower), interpolate(start, end, upper)])
        }
        return segments
    }

    private static func intersectionParameter(_ start: GeoBoundaryPoint, _ end: GeoBoundaryPoint,
                                              _ edgeStart: GeoBoundaryPoint, _ edgeEnd: GeoBoundaryPoint,
                                              longitudeScale: Double) -> Double? {
        let rx = (end.longitude - start.longitude) * longitudeScale
        let ry = end.latitude - start.latitude
        let sx = (edgeEnd.longitude - edgeStart.longitude) * longitudeScale
        let sy = edgeEnd.latitude - edgeStart.latitude
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 1e-12 else { return nil }
        let qx = (edgeStart.longitude - start.longitude) * longitudeScale
        let qy = edgeStart.latitude - start.latitude
        let t = (qx * sy - qy * sx) / denominator
        let u = (qx * ry - qy * rx) / denominator
        return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : nil
    }

    private static func interpolate(_ start: GeoBoundaryPoint, _ end: GeoBoundaryPoint, _ fraction: Double) -> GeoBoundaryPoint {
        GeoBoundaryPoint(latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                         longitude: start.longitude + (end.longitude - start.longitude) * fraction)
    }

    private static func polygonRings(type: String, coordinates: Any) -> [[[GeoBoundaryPoint]]] {
        func rings(_ raw: Any) -> [[GeoBoundaryPoint]] {
            guard let values = raw as? [Any] else { return [] }
            return values.compactMap { rawRing in
                guard let positions = rawRing as? [Any] else { return nil }
                let points = positions.compactMap { position -> GeoBoundaryPoint? in
                    guard let pair = position as? [NSNumber], pair.count >= 2 else { return nil }
                    return GeoBoundaryPoint(latitude: pair[1].doubleValue, longitude: pair[0].doubleValue)
                }
                return points.count >= 4 ? points : nil
            }
        }
        switch type {
        case "Polygon": return [rings(coordinates)].filter { !$0.isEmpty }
        case "MultiPolygon":
            guard let polygons = coordinates as? [Any] else { return [] }
            return polygons.map(rings).filter { !$0.isEmpty }
        default: return []
        }
    }

    private static func polygonContains(_ point: GeoBoundaryPoint, rings: [[GeoBoundaryPoint]]) -> Bool {
        guard let outer = rings.first, pointInRing(point, ring: outer) else { return false }
        return !rings.dropFirst().contains(where: { pointInRing(point, ring: $0) })
    }

    private static func pointInRing(_ point: GeoBoundaryPoint, ring: [GeoBoundaryPoint]) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let a = ring[index], b = ring[previous]
            let crosses = (a.latitude > point.latitude) != (b.latitude > point.latitude)
            if crosses {
                let longitude = (b.longitude - a.longitude) * (point.latitude - a.latitude) /
                    (b.latitude - a.latitude) + a.longitude
                if point.longitude < longitude { inside.toggle() }
            }
            previous = index
        }
        return inside
    }

    private static func simplify(_ closedRing: [GeoBoundaryPoint], maximumPoints: Int = 480) -> [GeoBoundaryPoint] {
        var ring = closedRing
        if ring.count > 1, ring.first == ring.last { ring.removeLast() }
        guard ring.count > maximumPoints else { return ring + (ring.first.map { [$0] } ?? []) }
        let anchor = ring[0]
        let farthest = ring.indices.dropFirst().max { lhs, rhs in
            squaredDistance(ring[lhs], anchor) < squaredDistance(ring[rhs], anchor)
        } ?? ring.count / 2
        let firstPath = Array(ring[0...farthest])
        let secondPath = Array(ring[farthest...]) + [ring[0]]
        var tolerance = 0.00005
        var result = ring
        while result.count > maximumPoints && tolerance < 8 {
            let first = ramerDouglasPeucker(firstPath, tolerance: tolerance)
            let second = ramerDouglasPeucker(secondPath, tolerance: tolerance)
            result = first + Array(second.dropFirst())
            tolerance *= 2
        }
        if result.first != result.last, let first = result.first { result.append(first) }
        return result
    }

    private static func ramerDouglasPeucker(_ points: [GeoBoundaryPoint], tolerance: Double) -> [GeoBoundaryPoint] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = tolerance
            var farthestIndex: Int?
            for index in (start + 1)..<end {
                let distance = segmentDistance(points[index], from: points[start], to: points[end])
                if distance > farthest { farthest = distance; farthestIndex = index }
            }
            if let farthestIndex {
                keep[farthestIndex] = true
                stack.append((start, farthestIndex)); stack.append((farthestIndex, end))
            }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func segmentDistance(_ point: GeoBoundaryPoint, from start: GeoBoundaryPoint, to end: GeoBoundaryPoint) -> Double {
        let meanLatitude = (start.latitude + end.latitude + point.latitude) / 3 * .pi / 180
        let scale = cos(meanLatitude)
        let px = point.longitude * scale, py = point.latitude
        let ax = start.longitude * scale, ay = start.latitude
        let bx = end.longitude * scale, by = end.latitude
        let dx = bx - ax, dy = by - ay
        let length = dx * dx + dy * dy
        let fraction = length == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
        return hypot(px - (ax + fraction * dx), py - (ay + fraction * dy))
    }

    private static func squaredDistance(_ lhs: GeoBoundaryPoint, _ rhs: GeoBoundaryPoint) -> Double {
        let latitudeScale = cos((lhs.latitude + rhs.latitude) / 2 * .pi / 180)
        let dx = (lhs.longitude - rhs.longitude) * latitudeScale
        let dy = lhs.latitude - rhs.latitude
        return dx * dx + dy * dy
    }
}

private struct PinCelebrationView: View {
    let emoji: String
    @State private var burst = false
    private let colors: [Color] = [Color(hex: "E56C52"), Color(hex: "E7B45C"), Color(hex: "83A477"), Color(hex: "E99B79")]
    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2 + 8)
                for index in 0..<18 {
                    let angle = Double(index) * (.pi * 2 / 18)
                    let distance = burst ? 48.0 : 2.0
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                    let rect = CGRect(x: point.x - 3, y: point.y - 5, width: 6, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[index % colors.count].opacity(burst ? 0.0 : 0.95)))
                }
            }
            Text(emoji).font(.system(size: 38)).scaleEffect(burst ? 1.15 : 0.42).offset(y: 8)
        }
        .frame(width: 160, height: 92)
        .onAppear { withAnimation(.easeOut(duration: 0.72)) { burst = true } }
    }
}

private struct SearchMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.43), control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.74), control2: CGPoint(x: rect.minX, y: rect.height * 0.64))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.height * 0.4), radius: rect.width * 0.42, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.height * 0.64), control2: CGPoint(x: rect.width * 0.72, y: rect.height * 0.74))
        path.closeSubpath()
        return path
    }
}
private struct SearchMapPinView: View {
    let category: MapPlaceCategory
    var body: some View {
        ZStack {
            SearchMapPinShape().fill(LinearGradient(colors: [category.tint.opacity(0.88), category.tint, category.tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
            SearchMapPinShape().stroke(.white.opacity(0.92), lineWidth: 1.4)
            Circle().fill(.white.opacity(0.22)).frame(width: 17, height: 8).blur(radius: 2).offset(x: -5, y: -12)
            Image(systemName: category.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).offset(y: -4)
        }
        .frame(width: 42, height: 56)
        .shadow(color: category.tint.opacity(0.38), radius: 8, y: 5)
        .overlay(alignment: .topLeading) { Circle().fill(.white.opacity(0.82)).frame(width: 6, height: 6).blur(radius: 1).offset(x: 12, y: 9) }
        .frame(width: 48, height: 60).contentShape(Rectangle())
    }
}

private struct TripRouteLeg: Identifiable {
    let id: String
    let day: Int
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let walking: Bool
}

private extension TripFlowView {
    func linkedPlaceReference(_ place: PersonalPlace) -> LinkedPlaceReference {
        LinkedPlaceReference(id: place.id, name: place.name, address: place.address,
                             latitude: place.latitude, longitude: place.longitude,
                             googlePlaceID: place.googlePlaceID)
    }
    var tripCities: [String] {
        Array(Set(trips.filter { $0.research != nil }.map { $0.brief.destination.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    var cityTaskID: String { tripCities.joined(separator: "|") }
    var personalMapHome: some View {
        TrippyMapCanvas(
            pins: savedPlaces.map { personalPin($0) },
            cityPins: tripCities.compactMap { city in
                guard let coordinate = cityCoordinates[city]?.coordinate else { return nil }
                return WorkspaceMapPin(id: "city:\(city)", name: city, coordinate: coordinate, layer: "city", category: .other,
                                       badge: String(trips.filter { $0.brief.destination.trimmingCharacters(in: .whitespacesAndNewlines) == city && $0.research != nil }.count))
            },
            routes: [], savedPlaces: $savedPlaces, destination: "", fallback: nil,
            categories: Set(MapPlaceCategory.allCases),
            placesBaseURL: bridgeBaseURL, placesAccessToken: bridgeToken,
            onPlacesSettings: { showPlacesSettings = true },
            onCity: { city in libraryCity = city; librarySection = "Trips"; rootTab = "library" }, focusPlaceID: focusedSavedPlaceID,
            onNewTrip: { startNewTrip() },
            onCreateNote: { place, tripID in
                let id = UUID(); let linked = linkedPlaceReference(place); travelNotes.insert(TravelNote(id: id, title: place.name, tripID: tripID, sourceIDs: [], userText: place.address, updatedAt: .now, linkedPlaceIDs: [place.id], linkedPlaces: [linked]), at: 0); selectedTravelNoteID = id
            }, noteChoices: travelNotes.map { MapNoteChoice(id: $0.id, title: $0.title, tripID: $0.tripID) },
            onAddToNote: { place, noteID in
                guard let index = travelNotes.firstIndex(where: { $0.id == noteID }) else { return }
                let detail = [place.name, place.address].filter { !$0.isEmpty }.joined(separator: " · ")
                if !travelNotes[index].userText.localizedCaseInsensitiveContains(place.name) { travelNotes[index].userText += (travelNotes[index].userText.isEmpty ? "" : "\n") + detail }
                var linked = travelNotes[index].linkedPlaceIDs ?? []; if !linked.contains(place.id) { linked.append(place.id) }; travelNotes[index].linkedPlaceIDs = linked
                var references = travelNotes[index].linkedPlaces ?? []; let reference = linkedPlaceReference(place)
                if !references.contains(where: { $0.id == reference.id }) { references.append(reference) }; travelNotes[index].linkedPlaces = references
                travelNotes[index].updatedAt = .now; selectedTravelNoteID = noteID
            }, tripChoices: trips.map { MapTripChoice(id: $0.id, title: $0.title) },
            socialSources: socialSources, socialPlaces: socialPlaces, travelNotes: travelNotes,
            onSaveTripPin: { tripID, place in
                guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
                var pins = trips[index].savedPins ?? []; if !pins.contains(where: { $0.id == place.id }) { pins.append(place) }
                trips[index].savedPins = pins; trips[index].updatedAt = .now; TripStorage.save(trips)
            }
        ) {
            EmptyView()
        }
        .task(id: cityTaskID) {
            var resolvedCoordinates = cityCoordinates
            for city in tripCities where resolvedCoordinates[city] == nil {
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = city
                request.resultTypes = .address
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled, let item = response.mapItems.first else { continue }
                    let coordinate = item.placemark.coordinate
                    resolvedCoordinates[city] = StoredPlaceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, source: "Apple Maps city search", matchedAt: .now)
                } catch { /* Unlocated cities remain accessible through Library. */ }
            }
            guard !Task.isCancelled, resolvedCoordinates != cityCoordinates else { return }
            cityCoordinates = resolvedCoordinates
            PersonalPlaceStorage.saveCities(cityCoordinates)
        }
    }
    var appearanceButton: some View {
        Button { darkMode.toggle() } label: {
            Image(systemName: darkMode ? "sun.max" : "moon").frame(width: 44, height: 44)
        }.accessibilityLabel(darkMode ? "Φωτεινή εμφάνιση" : "Σκούρα εμφάνιση")
    }
    func personalPin(_ place: PersonalPlace) -> WorkspaceMapPin {
        WorkspaceMapPin(id: place.id, name: place.name, coordinate: place.coordinate, layer: "saved", category: place.category, city: place.city, address: place.address, searchKind: place.searchKind ?? .place, boundaryCountryCode: place.boundaryCountryCode, searchLatitudeSpan: place.searchLatitudeSpan, searchLongitudeSpan: place.searchLongitudeSpan, phoneNumber: place.phoneNumber, websiteURL: place.websiteURL, googlePlaceID: place.googlePlaceID)
    }
    var filteredLibraryTrips: [Trip] {
        trips.filter { trip in
            (libraryCity == nil || trip.brief.destination.trimmingCharacters(in: .whitespacesAndNewlines) == libraryCity) &&
            (libraryQuery.isEmpty || "\(trip.title) \(trip.brief.destination)".localizedCaseInsensitiveContains(libraryQuery))
        }
    }
    var librarySearchPrompt: String {
        switch librarySection {
        case "Notes": return "Αναζήτηση σημειώσεων"
        case "Inbox": return "Αναζήτηση πηγών"
        case "Videos": return "Αναζήτηση σε TikTok videos"
        case "Pins": return "Αναζήτηση στα Pins σου"
        default: return "Αναζήτηση ταξιδιών"
        }
    }
    var modernLibrary: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Library").font(.custom("PlusJakartaSans-ExtraBold", size: 34, relativeTo: .largeTitle)).tracking(-1.2)
                            Text("Τα ταξίδια, τα μέρη, η έμπνευσή σου.").font(.subheadline).foregroundStyle(AppPalette.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { librarySearchVisible.toggle() }
                        } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                            .accessibilityLabel("Αναζήτηση στη βιβλιοθήκη")
                        libraryAddMenu
                    }
                    if librarySearchVisible || !libraryQuery.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(librarySearchPrompt, text: $libraryQuery).font(.body).submitLabel(.search)
                            Button { libraryQuery = ""; librarySearchVisible = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                            }.accessibilityLabel("Κλείσιμο αναζήτησης")
                        }.padding(.leading, 16).padding(.trailing, 4).frame(minHeight: 52)
                            .background(AppPalette.surface, in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 24) {
                            ForEach(["Trips", "Pins", "Videos", "Notes", "Inbox"], id: \.self) { section in
                                Button {
                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { librarySection = section }
                                } label: {
                                    VStack(spacing: 10) {
                                        Text(section).font(.headline).foregroundStyle(librarySection == section ? AppPalette.ink : AppPalette.secondaryInk)
                                        Capsule().fill(librarySection == section ? AppPalette.ink : .clear).frame(height: 3)
                                    }.frame(minHeight: 44)
                                }.buttonStyle(.plain).accessibilityAddTraits(librarySection == section ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                    if let city = libraryCity {
                        Button { libraryCity = nil } label: {
                            Label(city, systemImage: "xmark.circle.fill").font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16).frame(minHeight: 44).background(AppPalette.surface, in: Capsule())
                        }.accessibilityLabel("Κατάργηση φίλτρου πόλης \(city)")
                    }
                    if librarySection == "Trips" {
                        if filteredLibraryTrips.isEmpty {
                            ContentUnavailableView(libraryCity == nil ? "Το επόμενο ταξίδι αρχίζει εδώ" : "Κανένα ταξίδι με αυτά τα φίλτρα", systemImage: "suitcase.rolling", description: Text("Πάτησε + για να φτιάξεις το brief σου."))
                        }
                        ForEach(filteredLibraryTrips) { trip in libraryTripRow(trip) }
                    } else if librarySection == "Pins" { savedLibrary; socialSavedPlaces }
                    else if librarySection == "Videos" { videoLibrary }
                    else if librarySection == "Notes" { notesLibrary }
                    else { socialInboxLibrary }
                    if librarySection == "Trips", let city = libraryCity {
                        socialPlaceVideoCarousel(city: city)
                    }
                }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 32)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(AppPalette.canvas).toolbar(.hidden, for: .navigationBar)
        }
    }
    var libraryAddMenu: some View {
        Menu {
            if librarySection == "Trips" { Button("Νέο ταξίδι", systemImage: "suitcase.rolling") { startNewTrip() } }
            if librarySection == "Videos" { Button("Προσθήκη TikTok link", systemImage: "link") { showImportLink = true } }
            if librarySection == "Notes" {
                Button("Νέο Note", systemImage: "square.and.pencil") {
                    let id = UUID()
                    travelNotes.insert(TravelNote(id: id, title: "Νέο Note", tripID: nil, sourceIDs: [], userText: "", updatedAt: .now), at: 0)
                    selectedTravelNoteID = id
                }
            }
            if librarySection == "Pins" { Button("Βρες ένα μέρος", systemImage: "magnifyingglass") { activeTripID = nil; stage = .library; rootTab = "map" } }
            Button("Προσθήκη TikTok link", systemImage: "link") { showImportLink = true }
        } label: {
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(AppPalette.inverseInk)
                .frame(width: 44, height: 44).background(AppPalette.brand, in: Circle())
        }.accessibilityLabel("Προσθήκη στη βιβλιοθήκη")
    }
    func libraryTripRow(_ trip: Trip) -> some View {
        Button { selectMapTrip(trip) } label: {
            VStack(alignment: .leading, spacing: 12) {
                TripCover(vibe: trip.brief.vibes.first ?? "Πόλη", destination: trip.brief.destination)
                    .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.title).font(.custom("PlusJakartaSans-Bold", size: 20)).foregroundStyle(AppPalette.ink)
                        Text("\(trip.brief.dateSummary) · \(trip.brief.travelers) άτομα").font(.subheadline).foregroundStyle(AppPalette.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: trip.research == nil ? "square.and.pencil" : "arrow.up.right").frame(width: 44, height: 44)
                }
                if trip.research == nil { Text("Brief · Συνέχισε τον σχεδιασμό").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
            }.contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle())
        .contextMenu {
            Button("Επεξεργασία brief", systemImage: "square.and.pencil") { editTrip(trip) }
            Button("Διαγραφή", systemImage: "trash", role: .destructive) { deleteTrip(trip.id) }
        }
    }
    var savedLibrary: some View {
        let places = savedPlaces.filter {
            (libraryCity == nil || $0.city == libraryCity) &&
            (libraryQuery.isEmpty || "\($0.name) \($0.city)".localizedCaseInsensitiveContains(libraryQuery))
        }
        return VStack(spacing: 16) {
            if places.isEmpty {
                ContentUnavailableView("Τα μέρη σου, σε έναν χάρτη", systemImage: "bookmark", description: Text("Βρες ένα μέρος στον χάρτη και πάτησε Save."))
            }
            ForEach(places) { place in
                HStack(spacing: 16) {
                    Image(systemName: place.category.symbol).frame(width: 48, height: 48)
                        .background(AppPalette.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        showTripDetails = false; activeTripID = nil; stage = .library
                        focusedSavedPlaceID = place.id; rootTab = "map"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).font(.headline)
                            Text(place.address.nonEmpty ?? place.city).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("\(place.name) · Προβολή στον χάρτη")
                    Menu {
                        Button("Άνοιγμα στο Apple Maps", systemImage: "map") {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); item.name = place.name; item.openInMaps()
                        }
                        Button("Αφαίρεση από Pins", systemImage: "bookmark.slash", role: .destructive) { savedPlaces.removeAll { $0.id == place.id } }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                }.foregroundStyle(AppPalette.ink)
                Divider()
            }
        }
    }
    func selectMapTrip(_ trip: Trip) {
        activeScheduleDate = nil; alternativesForItemID = nil
        selectedScheduleDayIndex = nil; selectedMapDay = nil
        workspaceTab = "Πρόγραμμα"
        showTripDetails = false
        resolvedCoordinates = [:]
        destinationCoordinate = nil
        activeTripID = trip.id
        brief = trip.brief
        for (id, stored) in trip.mapCoordinatesByPlaceID ?? [:] { resolvedCoordinates[id] = stored.coordinate }
        rootTab = "map"
        if trip.research == nil { openBrief() } else { stage = .workspace }
    }
    func workspacePin(itemID: String, day: [String: Any], dayIndex: Int, stopIndex: Int) -> WorkspaceMapPin? {
        let place = scheduledPlace(itemID, day: day)
        let stop = scheduledStop(itemID, day: day)
        guard let coordinate = planCoordinate(itemID, day: day) else { return nil }
        let name = place.flatMap(recordTitle) ?? stop.map(activityTitle) ?? "Στάση"
        let category = MapPlaceCategory.classify(recordValue(place ?? stop ?? [:], keys: ["category", "type", "kind"]) ?? "")
        return WorkspaceMapPin(id: place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID,
                               name: name, coordinate: coordinate, layer: "planned", category: category,
                               city: brief.destination, address: recordValue(place ?? [:], keys: ["address"]) ?? "",
                               badge: "\(dayIndex + 1).\(stopIndex + 1)")
    }
    var tripWorkspacePins: [WorkspaceMapPin] {
        var result: [WorkspaceMapPin] = []
        var plannedIDs = Set<String>()
        for (dayIndex, day) in dayRecords.enumerated() {
            for (stopIndex, itemID) in scheduleIDs(day, index: dayIndex).enumerated() {
                let id = scheduledPlace(itemID, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID
                plannedIDs.insert(id)
                if selectedMapDay == nil || selectedMapDay == dayIndex,
                   let pin = workspacePin(itemID: itemID, day: day, dayIndex: dayIndex, stopIndex: stopIndex) { result.append(pin) }
            }
        }
        for (index, place) in placeRecords.enumerated() {
            let id = recordValue(place, keys: ["id", "place_id"]) ?? "place-\(index)"
            guard !plannedIDs.contains(id), let coordinate = placeCoordinate(place) else { continue }
            result.append(WorkspaceMapPin(id: id, name: recordTitle(place) ?? "Μέρος", coordinate: coordinate, layer: "recommended",
                                          category: .classify(recordValue(place, keys: ["category", "type", "kind"]) ?? ""), city: brief.destination,
                                          address: recordValue(place, keys: ["address"]) ?? ""))
        }
        let center = cityCoordinates[brief.destination]?.coordinate ?? result.first?.coordinate
        result += savedPlaces.filter { place in
            if place.city.localizedCaseInsensitiveCompare(brief.destination) == .orderedSame { return true }
            guard let center else { return false }
            return CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 60000
        }.map(personalPin)
        // One physical place can belong to several layers; choose the visible layer, then deduplicate.
        var seen = Set<String>()
        var visible: [WorkspaceMapPin] = []
        for pin in result where mapLayers.contains(pin.layer) && mapCategories.contains(pin.category) {
            guard seen.insert(pin.id).inserted else { continue }
            let duplicate = visible.contains { existing in
                existing.name.localizedCaseInsensitiveCompare(pin.name) == .orderedSame &&
                CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)) < 30
            }
            if !duplicate { visible.append(pin) }
        }
        return visible
    }
    var workspaceRouteLegs: [TripRouteLeg] {
        guard mapLayers.contains("planned") else { return [] }
        var legs: [TripRouteLeg] = []
        for (dayIndex, day) in dayRecords.enumerated() where selectedMapDay == nil || selectedMapDay == dayIndex {
            let ids = scheduleIDs(day, index: dayIndex)
            guard ids.count > 1 else { continue }
            for index in 1..<ids.count {
                // A missing coordinate breaks the route. Never join over an unlocated stop.
                guard let from = workspacePin(itemID: ids[index - 1], day: day, dayIndex: dayIndex, stopIndex: index - 1),
                      let to = workspacePin(itemID: ids[index], day: day, dayIndex: dayIndex, stopIndex: index) else { continue }
                let mode = recordValue(scheduledStop(ids[index], day: day) ?? [:], keys: ["transport_mode", "travel_mode", "mode"])?.lowercased()
                guard mode == nil || ["walk", "walking", "foot", "drive", "driving", "car"].contains(mode!) else { continue }
                legs.append(TripRouteLeg(id: "\(activeTripID?.uuidString ?? ""):\(dayIndex):\(ids[index - 1]):\(ids[index])", day: dayIndex, from: from.coordinate, to: to.coordinate, walking: mode == nil ? routePreviewMode == "walking" : ["walk", "walking", "foot"].contains(mode!)))
            }
        }
        return legs
    }
    var tripMapWorkspace: some View {
        TrippyMapCanvas(pins: tripWorkspacePins + (trips.first(where: { $0.id == activeTripID })?.savedPins ?? []).map(personalPin), cityPins: [], routes: workspaceRouteLegs,
                        savedPlaces: $savedPlaces, destination: brief.destination,
                        fallback: cityCoordinates[brief.destination]?.coordinate, categories: mapCategories,
                        placesBaseURL: bridgeBaseURL, placesAccessToken: bridgeToken,
                        onPlacesSettings: { showPlacesSettings = true }, onCity: { _ in }, onPlanPin: { pin in
            if pin.layer == "recommended", let place = placeRecords.first(where: { recordValue($0, keys: ["id", "place_id"]) == pin.id }), !dayRecords.isEmpty {
                let index = selectedMapDay ?? 0
                if dayRecords.indices.contains(index) { addPlaceToDay(place, date: scheduleDateKey(dayRecords[index], index: index)) }
            }
            if pin.layer == "planned" {
                let dayIndex = dayRecords.enumerated().first { dayIndex, day in
                    scheduleIDs(day, index: dayIndex).contains { itemID in
                        (scheduledPlace(itemID, day: day).flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? itemID) == pin.id
                    }
                }?.offset
                selectedMapDay = dayIndex; selectedScheduleDayIndex = dayIndex
            }
            detailsDetent = .large; showTripDetails = true
        },
                        onNewTrip: { startNewTrip() }, onCreateNote: { place, tripID in
                            let id = UUID(); let linked = linkedPlaceReference(place); travelNotes.insert(TravelNote(id: id, title: place.name, tripID: tripID, sourceIDs: [], userText: place.address, updatedAt: .now, linkedPlaceIDs: [place.id], linkedPlaces: [linked]), at: 0); selectedTravelNoteID = id
                        }, noteChoices: travelNotes.map { MapNoteChoice(id: $0.id, title: $0.title, tripID: $0.tripID) },
                        onAddToNote: { place, noteID in
                            guard let index = travelNotes.firstIndex(where: { $0.id == noteID }) else { return }
                            let detail = [place.name, place.address].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !travelNotes[index].userText.localizedCaseInsensitiveContains(place.name) { travelNotes[index].userText += (travelNotes[index].userText.isEmpty ? "" : "\n") + detail }
                            var linked = travelNotes[index].linkedPlaceIDs ?? []; if !linked.contains(place.id) { linked.append(place.id) }; travelNotes[index].linkedPlaceIDs = linked
                            var references = travelNotes[index].linkedPlaces ?? []; let reference = linkedPlaceReference(place)
                            if !references.contains(where: { $0.id == reference.id }) { references.append(reference) }; travelNotes[index].linkedPlaces = references
                            travelNotes[index].updatedAt = .now; selectedTravelNoteID = noteID
                        }, tripChoices: trips.filter { $0.id == activeTripID }.map { MapTripChoice(id: $0.id, title: $0.title) },
                        socialSources: socialSources, socialPlaces: socialPlaces, travelNotes: travelNotes,
                        onSaveTripPin: { tripID, place in
                            guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
                            var pins = trips[index].savedPins ?? []; if !pins.contains(where: { $0.id == place.id }) { pins.append(place) }
                            trips[index].savedPins = pins; trips[index].updatedAt = .now; TripStorage.save(trips)
                        }, selectionKey: "\(activeTripID?.uuidString ?? ""):\(selectedMapDay.map(String.init) ?? "overview")",
                        schedulablePlaceIDs: dayRecords.isEmpty ? [] : Set(placeRecords.compactMap { recordValue($0, keys: ["id", "place_id"]) }),
                        planDayTitle: "Day \((selectedMapDay ?? 0) + 1)") {
            HStack(alignment: .top, spacing: 12) {
                Button { stage = .library; activeTripID = nil; rootTab = "map" } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44).background(AppPalette.canvas, in: Circle())
                }.accessibilityLabel("Κλείσιμο ταξιδιού")
                VStack(alignment: .leading, spacing: 10) {
                    MapTripTitle(title: activeTrip?.title ?? brief.title)
                    if verticalSizeClass != .compact {
                        Text("\(brief.dateSummary) · \(brief.travelers) άτομα")
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Όνομα ταξιδιού", systemImage: "pencil") { tripNameDraft = activeTrip?.title ?? brief.title; showRenameTrip = true }
                    Button("Επεξεργασία brief", systemImage: "slider.horizontal.3") { stage = .brief }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(AppPalette.canvas, in: Circle()) }
                    .accessibilityLabel("Επιλογές ταξιδιού")
            }
        }
        .task(id: "\(activeTripID?.uuidString ?? ""):\(activeTrip?.research?.hashValue ?? 0)") { await resolvePlaceCoordinates() }
        .safeAreaInset(edge: .bottom, spacing: 12) { tripMapShelf }
        .sheet(isPresented: $showTripMapFilters) { tripMapFilterSheet }
        .sheet(isPresented: $showTripDetails) { tripDetailPanel }
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let id = alternativesForItemID { alternativesSheet(itemID: id) }
        }
    }
    @ViewBuilder var tripMapShelf: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Όλο το ταξίδι") { selectedMapDay = nil; selectedScheduleDayIndex = nil }
                ForEach(dayRecords.indices, id: \.self) { index in
                    Button("Ημέρα \(index + 1)") { selectedMapDay = index; selectedScheduleDayIndex = index }
                }
            } label: {
                Label(selectedMapDay.map { "Ημέρα \($0 + 1)" } ?? "Όλο το ταξίδι", systemImage: "chevron.down")
                    .font(PlanType.detail).frame(minHeight: 44)
            }
            Spacer(minLength: 0)
            Button { showTripMapFilters = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Φίλτρα χάρτη")
            Button { selectedScheduleDayIndex = selectedMapDay; detailsDetent = .large; showTripDetails = true } label: {
                Text("Πρόγραμμα").font(PlanType.detail).padding(.horizontal, 16).frame(minHeight: 44)
                    .foregroundStyle(AppPalette.inverseInk).background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }.foregroundStyle(AppPalette.ink).padding(12).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: 720)
    }

    var tripPeekSummary: String {
        if let index = selectedMapDay, dayRecords.indices.contains(index) {
            return "\(scheduleIDs(dayRecords[index], index: index).count) στάσεις · Πρόγραμμα και λεπτομέρειες"
        }
        if dayRecords.isEmpty { return "Πρόγραμμα, μέρη και κόστος" }
        return "\(dayRecords.count) ημέρες · Πρόγραμμα, μέρη και κόστος"
    }
    var tripMapFilterSheet: some View {
        NavigationStack {
            Form {
                Section("Περιεχόμενο χάρτη") {
                    ForEach(["planned", "recommended", "saved"], id: \.self) { layer in
                        Toggle(layer == "planned" ? "Πρόγραμμα" : (layer == "recommended" ? "Προτάσεις" : "Pins"), isOn: Binding(get: { mapLayers.contains(layer) }, set: { on in
                            if on { mapLayers.insert(layer) } else { mapLayers.remove(layer) }
                        }))
                    }
                }
                Section("Κατηγορίες") {
                    ForEach(MapPlaceCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { mapCategories.contains(category) }, set: { on in
                            if on { mapCategories.insert(category) } else { mapCategories.remove(category) }
                        })) { Label(category.rawValue, systemImage: category.symbol) }
                    }
                }
                Section("Προεπισκόπηση διαδρομής") {
                    Picker("Μετακίνηση", selection: $routePreviewMode) {
                        Text("Πεζή").tag("walking"); Text("Οδήγηση").tag("driving")
                    }.pickerStyle(.segmented)
                    Text("Χρησιμοποιείται μόνο όταν το πρόγραμμα δεν ορίζει ήδη μέσο μετακίνησης.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Εμφάνιση όλων των κατηγοριών") { mapCategories = Set(MapPlaceCategory.allCases) }
                }
            }.tint(AppPalette.brand).navigationTitle("Ο χάρτης σου").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { showTripMapFilters = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    func mapDayButton(_ title: String, index: Int?) -> some View {
        Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selectedMapDay = index; selectedScheduleDayIndex = index } } label: {
            VStack(spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let index, dayRecords.indices.contains(index), let date = recordValue(dayRecords[index], keys: ["date"]) {
                    Text(date).font(.caption2).opacity(0.75)
                }
            }.foregroundStyle(selectedMapDay == index ? AppPalette.inverseInk : AppPalette.ink)
                .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 44)
                .modifier(SelectedMapChip(selected: selectedMapDay == index))
        }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(selectedMapDay == index ? .isSelected : [])
    }
    func mapLayerButton(_ title: String, symbol: String, layer: String) -> some View {
        Button { if mapLayers.contains(layer) { mapLayers.remove(layer) } else { mapLayers.insert(layer) } } label: {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).labelStyle(.titleOnly)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .foregroundStyle(mapLayers.contains(layer) ? AppPalette.ink : AppPalette.secondaryInk)
                .opacity(mapLayers.contains(layer) ? 1 : 0.65)
                .modifier(AdaptiveGlassControl(shape: .capsule))
                .overlay(alignment: .bottom) {
                    if mapLayers.contains(layer) { Circle().fill(AppPalette.ink).frame(width: 4, height: 4).padding(.bottom, 5) }
                }
        }.buttonStyle(QuietPressStyle()).accessibilityValue(mapLayers.contains(layer) ? "Ενεργό" : "Ανενεργό")
    }
    var filteredPlanPlaces: [[String: Any]] {
        placeRecords.filter { place in
            let id = recordValue(place, keys: ["id", "place_id"]) ?? ""
            let text = ["name", "description", "address", "cuisine"].compactMap { place[$0] as? String }.joined(separator: " ")
            return (planPlaceQuery.isEmpty || text.localizedCaseInsensitiveContains(planPlaceQuery))
                && (planPlaceCategory == nil || MapPlaceCategory.classify(recordValue(place, keys: ["category", "type"]) ?? "") == planPlaceCategory)
                && (!planLikedOnly || activeTrip?.reactionsByItemID?["place|\(id)"] == "like")
        }
    }
    var planPlaceFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppPalette.secondaryInk)
                TextField("Όνομα, περιοχή ή κουζίνα", text: $planPlaceQuery).font(PlanType.body)
                    .autocorrectionDisabled()
            }.padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Όλα") { planPlaceCategory = nil }
                        .buttonStyle(.bordered).tint(planPlaceCategory == nil ? AppPalette.brand : AppPalette.secondaryInk)
                    ForEach(MapPlaceCategory.allCases.filter { category in
                        placeRecords.contains { MapPlaceCategory.classify(recordValue($0, keys: ["category", "type"]) ?? "") == category }
                    }) { category in
                        Button(category.rawValue) { planPlaceCategory = planPlaceCategory == category ? nil : category }
                            .buttonStyle(.bordered).tint(planPlaceCategory == category ? AppPalette.brand : AppPalette.secondaryInk)
                    }
                }
            }
            Toggle("Μόνο όσα μου αρέσουν", isOn: $planLikedOnly).font(PlanType.detail).tint(AppPalette.brand)
        }
    }
    @ViewBuilder var tripPanelContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if workspaceTab == "Μέρη" {
                Text("Επιλογές για σένα").font(PlanType.title)
                Text("\(placeRecords.count) μέρη · κράτα όσα σου αρέσουν ή πρόσθεσέ τα σε ημέρα.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                planPlaceFilters
                Text("\(filteredPlanPlaces.count) αποτελέσματα").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                ForEach(Array(filteredPlanPlaces.enumerated()), id: \.offset) { index, place in placeCard(place, index: index) }
                if placeRecords.isEmpty { emptyResearchMessage }
                else if filteredPlanPlaces.isEmpty { Text("Δεν υπάρχουν μέρη με αυτά τα φίλτρα.").font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
            } else {
                analyticalCostTable
                VStack(alignment: .leading, spacing: 16) { Text("Εισιτήρια και κρατήσεις").font(PlanType.heading); ticketContent }
                DisclosureGroup("Μετακινήσεις") { transportContent.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Οι δικές σου δαπάνες") { budgetCalculator.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Ωράρια και αργίες") { calendarContent.padding(.top, 16) }.font(PlanType.heading)
                DisclosureGroup("Πηγές της έρευνας") { sourcesSection.padding(.top, 16) }.font(PlanType.heading)
            }
        }.tint(AppPalette.ink).padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
    }

    var tripDetailPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(activeTrip?.title ?? brief.title).font(PlanType.heading).lineLimit(1)
                Spacer()
                Button { showTripDetails = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Κλείσιμο προγράμματος")
            }.padding(.horizontal, 20).padding(.top, 8)
            HStack(spacing: 0) {
                ForEach(["Πρόγραμμα", "Μέρη", "Κόστη"], id: \.self) { tab in
                    Button { workspaceTab = tab } label: {
                        VStack(spacing: 8) {
                            Text(tab).font(PlanType.detail).frame(maxWidth: .infinity, minHeight: 36)
                            Rectangle().fill(workspaceTab == tab ? AppPalette.brand : .clear).frame(height: 2)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(workspaceTab == tab ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
            Divider()
            if workspaceTab == "Πρόγραμμα" {
                scheduleDayPicker.padding(.horizontal, 20).padding(.vertical, 12)
                scheduleList
            } else { ScrollView { tripPanelContent } }
        }
        .foregroundStyle(AppPalette.ink).background(AppPalette.canvas)
        .environment(\.layoutDirection, .leftToRight)
        .presentationDetents([.large], selection: $detailsDetent)
        .presentationDragIndicator(.visible)
        .onChange(of: selectedScheduleDayIndex) { _, day in selectedMapDay = day }
        .sheet(isPresented: Binding(get: { locatingPlanItemID != nil }, set: { if !$0 { locatingPlanItemID = nil } })) {
            if let id = locatingPlanItemID {
                let day = dayRecords.enumerated().first { scheduleIDs($0.element, index: $0.offset).contains(id) }?.element ?? [:]
                let place = scheduledPlace(id, day: day)
                let name = place.flatMap(recordTitle) ?? scheduledStop(id, day: day).map(activityTitle) ?? ""
                PlanLocationPicker(name: name, destination: brief.destination, center: destinationCoordinate) { coordinate in
                    let key = place.flatMap { recordValue($0, keys: ["id", "place_id"]) } ?? id
                    resolvedCoordinates[key] = coordinate
                    storeResolvedCoordinate(id: key, coordinate: coordinate)
                    locatingPlanItemID = nil
                }
            }
        }
        .sheet(isPresented: Binding(get: { activeScheduleDate != nil }, set: { if !$0 { activeScheduleDate = nil } })) {
            if let date = activeScheduleDate { addToDaySheet(date: date) }
        }
        .sheet(isPresented: Binding(get: { alternativesForItemID != nil }, set: { if !$0 { alternativesForItemID = nil } })) {
            if let id = alternativesForItemID { alternativesSheet(itemID: id) }
        }
    }


}

// Shared map controls keep Apple cartography and landmark artwork intact.
private struct TrippyMapCanvas<Header: View>: View {
    let pins: [WorkspaceMapPin]
    let cityPins: [WorkspaceMapPin]
    let routes: [TripRouteLeg]
    @Binding var savedPlaces: [PersonalPlace]
    let destination: String
    let fallback: CLLocationCoordinate2D?
    let categories: Set<MapPlaceCategory>
    let placesBaseURL: String
    let placesAccessToken: String
    var onPlacesSettings: (() -> Void)? = nil
    let onCity: (String) -> Void
    var onPlanPin: ((WorkspaceMapPin) -> Void)? = nil
    var focusPlaceID: String? = nil
    var onNewTrip: (() -> Void)? = nil
    var onCreateNote: ((PersonalPlace, UUID?) -> Void)? = nil
    var noteChoices: [MapNoteChoice] = []
    var onAddToNote: ((PersonalPlace, UUID) -> Void)? = nil
    var tripChoices: [MapTripChoice] = []
    var socialSources: [ImportedSocialSource] = []
    var socialPlaces: [SocialPlaceMention] = []
    var travelNotes: [TravelNote] = []
    var onSaveTripPin: ((UUID, PersonalPlace) -> Void)? = nil
    var selectionKey: String = ""
    var schedulablePlaceIDs: Set<String> = []
    var planDayTitle: String = "Day 1"
    @ViewBuilder let header: () -> Header
    @AppStorage("trippy.native.mapTheme") private var theme = "Explore"
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @AppStorage("trippy.native.glassTint") private var glassTint = "auto"
    @State private var showHomeFilters = false
    @State private var hasFittedMap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var mapPlaceBoundaryLines: [GeoBoundaryLine] = []
    @State private var areaHighlightOpacity = 0.0
    @State private var query = ""
    @State private var searchResults: [PersonalPlace] = []
    @State private var searchFilter: MapSearchFilter = .all
    @State private var searching = false
    @State private var searchError: String?
    @State private var searchSourceNotice: String?
    @State private var selectedPin: WorkspaceMapPin?
    @State private var selectedSearchPlace: WorkspaceMapPin?
    @State private var focusedMapPinID: String?
    @State private var selectedPinCategory: MapPlaceCategory?
    @State private var celebrationEmoji: String?
    @State private var pendingPlacePanelAction: (() -> Void)?
    @State private var googlePlaceDetails: GooglePlaceDetails?
    @State private var resolvedGooglePlaceIDs: [String: String] = [:]
    @State private var loadingGoogleDetails = false
    @State private var googleDetailsError: String?
    @State private var pendingPlanPin: WorkspaceMapPin?
    @State private var renderedRoutes: [String: MKRoute] = [:]
    @State private var routeCache: [String: MKRoute] = [:]
    @State private var routing = false
    @State private var failedRoutes = 0
    @State private var directionsRoute: MKRoute?
    @State private var showDirections = false
    @State private var calculatingDirections = false
    @State private var directionsError: String?
    @State private var locationError: String?
    @State private var centerWhenLocationArrives = false
    @State private var pendingDirectionsPin: WorkspaceMapPin?
    @StateObject private var locationService = CurrentLocationService()
    @State private var homeCategories = Set(MapPlaceCategory.allCases)
    @FocusState private var searchFocused: Bool
    private var effectiveCategories: Set<MapPlaceCategory> { destination.isEmpty ? homeCategories : categories }
    private var displayedSearchResults: [PersonalPlace] { searchResults.filter { searchFilter.includes($0) } }
    private var routeTaskID: String {
        routes.map { "\($0.id):\($0.from.latitude),\($0.from.longitude):\($0.to.latitude),\($0.to.longitude):\($0.walking)" }.joined(separator: "|")
    }
    private var pointTaskID: String { pins.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }.joined(separator: "|") + cityPins.map(\.id).joined() }
    private func cameraKey(for region: MKCoordinateRegion) -> String {
        let latitudeStep = max(0.004, min(0.75, region.span.latitudeDelta / 3))
        let longitudeStep = max(0.004, min(0.75, region.span.longitudeDelta / 3))
        let zoomBand = [0.08, 0.12, 0.6, 0.8, 2, 4, 8, 10, 18, 20, 95].firstIndex(where: { region.span.latitudeDelta < $0 }) ?? 11
        return "\(Int((region.center.latitude / latitudeStep).rounded())),\(Int((region.center.longitude / longitudeStep).rounded())),\(zoomBand)"
    }
    private var poiCategories: [MKPointOfInterestCategory] {
        var result: [MKPointOfInterestCategory] = []
        if effectiveCategories.contains(.sights) || effectiveCategories.contains(.parks) { result += [.museum, .nationalPark, .park, .theater] }
        if effectiveCategories.contains(.restaurants) || effectiveCategories.contains(.brunch) || effectiveCategories.contains(.streetFood) || effectiveCategories.contains(.burgers) || effectiveCategories.contains(.seafood) || effectiveCategories.contains(.vegan) { result += [.restaurant, .bakery] }
        if effectiveCategories.contains(.coffee) { result += [.cafe] }
        if effectiveCategories.contains(.bars) || effectiveCategories.contains(.clubs) { result += [.nightlife, .brewery, .winery] }
        if effectiveCategories.contains(.groceries) || effectiveCategories.contains(.shopping) || effectiveCategories.contains(.touristShops) { result += [.foodMarket, .store] }
        if effectiveCategories.contains(.metro) { result += [.publicTransport] }
        return result
    }
    private var mapStyle: MapStyle {
        switch theme {
        case "Satellite": return .imagery(elevation: .realistic)
        case "Hybrid": return .hybrid(elevation: .realistic, pointsOfInterest: .including(poiCategories))
        default: return .standard(elevation: .realistic, emphasis: theme == "Quiet" ? .muted : .automatic, pointsOfInterest: effectiveCategories.count == MapPlaceCategory.allCases.count ? .all : .including(poiCategories))
        }
    }
    var body: some View {
        MapReader { mapProxy in
        Map(position: $position) {
            UserAnnotation()
            ForEach(mapPlaceBoundaryLines) { line in
                switch line.style {
                case .fill:
                    MapPolygon(coordinates: line.points.map(\.coordinate))
                        .foregroundStyle(Color(hex: "F28C28").opacity(0.045 + 0.04 * areaHighlightOpacity))
                case .texture:
                    MapPolyline(coordinates: line.points.map(\.coordinate))
                        .stroke(Color(hex: "F28C28").opacity(0.10 + 0.12 * areaHighlightOpacity), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                case .outline:
                    MapPolyline(coordinates: line.points.map(\.coordinate))
                        .stroke(Color(hex: "F28C28").opacity(0.8 + 0.2 * areaHighlightOpacity), style: StrokeStyle(lineWidth: 3 + 1.2 * areaHighlightOpacity, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(pins.filter { effectiveCategories.contains($0.category) }) { pin in
                Annotation(pin.name, coordinate: pin.coordinate) { pinButton(pin) }
            }
            ForEach(cityPins) { pin in
                Annotation(pin.name, coordinate: pin.coordinate) {
                    Button { onCity(pin.name) } label: { cityTripPin(pin) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pin.name) · \(pin.badge ?? "") ταξίδια · Άνοιγμα στο Library")
                }
            }
            if let place = selectedSearchPlace, place.searchKind != .area {
                Annotation(place.name, coordinate: place.coordinate) { pinButton(place) }
            }
            ForEach(routes) { leg in
                if let route = renderedRoutes[routeKey(leg)] {
                    MapPolyline(route.polyline).stroke(routeColor(leg.day).opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if let directionsRoute {
                MapPolyline(directionsRoute.polyline)
                    .stroke(Color(hex: "F28C28"), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(mapStyle)
        .mapControls { MapCompass() }
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
            handleMapTap(at: tap.location, proxy: mapProxy)
        })
        .overlay(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.22))
                .mask(LinearGradient(stops: [
                    .init(color: .white.opacity(0.94), location: 0),
                    .init(color: .white.opacity(0.78), location: 0.3),
                    .init(color: .white.opacity(0.34), location: 0.72),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(height: 250).allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.white.opacity(0.48))
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.52), location: 0.32),
                    .init(color: .white.opacity(0.94), location: 0.7),
                    .init(color: .white, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .frame(height: 158)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            let nextRegion = context.region
            if visibleRegion == nil || cameraKey(for: nextRegion) != cameraKey(for: visibleRegion!) {
                visibleRegion = nextRegion
            }
        }
        .onChange(of: locationService.location?.timestamp) { _, _ in
            guard let location = locationService.location else { return }
            if centerWhenLocationArrives {
                centerWhenLocationArrives = false
                centerMap(on: location)
            }
            if let pin = pendingDirectionsPin {
                pendingDirectionsPin = nil
                Task { await calculateDirections(to: pin, from: location) }
            }
        }
        .onChange(of: locationService.failureMessage) { _, message in
            guard let message else { return }
            if pendingDirectionsPin != nil {
                pendingDirectionsPin = nil
                directionsError = message
            } else {
                centerWhenLocationArrives = false
                locationError = message
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .safeAreaInset(edge: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    searchBar
                    if !searchFocused { mapOptionsMenu }
                    if destination.isEmpty, let onNewTrip { newTripMapButton(action: onNewTrip) }
                }
                if !searchFocused && !destination.isEmpty { header() }
                if searching || !searchResults.isEmpty || searchError != nil { searchPanel }
            }.frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 8)
        }
        .sheet(isPresented: $showHomeFilters) { homeMapFilterSheet }
        .overlay(alignment: .bottomLeading) {
            if routing || failedRoutes > 0 {
                Label(routing ? "Ενημέρωση διαδρομών…" : "\(failedRoutes) διαδρομές δεν είναι διαθέσιμες", systemImage: routing ? "arrow.trianglehead.2.clockwise.rotate.90" : "exclamationmark.circle")
                    .font(.caption).padding(12).background(.regularMaterial, in: Capsule()).padding(16).padding(.trailing, 72)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !searchFocused {
                VStack(spacing: 12) {
                    Button(action: centerOnCurrentPosition) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(width: 50, height: 50)
                            .modifier(AdaptiveGlassControl(shape: .circle))
                    }
                    .buttonStyle(QuietPressStyle())
                    .accessibilityLabel("Κέντρο στην τρέχουσα θέση")
                    mapZoomControls
                }
                .padding(.trailing, 16)
                .padding(.bottom, 52)
            }
        }
        .task(id: routeTaskID) { await updateRoutes() }
        .onChange(of: pointTaskID, initial: true) { old, new in
            if !hasFittedMap && (!pins.isEmpty || !cityPins.isEmpty) { fitMap(); hasFittedMap = true }
        }
        .onChange(of: selectionKey) { _, _ in fitMap() }
        .onChange(of: focusPlaceID, initial: true) { _, id in
            if let pin = pins.first(where: { $0.id == id }) {
                position = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            }
        }
        .sheet(item: $selectedPin, onDismiss: {
            selectedSearchPlace = nil
            focusedMapPinID = nil
            mapPlaceBoundaryLines = []
            areaHighlightOpacity = 0
            googlePlaceDetails = nil
            resolvedGooglePlaceIDs = [:]
            googleDetailsError = nil
            query = ""
            searchResults = []
            if let pin = pendingPlanPin { pendingPlanPin = nil; onPlanPin?(pin) }
            if let action = pendingPlacePanelAction { pendingPlacePanelAction = nil; action() }
        }) { pin in selectedPlacePanel(pin) }
        .sheet(isPresented: $showDirections) {
            if let directionsRoute { RouteStepsSheet(route: directionsRoute) }
        }
        .alert("Δεν βρέθηκε διαδρομή", isPresented: Binding(
            get: { directionsError != nil },
            set: { if !$0 { directionsError = nil } }
        )) {
            Button("OK", role: .cancel) { directionsError = nil }
        } message: {
            Text(directionsError ?? "Δοκίμασε ξανά σε λίγο.")
        }
        .alert("Δεν είναι διαθέσιμη η τοποθεσία", isPresented: Binding(
            get: { locationError != nil },
            set: { if !$0 { locationError = nil } }
        )) {
            Button("Εντάξει", role: .cancel) { locationError = nil }
        } message: {
            Text(locationError ?? "Έλεγξε την πρόσβαση τοποθεσίας και δοκίμασε ξανά.")
        }
        }
    }
    func newTripMapButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppPalette.ink).frame(width: 48, height: 48)
                .modifier(AdaptiveGlassControl(shape: .circle))
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Νέο ταξίδι")
    }
    @ViewBuilder
    func cityTripPin(_ pin: WorkspaceMapPin) -> some View {
        let span = visibleRegion?.span.latitudeDelta ?? 0
        if span >= 0.08 {
            let iconSize: CGFloat = span >= 20 ? 9 : (span >= 8 ? 10 : (span >= 2 ? 11 : 12))
            HStack(spacing: 4) {
                Image(systemName: "suitcase.rolling.fill").font(.system(size: iconSize, weight: .semibold)).foregroundStyle(AppPalette.brand)
                if span < 2 {
                    Text(pin.badge ?? "0").font(.custom("PlusJakartaSans-Bold", size: 7))
                        .foregroundStyle(AppPalette.ink).padding(.horizontal, 4).background(AppPalette.accent.opacity(0.86), in: Capsule())
                }
            }
            .padding(.horizontal, span >= 8 ? 6 : 8).frame(minHeight: span >= 20 ? 28 : 32)
            .modifier(AdaptiveGlassControl(shape: .capsule))
            .overlay(Capsule().stroke(.white.opacity(0.84), lineWidth: 1))
            .shadow(color: AppPalette.ink.opacity(0.16), radius: 5, y: 2)
            .opacity(span >= 8 ? 0.78 : 1).frame(minWidth: 44, minHeight: 44).contentShape(Capsule())
        } else {
            HStack(spacing: 7) {
                Image(systemName: "suitcase.rolling.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.brand)
                Text(pin.name).font(.custom("PlusJakartaSans-Bold", size: 11)).lineLimit(1)
                Text("\(pin.badge ?? "0") TRIPS").font(.custom("PlusJakartaSans-Bold", size: 8)).tracking(0.35)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(AppPalette.accent, in: Capsule())
            }
            .padding(.horizontal, 11).padding(.vertical, 7).foregroundStyle(AppPalette.ink)
            .modifier(AdaptiveGlassControl(shape: .capsule))
            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: AppPalette.ink.opacity(0.15), radius: 5, y: 2)
        }
    }
    var mapZoomControls: some View {
        VStack(spacing: 0) {
            mapZoomDialButton("plus", title: "ZOOM IN") { adjustZoom(dividingBy: 2) }
            Rectangle().fill(AppPalette.secondaryInk.opacity(0.18)).frame(width: 34, height: 1)
            mapZoomDialButton("minus", title: "ZOOM OUT") { adjustZoom(dividingBy: 0.5) }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.82), lineWidth: 1))
        .overlay(alignment: .leading) {
            Capsule().fill(AppPalette.accent.opacity(0.9)).frame(width: 2, height: 38).padding(.leading, 3)
        }
        .shadow(color: AppPalette.ink.opacity(0.2), radius: 14, y: 6)
    }
    func mapZoomDialButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                Text(title).font(.custom("PlusJakartaSans-ExtraBold", size: 8)).tracking(0.65)
            }
            .foregroundStyle(AppPalette.ink)
            .frame(width: 66, height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityLabel(title == "ZOOM IN" ? "Μεγέθυνση" : "Σμίκρυνση")
    }
    func adjustZoom(dividingBy factor: Double) {
        let region = position.region ?? visibleRegion ?? .init(center: fallback ?? .init(latitude: 20, longitude: 0), span: .init(latitudeDelta: 60, longitudeDelta: 80))
        let latitude = min(150, max(0.001, region.span.latitudeDelta / factor))
        let longitude = min(150, max(0.001, region.span.longitudeDelta / factor))
        position = .region(.init(center: region.center, span: .init(latitudeDelta: latitude, longitudeDelta: longitude)))
    }
    var mapOptionsMenu: some View {
        Menu {
            Picker("Εμφάνιση χάρτη", selection: $theme) {
                Text("Explore").tag("Explore"); Text("Quiet").tag("Quiet")
                Text("Satellite").tag("Satellite"); Text("Hybrid").tag("Hybrid")
            }
            Picker("Απόχρωση Liquid Glass", selection: $glassTint) {
                Text("Αυτόματη").tag("auto")
                Text("Forest").tag("forest")
                Text("Κοραλί").tag("coral")
                Text("Μελί").tag("amber")
                Text("Φασκόμηλο").tag("sage")
            }
            Button(darkMode ? "Φωτεινή εμφάνιση" : "Σκούρα εμφάνιση", systemImage: darkMode ? "sun.max" : "moon") { darkMode.toggle() }
            Button("Google Places", systemImage: "magnifyingglass") { onPlacesSettings?() }
            if destination.isEmpty { Button("Ρυθμίσεις χάρτη", systemImage: "slider.horizontal.3") { showHomeFilters = true } }
            Button("Εμφάνιση όλων των σημείων", systemImage: "arrow.up.left.and.arrow.down.right") { fitMap() }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppPalette.ink).frame(width: 52, height: 52).modifier(AdaptiveGlassControl(shape: .circle))
        }.accessibilityLabel("Ρυθμίσεις χάρτη")
    }
    var homeMapFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Διάλεξε τι θα εμφανίζεται στον χάρτη.")
                        .font(.subheadline).foregroundStyle(AppPalette.secondaryInk)
                    PillFlowLayout(spacing: 9) {
                        ForEach(MapPlaceCategory.allCases) { category in
                            let selected = homeCategories.contains(category)
                            Button {
                                if selected { homeCategories.remove(category) } else { homeCategories.insert(category) }
                            } label: {
                                Label(category.rawValue, systemImage: category.symbol)
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                                    .padding(.horizontal, 13).padding(.vertical, 10)
                                    .foregroundStyle(selected ? AppPalette.inverseInk : AppPalette.ink)
                                    .background(selected ? AppPalette.brand : AppPalette.surface, in: Capsule())
                                    .overlay(Capsule().stroke(selected ? AppPalette.brand : AppPalette.ink.opacity(0.09), lineWidth: 1))
                            }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    Button("Εμφάνιση όλων των κατηγοριών", systemImage: "checkmark.circle") {
                        homeCategories = Set(MapPlaceCategory.allCases)
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.brand)
                }.padding(20)
            }
            .background(AppPalette.canvas)
            .navigationTitle("Ρυθμίσεις χάρτη").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { showHomeFilters = false }.tint(AppPalette.brand) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    func pinButton(_ pin: WorkspaceMapPin) -> some View {
        let span = visibleRegion?.span.latitudeDelta ?? 0
        let showsName = span < 1.5
        let iconColor = pin.layer == "recommended" ? Color(hex: "CE6651") : pin.category.tint
        return Button { focusPin(pin) } label: {
            if pin.layer == "search" {
                SearchMapPinView(category: pin.category)
            } else {
            HStack(spacing: 7) {
                Image(systemName: pin.layer == "saved" ? "bookmark.fill" : pin.category.symbol)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(iconColor)
                if showsName {
                    Text(pin.name).font(.custom("PlusJakartaSans-SemiBold", size: 11)).lineLimit(1)
                        .frame(maxWidth: 190, alignment: .leading)
                }
                if let badge = pin.badge, showsName {
                    Text(badge).font(.custom("PlusJakartaSans-Bold", size: 8)).foregroundStyle(AppPalette.ink)
                        .padding(.horizontal, 6).frame(minHeight: 16).background(AppPalette.surface, in: Capsule())
                }
            }
            .foregroundStyle(AppPalette.ink).padding(.horizontal, showsName ? 11 : 13).frame(minHeight: 42)
            .modifier(AdaptiveGlassControl(shape: .capsule))
            .overlay(Capsule().stroke(.white.opacity(0.82), lineWidth: 1))
            .shadow(color: AppPalette.ink.opacity(0.17), radius: 6, y: 2)
            }
        }.buttonStyle(QuietPressStyle())
            .overlay {
                if focusedMapPinID == pin.id {
                    Circle().stroke(AppPalette.brand, lineWidth: 2).padding(-5)
                        .shadow(color: AppPalette.brand.opacity(0.4), radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("\(pin.name) · \(pin.category.rawValue)")
    }
    var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(destination.isEmpty ? "Αναζήτηση μέρους" : "Αναζήτηση στο \(destination)", text: $query)
                .font(.subheadline).focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty || searchFocused {
                Button {
                    query = ""; searchResults = []; searchError = nil; searchSourceNotice = nil; searchFocused = false
                    if selectedSearchPlace != nil { selectedPin = nil }
                } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel("Καθαρισμός αναζήτησης")
            }
        }.padding(.leading, 18).padding(.trailing, 8).frame(minHeight: 52)
            .modifier(AdaptiveGlassControl(shape: .capsule))
            .task(id: query) { await searchPlaces() }
    }
    var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let searchSourceNotice {
                HStack(spacing: 7) {
                    if searchSourceNotice.hasPrefix("Google Places") { GooglePlacesGlyph() }
                    else { Image(systemName: "apple.logo").font(.caption.weight(.bold)).foregroundStyle(AppPalette.secondaryInk) }
                    Text(searchSourceNotice).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppPalette.secondaryInk)
                    Spacer()
                }.padding(.horizontal, 14).padding(.top, 12)
            }
            if searching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(AppPalette.brand)
                    Text("Αναζήτηση σε Google Places και Apple Maps…")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(AppPalette.secondaryInk)
                }.padding(.horizontal, 14).padding(.top, 12)
            }
            if searchResults.isEmpty, let error = searchError, !searching {
                Text(error).font(.caption).padding(16)
            } else if !searchResults.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(MapSearchFilter.allCases) { filter in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { searchFilter = filter }
                            } label: {
                                Text(filter.title).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(searchFilter == filter ? AppPalette.inverseInk : AppPalette.ink)
                                    .padding(.horizontal, 12).frame(height: 31)
                                    .background(searchFilter == filter ? AppPalette.brand : AppPalette.surface.opacity(0.82), in: Capsule())
                                    .overlay(Capsule().stroke(AppPalette.ink.opacity(searchFilter == filter ? 0 : 0.08), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12).padding(.top, 11)
                }.scrollIndicators(.hidden)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(displayedSearchResults) { place in
                            Button { selectSearchResult(place) } label: {
                                HStack(spacing: 13) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14).fill(place.searchKind == .area ? AppPalette.accent.opacity(0.42) : place.category.tint.opacity(0.14))
                                        Image(systemName: place.searchKind == .area ? "map.fill" : place.category.symbol)
                                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(place.searchKind == .area ? AppPalette.brand : place.category.tint)
                                    }.frame(width: 42, height: 42)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                                        Text(place.address.isEmpty ? place.city : place.address).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Text(place.searchKind == .area ? geographicScopeLabel(place.boundaryLevel) : place.category.rawValue)
                                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(AppPalette.secondaryInk)
                                        .padding(.horizontal, 8).padding(.vertical, 5).background(AppPalette.surface, in: Capsule())
                                }.padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 60)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }.buttonStyle(QuietPressStyle())
                        }
                        if displayedSearchResults.isEmpty, !searching {
                            Text("Δεν βρέθηκαν επιλογές σε αυτή την κατηγορία.").font(.caption).foregroundStyle(AppPalette.secondaryInk).padding(16)
                        }
                    }
                }.frame(maxHeight: 250)
                if searchSourceNotice?.hasPrefix("Google Places") == true, !searchResults.isEmpty {
                    Text("Google Places και Apple Maps · επίλεξε ένα αποτέλεσμα για εστίαση στον χάρτη.")
                        .font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                        .padding(.horizontal, 14).padding(.bottom, 11).padding(.top, 4)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1))
            .shadow(color: AppPalette.ink.opacity(0.12), radius: 18, y: 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
    func searchPlaces() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchError = nil
        guard text.count >= 2 else {
            searching = false; searchResults = []; searchSourceNotice = nil; searchFilter = .all
            return
        }
        searching = true; searchResults = []; searchSourceNotice = nil
        searchFilter = .all
        do {
            try await Task.sleep(for: .milliseconds(160))
            try Task.checkCancellation()
            let googleTask = Task { try? await searchGooglePlaces(text) }
            let appleTask = Task { try? await searchApplePlaces(text) }
            defer { googleTask.cancel(); appleTask.cancel() }
            let appleResults = await withTaskCancellationHandler {
                await appleTask.value ?? []
            } onCancel: {
                googleTask.cancel(); appleTask.cancel()
            }
            try Task.checkCancellation()
            searchResults = rankedUniqueSearchResults(appleResults, query: text)
            if !appleResults.isEmpty { searchSourceNotice = "Apple Maps · εμφανίζονται και τα Google Places αποτελέσματα" }

            let googleResults = await googleTask.value ?? []
            try Task.checkCancellation()
            searchResults = rankedUniqueSearchResults(googleResults + appleResults, query: text)
            searching = false
            if !googleResults.isEmpty {
                searchSourceNotice = "Google Places + Apple Maps · ζωντανά αποτελέσματα"
            } else if placesAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchSourceNotice = "Apple Maps · πρόσθεσε το Trippy bridge token στις ρυθμίσεις Google Places"
            } else if !appleResults.isEmpty {
                searchSourceNotice = "Apple Maps · το Google Places δεν επέστρεψε αποτελέσματα"
            } else {
                searchSourceNotice = "Google Places + Apple Maps"
            }
            if searchResults.isEmpty { searchError = "Δεν βρέθηκαν αποτελέσματα. Δοκίμασε όνομα πόλης, γειτονιάς ή μέρους." }
        } catch {
            guard !Task.isCancelled else { return }
            searching = false
            searchError = "Η αναζήτηση δεν είναι διαθέσιμη αυτή τη στιγμή. Δοκίμασε ξανά."
        }
    }
    private func searchApplePlaces(_ text: String) async throws -> [PersonalPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination.isEmpty ? text : "\(text), \(destination)"
        if let region = visibleRegion { request.region = region }
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
        return response.mapItems.prefix(12).compactMap { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let name = item.name ?? text
            let placemark = item.placemark
            let normalizedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let areaNames = [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea, placemark.country]
                .compactMap { $0?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            let isArea = item.pointOfInterestCategory == nil && areaNames.contains(normalizedName)
            let kind: SearchPlaceKind = isArea ? .area : (item.pointOfInterestCategory == nil ? .attraction : .place)
            return PersonalPlace(id: "apple:\(name.lowercased()):\(coordinate.latitude):\(coordinate.longitude)", name: name,
                                 city: placemark.locality ?? destination, address: placemark.title ?? name,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude,
                                 category: .classify(item.pointOfInterestCategory?.rawValue ?? name),
                                 searchKind: kind, boundaryCountryCode: placemark.isoCountryCode,
                                 searchLatitudeSpan: response.boundingRegion.span.latitudeDelta,
                                 searchLongitudeSpan: response.boundingRegion.span.longitudeDelta,
                                 boundaryLevel: boundaryLevel(for: placemark, title: name),
                                 phoneNumber: item.phoneNumber, websiteURL: item.url?.absoluteString)
        }
    }
    private func boundaryLevel(for placemark: MKPlacemark, title: String) -> String? {
        let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        func matches(_ value: String?) -> Bool {
            value?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalizedTitle
        }
        if matches(placemark.country) { return "country" }
        if matches(placemark.administrativeArea) { return "region" }
        if matches(placemark.subAdministrativeArea) { return "district" }
        if matches(placemark.locality) { return "city" }
        return nil
    }
    private func rankedUniqueSearchResults(_ candidates: [PersonalPlace], query: String) -> [PersonalPlace] {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var unique: [PersonalPlace] = []
        for place in candidates {
            let duplicate = unique.contains { existing in
                if existing.googlePlaceID != nil, existing.googlePlaceID == place.googlePlaceID { return true }
                if existing.searchKind == .area, place.searchKind == .area,
                   existing.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame { return true }
                let meters = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                return meters < 140 && existing.name.localizedCaseInsensitiveCompare(place.name) == .orderedSame
            }
            if !duplicate { unique.append(place) }
            if unique.count == 24 { break }
        }
        return unique.sorted { lhs, rhs in
            func score(_ place: PersonalPlace) -> Int {
                let name = place.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if name == normalizedQuery { return place.searchKind == .area ? 100 : 90 }
                if place.searchKind == .area && name.hasPrefix(normalizedQuery) { return 80 }
                if name.hasPrefix(normalizedQuery) { return 70 }
                return 50
            }
            return score(lhs) > score(rhs)
        }
    }
    private func searchGooglePlaces(_ text: String) async throws -> [PersonalPlace] {
        guard !placesAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard var components = URLComponents(string: placesBaseURL + "/api/places/search") else { throw URLError(.badURL) }
        let queryText = destination.isEmpty ? text : "\(text), \(destination)"
        components.queryItems = [URLQueryItem(name: "q", value: queryText),
                                 URLQueryItem(name: "lang", value: googlePlacesLanguage(for: text))]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(placesAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(GooglePlaceSearchResponse.self, from: data)
        return payload.places.map { place in
            let type = place.primaryType.lowercased()
            let knownTypes = place.types ?? []
            let areaTypes = ["locality", "country", "administrative_area_level_1", "administrative_area_level_2", "postal_town", "neighborhood", "sublocality"]
            let sameAsCity = place.city?.localizedCaseInsensitiveCompare(place.name) == .orderedSame
            let area = place.isArea == true || sameAsCity
                || knownTypes.contains(where: { candidate in areaTypes.contains(where: candidate.contains) })
                || areaTypes.contains(where: type.contains)
            let boundaryLevel = place.boundaryLevel ?? {
                if knownTypes.contains("country") { return "country" }
                if knownTypes.contains("administrative_area_level_1") { return "region" }
                if knownTypes.contains("administrative_area_level_2") { return "district" }
                if knownTypes.contains(where: { ["neighborhood", "sublocality"].contains($0) }) { return "area" }
                return area ? "city" : nil
            }()
            let category = MapPlaceCategory.classify(place.primaryType)
            let kind: SearchPlaceKind = area ? .area : (category == .sights ? .attraction : .place)
            return PersonalPlace(id: "google:\(place.placeID)", name: place.name, city: place.city ?? destination,
                                address: place.address, latitude: place.latitude, longitude: place.longitude,
                                category: category, searchKind: kind, boundaryCountryCode: place.countryCode,
                                searchLatitudeSpan: area ? (place.latitudeSpan ?? 1.2) : nil,
                                searchLongitudeSpan: area ? (place.longitudeSpan ?? 1.2) : nil,
                                boundaryLevel: boundaryLevel,
                                searchTypes: knownTypes, googlePlaceID: place.placeID)
        }
    }
    private func googlePlacesLanguage(for text: String) -> String {
        let containsGreek = text.unicodeScalars.contains { scalar in
            (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
        }
        return containsGreek ? "el" : "en"
    }
    private func geographicScopeLabel(_ level: String?) -> String {
        switch level {
        case "country": "Χώρα"
        case "region": "Περιφέρεια"
        case "district", "area": "Περιοχή"
        default: "Πόλη"
        }
    }
    private func selectSearchResult(_ result: PersonalPlace) {
        let place = result
        let pin = WorkspaceMapPin(id: place.id, name: place.name, coordinate: place.coordinate, layer: "search",
                                  category: place.category, city: place.city, address: place.address,
                                  searchKind: place.searchKind ?? .place, boundaryCountryCode: place.boundaryCountryCode,
                                  searchLatitudeSpan: place.searchLatitudeSpan, searchLongitudeSpan: place.searchLongitudeSpan,
                                  boundaryLevel: place.boundaryLevel,
                                  phoneNumber: place.phoneNumber, websiteURL: place.websiteURL, googlePlaceID: place.googlePlaceID)
        presentPlace(pin)
    }
    private func presentPlace(_ pin: WorkspaceMapPin) {
        query = ""
        searchResults = []
        searchFocused = false
        searchSourceNotice = nil
        focusedMapPinID = pin.id
        selectedSearchPlace = pin.layer == "search" && pin.searchKind != .area ? pin : nil
        selectedPinCategory = nil
        googlePlaceDetails = nil
        googleDetailsError = nil
        let latitudeSpan = pin.searchKind == .area ? max(0.08, min(16, (pin.searchLatitudeSpan ?? 0.5) * 1.28)) : 0.012
        let longitudeSpan = pin.searchKind == .area ? max(0.08, min(16, (pin.searchLongitudeSpan ?? 0.5) * 1.28)) : 0.012
        let region = MKCoordinateRegion(center: pin.coordinate, span: .init(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
        withAnimation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.86)) {
            if pin.searchKind == .attraction {
                position = .camera(MapCamera(centerCoordinate: pin.coordinate, distance: 820, heading: 0, pitch: 58))
            } else if pin.searchKind == .place {
                position = .camera(MapCamera(centerCoordinate: pin.coordinate, distance: 520, heading: 0, pitch: 34))
            } else { position = .region(region) }
        }
        selectedPin = pin
        guard pin.searchKind == .area else { mapPlaceBoundaryLines = []; areaHighlightOpacity = 0; return }
        Task {
            let lines = try? await GeoBoundaryRepository.shared.boundary(
                countryISO2: pin.boundaryCountryCode,
                countryNames: [pin.address, pin.city].filter { !$0.isEmpty },
                placeNames: [pin.name], levelID: pin.boundaryLevel ?? "city",
                center: GeoBoundaryPoint(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
            guard !Task.isCancelled, focusedMapPinID == pin.id else { return }
            withAnimation(.easeInOut(duration: 0.35)) { mapPlaceBoundaryLines = lines ?? []; areaHighlightOpacity = 0 }
            guard lines != nil else { return }
            for _ in 0..<2 {
                withAnimation(.easeOut(duration: 0.24)) { areaHighlightOpacity = 1 }
                try? await Task.sleep(for: .milliseconds(360))
                withAnimation(.easeInOut(duration: 0.32)) { areaHighlightOpacity = 0.12 }
                try? await Task.sleep(for: .milliseconds(180))
            }
            withAnimation(.easeOut(duration: 0.35)) { areaHighlightOpacity = 0 }
        }
    }
    private func focusPin(_ pin: WorkspaceMapPin) {
        presentPlace(pin)
    }
    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard selectedPin != nil else { return }
        let selectablePins = pins + cityPins + (selectedSearchPlace.map { [$0] } ?? [])
        let touchedPin = selectablePins.contains { pin in
            guard let anchor = proxy.convert(pin.coordinate, to: .local) else { return false }
            return hypot(anchor.x - point.x, anchor.y - point.y) < 125
        }
        guard !touchedPin else { return }
        selectedPin = nil
    }
    func selectedPlacePanel(_ pin: WorkspaceMapPin) -> some View {
        let saved = savedPlaces.contains { samePlace($0, pin) }
        let category = selectedPinCategory ?? pin.category
        let mentions = relatedTikTokMentions(for: pin)
        let linkedSources = socialSources.filter { source in
            mentions.contains(where: { $0.sourceID == source.id })
        }
        let linkedNotes = travelNotes.filter { note in
            mentions.contains(where: { $0.noteID == note.id || note.sourceIDs.contains($0.sourceID) })
                || (note.linkedPlaceIDs ?? []).contains(pin.id)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(googlePlaceDetails?.name.nonEmpty ?? pin.name).font(.custom("PlusJakartaSans-ExtraBold", size: 26)).tracking(-0.6)
                            .foregroundStyle(AppPalette.ink).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 7) {
                            Image(systemName: pin.searchKind == .area ? "map.fill" : category.symbol)
                                .foregroundStyle(pin.searchKind == .area ? AppPalette.brand : category.tint)
                            Text(pin.searchKind == .area ? geographicScopeLabel(pin.boundaryLevel) : (googlePlaceDetails?.primaryType.nonEmpty ?? category.rawValue))
                            if pin.searchKind == .area, let count = cityTripCount(for: pin), count > 0 {
                                Text("\(count) trips").font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(AppPalette.accent.opacity(0.35), in: Capsule())
                            }
                        }.font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
                    }
                    Spacer(minLength: 2)
                    Button { selectedPin = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle()).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Κλείσιμο μέρους")
                }

                if let googlePlaceDetails {
                    VStack(alignment: .leading, spacing: 14) {
                    if !googlePlaceDetails.photos.isEmpty {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 11) {
                                ForEach(googlePlaceDetails.photos) { photo in
                                    GooglePlacePhotoCard(photo: photo, baseURL: placesBaseURL, accessToken: placesAccessToken)
                                }
                            }
                        }.scrollIndicators(.hidden).contentMargins(.trailing, 2)
                    } else {
                        Label("Δεν υπάρχουν διαθέσιμες φωτογραφίες για αυτό το μέρος.", systemImage: "photo")
                            .font(.caption).foregroundStyle(AppPalette.secondaryInk)
                    }
                    GooglePlacesBrandLink(url: googlePlaceDetails.googleMapsURL.flatMap(URL.init(string:)))
                    if let rating = googlePlaceDetails.rating {
                        HStack(spacing: 7) {
                            Image(systemName: "star.fill").foregroundStyle(Color(hex: "E5A52B"))
                            Text(String(format: "%.1f", rating)).font(.headline)
                            if let count = googlePlaceDetails.reviewCount { Text("(\(count.formatted()) κριτικές)").font(.subheadline).foregroundStyle(AppPalette.secondaryInk) }
                            Spacer()
                            if let open = googlePlaceDetails.openNow {
                                Label(open ? "Ανοιχτό τώρα" : "Κλειστό τώρα", systemImage: "circle.fill")
                                    .font(.caption.weight(.bold)).foregroundStyle(open ? Color(hex: "448568") : Color(hex: "B85C52"))
                            }
                        }
                    }
                    if let summary = googlePlaceDetails.summary.nonEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                    if !googlePlaceDetails.openingHours.isEmpty {
                        DisclosureGroup("Ώρες λειτουργίας") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(googlePlaceDetails.openingHours.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                }
                            }.padding(.top, 8)
                        }.font(.subheadline.weight(.semibold)).tint(AppPalette.brand)
                    }
                    if !googlePlaceDetails.reviews.isEmpty {
                        DisclosureGroup("Κριτικές · \(googlePlaceDetails.reviews.count)") {
                            VStack(alignment: .leading, spacing: 11) {
                            Text("Google Maps").font(.caption2.weight(.medium)).foregroundStyle(AppPalette.secondaryInk)
                            ForEach(googlePlaceDetails.reviews) { review in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 9) {
                                        if let avatarURL = review.authorPhotoURL.flatMap(URL.init(string:)) {
                                            GoogleAuthorAvatar(url: avatarURL)
                                        }
                                        if let profile = review.authorURL.flatMap(URL.init(string:)) {
                                            Link(review.authorName, destination: profile).font(.caption.weight(.bold))
                                        } else { Text(review.authorName).font(.caption.weight(.bold)) }
                                        Spacer()
                                        if let rating = review.rating {
                                            HStack(spacing: 2) { ForEach(0..<5, id: \.self) { index in Image(systemName: Double(index) < rating.rounded() ? "star.fill" : "star").foregroundStyle(Color(hex: "E5A52B")) } }
                                                .font(.system(size: 9))
                                        }
                                        Text(review.relativeTime).font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                                    }
                                    if let text = review.text.nonEmpty { Text(text).font(.caption).foregroundStyle(AppPalette.ink).lineLimit(4) }
                                    if let visitDate = review.visitDate, let year = visitDate.year, let month = visitDate.month {
                                        Text("Επίσκεψη: \(String(format: "%02d/%04d", month, year))")
                                            .font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                                    }
                                    if let sourceURL = review.googleMapsURL.flatMap(URL.init(string:)) {
                                        Link("Προβολή κριτικής στο Google Maps", destination: sourceURL)
                                            .font(.caption2.weight(.semibold)).foregroundStyle(AppPalette.brand)
                                    }
                                }
                                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }
                            }
                        }.font(.subheadline.weight(.semibold)).tint(AppPalette.brand)
                    }
                    if let phone = googlePlaceDetails.phoneNumber,
                       let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label(phone, systemImage: "phone.fill").font(.caption.weight(.semibold)) }.foregroundStyle(AppPalette.secondaryInk)
                    }
                    if let rawURL = googlePlaceDetails.websiteURL, let url = URL(string: rawURL) {
                        Link(destination: url) { Label("Ιστότοπος", systemImage: "globe").font(.caption.weight(.semibold)) }.foregroundStyle(AppPalette.secondaryInk)
                    }
                    }
                    .padding(15)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1))
                } else if loadingGoogleDetails {
                    HStack(spacing: 9) { ProgressView(); Text("Φορτώνω φωτογραφίες και πληροφορίες…").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                } else if let googleDetailsError {
                    Text(googleDetailsError).font(.caption).foregroundStyle(AppPalette.secondaryInk)
                }
                if googlePlaceDetails == nil {
                    if let phone = pin.phoneNumber,
                       let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label(phone, systemImage: "phone.fill").font(.caption.weight(.semibold)) }
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    if let rawURL = pin.websiteURL, let url = URL(string: rawURL) {
                        Link(destination: url) { Label("Ιστότοπος", systemImage: "globe").font(.caption.weight(.semibold)) }
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
                if !pin.address.isEmpty { Label(pin.address, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(AppPalette.secondaryInk) }

                if !mentions.isEmpty || !linkedSources.isEmpty || !linkedNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note").foregroundStyle(AppPalette.brand)
                            Text("TikTok notes").font(.custom("PlusJakartaSans-Bold", size: 17)).foregroundStyle(AppPalette.ink)
                            Spacer()
                            Text("\(max(linkedSources.count, mentions.count)) saves").font(.caption2.weight(.bold))
                                .padding(.horizontal, 9).padding(.vertical, 6).background(AppPalette.brand.opacity(0.11), in: Capsule())
                        }
                        if !mentions.isEmpty {
                            ForEach(mentions) { mention in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "mappin.circle.fill").foregroundStyle(category.tint)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(mention.name).font(.subheadline.weight(.bold)).foregroundStyle(AppPalette.ink)
                                            if let summary = mention.summary.nonEmpty { Text(summary).font(.caption).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true) }
                                        }
                                    }
                                    if let note = linkedNotes.first(where: { $0.id == mention.noteID || $0.sourceIDs.contains(mention.sourceID) }),
                                       let noteText = note.userText.nonEmpty {
                                        Text(noteText).font(.caption).foregroundStyle(AppPalette.ink).padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    if let source = socialSources.first(where: { $0.id == mention.sourceID }),
                                       let link = source.envelope.sourceURL.flatMap(URL.init(string:)) {
                                        Link(destination: link) {
                                            Label(source.listTitle ?? source.displayTitle ?? "Open TikTok", systemImage: "play.rectangle.fill")
                                                .font(.caption.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 13).frame(height: 38)
                                                .background(Color(hex: "272725"), in: Capsule())
                                        }
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                            }
                        }
                        if mentions.isEmpty {
                            ForEach(linkedNotes) { note in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.title).font(.caption.weight(.bold)).foregroundStyle(AppPalette.ink)
                                    Text(note.userText.nonEmpty ?? "Saved note").font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(4)
                                }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TikTok notes").font(.custom("PlusJakartaSans-Bold", size: 17)).foregroundStyle(AppPalette.ink)
                        Text("Τα σχετικά TikTok saves και οι σημειώσεις τους θα εμφανιστούν εδώ.")
                            .font(.caption).foregroundStyle(AppPalette.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                if onPlanPin != nil && (pin.layer == "planned" || pin.layer == "recommended") {
                    Button { pendingPlanPin = pin; selectedPin = nil } label: {
                        Label("Προσθήκη στο πρόγραμμα", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 46)
                            .foregroundStyle(AppPalette.ink).background(AppPalette.surface, in: Capsule())
                    }.buttonStyle(QuietPressStyle())
                }
            }
            .padding(20)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            placeActionBar(pin, category: category, saved: saved)
        }
        .presentationDetents([.height(pin.searchKind == .area ? 250 : 500), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(500)))
        .overlay(alignment: .top) {
            if let emoji = celebrationEmoji { PinCelebrationView(emoji: emoji).padding(.top, 2).transition(.scale(scale: 0.2).combined(with: .opacity)).allowsHitTesting(false) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: celebrationEmoji)
        .task(id: pin.id) { await loadGoogleDetails(for: pin) }
    }
    @ViewBuilder
    private func placeActionBar(_ pin: WorkspaceMapPin, category: MapPlaceCategory, saved: Bool) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                if pin.searchKind != .area {
                    Menu {
                    ForEach(MapPlaceCategory.allCases) { item in
                        Button {
                            selectedPinCategory = item
                            if let index = savedPlaces.firstIndex(where: { samePlace($0, pin) }) {
                                savedPlaces[index].category = item
                            } else {
                                savedPlaces.append(enrichedPlace(for: pin, category: item))
                                celebrate(item)
                            }
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .foregroundStyle(item.tint)
                        }
                    }
                    if saved {
                        Button("Αφαίρεση pin", systemImage: "bookmark.slash", role: .destructive) {
                            savedPlaces.removeAll { samePlace($0, pin) }
                        }
                    }
                } label: {
                    Label(saved ? "Pinned" : "Pin", systemImage: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(AppPalette.inverseInk).background(AppPalette.brand, in: Capsule())
                    }.buttonStyle(QuietPressStyle()).accessibilityLabel("Pin · επιλογή κατηγορίας")
                }

                if let onSaveTripPin {
                    Menu {
                        if tripChoices.isEmpty { Button("Δημιουργία νέου Trip", systemImage: "plus") { onNewTrip?() } }
                        else {
                            ForEach(tripChoices) { trip in
                                Button(trip.title, systemImage: "suitcase.rolling") {
                                    onSaveTripPin(trip.id, enrichedPlace(for: pin, category: category)); celebrate(category)
                                }
                            }
                            if let onNewTrip { Button("Δημιουργία νέου Trip", systemImage: "plus") { onNewTrip() } }
                        }
                    } label: {
                        Label("Save to Trip", systemImage: "suitcase.rolling")
                            .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 46).modifier(AdaptiveGlassControl(shape: .capsule))
                    }.buttonStyle(QuietPressStyle())
                }

                if pin.searchKind != .area {
                    Button { beginDirections(to: pin) } label: {
                    Label(calculatingDirections ? "Loading…" : "Directions", systemImage: "figure.walk")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 46).modifier(AdaptiveGlassControl(shape: .capsule))
                    }.buttonStyle(QuietPressStyle()).disabled(calculatingDirections)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    if let onAddToNote, !noteChoices.isEmpty {
                        Menu("Προσθήκη σε Note", systemImage: "text.badge.plus") {
                            ForEach(noteChoices) { note in
                                Button(note.tripID == nil ? note.title : "\(note.title) · Trip") {
                                    let place = enrichedPlace(for: pin, category: category)
                                    dismissPlacePanel(then: { onAddToNote(place, note.id) })
                                }
                            }
                        }
                    }
                    Button("Νέα global σημείωση", systemImage: "note.text.badge.plus") {
                        let place = enrichedPlace(for: pin, category: category)
                        dismissPlacePanel(then: { onCreateNote?(place, nil) })
                    }
                    if !tripChoices.isEmpty {
                        Menu("Νέα σημείωση για Trip", systemImage: "suitcase") {
                            ForEach(tripChoices) { trip in
                                Button(trip.title) {
                                    let place = enrichedPlace(for: pin, category: category)
                                    dismissPlacePanel(then: { onCreateNote?(place, trip.id) })
                                }
                            }
                        }
                    }
                } label: {
                    Label("Note", systemImage: "note.text")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 44)
                        .modifier(AdaptiveGlassControl(shape: .capsule))
                }.buttonStyle(QuietPressStyle())
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                    item.name = pin.name
                    item.openInMaps()
                } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 44).modifier(AdaptiveGlassControl(shape: .capsule))
                }.buttonStyle(QuietPressStyle()).accessibilityLabel("Άνοιγμα στους Χάρτες Apple")
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.65)).frame(height: 1) }
    }
    private func dismissPlacePanel(then action: @escaping () -> Void) {
        pendingPlacePanelAction = action
        selectedPin = nil
    }
    private func enrichedPlace(for pin: WorkspaceMapPin, category: MapPlaceCategory) -> PersonalPlace {
        var place = pin.personalPlace
        place.category = category
        place.googlePlaceID = pin.googlePlaceID ?? resolvedGooglePlaceIDs[pin.id]
        return place
    }
    private func relatedTikTokMentions(for pin: WorkspaceMapPin) -> [SocialPlaceMention] {
        let target = pin.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return socialPlaces.filter { mention in
            let candidate = mention.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if pin.searchKind == .area,
               [pin.name, pin.city].contains(where: { !$0.isEmpty && mention.city?.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                return true
            }
            if target == candidate { return true }
            if let latitude = mention.latitude, let longitude = mention.longitude {
                let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                if distance <= 180 { return true }
            }
            return !(pin.city.isEmpty || mention.city == nil) && mention.city!.localizedCaseInsensitiveCompare(pin.city) == .orderedSame
                && candidate.localizedCaseInsensitiveContains(target)
        }
    }
    private func loadGoogleDetails(for pin: WorkspaceMapPin) async {
        googlePlaceDetails = nil
        googleDetailsError = nil
        guard !placesAccessToken.isEmpty else {
            googleDetailsError = "Σύνδεσε το Trippy Places gateway για φωτογραφίες, reviews και ωράρια Google."
            return
        }
        loadingGoogleDetails = true
        defer { loadingGoogleDetails = false }
        var placeID = pin.googlePlaceID ?? resolvedGooglePlaceIDs[pin.id]
        if placeID == nil {
            let query = [pin.name, pin.address, pin.city].filter { !$0.isEmpty }.joined(separator: ", ")
            guard let candidates = try? await searchGooglePlaces(query), !Task.isCancelled else {
                googleDetailsError = "Δεν βρέθηκαν στοιχεία Google Places για αυτό το σημείο."
                return
            }
            let origin = pin.coordinate
            let closest = candidates.min { first, second in
                CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
                    < CLLocation(latitude: second.latitude, longitude: second.longitude).distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
            }
            guard let closest,
                  CLLocation(latitude: closest.latitude, longitude: closest.longitude).distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude)) < 900 else {
                googleDetailsError = "Δεν βρέθηκαν στοιχεία Google Places αρκετά κοντά σε αυτό το pin."
                return
            }
            guard let closestPlaceID = closest.googlePlaceID else { return }
            placeID = closestPlaceID
            guard selectedPin?.id == pin.id, !Task.isCancelled else { return }
            resolvedGooglePlaceIDs[pin.id] = closestPlaceID
        }
        guard let placeID else { return }
        guard var components = URLComponents(string: placesBaseURL + "/api/places/details") else { return }
        components.queryItems = [URLQueryItem(name: "place_id", value: placeID)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(placesAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, selectedPin?.id == pin.id else { return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let failure = try? JSONDecoder().decode(GooglePlacesRequestError.self, from: data)
                let reason = failure?.message ?? failure?.errorCode ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                googleDetailsError = "Google Places: \(reason)"; return
            }
            googlePlaceDetails = try JSONDecoder().decode(GooglePlaceDetails.self, from: data)
        } catch {
            guard !Task.isCancelled else { return }
            googleDetailsError = "Δεν ήταν δυνατή η φόρτωση πληροφοριών Google Places."
        }
    }
    private func cityTripCount(for pin: WorkspaceMapPin) -> Int? {
        let names = [pin.name, pin.city]
        let count = cityPins.filter { candidate in names.contains { $0.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame } }
            .compactMap { Int($0.badge ?? "0") }.reduce(0, +)
        return count == 0 ? nil : count
    }
    private func celebrate(_ category: MapPlaceCategory) {
        let generator = UINotificationFeedbackGenerator(); generator.notificationOccurred(.success)
        let symbols: [MapPlaceCategory: String] = [.restaurants: "🍜", .streetFood: "🌮", .burgers: "🍔", .seafood: "🦐", .vegan: "🥑", .coffee: "☕️", .brunch: "🥐", .bars: "🍸", .clubs: "🎶", .parks: "🌿", .sights: "✨", .shopping: "🛍️", .touristShops: "🎁", .groceries: "🧺", .metro: "🚇", .other: "📍"]
        withAnimation { celebrationEmoji = symbols[category] ?? "✨" }
        Task { try? await Task.sleep(for: .milliseconds(850)); withAnimation { celebrationEmoji = nil } }
    }
    func samePlace(_ place: PersonalPlace, _ pin: WorkspaceMapPin) -> Bool {
        if place.id == pin.id { return true }
        let distance = CLLocation(latitude: place.latitude, longitude: place.longitude).distance(from: CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
        return distance < 30 && place.name.localizedCaseInsensitiveCompare(pin.name) == .orderedSame
    }
    func fitMap() {
        let coordinates = (pins.filter { effectiveCategories.contains($0.category) } + cityPins).map(\.coordinate)
        if coordinates.isEmpty {
            if let fallback { position = .region(.init(center: fallback, span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08))) }
            else { position = .automatic }
            return
        }
        let latitudes = coordinates.map(\.latitude), longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!, minLon = longitudes.min()!, maxLon = longitudes.max()!
        position = .region(.init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                span: .init(latitudeDelta: max(0.015, (maxLat - minLat) * 1.8), longitudeDelta: max(0.015, (maxLon - minLon) * 1.5))))
    }
    private func centerOnCurrentPosition() {
        if let location = locationService.location, Date().timeIntervalSince(location.timestamp) < 120 {
            centerMap(on: location)
        } else {
            centerWhenLocationArrives = true
            locationService.requestCurrentLocation()
        }
    }
    private func centerMap(on location: CLLocation) {
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(.init(center: location.coordinate,
                                     span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))
        }
    }
    private func beginDirections(to pin: WorkspaceMapPin) {
        pendingDirectionsPin = pin
        if let location = locationService.location, Date().timeIntervalSince(location.timestamp) < 120 {
            pendingDirectionsPin = nil
            Task { await calculateDirections(to: pin, from: location) }
        } else {
            locationService.requestCurrentLocation()
        }
    }
    private func calculateDirections(to pin: WorkspaceMapPin, from origin: CLLocation) async {
        calculatingDirections = true
        defer { calculatingDirections = false }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
        destinationItem.name = pin.name
        request.destination = destinationItem
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                directionsError = "Δεν βρέθηκε διαθέσιμη πεζή διαδρομή προς \(pin.name)."
                return
            }
            directionsRoute = route
            withAnimation(.easeInOut(duration: 0.45)) {
                position = .rect(route.polyline.boundingMapRect)
            }
            selectedPin = nil
            try? await Task.sleep(for: .milliseconds(320))
            showDirections = true
        } catch {
            directionsError = "Δεν ήταν δυνατός ο υπολογισμός οδηγιών. Έλεγξε την πρόσβαση τοποθεσίας και τη σύνδεση στο internet."
        }
    }
    func routeKey(_ leg: TripRouteLeg) -> String {
        "\(leg.from.latitude),\(leg.from.longitude):\(leg.to.latitude),\(leg.to.longitude):\(leg.walking)"
    }
    func routeColor(_ day: Int) -> Color {
        let colors = darkMode
            ? [Color(hex: "8BCEAB"), Color(hex: "FF957D"), Color(hex: "91C9E4"), Color(hex: "D6BD86")]
            : [AppPalette.brand, Color(hex: "CE6651"), Color(hex: "427E9B"), Color(hex: "8D7846")]
        return colors[day % colors.count]
    }
    func updateRoutes() async {
        // Clearing first ensures a changed itinerary never shows a stale path.
        renderedRoutes = [:]; failedRoutes = 0
        routing = !routes.isEmpty
        let taskID = routeTaskID
        for leg in routes {
            guard !Task.isCancelled, taskID == routeTaskID else { return }
            let key = routeKey(leg)
            if let cached = routeCache[key] { renderedRoutes[key] = cached; continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: leg.from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: leg.to))
            request.transportType = leg.walking ? .walking : .automobile
            let directions = MKDirections(request: request)
            do {
                let response = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled, taskID == routeTaskID else { return }
                if let route = response.routes.first { routeCache[key] = route; renderedRoutes[key] = route }
                else { failedRoutes += 1 }
            } catch {
                guard !Task.isCancelled, taskID == routeTaskID else { return }
                failedRoutes += 1
            }
        }
        if !Task.isCancelled { routing = false }
    }
}

// A full-screen journey, with the supplied brand artwork as its signature detail.
private struct ResearchProgressScreen: View {
    let destination: String
    let operations: [ResearchOperation]
    let currentStep: Int
    let completedSteps: Set<Int>
    let running: Bool
    let saved: Bool
    let partial: Bool
    let error: String?
    let needsServiceUpdate: Bool
    let canRecover: Bool
    let resuming: Bool
    var needsNewRequest: Bool = false
    var diagnostic: String? = nil
    var phaseStates: [Int: String] = [:]
    let onClose: () -> Void
    let onRetry: () -> Void
    let onSettings: () -> Void
    let onRecover: () -> Void
    let onOpenPlan: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        if saved { return partial ? "Το πλάνο σου είναι εδώ" : "Έτοιμο το ταξίδι σου" }
        if needsServiceUpdate { return "Πριν ξεκινήσουμε" }
        if error != nil { return "Η έρευνα χρειάζεται συνέχεια" }
        return "Ετοιμάζουμε το ταξίδι σου"
    }
    private var status: String {
        if saved { return partial ? "Αποθηκεύτηκε · υπάρχουν σημεία για έλεγχο" : "Αποθηκεύτηκε στο ταξίδι σου" }
        if error != nil {
            if needsNewRequest { return "Χρειάζεται νέο αίτημα έρευνας" }
            return needsServiceUpdate ? "Αναμονή ενημέρωσης υπηρεσίας" : "Χρειάζεται έλεγχος κατάστασης"
        }
        return "\(completedSteps.count) από 5 βήματα ολοκληρώθηκαν"
    }
    private var background: some View {
        ZStack {
            AppPalette.canvas
            LinearGradient(colors: colorScheme == .dark
                ? [Color(hex: "252A25"), Color(hex: "202522"), AppPalette.canvas]
                : [Color(hex: "FFEDD9"), Color(hex: "FFF7EF"), Color(hex: "FFFDFA")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [AppPalette.accent.opacity(colorScheme == .dark ? 0.07 : 0.08), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 420)
        }.ignoresSafeArea()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("trippy").font(.custom("PlusJakartaSans-Bold", size: 20, relativeTo: .headline))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel("Κλείσιμο έρευνας")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.custom("PlusJakartaSans-Bold", size: 32, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(destination.isEmpty ? "Για το επόμενο ταξίδι σου" : destination)
                        .font(.custom("PlusJakartaSans-Medium", size: 16, relativeTo: .body))
                        .foregroundStyle(AppPalette.secondaryInk)
                }.accessibilityElement(children: .combine)
                TrippyLoadingEmblem(active: running && error == nil)
                    .containerRelativeFrame(.vertical) { length, _ in min(360, max(264, length * 0.38)) }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(saved ? "Το πλάνο σου" : "Βήμα προς βήμα")
                            .font(.custom("PlusJakartaSans-Bold", size: 20, relativeTo: .headline))
                        Spacer()
                        Text("\(completedSteps.count)/5")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 13, relativeTo: .caption))
                            .monospacedDigit().contentTransition(.numericText())
                    }
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { step in
                            Capsule().fill(completedSteps.contains(step) ? AppPalette.ink : step == currentStep && running ? AppPalette.art : AppPalette.secondaryInk.opacity(0.12))
                                .frame(height: 4)
                        }
                    }.accessibilityHidden(true)
                    Text(status).font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .caption))
                        .foregroundStyle(AppPalette.secondaryInk)
                    VStack(spacing: 0) {
                        ForEach(ResearchOperation.planned) { planned in
                            stepRow(operations.first { $0.step == planned.step } ?? planned)
                        }
                    }
                }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(needsServiceUpdate ? "Χρειάζεται ενημέρωση" : "Δεν ολοκληρώθηκε η έρευνα",
                              systemImage: needsServiceUpdate ? "arrow.triangle.2.circlepath" : "exclamationmark.circle")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 16, relativeTo: .body))
                        Text(error).font(.custom("PlusJakartaSans-Regular", size: 16, relativeTo: .body))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(AppPalette.secondaryInk)
                        if let diagnostic {
                            DisclosureGroup("Στοιχεία για υποστήριξη") {
                                Text(diagnostic).font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled).padding(.top, 8)
                            }.font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .caption))
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                if saved, let diagnostic {
                    DisclosureGroup("Στοιχεία έρευνας και υποστήριξης") {
                        Text(diagnostic).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).padding(.top, 8)
                        Button("Αντιγραφή στοιχείων") { UIPasteboard.general.string = diagnostic }
                    }.font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .caption))
                }
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(AppPalette.ink)
        .background(background)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .interactiveDismissDisabled(running)
        .environment(\.layoutDirection, .leftToRight)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: currentStep)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: completedSteps)
    }
    private func stepRow(_ operation: ResearchOperation) -> some View {
        let done = completedSteps.contains(operation.step)
        let active = operation.step == currentStep && running && error == nil
        let phaseState = phaseStates[operation.step]
        let stopped = phaseState == "failed" || (phaseState == nil && operation.step == currentStep && error != nil)
        let reached = done || active || stopped
        return HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ResearchStepSymbol(symbol: operation.symbol, active: active, completed: done, stopped: stopped)
                if operation.step < 5 {
                    Rectangle().fill(done ? AppPalette.art.opacity(0.6) : AppPalette.secondaryInk.opacity(0.12))
                        .frame(width: 2).frame(maxHeight: .infinity).padding(.vertical, 4)
                }
            }.frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(operation.title).font(.custom("PlusJakartaSans-SemiBold", size: 16, relativeTo: .body))
                    if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.secondaryInk) }
                }
                Text(done ? "Ολοκληρώθηκε" : ResearchDiagnostics.phaseDetail(phaseState) ?? (stopped ? "Περιμένει συνέχεια" : saved ? "Δεν ολοκληρώθηκε" : operation.detail))
                    .font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .caption))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }.padding(.top, 4).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(reached ? AppPalette.ink : AppPalette.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Ολοκληρώθηκε" : active ? "Σε εξέλιξη" : stopped ? "Διακόπηκε" : "Δεν ξεκίνησε")
    }
    private func primaryAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.custom("PlusJakartaSans-SemiBold", size: 16, relativeTo: .body))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(AppPalette.inverseInk)
                .background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    private var actions: some View {
        VStack(spacing: 8) {
            if saved {
                primaryAction("Δες το πλάνο σου", symbol: "arrow.right", action: onOpenPlan)
            } else if canRecover {
                primaryAction("Ανάκτησε το υπάρχον πλάνο", symbol: "tray.and.arrow.down", action: onRecover)
            } else if needsServiceUpdate {
                primaryAction("Ρυθμίσεις σύνδεσης", symbol: "network", action: onSettings)
            } else if error != nil {
                primaryAction(needsNewRequest ? "Ξεκίνα νέα έρευνα" : resuming ? "Έλεγχος κατάστασης" : "Δοκίμασε ξανά", symbol: "arrow.clockwise", action: onRetry)
            } else {
                HStack(spacing: 12) {
                    ProgressView().tint(AppPalette.brand)
                    Text(resuming ? "Μπορείς να κλείσεις αυτή τη σελίδα. Η έρευνα συνεχίζεται." : "Περίμενε λίγο μέχρι να ξεκινήσει η έρευνα.")
                        .font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .caption))
                        .foregroundStyle(AppPalette.secondaryInk)
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background(AppPalette.canvas.opacity(0.96))
    }
}

private struct ResearchStepSymbol: View {
    let symbol: String
    let active: Bool
    let completed: Bool
    let stopped: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(active ? AppPalette.art.opacity(0.22) : completed ? AppPalette.brand.opacity(0.08) : AppPalette.surface.opacity(0.72))
            Image(systemName: stopped ? "pause" : symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active || completed || stopped ? AppPalette.ink : AppPalette.secondaryInk)
                .symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
            if active {
                if reduceMotion {
                    Circle().stroke(AppPalette.art, lineWidth: 2)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        Circle().trim(from: 0.12, to: 0.38).stroke(AppPalette.art, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180))
                    }
                }
            }
        }.frame(width: 40, height: 40).accessibilityHidden(true)
    }
}

// The supplied SVG contains its own animation. Render locally to preserve the artwork.
private struct TrippyLoadingEmblem: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        SVGIdleView(animate: active && !reduceMotion && scenePhase == .active)
            .accessibilityHidden(true)
    }
}
private struct SVGIdleView: UIViewRepresentable {
    let animate: Bool
    final class Coordinator: NSObject, WKNavigationDelegate {
        var animate: Bool
        init(animate: Bool) { self.animate = animate }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(animate ? "document.querySelector('svg')?.unpauseAnimations()" : "document.querySelector('svg')?.pauseAnimations()", completionHandler: nil)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(animate: animate) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear; web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        if let url = Bundle.main.url(forResource: "logo-idle", withExtension: "svg", subdirectory: "Brand"),
           let svg = try? String(contentsOf: url, encoding: .utf8) {
            let paused = animate ? "" : "svg.pauseAnimations();svg.setCurrentTime(0);"
            web.loadHTMLString("""
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">
            <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}svg{width:100%;height:100%;display:block}svg circle[fill="none"],svg path[stroke-opacity]{stroke:none!important}</style></head>
            <body>\(svg)<script>let svg=document.querySelector('svg');\(paused)</script></body></html>
            """, baseURL: nil)
        }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.animate = animate
        web.evaluateJavaScript(animate ? "document.querySelector('svg')?.unpauseAnimations()" : "document.querySelector('svg')?.pauseAnimations()", completionHandler: nil)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.evaluateJavaScript("document.querySelector('svg')?.pauseAnimations()", completionHandler: nil)
        web.stopLoading(); web.navigationDelegate = nil
    }
}

// MARK: - Personal social-source library
private extension TripFlowView {
    func persistSocialLibrary() {
        do { try SocialLibraryStore.save(SocialLibraryDocument(sources: socialSources, places: socialPlaces, notes: travelNotes)) }
        catch { showToast("Δεν αποθηκεύτηκαν οι αλλαγές. Έλεγξε τον διαθέσιμο χώρο.") }
    }
    func syncShareTargets() {
        SharedInbox.writeTargets(trips.map { ShareTarget(id: $0.id, title: $0.title, tripID: $0.id, kind: "trip") } + travelNotes.map { ShareTarget(id: $0.id, title: $0.title, tripID: $0.tripID, kind: "note") })
    }
    @MainActor func importSharedSources() async {
        guard !processingShares else { return }
        processingShares = true
        defer { processingShares = false }
        for envelope in SharedInbox.pending() where !socialSources.contains(where: { $0.id == envelope.id }) {
            var source = await SharedSourceProcessor.process(envelope)
            source.city = trips.first(where: { $0.id == envelope.destination.tripID })?.brief.destination
            socialSources.append(source)
            if envelope.destination.mode == "note" { attachSourceToNote(source, noteID: envelope.destination.noteID) }
            persistSocialLibrary()
        }
    }
    private func sourceTextBinding(_ sourceID: UUID, field: String) -> Binding<String> {
        Binding(get: {
            guard let source = socialSources.first(where: { $0.id == sourceID }) else { return "" }
            switch field {
            case "title": return source.displayTitle ?? ""
            case "city": return source.city ?? trips.first(where: { $0.id == source.envelope.destination.tripID })?.brief.destination ?? ""
            default: return source.listTitle ?? ""
            }
        }, set: { value in
            guard let index = socialSources.firstIndex(where: { $0.id == sourceID }) else { return }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            switch field {
            case "title": socialSources[index].displayTitle = clean
            case "city": socialSources[index].city = clean
            default: socialSources[index].listTitle = clean
            }
        })
    }
    private func isVideoSource(_ source: ImportedSocialSource) -> Bool {
        source.envelope.mediaKind == "video" || source.envelope.sourceURL?.localizedCaseInsensitiveContains("tiktok.com") == true
    }
    private func cityForSource(_ source: ImportedSocialSource) -> String {
        source.city?.nonEmpty ?? trips.first(where: { $0.id == source.envelope.destination.tripID })?.brief.destination ?? ""
    }
    private func cityForMention(_ place: SocialPlaceMention) -> String {
        if let city = place.city?.nonEmpty { return city }
        if let tripCity = trips.first(where: { $0.id == place.tripID })?.brief.destination { return tripCity }
        if let source = socialSources.first(where: { $0.id == place.sourceID }) { return cityForSource(source) }
        return ""
    }
    var videoLibrary: some View {
        let videos = socialSources.filter { isVideoSource($0) && sourceMatchesLibrary($0) }
            .sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
        return VStack(alignment: .leading, spacing: 16) {
            if videos.isEmpty {
                ContentUnavailableView("Τα TikTok saves σου, οργανωμένα", systemImage: "play.rectangle.on.rectangle",
                                       description: Text("Κάνε share ένα video στο Trippy και σύνδεσέ το με πόλη, places και Notes."))
            }
            ForEach(videos) { source in
                TikTokVideoMemoryCard(source: source,
                    places: socialPlaces.filter { $0.sourceID == source.id },
                    notes: travelNotes.filter { $0.sourceIDs.contains(source.id) },
                    city: cityForSource(source),
                    onOpenSource: { selectedSocialSource = source },
                    onOpenNote: { selectedTravelNoteID = $0 })
            }
        }
    }
    private func socialPlaceVideoCarousel(city: String) -> some View {
        let matches = socialPlaces.filter { cityForMention($0).localizedCaseInsensitiveCompare(city) == .orderedSame }
        let linkedSourceIDs = Set(matches.map(\.sourceID))
        let unlinkedVideos = socialSources.filter {
            isVideoSource($0) && cityForSource($0).localizedCaseInsensitiveCompare(city) == .orderedSame && !linkedSourceIDs.contains($0.id)
        }.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
        let grouped = Dictionary(grouping: matches) { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let clusters = grouped.compactMap { key, mentions -> TikTokPlaceCluster? in
            guard let first = mentions.first else { return nil }
            return TikTokPlaceCluster(id: key, title: first.name, city: city, mentions: mentions.sorted { mentionSourceDate($0) > mentionSourceDate($1) })
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "music.note").font(.headline).foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TikTok saves · \(city)").font(.custom("PlusJakartaSans-Bold", size: 19)).foregroundStyle(AppPalette.ink)
                    Text("Videos, places και τα notes τους μαζί.").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                Button("Videos") { librarySection = "Videos" }.font(.caption.weight(.bold)).foregroundStyle(AppPalette.brand)
            }
            if clusters.isEmpty && unlinkedVideos.isEmpty {
                Button { showImportLink = true } label: {
                    Label("Πρόσθεσε TikTok save για \(city)", systemImage: "plus")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                        .background(AppPalette.surface, in: Capsule())
                }.buttonStyle(.plain)
            }
            if !clusters.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(clusters) { cluster in
                            TikTokPlaceMemoryCard(cluster: cluster,
                                sources: cluster.mentions.compactMap { mention in socialSources.first { $0.id == mention.sourceID } },
                                notes: travelNotes,
                                onOpenSource: { sourceID in selectedSocialSource = socialSources.first { $0.id == sourceID } },
                                onOpenNote: { selectedTravelNoteID = $0 })
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            }
            if !unlinkedVideos.isEmpty {
                Text("Videos που δεν έχουν ακόμη place tag").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.secondaryInk)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(unlinkedVideos) { source in
                            TikTokVideoMemoryCard(source: source, places: [], notes: travelNotes.filter { $0.sourceIDs.contains(source.id) },
                                city: city, onOpenSource: { selectedSocialSource = source }, onOpenNote: { selectedTravelNoteID = $0 })
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            }
        }.padding(.top, 8)
    }
    private func mentionSourceDate(_ mention: SocialPlaceMention) -> Date {
        socialSources.first(where: { $0.id == mention.sourceID })?.envelope.capturedAt ?? .distantPast
    }
    func attachSourceToNote(_ source: ImportedSocialSource, noteID: UUID?) {
        if let noteID, let index = travelNotes.firstIndex(where: { $0.id == noteID }) {
            if !travelNotes[index].sourceIDs.contains(source.id) { travelNotes[index].sourceIDs.append(source.id) }
            if travelNotes[index].city == nil { travelNotes[index].city = cityForSource(source).nonEmpty }
            travelNotes[index].updatedAt = .now
        } else {
            let title = source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok inspiration"
            travelNotes.insert(TravelNote(id: UUID(), title: String(title.prefix(80)), tripID: source.envelope.destination.tripID,
                                         sourceIDs: [source.id], userText: "", updatedAt: .now, city: cityForSource(source).nonEmpty), at: 0)
        }
    }
    @MainActor private func saveTikTokPlace(from source: ImportedSocialSource) async {
        let name = socialPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = socialPlaceCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var latitude: Double?
        var longitude: Double?
        var resolvedCity = city
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, city].filter { !$0.isEmpty }.joined(separator: ", ")
        if let region = cityCoordinates[city]?.coordinate {
            request.region = MKCoordinateRegion(center: region, span: .init(latitudeDelta: 1, longitudeDelta: 1))
        }
        if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
            latitude = item.placemark.coordinate.latitude
            longitude = item.placemark.coordinate.longitude
            resolvedCity = item.placemark.locality ?? city
        }
        let mentionID = UUID()
        let noteID = UUID()
        let tripID = source.envelope.destination.tripID
        let evidenceText = source.evidence.first(where: { $0.id == socialEvidenceID })?.text ?? ""
        let noteText = [socialPlaceSummary.trimmingCharacters(in: .whitespacesAndNewlines), evidenceText]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        socialPlaces.append(SocialPlaceMention(id: mentionID, name: name, summary: socialPlaceSummary,
                                              sourceID: source.id, evidenceIDs: socialEvidenceID.isEmpty ? [] : [socialEvidenceID],
                                              tripID: tripID, latitude: latitude, longitude: longitude,
                                              city: resolvedCity.nonEmpty, noteID: noteID))
        if let index = socialSources.firstIndex(where: { $0.id == source.id }) {
            var placeIDs = socialSources[index].linkedPlaceIDs ?? []
            if !placeIDs.contains(mentionID) { placeIDs.append(mentionID) }
            socialSources[index].linkedPlaceIDs = placeIDs
            if socialSources[index].city == nil { socialSources[index].city = resolvedCity.nonEmpty }
        }
        travelNotes.insert(TravelNote(id: noteID, title: name, tripID: tripID,
                                      sourceIDs: [source.id], userText: noteText, updatedAt: .now,
                                      placeMentionID: mentionID, city: resolvedCity.nonEmpty), at: 0)
        showAddSocialPlace = false
        socialPlaceName = ""; socialPlaceSummary = ""; socialPlaceCity = ""
    }
    var socialInboxLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            if processingShares { HStack { TrippyLoadingEmblem(active: true).frame(width: 48, height: 48); Text("Διαβάζω τα shares…").font(.subheadline) } }
            if socialSources.isEmpty {
                ContentUnavailableView("Έμπνευση από TikTok", systemImage: "square.and.arrow.down", description: Text("Στο TikTok: Share → More → Save to Trippy. Μπορείς επίσης να προσθέσεις link εδώ."))
            }
            ForEach(socialSources.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }.filter { sourceMatchesLibrary($0) }) { source in
                Button { selectedSocialSource = source } label: {
                    HStack(spacing: 16) {
                        Image(systemName: source.envelope.mediaKind == "slides" ? "photo.stack" : (source.envelope.mediaKind == "video" ? "play.rectangle" : "link"))
                            .font(.title3).frame(width: 48, height: 48).background(AppPalette.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok share").font(.headline).lineLimit(2)
                            Text(sourceStatus(source)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
    func sourceMatchesLibrary(_ source: ImportedSocialSource) -> Bool {
        return (libraryCity == nil || cityForSource(source).localizedCaseInsensitiveCompare(libraryCity!) == .orderedSame) &&
            (libraryQuery.isEmpty || (source.displayTitle ?? "").localizedCaseInsensitiveContains(libraryQuery) ||
             (source.listTitle ?? "").localizedCaseInsensitiveContains(libraryQuery) ||
             source.envelope.sourceURL?.localizedCaseInsensitiveContains(libraryQuery) == true ||
             source.evidence.contains { $0.text.localizedCaseInsensitiveContains(libraryQuery) })
    }
    func sourceStatus(_ source: ImportedSocialSource) -> String {
        switch source.state {
        case "needs_retrieval": return "Αποθηκεύτηκε το link · Αναμονή ανάκτησης post"
        case "needs_transcript": return "Αποθηκεύτηκε το video · Αναμονή transcript"
        case "ready": return "Διαθέσιμη πληροφορία και places"
        default: return "Διαβάστηκε το κείμενο · Έλεγχος places"
        }
    }
    var notesLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            if travelNotes.isEmpty { ContentUnavailableView("Χώρος για την έμπνευσή σου", systemImage: "note.text", description: Text("Κράτησε ολόκληρη την πληροφορία ενός post ή τις δικές σου σημειώσεις.")) }
            ForEach(travelNotes.filter { note in
                let trip = trips.first { $0.id == note.tripID }
                let noteCity = note.city ?? trip?.brief.destination
                return (libraryCity == nil || noteCity?.localizedCaseInsensitiveCompare(libraryCity!) == .orderedSame) &&
                    (libraryQuery.isEmpty || "\(note.title) \(note.userText)".localizedCaseInsensitiveContains(libraryQuery) ||
                     socialSources.filter { note.sourceIDs.contains($0.id) }.contains { source in source.evidence.contains { $0.text.localizedCaseInsensitiveContains(libraryQuery) } })
            }) { note in
                Button { selectedTravelNoteID = note.id } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: "note.text"); Spacer(); Text(note.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                        Text(note.title).font(.custom("PlusJakartaSans-Bold", size: 20)).lineLimit(2)
                        Text(note.userText.nonEmpty ?? "\(note.sourceIDs.count) πηγές · Όλη η πληροφορία σε ένα note").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        if let trip = trips.first(where: { $0.id == note.tripID }) { Text(trip.title).font(.caption.weight(.semibold)) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain)
            }
        }
    }
    var socialSavedPlaces: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !socialPlaces.isEmpty { Text("Από την έμπνευσή σου").font(.headline) }
            ForEach(socialPlaces.filter { place in
                return (libraryCity == nil || cityForMention(place).localizedCaseInsensitiveCompare(libraryCity!) == .orderedSame) &&
                    (libraryQuery.isEmpty || place.name.localizedCaseInsensitiveContains(libraryQuery))
            }) { place in
                Button { selectedSocialSource = socialSources.first { $0.id == place.sourceID } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name).font(.headline)
                        Text(place.summary).font(.subheadline).foregroundStyle(.secondary)
                        Label("Πληροφορία από post · Προβολή πηγής", systemImage: "link").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
    func socialSourceDetail(_ initial: ImportedSocialSource) -> some View {
        let source = socialSources.first { $0.id == initial.id } ?? initial
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Video memory", systemImage: "music.note").font(.caption.weight(.bold)).foregroundStyle(AppPalette.brand)
                        TextField("Τίτλος video", text: sourceTextBinding(source.id, field: "title"))
                            .font(.custom("PlusJakartaSans-Bold", size: 21))
                        HStack(spacing: 10) {
                            TextField("Πόλη", text: sourceTextBinding(source.id, field: "city"))
                            TextField("Τίτλος λίστας", text: sourceTextBinding(source.id, field: "list"))
                        }.font(.subheadline)
                        Text("Π.χ. Top 10 nightlife places · Warsaw. Το video συνδέεται με κάθε place και το note του.")
                            .font(.caption).foregroundStyle(AppPalette.secondaryInk)
                    }.padding(18).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text(sourceStatus(source)).font(.subheadline).foregroundStyle(.secondary)
                    if let link = source.envelope.sourceURL, let url = URL(string: link) { TikTokLinkPill(url: url) }
                    if let trip = trips.first(where: { $0.id == source.envelope.destination.tripID }) { Label(trip.title, systemImage: "suitcase.rolling").font(.subheadline) }
                    if let video = source.envelope.attachments.first(where: { $0.kind == "video" }),
                       let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: video) {
                        SharedSourceVideoThumbnail(url: url)
                    }
                    ForEach(source.evidence.sorted { $0.order < $1.order }) { block in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(block.origin == "slide_ocr" ? "Slide \(block.order + 1) · OCR" : "Κείμενο που παραδόθηκε με το share").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if let attachmentID = block.attachmentID,
                               let attachment = source.envelope.attachments.first(where: { $0.id == attachmentID }),
                               let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment) {
                                SharedSourceImage(url: url)
                            }
                            Text(block.text).font(.body).textSelection(.enabled)
                        }
                    }
                    ForEach(source.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    if source.evidence.isEmpty { Text("Το post δεν έχει ανακτηθεί ακόμη. Ο σύνδεσμος και ο προορισμός αποθήκευσης έχουν διατηρηθεί.").font(.subheadline) }
                    Menu {
                        Button("Νέο Note", systemImage: "square.and.pencil") { attachSourceToNote(source, noteID: nil) }
                        ForEach(travelNotes) { note in
                            Button(note.title) { attachSourceToNote(source, noteID: note.id) }
                        }
                    } label: { Label("Κράτησε όλη την πληροφορία σε Note", systemImage: "note.text.badge.plus") }.frame(minHeight: 44)
                    Button {
                        socialPlaceSourceID = source.id; socialPlaceName = ""; socialPlaceSummary = ""
                        socialPlaceCity = cityForSource(source)
                        socialEvidenceID = source.evidence.first?.id ?? ""; showAddSocialPlace = true
                    } label: { Label("Σύνδεσε place με αυτό το video", systemImage: "mappin.and.ellipse") }.frame(minHeight: 44)
                    ForEach(socialPlaces.filter { $0.sourceID == source.id }) { place in
                        Button { if let noteID = place.noteID { selectedTravelNoteID = noteID } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(place.name, systemImage: "mappin.and.ellipse").font(.headline)
                                Text(place.summary.nonEmpty ?? cityForMention(place)).font(.subheadline).foregroundStyle(.secondary)
                                if place.noteID != nil { Label("Άνοιγμα place note", systemImage: "note.text").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.brand) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(24)
            }.background(AppPalette.canvas)
                .navigationTitle("Η πηγή σου").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { selectedSocialSource = nil } } }
                .sheet(isPresented: $showAddSocialPlace) { socialPlaceReviewSheet(source) }
        }
    }
    func socialPlaceReviewSheet(_ source: ImportedSocialSource) -> some View {
        NavigationStack {
            Form {
                TextField("Όνομα place όπως γράφεται στην πηγή", text: $socialPlaceName)
                TextField("Πόλη / περιοχή", text: $socialPlaceCity)
                Picker("Κείμενο τεκμηρίωσης", selection: $socialEvidenceID) {
                    ForEach(source.evidence) { Text($0.origin == "slide_ocr" ? "Slide \($0.order + 1)" : "Shared text").tag($0.id) }
                }
                if let evidence = source.evidence.first(where: { $0.id == socialEvidenceID }) { Text(evidence.text).font(.subheadline).textSelection(.enabled) }
                TextField("Σύντομη πληροφορία", text: $socialPlaceSummary, axis: .vertical)
                Text("Θα συνδεθεί με την πόλη, την πηγή και το δικό του place note. Η θέση γίνεται resolve από Apple Maps.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Save place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ακύρωση") { showAddSocialPlace = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveTikTokPlace(from: source) } }
                        .disabled(socialPlaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    func travelNoteDetail(_ id: UUID) -> some View {
        let note = travelNotes.first { $0.id == id }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Τίτλος", text: Binding(get: { travelNotes.first { $0.id == id }?.title ?? "" }, set: { title in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].title = title; travelNotes[index].updatedAt = .now }
                    })).font(.custom("PlusJakartaSans-Bold", size: 28))
                    Picker("Συλλογή", selection: Binding(get: { travelNotes.first { $0.id == id }?.tripID }, set: { tripID in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].tripID = tripID }
                    })) {
                        Text("Γενικά Notes").tag(UUID?.none)
                        ForEach(trips) { trip in Text(trip.title).tag(Optional(trip.id)) }
                    }
                    if let linkedPlaces = note?.linkedPlaces, !linkedPlaces.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Συνδεδεμένα μέρη").font(.headline)
                            ForEach(linkedPlaces) { place in
                                Button {
                                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
                                    item.name = place.name
                                    item.openInMaps()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse").foregroundStyle(AppPalette.brand)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.ink)
                                            Text(place.address).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                    }.padding(12).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    TextField("Οι σκέψεις σου…", text: Binding(get: { travelNotes.first { $0.id == id }?.userText ?? "" }, set: { text in
                        if let index = travelNotes.firstIndex(where: { $0.id == id }) { travelNotes[index].userText = text; travelNotes[index].updatedAt = .now }
                    }), axis: .vertical).font(.body)
                    ForEach(socialSources.filter { note?.sourceIDs.contains($0.id) == true }) { source in
                        VStack(alignment: .leading, spacing: 16) {
                            Label(sourceStatus(source), systemImage: "link").font(.caption).foregroundStyle(.secondary)
                            ForEach(source.evidence.sorted { $0.order < $1.order }) { block in
                                Text(block.text).font(.body).textSelection(.enabled)
                            }
                            ForEach(socialPlaces.filter { $0.sourceID == source.id }) { place in
                                VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.headline); Text(place.summary).font(.subheadline) }
                            }
                            if let link = source.envelope.sourceURL, let url = URL(string: link) { Link("Αρχικό post", destination: url) }
                        }.padding(20).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                }.padding(24)
            }.background(AppPalette.canvas).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { selectedTravelNoteID = nil } } }
        }
    }
    var importLinkSheet: some View {
        NavigationStack {
            Form {
                TextField("TikTok link", text: $importSourceURL).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Text("Το link αποθηκεύεται στο Inbox. Οι εικόνες/captions ή το transcript απαιτούν ανάκτηση του post.").font(.caption).foregroundStyle(.secondary)
                if let importLinkError { Text(importLinkError).foregroundStyle(.red) }
            }.navigationTitle("Προσθήκη πηγής")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Ακύρωση") { showImportLink = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let url = URL(string: importSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
                                  let host = url.host?.lowercased(), host == "tiktok.com" || host.hasSuffix(".tiktok.com") else {
                                importLinkError = "Χρειάζεται έγκυρο HTTPS TikTok link."; return
                            }
                            let envelope = SharedSourceEnvelope(id: UUID(), capturedAt: .now, sourceURL: url.absoluteString, sharedText: "", attachments: [],
                                                                destination: ShareDestination(mode: "places", tripID: nil, noteID: nil))
                            socialSources.append(ImportedSocialSource(id: envelope.id, envelope: envelope, evidence: [], state: "needs_retrieval", issues: []))
                            importSourceURL = ""; importLinkError = nil; showImportLink = false
                        }
                    }
                }
        }
    }
}

private struct SharedSourceVideoThumbnail: View {
    let url: URL
    @State private var frame: UIImage?
    var body: some View {
        ZStack {
            if let frame { Image(uiImage: frame).resizable().scaledToFill() }
            else { RoundedRectangle(cornerRadius: 20).fill(AppPalette.ink).overlay(Image(systemName: "play.fill").font(.title).foregroundStyle(.white)) }
            Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
        }
        .frame(height: 172).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: url) {
            let generated = await Task.detached(priority: .utility) { () -> UIImage? in
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                guard let image = try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil) else { return nil }
                return UIImage(cgImage: image)
            }.value
            if !Task.isCancelled { frame = generated }
        }
        .accessibilityLabel("Προεπισκόπηση αποθηκευμένου TikTok video")
    }
}

private struct TikTokLinkPill: View {
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "music.note").font(.system(size: 13, weight: .bold))
                Text("Open TikTok").font(.custom("PlusJakartaSans-Bold", size: 12))
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.white).padding(.horizontal, 14).frame(minHeight: 42)
            .background(LinearGradient(colors: [Color(hex: "343433"), .black], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
            .overlay(alignment: .topLeading) { Capsule().fill(.white.opacity(0.22)).frame(height: 1).padding(.horizontal, 12).offset(y: 2) }
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Άνοιγμα TikTok βίντεο")
    }
}

private struct TikTokVideoMemoryCard: View {
    let source: ImportedSocialSource
    let places: [SocialPlaceMention]
    let notes: [TravelNote]
    let city: String
    let onOpenSource: () -> Void
    let onOpenNote: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.listTitle ?? "TikTok save").font(.caption.weight(.bold)).foregroundStyle(AppPalette.brand).lineLimit(1)
                    Text(source.displayTitle ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok video")
                        .font(.custom("PlusJakartaSans-Bold", size: 16)).foregroundStyle(AppPalette.ink).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !city.isEmpty { Text(city).font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 6).background(AppPalette.surface, in: Capsule()) }
            }
            if let attachment = source.envelope.attachments.first(where: { $0.kind == "video" }),
               let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment) {
                Button(action: onOpenSource) { SharedSourceVideoThumbnail(url: url) }.buttonStyle(.plain)
            } else {
                Button(action: onOpenSource) {
                    RoundedRectangle(cornerRadius: 20).fill(AppPalette.ink)
                        .overlay(Image(systemName: "play.rectangle.fill").font(.system(size: 32)).foregroundStyle(.white))
                        .frame(height: 145)
                }.buttonStyle(.plain)
            }
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PLACES FROM THIS VIDEO").font(.custom("PlusJakartaSans-ExtraBold", size: 9)).tracking(0.9).foregroundStyle(AppPalette.secondaryInk)
                    ForEach(places) { place in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(AppPalette.brand)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.ink)
                                if let summary = place.summary.nonEmpty { Text(summary).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            ForEach(notes) { note in
                Button { onOpenNote(note.id) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "note.text").foregroundStyle(AppPalette.brand)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title).font(.caption.weight(.bold)).foregroundStyle(AppPalette.ink)
                            Text(note.userText.nonEmpty ?? "Σημείωση από αυτό το video")
                                .font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppPalette.secondaryInk)
                    }.padding(11).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.buttonStyle(.plain)
            }
            if let rawURL = source.envelope.sourceURL, let url = URL(string: rawURL) { TikTokLinkPill(url: url) }
        }
        .padding(16).frame(width: 300, alignment: .leading)
        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: AppPalette.ink.opacity(0.1), radius: 16, y: 7)
    }
}

private struct TikTokPlaceMemoryCard: View {
    let cluster: TikTokPlaceCluster
    let sources: [ImportedSocialSource]
    let notes: [TravelNote]
    let onOpenSource: (UUID) -> Void
    let onOpenNote: (UUID) -> Void
    private var uniqueSources: [ImportedSocialSource] {
        var seen = Set<UUID>()
        return sources.filter { seen.insert($0.id).inserted }.sorted { $0.envelope.capturedAt > $1.envelope.capturedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cluster.title).font(.custom("PlusJakartaSans-Bold", size: 18)).foregroundStyle(AppPalette.ink).lineLimit(1)
                    Text(cluster.city).font(.caption.weight(.medium)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer(minLength: 0)
                Text("\(uniqueSources.count) videos").font(.caption2.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(AppPalette.brand.opacity(0.12), in: Capsule()).foregroundStyle(AppPalette.brand)
            }
            if let summary = cluster.mentions.first(where: { $0.summary.nonEmpty != nil })?.summary.nonEmpty {
                Text(summary).font(.caption).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(uniqueSources) { source in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(source.listTitle ?? source.displayTitle ?? "TikTok save")
                                .font(.caption.weight(.bold)).foregroundStyle(AppPalette.brand).lineLimit(2).frame(height: 32, alignment: .topLeading)
                            if let attachment = source.envelope.attachments.first(where: { $0.kind == "video" }),
                               let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment) {
                                Button { onOpenSource(source.id) } label: { SharedSourceVideoThumbnail(url: url).frame(width: 206, height: 112) }
                                    .buttonStyle(.plain)
                            } else {
                                Button { onOpenSource(source.id) } label: {
                                    RoundedRectangle(cornerRadius: 18).fill(AppPalette.ink)
                                        .overlay(Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.white))
                                        .frame(width: 206, height: 112)
                                }.buttonStyle(.plain)
                            }
                            Text(source.displayTitle ?? source.evidence.first?.text.split(separator: "\n").first.map(String.init) ?? "TikTok video")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppPalette.ink).lineLimit(2).frame(height: 34, alignment: .topLeading)
                            ForEach(notes.filter { note in
                                note.placeMentionID.map { id in cluster.mentions.contains(where: { $0.id == id }) } ?? false
                            }) { note in
                                if note.sourceIDs.contains(source.id) {
                                    Button { onOpenNote(note.id) } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Label(note.title, systemImage: "note.text").font(.caption.weight(.bold)).lineLimit(1)
                                            Text(note.userText.nonEmpty ?? "Άνοιγμα note").font(.caption2).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                                        }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(9)
                                            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain)
                                }
                            }
                            if let rawURL = source.envelope.sourceURL, let url = URL(string: rawURL) { TikTokLinkPill(url: url) }
                        }
                        .padding(11).frame(width: 228, alignment: .leading)
                        .background(AppPalette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }.scrollIndicators(.hidden)
        }
        .padding(15).frame(width: 326, alignment: .leading)
        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: AppPalette.ink.opacity(0.1), radius: 15, y: 7)
    }
}

private struct SharedSourceImage: View {
    let url: URL
    @State private var preview: UIImage?
    @State private var finished = false
    var body: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().scaledToFit() }
            else if finished { Label("Η εικόνα δεν είναι διαθέσιμη", systemImage: "photo").font(.caption).foregroundStyle(.secondary).frame(minHeight: 80) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }.frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 20))
            .task(id: url) {
                let image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
                if !Task.isCancelled { preview = image; finished = true }
            }
            .accessibilityLabel("Εικόνα από την αρχική πηγή")
    }
}

private struct GooglePlacesGlyph: View {
    var body: some View {
        Text("Google Maps").font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: "5E5E5E"))
            .accessibilityLabel("Google Maps")
    }
}

private struct GooglePlacesBrandLink: View {
    let url: URL?
    var body: some View {
        HStack(spacing: 7) {
            GooglePlacesGlyph()
            Spacer()
            if let url {
                Link(destination: url) {
                    Label("Άνοιγμα", systemImage: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(AppPalette.brand)
                }
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct GooglePlacePhotoCard: View {
    let photo: GooglePlacePhoto
    let baseURL: String
    let accessToken: String
    @State private var image: UIImage?
    @State private var loading = true
    @State private var imageError: String?
    @State private var retryAttempt = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else if loading { RoundedRectangle(cornerRadius: 22).fill(AppPalette.surface).overlay(ProgressView()) }
                else {
                    RoundedRectangle(cornerRadius: 22).fill(AppPalette.surface)
                        .overlay {
                            VStack(spacing: 7) {
                                Image(systemName: "photo.badge.exclamationmark").font(.title3).foregroundStyle(AppPalette.secondaryInk)
                                Text(imageError ?? "Η φωτογραφία δεν φορτώθηκε")
                                    .font(.caption2).foregroundStyle(AppPalette.secondaryInk).multilineTextAlignment(.center)
                                Button("Δοκίμασε ξανά") { retryAttempt += 1 }
                                    .font(.caption2.weight(.bold)).foregroundStyle(AppPalette.brand)
                            }.padding(14)
                        }
                }
            }.frame(width: 270, height: 174).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                if let attributions = photo.authorAttributions, !attributions.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(attributions) { author in
                                if let url = author.uri.flatMap({ URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0) }) {
                                    Link(author.displayName, destination: url).font(.caption2.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                                } else { Text(author.displayName).font(.caption2.weight(.bold)).foregroundStyle(.white).lineLimit(1) }
                            }
                        }
                    }.scrollIndicators(.hidden).frame(maxHeight: 16)
                }
                if let sourceURL = photo.googleMapsURL.flatMap(URL.init(string:)) {
                    Link("Προβολή φωτογραφίας στο Google Maps", destination: sourceURL)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                } else {
                    Text("Google Maps photo").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.86))
                }
            }.padding(11)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.82), lineWidth: 1))
        .task(id: "\(photo.name)-\(retryAttempt)") { await loadPhoto() }
    }

    private func loadPhoto() async {
        loading = true
        imageError = nil
        defer { loading = false }
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            imageError = "Λείπει το Trippy bridge token."
            return
        }
        guard var components = URLComponents(string: baseURL + "/api/places/photo") else { return }
        components.queryItems = [URLQueryItem(name: "name", value: photo.name), URLQueryItem(name: "max_width", value: "960")]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            if !Task.isCancelled { imageError = "Δεν ήταν δυνατή η επικοινωνία με το Places gateway." }
            return
        }
        guard (200..<300).contains(http.statusCode), let decoded = UIImage(data: data) else {
            if !Task.isCancelled { imageError = "Η εικόνα απορρίφθηκε (HTTP \(http.statusCode))." }
            return
        }
        guard !Task.isCancelled else { return }
        image = decoded
    }
}

private struct GoogleAuthorAvatar: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Circle().fill(AppPalette.brand.opacity(0.15)).overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(AppPalette.brand)) }
        }
        .frame(width: 28, height: 28).clipShape(Circle())
        .task(id: url) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data), !Task.isCancelled else { return }
            image = decoded
        }
    }
}

private struct RouteStepsSheet: View {
    let route: MKRoute
    @Environment(\.dismiss) private var dismiss

    private var steps: [MKRoute.Step] { route.steps.filter { !$0.instructions.isEmpty } }
    private var durationText: String {
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) ώ \(minutes % 60) λ" : "\(minutes) λεπτά"
    }
    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.walk").font(.title2.weight(.semibold))
                            .foregroundStyle(AppPalette.brand).frame(width: 48, height: 48)
                            .background(AppPalette.brand.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Πεζή διαδρομή").font(.headline)
                            Text("\(distanceText(route.distance)) · \(durationText)")
                                .font(.subheadline).foregroundStyle(AppPalette.secondaryInk)
                        }
                    }.padding(.vertical, 5)
                }
                Section("Βήματα") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)").font(.caption.weight(.bold))
                                .foregroundStyle(AppPalette.ink).frame(width: 26, height: 26)
                                .background(AppPalette.brand.opacity(0.2), in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.instructions).font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.ink)
                                if step.distance > 0 {
                                    Text(distanceText(step.distance)).font(.caption).foregroundStyle(AppPalette.secondaryInk)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    if steps.isEmpty {
                        Text("Δεν υπάρχουν αναλυτικά βήματα για αυτή τη διαδρομή.")
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .navigationTitle("Οδηγίες")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// Quiet content, expressive title, glass reserved for floating controls.
private struct MapTripTitle: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).font(.custom("Georgia-BoldItalic", size: 32, relativeTo: .largeTitle))
            .tracking(-1).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppPalette.ink)
            .shadow(color: scheme == .dark ? .black.opacity(0.85) : .white.opacity(0.95), radius: 3)
            .shadow(color: scheme == .dark ? .black.opacity(0.5) : .white.opacity(0.8), radius: 8)
    }
}
private struct SelectedMapChip: ViewModifier {
    let selected: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if selected { content.background(AppPalette.brand, in: Capsule()) }
        else { content.modifier(AdaptiveGlassControl(shape: .capsule)) }
    }
}
private struct AdaptiveGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 8) { content() } }
        else { content() }
    }
}
private struct QuietPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private extension TripFlowView {
    var bridgeSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Υπηρεσία έρευνας") {
                    TextField("HTTPS URL", text: $bridgeHost).textInputAutocapitalization(.never)
                        .keyboardType(.URL).autocorrectionDisabled()
                    Text("Διεύθυνση του server για το AI research.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Σύνδεση έρευνας").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { showBridgeSettings = false } } }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    var placesSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Σύνδεση με το Trippy") {
                    LabeledContent("Gateway") {
                        Text(bridgeBaseURL).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    SecureField("Trippy bridge token", text: $bridgeToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Εδώ βάζεις το TRIPPY_BRIDGE_TOKEN από το Render — όχι το Google Places API key. Αποθηκεύεται στο Keychain. Το Google key μένει μόνο στο Render. Ο έλεγχος κάνει μία αναζήτηση μόνο με Place ID, χωρίς να φορτώσει ή να αποθηκεύσει στοιχεία μέρους.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await checkPlacesConnection() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCheckingPlacesConnection { ProgressView().padding(.trailing, 5) }
                            Text(isCheckingPlacesConnection ? "Έλεγχος σύνδεσης…" : "Έλεγχος σύνδεσης")
                            Spacer()
                        }
                    }
                    .disabled(isCheckingPlacesConnection)
                    placesConnectionFeedback
                }
            }
            .navigationTitle("Google Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Έγινε") { showPlacesSettings = false } } }
        }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    private var isCheckingPlacesConnection: Bool {
        if case .checking = placesConnectionState { return true }
        return false
    }

    @ViewBuilder
    private var placesConnectionFeedback: some View {
        switch placesConnectionState {
        case .idle:
            Label("Ο έλεγχος θα δοκιμάσει app → Render → Google Places.", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(.secondary)
        case .checking:
            Label("Ελέγχω και τα δύο σκέλη της σύνδεσης…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption).foregroundStyle(.secondary)
        case .connected:
            Label("Συνδέθηκε: app → Render → Google Places API (New).", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "37835F"))
        case .missingToken:
            Label("Λείπει το TRIPPY_BRIDGE_TOKEN. Το πεδίο δεν δέχεται το Google key.", systemImage: "key.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .rejectedToken:
            Label("Το Render απέρριψε το token. Χρειάζεται η ίδια τιμή TRIPPY_BRIDGE_TOKEN και στις δύο πλευρές.", systemImage: "lock.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .missingGoogleKey:
            Label("Το app συνδέθηκε με Render, αλλά λείπει το GOOGLE_PLACES_API_KEY από το Render Environment.", systemImage: "key.slash")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .rateLimited:
            Label("Το gateway έφτασε το όριο αιτημάτων. Περίμενε λίγο και δοκίμασε ξανά.", systemImage: "hourglass")
                .font(.caption).foregroundStyle(Color(hex: "A96D45"))
        case .gatewayError(let message):
            Label("Δεν απάντησε σωστά το Render gateway: \(message)", systemImage: "wifi.exclamationmark")
                .font(.caption).foregroundStyle(Color(hex: "B85C52"))
        case .googleError(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label("Το app συνδέθηκε με Render. Το Google Places απέρριψε το αίτημα.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "B85C52"))
                Text(message).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func checkPlacesConnection() async {
        let token = bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            placesConnectionState = .missingToken
            return
        }
        placesConnectionState = .checking
        guard let url = URLComponents(string: bridgeBaseURL + "/api/places/status")?.url else {
            placesConnectionState = .gatewayError("Η διεύθυνση του gateway δεν είναι έγκυρη.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                placesConnectionState = .gatewayError("Η απάντηση δεν ήταν έγκυρη HTTP response.")
                return
            }
            let result = try? JSONDecoder().decode(PlacesGatewayHealthResponse.self, from: data)
            if http.statusCode == 200, result?.gateway == "connected", result?.googlePlaces == "connected" {
                placesConnectionState = .connected
            } else if http.statusCode == 401 {
                placesConnectionState = .rejectedToken
            } else if result?.errorCode == "google_places_key_missing" {
                placesConnectionState = .missingGoogleKey
            } else if http.statusCode == 429 {
                placesConnectionState = .rateLimited
            } else if result?.gateway == "connected", result?.googlePlaces == "error" {
                let code = result?.errorCode ?? "UNKNOWN"
                let message = result?.message ?? "Άγνωστη απάντηση Google Places (\(code))."
                placesConnectionState = .googleError("\(code): \(message)")
            } else if http.statusCode == 404 {
                placesConnectionState = .gatewayError("Το Render δεν έχει ακόμη το νέο endpoint ελέγχου· κάνε deploy την έκδοση του bridge.")
            } else {
                let detail = result?.message ?? result?.error ?? "HTTP \(http.statusCode)"
                placesConnectionState = .gatewayError(detail)
            }
        } catch {
            placesConnectionState = .gatewayError("Δεν ήταν δυνατή η πρόσβαση στο Render. Έλεγξε τη διεύθυνση και τη σύνδεση internet.")
        }
    }
}

// Plan typography scales with the user's preferred text size.
private enum PlanType {
    static let title = Font.custom("PlusJakartaSans-Bold", size: 24, relativeTo: .title2)
    static let heading = Font.custom("PlusJakartaSans-Bold", size: 17, relativeTo: .headline)
    static let body = Font.custom("PlusJakartaSans-Regular", size: 15, relativeTo: .body)
    static let detail = Font.custom("PlusJakartaSans-Medium", size: 13, relativeTo: .subheadline)
}

private struct PlanRouteMap: View {
    let points: [ResearchMapPoint]
    let legs: [TripRouteLeg]
    let fallback: CLLocationCoordinate2D?
    let missingCount: Int
    @State private var position: MapCameraPosition = .automatic
    @State private var rendered: [String: MKRoute] = [:]
    @State private var cache: [String: MKRoute] = [:]
    @State private var loading = false
    @State private var failed = 0
    private var taskKey: String {
        legs.map { "\($0.id):\($0.from.latitude),\($0.from.longitude):\($0.to.latitude),\($0.to.longitude):\($0.walking)" }.joined(separator: "|")
    }
    private var cameraKey: String {
        points.map { "\($0.id):\($0.latitude),\($0.longitude)" }.joined(separator: "|") + ":\(fallback?.latitude ?? 0):\(fallback?.longitude ?? 0)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !points.isEmpty {
                Map(position: $position, interactionModes: [.pan, .zoom]) {
                    ForEach(points) { point in Marker(point.title, coordinate: point.coordinate).tint(AppPalette.brand) }
                    ForEach(legs) { leg in
                        if let route = rendered[leg.id] { MapPolyline(route.polyline).stroke(AppPalette.brand, lineWidth: 4) }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                .frame(height: 176).clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Στάσεις και προεπισκόπηση διαδρομής της ημέρας")
                if loading { HStack { ProgressView(); Text("Υπολογισμός διαδρομής…").font(PlanType.detail) } }
                else if !legs.isEmpty {
                    let minutes = Int(rendered.values.reduce(0) { $0 + $1.expectedTravelTime } / 60)
                    Text(rendered.isEmpty ? "Η διαδρομή δεν είναι διαθέσιμη. Άνοιξε τις Οδηγίες σε κάθε στάση." : "\(minutes) λεπτά μετακίνησης · \(legs.allSatisfy(\.walking) ? "πεζή προεπισκόπηση" : "προεπισκόπηση διαδρομής")\(failed > 0 ? " · μερική διαδρομή" : "")")
                        .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                } else if points.count > 1 {
                    Text("Τα σημεία εμφανίζονται. Για το επιλεγμένο μέσο, δες τις Οδηγίες κάθε στάσης.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
                }
            } else {
                Label("Λείπουν τα σημεία της ημέρας", systemImage: "mappin.slash")
                    .font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
            if missingCount > 0 && !points.isEmpty {
                Text("\(missingCount) στάσεις δεν έχουν ακριβές σημείο. Η διαδρομή είναι μερική.").font(PlanType.detail).foregroundStyle(AppPalette.secondaryInk)
            }
        }
        .task(id: cameraKey) { fit() }
        .task(id: taskKey) { await route() }
    }
    private func fit() {
        let coordinates = points.map(\.coordinate)
        guard let first = coordinates.first else { return }
        let minLat = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? first.latitude
        let minLon = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLon = coordinates.map(\.longitude).max() ?? first.longitude
        position = .region(.init(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                 span: .init(latitudeDelta: max(0.012, (maxLat - minLat) * 1.6), longitudeDelta: max(0.012, (maxLon - minLon) * 1.6))))
    }
    private func route() async {
        rendered = [:]; failed = 0; loading = !legs.isEmpty
        let generation = taskKey
        for leg in legs {
            guard !Task.isCancelled, generation == taskKey else { return }
            let key = "\(leg.from.latitude),\(leg.from.longitude):\(leg.to.latitude),\(leg.to.longitude):\(leg.walking)"
            if let existing = cache[key] { rendered[leg.id] = existing; continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: leg.from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: leg.to))
            request.transportType = leg.walking ? .walking : .automobile
            let directions = MKDirections(request: request)
            do {
                let response = try await withTaskCancellationHandler { try await directions.calculate() } onCancel: { directions.cancel() }
                guard !Task.isCancelled, generation == taskKey else { return }
                if let result = response.routes.first { rendered[leg.id] = result; cache[key] = result }
                else { failed += 1 }
            } catch {
                guard !Task.isCancelled, generation == taskKey else { return }
                failed += 1
            }
        }
        if !Task.isCancelled, generation == taskKey { loading = false }
    }
}

private struct PlanLocationPicker: View {
    let name: String
    let destination: String
    let center: CLLocationCoordinate2D?
    let onSelect: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var searching = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Διάλεξε το ακριβές μέρος και έλεγξε τη διεύθυνση.").font(PlanType.body)
                    TextField("Όνομα και περιοχή", text: $query).textFieldStyle(.roundedBorder).font(PlanType.body)
                    if searching { ProgressView("Αναζήτηση…") }
                    if let error { Text(error).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk) }
                    ForEach(results.indices, id: \.self) { index in
                        let item = results[index]
                        Button { selected = item } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.name ?? name).font(PlanType.heading)
                                    Text(item.placemark.title ?? destination).font(PlanType.body).foregroundStyle(AppPalette.secondaryInk)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                Image(systemName: selected === item ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if let selected {
                        Map(initialPosition: .region(.init(center: selected.placemark.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                            Marker(selected.name ?? name, coordinate: selected.placemark.coordinate)
                        }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12)).id(selected.placemark.coordinate.latitude.description + selected.placemark.coordinate.longitude.description)
                        Button { onSelect(selected.placemark.coordinate); dismiss() } label: {
                            Text("Χρησιμοποίησε αυτό το σημείο").font(PlanType.heading)
                                .frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(AppPalette.inverseInk)
                                .background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.background(AppPalette.canvas).foregroundStyle(AppPalette.ink)
                .navigationTitle("Σημείο στάσης").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Κλείσιμο") { dismiss() } } }
        }.tint(AppPalette.brand)
        .onAppear { query = "\(name), \(destination)" }
        .task(id: query) { await search() }
    }
    private func search() async {
        selected = nil; results = []; error = nil; searching = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 2 else { return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
            if let center { request.region = .init(center: center, span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4)) }
            let search = MKLocalSearch(request: request)
            let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
            guard !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(8))
            if results.isEmpty { error = "Δεν βρέθηκε σημείο. Δοκίμασε όνομα και πλήρη διεύθυνση." }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Η αναζήτηση δεν είναι διαθέσιμη. Δοκίμασε ξανά."
        }
        if !Task.isCancelled { searching = false }
    }
}


// Offline preview states: these callbacks never start research or spend budget.
#Preview("Research · in progress") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 3, completedSteps: [1, 2], running: true, saved: false, partial: false,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: true,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · service update") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 1, completedSteps: [], running: false, saved: false, partial: false,
        error: "Η υπηρεσία δεν έχει ακόμη τη νέα έκδοση του σχεδιαστή. Η έρευνα δεν ξεκίνησε και δεν έγινε χρέωση.",
        needsServiceUpdate: true, canRecover: false, resuming: false,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · saved with checks") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 5, completedSteps: [1, 2, 3, 4, 5], running: false, saved: true, partial: true,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: false,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
}

#Preview("Research · dark and large text") {
    ResearchProgressScreen(destination: "Barcelona, Spain", operations: ResearchOperation.planned,
        currentStep: 3, completedSteps: [1, 2], running: true, saved: false, partial: false,
        error: nil, needsServiceUpdate: false, canRecover: false, resuming: true,
        onClose: {}, onRetry: {}, onSettings: {}, onRecover: {}, onOpenPlan: {})
        .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility1)
}
