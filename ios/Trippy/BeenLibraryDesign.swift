import SwiftUI
import MapKit
import UIKit

// A snapshot is rebuilt on storage changes, never while the globe is moving.
struct BeenPassportSnapshot {
    let revision = UUID()
    let visits: [VisitedPlace]
    let countries: [VisitedCountryGroup]
    let continents: [String]
    let years: [Int]
    init(_ visits: [VisitedPlace] = []) {
        self.visits = visits.sorted { $0.visitedAt == $1.visitedAt ? $0.id < $1.id : $0.visitedAt > $1.visitedAt }
        countries = VisitedCountryGroup.groups(visits).filter { $0.countryCode != nil }
        continents = Set(visits.map { WorldContinentCatalog.name(for: $0.countryCode) }).filter { $0 != "Other" }.sorted()
        years = Set(visits.map { Calendar.current.component(.year, from: $0.visitedAt) }).sorted(by: >)
    }
    var countryCount: Int { countries.count }
    func countries(in continent: String?) -> [VisitedCountryGroup] {
        countries.filter { continent == nil || WorldContinentCatalog.name(for: $0.countryCode) == continent }
    }
    var shareText: String { "Been to · Trippy · \(countryCount) countries & regions · \(visits.count) cities · \(continents.count) continents" }
}

enum BeenCollection: String, Identifiable, CaseIterable {
    case countries, continents, cities, timeline, flags, milestones
    var id: String { rawValue }
    var title: String {
        switch self {
        case .countries: "Countries"
        case .continents: "Continents"
        case .cities: "Cities"
        case .timeline: "Timeline"
        case .flags: "Flags"
        case .milestones: "Milestones"
        }
    }
    var symbol: String {
        switch self {
        case .countries: "globe.europe.africa"
        case .continents: "globe.americas"
        case .cities: "building.2"
        case .timeline: "clock.arrow.circlepath"
        case .flags: "flag"
        case .milestones: "seal"
        }
    }
}

enum BeenPalette {
    static let amber = Color(red: 0.94, green: 0.66, blue: 0.24)
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? amber : Color(red: 0.57, green: 0.31, blue: 0.045)
    }
    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.07, green: 0.075, blue: 0.08) : Color(red: 0.965, green: 0.95, blue: 0.92)
    }
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.95, green: 0.94, blue: 0.90) : Color(red: 0.18, green: 0.17, blue: 0.14) }
    static func secondary(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(scheme == .dark ? 0.62 : 0.65) }
}

struct BeenGlassSurface: ViewModifier {
    var radius: CGFloat = 28
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}
struct BeenGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) { GlassEffectContainer(spacing: 12) { content() } }
        else { content() }
    }
}
struct BeenRoundButton: View {
    let symbol: String
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Circle())
                .modifier(BeenGlassSurface(radius: 22))
        }.buttonStyle(BeenHapticStyle()).accessibilityLabel(title)
    }
}

private struct BeenHapticStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { TrippyHaptics.light() } }
    }
}

struct BeenAddVisitButton: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.06)).frame(width: 46, height: 46)
                .background(LinearGradient(colors: [Color(red: 1, green: 0.81, blue: 0.5), Color(red: 0.94, green: 0.57, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 7, x: 4, y: 5)
                .shadow(color: Color.white.opacity(scheme == .dark ? 0.06 : 0.8), radius: 5, x: -3, y: -3)
        }.buttonStyle(BeenHapticStyle()).accessibilityLabel("Add a visit")
    }
}

