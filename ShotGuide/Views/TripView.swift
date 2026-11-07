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
    @State private var showAllShots = false
    /// New place: the name being typed for the place your next clip starts (1.21).
    @State private var askingNewPlace = false
    /// The scene being named, and the name being typed.
    @State private var namingScene: Int? = nil
    @State private var placeDraft = ""
    /// The last copy to a drive, so its clips can come off the phone.
    @State private var lastCopy: TripStore.CopySummary? = nil

    var body: some View {
        alerts(placeAlerts(sheets(page)))
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
            sceneSection(trip)
            ForEach(TripPhase.allCases) { phase in
                phaseSection(phase, trip: trip)
            }
            importSection
            clipsSection(trip)
        }
        .onAppear {
            // Where you are, for the light and for noticing a new scene before you film it.
            location.start()
            scheduleLightAlerts()
        }
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
            ShotCameraView(tripID: tripID, shot: slot.shot, day: currentDay, fixedVariant: slot.half, role: slot.role)
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
                coverageLine(trip, day: number)
                if store.spaceLeftText != nil {
                    spaceLine()
                }
            }
            .font(.subheadline)
            nextRow(trip, day: number)
            missingGroup(trip, day: number)
            if let copyProgress {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(copyProgress)
                        .font(.subheadline)
                }
            }
            typeRow(day)
            lightRow(trip)
            allShotsRow
            if trip.clips(onDay: number).isEmpty {
                Label("Before your first shot, wipe your lens. A smudge softens every shot.", systemImage: "sparkles")
                    .font(.subheadline)
            }
        } footer: {
            // One literal, so the symbols show as pictures.
            Text("\(Image(systemName: "checkmark.circle.fill")) confirmed usable · \(Image(systemName: "checkmark.circle")) counts for now (passed its check) · \(Image(systemName: "exclamationmark.triangle.fill")) doesn't count yet. Light, everyday and full build on each other: stop whenever you're happy.")
        }
    }

    // MARK: Coverage

    /// "Light day 10/10 ✓ · Everyday 14/22 · Full day 18/30", from the same takes.
    private func coverageLine(_ trip: Trip, day number: Int) -> some View {
        let coverage = trip.dayCoverage(number)
        let parts = CoverageLevel.allCases.map { level -> String in
            let done = coverage.done(level)
            let target = coverage.target(level)
            return "\(level.title) \(done)/\(target)" + (target > 0 && done >= target ? " ✓" : "")
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(parts.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if coverage.confirmed > 0 {
                Text("\(coverage.confirmed) confirmed usable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The next useful thing to film, one tap away: establish a new place when you've moved on, otherwise the first
    /// row the lowest unfinished level still needs, in the order of the day.
    @ViewBuilder
    private func nextRow(_ trip: Trip, day number: Int) -> some View {
        let newPlace = !trip.clips(onDay: number).isEmpty && nextClipStartsScene(trip, day: number)
        let next: ShotSuggestion? = newPlace
            ? Optional(sceneSuggestion(.establish, trip: trip, day: number))
            : trip.nextSuggestion(day: number)
        if let next {
            Button {
                activeSlot = next.slot
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next: " + next.title)
                            .font(.headline)
                        Text(newPlace ? "A new place: establish it first." : nextHint(next))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Label("A full day's coverage. Film whatever's worth it.", systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(Color.green)
        }
    }

    private func nextHint(_ next: ShotSuggestion) -> String {
        if let role = next.role.flatMap({ next.shot.role(withID: $0) }) {
            return role.purpose
        }
        return next.shot.summary
    }

    /// What each level still needs, role by role.
    @ViewBuilder
    private func missingGroup(_ trip: Trip, day number: Int) -> some View {
        let coverage = trip.dayCoverage(number)
        if !coverage.complete(.full) {
            DisclosureGroup {
                ForEach(CoverageLevel.allCases) { level in
                    let items = trip.missing(level, day: number)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(items.isEmpty ? "\(level.title): covered"
                             : "\(level.title): \(coverage.target(level) - coverage.done(level)) to go")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(items.isEmpty ? Color.green : Color.primary)
                        ForEach(items) { item in
                            Text(item.line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Text("What's still missing")
                    .font(.subheadline)
            }
        }
    }

    // MARK: Scenes

    /// Whether your next clip would start a new scene: your choice if you made one, otherwise the app's suggestion
    /// from where you are now and when you filmed last.
    private func nextClipStartsScene(_ trip: Trip, day number: Int) -> Bool {
        let coordinate = location.location?.coordinate
        return trip.nextClipStartsScene(day: number, latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                                        at: Date())
    }

    /// The place you're filming at, once the day has been at more than one: the role buttons show what's been filmed
    /// there (1.21).
    private func placeNow(_ trip: Trip, day number: Int) -> PlaceNow? {
        trip.placeNow(day: number, startsNew: nextClipStartsScene(trip, day: number))
    }

    @ViewBuilder
    private func sceneSection(_ trip: Trip) -> some View {
        let number = dayNumber(trip)
        let scenes = trip.scenes(onDay: number)
        if let current = scenes.last {
            Section {
                sceneStatusRow(trip, day: number, current: current)
                sceneCard(current, trip: trip, day: number, isCurrent: true, isFirst: scenes.count == 1)
                ForEach(Array(scenes.dropLast().reversed())) { scene in
                    sceneCard(scene, trip: trip, day: number, isCurrent: false, isFirst: scene.number == scenes.first?.number)
                }
            } header: {
                Text("Scene coverage")
            } footer: {
                Text("A scene is the clips from one place, so each can tell a short story. The app suggests them from "
                    + "distance and time. Tap New place when you get somewhere new, or name a place from its menu, and its "
                    + "clips get the name in their files. On a day at more than one place, the role buttons show what "
                    + "you've filmed at the one you're at. Merge, split or confirm scenes whenever you like: they never "
                    + "change the day's counts.")
            }
        }
    }

    /// What happens to the next clip, with the one tap to change it.
    @ViewBuilder
    private func sceneStatusRow(_ trip: Trip, day number: Int, current: ClipScene) -> some View {
        let choice = trip.nextScene?.day == number ? trip.nextScene : nil
        let startsNew = nextClipStartsScene(trip, day: number)
        VStack(alignment: .leading, spacing: 6) {
            if let choice {
                Label(choiceText(choice, current: current), systemImage: "hand.point.up.left.fill")
                    .font(.subheadline)
                Button("Undo") {
                    store.setNextScene(nil, day: number, tripID: tripID)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            } else if startsNew {
                Label("Looks like a new place: your next clip will start a new scene.", systemImage: "location.fill")
                    .font(.subheadline)
                HStack(spacing: 20) {
                    Button("Name it") {
                        placeDraft = ""
                        askingNewPlace = true
                    }
                    Button("Keep it in \(current.name)") {
                        store.setNextScene(false, day: number, tripID: tripID)
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            } else {
                Label("Filming at \(current.name).", systemImage: "location.fill")
                    .font(.subheadline)
                Button("New place") {
                    placeDraft = ""
                    askingNewPlace = true
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func choiceText(_ choice: SceneChoice, current: ClipScene) -> String {
        guard choice.startsNew else {
            return "Your next clip stays in \(current.name)."
        }
        if let name = choice.name {
            return "Your next clip starts a new place: \(name)."
        }
        return "Your next clip starts a new scene."
    }

    private func sceneCard(_ scene: ClipScene, trip: Trip, day number: Int, isCurrent: Bool, isFirst: Bool) -> some View {
        let have = scene.ingredients
        let count = scene.clips.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.name)
                        .font(.headline)
                    Text("\(count) \(count == 1 ? "clip" : "clips") · \(have.count) of 5 · "
                        + (scene.confirmed ? "confirmed" : "suggested"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(scene.placeName == nil ? "Name this place" : "Rename this place") {
                        placeDraft = scene.placeName ?? ""
                        namingScene = scene.number
                    }
                    if !scene.confirmed {
                        Button("Looks right") {
                            store.confirmScene(scene.number, day: number, tripID: tripID)
                        }
                    }
                    if !isFirst {
                        Button("Merge with the scene before") {
                            store.mergeScene(scene.number, day: number, tripID: tripID)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
            FlowLayout(spacing: 6) {
                ForEach(SceneIngredient.allCases) { ingredient in
                    if have.contains(ingredient) {
                        CoverageChip(text: ingredient.title, look: .done)
                    } else if isCurrent {
                        let suggestion = sceneSuggestion(ingredient, trip: trip, day: number)
                        Button {
                            activeSlot = suggestion.slot
                        } label: {
                            CoverageChip(text: "\(ingredient.title): \(suggestion.title)", look: .toFilm)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        CoverageChip(text: ingredient.title, look: .spare)
                    }
                }
            }
        }
    }

    /// The shot for a missing part of a scene's story: the first one the day still needs a role or take of, or
    /// else the first, as an extra that's new for this place.
    private func sceneSuggestion(_ ingredient: SceneIngredient, trip: Trip, day number: Int) -> ShotSuggestion {
        for candidate in ingredient.suggestions {
            let coverage = trip.coverage(for: ShotSlot(shot: candidate.shot, half: nil), day: number)
            if let role = candidate.role {
                if coverage.openRoleIDs.contains(role) {
                    return candidate
                }
            } else if !coverage.complete {
                return candidate
            }
        }
        return ingredient.suggestions[0]
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

    /// Every shot in the order of the day, with what you'd see in it and how to film it (1.20).
    private var allShotsRow: some View {
        Button {
            showAllShots = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All shots")
                        .font(.headline)
                    Text("What each one captures, where to film it and how")
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
                factsRow(trip, day: number)
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
            Text("Star time-lapses, Cinematic mode, drone or GoPro clips and photos, and screenshots of maps and bookings for guides. "
                + "They're named, tagged and copied to your SSD like the rest.")
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
                TripFactsView(tripID: tripID, day: currentDay)
            }
            .sheet(isPresented: $showStartDay) {
                StartDaySheet(tripID: tripID) { number in
                    selectedDay = number
                }
            }
            .sheet(isPresented: $showTypePicker) {
                TypePickerSheet(tripID: tripID, day: currentDay)
            }
            .sheet(isPresented: $showAllShots) {
                AllShotsView(type: store.trip(id: tripID)?.day(currentDay).type ?? .general)
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

    /// New place, and naming a place afterwards: a name box each, and the name is optional (1.21).
    private func placeAlerts<Page: View>(_ view: Page) -> some View {
        view
            .alert("New place", isPresented: $askingNewPlace) {
                TextField("Name it, like Twin Falls", text: $placeDraft)
                Button("Start") {
                    store.setNextScene(true, day: currentDay, tripID: tripID, name: placeDraft)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your next clip starts a new place. Its clips get the name, so their files are easy to tell apart. "
                    + "You can leave it blank.")
            }
            .alert(
                "Name this place",
                isPresented: Binding(get: { namingScene != nil }, set: { if !$0 { namingScene = nil } }),
                presenting: namingScene
            ) { scene in
                TextField("Name it, like Twin Falls", text: $placeDraft)
                Button("Save") {
                    store.namePlace(scene, day: currentDay, name: placeDraft, tripID: tripID)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its clips get the name, and their files too. Clips you've named yourself keep their own.")
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

    private static let factsHint = "Distance, time, cost and tips about this place, for on-screen text and guide reels"

    /// The facts about this day's place. Days at the same place share them.
    private func factsRow(_ trip: Trip, day: Int) -> some View {
        let facts = trip.dayFacts(day)
        let summary = facts?.summary ?? ""
        return Button {
            showFacts = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLACE FACTS")
                        .font(.headline)
                    Text(summary.isEmpty ? Self.factsHint : summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if facts != nil {
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
        let coverage = trip.coverage(for: slot, day: day)
        let summary = slot.summary(for: type)
        let tierLabel = slot.tier(for: type).label
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                activeSlot = slot
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: shot.defaultGroup == .inShot ? "person.fill" : "hand.raised.fill")
                        .frame(width: 28)
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(.headline)
                        Text(tierLabel.map { summary + " · " + $0 } ?? summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if shot != .voiceover {
                            FilmingTag(filming: shot.filming, mount: shot.mountSummary)
                                .padding(.top, 1)
                        }
                    }
                    Spacer()
                    progressBadge(coverage)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !coverage.roles.isEmpty {
                placeChips(slot, trip: trip, day: day, dayCoverage: coverage)
            }
        }
        .foregroundStyle(Color.primary)
    }

    /// The role chips: for the whole day, or, once the day has been at more than one place, for the place you're at,
    /// under its name. The count beside the shot stays the day's (1.21).
    @ViewBuilder
    private func placeChips(_ slot: ShotSlot, trip: Trip, day: Int, dayCoverage: SlotCoverage) -> some View {
        if let place = placeNow(trip, day: day) {
            VStack(alignment: .leading, spacing: 6) {
                Text(place.caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
                roleChips(trip.coverage(for: slot, day: day, at: place), slot: slot)
            }
        } else {
            roleChips(dayCoverage, slot: slot)
        }
    }

    /// "2/3", a tick once it's covered (filled once every take that counts is confirmed), and any extras or takes
    /// that don't count.
    private func progressBadge(_ coverage: SlotCoverage) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(coverage.done)/\(coverage.target)")
                    .font(.subheadline.monospacedDigit())
                if coverage.complete {
                    Image(systemName: coverage.fullyConfirmed ? "checkmark.circle.fill" : "checkmark.circle")
                }
            }
            .foregroundStyle(coverage.complete ? Color.green : Color.secondary)
            if coverage.extras > 0 {
                Text("+\(coverage.extras) extra")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if coverage.retakes > 0 {
                Text("\(coverage.retakes) not counted")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    /// One chip per creative role, named: tap one to film that role.
    private func roleChips(_ coverage: SlotCoverage, slot: ShotSlot) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(coverage.roles) { line in
                Button {
                    activeSlot = ShotSlot(shot: slot.shot, half: slot.half, role: line.role.id)
                } label: {
                    CoverageChip(text: line.role.title, look: roleLook(line, shotCovered: coverage.complete))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.leading, 40)
    }

    /// Green once a take counts for the role, a warning when its last take didn't, outlined for optional roles and
    /// swap-ins, and for the usual roles left once the shot is covered.
    private func roleLook(_ line: SlotCoverage.RoleLine, shotCovered: Bool) -> CoverageChip.Look {
        if line.confirmed > 0 {
            return .confirmed
        }
        if line.covered {
            return .covered
        }
        if line.retakes > 0 {
            return .retake
        }
        if line.role.isOptional {
            return .optional
        }
        if line.role.isSubstitute {
            return .swapIn
        }
        return shotCovered ? .spare : .toFilm
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
