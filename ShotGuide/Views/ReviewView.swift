import AVKit
import ImageIO
import SwiftUI
import UIKit

/// A clip in full (tapped under Clips, or played from the card after a take): watch it back, name it, tag it, star it
/// or delete it. Every take you keep counts (1.28), so there's nothing to confirm.
struct ReviewView: View {
    let tripID: UUID
    let clipID: UUID
    var autoplay: Bool
    var preselectSuggestions: Bool
    var title: String

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var tagLibrary: TagLibrary
    @EnvironmentObject var looks: LookLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer? = nil
    @State private var photo: UIImage? = nil
    @State private var suggested: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var favourite = false
    /// The creative role, for shots with roles.
    @State private var roleChoice: String? = nil
    @State private var notes = ""
    @State private var name = ""
    /// What's in a clip from another camera (1.28), for the catalogue.
    @State private var about = ""
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
                    if clip?.isAdded == true {
                        aboutSection
                    }
                    nameSection
                    if let clip, clip.isAdded {
                        shotPicker(clip)
                    }
                    roleSection
                    if let clip, clip.isOneTake {
                        partsSection(clip)
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
            .onChange(of: favourite) { _, _ in saveCoverageChoices() }
            .onChange(of: roleChoice) { _, _ in saveCoverageChoices() }
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
            LogClipPlayer(player: player, orientation: logOrientation,
                          lookName: looks.selected.isAsRecorded ? "as recorded" : looks.selected.name, wide: wide)
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
                Text("A normal-looking copy with the \(looks.gradingLook.name) look, for posting from your phone. The clip itself stays in Log for the edit.")
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
        guard let clip, let trip = store.trip(id: tripID), let cube = looks.gradingCube else { return }
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

    // MARK: Coverage

    /// What a filmed take was for, like WIDE's Establishing, so a take filmed for the wrong one can be moved. Clips from
    /// another camera get theirs from Shot type.
    @ViewBuilder
    private var roleSection: some View {
        if let clip, let type = clip.shotType, !clip.isPhoto, !clip.isAdded, !type.roles.isEmpty {
            roleRow(type)
        }
    }

    private func roleRow(_ type: ShotType) -> some View {
        let current = roleChoice.flatMap { type.role(withID: $0) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Role")
                    .font(.headline)
                Spacer()
                if type.rolesAreVariants {
                    Text(current?.title ?? "Not set")
                        .fontWeight(.semibold)
                } else {
                    Menu {
                        ForEach(type.roles) { role in
                            Button(role.title) {
                                roleChoice = role.id
                            }
                        }
                    } label: {
                        Text(current?.title ?? "Not set")
                            .fontWeight(.semibold)
                    }
                }
            }
            if let current {
                Text(current.purpose)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// ONE TAKE's parts (1.24): what each counts as, and where it is in the take.
    private func partsSection(_ clip: Clip) -> some View {
        let parts = clip.parts ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Text("Parts")
                .font(.headline)
            if parts.isEmpty {
                Text("The take stopped before its first part, so it doesn't count for anything.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.takeTitle)
                                .font(.subheadline.weight(.semibold))
                            Text("\(part.title) · \(clockString(part.start)) to \(clockString(part.end)) · take \(part.take)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if player != nil {
                            Button {
                                player?.seek(to: CMTime(seconds: part.start, preferredTimescale: 600))
                                player?.play()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            if !parts.isEmpty {
                Text("Each part counts as a take of its own shot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Saves the coverage choices straight away, so the camera sees them as soon as the review closes.
    private func saveCoverageChoices() {
        guard loaded, !deleted, let original = clip else { return }
        var updated = original
        applyCoverageChoices(to: &updated, original: original)
        if updated != original {
            store.updateClip(updated, in: tripID)
        }
    }

    private func applyCoverageChoices(to updated: inout Clip, original: Clip) {
        updated.favourite = favourite
        if let roleChoice, roleChoice != original.roleID {
            updated.role = roleChoice
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.headline)
            NameField(name: $name, suggestions: store.trip(id: tripID)?.nameSuggestions() ?? [],
                      placeholder: "Name it, like Lower Falls or Plane")
        }
    }

    /// For clips from another camera (1.28): what's in it, in your words, for the catalogue.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's in it?")
                .font(.headline)
            TextField("Like sunset from the car, the heater on", text: $about, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// For clips added from Photos: which shot it is, so it sorts and counts with the rest.
    private func shotPicker(_ clip: Clip) -> some View {
        HStack {
            Text("Shot type")
                .font(.headline)
            Spacer()
            ShotTypeMenu(current: ShotRow.forClip(clip)) { row in
                save()
                store.setShot(of: row, clipID: clipID, tripID: tripID)
                roleChoice = store.trip(id: tripID)?.clips.first { $0.id == clipID }?.roleID
            }
        }
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
        if preview.displayName == clip.displayName {
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
        roleChoice = clip.roleID
        notes = clip.notes
        name = clip.name ?? ""
        about = clip.about ?? ""
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
        applyCoverageChoices(to: &updated, original: original)
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmedName.isEmpty ? nil : trimmedName
        let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
        if original.isAdded || original.about != nil {
            updated.about = trimmedAbout.isEmpty ? nil : trimmedAbout
        }
        if updated != original {
            store.updateClip(updated, in: tripID)
        }
        if updated.displayName != original.displayName {
            store.applyFileName(clipID: clipID, tripID: tripID)
        }
    }
}
