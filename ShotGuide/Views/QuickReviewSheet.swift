import SwiftUI

/// The short card after a take (1.28), instead of the full review: name it, star it or delete it, then go again.
/// Every take you keep counts, so there's nothing to confirm. Tags, notes and the rest are under Clips, or behind the
/// play button.
struct QuickReviewSheet: View {
    let tripID: UUID
    let clipID: UUID
    /// "WIDE · Establishing".
    let title: String
    /// Something worth knowing about the take, like what a ONE TAKE's parts were saved as.
    var note: String? = nil
    /// Done: the camera closes too.
    var onDone: () -> Void

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var favourite = false
    @State private var loaded = false
    @State private var deleted = false
    @State private var confirmDelete = false
    @State private var showFull = false

    private var trip: Trip? { store.trip(id: tripID) }
    private var clip: Clip? { trip?.clips.first { $0.id == clipID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let clip, let trip {
                        picture(clip, trip: trip)
                        takeLines(clip)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name it")
                            .font(.headline)
                        NameField(name: $name, suggestions: trip?.nameSuggestions() ?? [])
                    }
                    HStack(spacing: 12) {
                        Button {
                            favourite.toggle()
                        } label: {
                            Label("Best take", systemImage: favourite ? "star.fill" : "star")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(favourite ? Color.yellow : Color.secondary)
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Every take you keep counts. Tags, notes and the rest are under Clips.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Another take")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        save()
                        onDone()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .tint(.orange)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .sheet(isPresented: $showFull, onDismiss: reload) {
            ReviewView(tripID: tripID, clipID: clipID, autoplay: true, preselectSuggestions: false, title: title)
        }
        .confirmationDialog("Delete this take?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleted = true
                if let clip, let trip {
                    Thumbnails.forget(store.clipURL(clip, in: trip))
                }
                store.deleteClip(clipID, from: tripID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from your phone.")
        }
    }

    /// The take's picture, with play to watch it in the full review.
    private func picture(_ clip: Clip, trip: Trip) -> some View {
        let wide = clip.orientation == Clip.landscape
        return Button {
            save()
            showFull = true
        } label: {
            ClipThumbnail(url: store.clipURL(clip, in: trip), clip: clip)
                .frame(width: wide ? nil : 210, height: wide ? 200 : 330)
                .frame(maxWidth: wide ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .shadow(radius: 6)
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch it")
    }

    /// "Take 1 · 10.4 s", the take check, and anything else worth knowing.
    @ViewBuilder
    private func takeLines(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Take \(clip.take) · " + String(format: "%.1f s", clip.durationSeconds))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if let check = clip.check {
                let passed = clip.checkPassed ?? true
                Label(check, systemImage: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(passed ? Color.green : Color.orange)
            }
            if clip.stoppedShort {
                Label("It stopped before its planned length. Keep it if it's good: it still counts.",
                      systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let note {
                Label(note, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() {
        guard !loaded, let clip else { return }
        loaded = true
        name = clip.name ?? ""
        favourite = clip.favourite
    }

    /// After the full review, which may have changed them.
    private func reload() {
        guard let clip else { return }
        name = clip.name ?? ""
        favourite = clip.favourite
    }

    private func save() {
        guard loaded, !deleted, let clip else { return }
        if clip.favourite != favourite {
            var updated = clip
            updated.favourite = favourite
            store.updateClip(updated, in: tripID)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if (clip.displayName ?? "") != trimmed {
            if let trip {
                Thumbnails.forget(store.clipURL(clip, in: trip))
            }
            store.setName(trimmed, clipID: clipID, tripID: tripID)
        }
    }
}
