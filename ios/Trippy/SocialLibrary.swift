import AVFoundation
import Foundation
import UIKit
import Vision

struct SocialLibraryDocument: Codable {
    var version = 1
    var sources: [ImportedSocialSource] = []
    var places: [SocialPlaceMention] = []
    var notes: [TravelNote] = []
    /// Your quick take per real place (PlaceKey), shared by every pin, save, note and video of that place.
    var takes: [String: PlaceTake]? = nil
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
        let isVideo = post.map { !$0.isSlideshow && ($0.durationSeconds ?? 0) > 0 } ?? false
        var body: [String: Any] = ["source_id": source.id.uuidString, "url": source.envelope.sourceURL ?? "",
                                   "author": post?.authorHandle ?? "", "evidence": evidence, "video_id": post?.postID ?? "",
                                   "expects_video": isVideo, "reread": source.rereadRequested == true]
        // Every post is read once for everyone: ask first, so an indexed post costs no upload and no credit.
        if let probe = try? await send(jsonRequest(url, body: body.merging(["probe": true]) { $1 }, token: token, timeout: 20)),
           probe.status != "unindexed" { return probe }
        body["images"] = await Task.detached(priority: .utility) { slideImages(source) }.value
        // Videos are read on the phone first (VideoReading): only the frames where text appears go, with what
        // the phone read on them, and the sound check decides whether the transcript and the audio are worth sending.
        if let post, isVideo {
            let upload = await videoUpload(for: post)
            body["media_note"] = upload.note
            if let sound = upload.sound {
                body["sound"] = sound.kind.rawValue
                // A song's auto-captions are lyrics: they would only mislead the read.
                if !sound.hasVoice { evidence.removeAll { $0["origin"] == "auto_caption" } }
            }
            if !upload.frameText.isEmpty { evidence.append(["origin": "frame_text", "text": upload.frameText]) }
            body["evidence"] = evidence
            if let video = upload.video { body["video"] = ["mime": "video/mp4", "data": video.base64EncodedString()] }
            if !upload.frames.isEmpty {
                body["images"] = upload.frames.map { ["mime": "image/jpeg", "data": $0.jpeg.base64EncodedString()] }
                body["frame_times"] = upload.frames.map(\.time)
            }
            if let audio = upload.audio { body["audio"] = ["mime": "audio/mp4", "data": audio.base64EncodedString()] }
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private static func jsonRequest(_ url: URL, body: [String: Any], token: String, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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

    /// Slides go to Gemini as images (it reads stylised on-image text better than OCR). All of them, up to
    /// TikTok's 35; long slideshows drop to 1024 px so the request stays well under Gemini's 20 MB inline limit.
    private static func slideImages(_ source: ImportedSocialSource) -> [[String: String]] {
        let slides = source.envelope.attachments.filter { $0.kind == "image" }.sorted { $0.order < $1.order }.prefix(35)
        let edge: CGFloat = slides.count > 12 ? 1024 : 1280
        return slides.compactMap { attachment in
            guard let url = SharedInbox.attachmentURL(sourceID: source.id, attachment: attachment),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            let scale = min(1, edge / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.78) { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return ["mime": "image/jpeg", "data": data.base64EncodedString()]
        }
    }

    struct VideoUpload {
        var video: Data? = nil
        var audio: Data? = nil
        var frames: [VideoKeyframe] = []
        var frameText = ""
        var sound: SoundVerdict? = nil
        var note = ""
    }

    /// Fresh read (signed URLs expire), download the video with that session's cookies, then decide on the phone
    /// what is worth sending: the frames where text appears (VideoReading.keyframes), and the audio only when
    /// someone speaks and TikTok has no captions of it. A video with no text on it at all goes as a small copy
    /// instead, so its pictures still reach the read. Up to five minutes.
    private static func videoUpload(for post: TikTokPostSnapshot) async -> VideoUpload {
        var upload = VideoUpload()
        guard (post.durationSeconds ?? 0) <= 300, let link = URL(string: post.canonicalURL) else { upload.note = "too long"; return upload }
        let reader = TikTokPageReader()
        guard (try? await reader.read(link, into: nil)) != nil else { upload.note = "page not readable"; return upload }
        let video: URL
        do { video = try await reader.downloadVideo() } catch { upload.note = "download failed: \(error)"; return upload }
        defer { try? FileManager.default.removeItem(at: video) }
        let ignore = Set((post.authorHandle ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        async let sound = VideoReading.sound(of: video)
        async let frames = VideoReading.keyframes(of: video, ignoring: ignore)
        upload.sound = await sound
        let picked = await frames
        let hasText = picked.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasText {
            upload.frames = picked
            upload.frameText = picked.filter { !$0.text.isEmpty }
                .map { "[\(Int($0.time) / 60):\(String(format: "%02d", Int($0.time) % 60))] " + $0.text.replacingOccurrences(of: "\n", with: " / ") }
                .joined(separator: "\n")
            upload.note = "\(picked.count) frames with text"
        } else if let small = await shrunkenVideo(video) {
            upload.video = small; upload.note = "video (no text on the frames)"
        } else {
            upload.frames = picked; upload.note = "\(picked.count) frames"
        }
        // Speech with no TikTok captions: send the voice. A song or silence: nothing to listen to.
        if upload.video == nil, upload.sound?.hasVoice == true, (post.transcript ?? "").isEmpty, let audio = await audioTrack(of: video) {
            upload.audio = audio; upload.note += " + voice"
        }
        if let sound = upload.sound { upload.note += " · sound: \(sound.kind.rawValue)" }
        return upload
    }

    /// 1 fps (Gemini samples video at 1 fps anyway), at most 540 px wide, H.264 + mono AAC, under ~8 MB so the
    /// request stays inside Gemini's inline limit. Text drawn on the frames stays readable; a 30 s post is ~1 MB.
    private static func shrunkenVideo(_ source: URL, budgetBytes: Double = 8_000_000) async -> Data? {
        let asset = AVURLAsset(url: source)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform),
              let duration = try? await asset.load(.duration).seconds, duration > 0, natural.width > 0 else { return nil }
        let sound = try? await asset.loadTracks(withMediaType: .audio).first
        let scale = min(1, 540 / natural.width)
        let width = Int(natural.width * scale / 2) * 2, height = Int(natural.height * scale / 2) * 2
        let bitrate = max(120_000, min(450_000, Int(budgetBytes * 8 / duration) - 32_000))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else { return nil }

        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        frames.alwaysCopiesSampleData = false
        let frameInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoMaxKeyFrameIntervalKey: 10,
                                              AVVideoExpectedSourceFrameRateKey: 1]])
        frameInput.transform = transform
        frameInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(frames), writer.canAdd(frameInput) else { return nil }
        reader.add(frames); writer.add(frameInput)

        var samples: AVAssetReaderTrackOutput?, sampleInput: AVAssetWriterInput?
        if let sound {
            let out = AVAssetReaderTrackOutput(track: sound, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(out), writer.canAdd(input) { reader.add(out); writer.add(input); samples = out; sampleInput = input }
        }
        guard reader.startReading(), writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        // Pull both tracks in turn (the writer stalls one input until the other catches up), keeping one frame per second.
        var framesDone = false, samplesDone = samples == nil, nextFrame = 0.0
        while !(framesDone && samplesDone) {
            var moved = false
            if !framesDone, frameInput.isReadyForMoreMediaData {
                moved = true
                if let buffer = frames.copyNextSampleBuffer() {
                    let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                    if time >= nextFrame { guard frameInput.append(buffer) else { break }; nextFrame = time + 1 }
                } else { frameInput.markAsFinished(); framesDone = true }
            }
            if !samplesDone, let samples, let sampleInput, sampleInput.isReadyForMoreMediaData {
                moved = true
                if let buffer = samples.copyNextSampleBuffer() { guard sampleInput.append(buffer) else { break } }
                else { sampleInput.markAsFinished(); samplesDone = true }
            }
            if reader.status == .failed || writer.status == .failed { break }
            if !moved { try? await Task.sleep(nanoseconds: 2_000_000) }
        }
        guard framesDone, samplesDone, reader.status == .completed else { reader.cancelReading(); writer.cancelWriting(); return nil }
        await writer.finishWriting()
        guard writer.status == .completed, let data = try? Data(contentsOf: output), Double(data.count) <= budgetBytes * 1.2 else { return nil }
        return data
    }

    /// Keep only an AAC audio track of a downloaded video.
    private static func audioTrack(of video: URL) async -> Data? {
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
