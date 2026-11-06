import SwiftUI
import AppKit
import CoreText

private struct PlanningGallery: View {
    let step: Int
    @Environment(\.colorScheme) private var scheme
    @State private var pace = 0.45
    private var colors: PlanningColors { PlanningColors(scheme: scheme) }
    private let titles = ["Βασικά", "Προτιμήσεις", "Κόστος", "Σχόλια & έρευνα"]
    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.ink)
    }
    private func choices(_ titles: [String], selected: String) -> some View {
        PillFlowLayout {
            ForEach(titles, id: \.self) { title in
                PlanningChoicePill(title: title, selected: title == selected)
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(titles[step]).font(.system(size: 29, weight: .bold)).foregroundStyle(colors.ink)
            HStack {
                Text("ΒΗΜΑ \(step + 1) ΑΠΟ 4").font(.system(size: 10, weight: .bold)).tracking(1.2)
                Spacer()
                Text(titles[step]).font(.caption.weight(.semibold)).foregroundStyle(colors.brand)
            }.foregroundStyle(colors.secondaryInk)
            HStack(spacing: 5) {
                ForEach(0..<4) { index in Capsule().fill(index <= step ? colors.progress(index) : colors.secondaryInk.opacity(0.14)).frame(height: 4) }
            }
            if step == 0 {
                heading("Όνομα ταξιδιού")
                Label("Weekend in Barcelona", systemImage: "pencil.line").padding(16).frame(maxWidth: .infinity, alignment: .leading).planningSurface(radius: 16, raised: true)
                heading("Πού θέλεις να πας;")
                PlanningDestinationCard(destination: "Barcelona", dates: "5/12-9/12 2026", travelers: 2)
                choices(["Ευρώπη", "Ασία", "Αμερική", "Οπουδήποτε"], selected: "Ευρώπη")
                heading("Ποιοι ταξιδεύουν;")
                choices(["Μόνος/η", "Ζευγάρι", "Φίλοι", "Οικογένεια", "Δουλειά"], selected: "Φίλοι")
            } else if step == 1 {
                VStack(alignment: .leading, spacing: 20) {
                    heading("Τι ατμόσφαιρα προτιμάς;")
                    choices(["Πόλη", "Φύση", "Παραλία", "Πολιτισμός"], selected: "Πόλη")
                    heading("Τι θέλεις να ζήσεις;")
                    choices(["Φαγητό", "Αξιοθέατα", "Καφές", "Αγορές", "Νυχτερινή ζωή"], selected: "Φαγητό")
                    VStack(alignment: .leading, spacing: 12) {
                        heading("Φαγητό")
                        choices(["Τοπική κουζίνα", "Street food", "Fine dining"], selected: "Τοπική κουζίνα")
                    }.padding(14).planningSurface(radius: 17, raised: true)
                    heading("Ρυθμός")
                    Slider(value: $pace).tint(colors.accent)
                    heading("Πού θέλεις να μείνεις;")
                    choices(["Boutique / Hotel", "Apartment / Airbnb", "Hostal"], selected: "Boutique / Hotel")
                }.padding(16).planningSurface(radius: 20)
            } else if step == 2 {
                VStack(alignment: .leading, spacing: 20) {
                    heading("Ποιο είναι το budget σου;")
                    choices(["Ανά άτομο", "Συνολικά για την παρέα"], selected: "Ανά άτομο")
                    Text("Προαιρετικό ανώτατο ποσό").font(.caption).foregroundStyle(colors.secondaryInk)
                    Text("800 €").padding(16).frame(maxWidth: .infinity, alignment: .leading).planningSurface(radius: 15, raised: true)
                    heading("Τι να υπολογίσει;")
                    Text("Επίλεξε τι περιλαμβάνει το ποσό σου.").font(.caption).foregroundStyle(colors.secondaryInk)
                    choices(["Διαμονή", "Μετακινήσεις στην πόλη", "Φαγητό", "Εισιτήρια & δραστηριότητες"], selected: "Διαμονή")
                }.padding(16).planningSurface(radius: 20)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    PlanningDestinationCard(destination: "Barcelona", dates: "5/12-9/12 2026", travelers: 2)
                    heading("Τι άλλο να ξέρουμε;")
                    Text("Περιορισμοί, αγαπημένα και οτιδήποτε κάνει το ταξίδι δικό σου.").font(.caption).foregroundStyle(colors.secondaryInk)
                    Text("Γράψε με τον δικό σου τρόπο…").font(.subheadline).foregroundStyle(colors.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading).padding(15).planningSurface(radius: 17, raised: true)
                    heading("Πώς θέλεις να γίνει η έρευνα;")
                    Label("Αυτόματη έρευνα", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 68).foregroundStyle(colors.inverseInk).background(colors.brand, in: RoundedRectangle(cornerRadius: 18))
                    Label("Χειροκίνητη έρευνα", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 68).planningSurface(radius: 18, raised: true)
                }.padding(16).planningSurface(radius: 20)
            }
            Spacer(minLength: 0)
            if step < 3 {
                Label("Συνέχεια", systemImage: "arrow.right").font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.inverseInk).frame(maxWidth: .infinity).frame(height: 52).background(colors.brand, in: Capsule())
            }
        }.foregroundStyle(colors.ink).padding(22).frame(width: 402, height: step == 1 ? 1100 : 820, alignment: .topLeading).background(colors.canvas)
    }
}
@main struct PlanningDesignRenderer {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.count > 2 {
            let fonts = URL(fileURLWithPath: CommandLine.arguments[2])
            for font in try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) where font.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            for step in 0..<4 {
                let renderer = ImageRenderer(content: PlanningGallery(step: step).environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                try data.write(to: directory.appendingPathComponent("planning-\(step)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
