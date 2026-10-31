import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TripView: View {
    let tripID: UUID

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @State private var activeSlot: ShotSlot? = nil
    @State private var selectedClip: Clip? = nil
    @State private var exporting = false
    @State private var exportedFile: SharedFile? = nil
    @State private var sharing: SharedFile? = nil
    @State private var exportError: String? = nil
    @State private var pickingFolder = false
    @State private var copyProgress: String? = nil
    @State private var copiedMessage: String? = nil
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importMessage: String? = nil
    @State private var showFacts = false

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
                    Text("\(trip.doneTotal) of \(trip.targetTotal) clips")
                        .foregroundStyle(.secondary)
                    if let space = store.spaceLeftText {
                        let low = (store.minutesOfVideoLeft ?? 0) < 15
                        Text(low ? "\(space). Running low: copy a trip to your SSD to free some up." : space)
                            .foregroundStyle(low ? Color.red : Color.secondary)
                    }
                }
                .font(.subheadline)
                if let copyProgress {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(copyProgress)
                            .font(.subheadline)
                    }
                }
                // The light right now, so you know when to save the shots worth taking your time over.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Label(lightLine(for: trip, at: context.date) ?? "Sunrise and sunset times show up once your location is found.",
                          systemImage: "sun.horizon.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.orange)
                }
                if trip.clips.isEmpty {
                    Label("Before your first shot, wipe your lens. A smudge softens every shot.", systemImage: "sparkles")
                        .font(.subheadline)
                }
            }

            ForEach(TripPhase.allCases) { phase in
                Section {
                    ForEach(phase.slots) { slot in
                        slotRow(slot, trip: trip)
                    }
                    if phase == .leaving {
                        factsRow(trip)
                    }
                } header: {
                    Text(phase.title)
                } footer: {
                    Text(phase.footer)
                }
            }

            Section {
                PhotosPicker(selection: $pickedItems, matching: .any(of: [.videos, .images]), preferredItemEncoding: .current) {
                    Label("Add from Photos", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(exporting)
            } header: {
                Text("From other cameras")
            } footer: {
                Text("Star time-lapses, Cinematic mode, drone or GoPro clips and photos. They're named, tagged and copied to your SSD like the rest.")
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
                    Text("Tap a clip to tag it or star it. Export trip makes cutouts and captions for editing, then copies everything "
                        + "to your SSD, sorted into continent, country and state folders. Keep the app open while it works.")
                }
            }
        }
        .navigationTitle(trip.place)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if exporting {
                    ProgressView()
                } else {
                    Menu {
                        Button {
                            pickingFolder = true
                        } label: {
                            Label("Copy to SSD or folder", systemImage: "externaldrive")
                        }
                        Button {
                            export(trip)
                        } label: {
                            Label("Make a .zip file", systemImage: "doc.zipper")
                        }
                    } label: {
                        Label("Export trip", systemImage: "square.and.arrow.up")
                    }
                    .disabled(trip.clips.isEmpty)
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let folder):
                copy(trip, to: folder)
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
        .alert(
            "Trip copied",
            isPresented: Binding(get: { copiedMessage != nil }, set: { if !$0 { copiedMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedMessage ?? "")
        }
        .fullScreenCover(item: $activeSlot) { slot in
            if slot.shot == .voiceover {
                VoiceoverView(tripID: tripID)
            } else {
                ShotCameraView(tripID: tripID, shot: slot.shot, fixedVariant: slot.half)
            }
        }
        .sheet(isPresented: $showFacts) {
            TripFactsView(tripID: tripID)
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            importItems(items)
        }
        .alert(
            "Added from Photos",
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
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
            Text("\(file.url.lastPathComponent) is in the Shot Guide folder. Plug into your PC, open iTunes, click the phone button, then File Sharing › Shot Guide, and save it. (In the Apple Devices app it's Files › Shot Guide.) Delete it from the phone afterwards to free up space.")
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

    /// "Golden hour starts at 5:41 pm, sunset at 6:12 pm", from where you are now (or where the trip started).
    private func lightLine(for trip: Trip, at date: Date) -> String? {
        let coordinate = location.location?.coordinate
        guard let latitude = coordinate?.latitude ?? trip.latitude,
              let longitude = coordinate?.longitude ?? trip.longitude else { return nil }
        return SunCalc.lightLine(at: date, latitude: latitude, longitude: longitude)
    }

    private func factsRow(_ trip: Trip) -> some View {
        let summary = trip.facts?.summary ?? ""
        return Button {
            showFacts = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRIP FACTS")
                        .font(.headline)
                    Text(summary.isEmpty ? "Distance, time, cost, tips: for on-screen text and guide reels" : summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if trip.facts != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
            }
        }
        .foregroundStyle(Color.primary)
    }

    private func importItems(_ items: [PhotosPickerItem]) {
        pickedItems = []
        exporting = true
        copyProgress = "Adding from Photos…"
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in
            let added = await MediaImporter.importItems(items, tripID: tripID, store: store) { copyProgress = $0 }
            endExport()
            if added == items.count {
                importMessage = added == 1
                    ? "Added to the trip with its time, place and suggested tags. Tap it under Clips to check the tags."
                    : "All \(added) added to the trip with their times, places and suggested tags. Tap each under Clips to check the tags."
            } else {
                importMessage = "\(added) of \(items.count) added. The rest couldn't be read."
            }
        }
    }

    private func slotRow(_ slot: ShotSlot, trip: Trip) -> some View {
        let shot = slot.shot
        let count = slot.takeCount(in: trip)
        let done = count >= slot.target
        return Button {
            activeSlot = slot
        } label: {
            HStack(spacing: 12) {
                Image(systemName: shot.defaultGroup == .inShot ? "person.fill" : "hand.raised.fill")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title)
                        .font(.headline)
                    Text(shot.countsTowardTotal ? slot.summary : slot.summary + " · extra")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count)/\(slot.target)")
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

    /// Before a trip leaves the phone, make the cutouts and captions the editor needs. Clips already done are skipped.
    private func startExport() {
        exporting = true
        copyProgress = "Getting ready…"
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endExport() {
        exporting = false
        copyProgress = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func export(_ trip: Trip) {
        startExport()
        Task { @MainActor in
            await ClipPrep.prepare(tripID: tripID, store: store) { copyProgress = $0 }
            copyProgress = "Packing the .zip file…"
            store.exportTrip(store.trip(id: tripID) ?? trip) { result in
                endExport()
                switch result {
                case .success(let url):
                    exportedFile = SharedFile(url: url)
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func copy(_ trip: Trip, to folder: URL) {
        startExport()
        Task { @MainActor in
            await ClipPrep.prepare(tripID: tripID, store: store) { copyProgress = $0 }
            store.copyTrip(store.trip(id: tripID) ?? trip, to: folder, progress: { done, total in
                copyProgress = "Copying \(done) of \(total) files to \(folder.lastPathComponent)…"
            }, completion: { result in
                endExport()
                switch result {
                case .success(let summary):
                    copiedMessage = Self.copiedText(summary)
                case .failure(let error):
                    exportError = error.localizedDescription
                        + "\n\nCheck the SSD is plugged in and has space, then copy again. Clips that made it across won't be copied twice."
                }
            })
        }
    }

    private static func copiedText(_ summary: TripStore.CopySummary) -> String {
        func clips(_ count: Int) -> String {
            count == 1 ? "1 clip" : "\(count) clips"
        }
        let first: String
        if summary.copied == 0 {
            first = "Nothing new to copy: the clips were already on the drive, so only the catalogue was updated."
        } else if summary.alreadyThere == 0 {
            first = "\(clips(summary.copied)) copied."
        } else {
            let verb = summary.alreadyThere == 1 ? "was" : "were"
            first = "\(clips(summary.copied)) copied. \(clips(summary.alreadyThere)) already on the drive \(verb) skipped."
        }
        return first + " They're in \(summary.path).\n\nOnce you've checked them on the drive, you can delete the trip from your phone to free up space."
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
