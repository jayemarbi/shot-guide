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
    /// The day on screen. nil follows the latest day.
    @State private var selectedDay: Int? = nil
    @State private var showStartDay = false
    @State private var showTypePicker = false
    /// The last copy to a drive, so its clips can come off the phone.
    @State private var lastCopy: TripStore.CopySummary? = nil

    var body: some View {
        alerts(sheets(page))
    }

    // The page is built from small pieces so the compiler can type-check each one quickly.

    @ViewBuilder
    private var page: some View {
        if let trip = store.trip(id: tripID) {
            content(for: trip)
        } else {
            Text("This trip couldn't be found.")
                .foregroundStyle(.secondary)
        }
    }

    /// The day on screen: the one you picked, or the latest.
    private func dayNumber(_ trip: Trip) -> Int {
        min(selectedDay ?? trip.lastDayNumber, trip.lastDayNumber)
    }

    private var currentDay: Int {
        store.trip(id: tripID).map { dayNumber($0) } ?? 1
    }

    private func content(for trip: Trip) -> some View {
        List {
            daysSection(trip)
            headerSection(trip)
            ForEach(TripPhase.allCases) { phase in
                phaseSection(phase, trip: trip)
            }
            importSection
            clipsSection(trip)
        }
        .onAppear(perform: scheduleLightAlerts)
        .navigationTitle(trip.place)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                exportButton(trip)
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
        .fullScreenCover(item: $activeSlot) { slot in
            shotScreen(slot)
        }
    }

    @ViewBuilder
    private func shotScreen(_ slot: ShotSlot) -> some View {
        if slot.shot == .voiceover {
            VoiceoverView(tripID: tripID, day: currentDay)
        } else {
            ShotCameraView(tripID: tripID, shot: slot.shot, day: currentDay, fixedVariant: slot.half)
        }
    }

    @ViewBuilder
    private func exportButton(_ trip: Trip) -> some View {
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

    /// Day 1, Day 2… along the top, and a button to start the next day.
    private func daysSection(_ trip: Trip) -> some View {
        let current = dayNumber(trip)
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trip.allDays) { day in
                        dayChip(day, selected: day.number == current)
                    }
                    addDayChip(next: trip.lastDayNumber + 1)
                }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private func dayChip(_ day: TripDay, selected: Bool) -> some View {
        Button {
            selectedDay = day.number
        } label: {
            Text(selected ? day.label : "Day \(day.number)")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Color.orange : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    private func addDayChip(next: Int) -> some View {
        Button {
            showStartDay = true
        } label: {
            Label("Day \(next)", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.17), in: Capsule())
                .foregroundStyle(Color.orange)
        }
        .buttonStyle(.plain)
    }

    private func headerSection(_ trip: Trip) -> some View {
        let number = dayNumber(trip)
        let day = trip.day(number)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(regionText(trip, day: day))
                Text("\(trip.doneTotal(day: number)) of \(trip.targetTotal(day: number)) clips")
                    .foregroundStyle(.secondary)
                if store.spaceLeftText != nil {
                    spaceLine()
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
            typeRow(day)
            lightRow(trip)
            if trip.clips(onDay: number).isEmpty {
                Label("Before your first shot, wipe your lens. A smudge softens every shot.", systemImage: "sparkles")
                    .font(.subheadline)
            }
        }
    }

    private func regionText(_ trip: Trip, day: TripDay) -> String {
        [day.place, trip.regionLine].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func typeRow(_ day: TripDay) -> some View {
        Button {
            showTypePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: day.type.symbol)
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.type.title)
                        .font(.headline)
                    Text("Trip type for day \(day.number) · tap to change")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(Color.primary)
    }

    /// The light right now, so you know when to save the shots worth taking your time over.
    private func lightRow(_ trip: Trip) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let line: String = lightLine(for: trip, at: context.date)
                ?? "Sunrise and sunset times show up once your location is found."
            Label(line, systemImage: "sun.horizon.fill")
                .font(.subheadline)
                .foregroundStyle(Color.orange)
        }
    }

    private func phaseSection(_ phase: TripPhase, trip: Trip) -> some View {
        let number = dayNumber(trip)
        return Section {
            ForEach(phase.slots) { slot in
                slotRow(slot, trip: trip, day: number)
            }
            if phase.showsTripFacts {
                factsRow(trip)
            }
        } header: {
            Text(phase.title)
        } footer: {
            Text(phase.footer)
        }
    }

    private var importSection: some View {
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
    }

    @ViewBuilder
    private func clipsSection(_ trip: Trip) -> some View {
        let dayClips = trip.clips(onDay: dayNumber(trip)).sorted { $0.recordedAt > $1.recordedAt }
        if !dayClips.isEmpty {
            Section {
                ForEach(dayClips) { clip in
                    Button {
                        selectedClip = clip
                    } label: {
                        ClipRow(clip: clip)
                    }
                }
            } header: {
                Text("Clips")
            } footer: {
                Text("Tap a clip to rename, tag or star it. Export trip makes cutouts and captions for editing, then copies "
                    + "everything to your SSD, sorted into continent, country and state folders. Keep the app open while it works.")
            }
        }
    }

    private func sheets<Page: View>(_ view: Page) -> some View {
        view
            .sheet(isPresented: $showFacts) {
                TripFactsView(tripID: tripID)
            }
            .sheet(isPresented: $showStartDay) {
                StartDaySheet(tripID: tripID) { number in
                    selectedDay = number
                }
            }
            .sheet(isPresented: $showTypePicker) {
                TypePickerSheet(tripID: tripID, day: currentDay)
            }
            .sheet(item: $selectedClip) { clip in
                ReviewView(tripID: tripID, clipID: clip.id, autoplay: false, preselectSuggestions: false, title: "Clip")
            }
            .sheet(item: $sharing) { file in
                ShareSheet(items: [file.url])
            }
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                importItems(items)
            }
    }

    /// Shows a message while `text` is set, and clears it when the alert closes.
    private func showing(_ text: Binding<String?>) -> Binding<Bool> {
        Binding(get: { text.wrappedValue != nil }, set: { if !$0 { text.wrappedValue = nil } })
    }

    private func alerts<Page: View>(_ view: Page) -> some View {
        view
            .alert("Trip copied", isPresented: showing($copiedMessage)) {
                if let lastCopy, !lastCopy.verified.isEmpty {
                    Button("Free up space") { freeUpSpace(lastCopy) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedMessage ?? "")
            }
            .alert("Added from Photos", isPresented: showing($importMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .alert("Export didn't work", isPresented: showing($exportError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
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
                Text(Self.exportedText(file))
            }
    }

    private static func exportedText(_ file: SharedFile) -> String {
        "\(file.url.lastPathComponent) is in the Shot Guide folder. Plug into your PC, open iTunes, click the phone button, "
            + "then File Sharing › Shot Guide, and save it. (In the Apple Devices app it's Files › Shot Guide.) "
            + "Delete it from the phone afterwards to free up space."
    }

    /// "Golden hour starts at 5:41 pm, sunset at 6:12 pm", from where you are now (or where the trip started).
    private func lightLine(for trip: Trip, at date: Date) -> String? {
        let coordinate = location.location?.coordinate
        guard let latitude = coordinate?.latitude ?? trip.latitude,
              let longitude = coordinate?.longitude ?? trip.longitude else { return nil }
        return SunCalc.lightLine(at: date, latitude: latitude, longitude: longitude)
    }

    /// "About 45 min of 4K space left", in red with a nudge when it's running low.
    private func spaceLine() -> some View {
        let space: String = store.spaceLeftText ?? ""
        let low: Bool = (store.minutesOfVideoLeft ?? 0) < 15
        let text: String = low ? space + ". Running low: copy a trip to your SSD to free some up." : space
        let colour: Color = low ? Color.red : Color.secondary
        return Text(text).foregroundStyle(colour)
    }

    /// Golden hour, sunset and blue hour alerts, for a trip you're filming now.
    private func scheduleLightAlerts() {
        guard let trip = store.trip(id: tripID) else { return }
        let now = Date()
        let lastDay = trip.day(trip.lastDayNumber)
        let filmingNow = now.timeIntervalSince(lastDay.startedAt) < 30 * 3600
            || trip.clips.contains { now.timeIntervalSince($0.recordedAt) < 12 * 3600 }
        guard filmingNow else { return }
        let coordinate = location.location?.coordinate
        guard let latitude = coordinate?.latitude ?? lastDay.latitude ?? trip.latitude,
              let longitude = coordinate?.longitude ?? lastDay.longitude ?? trip.longitude else { return }
        LightAlerts.schedule(place: lastDay.place, latitude: latitude, longitude: longitude)
    }

    /// Takes the clips that are safely on the drive off the phone. The trip still lists them.
    private func freeUpSpace(_ copy: TripStore.CopySummary) {
        store.freeUpSpace(tripID: tripID, verified: copy.verified)
        lastCopy = nil
    }

    private static let factsHint = "Distance, time, cost, tips: for on-screen text and guide reels"

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
                    Text(summary.isEmpty ? Self.factsHint : summary)
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
            let added = await MediaImporter.importItems(items, tripID: tripID, day: currentDay, store: store) { copyProgress = $0 }
            endExport()
            if added == items.count {
                importMessage = added == 1
                    ? "Added to the trip with its time, place and suggested tags. Tap it under Clips to pick its shot type and check the tags."
                    : "All \(added) added to the trip with their times, places and suggested tags. "
                        + "Tap each under Clips to pick its shot type and check the tags."
            } else {
                importMessage = "\(added) of \(items.count) added. The rest couldn't be read."
            }
        }
    }

    private func slotRow(_ slot: ShotSlot, trip: Trip, day: Int) -> some View {
        let shot = slot.shot
        let type = trip.day(day).type
        let count = slot.takeCount(in: trip, day: day)
        let target = slot.target(for: type)
        let summary = slot.summary(for: type)
        let counts = slot.counts(for: type)
        let done = count >= target
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
                    Text(counts ? summary : summary + " · extra")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if shot != .voiceover {
                        FilmingTag(filming: shot.filming, mount: shot.mountSummary)
                            .padding(.top, 1)
                    }
                }
                Spacer()
                Text("\(count)/\(target)")
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
                    lastCopy = summary
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
        return first + " They're in \(summary.path).\n\nFree up space takes the copied clips off this phone. "
            + "The trip keeps its shot list, names and counts."
    }
}

struct ClipRow: View {
    let clip: Clip

    private var shotLine: String {
        "\(clip.shotType?.title ?? clip.shot) · take \(clip.take)"
    }

    private var detailLine: String {
        let tags = clip.tags.isEmpty ? "No tags yet" : clip.tags.joined(separator: ", ")
        return clip.displayName == nil ? tags : shotLine + " · " + tags
    }

    private var lengthText: String {
        clip.isOnPhone ? String(format: "%.0f s", clip.durationSeconds) : "On SSD"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(clip.displayName ?? shotLine)
                        .font(.subheadline.weight(.semibold))
                    if clip.favourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.yellow)
                    }
                    if clip.checkPassed == false {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(lengthText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
    }
}
