import Foundation

/// Gets a trip's clips ready for editing before they leave the phone: a cutout mask for every shot
/// you're in, and captions for the shots where you talk. Each clip is only done once.
enum ClipPrep {
    static let talkingShots: Set<String> = [
        ShotType.talk.rawValue,
        ShotType.reaction.rawValue,
        ShotType.stay.rawValue,
        ShotType.voiceover.rawValue
    ]

    /// Takes longer than this say so while their cutout's made, as it takes a few minutes.
    static let longTake: Double = 120

    /// Every shot you're in gets a cutout, long takes and DANCE included (1.24.1): text behind you, clones that
    /// overlap, silhouettes and cutout effects all need one. TIMELAPSE is left out: you're not really in it.
    static func needsMask(_ clip: Clip) -> Bool {
        clip.isOnPhone && clip.inShot && clip.shot != ShotType.timelapse.rawValue && clip.maskFileName == nil
    }

    static func needsCaptions(_ clip: Clip) -> Bool {
        clip.isOnPhone && talkingShots.contains(clip.shot) && clip.transcript == nil
    }

    static func baseName(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// What couldn't be done this time (1.25), so it's said rather than skipped quietly.
    struct Report {
        /// Clips whose cutout couldn't be made, by name, like WIDE_03.
        var missedCutouts: [String] = []

        /// A line for the end of the copy, or nil when everything was made.
        var note: String? {
            guard !missedCutouts.isEmpty else { return nil }
            let names = missedCutouts.joined(separator: ", ")
            let what = missedCutouts.count == 1 ? "The cutout for \(names) couldn't be made" : "The cutouts for \(names) couldn't be made"
            return what + ". Copy again before you free up space and they'll be tried again."
        }
    }

    /// The short name the catalogue uses for a clip, like WIDE_03.
    static func shortName(_ clip: Clip) -> String {
        "\(clip.shot)_\(String(format: "%02d", clip.take))"
    }

    /// Updates the trip as it goes, so anything finished is kept even if you leave the app.
    /// The slow work runs off the main thread; `status` is called with a line to show on screen.
    @MainActor
    @discardableResult
    static func prepare(tripID: UUID, store: TripStore, status: @escaping (String) -> Void) async -> Report {
        var report = Report()
        guard let trip = store.trip(id: tripID) else { return report }
        let folder = store.folderURL(for: trip)

        let maskClips = trip.clips.filter { needsMask($0) }
        for (index, clip) in maskClips.enumerated() {
            let long = clip.durationSeconds > longTake
                ? " This one's \(clockString(clip.durationSeconds)) long, so it takes a few minutes."
                : ""
            status("Making cutouts of you: \(index + 1) of \(maskClips.count)…" + long)
            let maskName = baseName(clip.fileName) + "_mask.mov"
            // A second try for one that fails, as a hiccup (the app going to the background, say) can stop it.
            var made = false
            for _ in 0..<2 where !made {
                do {
                    // Log clips are flat and grey; the person finder works better on them made to look normal.
                    try await MaskMaker.makeMask(
                        for: folder.appendingPathComponent(clip.fileName),
                        to: folder.appendingPathComponent(maskName),
                        look: clip.isLog ? CubeLUT.standard : nil)
                    made = true
                } catch {
                    // Tried again, or left for next time. The copy carries on without this mask.
                }
            }
            if made, var current = store.trip(id: tripID)?.clips.first(where: { $0.id == clip.id }) {
                current.maskFileName = maskName
                store.updateClip(current, in: tripID)
            } else if !made {
                report.missedCutouts.append(shortName(clip))
            }
        }

        let talkClips = trip.clips.filter { needsCaptions($0) }
        guard !talkClips.isEmpty else { return report }
        guard await Transcriber.requestPermission() else { return report }
        for (index, clip) in talkClips.enumerated() {
            status("Writing captions of what you said: \(index + 1) of \(talkClips.count)…")
            do {
                let result = try await Transcriber.transcribe(folder.appendingPathComponent(clip.fileName))
                guard var current = store.trip(id: tripID)?.clips.first(where: { $0.id == clip.id }) else { continue }
                if let result {
                    let captionsName = baseName(clip.fileName) + ".srt"
                    try Data(result.srt.utf8).write(to: folder.appendingPathComponent(captionsName), options: .atomic)
                    current.captionsFileName = captionsName
                    current.transcript = result.text
                } else {
                    // Checked, and there was no speech.
                    current.transcript = ""
                }
                store.updateClip(current, in: tripID)
            } catch {
                // Left for next time.
            }
        }
        return report
    }
}
