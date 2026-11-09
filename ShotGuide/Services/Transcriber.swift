import AVFoundation
import Speech

/// Writes down what you say in a clip, on the phone, as plain text and as subtitles (.srt) the editor can time captions from.
enum Transcriber {
    struct Result {
        let text: String
        let srt: String
    }

    enum TranscribeError: Error {
        /// No offline speech recognition right now (e.g. the language isn't downloaded). Worth trying again later.
        case unavailable
        case failed
    }

    private enum Outcome {
        case heard([Word])
        case noSpeech
        case failed
    }

    /// A word heard, with when it was said, in seconds from the start of the clip.
    struct Word: Equatable {
        let text: String
        let start: Double
        let duration: Double
    }

    /// Everything heard in a clip, put together from the pieces the recogniser hands back (1.25). Since iOS 17 it
    /// hands back what you said up to each pause as a piece of its own, and its last piece only holds what came after
    /// the last pause, so keeping just that one lost everything else: on the test day, a 30-second voiceover came out
    /// as its last sentence. Each piece covers from its first word on, and replaces anything heard from then, so older
    /// iOS, where each piece repeats everything from the start, comes out the same.
    final class Heard {
        private(set) var words: [Word] = []

        func add(_ piece: [Word]) {
            guard let first = piece.first else { return }
            words.removeAll { $0.start >= first.start - 0.05 }
            words.append(contentsOf: piece)
            words.sort { $0.start < $1.start }
        }

        func add(_ transcription: SFTranscription) {
            add(transcription.segments.map {
                Word(text: $0.substring, start: $0.timestamp, duration: $0.duration)
            })
        }
    }

    static func requestPermission() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Returns nil when the clip has no speech in it. Throws when it couldn't be checked, so it's tried again next time.
    static func transcribe(_ clipURL: URL) async throws -> Result? {
        let locales = [Locale.current, Locale(identifier: "en-AU"), Locale(identifier: "en-US")]
        let recognizers = locales.compactMap { SFSpeechRecognizer(locale: $0) }
        guard let recognizer = recognizers.first(where: { $0.supportsOnDeviceRecognition && $0.isAvailable }) else {
            throw TranscribeError.unavailable
        }

        let asset = AVURLAsset(url: clipURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            return nil
        }

        // Speech recognition reads audio files, so pull the sound out of the clip first.
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        try await export.export(to: audioURL, as: .m4a)

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let heard = Heard()
        let outcome: Outcome = await withCheckedContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result {
                    // Every piece counts, not only the last.
                    heard.add(result.bestTranscription)
                    if result.isFinal {
                        finished = true
                        continuation.resume(returning: .heard(heard.words))
                        return
                    }
                }
                if let error {
                    finished = true
                    if !heard.words.isEmpty {
                        // It can end on an error after the pieces it heard, like silence at the end of the clip.
                        continuation.resume(returning: .heard(heard.words))
                        return
                    }
                    // "No speech detected" (code 1110) arrives as an error; anything else is a real failure.
                    let nsError = error as NSError
                    let noSpeech = nsError.code == 1110 || nsError.localizedDescription.localizedCaseInsensitiveContains("no speech")
                    continuation.resume(returning: noSpeech ? .noSpeech : .failed)
                }
            }
        }

        let words: [Word]
        switch outcome {
        case .heard(let heardWords):
            words = heardWords
        case .noSpeech:
            return nil
        case .failed:
            throw TranscribeError.failed
        }
        let text = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return Result(text: text, srt: srt(from: words))
    }

    /// Groups words into short caption lines: at most 5 words or 2.5 seconds each.
    static func srt(from words: [Word]) -> String {
        var lines: [(start: Double, end: Double, text: String)] = []
        var current: [Word] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            lines.append((start: first.start, end: last.start + last.duration, text: text))
            current = []
        }

        for word in words {
            if let first = current.first,
               current.count >= 5 || word.start + word.duration - first.start > 2.5 {
                flush()
            }
            current.append(word)
        }
        flush()

        return lines.enumerated().map { index, line in
            "\(index + 1)\n\(srtTime(line.start)) --> \(srtTime(line.end))\n\(line.text)\n"
        }.joined(separator: "\n")
    }

    static func srtTime(_ seconds: Double) -> String {
        let total = Int((max(seconds, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", total / 3_600_000, (total / 60_000) % 60, (total / 1000) % 60, total % 1000)
    }
}
