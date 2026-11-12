import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SoundAnalysis
import UniformTypeIdentifiers
import Vision

// MARK: - Reading a video on the phone, before anything is sent
//
// Two free, on-device passes decide what a shared video costs to read:
//
// Frames: the video is scanned small and often (a few times a second) with Apple's text recogniser. A frame is
// kept only when new words appear, at the moment they are fully visible (the most text in that stretch), plus a
// frame for the opening and an occasional one where the picture changes with no text. A route video whose stop
// names flash for a second each becomes about a dozen frames instead of a whole video upload.
//
// Sound: Apple's sound classifier listens in 1.5-second windows for speech, singing and music. A song (even with
// TikTok's auto-captions of its lyrics) means no transcript and no audio are sent; a voice-over, with or without
// music under it, keeps the transcript, or sends the audio when TikTok has none.
//
// Plain Foundation, AVFoundation, Vision and SoundAnalysis: it compiles for the Mac too, so it is tested there.

struct VideoKeyframe: Equatable {
    let time: Double
    let jpeg: Data
    /// What the text recogniser read on this frame, one line per piece of text.
    let text: String
}

enum SoundKind: String, Codable { case speech, mixed, music, silent }

struct SoundVerdict: Equatable {
    let kind: SoundKind
    /// Share of the windows with someone talking, and with music or singing.
    let speech: Double
    let music: Double
    /// Speech is there: the transcript is worth keeping.
    var hasVoice: Bool { kind == .speech || kind == .mixed }
}

enum VideoReading {
    // MARK: Frames

    struct Scan { let time: Double; let words: Set<String>; let characters: Int; let thumb: [UInt8] }
    /// Test hook: every decision the picker makes, as a line.
    nonisolated(unsafe) static var trace: ((String) -> Void)?

