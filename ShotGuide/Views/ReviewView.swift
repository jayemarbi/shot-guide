import AVKit
import ImageIO
import SwiftUI
import UIKit

/// Shown after each take (and when you tap a clip later): watch it back, name it, tag it, star it or delete it.
struct ReviewView: View {
    let tripID: UUID
    let clipID: UUID
    var autoplay: Bool
    var preselectSuggestions: Bool
    var title: String
    /// A line under the name box when it was filled in for you, like "Same as your last clip here".
    var nameNote: String? = nil

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var tagLibrary: TagLibrary
    @EnvironmentObject var looks: LookLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer? = nil
    @State private var photo: UIImage? = nil
    @State private var suggested: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var favourite = false
    @State private var notes = ""
    @State private var name = ""
    @State private var shotName = ""
    @State private var loaded = false
    @State private var deleted = false
    @State private var confirmDelete = false
    /// Which way an Apple Log clip's frames are stored, for playing it through the look.
    @State private var logOrientation: CGImagePropertyOrientation = .right
    /// A wide clip, filmed with the phone sideways.
    @State private var wide = false
    @State private var copyState: CopyState = .idle

    enum CopyState: Equatable {
        case idle
        case working(Double)
        case done
        case failed(String)
    }

    /// Shot types a clip added from Photos can be given. Transitions need halves, so they're left out.
    static let importChoices: [ShotType] = ShotType.allCases.filter { !$0.isTransition && $0 != .voiceover && $0 != .quick }