struct BeenPassportSummary: View {
    let snapshot: BeenPassportSnapshot
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                metric(snapshot.countryCount, "countries & regions")
                Rectangle().fill(BeenPalette.ink(scheme).opacity(0.1)).frame(width: 1, height: 36).padding(.horizontal, 14)
                metric(snapshot.visits.count, "cities")
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(BeenPalette.ink(scheme).opacity(0.09), lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(snapshot.continents.count) / 6)
                        .stroke(BeenPalette.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(snapshot.continents.count)/6").font(.custom("PlusJakartaSans-Bold", size: 16)).monospacedDigit()
                        Text("continents").font(.system(size: 9, weight: .medium)).foregroundStyle(BeenPalette.secondary(scheme))
                    }
                }.frame(width: 62, height: 62).accessibilityElement(children: .ignore).accessibilityLabel("\(snapshot.continents.count) of 6 continents")
            }
        }.padding(22).foregroundStyle(BeenPalette.ink(scheme)).beenSurface(radius: 26)
    }
    private func metric(_ number: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(number.formatted()).font(.custom("PlusJakartaSans-ExtraBold", size: 30)).tracking(-1).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme))
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(BeenPalette.secondary(scheme))
        }
    }
}
struct BeenShortcut: View {
    let title: String
    let symbol: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
                HStack(spacing: 2) {
                    Text(title).font(.custom("PlusJakartaSans-Bold", size: 11, relativeTo: .caption)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).opacity(0.45)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).frame(minHeight: 96).beenSurface(radius: 20)
        }.buttonStyle(BeenHapticStyle())
    }
}
struct BeenCollectionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let value: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
                    .frame(width: 40, height: 40).beenSurface(radius: 14, inset: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(BeenPalette.secondary(scheme)) }
                }
                Spacer(minLength: 8)
                Text(value).font(.custom("PlusJakartaSans-Bold", size: 16)).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(BeenPalette.secondary(scheme))
            }.padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(BeenHapticStyle())
    }
}

enum BeenContinentName {
    static let all = ["Europe", "Africa", "Asia", "North America", "South America", "Oceania"]
    static func symbol(_ name: String) -> String {
        switch name {
        case "Europe", "Africa": "globe.europe.africa.fill"
        case "Asia", "Oceania": "globe.asia.australia.fill"
        default: "globe.americas.fill"
        }
    }
    static func center(_ name: String) -> CLLocationCoordinate2D {
        switch name {
        case "Europe": .init(latitude: 50, longitude: 15)
        case "Africa": .init(latitude: 2, longitude: 20)
        case "Asia": .init(latitude: 32, longitude: 100)
        case "North America": .init(latitude: 42, longitude: -100)
        case "South America": .init(latitude: -20, longitude: -60)
        default: .init(latitude: -24, longitude: 145)
        }
    }
    static func title(_ name: String) -> String {
        switch name {
        case "Europe": "Europe"
        case "Asia": "Asia"
        case "Africa": "Africa"
        case "North America": "N. America"
        case "South America": "S. America"
        case "Oceania": "Oceania"
        default: "Other"
        }
    }
}

