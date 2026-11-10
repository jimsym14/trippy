import Foundation

struct ShareDestination: Codable, Equatable {
    var mode: String // places or note
    var tripID: UUID?
    var noteID: UUID?
    /// "Add to Must Do" in the share sheet: places are also saved (heart), not only pinned.
    var mustDo: Bool? = nil
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
    /// Filled by the share extension when the link is a readable public TikTok post.
    var tiktok: TikTokPostSnapshot? = nil
    var mediaKind: String {
        if let tiktok { return tiktok.isSlideshow ? "slides" : "video" }
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
    var displayTitle: String? = nil
    var city: String? = nil
    var listTitle: String? = nil
    var linkedPlaceIDs: [UUID]? = nil
    /// Server extraction: queued/running/ready/failed, and the Gemini model that answered.
    var extractionStatus: String? = nil
    var extractionError: String? = nil
    var extractionModel: String? = nil
    var extractedAt: Date? = nil
    var summary: String? = nil
    var country: String? = nil
    var countryCode: String? = nil
    /// "places", "tips" or "mixed". Tips posts live in the Tips shelf of Videos, with their own note.
    var postKind: String? = nil
    var tips: [SocialTip]? = nil
    /// True when the server handed back an earlier read of the same post (indexed once for everyone).
    var fromIndex: Bool? = nil
    var isTips: Bool { postKind == "tips" }
}
/// One beat of a post's timeline: when ("0:12", "slide 3", "caption") and what was said or shown.
struct SocialMoment: Codable, Equatable, Hashable { var at: String; var text: String }
struct SocialTip: Codable, Equatable, Hashable { var title: String; var detail: String; var at: String? = nil }
struct SocialPlaceMention: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var summary: String
    var sourceID: UUID
    var evidenceIDs: [String]
    var tripID: UUID?
    var latitude: Double?
    var longitude: Double?
    var city: String? = nil
    var noteID: UUID? = nil
    // Mio-style card, written by the extraction pipeline.
    var category: String? = nil
    var nameLatin: String? = nil
    var neighborhood: String? = nil
    var country: String? = nil
    var countryCode: String? = nil
    var address: String? = nil
    var googlePlaceID: String? = nil
    var vibeTags: [String]? = nil
    var proTips: [String]? = nil
    var goodToKnow: [String]? = nil
    var mustTry: [String]? = nil
    var whyGo: [String]? = nil
    var priceHint: String? = nil
    var evidence: [String]? = nil
    var moments: [SocialMoment]? = nil
}

/// Response shape of GET /api/social/extract (see trippy/social/extract.py).
struct SocialExtractionJob: Decodable {
    struct Google: Decodable { let placeID: String?; let name: String?; let address: String?; let latitude: Double?; let longitude: Double?; let primaryType: String?; let city: String?; let countryCode: String? }
    struct Place: Decodable {
        let name: String; let nameLatin: String?; let category: String; let neighborhood: String?; let city: String?; let country: String?
        let countryCode: String?; let addressHint: String?; let vibeTags: [String]; let tldr: String; let proTips: [String]; let goodToKnow: [String]
        let mustTry: [String]; let whyGo: [String]; let priceHint: String?; let evidence: [String]; let confidence: Double; let google: Google?
        let moments: [SocialMoment]?
        enum CodingKeys: String, CodingKey {
            case name, category, neighborhood, city, country, tldr, evidence, confidence, google, moments
            case nameLatin = "name_latin", countryCode = "country_code", addressHint = "address_hint", vibeTags = "vibe_tags"
            case proTips = "pro_tips", goodToKnow = "good_to_know", mustTry = "must_try", whyGo = "why_go", priceHint = "price_hint"
        }
    }
    struct Result: Decodable {
        let postTitle: String; let postSummary: String; let city: String; let country: String; let countryCode: String?
        let places: [Place]; let model: String?
        let postKind: String?; let tips: [SocialTip]?
        enum CodingKeys: String, CodingKey {
            case city, country, places, model, tips
            case postTitle = "post_title", postSummary = "post_summary", countryCode = "country_code", postKind = "post_kind"
        }
    }
    let jobID: String
    let status: String
    let error: String?
    let note: String?
    let result: Result?
    let cached: Bool?
    enum CodingKeys: String, CodingKey { case status, error, note, result, cached; case jobID = "job_id" }
}
struct LinkedPlaceReference: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var googlePlaceID: String? = nil
}
struct TravelNote: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var tripID: UUID?
    var sourceIDs: [UUID]
    var userText: String
    var updatedAt: Date
    var placeMentionID: UUID? = nil
    var city: String? = nil
    var linkedPlaceIDs: [String]? = nil
    var linkedPlaces: [LinkedPlaceReference]? = nil
    /// "place" (one venue, written automatically from videos), "tips" (a tips post) or nil (your own note).
    var kind: String? = nil
    /// Same key as the place's pin and take, so one venue has one note however many videos mention it.
    var placeKey: String? = nil
    /// What each video said, keyed by source ID. Re-reading a video replaces its section, never duplicates it.
    var fromSources: [String: String]? = nil
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

