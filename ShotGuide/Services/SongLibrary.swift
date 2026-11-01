import AVFoundation
import Foundation

/// A song to dance to: an audio file in the Songs folder.
struct Song: Identifiable, Hashable {
    let fileName: String

    var id: String { fileName }
    var name: String { (fileName as NSString).deletingPathExtension }
}

enum SongError: LocalizedError {
    case noSound

    var errorDescription: String? {
        "That file has no sound the app can read."
    }
}

/// The songs you've added for DANCE, kept in On My iPhone › Shot Guide › Songs so every trip can use them.
/// Sound from videos and screen recordings is saved as .m4a. Audio files dropped into that folder with the
/// Files app show up too.
final class SongLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    /// The song DANCE plays, remembered between trips.
    @Published var selectedFile: String? {
        didSet { UserDefaults.standard.set(selectedFile, forKey: Self.selectedKey) }
    }

    static let selectedKey = "dance.song"
    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "caf"]

    let folder: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Songs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        selectedFile = UserDefaults.standard.string(forKey: Self.selectedKey)
        reload()
    }

    var selected: Song? {
        songs.first { $0.fileName == selectedFile }
    }

    func url(for song: Song) -> URL {
        folder.appendingPathComponent(song.fileName)
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        songs = files
            .filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { Song(fileName: $0) }
        if let selectedFile, !songs.contains(where: { $0.fileName == selectedFile }) {
            self.selectedFile = nil
        }
    }

    /// Saves the sound of a video, screen recording or audio file as a song called `name`, and picks it.
    @MainActor
    func add(from source: URL, name: String) async throws -> Song {
        let cleaned = Self.cleanName(name)
        let fileName = TripStore.freeName(cleaned + ".m4a", in: folder)
        let destination = folder.appendingPathComponent(fileName)
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty,
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SongError.noSound
        }
        try await export.export(to: destination, as: .m4a)
        reload()
        let song = Song(fileName: fileName)
        selectedFile = fileName
        return song
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(at: url(for: song))
        reload()
    }

    /// Letters, numbers, spaces and a little punctuation, so the name works as a file name everywhere.
    static func cleanName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -'&()."))
        let kept = String(name.unicodeScalars.filter { allowed.contains($0) })
        let trimmed = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Song" : String(trimmed.prefix(60))
    }

    /// The name a picked file suggests: its file name, unless it's a screen recording's random one.
    static func suggestedName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let looksRandom = base.count >= 30 || base.range(of: "^[0-9A-F-]{8,}$", options: .regularExpression) != nil
        return looksRandom ? "" : base
    }
}