    private var clip: Clip? {
        store.trip(id: tripID)?.clips.first { $0.id == clipID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    media
                    gradedCopySection
                    checkSection
                    nameSection
                    if clip?.isAdded == true {
                        shotPicker
                    }
                    if let clip {
                        details(for: clip)
                    }
                    Toggle(isOn: $favourite) {
                        Label("Best take", systemImage: "star.fill")
                    }
                    .tint(.yellow)
                    TagEditor(selected: $selected, suggested: suggested)
                    notesSection
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete this take", systemImage: "trash")
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .onDisappear {
                player?.pause()
                save()
            }
            .confirmationDialog("Delete this take?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleted = true
                    player?.pause()
                    store.deleteClip(clipID, from: tripID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(clip?.isOnPhone == false ? "It comes off this trip. The copy on your SSD stays." : "The file is removed from your phone.")
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var media: some View {
        if clip?.isOnPhone == false {
            Label("This clip is on your SSD now. Its name, tags and notes still save here.", systemImage: "externaldrive.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        } else if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 420)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let player, clip?.isAudio == true {
            // Sound only: just the play controls.
            VideoPlayer(player: player)
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let player, clip?.isLog == true {
            LogClipPlayer(player: player, orientation: logOrientation, lookName: looks.selected.name, wide: wide)
        } else if let player {
            VideoPlayer(player: player)
                .aspectRatio(wide ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
                .frame(maxHeight: 400)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Apple Log clips: save a normal-looking copy to Photos, for posting from the phone.
    @ViewBuilder
    private var gradedCopySection: some View {
        if let clip, clip.isLog, clip.isOnPhone, !clip.isPhoto {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    saveGradedCopy()
                } label: {
                    Label(copyButtonTitle, systemImage: copyState == .done ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isCopying)
                if case .working(let fraction) = copyState {
                    ProgressView(value: fraction)
                }
                if case .failed(let text) = copyState {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
                Text("A normal-looking copy with the \(looks.selected.name) look, for posting from your phone. The clip itself stays in Log for the edit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isCopying: Bool {
        if case .working = copyState { return true }
        return false
    }

    private var copyButtonTitle: String {
        switch copyState {
        case .idle, .failed: return "Save a graded copy to Photos"
        case .working: return "Saving the graded copy…"
        case .done: return "Saved to Photos"
        }
    }

    private func saveGradedCopy() {
        guard let clip, let trip = store.trip(id: tripID), let cube = looks.currentCube else { return }
        let url = store.clipURL(clip, in: trip)
        player?.pause()
        copyState = .working(0)
        Task {
            do {
                try await GradedCopy.saveToPhotos(clipURL: url, cube: cube) { fraction in
                    DispatchQueue.main.async {
                        if case .working = copyState {
                            copyState = .working(fraction)
                        }
                    }
                }
                copyState = .done
            } catch {
                copyState = .failed(error.localizedDescription)
            }
        }
    }

    /// The take check, for still shots: steady and level, or what to watch for.
    @ViewBuilder
    private var checkSection: some View {
        if let clip, let check = clip.check {
            let passed = clip.checkPassed ?? true
            Label(check, systemImage: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(passed ? Color.green : Color.orange)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.headline)
            TextField("Name it, like Lower Falls or Plane", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            if let nameNote, !name.isEmpty, name == clip?.displayName {
                Label(nameNote, systemImage: "location.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            recentNames
        }
    }

    @ViewBuilder
    private var recentNames: some View {
        let names = recentNameList
        if names.isEmpty {
            Text("Names you use show up here, one tap to reuse.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 8) {
                Text("Recent")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 7)
                ForEach(names, id: \.self) { recent in
                    TagChip(text: recent, isOn: recent == name.trimmingCharacters(in: .whitespaces), isSuggested: false) {
                        name = recent
                    }
                }
            }
        }
    }

    /// Names used on this trip, most recent first.
    private var recentNameList: [String] {
        guard let trip = store.trip(id: tripID) else { return [] }
        var names: [String] = []
        for other in trip.clips.sorted(by: { $0.recordedAt > $1.recordedAt }) {
            if let otherName = other.displayName, !names.contains(otherName) {
                names.append(otherName)
            }
            if names.count == 6 {
                break
            }
        }
        return names
    }

    /// For clips added from Photos: which shot it is, so it sorts and counts with the rest.
    private var shotPicker: some View {
        HStack {
            Text("Shot type")
                .font(.headline)
            Spacer()
            Menu {
                Button("Not set") { shotName = MediaImporter.shotName }
                ForEach(Self.importChoices) { choice in
                    Button(choice.title) { shotName = choice.rawValue }
                }
            } label: {
                Text(shotLabel)
                    .fontWeight(.semibold)
            }
        }
    }

    private var shotLabel: String {
        if shotName.isEmpty || shotName == MediaImporter.shotName {
            return "Not set"
        }
        return ShotType(rawValue: shotName)?.title ?? shotName
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.headline)
            TextField("Anything worth remembering", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func details(for clip: Clip) -> some View {
        let parts = [
            clip.light,
            clip.lens,
            clip.fps > 0 ? "\(clip.fps) fps" : "",
            clip.isPhoto ? "" : String(format: "%.1f s", clip.durationSeconds),
            clip.orientationLabel ?? ""
        ]
        let marks = (clip.marks ?? []).map { clockString($0) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(previewFileName(clip))
                .font(.subheadline.weight(.semibold))
            Text(parts.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let colour = colourLine(clip) {
                Text(colour)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !marks.isEmpty {
                Label("Marked at " + marks.joined(separator: ", "), systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color.yellow)
            }
            if let songName = clip.songName {
                Label(songLine(songName, start: clip.songStart), systemImage: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Apple Log · 5600 K · ISO 125 · 1/60"
    private func colourLine(_ clip: Clip) -> String? {
        guard let profile = clip.colourProfile else { return nil }
        var parts = [profile == Clip.appleLog ? "Apple Log" : "Normal colour"]
        if let balance = clip.whiteBalance {
            parts.append("\(balance.kelvin) K")
        }
        if let iso = clip.iso {
            parts.append("ISO \(iso)")
        }
        if let shutter = clip.shutterText {
            parts.append(shutter)
        }
        return parts.joined(separator: " · ")
    }

    /// "Song: Espresso, from 1:22 in"
    private func songLine(_ name: String, start: Double?) -> String {
        guard let start else { return "Song: " + name }
        return "Song: " + name + ", from " + clockString(start) + " in"
    }

    /// The file name with the name you're typing, so you can see how it'll be saved.
    private func previewFileName(_ clip: Clip) -> String {
        guard let trip = store.trip(id: tripID) else { return clip.fileName }
        var preview = clip
        preview.name = name
        if !shotName.isEmpty {
            preview.shot = shotName
        }
        if preview.displayName == clip.displayName && preview.shot == clip.shot {
            return clip.fileName
        }
        return store.expectedFileName(for: preview, in: trip)
    }

    // MARK: Loading and saving

    private func load() {
        guard !loaded, let clip, let trip = store.trip(id: tripID) else { return }
        loaded = true
        selected = Set(clip.tags)
        favourite = clip.favourite
        notes = clip.notes
        name = clip.name ?? ""
        shotName = clip.shot
        guard clip.isOnPhone else { return }
        let url = store.clipURL(clip, in: trip)
        if clip.isPhoto {
            photo = UIImage(contentsOfFile: url.path)
        } else {
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            if autoplay {
                newPlayer.play()
            }
            // Which way the frames are stored: for the look, and whether the clip is wide or tall.
            Task {
                if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                   let transform = try? await track.load(.preferredTransform),
                   let size = try? await track.load(.naturalSize) {
                    logOrientation = MaskMaker.orientation(of: transform)
                    let shown = size.applying(transform)
                    wide = abs(shown.width) > abs(shown.height)
                }
            }
        }
        let preselect = preselectSuggestions
        TagSuggester.suggest(for: url) { tags in
            suggested = Set(tags)
            if preselect {
                selected.formUnion(tags)
            }
        }
    }

    private func save() {
        guard !deleted, let original = clip else { return }
        var updated = original
        updated.tags = tagLibrary.ordered(selected)
        updated.favourite = favourite
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmedName.isEmpty ? nil : trimmedName
        if updated != original {
            store.updateClip(updated, in: tripID)
        }
        if !shotName.isEmpty && shotName != original.shot {
            // Renames the file as well.
            store.setShot(shotName, clipID: clipID, tripID: tripID)
        } else if updated.displayName != original.displayName {
            store.applyFileName(clipID: clipID, tripID: tripID)
        }
    }
}
