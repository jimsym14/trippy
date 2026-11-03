import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(context: extensionContext))
        addChild(host); view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareCaptureView: View {
    let context: NSExtensionContext?
    @State private var mode = "places"
    @State private var tripID: UUID?
    @State private var noteID: UUID?
    @State private var targets = SharedInbox.readTargets()
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Κράτησε την έμπνευση", systemImage: "bookmark")
                        .font(.title2.weight(.semibold))
                    Text("Μέρη για γρήγορο save ή Note για ολόκληρη την πληροφορία και τις πηγές.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Τι θέλεις να κρατήσεις;") {
                    Picker("Αποθήκευση ως", selection: $mode) {
                        Text("Places").tag("places"); Text("Note").tag("note")
                    }.pickerStyle(.segmented)
                    Picker("Συλλογή", selection: $tripID) {
                        Text("Γενική βιβλιοθήκη").tag(UUID?.none)
                        ForEach(targets.filter { $0.kind == "trip" }) { target in Text(target.title).tag(Optional(target.id)) }
                    }
                    if mode == "note" {
                        Picker("Note", selection: $noteID) {
                            Text("Δημιουργία νέου Note").tag(UUID?.none)
                            ForEach(targets.filter { $0.kind == "note" && $0.tripID == tripID }) { target in Text(target.title).tag(Optional(target.id)) }
                        }
                    }
                }
                Section {
                    Text("Το share αποθηκεύεται πρώτα. Το Trippy επεξεργάζεται το διαθέσιμο κείμενο και τις εικόνες όταν ανοίξεις την εφαρμογή. Αν παραδοθεί μόνο link, θα χρειαστεί ανάκτηση του post.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Save to Trippy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ακύρωση") { context?.cancelRequest(withError: CocoaError(.userCancelled)) }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await capture() } } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
                    }.disabled(saving || SharedInbox.root == nil)
                }
            }
            .onChange(of: tripID) { _, _ in noteID = nil }
            .onAppear { if SharedInbox.root == nil { error = "Η αποθήκευση share δεν είναι διαθέσιμη. Πρόσθεσε το link από το Inbox της εφαρμογής." } }
        }.tint(Color(red: 0.06, green: 0.16, blue: 0.12))
    }
    @MainActor func capture() async {
        saving = true; error = nil
        let id = UUID()
        do {
            let folder = try SharedInbox.prepare(id)
            let items = (context?.inputItems as? [NSExtensionItem] ?? [])
            let providers = items.flatMap { $0.attachments ?? [] }
            guard !providers.isEmpty, providers.count <= 40 else { throw CocoaError(.fileReadCorruptFile) }
            var attachments: [SharedAttachment] = []
            var texts = items.compactMap { $0.attributedContentText?.string }
            var sourceURL: String?
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) && !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) && !provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    let value = try await loadItem(provider, type: UTType.url.identifier)
                    let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                    if let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { sourceURL = sourceURL ?? url.absoluteString }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
                    let file = try await copyFile(provider, type: type, folder: folder, maximum: 20_000_000)
                    attachments.append(SharedAttachment(id: UUID(), filename: file.lastPathComponent, kind: "image", order: attachments.count))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    let file = try await copyFile(provider, type: UTType.movie.identifier, folder: folder, maximum: 150_000_000)
                    attachments.append(SharedAttachment(id: UUID(), filename: file.lastPathComponent, kind: "video", order: attachments.count))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try await loadItem(provider, type: UTType.plainText.identifier) as? String { texts.append(text) }
                }
            }
            let text = Array(NSOrderedSet(array: texts)) as? [String] ?? texts
            let joined = text.joined(separator: "\n\n")
            guard joined.utf8.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
            if sourceURL == nil {
                let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                sourceURL = detector.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined))?.url?.absoluteString
            }
            guard sourceURL != nil || !joined.isEmpty || !attachments.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            try SharedInbox.commit(SharedSourceEnvelope(id: id, capturedAt: .now, sourceURL: sourceURL, sharedText: joined, attachments: attachments,
                                                      destination: ShareDestination(mode: mode, tripID: tripID, noteID: mode == "note" ? noteID : nil)))
            context?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            self.error = "Δεν αποθηκεύτηκε το share. Δοκίμασε ξανά με link ή εικόνες (έως 20 MB ανά εικόνα)."
            if let folder = SharedInbox.root?.appendingPathComponent(id.uuidString) { try? FileManager.default.removeItem(at: folder) }
            saving = false
        }
    }
    func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
            }
        }
    }
    func copyFile(_ provider: NSItemProvider, type: String, folder: URL, maximum: Int) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileReadCorruptFile) }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0 && size <= maximum else { throw CocoaError(.fileReadTooLarge) }
                    let suffix = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "dat") : url.pathExtension
                    let output = folder.appendingPathComponent(UUID().uuidString + "." + suffix)
                    try FileManager.default.copyItem(at: url, to: output)
                    continuation.resume(returning: output)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