struct BeenSheetFrame<Content: View>: View {
    let title: String
    var subtitle = ""
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.custom("PlusJakartaSans-Bold", size: 30, relativeTo: .title)).tracking(-1).fixedSize(horizontal: false, vertical: true)
                        if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(BeenPalette.secondary(scheme)).fixedSize(horizontal: false, vertical: true) }
                    }
                    content()
                }.padding(22).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize).background(BeenPalette.base(scheme).ignoresSafeArea())
                .foregroundStyle(BeenPalette.ink(scheme)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }.tint(BeenPalette.accent(scheme)).presentationDragIndicator(.visible)
    }
}
struct BeenEmptyPassport: View {
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "globe.europe.africa").font(.system(size: 32, weight: .light)).foregroundStyle(BeenPalette.accent(scheme))
            Text("Your first city starts here.").font(.custom("PlusJakartaSans-Bold", size: 20)).fixedSize(horizontal: false, vertical: true)
            Button(action: action) { Label("Add a city", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent).tint(BeenPalette.accent(scheme))
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).beenSurface(radius: 26)
    }
}
struct BeenCountryRow: View {
    let group: VisitedCountryGroup
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    /// "3 cities · 2019–2024 · Europe"
    private var summary: String {
        let years = group.visits.map { Calendar.current.component(.year, from: $0.visitedAt) }
        let span = years.min().map { first in years.max().map { $0 == first ? String(first) : "\(first)–\($0)" } ?? String(first) } ?? ""
        return ["\(group.visits.count) \(group.visits.count == 1 ? "city" : "cities")", span, BeenContinentName.title(WorldContinentCatalog.name(for: group.countryCode))]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(WorldGlobeView.flag(group.countryCode)).font(.system(size: 30)).frame(width: 48, height: 48).beenSurface(radius: 16, inset: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name).font(.custom("PlusJakartaSans-Bold", size: 16)).fixedSize(horizontal: false, vertical: true)
                    Text(summary).font(.system(size: 12)).foregroundStyle(BeenPalette.secondary(scheme)).lineLimit(2)
                }
                Spacer(minLength: 6)
                Text(group.visits.count.formatted()).font(.custom("PlusJakartaSans-Bold", size: 19)).monospacedDigit().foregroundStyle(BeenPalette.accent(scheme))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(BeenPalette.secondary(scheme))
            }.padding(16).beenSurface(radius: 23)
        }.buttonStyle(BeenHapticStyle())
    }
}
struct BeenVisitRow: View {
    let place: VisitedPlace
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(WorldGlobeView.flag(place.countryCode)).font(.system(size: 25)).frame(width: 42, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name).font(.custom("PlusJakartaSans-Bold", size: 16)).fixedSize(horizontal: false, vertical: true)
                    Text(place.countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } ?? "Unknown country")
                        .font(.system(size: 11)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(place.visitedAt, format: .dateTime.day().month(.abbreviated)).font(.system(size: 11, weight: .semibold))
                    Text(place.visitedAt, format: .dateTime.year()).font(.custom("PlusJakartaSans-Bold", size: 13)).foregroundStyle(BeenPalette.accent(scheme))
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(BeenPalette.secondary(scheme))
            }.padding(16).frame(minHeight: 82).beenSurface(radius: 22)
        }.buttonStyle(BeenHapticStyle())
    }
}
struct BeenCollectionSheet: View {
    let collection: BeenCollection
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @State private var snapshot = BeenPassportSnapshot()
    @State private var country: VisitedCountryGroup?
    @State private var city: VisitedPlace?
    @State private var showAdd = false
    @State private var chronology = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        BeenSheetFrame(title: collection.title, subtitle: subtitle) {
            if snapshot.visits.isEmpty && collection != .milestones {
                BeenEmptyPassport { showAdd = true }
            } else {
                content
            }
        }.presentationDetents([.large])
            .onAppear { reload() }.onChange(of: storage) { _, _ in reload() }
            .sheet(item: $country) { WorldCountryVisitsView(group: $0) }
            .sheet(item: $city) { BeenVisitDetail(place: $0) }
            .sheet(isPresented: $showAdd) { VisitedPlacePicker() }
    }
    private var subtitle: String {
        switch collection {
        case .countries: "\(snapshot.countryCount) countries · \(Int((Double(snapshot.countryCount) / 195 * 100).rounded()))% of the world"
        case .continents: "\(snapshot.continents.count) of 6 continents"
        case .cities: "\(snapshot.visits.count) cities, newest first"
        case .timeline: "\(snapshot.years.count) years of travel"
        case .flags: "\(snapshot.countryCount) flags"
        case .milestones: "Goals you’ve reached and what’s next"
        }
    }
    @ViewBuilder private var content: some View {
        switch collection {
        case .countries:
            LazyVStack(spacing: 12) { ForEach(snapshot.countries) { group in BeenCountryRow(group: group) { country = group } } }
        case .cities:
            LazyVStack(spacing: 12) { ForEach(snapshot.visits) { place in BeenVisitRow(place: place) { city = place } } }
        case .continents:
            VStack(spacing: 18) {
                ForEach(["Europe", "Asia", "Africa", "North America", "South America", "Oceania"], id: \.self) { continent in
                    let groups = snapshot.countries(in: continent)
                    let total = WorldContinentCatalog.count(continent)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ContinentIcon(name: continent, size: 40, selected: !groups.isEmpty)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BeenContinentName.title(continent)).font(.custom("PlusJakartaSans-Bold", size: 20))
                                Text("\(groups.count) of \(total) countries · \(groups.reduce(0) { $0 + $1.visits.count }) cities")
                                    .font(.system(size: 12)).foregroundStyle(BeenPalette.secondary(scheme))
                            }
                            Spacer()
                            ProgressRing(value: Double(groups.count) / Double(max(total, 1)), label: "\(Int((Double(groups.count) / Double(max(total, 1)) * 100).rounded()))%")
                        }
                        if groups.isEmpty { Text("Not visited yet.").font(.subheadline).foregroundStyle(BeenPalette.secondary(scheme)) }
                        ForEach(groups) { group in BeenCountryRow(group: group) { country = group } }
                    }.padding(18).beenSurface(radius: 26, inset: true)
                }
            }
        case .timeline:
            VStack(alignment: .leading, spacing: 22) {
                Picker("Timeline view", selection: $chronology) {
                    Text("By year").tag(false)
                    Text("Chronology").tag(true)
                }.pickerStyle(.segmented)
                if chronology {
                    LazyVStack(spacing: 12) {
                        ForEach(snapshot.visits.reversed()) { place in BeenVisitRow(place: place) { city = place } }
                    }
                } else {
                    ForEach(snapshot.years, id: \.self) { year in
                        let visits = snapshot.visits.filter { Calendar.current.component(.year, from: $0.visitedAt) == year }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(String(year)).font(.custom("PlusJakartaSans-ExtraBold", size: 34)).tracking(-1).foregroundStyle(BeenPalette.accent(scheme))
                                Spacer()
                                Text("\(visits.count) cities").font(.caption).foregroundStyle(BeenPalette.secondary(scheme))
                            }.padding(.horizontal, 4)
                            ForEach(visits) { place in BeenVisitRow(place: place) { city = place } }
                        }
                    }
                }
            }
        case .flags:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(snapshot.countries) { group in
                    Button { country = group } label: {
                        VStack(spacing: 12) {
                            Text(WorldGlobeView.flag(group.countryCode)).font(.system(size: 52))
                            Text(group.name).font(.custom("PlusJakartaSans-Bold", size: 14)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Text("\(group.visits.count) cities").font(.system(size: 11)).foregroundStyle(BeenPalette.secondary(scheme))
                        }.frame(maxWidth: .infinity).frame(minHeight: 148).padding(14).beenSurface(radius: 24)
                    }.buttonStyle(BeenHapticStyle())
                }
            }
        case .milestones:
            VStack(spacing: 14) {
                milestone("First steps", subtitle: "Your first city", symbol: "shoeprints.fill", count: snapshot.visits.count, target: 1)
                milestone("City collector", subtitle: "10 different cities", symbol: "building.2.fill", count: snapshot.visits.count, target: 10)
                milestone("Across borders", subtitle: "5 countries or regions", symbol: "globe.europe.africa.fill", count: snapshot.countryCount, target: 5)
                milestone("A bigger world", subtitle: "3 continents", symbol: "globe.americas.fill", count: snapshot.continents.count, target: 3)
                milestone("World citizen", subtitle: "All 6 continents", symbol: "seal.fill", count: snapshot.continents.count, target: 6)
            }
        }
    }
    private func milestone(_ title: String, subtitle: String, symbol: String, count: Int, target: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(count >= target ? BeenPalette.accent(scheme) : BeenPalette.secondary(scheme))
                    .frame(width: 48, height: 48).beenSurface(radius: 18, inset: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.custom("PlusJakartaSans-Bold", size: 16))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 4)
                if count >= target { Image(systemName: "checkmark.seal.fill").foregroundStyle(BeenPalette.amber) }
            }
            ProgressView(value: Double(min(count, target)), total: Double(target)).tint(BeenPalette.amber)
            Text(count >= target ? "Visited." : "\(min(count, target)) / \(target)").font(.system(size: 11, weight: .semibold)).foregroundStyle(BeenPalette.secondary(scheme))
        }.padding(20).beenSurface(radius: 26)
    }
    private func reload() { snapshot = BeenPassportSnapshot(VisitedPlace.decode(storage)) }
}