// MARK: - TikTok public post reader
/// What a public TikTok post page carries, read the way Safari would load it.
/// Media URLs are short-lived and signed; slides/cover are copied into the share folder.
struct TikTokPostSnapshot: Codable, Equatable {
    var postID: String
    var canonicalURL: String
    var isSlideshow: Bool
    var authorHandle: String?
    var authorName: String?
    var caption: String
    var slideshowTitle: String?
    var onScreenText: [String]
    var slideCount: Int
    var transcript: String?
    var transcriptLanguage: String?
    var durationSeconds: Int?
    var region: String?
    var topicLabels: [String]
    var mentions: [String]
    var hashtags: [String]
    var likes: Int?
    var saves: Int?
    var musicTitle: String?
    var coverURL: String?
    var fetchedAt: Date

    /// All text evidence in reading order, for the extraction prompt.
    var evidenceText: [(origin: String, text: String)] {
        var blocks: [(String, String)] = []
        if !caption.isEmpty { blocks.append(("post_caption", caption)) }
        if let slideshowTitle, !slideshowTitle.isEmpty { blocks.append(("post_caption", slideshowTitle)) }
        if !onScreenText.isEmpty { blocks.append(("on_screen_text", onScreenText.joined(separator: "\n"))) }
        if let transcript, !transcript.isEmpty { blocks.append(("auto_caption", transcript)) }
        return blocks
    }
}

enum TikTokReaderError: LocalizedError {
    case notTikTok, unavailable, blocked(Int)
    var errorDescription: String? {
        switch self {
        case .notTikTok: "This link isn't a TikTok post."
        case .unavailable: "TikTok didn't return this post. It may be private or removed."
        case .blocked(let code): "TikTok refused the request (HTTP \(code))."
        }
    }
}

