import SwiftUI

/// Steps through clips and photos just added from Photos (1.28): what's in each, its name and, if you like, its shot.
/// What's in it goes in the catalogue, so the edit knows how to use something filmed on another camera.
struct AddedClipsSheet: View {
    let tripID: UUID
    let clipIDs: [UUID]
    /// Said on the first one, like "3 of 4 added".
    var note: String? = nil

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var about = ""
    @State private var name = ""
    @State private var loadedID: UUID? = nil

    private var trip: Trip? { store.trip(id: tripID) }

    private var clipID: UUID? {
        clipIDs.indices.contains(index) ? clipIDs[index] : nil
    }

    private var clip: Clip? {
        clipID.flatMap { id in trip?.clips.first { $0.id == id } }
    }

    private var isLast: Bool { index >= clipIDs.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let note, index == 0 {
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.orange)
                    }
                    if let clip, let trip {
                        preview(clip, trip: trip)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's in it?")
                            .font(.headline)
                        TextField("Like sunset from Trail Ridge Road, us in the car with the heater on", text: $about,
                                  axis: .vertical)
                            .lineLimit(2...5)
                            .padding(10)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        Text("Type it, or tap the mic on the keyboard and say it. It goes in the catalogue, so the edit "
                            + "knows how to use it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        NameField(name: $name, suggestions: trip?.nameSuggestions() ?? [])
                    }
                    if let clip {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Shot type")
                                    .font(.headline)
                                Spacer()
                                ShotTypeMenu(current: ShotRow.forClip(clip)) { row in
                                    store.setShot(of: row, clipID: clip.id, tripID: tripID)
                                }
                            }
                            Text("Optional. It puts it with that shot's clips, and it counts like one you filmed.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(clipIDs.count == 1 ? "Added from Photos" : "\(index + 1) of \(clipIDs.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        saveCurrent()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLast ? "Done" : "Next") {
                        next()
                    }
                }
            }
            .onAppear(perform: loadCurrent)
        }
    }

    private func preview(_ clip: Clip, trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ClipThumbnail(url: store.clipURL(clip, in: trip), clip: clip)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(whenLine(clip))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// "Video · Mon 16 Nov, 4:12 pm · 8 s".
    private func whenLine(_ clip: Clip) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, h:mm a"
        formatter.timeZone = TimeZone(identifier: clip.timeZoneID) ?? .current
        var parts = [clip.isPhoto ? "Photo" : "Video", formatter.string(from: clip.recordedAt)]
        if !clip.isPhoto && clip.durationSeconds > 0 {
            parts.append(String(format: "%.0f s", clip.durationSeconds))
        }
        return parts.joined(separator: " · ")
    }

    private func loadCurrent() {
        guard let clip, loadedID != clip.id else { return }
        loadedID = clip.id
        about = clip.about ?? ""
        name = clip.name ?? ""
    }

    private func saveCurrent() {
        guard let clip, loadedID == clip.id else { return }
        let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedAbout: String? = trimmedAbout.isEmpty ? nil : trimmedAbout
        if clip.about != wantedAbout {
            var updated = clip
            updated.about = wantedAbout
            store.updateClip(updated, in: tripID)
        }
        store.setName(name, clipID: clip.id, tripID: tripID)
    }

    private func next() {
        saveCurrent()
        if isLast {
            dismiss()
        } else {
            index += 1
            loadCurrent()
        }
    }
}