struct BeenVisitDetail: View {
    let place: VisitedPlace
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var date = Date()
    @State private var confirmDelete = false
    var body: some View {
        BeenSheetFrame(title: place.name, subtitle: "\(WorldGlobeView.flag(place.countryCode))  \(place.countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } ?? "Unknown country")") {
            VStack(alignment: .leading, spacing: 18) {
                Label("I was here", systemImage: "checkmark.seal.fill").font(.custom("PlusJakartaSans-Bold", size: 19)).foregroundStyle(BeenPalette.accent(scheme))
                DatePicker("Visit date", selection: $date, in: ...Date(), displayedComponents: .date)
                    .font(.subheadline).tint(BeenPalette.accent(scheme))
                Button("Save date", systemImage: "checkmark") {
                    var visits = VisitedPlace.decode(storage)
                    if let index = visits.firstIndex(where: { $0.id == place.id }) { visits[index].visitedAt = date; storage = VisitedPlace.encode(visits) }
                    dismiss()
                }.buttonStyle(.borderedProminent).tint(BeenPalette.accent(scheme))
            }.padding(22).beenSurface(radius: 26)
            Button { openMap() } label: { Label("Open in Apple Maps", systemImage: "map").frame(maxWidth: .infinity, minHeight: 50) }
                .buttonStyle(.bordered).tint(BeenPalette.accent(scheme))
            Button("Remove visit", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.presentationDetents([.medium, .large])
            .onAppear { date = VisitedPlace.decode(storage).first(where: { $0.id == place.id })?.visitedAt ?? place.visitedAt }
            .confirmationDialog("Remove visit to \(place.name);", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove visit", role: .destructive) { storage = VisitedPlace.encode(VisitedPlace.decode(storage).filter { $0.id != place.id }); dismiss() }
            }
    }
    private func openMap() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); item.name = place.name; item.openInMaps()
    }
}

