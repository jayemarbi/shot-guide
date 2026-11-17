import SwiftUI
import UIKit

/// Tapping a shot (1.28): its card first, then the camera, which opens on exactly that shot.
struct ShotFlow: ViewModifier {
    let tripID: UUID
    let day: Int
    @Binding var card: ShotRow?
    /// Film it was tapped: the camera opens once the card has gone.
    @State private var pending: ShotRow? = nil
    @State private var filming: ShotRow? = nil

    func body(content: Content) -> some View {
        content
            .sheet(item: $card, onDismiss: startPending) { row in
                ShotCardView(tripID: tripID, day: day, row: row) {
                    pending = row
                }
            }
            .fullScreenCover(item: $filming) { row in
                ShotScreen(tripID: tripID, day: day, row: row)
            }
    }

    private func startPending() {
        guard let row = pending else { return }
        pending = nil
        filming = row
    }
}

extension View {
    /// Shows a row's card when `card` is set, and the camera after Film it.
    func shotFlow(tripID: UUID, day: Int, card: Binding<ShotRow?>) -> some View {
        modifier(ShotFlow(tripID: tripID, day: day, card: card))
    }
}

/// The camera for a row, or the recorder for VOICEOVER.
struct ShotScreen: View {
    let tripID: UUID
    let day: Int
    let row: ShotRow

    var body: some View {
        if row.shot == .voiceover {
            VoiceoverView(tripID: tripID, day: day)
        } else {
            ShotCameraView(tripID: tripID, shot: row.shot, day: day, fixedVariant: row.fixedVariant, role: row.role)
        }
    }
}

/// The card before a shot (1.28): what it is, where it goes in a reel, how to get it, and ideas to pick from, with a
/// still from your own best take once you have one. Film it opens the camera; Not now goes back to the list.
struct ShotCardView: View {
    let tripID: UUID
    let day: Int
    let row: ShotRow
    var onFilm: () -> Void

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    /// The ideas showing how: the first one to start with.
    @State private var openIdeas: Set<String> = []
    @State private var best: BestTake? = nil
    @State private var editingScript = false

    /// A still from your own take of this shot, from any trip: your starred one, or else the latest.
    struct BestTake {
        let clip: Clip
        let url: URL
        let caption: String
    }

    private var card: ShotCard { row.card }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let best {
                    bestStill(best)
                }
                section("What it is", card.what)
                if !card.whereItGoes.isEmpty {
                    section("Where it goes", card.whereItGoes)
                }
                if row.shot == .voiceover || (row.shot == .talk && row.variant == 0) {
                    scriptSection
                }
                howSection
                if !card.ideas.isEmpty {
                    ideasSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            buttons
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if openIdeas.isEmpty, let first = card.ideas.first {
                openIdeas = [first.id]
            }
        }
        .task(id: row.id) {
            best = findBest()
        }
        .sheet(isPresented: $editingScript) {
            ScriptSheet(tripID: tripID, shot: row.shot)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title)
                .font(.title2.weight(.bold))
            FlowLayout(spacing: 6) {
                ForEach(row.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.orange)
                        .fixedSize()
                }
            }
        }
    }

    private func bestStill(_ best: BestTake) -> some View {
        let wide = best.clip.orientation == Clip.landscape
        return VStack(alignment: .leading, spacing: 6) {
            ClipThumbnail(url: best.url, clip: best.clip)
                .frame(maxWidth: .infinity)
                .frame(height: wide ? 190 : 260)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Label(best.caption, systemImage: best.clip.favourite ? "star.fill" : "film")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading(title)
            Text(text)
                .foregroundStyle(Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("How to get it")
            ForEach(Array(card.how.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.black)
                        .frame(width: 24, height: 24)
                        .background(Color.orange, in: Circle())
                    Text(step)
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("Ideas")
                .padding(.bottom, 4)
            ForEach(card.ideas) { idea in
                let open = openIdeas.contains(idea.id)
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if open {
                                openIdeas.remove(idea.id)
                            } else {
                                openIdeas.insert(idea.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.orange)
                            Text(idea.title)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open {
                        Text(idea.how)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 28)
                            .padding(.bottom, 6)
                    }
                }
                Divider()
            }
        }
    }

    /// TALK at home and VOICEOVER read from your script.
    @ViewBuilder
    private var scriptSection: some View {
        let script = store.trip(id: tripID)?.script(for: row.shot)
        VStack(alignment: .leading, spacing: 8) {
            heading("Your script")
            if let script {
                Text(script)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(5)
                Button("Change the script") { editingScript = true }
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("No script yet. Paste in the one written from your place facts, and it scrolls while you "
                    + (row.shot == .voiceover ? "record." : "film."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Add your script") { editingScript = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .tint(.orange)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            Button {
                onFilm()
                dismiss()
            } label: {
                Text(row.shot == .voiceover ? "Record it" : "Film it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .tint(.orange)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Your best take

    private func findBest() -> BestTake? {
        var found: (clip: Clip, trip: Trip)? = nil
        for trip in store.trips {
            for clip in trip.clips where clip.isOnPhone && !clip.isPhoto && !clip.isAudio && clip.countsAsCoverage
                && ShotRow.forClip(clip)?.id == row.id {
                guard let current = found?.clip else {
                    found = (clip, trip)
                    continue
                }
                if clip.favourite != current.favourite ? clip.favourite : clip.recordedAt > current.recordedAt {
                    found = (clip, trip)
                }
            }
        }
        guard let found else { return nil }
        let name = found.clip.displayName ?? found.trip.place
        let caption = (found.clip.favourite ? "Your best one so far · " : "Your last one · ") + name
        return BestTake(clip: found.clip, url: store.clipURL(found.clip, in: found.trip), caption: caption)
    }
}