    /// The frames worth sending, oldest first, at most `maxFrames`, `edge` pixels on the long side.
    static func keyframes(of url: URL, maxFrames: Int = 35, edge: CGFloat = 768, ignoring: Set<String> = []) async -> [VideoKeyframe] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }
        // Two looks a second (a caption card stays up for a second or more), sparser for long videos (at most 180).
        // The accurate reader: the fast one misreads too much ("chrislmas") to tell new text from old.
        let step = max(0.5, duration / 180)
        let small = AVAssetImageGenerator(asset: asset)
        small.appliesPreferredTrackTransform = true
        small.maximumSize = CGSize(width: 560, height: 560)   // big enough for the fast reader to read a caption card
        small.requestedTimeToleranceBefore = CMTime(seconds: step / 2, preferredTimescale: 600)
        small.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)
        var scans: [Scan] = []
        var time = min(0.2, duration / 2)
        while time < duration {
            if let image = try? await small.image(at: CMTime(seconds: time, preferredTimescale: 600)).image {
                let lines = recognise(image, fast: false)
                scans.append(Scan(time: time, words: words(lines, ignoring: ignoring), characters: lines.joined().count, thumb: thumbnail(image)))
            }
            time += step
        }
        let times = choose(scans, maxFrames: maxFrames, duration: duration)
        let large = AVAssetImageGenerator(asset: asset)
        large.appliesPreferredTrackTransform = true
        large.maximumSize = CGSize(width: edge, height: edge)
        large.requestedTimeToleranceBefore = .zero
        large.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        var frames: [VideoKeyframe] = []
        for time in times {
            guard let image = try? await large.image(at: CMTime(seconds: time, preferredTimescale: 600)).image, let jpeg = jpeg(image) else { continue }
            frames.append(VideoKeyframe(time: (time * 10).rounded() / 10, jpeg: jpeg, text: recognise(image, fast: false).joined(separator: "\n")))
        }
        return frames
    }

    /// Which scanned moments to keep. Pure, so it is tested without a video.
    ///
    /// Scans group into stretches with the same words. A stretch that brings words not seen in any kept frame is
    /// kept at its fullest moment (most text: the card has finished fading in). Counters ("0.7 km walked") don't
    /// count as new: words are letters only. The first moment is kept as the cover; a picture change with no text
    /// for three seconds or more gets one frame, so a landmark shown without a caption isn't lost.
    static func choose(_ scans: [Scan], maxFrames: Int, duration: Double) -> [Double] {
        guard let first = scans.first else { return [] }
        struct Stretch { var scans: [Scan]; var words: Set<String> }
        var stretches: [Stretch] = []
        for scan in scans {
            if var last = stretches.last, similar(last.words, scan.words) {
                last.scans.append(scan); last.words.formUnion(scan.words); stretches[stretches.count - 1] = last
            } else {
                stretches.append(Stretch(scans: [scan], words: scan.words))
            }
        }
        var kept: [(time: Double, text: Bool)] = []
        var keptWords: [Set<String>] = []
        var seen = Set<String>()
        var lastThumb = first.thumb
        for stretch in stretches {
            if stretch.words.isEmpty {
                let span = (stretch.scans.last?.time ?? 0) - (stretch.scans.first?.time ?? 0)
                let middle = stretch.scans[stretch.scans.count / 2]
                if span >= 3, difference(middle.thumb, lastThumb) > 0.12 {
                    kept.append((middle.time, false)); keptWords.append([]); lastThumb = middle.thumb
                }
                continue
            }
            // New text means real new words: two or more, or a third of what is on screen. A misread letter
            // ("stop's" for "stops") is not a new card.
            trace?(String(format: "%5.2f–%5.2f ", stretch.scans.first!.time, stretch.scans.last!.time) + stretch.words.sorted().joined(separator: " "))
            let fresh = stretch.words.subtracting(seen).filter { word in !seen.contains { $0.hasPrefix(word.prefix(4)) || word.hasPrefix($0.prefix(4)) } }
            guard fresh.count >= 2 || Double(fresh.count) >= Double(stretch.words.count) / 3 && !fresh.isEmpty else { continue }
            let best = stretch.scans.max { ($0.words.count, $0.characters) < ($1.words.count, $1.characters) } ?? stretch.scans[0]
            // Text still fading in, followed within two seconds by the same text in full: keep only the full one.
            if let last = kept.last, last.text, best.time - last.time < 2.1, let previous = keptWords.last,
               Double(previous.filter { word in stretch.words.contains { $0.hasPrefix(word.prefix(3)) } }.count) >= Double(previous.count) / 2 {
                kept.removeLast(); keptWords.removeLast()
            }
            kept.append((best.time, true)); keptWords.append(stretch.words); seen.formUnion(stretch.words); lastThumb = best.thumb
        }
        // The opening frame is the cover, unless text already shows within the first two seconds.
        if !kept.contains(where: { $0.time <= first.time + 2 }) { kept.insert((first.time, false), at: 0) }
        // Over the limit: picture-only frames go first, then text frames are thinned evenly.
        if kept.count > maxFrames {
            let textOnly = kept.filter(\.text)
            kept = textOnly.count >= maxFrames ? stride(from: 0, to: textOnly.count, by: max(1, textOnly.count / maxFrames)).map { textOnly[$0] }
                : kept.filter(\.text) + kept.filter { !$0.text }.prefix(maxFrames - textOnly.count)
        }
        return Array(kept.map(\.time).sorted().prefix(maxFrames))
    }

    /// Two moments read the same when most of their words are shared (a card fading in is still the same card).
    static func similar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        let shared = Double(a.intersection(b).count)
        return shared / Double(min(a.count, b.count)) >= 0.6
    }

    /// Letters-only words of three or more characters, lowercased: numbers, counters and watermarks don't count.
    static func words(_ lines: [String], ignoring: Set<String> = []) -> Set<String> {
        let skip = ignoring.union(["tiktok", "original", "sound"])
        var out = Set<String>()
        for line in lines {
            for word in line.lowercased().split(whereSeparator: { !$0.isLetter }) where word.count >= 3 && !skip.contains(String(word)) {
                out.insert(String(word))
            }
        }
        return out
    }

    private static func recognise(_ image: CGImage, fast: Bool) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        request.minimumTextHeight = fast ? 0.018 : 0.012
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first }.filter { $0.confidence >= 0.3 }.map(\.string)
    }

    /// 12×12 grey picture, for telling a new scene from the same one.
    private static func thumbnail(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 144)
        guard let context = CGContext(data: &pixels, width: 12, height: 12, bitsPerComponent: 8, bytesPerRow: 12,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return pixels }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 12, height: 12))
        return pixels
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) / 255
    }

    private static func jpeg(_ image: CGImage, quality: Double = 0.72) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Sound

    /// Speech, music, both, or nothing. Needs a file with an audio track (an .m4a, or the video itself on the Mac).
    static func sound(of url: URL) async -> SoundVerdict {
        guard let analyzer = try? SNAudioFileAnalyzer(url: url),
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return SoundVerdict(kind: .silent, speech: 0, music: 0) }
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        let listener = Listener()
        guard (try? analyzer.add(request, withObserver: listener)) != nil else { return SoundVerdict(kind: .silent, speech: 0, music: 0) }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            analyzer.analyze { _ in done.resume() }
        }
        return verdict(listener.windows)
    }

    /// One window's scores for the labels that matter, pure so the decision is tested without audio.
    struct Window { let speech: Double; let singing: Double; let music: Double }

    static func verdict(_ windows: [Window]) -> SoundVerdict {
        guard !windows.isEmpty else { return SoundVerdict(kind: .silent, speech: 0, music: 0) }
        // A window is talk when speech clearly beats singing (lyrics are singing, not speech).
        let talk = windows.filter { $0.speech >= 0.45 && $0.speech > $0.singing + 0.1 }.count
        let tune = windows.filter { $0.music >= 0.45 || $0.singing >= 0.45 }.count
        let speech = Double(talk) / Double(windows.count), music = Double(tune) / Double(windows.count)
        let kind: SoundKind = speech >= 0.2 ? (music >= 0.3 ? .mixed : .speech) : music >= 0.25 ? .music : .silent
        return SoundVerdict(kind: kind, speech: (speech * 100).rounded() / 100, music: (music * 100).rounded() / 100)
    }

    private final class Listener: NSObject, SNResultsObserving {
        var windows: [Window] = []
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            func score(_ ids: [String]) -> Double { ids.compactMap { result.classification(forIdentifier: $0)?.confidence }.max() ?? 0 }
            windows.append(Window(speech: score(["speech", "conversation", "narration_monologue", "male_speech_man_speaking", "female_speech_woman_speaking"]),
                                  singing: score(["singing", "choir_singing", "rapping"]), music: score(["music"])))
        }
    }
}