struct BeenVisitSearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let loading: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium)).foregroundStyle(BeenPalette.accent(scheme))
            TextField("City or place", text: $query).font(.custom("PlusJakartaSans-Medium", size: 17))
                .autocorrectionDisabled().submitLabel(.search).focused(focused)
                .accessibilityLabel("Search city or place")
            if loading { ProgressView().controlSize(.small).tint(BeenPalette.accent(scheme)).accessibilityLabel("Search") }
            if !query.isEmpty {
                Button { query = ""; focused.wrappedValue = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(BeenPalette.secondary(scheme)).frame(width: 28, height: 36)
                }.buttonStyle(BeenHapticStyle()).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 18).frame(height: 60)
            .modifier(BeenSearchGlass(focused: focused.wrappedValue))
    }
}
struct BeenSearchGlass: ViewModifier {
    let focused: Bool
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(BeenPalette.amber.opacity(focused ? 0.09 : 0.025)).interactive(), in: RoundedRectangle(cornerRadius: 23))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
                .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(BeenPalette.accent(scheme).opacity(focused ? 0.38 : 0.1), lineWidth: 1))
        }
    }
}
struct BeenSearchPrompt: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(BeenPalette.accent(scheme).opacity(0.8))
            Text("Where have you been?").font(.custom("PlusJakartaSans-Bold", size: 18))
            Text("Find a city and add it with a tap.").font(.system(size: 13)).multilineTextAlignment(.center).lineSpacing(4).foregroundStyle(BeenPalette.secondary(scheme))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 20)
    }
}
struct BeenVisitSearchResult: View {
    let place: VisitedPlace
    let recorded: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(WorldGlobeView.flag(place.countryCode)).font(.system(size: 28)).frame(width: 48, height: 48).beenSurface(radius: 17, inset: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.name).font(.custom("PlusJakartaSans-Bold", size: 17)).fixedSize(horizontal: false, vertical: true)
                    Text(place.countryCode.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) } ?? "Region")
                        .font(.system(size: 12)).foregroundStyle(BeenPalette.secondary(scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: recorded ? "checkmark" : "plus").font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34).foregroundStyle(recorded ? BeenPalette.secondary(scheme) : BeenPalette.accent(scheme))
                    .background(BeenPalette.amber.opacity(recorded ? 0.05 : 0.16), in: Circle())
            }.padding(16).frame(minHeight: 88).beenSurface(radius: 24)
        }.buttonStyle(BeenHapticStyle()).disabled(recorded)
            .accessibilityLabel("\(place.name), \(place.countryCode ?? "") · \(recorded ? "Already visited" : "Add visit")")
    }
}

