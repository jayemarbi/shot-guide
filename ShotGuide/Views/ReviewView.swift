import AVKit
import SwiftUI

/// Shown after each take (and when you tap a clip later): watch it back, tag it, star it or delete it.
struct ReviewView: View {
    let tripID: UUID
    let clipID: UUID
    var autoplay: Bool
    var preselectSuggestions: Bool
    var title: String

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var tagLibrary: TagLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer? = nil
    @State private var suggested: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var favourite = false
    @State private var notes = ""
    @State private var loaded = false
    @State private var deleted = false
    @State private var confirmDelete = false

    private var clip: Clip? {
        store.trip(id: tripID)?.clips.first { $0.id == clipID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let player {
                        VideoPlayer(player: player)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .frame(maxHeight: 420)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    if let clip {
                        details(for: clip)
                    }
                    Toggle(isOn: $favourite) {
                        Label("Best take", systemImage: "star.fill")
                    }
                    .tint(.yellow)
                    TagEditor(selected: $selected, suggested: suggested)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.headline)
                        TextField("Anything worth remembering", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(10)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
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
                Text("The video file is removed from your phone.")
            }
        }
    }

    private func details(for clip: Clip) -> some View {
        let parts = [clip.light, clip.lens, "\(clip.fps) fps", String(format: "%.1f s", clip.durationSeconds)]
        return VStack(alignment: .leading, spacing: 4) {
            Text(clip.fileName)
                .font(.subheadline.weight(.semibold))
            Text(parts.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard !loaded, let clip, let trip = store.trip(id: tripID) else { return }
        loaded = true
        selected = Set(clip.tags)
        favourite = clip.favourite
        notes = clip.notes
        let url = store.clipURL(clip, in: trip)
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        if autoplay {
            newPlayer.play()
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
        if updated != original {
            store.updateClip(updated, in: tripID)
        }
    }
}
