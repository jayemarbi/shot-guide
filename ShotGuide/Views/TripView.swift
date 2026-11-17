import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A trip's page (1.28): where it is and how the day's going at the top, then a button for each part of the day in
/// the order you'd film them, B-roll for any time, what's filmed at home, and the day's clips.
struct TripView: View {
    let tripID: UUID

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @State private var exporting = false
    @State private var exportedFile: SharedFile? = nil
    @State private var sharing: SharedFile? = nil
    @State private var exportError: String? = nil
    @State private var pickingFolder = false
    @State private var copyProgress: String? = nil
    @State private var copiedMessage: String? = nil
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importMessage: String? = nil
    /// Clips just added from Photos, to say what's in each and name it.
    @State private var added: AddedClips? = nil
    @State private var showFacts = false
    @State private var showCosts = false
    /// The day on screen. nil follows the latest day.
    @State private var selectedDay: Int? = nil
    @State private var showStartDay = false
    @State private var showTypePicker = false
    @State private var showAllShots = false
    /// The city or town being typed.
    @State private var editingTown = false
    @State private var townDraft = ""
    /// The shot whose card is showing, for the ones filmed at home.
    @State private var card: ShotRow? = nil
    @AppStorage("clipsByName") private var clipsByName = false
    /// The last copy to a drive, so its clips can come off the phone.
    @State private var lastCopy: TripStore.CopySummary? = nil
    /// Heat and battery, shown here rather than in the camera, so nothing distracts you while you film (1.24).
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @State private var battery: Float = -1
    @State private var charging = false

    /// Clips added from Photos in one go.
    struct AddedClips: Identifiable {
        let id = UUID()
        let clipIDs: [UUID]
        let note: String?
    }

    var body: some View {
        alerts(sheets(phoneEvents(page)))
    }