struct BeenRaisedSurface: ViewModifier {
    let radius: CGFloat
    let inset: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let highlight = scheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.16) : Color(red: 0.995, green: 0.987, blue: 0.965)
        content.background {
            shape.fill(LinearGradient(colors: [highlight, BeenPalette.base(scheme)], startPoint: inset ? .bottomTrailing : .topLeading, endPoint: inset ? .topLeading : .bottomTrailing))
        }
        .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.07 : 0.7), lineWidth: 0.8))
        .shadow(color: .white.opacity(scheme == .dark ? 0.02 : 0.65), radius: inset ? 2 : 4, x: -2, y: -2)
        .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.055), radius: inset ? 2 : 5, x: 2, y: 3)
    }
}
extension View {
    func beenSurface(radius: CGFloat = 24, inset: Bool = false) -> some View { modifier(BeenRaisedSurface(radius: radius, inset: inset)) }
}

struct BeenPassportContents: View {
    let snapshot: BeenPassportSnapshot
    var selectedContinent: String? = nil
    var boundaryUnavailable = false
    var onCollection: (BeenCollection) -> Void
    var onCountry: (VisitedCountryGroup) -> Void
    var onAdd: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
                    VStack(alignment: .leading, spacing: 18) {
                        BeenPassportSummary(snapshot: snapshot)
                        HStack(spacing: 10) {
                            BeenShortcut(title: "Timeline", symbol: "clock.arrow.circlepath") { onCollection(.timeline) }
                            BeenShortcut(title: "Flags", symbol: "flag") { onCollection(.flags) }
                            BeenShortcut(title: "Milestones", symbol: "seal") { onCollection(.milestones) }
                        }
                        VStack(spacing: 0) {
                            BeenCollectionRow(title: "Countries", subtitle: "", symbol: "globe.europe.africa", value: snapshot.countryCount.formatted()) { onCollection(.countries) }
                            Divider().opacity(0.4)
                            BeenCollectionRow(title: "Continents", subtitle: "", symbol: "globe.americas", value: "\(snapshot.continents.count)/6") { onCollection(.continents) }
                            Divider().opacity(0.4)
                            BeenCollectionRow(title: "Cities", subtitle: "", symbol: "building.2", value: snapshot.visits.count.formatted()) { onCollection(.cities) }
                        }.padding(.horizontal, 16).beenSurface(radius: 24, inset: true)
                        if let continent = selectedContinent {
                            Text(BeenContinentName.title(continent)).font(.custom("PlusJakartaSans-Bold", size: 20))
                            ForEach(snapshot.countries(in: continent)) { group in
                                BeenCountryRow(group: group) { onCountry(group) }
                            }
                        }
                        if snapshot.visits.isEmpty {
                            BeenEmptyPassport { onAdd() }
                        }
                        Text(boundaryUnavailable ? "Some outlines are unavailable. Your visits are saved." : "Apple Maps · geoBoundaries")
                            .font(.system(size: 10)).foregroundStyle(BeenPalette.secondary(scheme)).lineSpacing(4).padding(.horizontal, 4)
                    }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 28)
    }
}