/// One instance per share: its session keeps TikTok's anonymous cookies, which the
/// signed video URL requires. No login, no stored credentials.
final class TikTokPageReader {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private(set) var session: URLSession
    private(set) var videoURL: URL?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
        session = Self.makeSession(timeout: timeout)
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpCookieStorage = HTTPCookieStorage()
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept-Language": "en-US,en;q=0.9"]
        return URLSession(configuration: configuration)
    }

    static func isTikTok(_ url: URL) -> Bool {
        let host = (url.host() ?? "").lowercased()
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    /// Reads the post; downloads slides (and the cover) into `folder` when given.
    /// Returns the snapshot plus local slide filenames in order.
    func read(_ url: URL, into folder: URL?, maxSlides: Int = 35) async throws -> (TikTokPostSnapshot, slides: [String], cover: String?) {
        guard Self.isTikTok(url) else { throw TikTokReaderError.notTikTok }
        var (item, finalURL) = try await fetchItem(url)
        if item == nil, let alternate = Self.alternatePath(finalURL) {
            session = Self.makeSession(timeout: timeout) // TikTok refuses the retry when the first visit's cookies are sent
            (item, finalURL) = try await fetchItem(alternate)
        }
        guard let item, let postID = item["id"] as? String, !postID.isEmpty else { throw TikTokReaderError.unavailable }

        let video = item["video"] as? [String: Any] ?? [:]
        let author = item["author"] as? [String: Any] ?? [:]
        let imagePost = item["imagePost"] as? [String: Any]
        let images = (imagePost?["images"] as? [[String: Any]]) ?? []
        let stats = item["stats"] as? [String: Any] ?? [:]
        let stickers = (item["stickersOnItem"] as? [[String: Any]] ?? []).flatMap { $0["stickerText"] as? [String] ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let extras = item["textExtra"] as? [[String: Any]] ?? []
        let handle = author["uniqueId"] as? String
        videoURL = (video["playAddr"] as? String).flatMap(URL.init(string:))

        var transcript: String?, language: String?
        let subtitles = (video["subtitleInfos"] as? [[String: Any]] ?? []).filter { ($0["Format"] as? String)?.lowercased() == "webvtt" }
        if let track = subtitles.first, let link = (track["Url"] as? String).flatMap(URL.init(string:)),
           let (data, response) = try? await session.data(from: link), (response as? HTTPURLResponse)?.statusCode == 200 {
            transcript = Self.plainText(fromVTT: String(decoding: data, as: UTF8.self))
            language = track["LanguageCodeName"] as? String
        }

        var slideFiles: [String] = [], coverFile: String?
        let coverLink = ((imagePost?["cover"] as? [String: Any])?["imageURL"] as? [String: Any]).flatMap { ($0["urlList"] as? [String])?.first }
            ?? video["originCover"] as? String ?? video["cover"] as? String
        if let folder {
            for (index, image) in images.prefix(maxSlides).enumerated() {
                guard let link = ((image["imageURL"] as? [String: Any])?["urlList"] as? [String])?.first.flatMap(URL.init(string:)) else { continue }
                if let name = try? await download(link, to: folder, name: String(format: "slide-%02d", index + 1)) { slideFiles.append(name) }
            }
            if images.isEmpty, let link = coverLink.flatMap(URL.init(string:)) { coverFile = try? await download(link, to: folder, name: "cover") }
        }

        let snapshot = TikTokPostSnapshot(
            postID: postID,
            canonicalURL: handle.map { "https://www.tiktok.com/@\($0)/\(images.isEmpty ? "video" : "photo")/\(postID)" } ?? finalURL.absoluteString,
            isSlideshow: !images.isEmpty,
            authorHandle: handle, authorName: author["nickname"] as? String,
            caption: (item["desc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            slideshowTitle: imagePost?["title"] as? String,
            onScreenText: stickers, slideCount: images.count,
            transcript: transcript, transcriptLanguage: language,
            durationSeconds: (video["duration"] as? NSNumber)?.intValue,
            region: item["locationCreated"] as? String,
            topicLabels: item["diversificationLabels"] as? [String] ?? [],
            mentions: extras.compactMap { $0["userUniqueId"] as? String }.filter { !$0.isEmpty },
            hashtags: extras.compactMap { $0["hashtagName"] as? String }.filter { !$0.isEmpty },
            likes: (stats["diggCount"] as? NSNumber)?.intValue, saves: (stats["collectCount"] as? NSNumber)?.intValue,
            musicTitle: (item["music"] as? [String: Any])?["title"] as? String,
            coverURL: coverLink, fetchedAt: .now)
        return (snapshot, slideFiles, coverFile)
    }

    /// Downloads the video (cookies from `read` are required). Caller deletes the file.
    func downloadVideo(maximumBytes: Int = 60_000_000) async throws -> URL {
        guard let videoURL else { throw TikTokReaderError.unavailable }
        var request = URLRequest(url: videoURL)
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        let (file, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TikTokReaderError.blocked((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= maximumBytes else { try? FileManager.default.removeItem(at: file); throw CocoaError(.fileReadTooLarge) }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    private func fetchItem(_ url: URL) async throws -> ([String: Any]?, URL) {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let finalURL = http?.url ?? url
        guard let status = http?.statusCode, (200..<300).contains(status) else { throw TikTokReaderError.blocked(http?.statusCode ?? 0) }
        let html = String(decoding: data, as: UTF8.self)
        guard let open = html.range(of: "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\""),
              let start = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)) as? [String: Any],
              let scope = json["__DEFAULT_SCOPE__"] as? [String: Any] else { return (nil, finalURL) }
        let detail = (scope["webapp.video-detail"] ?? scope["webapp.reflow.video.detail"]) as? [String: Any]
        let item = (detail?["itemInfo"] as? [String: Any])?["itemStruct"] as? [String: Any]
        guard let item, (item["id"] as? String)?.isEmpty == false else { return (nil, finalURL) }
        return (item, finalURL)
    }

    /// Slideshows sometimes resolve only on /photo/, videos only on /video/.
    static func alternatePath(_ url: URL) -> URL? {
        let text = url.absoluteString
        if text.contains("/video/") { return URL(string: text.replacingOccurrences(of: "/video/", with: "/photo/")) }
        if text.contains("/photo/") { return URL(string: text.replacingOccurrences(of: "/photo/", with: "/video/")) }
        return nil
    }

    static func plainText(fromVTT vtt: String) -> String {
        var lines: [String] = []
        for raw in vtt.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "WEBVTT" || line.contains("-->") || line.allSatisfy(\.isNumber) { continue }
            if lines.last != line { lines.append(line) }
        }
        return lines.joined(separator: " ")
    }

    private func download(_ url: URL, to folder: URL, name: String) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 0, data.count <= 20_000_000 else { throw TikTokReaderError.unavailable }
        let ext = http.mimeType == "image/png" ? "png" : http.mimeType == "image/webp" ? "webp" : http.mimeType == "image/heic" ? "heic" : "jpg"
        let filename = "\(name).\(ext)"
        try data.write(to: folder.appendingPathComponent(filename), options: .atomic)
        return filename
    }
}
