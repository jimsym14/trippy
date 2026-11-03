import Foundation

struct ShareDestination: Codable, Equatable {
    var mode: String // places or note
    var tripID: UUID?
    var noteID: UUID?
}
struct SharedAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    var filename: String
    var kind: String // image or video
    var order: Int
}
struct SharedSourceEnvelope: Codable, Identifiable, Equatable {
    var id: UUID
    var capturedAt: Date
    var sourceURL: String?
    var sharedText: String
    var attachments: [SharedAttachment]
    var destination: ShareDestination
    var mediaKind: String {
        if attachments.contains(where: { $0.kind == "video" }) { return "video" }
        if attachments.contains(where: { $0.kind == "image" }) { return "slides" }
        return "unknown"
    }
}
struct ShareTarget: Codable, Identifiable {
    var id: UUID
    var title: String
    var tripID: UUID?
    var kind: String
}
struct SourceEvidenceBlock: Codable, Identifiable, Equatable {
    var id: String
    var origin: String // shared_text, slide_ocr, supplied_transcript, post_caption
    var text: String
    var attachmentID: UUID?
    var order: Int
}
struct ImportedSocialSource: Codable, Identifiable, Equatable {
    var id: UUID
    var envelope: SharedSourceEnvelope
    var evidence: [SourceEvidenceBlock]
    var state: String // needs_retrieval, needs_transcript, needs_place_review, ready
    var issues: [String]
}
struct SocialPlaceMention: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var summary: String
    var sourceID: UUID
    var evidenceIDs: [String]
    var tripID: UUID?
    var latitude: Double?
    var longitude: Double?
}
struct TravelNote: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var tripID: UUID?
    var sourceIDs: [UUID]
    var userText: String
    var updatedAt: Date
}

// One immutable envelope per share. Atomic writes survive extension termination.
enum SharedInbox {
    static let appGroup = "group.com.dimitrisymeonidis.trippy"
    static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("SocialInbox", isDirectory: true)
    }
    static func prepare(_ id: UUID) throws -> URL {
        guard let root else { throw CocoaError(.fileWriteNoPermission) }
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func commit(_ source: SharedSourceEnvelope) throws {
        let folder = try prepare(source.id)
        try JSONEncoder().encode(source).write(to: folder.appendingPathComponent("envelope.json"), options: .atomic)
    }
    static func pending() -> [SharedSourceEnvelope] {
        guard let root, let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("envelope.json")) else { return nil }
            return try? JSONDecoder().decode(SharedSourceEnvelope.self, from: data)
        }.sorted { $0.capturedAt < $1.capturedAt }
    }
    static func attachmentURL(sourceID: UUID, attachment: SharedAttachment) -> URL? {
        guard attachment.filename == URL(fileURLWithPath: attachment.filename).lastPathComponent,
              !attachment.filename.hasPrefix("."), let root else { return nil }
        return root.appendingPathComponent(sourceID.uuidString).appendingPathComponent(attachment.filename)
    }
    static func readTargets() -> [ShareTarget] {
        guard let url = root?.appendingPathComponent("targets.json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ShareTarget].self, from: data)) ?? []
    }
    static func writeTargets(_ targets: [ShareTarget]) {
        guard let root else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(targets).write(to: root.appendingPathComponent("targets.json"), options: .atomic)
        } catch { /* App remains usable when App Group provisioning is unavailable. */ }
    }
}
