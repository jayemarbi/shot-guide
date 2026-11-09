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

    /// The longest take that gets a cutout on the phone, in seconds.
    static let longestMasked: Double = 120

    static func needsMask(_ clip: Clip) -> Bool {
        // DANCE takes can run a whole song, and long takes like ONE TAKE and CLONE several minutes (1.24), which would
        // take ages to cut out on the phone and heat it up, so they're skipped: the editor cuts you out of those.
        clip.isOnPhone && clip.inShot && clip.shot != ShotType.timelapse.rawValue && clip.shot != ShotType.dance.rawValue
            && clip.durationSeconds <= longestMasked && clip.maskFileName == nil
    }

    static func needsCaptions(_ clip: Clip) -> Bool {
        clip.isOnPhone && talkingShots.contains(clip.shot) && clip.transcript == nil
    }

    static func baseName(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// Updates the trip as it goes, so anything finished is kept even if you leave the app.
    /// The slow work runs off the main thread; `status` is called with a line to show on screen.
    @MainActor
    static func prepare(tripID: UUID, store: TripStore, status: @escaping (String) -> Void) async {
        guard let trip = store.trip(id: tripID) else { return }
        let folder = store.folderURL(for: trip)

        let maskClips = trip.clips.filter { needsMask($0) }
        for (index, clip) in maskClips.enumerated() {
            status("Making cutouts of you: \(index + 1) of \(maskClips.count)…")
            let maskName = baseName(clip.fileName) + "_mask.mov"
            do {
                // Log clips are flat and grey; the person finder works better on them made to look normal.
                try await MaskMaker.makeMask(
                    for: folder.appendingPathComponent(clip.fileName),
                    to: folder.appendingPathComponent(maskName),
                    look: clip.isLog ? CubeLUT.standard : nil)
                if var current = store.trip(id: tripID)?.clips.first(where: { $0.id == clip.id }) {
                    current.maskFileName = maskName
                    store.updateClip(current, in: tripID)
                }
            } catch {
                // Left for next time. The copy carries on without this mask.
            }
        }

        let talkClips = trip.clips.filter { needsCaptions($0) }
        guard !talkClips.isEmpty else { return }
        guard await Transcriber.requestPermission() else { return }
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
    }
}