struct BeenClusterSelection: Identifiable {
    let id = UUID()
    let visits: [VisitedPlace]
}
struct BeenClusterCitiesSheet: View {
    let selection: BeenClusterSelection
    @AppStorage("trippy.native.visitedPlaces.v1") private var storage = "[]"
    @State private var visits: [VisitedPlace] = []
    @State private var selectedVisit: VisitedPlace?
    var body: some View {
        BeenSheetFrame(title: "Cities here", subtitle: "\(visits.count) visits in this area.") {
            LazyVStack(spacing: 12) {
                ForEach(visits) { place in BeenVisitRow(place: place) { selectedVisit = place } }
            }
        }.presentationDetents([.medium, .large]).sheet(item: $selectedVisit) { BeenVisitDetail(place: $0) }
            .onAppear { reload() }.onChange(of: storage) { _, _ in reload() }
    }
    private func reload() {
        let ids = Set(selection.visits.map(\.id))
        visits = VisitedPlace.decode(storage).filter { ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// Two everyday groups; less-used geometry options stay behind one disclosure.
struct BeenMapFilterOptions: View {
    @Binding var countryLayer: Bool
    @Binding var cities: Bool
    @Binding var badges: Bool
    @Binding var zoomLabels: Bool
    @Binding var outlines: Bool
    @Binding var fill: Bool
    @Binding var hatching: Bool
    @Binding var detailed: Bool
    @Binding var innerCities: Bool
    @State private var showDetail = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("City markers") {
                row("Been to cities", symbol: "mappin.and.ellipse", value: $cities)
                Divider().padding(.leading, 44)
                row("Visited badges", symbol: "checkmark.seal.fill", value: $badges)
                Divider().padding(.leading, 44)
                row("Zoom labels & transitions", symbol: "sparkles.rectangle.stack", value: $zoomLabels)
            }
            group("Country layer") {
                row("Show on map", symbol: "globe.europe.africa", value: $countryLayer)
                Divider().padding(.leading, 44)
                row("Outlines", symbol: "map", value: $outlines).disabled(!countryLayer)
                Divider().padding(.leading, 44)
                row("Color fill", symbol: "paintpalette", value: $fill).disabled(!countryLayer)
            }
            DisclosureGroup(isExpanded: $showDetail) {
                VStack(spacing: 0) {
                    row("Hatching", symbol: "line.3.horizontal", value: $hatching)
                    Divider().padding(.leading, 44)
                    row("Detailed outlines", symbol: "point.topleft.down.curvedto.point.bottomright.up", value: $detailed)
                    Divider().padding(.leading, 44)
                    row("City boundaries", symbol: "building.2", value: $innerCities)
                }.disabled(!countryLayer).padding(.top, 10)
            } label: {
                Label("Map detail", systemImage: "slider.horizontal.3")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                    .padding(.vertical, 8)
            }.padding(.horizontal, 14).padding(.vertical, 6).beenSurface(radius: 20, inset: true)
        }.foregroundStyle(BeenPalette.ink(scheme)).tint(BeenPalette.accent(scheme))
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.custom("PlusJakartaSans-Bold", size: 12)).foregroundStyle(BeenPalette.secondary(scheme)).padding(.leading, 4)
            VStack(spacing: 0, content: content).padding(.horizontal, 14).padding(.vertical, 4).beenSurface(radius: 20)
        }
    }
    private func row(_ title: String, symbol: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BeenPalette.accent(scheme)).frame(width: 30, height: 30)
                    .background(BeenPalette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 13))
            }
        }.toggleStyle(.switch).frame(minHeight: 50).padding(.vertical, 3)
    }
}
