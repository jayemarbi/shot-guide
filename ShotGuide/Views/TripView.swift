import SwiftUI

struct TripView: View {
    let tripID: UUID

    @EnvironmentObject var store: TripStore
    @State private var activeShot: ShotType? = nil
    @State private var selectedClip: Clip? = nil
    @State private var exporting = false
    @State private var exportedFile: SharedFile? = nil
    @State private var sharing: SharedFile? = nil
    @State private var exportError: String? = nil

    var body: some View {
        Group {
            if let trip = store.trip(id: tripID) {
                content(for: trip)
            } else {
                Text("This trip couldn't be found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func content(for trip: Trip) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text([trip.regionLine, trip.continent].filter { !$0.isEmpty }.joined(separator: " · "))
                    Text("\(trip.doneTotal) of \(trip.targetTotal) clips · \(store.freeSpaceText)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Section("Do first") {
                ForEach(ShotType.allCases.filter { $0.doFirst }) { shot in
                    shotRow(shot, trip: trip)
                }
            }

            Section("Any order") {
                ForEach(ShotType.allCases.filter { !$0.doFirst }) { shot in
                    shotRow(shot, trip: trip)
                }
            }

            if !trip.clips.isEmpty {
                Section {
                    ForEach(trip.clips.sorted { $0.recordedAt > $1.recordedAt }) { clip in
                        Button {
                            selectedClip = clip
                        } label: {
                            ClipRow(clip: clip)
                        }
                    }
                } header: {
                    Text("Clips")
                } footer: {
                    Text("Tap a clip to tag it or star it. Export trip packs everything into one file for your PC.")
                }
            }
        }
        .navigationTitle(trip.place)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if exporting {
                    ProgressView()
                } else {
                    Button {
                        export(trip)
                    } label: {
                        Label("Export trip", systemImage: "square.and.arrow.up")
                    }
                    .disabled(trip.clips.isEmpty)
                }
            }
        }
        .fullScreenCover(item: $activeShot) { shot in
            ShotCameraView(tripID: tripID, shot: shot)
        }
        .sheet(item: $selectedClip) { clip in
            ReviewView(tripID: tripID, clipID: clip.id, autoplay: false, preselectSuggestions: false, title: "Clip")
        }
        .sheet(item: $sharing) { file in
            ShareSheet(items: [file.url])
        }
        .alert(
            "Trip exported",
            isPresented: Binding(get: { exportedFile != nil }, set: { if !$0 { exportedFile = nil } }),
            presenting: exportedFile
        ) { file in
            Button("Share…") {
                exportedFile = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sharing = file }
            }
            Button("OK", role: .cancel) {}
        } message: { file in
            Text("\(file.url.lastPathComponent) is in the Shot Guide folder. Plug into your PC and open Apple Devices › Files › Shot Guide to save it. Delete it from the phone afterwards to free up space.")
        }
        .alert(
            "Export didn't work",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func shotRow(_ shot: ShotType, trip: Trip) -> some View {
        let count = trip.takeCount(of: shot)
        let done = count >= shot.targetTakes
        return Button {
            activeShot = shot
        } label: {
            HStack(spacing: 12) {
                Image(systemName: shot.defaultGroup == .inShot ? "person.fill" : "hand.raised.fill")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shot.title)
                        .font(.headline)
                    Text(shot.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count)/\(shot.targetTakes)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(done ? Color.green : Color.secondary)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
            }
        }
        .foregroundStyle(Color.primary)
    }

    private func export(_ trip: Trip) {
        exporting = true
        store.exportTrip(trip) { result in
            exporting = false
            switch result {
            case .success(let url):
                exportedFile = SharedFile(url: url)
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }
}

struct ClipRow: View {
    let clip: Clip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(clip.shotType?.title ?? clip.shot) · take \(clip.take)")
                        .font(.subheadline.weight(.semibold))
                    if clip.favourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.yellow)
                    }
                }
                Text(clip.tags.isEmpty ? "No tags yet" : clip.tags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.0f s", clip.durationSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
    }
}
