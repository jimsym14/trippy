import AVFoundation
import Foundation
import UIKit
import Vision

struct SocialLibraryDocument: Codable {
    var version = 1
    var sources: [ImportedSocialSource] = []
    var places: [SocialPlaceMention] = []
    var notes: [TravelNote] = []
}
enum SocialLibraryStore {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SocialLibrary", isDirectory: true).appendingPathComponent("library-v1.json")
    }
    static func load() -> SocialLibraryDocument {
        guard let data = try? Data(contentsOf: file) else { return SocialLibraryDocument() }
        return (try? JSONDecoder().decode(SocialLibraryDocument.self, from: data)) ?? SocialLibraryDocument()
    }
    static func save(_ document: SocialLibraryDocument) throws {
        if FileManager.default.fileExists(atPath: file.path) {
            let oldData = try Data(contentsOf: file)
            let old = try JSONDecoder().decode(SocialLibraryDocument.self, from: oldData)
            guard old.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: file, options: .atomic)
    }
}

enum SharedSourceProcessor {
    static func process(_ envelope: SharedSourceEnvelope) async -> ImportedSocialSource {
        await Task.detached(priority: .utility) {
            var blocks: [SourceEvidenceBlock] = []
            var issues: [String] = []
            if !envelope.sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(SourceEvidenceBlock(id: "shared-text", origin: "shared_text", text: envelope.sharedText, attachmentID: nil, order: -1))
            }
            for attachment in envelope.attachments.sorted(by: { $0.order < $1.order }) where attachment.kind == "image" {
                guard let url = SharedInbox.attachmentURL(sourceID: envelope.id, attachment: attachment) else {
                    issues.append("Image \(attachment.order + 1) not found."); continue
                }
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.automaticallyDetectsLanguage = true
                    let supported = try request.supportedRecognitionLanguages()
                    request.recognitionLanguages = ["el-GR", "en-US", "es-ES", "fr-FR"].filter(supported.contains)
                    try VNImageRequestHandler(url: url, options: [:]).perform([request])
                    let observations = (request.results ?? []).sorted {
                        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 { return $0.boundingBox.midY > $1.boundingBox.midY }
                        return $0.boundingBox.minX < $1.boundingBox.minX
                    }
                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    if text.isEmpty { issues.append("No text recognized on slide \(attachment.order + 1).") }
                    else { blocks.append(SourceEvidenceBlock(id: "slide:\(attachment.id.uuidString)", origin: "slide_ocr", text: text, attachmentID: attachment.id, order: attachment.order)) }
                } catch { issues.append("Couldn’t read slide \(attachment.order + 1). The image was kept.") }
            }
            let state = envelope.mediaKind == "unknown" ? "needs_retrieval" : (envelope.mediaKind == "video" ? "needs_transcript" : "needs_place_review")
            return ImportedSocialSource(id: envelope.id, envelope: envelope, evidence: blocks, state: state, issues: issues)
        }.value
    }
}

// MARK: - Share-to-map extraction client

enum SocialExtractionClient {
    enum Failure: LocalizedError {
        case notConnected, server(Int, String?)
        var errorDescription: String? {
            switch self {
            case .notConnected: "Connect the trippy bridge in Settings to read shared videos."
            case .server(let code, let message): message ?? "The extraction service answered HTTP \(code)."
            }
        }
    }

    static func wantsExtraction(_ source: ImportedSocialSource) -> Bool {
        guard source.extractionStatus != "ready", source.extractionStatus != "failed" else { return false }
        if source.envelope.tiktok != nil { return true }
        return source.envelope.sourceURL.flatMap(URL.init(string:)).map(TikTokPageReader.isTikTok) ?? false
    }