    /// Keeps the heat and battery warning up to date (1.24).
    private func phoneEvents<Page: View>(_ view: Page) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                DispatchQueue.main.async { thermal = ProcessInfo.processInfo.thermalState }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
                readBattery()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                readBattery()
            }
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
        let day = dayNumber(trip)
        return List {
            daysSection(trip)
            headerSection(trip, day: day)
            daySection(trip, day: day)
            anyTimeSection(trip, day: day)
            homeSection(trip, day: day)
            clipsSection(trip, day: day)
        }
        .onAppear {
            // Where you are, for the light.
            location.start()
            scheduleLightAlerts()
            UIDevice.current.isBatteryMonitoringEnabled = true
            readBattery()
            thermal = ProcessInfo.processInfo.thermalState
        }
        .navigationTitle(trip.place)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                exportButton(trip)
            }
            ToolbarItem(placement: .primaryAction) {
                moreMenu(trip, day: day)
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
        .shotFlow(tripID: tripID, day: day, card: $card)
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

    /// The day's trip type, every shot explained, and the city or town.
    private func moreMenu(_ trip: Trip, day: Int) -> some View {
        Menu {
            Button {
                showTypePicker = true
            } label: {
                Label("Trip type: \(trip.day(day).type.title)", systemImage: trip.day(day).type.symbol)
            }
            Button {
                showAllShots = true
            } label: {
                Label("All shots", systemImage: "book.fill")
            }
            Button {
                townDraft = trip.town(onDay: day) ?? ""
                editingTown = true
            } label: {
                Label(trip.town(onDay: day).map { "City or town: \($0)" } ?? "Add the city or town",
                      systemImage: "building.2.fill")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
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

    // MARK: The top

    /// Where the day is, how it's going, the light, and anything about the phone worth knowing.
    private func headerSection(_ trip: Trip, day: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if !whereText(trip, day: day).isEmpty {
                    Text(whereText(trip, day: day))
                        .font(.subheadline.weight(.semibold))
                }
                coverageLine(trip, day: day)
                lightRow(trip)
                if store.spaceLeftText != nil {
                    spaceLine()
                }
                if let warning = phoneWarning {
                    Label(warning.text, systemImage: warning.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(warning.critical ? Color.red : Color.orange)
                        .padding(.top, 2)
                }
                if let copyProgress {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(copyProgress)
                    }
                    .padding(.top, 2)
                }
                if trip.clips(onDay: day).isEmpty {
                    Label("Before your first shot, wipe your lens. A smudge softens every shot.", systemImage: "sparkles")
                        .padding(.top, 2)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
    }

    /// "Estes Park · Colorado · United States", with the day's place first on a day somewhere new.
    private func whereText(_ trip: Trip, day: Int) -> String {
        let place = trip.day(day).place
        let line = trip.whereLine(day: day)
        guard place != trip.place, !place.isEmpty else { return line }
        return [place, line].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Everyday 13 of 22 · Full day 13 of 25", from the same takes, with a tick for a light day once it's done.
    private func coverageLine(_ trip: Trip, day: Int) -> some View {
        let coverage = trip.dayCoverage(day)
        var parts: [String] = []
        if coverage.target(.light) > 0 && coverage.complete(.light) && !coverage.complete(.everyday) {
            parts.append("Light day ✓")
        }
        for level in [CoverageLevel.everyday, .full] {
            let done = coverage.done(level)
            let target = coverage.target(level)
            parts.append("\(level.title) \(done) of \(target)" + (target > 0 && done >= target ? " ✓" : ""))
        }
        return Text(parts.joined(separator: " · "))
            .foregroundStyle(.secondary)
    }

    /// The light right now, so you know when to save the shots worth taking your time over.
    private func lightRow(_ trip: Trip) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let line: String = lightLine(for: trip, at: context.date)
                ?? "Sunrise and sunset times show up once your location is found."
            Label(line, systemImage: "sun.horizon.fill")
                .foregroundStyle(Color.orange)
        }
    }

    /// Heat, then battery, when either could cut a take short. nil the rest of the time.
    private var phoneWarning: (text: String, symbol: String, critical: Bool)? {
        switch thermal {
        case .critical:
            return ("The phone is too hot to film well. Let it cool in the shade for a few minutes.",
                    "thermometer.sun.fill", true)
        case .serious:
            return ("The phone is getting hot, and recording may stop. Shade it between takes.", "thermometer.sun.fill", false)
        default:
            break
        }
        guard battery >= 0, !charging else { return nil }
        let percent = Int((battery * 100).rounded())
        if battery < 0.1 {
            return ("Battery at \(percent)%. The cold drains it faster, so keep the phone in a warm pocket between shots.",
                    "battery.25", true)
        }
        if battery < 0.25 {
            return ("Battery at \(percent)%. Plug in a power bank before a TIMELAPSE, HYPERLAPSE or ONE TAKE.",
                    "battery.25", false)
        }
        return nil
    }

    private func readBattery() {
        let device = UIDevice.current
        battery = device.batteryLevel
        charging = device.batteryState == .charging || device.batteryState == .full
    }

    // MARK: The parts of the day

    private func daySection(_ trip: Trip, day: Int) -> some View {
        Section {
            ForEach(TripPhase.dayParts) { part in
                partLink(part, trip: trip, day: day)
            }
        } header: {
            Text("Your day")
        } footer: {
            Text("Each part lists its shots in the order you'd film them, grouped by what the phone goes on.")
        }
    }

    private func anyTimeSection(_ trip: Trip, day: Int) -> some View {
        Section {
            partLink(.bRoll, trip: trip, day: day)
        } header: {
            Text("Any time")
        }
    }

    private func partLink(_ part: TripPhase, trip: Trip, day: Int) -> some View {
        let progress = trip.progress(of: part, day: day)
        return NavigationLink {
            PartView(tripID: tripID, day: day, part: part)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: part.symbol)
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.title)
                        .font(.headline)
                    Text(part.buttonLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                progressText(progress)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func progressText(_ progress: (done: Int, target: Int)) -> some View {
        if progress.target > 0 && progress.done >= progress.target {
            Label("\(progress.done) of \(progress.target)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.green)
        } else if progress.target > 0 {
            Text("\(progress.done) of \(progress.target)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: At home

    /// What's filmed before and after the trip, and the facts and costs it's written from (1.28).
    private func homeSection(_ trip: Trip, day: Int) -> some View {
        Section {
            ForEach(TripPhase.atHome.rows) { row in
                Button {
                    card = row
                } label: {
                    ShotRowLabel(title: row.title, line: homeLine(row, trip: trip), status: homeStatus(row, trip: trip))
                }
            }
            factsRow(trip, day: day)
            costsRow(trip, day: day)
            PhotosPicker(selection: $pickedItems, matching: .any(of: [.videos, .images]), preferredItemEncoding: .current) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add from Photos")
                            .font(.headline)
                        Text("Clips and photos from your other cameras")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(Color.orange)
                }
                .foregroundStyle(Color.primary)
            }
            .disabled(exporting)
        } header: {
            Text("At home")
        } footer: {
            Text("For after the trip. TALK and VOICEOVER read from a script written from your place facts.")
        }
    }

    /// TALK and VOICEOVER say whether there's a script yet.
    private func homeLine(_ row: ShotRow, trip: Trip) -> String {
        guard row.shot == .talk || row.shot == .voiceover else { return row.line }
        guard trip.script(for: row.shot) != nil else {
            return row.shot == .talk ? "Add your script, then read it to camera" : "Add your script, then read it over the footage"
        }
        return row.line
    }

    /// Filmed at home, so it counts across the whole trip: HOME's halves need one each.
    private func homeStatus(_ row: ShotRow, trip: Trip) -> RowStatus? {
        let filmed = trip.allDays.reduce(0) { $0 + trip.takes(of: row, day: $1.number).count }
        if filmed > 0 {
            return .filmed(filmed)
        }
        return row.shot == .home ? RowStatus.progress(done: 0, target: 1) : nil
    }

    private static let factsHint = "Distance, time, costs, your rating and tips, for scripts, guides and on-screen text"

    /// The facts about this day's place. Days at the same place share them.
    private func factsRow(_ trip: Trip, day: Int) -> some View {
        let facts = trip.dayFacts(day)
        let summary = facts?.summary ?? ""
        return Button {
            showFacts = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Place facts")
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

    /// What you've spent at this day's place, and the quickest way to add a cost the moment you pay (1.27).
    private func costsRow(_ trip: Trip, day: Int) -> some View {
        let costs = trip.dayFacts(day)?.costs ?? []
        let line = costs.isEmpty ? "Add what you pay for as you go, for price lists and cost guides"
            : "Spent " + trip.totalLine(costs)
        return Button {
            showCosts = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Costs")
                        .font(.headline)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.orange)
            }
        }
        .foregroundStyle(Color.primary)
    }

    // MARK: Clips

    /// The day's clips by shot or by name (1.28): a count for each, to tap into.
    @ViewBuilder
    private func clipsSection(_ trip: Trip, day: Int) -> some View {
        let dayClips = trip.clips(onDay: day)
        if !dayClips.isEmpty {
            let groups = clipsByName ? ClipGroup.byName(dayClips) : ClipGroup.byShot(dayClips)
            Section {
                Picker("Group clips", selection: $clipsByName) {
                    Text("By shot").tag(false)
                    Text("By name").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                ForEach(groups) { group in
                    NavigationLink {
                        ClipGroupView(tripID: tripID, day: day, group: group)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.headline)
                                    .foregroundStyle(group.title == "No name yet" ? Color.secondary : Color.primary)
                                if let detail = group.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(group.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Clips · \(dayClips.count)")
            } footer: {
                Text(clipsByName
                     ? "The names you gave your clips. Ones without a name are under No name yet, and their geotags still say where they were filmed."
                     : "Tap a shot to see just its clips. Export copies everything to your SSD, sorted into continent, country and state folders, with cutouts and captions for editing. Keep the app open while it works.")
            }
        }
    }

    // MARK: Sheets and alerts

    private func sheets<Page: View>(_ view: Page) -> some View {
        view
            .sheet(isPresented: $showFacts) {
                TripFactsView(tripID: tripID, day: currentDay)
            }
            .sheet(isPresented: $showCosts) {
                CostsSheet(tripID: tripID, day: currentDay)
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
            .sheet(item: $added) { batch in
                AddedClipsSheet(tripID: tripID, clipIDs: batch.clipIDs, note: batch.note)
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
            .alert("City or town", isPresented: $editingTown) {
                TextField("Like Estes Park", text: $townDraft)
                Button("Save") {
                    store.setTown(townDraft, day: currentDay, tripID: tripID)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Where the trip is, under the state. It goes in the catalogue with every clip.")
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

    /// Adds them, then steps through each one to say what's in it and name it (1.28).
    private func importItems(_ items: [PhotosPickerItem]) {
        pickedItems = []
        exporting = true
        copyProgress = "Adding from Photos…"
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in
            let ids = await MediaImporter.importItems(items, tripID: tripID, day: currentDay, store: store) { copyProgress = $0 }
            endExport()
            let note: String? = ids.count == items.count ? nil : "\(ids.count) of \(items.count) added. The rest couldn't be read."
            if ids.isEmpty {
                importMessage = "None of them could be read. Try again, or add them one at a time."
            } else {
                added = AddedClips(clipIDs: ids, note: note)
            }
        }
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
            let prep = await ClipPrep.prepare(tripID: tripID, store: store) { copyProgress = $0 }
            store.copyTrip(store.trip(id: tripID) ?? trip, to: folder, progress: { done, total in
                copyProgress = "Copying \(done) of \(total) files to \(folder.lastPathComponent)…"
            }, completion: { result in
                endExport()
                switch result {
                case .success(let summary):
                    lastCopy = summary
                    copiedMessage = Self.copiedText(summary) + (prep.note.map { "\n\n" + $0 } ?? "")
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

extension TripPhase {
    var symbol: String {
        switch self {
        case .onTheWay: return "car.fill"
        case .arriving: return "figure.walk"
        case .firstLook: return "eye.fill"
        case .atTheSpot: return "mountain.2.fill"
        case .leaving: return "figure.walk.departure"
        case .bRoll: return "film.stack"
        case .atHome: return "house.fill"
        }
    }
}
