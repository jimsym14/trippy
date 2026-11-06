import SwiftUI

/// The app's own bottom bar: two places (Map, Library) and one action (New trip),
/// kept separate so the action never reads as a third tab.
/// The one action button beside the tabs. It changes with the page: plus by default, other glyphs where they fit better.
struct TabBarAction {
    let id: String
    let label: String
    var symbol: String?      // nil = the app's own plus
    let run: () -> Void
    static func newTrip(_ run: @escaping () -> Void) -> Self { .init(id: "trip", label: "New trip", symbol: nil, run: run) }
}

struct TrippyTabBar: View {
    @Binding var selection: String
    var action: TabBarAction
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabs: [(id: String, title: String, icon: TrippyIcon)] = [("map", "Map", .map), ("library", "Library", .library)]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.id) { tab in
                    let selected = selection == tab.id
                    Button {
                        guard !selected else { return }
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) { selection = tab.id }
                    } label: {
                        HStack(spacing: 7) {
                            TrippyIconView(icon: tab.icon, size: 20, weight: selected ? 2.1 : 1.7, filled: selected,
                                           animated: true, trigger: selected)
                            if selected {
                                Text(tab.title).font(.custom("PlusJakartaSans-Bold", size: 14, relativeTo: .subheadline))
                                    .fixedSize()
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .foregroundStyle(selected ? Sketch.paper : Sketch.inkSoft)
                        .tint(selected ? Sketch.paper : Sketch.inkSoft)
                        .padding(.horizontal, selected ? 18 : 16)
                        .frame(minWidth: 52, minHeight: 48)
                        .background {
                            if selected {
                                Capsule().fill(Sketch.ink).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(SketchPressStyle())
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(5)
            .background(BarSurface(shape: Capsule()))

            Button {
                action.run()
            } label: {
                ZStack {
                    if let symbol = action.symbol {
                        Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        TrippyIconView(icon: .plus, size: 22, weight: 2.2)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .foregroundStyle(Sketch.ink)
                .frame(width: 58, height: 58)
                .background(BarSurface(shape: Circle()))
            }
            .buttonStyle(SketchPressStyle())
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.7), value: action.symbol)
            .accessibilityLabel(action.label)
        }
        .padding(.bottom, 6)
    }
}

/// Solid paper surface with a hairline and soft lift; readable over any map.
private struct BarSurface<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        shape.fill(Sketch.card)
            .overlay(shape.strokeBorder(Sketch.ink.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

