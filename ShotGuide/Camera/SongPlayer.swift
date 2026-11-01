import AVFoundation
import Foundation

/// Plays the DANCE song in your AirPods (or on the phone's speaker), started during the countdown so the
/// part you picked lands as recording starts.
final class SongPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    /// The song played to its end.
    @Published private(set) var finished = false

    private var player: AVAudioPlayer?
    private var startTask: Task<Void, Never>?
    private(set) var loadedURL: URL?

    var duration: Double {
        player?.duration ?? 0
    }

    var currentTime: Double {
        player?.currentTime ?? 0
    }

    @discardableResult
    func load(_ url: URL) -> Bool {
        if loadedURL == url, player != nil {
            return true
        }
        stop()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            player = nil
            loadedURL = nil
            return false
        }
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        player = newPlayer
        loadedURL = url
        return true
    }

    /// Plays from `position` (seconds into the song) once `delay` seconds have passed.
    func play(from position: Double, after delay: Double) {
        guard let player else { return }
        startTask?.cancel()
        finished = false
        player.currentTime = max(0, min(position, max(player.duration - 0.1, 0)))
        let wait = max(0, delay)
        startTask = Task { @MainActor [weak self] in
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled, let self, let player = self.player else { return }
            player.play()
            self.isPlaying = true
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        player?.stop()
        isPlaying = false
    }

    /// Where in the song you're hearing right now, allowing for the delay in Bluetooth headphones like AirPods.
    /// nil while the song isn't playing.
    var heardPosition: Double? {
        guard let player, player.isPlaying else { return nil }
        return max(0, player.currentTime - AVAudioSession.sharedInstance().outputLatency)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.finished = true
        }
    }
}
