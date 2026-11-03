import Foundation
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
                    issues.append("Δεν βρέθηκε η εικόνα \(attachment.order + 1)."); continue
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
                    if text.isEmpty { issues.append("Δεν αναγνωρίστηκε κείμενο στο slide \(attachment.order + 1).") }
                    else { blocks.append(SourceEvidenceBlock(id: "slide:\(attachment.id.uuidString)", origin: "slide_ocr", text: text, attachmentID: attachment.id, order: attachment.order)) }
                } catch { issues.append("Δεν διαβάστηκε το slide \(attachment.order + 1). Διατηρήθηκε η εικόνα.") }
            }
            let state = envelope.mediaKind == "unknown" ? "needs_retrieval" : (envelope.mediaKind == "video" ? "needs_transcript" : "needs_place_review")
            return ImportedSocialSource(id: envelope.id, envelope: envelope, evidence: blocks, state: state, issues: issues)
        }.value
    }
}
