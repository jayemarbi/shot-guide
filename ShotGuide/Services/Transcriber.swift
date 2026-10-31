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
        case heard(SFTranscription)
        case noSpeech
        case failed
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

        let outcome: Outcome = await withCheckedContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: .heard(result.bestTranscription))
                } else if let error {
                    finished = true
                    // "No speech detected" (code 1110) arrives as an error; anything else is a real failure.
                    let nsError = error as NSError
                    let noSpeech = nsError.code == 1110 || nsError.localizedDescription.localizedCaseInsensitiveContains("no speech")
                    continuation.resume(returning: noSpeech ? .noSpeech : .failed)
                }
            }
        }

        let transcription: SFTranscription
        switch outcome {
        case .heard(let heard):
            transcription = heard
        case .noSpeech:
            return nil
        case .failed:
            throw TranscribeError.failed
        }
        let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return Result(text: text, srt: srt(from: transcription.segments))
    }

    /// Groups words into short caption lines: at most 5 words or 2.5 seconds each.
    static func srt(from segments: [SFTranscriptionSegment]) -> String {
        var lines: [(start: Double, end: Double, text: String)] = []
        var current: [SFTranscriptionSegment] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let words = current.map { $0.substring }.joined(separator: " ")
            lines.append((start: first.timestamp, end: last.timestamp + last.duration, text: words))
            current = []
        }

        for segment in segments {
            if let first = current.first,
               current.count >= 5 || segment.timestamp + segment.duration - first.timestamp > 2.5 {
                flush()
            }
            current.append(segment)
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