    /// Fills in the TikTok snapshot when the share sheet closed before reading finished.
    static func ensureSnapshot(_ source: ImportedSocialSource) async -> ImportedSocialSource {
        guard source.envelope.tiktok == nil, let link = source.envelope.sourceURL.flatMap(URL.init(string:)),
              TikTokPageReader.isTikTok(link), let folder = SharedInbox.root?.appendingPathComponent(source.id.uuidString) else { return source }
        var updated = source
        guard let (post, slides, cover) = try? await TikTokPageReader().read(link, into: folder) else { return source }
        updated.envelope.tiktok = post
        updated.envelope.sourceURL = post.canonicalURL
        for name in slides { updated.envelope.attachments.append(SharedAttachment(id: UUID(), filename: name, kind: "image", order: updated.envelope.attachments.count)) }
        if let cover { updated.envelope.attachments.append(SharedAttachment(id: UUID(), filename: cover, kind: "cover", order: updated.envelope.attachments.count)) }
        try? SharedInbox.commit(updated.envelope)
        let processed = await SharedSourceProcessor.process(updated.envelope)
        updated.evidence = processed.evidence
        updated.issues = processed.issues
        return updated
    }

    static func submit(_ source: ImportedSocialSource, baseURL: String, token: String) async throws -> SocialExtractionJob {
        guard !token.isEmpty, let url = URL(string: baseURL + "/api/social/extract") else { throw Failure.notConnected }
        let post = source.envelope.tiktok
        var evidence: [[String: String]] = post?.evidenceText.map { ["origin": $0.origin, "text": $0.text] } ?? []
        for block in source.evidence where block.origin == "slide_ocr" || (post == nil && block.origin == "shared_text") {
            evidence.append(["origin": block.origin, "text": block.text])
        }
        var body: [String: Any] = ["source_id": source.id.uuidString, "url": source.envelope.sourceURL ?? "",
                                   "author": post?.authorHandle ?? "", "evidence": evidence]
        body["images"] = await Task.detached(priority: .utility) { slideImages(source) }.value
        if let post, !post.isSlideshow, (post.transcript ?? "").isEmpty, (post.durationSeconds ?? 0) > 0,
           let audio = await audioTrack(for: post) {
            body["audio"] = ["mime": "audio/mp4", "data": audio.base64EncodedString()]
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    static func poll(_ jobID: String, baseURL: String, token: String) async throws -> SocialExtractionJob? {
        guard var components = URLComponents(string: baseURL + "/api/social/extract") else { throw Failure.notConnected }
        components.queryItems = [URLQueryItem(name: "job_id", value: jobID)]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        do { return try await send(request) }
        catch Failure.server(404, _) { return nil } // server restarted: caller resubmits
    }

    private static func send(_ request: URLRequest) async throws -> SocialExtractionJob {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw Failure.server(status, message)
        }
        return try JSONDecoder().decode(SocialExtractionJob.self, from: data)
    }

    /// Slides go to Gemini as images (it reads stylised on-image text better than OCR). Max 12, 1280 px JPEG.
    private static func slideImages(_ source: ImportedSocialSource) -> [[String: String]] {
        source.envelope.attachments.filter { $0.kind == "image" }.sorted { $0.order < $1.order }.prefix(12).compactMap { attachment in
            guard let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            let scale = min(1, 1280 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.78) { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return ["mime": "image/jpeg", "data": data.base64EncodedString()]
        }
    }

    /// Fresh read (signed URLs expire), download the video with that session's cookies,
    /// keep only an AAC audio track, delete the video. Up to five minutes.
    private static func audioTrack(for post: TikTokPostSnapshot) async -> Data? {
        guard (post.durationSeconds ?? 0) <= 300, let link = URL(string: post.canonicalURL) else { return nil }
        let reader = TikTokPageReader()
        guard (try? await reader.read(link, into: nil)) != nil, let video = try? await reader.downloadVideo() else { return nil }
        defer { try? FileManager.default.removeItem(at: video) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: output) }
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: video), presetName: AVAssetExportPresetAppleM4A) else { return nil }
        if #available(iOS 18, *) {
            do { try await export.export(to: output, as: .m4a) } catch { return nil }
        } else {
            export.outputURL = output; export.outputFileType = .m4a
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in export.exportAsynchronously { done.resume() } }
            guard export.status == .completed else { return nil }
        }
        return try? Data(contentsOf: output)
    }
}
