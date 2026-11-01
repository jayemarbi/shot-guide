import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks the DANCE song: from a video or screen recording in Photos, or an audio file in Files.
struct SongPickerSheet: View {
    @EnvironmentObject var songs: SongLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var importingFile = false
    @State private var working: String? = nil
    @State private var errorText: String? = nil
    /// A picked file waiting for its name.
    @State private var pending: URL? = nil
    @State private var newName = ""
    @State private var naming = false

    var body: some View {
        NavigationStack {
            List {
                addSection
                if let working {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(working)
                        }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(Color.red)
                    }
                }
                songsSection
            }
            .navigationTitle("Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.audio, .movie]) { result in
                pickedFile(result)
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                pickedVideo(item)
            }
            .alert("Name this song", isPresented: $naming) {
                TextField("Song name", text: $newName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) { discardPending() }
            } message: {
                Text("Like the song and artist, so you can find it again.")
            }
            .onAppear { songs.reload() }
        }
    }

    private var addSection: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .videos, preferredItemEncoding: .current) {
                Label("From a video or screen recording", systemImage: "photo.on.rectangle")
            }
            Button {
                importingFile = true
            } label: {
                Label("From Files", systemImage: "folder")
            }
        } header: {
            Text("Add a song")
        } footer: {
            Text("For a trending sound, screen-record the reel with its sound on and pick the recording. "
                + "Use the exact version you'll post with, as a sped-up or remixed one throws the timing off.")
        }
    }

    private var songsSection: some View {
        Section {
            if songs.songs.isEmpty {
                Text("No songs yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(songs.songs) { song in
                Button {
                    songs.selectedFile = song.fileName
                    dismiss()
                } label: {
                    songRow(song)
                }
                .foregroundStyle(Color.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    songs.delete(songs.songs[index])
                }
            }
        } header: {
            Text("Your songs")
        } footer: {
            Text("Kept in On My iPhone › Shot Guide › Songs, for every trip. Swipe left to delete one.")
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack {
            Image(systemName: "music.note")
                .foregroundStyle(Color.orange)
            Text(song.name)
            Spacer()
            if songs.selectedFile == song.fileName {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
            }
        }
        .contentShape(Rectangle())
    }

    private func pickedVideo(_ item: PhotosPickerItem) {
        errorText = nil
        working = "Getting the video…"
        Task { @MainActor in
            defer { photoItem = nil }
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    working = nil
                    errorText = "That video couldn't be read."
                    return
                }
                working = nil
                askForName(movie.url, suggested: "")
            } catch {
                working = nil
                errorText = "That video couldn't be read."
            }
        }
    }

    private func pickedFile(_ result: Result<URL, Error>) {
        errorText = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let copy = try MediaImporter.copyToTemporary(url, fallbackExtension: "m4a")
            askForName(copy, suggested: SongLibrary.suggestedName(for: url))
        } catch {
            errorText = "That file couldn't be read."
        }
    }

    private func askForName(_ url: URL, suggested: String) {
        pending = url
        newName = suggested
        naming = true
    }

    private func save() {
        guard let source = pending else { return }
        pending = nil
        let name = newName
        working = "Saving the song…"
        Task { @MainActor in
            do {
                _ = try await songs.add(from: source, name: name)
                working = nil
                try? FileManager.default.removeItem(at: source)
                dismiss()
            } catch {
                working = nil
                errorText = error.localizedDescription
                try? FileManager.default.removeItem(at: source)
            }
        }
    }

    private func discardPending() {
        if let pending {
            try? FileManager.default.removeItem(at: pending)
        }
        pending = nil
    }
}

/// Picks where in the song a take starts, with a play button to hear the spot.
struct SongPointSheet: View {
    let songURL: URL
    @Binding var point: Double

    @StateObject private var preview = SongPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(clockString(point))
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                Slider(value: $point, in: 0...max(preview.duration, 1))
                    .tint(.orange)
                controls
                Text("The song starts during the countdown, so this point lands as recording starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Where to start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { preview.load(songURL) }
            .onDisappear { preview.stop() }
        }
        .presentationDetents([.medium])
    }

    private var controls: some View {
        HStack {
            Button("Back 5 s") {
                point = max(0, point - 5)
            }
            Spacer()
            Button {
                if preview.isPlaying {
                    preview.stop()
                } else {
                    preview.play(from: point, after: 0)
                }
            } label: {
                Label(preview.isPlaying ? "Stop" : "Play from here", systemImage: preview.isPlaying ? "stop.fill" : "play.fill")
                    .font(.headline)
            }
            Spacer()
            Button("On 5 s") {
                point = min(max(preview.duration - 1, 0), point + 5)
            }
        }
    }
}
