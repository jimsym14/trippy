import SwiftUI
import UIKit
import MapKit
import UniformTypeIdentifiers

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
    var dateIsUnknown = false
    var duration = 4
    var travelers = 2
    var group = "Φίλοι"
    var vibes: Set<String> = ["Πόλη"]
    var interests: Set<String> = ["Φαγητό", "Αξιοθέατα"]
    var budget = ""
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
        case destination, startDate, endDate, dateIsUnknown, duration, travelers, group, vibes, interests, budget, notes, dietaryNeeds, mobility, stayStyle
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        dateIsUnknown = try c.decodeIfPresent(Bool.self, forKey: .dateIsUnknown) ?? false
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 4
        travelers = try c.decodeIfPresent(Int.self, forKey: .travelers) ?? 2
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Φίλοι"
        vibes = try c.decodeIfPresent(Set<String>.self, forKey: .vibes) ?? ["Πόλη"]
        interests = try c.decodeIfPresent(Set<String>.self, forKey: .interests) ?? ["Φαγητό", "Αξιοθέατα"]
        budget = try c.decodeIfPresent(String.self, forKey: .budget) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dietaryNeeds = try c.decodeIfPresent(Set<String>.self, forKey: .dietaryNeeds) ?? []
        mobility = try c.decodeIfPresent(Set<String>.self, forKey: .mobility) ?? []
        stayStyle = try c.decodeIfPresent(String.self, forKey: .stayStyle) ?? "Boutique / Hotel"
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
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, width)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append(Item(index: index, origin: CGPoint(x: x, y: y), size: CGSize(width: itemWidth, height: size.height)))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (items, items.isEmpty ? 0 : y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth)
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(subviews, width: bounds.width).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                      anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
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
        case 1: "Αναζήτηση πηγών"
        case 2: "Σύνθεση προγράμματος"
        default: "Αποθήκευση ταξιδιού"
        }
    }
    var symbol: String {
        switch step {
        case 1: "globe.europe.africa"
        case 2: "sparkles"
        default: "checkmark"
        }
    }
}

private struct Trip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var brief: TripBrief
    var research: String? = nil
    var updatedAt = Date()
    var scheduleOrderByDate: [String: [String]]? = nil
    var reactionsByItemID: [String: String]? = nil
    var mapCoordinatesByPlaceID: [String: StoredPlaceCoordinate]? = nil
    var scheduleEditsByItemID: [String: ScheduleItemEdit]? = nil
    var checklistDoneIDs: Set<String>? = nil
    var budgetEntries: [TripBudgetEntry]? = nil

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

private struct TripFlowView: View {
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @AppStorage("trippy.bridgeHost") private var bridgeHost = "https://trippy-research-89fm.onrender.com/"
    @State private var trips = TripStorage.load()
    @State private var brief = TripBrief()
    @State private var activeTripID: UUID?
    @State private var selectedCard = 0
    @State private var selectedScrollID: Int? = 0
    @State private var stage: TripStage = .library
    @State private var briefProgress: CGFloat = 0
    @State private var cardDrag: CGFloat = 0
    @State private var briefReveal: CGFloat = 0
    @State private var isRevealingBrief = false
    @State private var gestureTripID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var importText = ""
    @State private var importError: String?
    @State private var toast: String?
    @State private var showPromptSheet = false
    @State private var showResearchFileImporter = false
    @State private var pace = 0.35
    @State private var selectedRegion = "Ευρώπη"
    @State private var workspaceTab = "Πρόγραμμα"
    @State private var showExtraPreferences = false
    @State private var expandedDayIndices: Set<Int> = []
    @State private var expandedScheduleItemIDs: Set<String> = []
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
    @State private var liveResearchStep = 1
    @State private var liveResearchError: String? = nil
    @State private var liveResearchTask: Task<Void, Never>? = nil
    @State private var calendarDisplayedMonth = Date()
    @State private var calendarRangeStart: DateComponents?
    @State private var calendarRangeEnd: DateComponents?
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
            switch stage {
            case .library:
                GeometryReader { geometry in
                    ZStack {
                        if briefReveal > 0 {
                            briefScreen
                                .offset(y: geometry.size.height * (1 - briefReveal))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        library
                            .offset(y: -geometry.size.height * briefReveal)
                    }
                    .clipped()
                }
                .transition(.opacity)
            case .brief:
                briefScreen
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .workspace:
                workspace
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            resolvedHolidayLocation = nil
            resolvedDestination = ""
            calendarHolidays = []
            loadHolidays(for: destination, debounce: true)
        }
        .onChange(of: calendarDisplayedMonth) { old, new in
            if Calendar.current.component(.year, from: old) != Calendar.current.component(.year, from: new) {
                loadHolidays(for: brief.destination)
            }
        }
        .onChange(of: stage) { _, new in
            if new == .brief { loadHolidays(for: brief.destination) }
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .animation(.spring(response: 0.68, dampingFraction: 0.88), value: stage)
        .animation(.spring(response: 0.48, dampingFraction: 0.78), value: selectedCard)
        .sheet(isPresented: $showPromptSheet) { promptSheet }
        .sheet(isPresented: $showLiveResearchSheet) { liveResearchSheet }
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
                    createTrip()
                    openBrief()
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
        let cardGesture = DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !isRevealingBrief,
                      abs(value.translation.height) > abs(value.translation.width) * 1.25,
                      !trips.isEmpty else { return }
                if gestureTripID == nil, trips.indices.contains(selectedCard) {
                    let trip = trips[selectedCard]
                    gestureTripID = trip.id
                    activeTripID = trip.id
                    brief = trip.brief
                }
                let vertical = value.translation.height
                if vertical < 0 {
                    cardDrag = 0
                    briefReveal = min(0.94, -vertical / max(size.height, 1))
                } else {
                    briefReveal = 0
                    cardDrag = min(160, vertical * 0.8)
                }
            }
            .onEnded { value in
                guard !isRevealingBrief, gestureTripID != nil else { return }
                let upward = -value.translation.height
                let predicted = -value.predictedEndTranslation.height
                if upward > size.height * 0.22 || (upward > 65 && predicted > size.height * 0.45) {
                    finishBriefReveal()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        briefReveal = 0
                        cardDrag = value.translation.height > 65 ? 100 : 0
                    }
                    gestureTripID = nil
                }
            }

