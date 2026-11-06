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
    @State private var targets = SharedInbox.readTargets()
    @State private var envelope: SharedSourceEnvelope?
    @State private var phase = Phase.saving
    @State private var cover: UIImage?
    @State private var mustDo = false
    @State private var tripID: UUID?
    @State private var sharedToday = 0
    @State private var error: String?
    @State private var bounce = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Phase { case saving, reading, ready, savedOnly }

    private var ink: Color { scheme == .dark ? Color(red: 0.95, green: 0.93, blue: 0.89) : Color(red: 0.06, green: 0.16, blue: 0.12) }
    private var paper: Color { scheme == .dark ? Color(red: 0.09, green: 0.08, blue: 0.08) : Color(red: 0.97, green: 0.95, blue: 0.92) }
    private var card: Color { scheme == .dark ? Color(red: 0.13, green: 0.12, blue: 0.11) : .white }
    private let coral = Color(red: 0.87, green: 0.35, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("trippy").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                Spacer()
                if sharedToday > 0 {
                    Text("\(sharedToday) shared today").font(.footnote.weight(.semibold)).foregroundStyle(ink.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(card, in: Capsule())
                }
            }.padding(.horizontal, 22).padding(.top, 22)

            Spacer(minLength: 12)
            ZStack {
                Circle().fill(coral.opacity(0.12)).frame(width: 128, height: 128)
                Image(systemName: phase == .ready || phase == .savedOnly ? "mappin.and.ellipse" : "sparkle.magnifyingglass")
                    .font(.system(size: 50, weight: .semibold)).foregroundStyle(coral)
                    .symbolEffect(.bounce, value: bounce)
                    .contentTransition(.symbolEffect(.replace))
            }.accessibilityHidden(true)

            VStack(spacing: 8) {
                (Text(phase == .savedOnly ? "Saved " : "We're ") + Text(phase == .savedOnly ? "for later" : "on it!").foregroundStyle(coral))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(ink)
                Text(subtitle).font(.subheadline).foregroundStyle(ink.opacity(0.65)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 28).padding(.top, 18)

            postCard.padding(.horizontal, 22).padding(.top, 22)

            Button { mustDo.toggle(); bounce.toggle(); persistChoices() } label: {
                Label("Add to Must Do", systemImage: mustDo ? "heart.fill" : "heart")
                    .font(.body.weight(.semibold)).foregroundStyle(mustDo ? .white : ink)
                    .padding(.horizontal, 22).frame(minHeight: 48)
                    .background(mustDo ? AnyShapeStyle(coral) : AnyShapeStyle(card), in: Capsule())
                    .overlay(Capsule().strokeBorder(ink.opacity(mustDo ? 0 : 0.18), lineWidth: 1))
            }
            .padding(.top, 20)
            .disabled(envelope == nil)
            .accessibilityAddTraits(mustDo ? .isSelected : [])

            Spacer(minLength: 12)
            collectionPicker.padding(.horizontal, 22)
            if let error { Text(error).font(.footnote).foregroundStyle(coral).padding(.horizontal, 22).padding(.top, 8) }
            Button { context?.completeRequest(returningItems: [], completionHandler: nil) } label: {
                Text("Done").font(.headline).foregroundStyle(scheme == .dark ? Color(red: 0.06, green: 0.16, blue: 0.12) : .white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(scheme == .dark ? Color(red: 0.95, green: 0.93, blue: 0.89) : Color(red: 0.06, green: 0.16, blue: 0.12), in: Capsule())
            }
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18)
        }
        .background(paper.ignoresSafeArea())
        .task { await capture() }
    }

    private var subtitle: String {
        switch phase {
        case .saving: "Saving your share…"
        case .reading: "Reading the post. It'll be on your map in a minute or two."
        case .ready: "Got it. We'll pin every spot from it on your map in a minute or two."
        case .savedOnly: "Kept safely. Open trippy to finish reading it."
        }
    }

    @ViewBuilder private var postCard: some View {
        let post = envelope?.tiktok
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink.opacity(0.08))
                if let cover { Image(uiImage: cover).resizable().scaledToFill() }
                else if phase == .saving || phase == .reading { ProgressView() }
                else { Image(systemName: "play.rectangle").foregroundStyle(ink.opacity(0.5)) }
            }
            .frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(post.map { [$0.caption, $0.slideshowTitle ?? ""].first { !$0.isEmpty } ?? "TikTok post" } ?? envelope?.sharedText.nonEmptyLine ?? "Your share")
                    .font(.subheadline.weight(.medium)).foregroundStyle(ink).lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(.black, in: RoundedRectangle(cornerRadius: 5))
                    Text(post?.authorHandle.map { "@\($0)" } ?? (envelope?.sourceURL.flatMap { URL(string: $0)?.host() } ?? ""))
                        .font(.footnote.weight(.semibold)).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                    if let post, post.isSlideshow { Text("· \(post.slideCount) slides").font(.footnote).foregroundStyle(ink.opacity(0.55)) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var collectionPicker: some View {
        let trips = targets.filter { $0.kind == "trip" }
        HStack(spacing: 10) {
            Text("Add to").font(.subheadline).foregroundStyle(ink.opacity(0.7))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(trips) { trip in
                        Button { tripID = tripID == trip.id ? nil : trip.id; persistChoices() } label: {
                            Text(trip.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                .foregroundStyle(tripID == trip.id ? .white : ink).padding(.horizontal, 14).frame(minHeight: 40)
                                .background(tripID == trip.id ? AnyShapeStyle(ink) : AnyShapeStyle(card), in: Capsule())
                        }.accessibilityAddTraits(tripID == trip.id ? .isSelected : [])
                    }
                    if trips.isEmpty {
                        Text("Your map").font(.subheadline.weight(.semibold)).foregroundStyle(ink).padding(.horizontal, 14).frame(minHeight: 40)
                            .overlay(Capsule().strokeBorder(ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func persistChoices() {
        guard var current = envelope else { return }
        current.destination.mustDo = mustDo
        current.destination.tripID = tripID
        envelope = current
        try? SharedInbox.commit(current)
    }

    @MainActor func capture() async {
        guard envelope == nil else { return }
        sharedToday = SharedInbox.pending().filter { Calendar.current.isDateInToday($0.capturedAt) }.count + 1
        guard SharedInbox.root != nil else { error = "Sharing isn't set up on this device yet."; phase = .savedOnly; return }
        error = nil
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
            var saved = SharedSourceEnvelope(id: id, capturedAt: .now, sourceURL: sourceURL, sharedText: joined, attachments: attachments,
                                             destination: ShareDestination(mode: "places", tripID: tripID, noteID: nil, mustDo: mustDo))
            // Commit first: even if TikTok is slow or the sheet is closed, the share is kept and the app finishes it.
            try SharedInbox.commit(saved)
            envelope = saved
            guard let link = sourceURL.flatMap(URL.init(string:)), TikTokPageReader.isTikTok(link) else { phase = .ready; return }
            phase = .reading
            let reader = TikTokPageReader(timeout: 12)
            do {
                let (post, slides, coverFile) = try await reader.read(link, into: folder)
                saved = envelope ?? saved
                saved.tiktok = post
                saved.sourceURL = post.canonicalURL
                for name in slides { saved.attachments.append(SharedAttachment(id: UUID(), filename: name, kind: "image", order: saved.attachments.count)) }
                if let coverFile { saved.attachments.append(SharedAttachment(id: UUID(), filename: coverFile, kind: "cover", order: saved.attachments.count)) }
                try SharedInbox.commit(saved)
                envelope = saved
                if let first = coverFile ?? slides.first { cover = UIImage(contentsOfFile: folder.appendingPathComponent(first).path) }
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { phase = .ready }
                bounce.toggle()
            } catch {
                phase = .savedOnly
            }
        } catch {
            self.error = "This couldn't be saved. Try sharing the link again."
            if let folder = SharedInbox.root?.appendingPathComponent(id.uuidString) { try? FileManager.default.removeItem(at: folder) }
            phase = .savedOnly
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

private extension String {
    var nonEmptyLine: String? {
        split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && !$0.hasPrefix("http") }
    }
}