        return Group {
            if trips.isEmpty {
                Button {
                    createTrip()
                    openBrief()
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
            stageHeader(title: "", back: .library)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stageProgress
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Νέο ταξίδι")
                            .font(.custom("PlusJakartaSans-ExtraBold", size: 29))
                            .tracking(-0.9)
                            .foregroundStyle(AppPalette.ink)
                        Text("Πες μας τι θέλεις, με λίγα βήματα.")
                            .font(.custom("PlusJakartaSans-Regular", size: 14))
                            .foregroundStyle(AppPalette.secondaryInk)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Πού θέλεις να πας;")
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(AppPalette.ink)
                            TextField("Πόλη ή χώρα", text: $brief.destination)
                                .font(.custom("PlusJakartaSans-Medium", size: 15))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit { loadHolidays(for: brief.destination) }
                            if !brief.destination.isEmpty {
                                Button { brief.destination = "" } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(AppPalette.secondaryInk) }
                            }
                        }
                        .padding(.horizontal, 15).frame(height: 52)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "EADFD5"), lineWidth: 0.8))
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
                                Button { selectedRegion = region } label: { choicePill(region, selected: selectedRegion == region) }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Πότε;")
                        PillFlowLayout {
                            Button { brief.dateIsUnknown = false } label: { choicePill("Συγκεκριμένες", selected: !brief.dateIsUnknown) }
                            Button { brief.dateIsUnknown = true } label: { choicePill("Ευέλικτες", selected: brief.dateIsUnknown) }
                            Button { brief.dateIsUnknown = true; brief.startDate = ""; brief.endDate = ""; calendarRangeStart = nil; calendarRangeEnd = nil } label: { choicePill("Δεν ξέρω", selected: brief.dateIsUnknown && brief.startDate.isEmpty) }
                        }
                        if !brief.dateIsUnknown {
                            Button {
                                showCalendarPicker = true
                                calendarRangeStart = brief.startDate.isEmpty ? nil : parseISODate(brief.startDate).map {
                                    Calendar.current.dateComponents([.year, .month, .day], from: $0)
                                }
                                calendarRangeEnd = brief.endDate.isEmpty ? nil : parseISODate(brief.endDate).map {
                                    Calendar.current.dateComponents([.year, .month, .day], from: $0)
                                }
                                if let date = parseISODate(brief.startDate) {
                                    calendarDisplayedMonth = date
                                }
                                if !brief.destination.isEmpty && calendarHolidays.isEmpty {
                                    loadHolidays(for: brief.destination)
                                }
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

                            // Holiday indicators preview
                            let rangeHolidays = holidaysInSelectedRange
                            if !rangeHolidays.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(rangeHolidays.prefix(3)) { holiday in
                                        HStack(spacing: 8) {
                                            Image(systemName: holiday.kind.symbol)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(holiday.kind.color)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(holiday.localName)
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                                                    .foregroundStyle(AppPalette.ink)
                                                Text(holiday.name)
                                                    .font(.custom("PlusJakartaSans-Regular", size: 10))
                                                    .foregroundStyle(AppPalette.secondaryInk)
                                            }
                                            Spacer()
                                            if let d = holiday.date.date {
                                                Text(d, format: .dateTime.day().month(.abbreviated))
                                                    .font(.custom("PlusJakartaSans-Medium", size: 10))
                                                    .foregroundStyle(AppPalette.secondaryInk)
                                            }
                                        }
                                    }
                                    if rangeHolidays.count > 3 {
                                        Text("+\(rangeHolidays.count - 3) ακόμη")
                                            .font(.custom("PlusJakartaSans-Medium", size: 10))
                                            .foregroundStyle(AppPalette.secondaryInk)
                                    }
                                }
                                .padding(12)
                                .background(Color(hex: "FFF8F4"), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "EADFD5"), lineWidth: 0.5))
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
                        sectionTitle("Τι τύπος ταξιδιού;")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(["Πόλη", "Φύση", "Παραλία", "Πολιτισμός"], id: \.self) { vibe in
                                Button {
                                    if brief.vibes.contains(vibe) { brief.vibes.remove(vibe) } else { brief.vibes.insert(vibe) }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: vibeIcon(vibe)).font(.system(size: 17, weight: .medium))
                                        Text(vibe).font(.custom("PlusJakartaSans-SemiBold", size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .foregroundStyle(brief.vibes.contains(vibe) ? AppPalette.ink : AppPalette.secondaryInk)
                                    .frame(maxWidth: .infinity).frame(height: 76)
                                    .background(brief.vibes.contains(vibe) ? Color(hex: "FFF0E8") : AppPalette.surface, in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(brief.vibes.contains(vibe) ? AppPalette.accent : Color(hex: "EADFD5"), lineWidth: brief.vibes.contains(vibe) ? 1.2 : 0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Ρυθμός")
                        HStack {
                            Text("Χαλαρά").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                            Slider(value: $pace, in: 0...1).tint(AppPalette.brand)
                            Text("Εντατικά").font(.caption).foregroundStyle(AppPalette.secondaryInk)
                        }
                    }

                    DisclosureGroup(isExpanded: $showExtraPreferences) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Ποιοι ταξιδεύουν;")
                                PillFlowLayout {
                                    ForEach(["Μόνος/η", "Ζευγάρι", "Φίλοι", "Οικογένεια", "Δουλειά"], id: \.self) { group in
                                        Button { brief.group = group } label: { choicePill(group, selected: brief.group == group) }
                                    }
                                }
                                HStack {
                                    Text("Άτομα").font(.custom("PlusJakartaSans-Medium", size: 13))
                                    Spacer()
                                    counter(value: $brief.travelers, range: 1...20, suffix: "")
                                }
                                .padding(13).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 15))
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Τι σου αρέσει;")
                                chipGrid(options: ["Φαγητό", "Αξιοθέατα", "Μουσεία", "Bars", "Clubs", "Αγορές", "Εκδρομές", "Events", "Vegan"], selection: $brief.interests)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Διατροφή και αλλεργίες")
                                chipGrid(options: ["Vegan", "Χορτοφαγική", "Χωρίς γλουτένη", "Halal", "Χωρίς ξηρούς καρπούς", "Lactose-free"], selection: $brief.dietaryNeeds)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Κινητικότητα")
                                chipGrid(options: ["Walkable", "Προσβάσιμο", "Καρότσι", "Χωρίς σκάλες"], selection: $brief.mobility)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("Στυλ διαμονής")
                                PillFlowLayout {
                                    ForEach(["Boutique / Hotel", "Apartment / Airbnb", "Hostal", "Value for Money"], id: \.self) { style in
                                        Button { brief.stayStyle = style } label: { choicePill(style, selected: brief.stayStyle == style) }
                                    }
                                }
                            }
                            inputField("Budget", placeholder: "Ανά άτομο ή για όλη την ομάδα", text: $brief.budget)
                            inputField("Σημειώσεις", placeholder: "Προτιμήσεις, αποκλεισμοί, πρόσβαση…", text: $brief.notes, axis: .vertical)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Σύνδεση AI bridge")
                                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                                    .foregroundStyle(AppPalette.ink)
                                TextField("https://your-service.onrender.com", text: $bridgeHost)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .font(.custom("PlusJakartaSans-Medium", size: 13))
                                    .padding(.horizontal, 12)
                                    .frame(height: 44)
                                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
                                Text("Βάλε το πλήρες HTTPS URL του Render, χωρίς /api/status. Για τοπική σύνδεση, βάλε την IP του Mac στο ίδιο Wi‑Fi.")
                                    .font(.custom("PlusJakartaSans-Regular", size: 10))
                                    .foregroundStyle(AppPalette.secondaryInk)
                            }
                        }
                        .padding(.top, 14)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Παρέα και προτιμήσεις")
                                .font(.custom("PlusJakartaSans-Bold", size: 13))
                                .foregroundStyle(AppPalette.ink)
                            Text("\(brief.travelers) άτομα · \(brief.group) · \(brief.interests.count) ενδιαφέροντα")
                                .font(.custom("PlusJakartaSans-Regular", size: 11))
                                .foregroundStyle(AppPalette.secondaryInk)
                        }
                    }
                    .tint(AppPalette.accent)
                    .padding(15)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            VStack(spacing: 8) {
                Button {
                    startLiveResearch()
                } label: {
                    HStack(spacing: 9) {
                        Spacer()
                        if isResearching {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(isResearching ? "Έρευνα σε εξέλιξη..." : "Έναρξη έρευνας AI")
                            .font(.custom("PlusJakartaSans-Bold", size: 15))
                        if !isResearching {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(height: 54)
                    .background(isResearching ? AppPalette.secondaryInk : AppPalette.brand, in: Capsule())
                }
                .disabled(isResearching)
                .accessibilityLabel("Έναρξη ζωντανής έρευνας με τεχνητή νοημοσύνη")

                Button {
                    pendingPrompt = nil
                    showPromptSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                        Text("Χειροκίνητη αντιγραφή prompt")
                            .font(.custom("PlusJakartaSans-Medium", size: 11))
                    }
                    .foregroundStyle(AppPalette.secondaryInk)
                    .padding(.vertical, 4)
                }
                .disabled(isResearching)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AppPalette.canvas)
        }
        .background(AppPalette.canvas)
        .onChange(of: brief) { _, _ in saveDraft() }
    }

    private var stageProgress: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ΤΑΞΙΔΙ · BRIEF")
                    .font(.custom("PlusJakartaSans-Bold", size: 9))
                    .tracking(1.1)
                    .foregroundStyle(AppPalette.secondaryInk)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppPalette.secondaryInk.opacity(0.14))
                        Capsule()
                            .fill(AppPalette.brand)
                            .frame(width: geometry.size.width * briefProgress)
                    }
                }
                .frame(height: 4)
            }
            Text("02 / 03")
                .font(.custom("PlusJakartaSans-Bold", size: 10))
                .monospacedDigit()
                .foregroundStyle(AppPalette.secondaryInk)
                .contentTransition(.numericText())
        }
        .padding(.top, 9)
        .onAppear {
            briefProgress = 0
            withAnimation(.spring(response: 0.8, dampingFraction: 0.86).delay(0.12)) {
                briefProgress = 2.0 / 3.0
            }
        }
        .onDisappear { briefProgress = 0 }
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
        Text(title)
            .font(.custom("PlusJakartaSans-SemiBold", size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .foregroundStyle(selected ? AppPalette.ink : AppPalette.secondaryInk)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(selected ? Color(hex: "FFE0D2") : AppPalette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? AppPalette.accent : Color(hex: "EADFD5"), lineWidth: 1))
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
        List {
            Section {
                tripHero.environment(\.layoutDirection, .leftToRight)
                scheduleDayPicker.environment(\.layoutDirection, .leftToRight)
            }.listRowBackground(AppPalette.canvas)
            if let index = selectedScheduleDayIndex, dayRecords.indices.contains(index) {
                let day = dayRecords[index]
                let date = scheduleDateKey(day, index: index)
                let ids = scheduleIDs(day, index: index)
                Section {
                    dayMap(points: mapPoints(for: day, index: index), title: dayTitle(day, index: index))
                    if let alternative = recordValue(day, keys: ["alternative"]), !alternative.isEmpty {
                        Text(alternative).font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                    dayCostSummary(day)
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dayTitle(day, index: index)).font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                        Text(recordValue(day, keys: ["theme"]) ?? "Ημέρα χωρίς θεματική").font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    }.textCase(nil)
                }.listRowBackground(AppPalette.canvas)
                Section {
                    if ids.isEmpty {
                        Button { activeScheduleDate = date } label: {
                            Label("Πρόσθεσε επιλογές από το pool", systemImage: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.brand)
                        }.listRowBackground(AppPalette.surface)
                    } else {
                        ForEach(ids, id: \.self) { itemID in
                            scheduleRow(itemID: itemID, date: date, day: day)
                                .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(AppPalette.surface)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) { removeScheduleItem(itemID, date: date, day: day) } label: {
                                        Label("Διαγραφή", systemImage: "trash")
                                    }
                                    Button {
                                        if alternativePlaces(for: itemID).isEmpty { showToast("Δεν υπάρχουν άλλες επιλογές στο pool") }
                                        else { alternativesForItemID = itemID }
                                    } label: { Label("Αλλαγή", systemImage: "arrow.triangle.swap") }
                                        .tint(AppPalette.brand)
                                }
                        }
                        .onMove { offsets, destination in
                            var order = scheduleIDs(day, index: index)
                            order.move(fromOffsets: offsets, toOffset: destination)
                            withAnimation(.snappy(duration: 0.34)) { setScheduleOrder(order, date: date) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Στάσεις της ημέρας").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                        Spacer()
                        Button { activeScheduleDate = date } label: { Image(systemName: "plus.circle.fill").foregroundStyle(AppPalette.brand) }
                            .buttonStyle(.plain).accessibilityLabel("Πρόσθεσε στάση")
                    }.textCase(nil)
                }
            } else {
                Section { overviewDashboard.environment(\.layoutDirection, .leftToRight) }
                    .listRowBackground(AppPalette.canvas)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        // In RTL, SwiftUI's native onMove grip sits at the left; card content remains LTR.
        .environment(\.layoutDirection, .rightToLeft)
        .background(AppPalette.canvas)
    }

    private var scheduleDayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                scheduleTab("Επισκόπηση", subtitle: brief.destination, selected: selectedScheduleDayIndex == nil) {
                    withAnimation(.snappy(duration: 0.28)) { selectedScheduleDayIndex = nil }
                }
                ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                    scheduleTab("Ημέρα \(index + 1)", subtitle: recordValue(day, keys: ["date"]) ?? "", selected: selectedScheduleDayIndex == index) {
                        withAnimation(.snappy(duration: 0.28)) { selectedScheduleDayIndex = index }
                    }
                }
            }
        }.scrollClipDisabled()
    }
    private func scheduleTab(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom("PlusJakartaSans-Bold", size: 11))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 9, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(selected ? Color.white : AppPalette.ink)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(selected ? AppPalette.brand : AppPalette.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : AppPalette.secondaryInk.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private var overviewDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Σύνοψη ταξιδιού", systemImage: "sparkles").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                Text(overviewText).font(.custom("PlusJakartaSans-Regular", size: 12)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if let seasonal = (researchRoot["overview"] as? [String: Any])?["seasonal_notes"] as? [String] {
                    ForEach(seasonal, id: \.self) { note in Label(note, systemImage: "sun.max").font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true) }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17))
            mapContent
            analyticalCostTable
            budgetCalculator
            checklistContent
            sourcesSection
            ForEach(Array(dayRecords.enumerated()), id: \.offset) { index, day in
                Button { withAnimation(.snappy(duration: 0.28)) { selectedScheduleDayIndex = index } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dayTitle(day, index: index)).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                            Text(recordValue(day, keys: ["theme"]) ?? "Άνοιγμα ημερήσιου πλάνου").font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(AppPalette.brand)
                    }.padding(13).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }
    private func selectedDayPage(_ index: Int) -> some View {
        let day = dayRecords[index]
        let date = scheduleDateKey(day, index: index)
        let ids = scheduleIDs(day, index: index)
        let points = mapPoints(for: day, index: index)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle(day, index: index)).font(.custom("PlusJakartaSans-ExtraBold", size: 19)).foregroundStyle(AppPalette.ink)
                    Text(recordValue(day, keys: ["theme"]) ?? "Ημέρα χωρίς θεματική").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
                Button { activeScheduleDate = date } label: { Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(AppPalette.brand, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Πρόσθεσε στάση")
            }
            if let alternative = recordValue(day, keys: ["alternative"]), !alternative.isEmpty {
                Label(alternative, systemImage: "arrow.triangle.branch").font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 13))
            }
            dayMap(points: points, title: dayTitle(day, index: index))
            if ids.isEmpty {
                Button { activeScheduleDate = date } label: { Label("Πρόσθεσε επιλογές από το pool", systemImage: "plus.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.brand).frame(maxWidth: .infinity).padding(20).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16)) }
                    .buttonStyle(.plain)
            } else {
                activityList(ids: ids, date: date, day: day, dayIndex: index)
            }
            dayCostSummary(day)
        }
    }

    private func activityList(ids: [String], date: String, day: [String: Any], dayIndex: Int) -> some View {
        List {
            ForEach(ids, id: \.self) { itemID in
                scheduleRow(itemID: itemID, date: date, day: day)
                    .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppPalette.surface)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) { removeScheduleItem(itemID, date: date, day: day) } label: {
                            Label("Διαγραφή", systemImage: "trash")
                        }
                        Button {
                            if alternativePlaces(for: itemID).isEmpty { showToast("Δεν υπάρχουν άλλες επιλογές στο pool") }
                            else { alternativesForItemID = itemID }
                        } label: { Label("Αλλαγή", systemImage: "arrow.triangle.swap") }
                            .tint(AppPalette.brand)
                    }
            }
            .onMove { offsets, destination in
                var order = scheduleIDs(day, index: dayIndex)
                order.move(fromOffsets: offsets, toOffset: destination)
                withAnimation(.snappy(duration: 0.34)) { setScheduleOrder(order, date: date) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        // RTL places the system's native reorder grip on the left; row content stays LTR.
        .environment(\.layoutDirection, .rightToLeft)
        .scrollDisabled(true)
        .frame(height: ids.reduce(CGFloat.zero) { total, id in total + (expandedScheduleItemIDs.contains(id) ? 225 : 100) })
        .background(AppPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        let cost = day["estimated_day_cost_per_person_eur"]
        return HStack(spacing: 10) {
            Image(systemName: "eurosign.circle.fill").font(.title3).foregroundStyle(AppPalette.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text("Εκτίμηση ημέρας ανά άτομο").font(.custom("PlusJakartaSans-Bold", size: 11)).foregroundStyle(AppPalette.ink)
                Text(cost.map(readableValue) ?? "Δεν δόθηκε τεκμηριωμένο ποσό").font(.system(size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
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
        let stop = scheduledStop(itemID, day: day)
        let place = scheduledPlace(itemID, day: day)
        let edits = activeTrip?.scheduleEditsByItemID?[itemID]
        let time = edits?.time ?? recordValue(stop, keys: ["time", "start_time"]) ?? "Ώρα ελεύθερη"
        let name = place.flatMap(recordTitle) ?? stop.map(activityTitle) ?? "Προτεινόμενη στάση"
        let detail = [stop.map(recordSummary), place.flatMap { recordValue($0, keys: ["address", "area"]) }].compactMap { $0 }.joined(separator: " · ")
        let estimatedCost = edits?.costPerPerson ?? recordValue(stop, keys: ["estimated_cost_per_person_eur"])
        let price = place.map(priceLabel).flatMap { $0 == "Τιμή μη επιβεβαιωμένη" ? nil : $0 }
        let reaction = activeTrip?.reactionsByItemID?[itemID]
        let expanded = expandedScheduleItemIDs.contains(itemID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                if let place {
                    PlaceImage(title: recordTitle(place) ?? "Travel", imageURL: recordValue(place, keys: ["image_url", "photo_url"]))
                        .frame(width: 84, height: 76).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let imageURL = recordValue(stop, keys: ["image_url", "photo_url"]) {
                    PlaceImage(title: name, imageURL: imageURL).frame(width: 84, height: 76).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 22)).foregroundStyle(AppPalette.brand)
                        .frame(width: 84, height: 76).background(Color(hex: "F6EAE0"), in: RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink).lineLimit(2)
                    Text("\(time) · \(estimatedCost.map { "€\($0)/άτομο" } ?? price ?? "Τιμή άγνωστη")")
                        .font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(AppPalette.secondaryInk).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        if expanded { expandedScheduleItemIDs.remove(itemID) } else { expandedScheduleItemIDs.insert(itemID) }
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 21, weight: .regular)).foregroundStyle(AppPalette.brand).frame(width: 34, height: 38)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(expanded ? "Σύμπτυξη δραστηριότητας" : "Άνοιγμα δραστηριότητας")
            }.environment(\.layoutDirection, .leftToRight)
            if expanded {
                Rectangle().fill(AppPalette.secondaryInk.opacity(0.12)).frame(height: 1)
                HStack(spacing: 8) {
                    editField("Ώρα", text: scheduleEditBinding(itemID, field: .time), prompt: "09:30")
                    editField("Κόστος / άτομο (€)", text: scheduleEditBinding(itemID, field: .cost), prompt: "—", keyboard: .decimalPad)
                }
                Text(detail).font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let place { activityInsights(place) }
                HStack(spacing: 14) {
                    if place != nil || stop != nil {
                        let coordinate = place.flatMap(placeCoordinate) ?? stop.flatMap(coordinateFromRecord)
                        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                        let mapURL = coordinate.flatMap { URL(string: "https://maps.apple.com/?ll=\($0.latitude),\($0.longitude)&q=\(query)") } ?? URL(string: "https://maps.apple.com/?q=\(query),\(brief.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? brief.destination)")!
                        Link(destination: mapURL) { Label("Χάρτης", systemImage: "map").font(.custom("PlusJakartaSans-SemiBold", size: 10)) }
                    }
                    if let url = place.flatMap({ recordValue($0, keys: ["official_url", "source_url", "url"]) }).flatMap(URL.init(string:)) {
                        Link(destination: url) { Label("Πηγή", systemImage: "arrow.up.right").font(.custom("PlusJakartaSans-SemiBold", size: 10)) }
                    }
                    Spacer()
                    reactionButton("hand.thumbsup", selected: reaction == "like", label: "Μου αρέσει") { setReaction("like", for: itemID) }
                    reactionButton("hand.thumbsdown", selected: reaction == "dislike", label: "Δεν μου αρέσει") { setReaction("dislike", for: itemID) }
                }
                .environment(\.layoutDirection, .leftToRight)
                .tint(AppPalette.brand)
            }
        }
        .padding(11)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy(duration: 0.28), value: expanded)
    }

    private func activityInsights(_ place: [String: Any]) -> some View {
        let tags = place["tags"] as? [String] ?? []
        let dietary = place["dietary_options"] as? [String] ?? []
        let bestFor = place["best_for"] as? [String] ?? []
        let facts: [(String, String)] = [
            ("Βαθμολογία", ratingLabel(place)),
            ("Δημοτικότητα", recordValue(place, keys: ["popularity"]) ?? "—"),
            ("Διάρκεια", recordValue(place, keys: ["average_visit_minutes"]).map { "\($0) λεπτά" } ?? "—"),
            ("Καλύτερη ώρα", recordValue(place, keys: ["best_time"]) ?? "—"),
            ("Κράτηση", recordValue(place, keys: ["reservation_required"]) ?? "Δεν αναφέρθηκε")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.0.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                        Text(fact.1).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppPalette.ink).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            ForEach(Array([("Ταιριάζει σε", bestFor), ("Διατροφή", dietary), ("Tags", tags)].enumerated()), id: \.offset) { _, row in
                if !row.1.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.0).font(.system(size: 9, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
                        Text(row.1.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(AppPalette.ink).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let reason = recordValue(place, keys: ["why_recommended"]) {
                Text(reason).font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
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
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(AppPalette.secondaryInk)
            TextField(prompt, text: text).font(.system(size: 12, weight: .medium)).keyboardType(keyboard)
                .padding(9).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 10))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var analyticalCostTable: some View {
        let costs = researchRoot["costs"] as? [String: Any] ?? [:]
        let rows: [(String, String, String, String)] = [
            ("Σύνολο ταξιδιού", costAmount(costs["per_person_estimate"]), costAmount(costs["group_estimate"]), recordValue(costs, keys: ["methodology"]) ?? "Εκτίμηση βάσει των πηγών του research"),
            ("Διαμονή", costAmount((costs["lodging_estimate"] as? [String: Any])?["per_room_per_night_eur"]), costAmount((costs["lodging_estimate"] as? [String: Any])?["group_total_eur"]), recordValue(costs["lodging_estimate"], keys: ["note"]) ?? "Ανά δωμάτιο / διανυκτέρευση · σύνολο ομάδας"),
            ("Μεταφορές + αξιοθέατα", costAmount((costs["transport_and_attractions_subtotal"] as? [String: Any])?["per_person_eur"]), costAmount((costs["transport_and_attractions_subtotal"] as? [String: Any])?["group_eur"]), recordValue(costs["transport_and_attractions_subtotal"], keys: ["basis"]) ?? "Βάση υπολογισμού μη διαθέσιμη"),
            ("Φαγητό", costAmount((costs["food_estimate"] as? [String: Any])?["per_person_per_day_eur"]), costAmount((costs["food_estimate"] as? [String: Any])?["group_total_eur"]), recordValue(costs["food_estimate"], keys: ["basis"]) ?? "Ημερήσια εκτίμηση · ομάδα")
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Label("Ανάλυση κόστους", systemImage: "chart.bar.xaxis").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
            HStack {
                Text("Κατηγορία").frame(maxWidth: .infinity, alignment: .leading)
                Text("/ άτομο").frame(width: 76, alignment: .trailing)
                Text("Ομάδα").frame(width: 76, alignment: .trailing)
            }.font(.system(size: 9, weight: .bold)).foregroundStyle(AppPalette.secondaryInk)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(row.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppPalette.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.1).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(AppPalette.brand).frame(width: 76, alignment: .trailing)
                        Text(row.2).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(AppPalette.ink).frame(width: 76, alignment: .trailing)
                    }
                    Text(row.3).font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 6)
                if row.0 != rows.last?.0 { Divider().overlay(AppPalette.secondaryInk.opacity(0.1)) }
            }
            Text("Οι τιμές παραμένουν ενδεικτικές μέχρι να επιβεβαιωθούν από επίσημη πηγή.")
                .font(.system(size: 9)).foregroundStyle(AppPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
    private func costAmount(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        if let object = value as? [String: Any] {
            let min = object["min"].flatMap { $0 is NSNull ? nil : String(describing: $0) }
            let max = object["max"].flatMap { $0 is NSNull ? nil : String(describing: $0) }
            let currency = recordValue(object, keys: ["currency"]) ?? "EUR"
            if let min, let max { return min == max ? "€\(min)" : "€\(min)–\(max)" }
            if let perPerson = object["per_person_eur"] { return costAmount(perPerson) }
            if let perDay = object["per_person_per_day_eur"] { return "€\(readableValue(perDay))/day" }
            if let group = object["group_total_eur"] { return "€\(readableValue(group))" }
            return currency == "EUR" ? "—" : currency
        }
        return "€\(readableValue(value))"
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
        return VStack(alignment: .leading, spacing: 10) {
            if tickets.isEmpty { Text("Δεν δόθηκαν ξεχωριστές επιλογές εισιτηρίων.").font(.system(size: 12)).foregroundStyle(AppPalette.secondaryInk) }
            ForEach(Array(tickets.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(recordTitle(item) ?? "Επιλογή \(index + 1)").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                    Text([recordValue(item, keys: ["price_per_person_eur", "group_price_eur"]).map { "€\($0)" }, recordValue(item, keys: ["notes", "description"])].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(AppPalette.secondaryInk)
                    if let url = recordValue(item, keys: ["booking_url", "official_url"]).flatMap(URL.init(string:)) { Link("Επίσημη κράτηση", destination: url).font(.system(size: 11, weight: .semibold)) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
        }
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
                            PlaceImage(title: recordTitle(place) ?? "Travel", imageURL: recordValue(place, keys: ["image_url", "photo_url"]))
                                .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recordTitle(place) ?? "Επιλογή \(index + 1)").font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.ink)
                                Text("\(recordValue(place, keys: ["category", "type"]) ?? "Πρόταση") · \(ratingLabel(place))")
                                    .font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk)
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
                Section("Κοντινές επιλογές από το pool") {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { index, place in
                        Button {
                            replaceScheduleItem(itemID, with: place)
                            alternativesForItemID = nil
                        } label: {
                            HStack(spacing: 11) {
                                PlaceImage(title: recordTitle(place) ?? "Travel", imageURL: recordValue(place, keys: ["image_url", "photo_url"]))
                                    .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recordTitle(place) ?? "Επιλογή").font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.ink)
                                    Text(alternativeReason(place, for: current)).font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk)
                                    Text("\(priceLabel(place)) · \(ratingLabel(place))").font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(AppPalette.brand)
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
                        Label("Επέκταση pool με ChatGPT", systemImage: "sparkles")
                            .font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(AppPalette.brand)
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
        guard !current.contains(id) else { showToast("Αυτό το μέρος υπάρχει ήδη στην ημέρα"); return }
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
        if let id, let resolved = resolvedCoordinates[id] { return resolved }
        if let id, let stored = activeTrip?.mapCoordinatesByPlaceID?[id] { return stored.coordinate }
        let coordinates = place["coordinates"] as? [String: Any] ?? [:]
        guard let lat = numericValue(coordinates, keys: ["latitude", "lat"]), let lon = numericValue(coordinates, keys: ["longitude", "lng", "lon"]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
        VStack(alignment: .leading, spacing: 10) {
            PlaceImage(title: recordTitle(place) ?? "Travel", imageURL: recordValue(place, keys: ["image_url", "photo_url"]))
                .frame(height: 155).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordTitle(place) ?? "Επιλογή \(index + 1)")
                        .font(.custom("PlusJakartaSans-Bold", size: 14)).foregroundStyle(AppPalette.ink)
                    Text(recordValue(place, keys: ["category", "type", "kind", "cuisine"]) ?? "Πρόταση")
                        .font(.custom("PlusJakartaSans-SemiBold", size: 10)).foregroundStyle(AppPalette.accent)
                }
                Spacer()
                Text(ratingLabel(place))
                    .font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(AppPalette.brand)
            }
            Text(recordSummary(place)).font(.custom("PlusJakartaSans-Regular", size: 11)).foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let why = recordValue(place, keys: ["why_recommended", "best_for", "popularity"]) {
                Text(why).font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(AppPalette.brand).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Label(priceLabel(place), systemImage: "eurosign.circle")
                if let checked = recordValue(place, keys: ["checked_at", "last_verified"]) {
                    Label("Έλεγχος \(checked)", systemImage: "clock")
                }
            }
            .font(.custom("PlusJakartaSans-Medium", size: 10)).foregroundStyle(AppPalette.secondaryInk)
            if let tags = place["tags"] as? [String], !tags.isEmpty {
                Text(tags.prefix(5).joined(separator: " · "))
                    .font(.custom("PlusJakartaSans-Regular", size: 10)).foregroundStyle(AppPalette.secondaryInk)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if let url = recordValue(place, keys: ["image_url", "photo_url"]), let link = URL(string: url) {
                    Link(destination: link) {
                        Label("Εικόνα", systemImage: "photo").font(.custom("PlusJakartaSans-SemiBold", size: 10))
                    }
                }
                if let imageSource = recordValue(place, keys: ["image_source_url", "image_attribution_url"]), let link = URL(string: imageSource) {
                    Link("Απόδοση εικόνας", destination: link).font(.custom("PlusJakartaSans-SemiBold", size: 10))
                }
                if let source = recordValue(place, keys: ["official_url", "source_url", "url"]), let link = URL(string: source) {
                    Link(destination: link) {
                        Label("Πηγή", systemImage: "arrow.up.right").font(.custom("PlusJakartaSans-SemiBold", size: 10))
                    }
                }
                Spacer()
                Button { showToast("Η επιλογή κρατήθηκε στο ταξίδι") } label: {
                    Label("Κράτα", systemImage: "heart").font(.custom("PlusJakartaSans-Bold", size: 10))
                        .foregroundStyle(AppPalette.ink).padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Color(hex: "FFE0D2"), in: Capsule())
                }
            }
            .foregroundStyle(AppPalette.brand)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
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
            if back == .library {
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
                    if selected { selection.wrappedValue.remove(option) }
                    else { selection.wrappedValue.insert(option) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(selected ? 1 : 0)
                        Text(option)
                            .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(selected ? AppPalette.ink : AppPalette.secondaryInk)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(selected ? Color(hex: "FFE0D2") : AppPalette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(selected ? AppPalette.accent : Color(hex: "EADFD5"), lineWidth: selected ? 1 : 0.7))
                }
                .buttonStyle(.plain)
            }
        }
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
        let trip = Trip(brief: initialBrief)
        trips.insert(trip, at: 0)
        activeTripID = trip.id
        brief = trip.brief
        selectedCard = 0
        selectedScrollID = 0
        TripStorage.save(trips)
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
            if activeTripID == id { activeTripID = nil; brief = TripBrief() }
        }
        TripStorage.save(trips)
    }

    private func finishBriefReveal() {
        isRevealingBrief = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.9)) {
            briefReveal = 1
            cardDrag = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 500))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                stage = .brief
                briefReveal = 0
                gestureTripID = nil
                isRevealingBrief = false
            }
        }
    }

    private func openBrief() { withAnimation { stage = .brief } }

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
        trips[index].research = sourceToStore
        trips[index].brief = brief
        trips[index].updatedAt = .now
        TripStorage.save(trips)
        pendingPrompt = nil
        withAnimation { stage = .workspace }
    }

    private func startLiveResearch() {
        guard !isResearching else { return }
        isResearching = true
        liveResearchError = nil
        recoverableResearch = nil
        liveResearchStep = 1
        researchOperations = [ResearchOperation(step: 1, detail: "Αναζήτηση επίσημων πηγών, ωραρίων και αργιών…")]
        showLiveResearchSheet = true

        let briefContext: [String: Any] = [
            "destination": brief.destination.isEmpty ? "Ρώμη" : brief.destination,
            "date_range": [
                "arrival": brief.startDate.isEmpty ? "2026-09-10" : brief.startDate,
                "departure": brief.endDate.isEmpty ? "2026-09-14" : brief.endDate,
                "duration_days": brief.duration
            ],
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "budget": brief.budget,
            "dietary_needs": brief.dietaryNeeds.sorted(),
            "mobility_requirements": brief.mobility.sorted(),
            "stay_style": brief.stayStyle,
            "custom_instructions": brief.notes,
            "pace": pace < 0.34 ? "χαλαρός" : (pace > 0.66 ? "εντατικός" : "ισορροπημένος")
        ]

        liveResearchTask = Task {
            do {
                // Check compatibility before starting either paid AI request.
                guard let preflightURL = URL(string: "\(bridgeBaseURL)/api/status") else { throw URLError(.badURL) }
                var preflight = URLRequest(url: preflightURL, cachePolicy: .reloadIgnoringLocalCacheData)
                preflight.timeoutInterval = 60
                let (statusData, preflightResponse) = try await URLSession.shared.data(for: preflight)
                try Task.checkCancellation()
                guard let http = preflightResponse as? HTTPURLResponse, http.statusCode == 200,
                      let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any] else {
                    throw URLError(.badServerResponse)
                }
                guard (status["api_version"] as? Int ?? 0) >= 2,
                      status["result_schema"] as? String == "trippy-research-v1" else {
                    await MainActor.run {
                        if status["step"] as? String == "completed", let result = status["result"] as? [String: Any] {
                            recoverableResearch = result
                            recoveryContext = status["request_context"] as? [String: Any] ?? briefContext
                            researchOperations = []
                            liveResearchError = "Το Render τρέχει την παλιά έκδοση. Το τελευταίο αποτέλεσμα μπορεί να ανακτηθεί χωρίς νέα έρευνα. Χρειάζεται Deploy latest commit για νέες έρευνες."
                        } else {
                            liveResearchError = "Το Render τρέχει την παλιά έκδοση. Χρειάζεται Deploy latest commit πριν από νέα έρευνα. Δεν ξεκίνησε χρεώσιμη αναζήτηση."
                        }
                        isResearching = false
                    }
                    return
                }
                guard let url = URL(string: "\(bridgeBaseURL)/api/research") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: briefContext)

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 202 && http.statusCode != 200 {
                    if http.statusCode == 409 {
                        await MainActor.run {
                            liveResearchError = "Υπάρχει ήδη έρευνα σε εξέλιξη στην υπηρεσία. Περίμενε να ολοκληρωθεί και δοκίμασε ξανά."
                            isResearching = false
                        }
                    } else {
                        await MainActor.run {
                            liveResearchError = "Η υπηρεσία έρευνας επέστρεψε HTTP \(http.statusCode). Έλεγξε το URL και τα logs στο Render."
                            isResearching = false
                        }
                    }
                    return
                }

                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1.5))
                    guard let statusURL = URL(string: "\(bridgeBaseURL)/api/status") else { throw URLError(.badURL) }
                    let (data, statusResponse) = try await URLSession.shared.data(from: statusURL)
                    try Task.checkCancellation()
                    guard let http = statusResponse as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw URLError(.badServerResponse)
                    }

                    let isRunning = json["is_running"] as? Bool ?? false
                    let step = json["step"] as? String ?? ""
                    let msg = json["message"] as? String ?? ""
                    let result = json["result"] as? [String: Any]
                    let error = json["error"] as? String

                    await MainActor.run {
                        if step == "searching_web" { recordResearchOperation(1, detail: msg) }
                        else if step == "synthesizing_patch" { recordResearchOperation(2, detail: msg) }
                        else if step == "completed" {
                            recordResearchOperation(3, detail: msg)
                            if let result {
                                finishLiveResearch(result, context: briefContext)
                            } else {
                                liveResearchError = "Η υπηρεσία ολοκλήρωσε την έρευνα χωρίς έγκυρο αποτέλεσμα. Δοκίμασε ξανά."
                                isResearching = false
                            }
                        } else if step == "error" {
                            liveResearchError = error ?? "Προέκυψε σφάλμα κατά την έρευνα."
                            isResearching = false
                        }
                    }

                    if !isRunning && step == "completed" { break }
                    if step == "error" { break }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    liveResearchError = "Η σύνδεση με το bridge στο \(bridgeBaseURL) απέτυχε. Έλεγξε το URL και ότι η υπηρεσία είναι διαθέσιμη. Αν χρησιμοποιείς IP του Mac, οι συσκευές πρέπει να είναι στο ίδιο Wi‑Fi."
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

    private func finishLiveResearch(_ result: [String: Any], context: [String: Any], recover: Bool = false) {
        let document = recover ? Self.foundationFromLiveResult(result, context: context) : result
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              let text = String(data: data, encoding: .utf8) else {
            liveResearchError = "Το αποτέλεσμα δεν μπόρεσε να διαβαστεί."
            isResearching = false
            return
        }
        if recover, let destination = (document["trip_context"] as? [String: Any])?["destination"] as? String {
            brief.destination = destination
        }
        importText = text
        importError = nil
        importResearch()
        isResearching = false
        if let error = importError {
            liveResearchError = error
            importError = nil
        } else {
            recoverableResearch = nil
            showLiveResearchSheet = false
        }
    }

    private func recordResearchOperation(_ step: Int, detail: String) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)) {
            liveResearchStep = step
            if let index = researchOperations.firstIndex(where: { $0.step == step }) {
                researchOperations[index].detail = detail
            } else {
                researchOperations.append(ResearchOperation(step: step, detail: detail))
            }
        }
    }

    private var liveResearchSheet: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: liveResearchError != nil ? "exclamationmark" : (researchOperations.last?.symbol ?? "globe.europe.africa"))
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(AppPalette.brand)
                            .frame(width: 68, height: 68)
                            .background(AppPalette.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                            .contentTransition(.symbolEffect(.replace))
                        Text(brief.destination.isEmpty ? "Έρευνα προορισμού" : "Έρευνα για \(brief.destination)")
                            .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                            .foregroundStyle(AppPalette.ink)
                        Text(liveResearchError == nil ? "Το ταξίδι σου χτίζεται, βήμα βήμα." : "Η έρευνα χρειάζεται την προσοχή σου.")
                            .font(.custom("PlusJakartaSans-Regular", size: 13))
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(researchOperations) { operation in
                            researchOperationRow(operation)
                                .padding(.vertical, 16)
                                .id(operation.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                            if operation.id != researchOperations.last?.id {
                                Rectangle()
                                    .fill(AppPalette.brand.opacity(0.15))
                                    .frame(width: 2, height: 16)
                                    .padding(.leading, 19)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                    if let error = liveResearchError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.custom("PlusJakartaSans-Medium", size: 12))
                            .foregroundStyle(AppPalette.ink)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    Color.clear.frame(height: 1).id("researchBottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 20)
            }
            .onChange(of: researchOperations.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    proxy.scrollTo("researchBottom", anchor: .bottom)
                }
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    if let result = recoverableResearch {
                        let destination = (result["set"] as? [String: Any])?["destination"] as? String ?? "τελευταίου ταξιδιού"
                        Button { finishLiveResearch(result, context: recoveryContext, recover: true) } label: {
                            Text("Ανάκτηση αποτελέσματος · \(destination)")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                .foregroundStyle(Color.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(AppPalette.brand, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                    }
                HStack(spacing: 12) {
                    Button { cancelLiveResearch() } label: {
                        Text(isResearching ? "Κλείσιμο" : "Έγινε")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppPalette.surface, in: Capsule())
                    }
                    if liveResearchError != nil && !isResearching {
                        Button { startLiveResearch() } label: {
                            Text("Δοκιμή ξανά")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AppPalette.brand, in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(AppPalette.canvas)
                }
                .background(AppPalette.canvas)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isResearching)
    }

    private func researchOperationRow(_ operation: ResearchOperation) -> some View {
        let current = operation.step == liveResearchStep
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(current ? AppPalette.brand : AppPalette.brand.opacity(0.1))
                    .frame(width: 40, height: 40)
                if current && isResearching {
                    ProgressView().tint(Color.white)
                } else {
                    Image(systemName: current ? operation.symbol : "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(current ? Color.white : AppPalette.brand)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(operation.title)
                    .font(.custom("PlusJakartaSans-Bold", size: 15))
                    .foregroundStyle(AppPalette.ink)
                Text(operation.detail)
                    .font(.custom("PlusJakartaSans-Regular", size: 12))
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .opacity(current ? 1 : 0.5)
        .scaleEffect(current ? 1 : 0.97, anchor: .leading)
        .accessibilityElement(children: .combine)
    }

    private var calendarNightCount: Int {
        guard let start = calendarDate(from: calendarRangeStart),
              let end = calendarDate(from: calendarRangeEnd) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private var holidaysInSelectedRange: [DestinationHoliday] {
        guard let start = calendarDate(from: calendarRangeStart),
              let end = calendarDate(from: calendarRangeEnd) else { return [] }
        return calendarHolidays.filter { holiday in
            guard let date = calendarDate(from: holiday.date) else { return false }
            return date >= start && date <= end
        }.sorted { ($0.date.month ?? 0, $0.date.day ?? 0) < ($1.date.month ?? 0, $1.date.day ?? 0) }
    }

    private var calendarPickerSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ημερομηνίες ταξιδιού")
                        .font(.custom("PlusJakartaSans-ExtraBold", size: 25))
                        .foregroundStyle(AppPalette.ink)
                    Text(resolvedDestination.isEmpty ? brief.title : resolvedDestination)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                HStack(spacing: 12) {
                    calendarSelectionLabel("ΑΦΙΞΗ", components: calendarRangeStart, active: calendarRangeStart == nil)
                    Image(systemName: "arrow.right").foregroundStyle(AppPalette.secondaryInk)
                    calendarSelectionLabel("ΑΝΑΧΩΡΗΣΗ", components: calendarRangeEnd, active: calendarRangeStart != nil && calendarRangeEnd == nil)
                }
                .padding(15)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18))

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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(Array(daysForDisplayedMonth().enumerated()), id: \.offset) { _, day in
                            if let day { calendarDayButton(day) }
                            else { Color.clear.frame(height: 44) }
                        }
                    }
                }
                .padding(15)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 22))

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
        .background(AppPalette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Text(calendarRangeStart == nil ? "Διάλεξε ημερομηνία άφιξης" : (calendarRangeEnd == nil ? "Τώρα διάλεξε αναχώρηση" : "\(calendarNightCount) διανυκτερεύσεις · \(calendarNightCount + 1) ημέρες"))
                    .font(.custom("PlusJakartaSans-SemiBold", size: 12))
                    .foregroundStyle(AppPalette.secondaryInk)
                HStack(spacing: 12) {
                    Button("Άκυρο") { showCalendarPicker = false }
                        .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                        .foregroundStyle(AppPalette.ink)
                        .frame(width: 90, height: 48)
                        .background(AppPalette.surface, in: Capsule())
                    Button {
                        if let start = calendarDate(from: calendarRangeStart), let end = calendarDate(from: calendarRangeEnd) {
                            brief.startDate = isoDate(start)
                            brief.endDate = isoDate(end)
                            brief.dateIsUnknown = false
                            brief.duration = max(1, calendarNightCount + 1)
                        }
                        showCalendarPicker = false
                    } label: {
                        Text("Εφαρμογή ημερομηνιών")
                            .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppPalette.brand, in: Capsule())
                    }
                    .disabled(calendarRangeStart == nil || calendarRangeEnd == nil)
                    .opacity(calendarRangeStart == nil || calendarRangeEnd == nil ? 0.45 : 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppPalette.canvas)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { loadHolidays(for: brief.destination) }
    }

    private func calendarSelectionLabel(_ title: String, components: DateComponents?, active: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.custom("PlusJakartaSans-SemiBold", size: 9))
                .tracking(1)
                .foregroundStyle(active ? AppPalette.brand : AppPalette.secondaryInk)
            if let date = calendarDate(from: components) {
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
            withAnimation(.easeInOut(duration: 0.2)) {
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
        calendarHolidays.filter { holiday in
            guard let date = calendarDate(from: holiday.date) else { return false }
            return Calendar.current.isDate(date, equalTo: calendarDisplayedMonth, toGranularity: .month)
        }.sorted { ($0.date.day ?? 0) < ($1.date.day ?? 0) }
    }

    private func calendarDayButton(_ date: Date) -> some View {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let isStart = components == calendarRangeStart
        let isEnd = components == calendarRangeEnd
        let isInRange: Bool = {
            guard let start = calendarDate(from: calendarRangeStart),
                  let end = calendarDate(from: calendarRangeEnd) else { return false }
            return date >= start && date <= end
        }()
        let holiday = calendarHolidays.first { holiday in
            guard let holidayDate = calendarDate(from: holiday.date) else { return false }
            return Calendar.current.isDate(date, inSameDayAs: holidayDate)
        }
        return Button {
            if calendarRangeStart == nil || calendarRangeEnd != nil {
                calendarRangeStart = components
                calendarRangeEnd = nil
            } else if let start = calendarDate(from: calendarRangeStart), date < start {
                calendarRangeStart = components
            } else {
                calendarRangeEnd = components
            }
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

    private func calendarDate(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        return Calendar.current.date(from: components)
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
            guard let coordinate = place.flatMap(placeCoordinate) ?? stop.flatMap(coordinateFromRecord) else { return nil }
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
        guard !isResolvingCoordinates else { return }
        isResolvingCoordinates = true
        defer { isResolvingCoordinates = false }
        if destinationCoordinate == nil, !brief.destination.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = brief.destination
            if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
                destinationCoordinate = item.placemark.coordinate
            }
        }
        for (id, stored) in activeTrip?.mapCoordinatesByPlaceID ?? [:] { resolvedCoordinates[id] = stored.coordinate }
        for place in placeRecords {
            guard placeCoordinate(place) == nil, let id = recordValue(place, keys: ["id", "place_id"]),
                  let name = recordTitle(place) else { continue }
            let address = recordValue(place, keys: ["address", "area", "neighborhood"])
            let query = [name, address, brief.destination].compactMap { $0 }.joined(separator: ", ")
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let response = try? await MKLocalSearch(request: request).start(), let item = response.mapItems.first {
                resolvedCoordinates[id] = item.placemark.coordinate
                storeResolvedCoordinate(id: id, coordinate: item.placemark.coordinate)
            }
            try? await Task.sleep(for: .milliseconds(250))
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
        let rating = place["rating"] as? [String: Any]
        guard let value = rating?["value"], !(value is NSNull) else { return "—" }
        let count = rating?["review_count"].flatMap { $0 is NSNull ? nil : String(describing: $0) }
        return count.map { "\(value) · \($0)" } ?? String(describing: value)
    }
    private func priceLabel(_ place: [String: Any]) -> String {
        guard let price = place["price"] as? [String: Any] else {
            return recordValue(place, keys: ["price", "cost", "price_range"]) ?? "Τιμή μη επιβεβαιωμένη"
        }
        let min = price["min"].flatMap { $0 is NSNull ? nil : String(describing: $0) }
        let max = price["max"].flatMap { $0 is NSNull ? nil : String(describing: $0) }
        let currency = recordValue(price, keys: ["currency"]) ?? "EUR"
        if let min, let max { return min == max ? "\(min) \(currency)" : "\(min)–\(max) \(currency)" }
        return "Τιμή μη επιβεβαιωμένη"
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                content.glassEffect(.regular.interactive(), in: Circle())
            case .capsule:
                content.glassEffect(.regular.interactive(), in: Capsule())
            case .rounded:
                content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
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
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(), "interests": brief.interests.sorted(),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
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
            "travelers": ["count": brief.travelers, "group": brief.group],
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
            "budget_context": brief.budget.isEmpty ? NSNull() : brief.budget as Any,
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
            "vibes": brief.vibes.sorted(),
            "interests": brief.interests.sorted(),
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
