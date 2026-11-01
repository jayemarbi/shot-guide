import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

/// Films one shot. Phone-in-hand shots get live prompts; in-the-shot shots get a timeline,
/// a countdown (with the flash blinking for the last 3 seconds), a clean screen and an instant replay.
struct ShotCameraView: View {
    let tripID: UUID
    let shot: ShotType
    /// The day of the trip the clips are filed under.
    let day: Int
    /// Opened from a transition's Out or In row: stick to that half for every take.
    let fixedVariant: Int?
    /// Quick clip: start recording as soon as the camera is ready.
    let autoStart: Bool

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @StateObject private var level = LevelMeter()
    @StateObject private var song = SongPlayer()
    @EnvironmentObject var songs: SongLibrary
    @AppStorage("showGrid") private var showGrid = true

    @State private var inShot: Bool
    @State private var variant = 0
    @State private var take = 1
    @State private var showBriefing: Bool
    @State private var timing = ShotTiming(countdown: 5, stopsByItself: true, length: 10)
    @State private var showTiming = false
    @State private var pinching = false
    @State private var countdownRemaining: Int? = nil
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var cameraAllowed = false
    @State private var permissionDenied = false
    @State private var focusPoint: CGPoint? = nil
    @State private var reviewClip: Clip? = nil
    @State private var zoomStarted = false
    @State private var message: String? = nil
    @State private var started = false
    @State private var marks: [Double] = []
    @State private var markNote: String? = nil
    @State private var lowLight = false
    @State private var micName = ""
    /// MATCH CUT: a still of the last one, and the zoom it used.
    @State private var ghost: UIImage? = nil
    @State private var ghostZoom: Double? = nil
    @State private var zoomRestored = false
    @State private var autoStarted = false
    @State private var firedCues: Set<Int> = []
    @State private var takeMotion: TakeMotion? = nil
    /// White balance, ISO and shutter as the take started.
    @State private var takeSettings: TakeSettings? = nil
    @State private var startZoom: Double = 1
    @State private var reviewNote: String? = nil
    @State private var thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @State private var battery: Float = -1
    @State private var charging = false
    /// DANCE: where in the song the next take starts, the song's position when the last take started recording,
    /// and where the song plays (AirPods or the phone's speaker).
    @State private var danceStart: DanceStart = .fromTop
    @State private var pickedPoint: Double = 0
    @State private var showSongPicker = false
    @State private var showPointPicker = false
    @State private var songStartAtRecording: Double? = nil
    @State private var routeName = ""

    init(tripID: UUID, shot: ShotType, day: Int, fixedVariant: Int? = nil, autoStart: Bool = false) {
        self.tripID = tripID
        self.shot = shot
        self.day = day
        self.fixedVariant = fixedVariant
        self.autoStart = autoStart
        _inShot = State(initialValue: shot.defaultGroup == .inShot)
        _showBriefing = State(initialValue: shot.defaultGroup == .inShot && !autoStart)
    }

    /// The day's trip type, which tunes the takes, the tips and, for snow, the brightness.
    private var tripType: TripType {
        store.trip(id: tripID)?.day(day).type ?? .general
    }

    /// The version for the next take: the half you picked on the trip page, or the shot's usual pattern.
    private func variantFor(take: Int) -> Int {
        fixedVariant ?? shot.defaultVariant(forTake: take)
    }

    private var plan: ShotPlan {
        var plan = shot.plan(take: take, inShot: inShot, variant: variant)
        // 60 fps lets an edit slow movement down, but it needs light. Once the sun is down, 30 fps looks better.
        if lowLight && plan.fps == 60 {
            plan.fps = 30
        }
        let type = tripType
        plan.exposureBias = plan.exposure == .silhouette ? -1.7 : type.exposureBias
        if let tip = type.tip(for: shot) {
            plan.before = plan.before.isEmpty ? tip + "." : tip + ". " + plan.before
        }
        return plan
    }

    /// Seconds of extra footage after a timeline ends, so the edit has room for transitions and speed ramps.
    static let extraSeconds: Double = 2

    private var hasExtra: Bool {
        timing.stopsByItself && plan.timelapseInterval == nil
    }

    /// When recording stops by itself, extra seconds included.
    private var stopTime: Double {
        timing.length + (hasExtra ? Self.extraSeconds : 0)
    }

    private var isTalkingShot: Bool {
        ClipPrep.talkingShots.contains(shot.rawValue)
    }

    private var isBusy: Bool {
        camera.phase == .recording || camera.phase == .finishing || countdownRemaining != nil
    }

    private var takeLabel: String {
        if shot == .quick {
            return "clip \(take)"
        }
        if shot == .dance {
            return "take \(take)"
        }
        if fixedVariant != nil, let half = plan.variantName {
            return "\(half) half"
        }
        let target = tripType.target(for: shot)
        return take > target ? "extra take \(take)" : "take \(take) of \(target)"
    }

    /// Heat and battery, shown above the camera controls when they could cut a take short.
    private var warningText: String? {
        if thermal == .critical {
            return "The phone is too hot to film well. Let it cool in the shade for a few minutes."
        }
        if thermal == .serious {
            return "The phone is getting hot and recording may stop. Shade it between takes."
        }
        guard battery >= 0, !charging else { return nil }
        let percent = Int((battery * 100).rounded())
        if (shot == .timelapse || shot == .hyperlapse) && battery < 0.25 {
            return "Battery at \(percent)%. A long \(shot.title) needs more, so plug in a power bank."
        }
        if battery < 0.1 {
            return "Battery at \(percent)%. The cold drains it faster, so keep the phone in a warm pocket between shots."
        }
        return nil
    }

    /// Changes to timing are remembered for this shot.
    private var timingBinding: Binding<ShotTiming> {
        Binding(
            get: { timing },
            set: { newValue in
                timing = newValue
                TimingStore.save(newValue, shot: shot, inShot: plan.isInShot)
            })
    }

    /// The timeline fitted to how this take will end, plus the extra seconds as their own step.
    private var displaySteps: [GuideStep] {
        var steps = plan.timeline(endingAt: timing.stopsByItself ? timing.length : nil)
        if hasExtra {
            let text = plan.isInShot
                ? "Hold still for 2 more seconds. It gives the edit room."
                : "Keep the phone steady for 2 more seconds. It gives the edit room."
            steps.append(GuideStep(start: timing.length, end: stopTime, text: text))
        }
        return steps
    }

    private var startHint: String {
        let buttons = plan.lens == .front
            ? "Start with the red button or a volume button."
            : "Start with the red button, a volume button or your Bluetooth remote."
        if timing.countdown == 0 {
            return buttons + " Recording starts straight away."
        }
        if plan.lens == .front {
            return buttons
        }
        return buttons + " The flash blinks for the last 3 seconds before recording starts."
    }

    var body: some View {
        events(screen)
    }

    private var screen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(
                session: camera.session,
                onTap: { viewPoint, devicePoint in
                    showFocus(at: viewPoint)
                    camera.focus(at: devicePoint, lock: false)
                },
                onHold: { viewPoint, devicePoint in
                    showFocus(at: viewPoint)
                    camera.focus(at: devicePoint, lock: true)
                },
                onDrag: { distance in
                    camera.nudgeExposure(by: Float(-distance / 250))
                },
                onButton: { recordTapped() },
                onSecondaryButton: {
                    if camera.phase == .recording {
                        markMoment()
                    } else {
                        recordTapped()
                    }
                },
                onPinch: { scale, state in
                    switch state {
                    case .began:
                        pinching = true
                        camera.pinchZoom(scale: scale, began: true)
                    case .changed:
                        camera.pinchZoom(scale: scale, began: false)
                    default:
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pinching = false }
                    }
                })
                .ignoresSafeArea()
                .overlay {
                    if let focusPoint {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: 76, height: 76)
                            .position(focusPoint)
                            .allowsHitTesting(false)
                    }
                }

            guides
                .ignoresSafeArea()
                .allowsHitTesting(false)

            shotGuideOverlay
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centreOverlay
                Spacer()
                bottomControls
            }

            if showBriefing && plan.isInShot && !isBusy && !permissionDenied {
                briefingCard
            }

            if let countdownRemaining {
                countdownView(countdownRemaining)
            }

            if permissionDenied {
                permissionView
            }
        }
        .statusBarHidden(true)
    }

    private func events<Content: View>(_ content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                micName = MicCheck.currentMicName() ?? ""
                DispatchQueue.main.async { routeName = Self.songRouteName() }
            }
            .onChange(of: songs.selectedFile) { _, _ in
                loadSong()
                danceStart = carryOnPoint == nil ? .fromTop : .carryOn
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                DispatchQueue.main.async { thermal = ProcessInfo.processInfo.thermalState }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
                readBattery()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                readBattery()
            }
            .onChange(of: camera.phase) { oldPhase, phase in
                if oldPhase == .recording {
                    // The take has ended: sum up the shake and tilt before the phone gets lowered.
                    takeMotion = level.endTake()
                    if shot == .dance && songStartAtRecording == nil, let heard = song.heardPosition {
                        // The song hadn't started when recording did: work it out from where it is now.
                        songStartAtRecording = max(0, heard - camera.elapsed)
                    }
                    song.stop()
                }
                if phase == .ready {
                    micName = MicCheck.currentMicName() ?? ""
                    cameraReady()
                }
            }
            .onAppear(perform: start)
            .onDisappear(perform: finish)
            .onChange(of: camera.elapsed) { _, value in
                tick(value)
            }
            .onChange(of: inShot) { _, _ in planChanged() }
            .onChange(of: variant) { _, _ in planChanged() }
            .onChange(of: take) { _, _ in planChanged() }
            .sheet(item: $reviewClip, onDismiss: reviewDismissed) { clip in
                ReviewView(
                    tripID: tripID,
                    clipID: clip.id,
                    autoplay: clip.inShot,
                    preselectSuggestions: true,
                    title: "\(shot.title) · take \(clip.take)",
                    nameNote: reviewNote)
            }
    }

    // MARK: Pieces of the screen

    /// A rule-of-thirds grid and a level line. They're only on the screen, never in the video.
    private var guides: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                if showGrid {
                    Path { path in
                        for third in [CGFloat(1) / 3, CGFloat(2) / 3] {
                            path.move(to: CGPoint(x: width * third, y: 0))
                            path.addLine(to: CGPoint(x: width * third, y: height))
                            path.move(to: CGPoint(x: 0, y: height * third))
                            path.addLine(to: CGPoint(x: width, y: height * third))
                        }
                    }
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                }
                if let tilt = level.tilt, abs(tilt) < 20 {
                    let isLevel = abs(tilt) < 1
                    // The line stays parallel to the real horizon and turns yellow when the phone is level.
                    Capsule()
                        .fill(isLevel ? Color.yellow : Color.white.opacity(0.8))
                        .frame(width: isLevel ? 120 : 96, height: isLevel ? 3 : 2)
                        .rotationEffect(.degrees(-tilt))
                        .position(x: width / 2, y: height / 2)
                }
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .disabled(isBusy)
                .opacity(isBusy ? 0.4 : 1)

                Button {
                    showGrid.toggle()
                } label: {
                    Image(systemName: showGrid ? "grid" : "square")
                        .font(.headline)
                        .padding(12)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .opacity(isBusy ? 0 : 1)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(shot.title) · \(takeLabel)")
                        .font(.headline)
                    Text([camera.lensLabel, camera.formatLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                    if isTalkingShot && !micName.isEmpty {
                        Label("Mic: \(micName)", systemImage: "mic.fill")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    if camera.exposureLocked {
                        Text("FOCUS AND EXPOSURE LOCKED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.yellow)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }

            if !isBusy {
                optionsRow
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var optionsRow: some View {
        VStack(spacing: 8) {
            if shot.canToggleInShot {
                Toggle("I'm in this shot", isOn: $inShot)
                    .tint(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5), in: Capsule())
            }
            if !shot.variants.isEmpty && fixedVariant == nil {
                Picker("Version", selection: $variant) {
                    ForEach(shot.variants.indices, id: \.self) { index in
                        Text(shot.variants[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            if plan.zoomRamp == nil && !camera.availableLenses.isEmpty {
                HStack(spacing: 8) {
                    ForEach(camera.availableLenses, id: \.self) { lens in
                        Button(camera.lensTitles[lens] ?? "") {
                            camera.setLens(lens)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(camera.currentLens == lens ? Color.orange : Color.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(camera.currentLens == lens ? Color.black : Color.white)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var centreOverlay: some View {
        if camera.phase == .recording {
            if plan.timelapseInterval != nil {
                lapseTimer
            } else if !plan.isInShot {
                promptCard
            }
        } else if camera.phase == .finishing {
            ProgressView("Saving…")
                .tint(.white)
                .foregroundStyle(Color.white)
                .padding()
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        } else if case .failed(let text) = camera.phase {
            notice(text)
        } else if let message {
            notice(message)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white)
            .padding(16)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var promptCard: some View {
        let steps = displaySteps
        let now = camera.elapsed
        if let index = steps.lastIndex(where: { now >= $0.start }) {
            let step = steps[index]
            let next: GuideStep? = index + 1 < steps.count ? steps[index + 1] : nil
            VStack(spacing: 10) {
                Text(step.text)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                if let end = step.end {
                    Text("\(Int(max(0, end - now).rounded(.up)))")
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    ProgressView(value: min(1, max(0, (now - step.start) / max(end - step.start, 0.1))))
                        .tint(.orange)
                        .frame(maxWidth: 220)
                }
                if let next {
                    Text("Next: \(next.text)")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .foregroundStyle(Color.white)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20)
        }
    }

    private var lapseTimer: some View {
        let interval = plan.timelapseInterval ?? 1
        let videoSeconds = camera.elapsed / interval / 30
        return VStack(spacing: 8) {
            Text(clockString(camera.elapsed))
                .font(.system(size: 64, weight: .bold).monospacedDigit())
            Text(String(format: "%.0f s of video so far", videoSeconds))
                .font(.headline)
            Text(camera.elapsed >= 600 ? "That's 10 minutes. Stop whenever you like." : "Aim for 10 minutes or more.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .foregroundStyle(Color.white)
        .padding(24)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if shot == .dance && !isBusy {
                songPanel
            }
            if let warningText, !isBusy || thermal == .critical {
                Label(warningText, systemImage: thermal == .nominal || thermal == .fair ? "battery.25" : "thermometer.sun.fill")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.orange)
            }
            if let markNote {
                Label(markNote, systemImage: "star.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(Color.yellow)
            }
            if pinching && !camera.lensLabel.isEmpty {
                Text(camera.lensLabel)
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6), in: Capsule())
            }
            if !isBusy && !plan.isInShot && !plan.before.isEmpty {
                Text(plan.before)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            if camera.phase == .recording && plan.isInShot && plan.timelapseInterval == nil {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text(timing.stopsByItself
                         ? "\(clockString(camera.elapsed)) / \(clockString(stopTime))"
                         : clockString(camera.elapsed))
                        .font(.headline.monospacedDigit())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5), in: Capsule())
            }
            HStack {
                Group {
                    if plan.isInShot && !isBusy {
                        Button {
                            showBriefing = true
                        } label: {
                            Label("Timeline", systemImage: "list.bullet")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.5), in: Capsule())
                        }
                    } else if camera.phase == .recording && plan.timelapseInterval == nil {
                        // Tap when something great happens, so the edit can cut straight to it.
                        Button(action: markMoment) {
                            Label("Mark", systemImage: "star.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.yellow.opacity(0.85), in: Capsule())
                                .foregroundStyle(Color.black)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 120, height: 44)

                Spacer()
                recordButton
                Spacer()

                Group {
                    if !isBusy {
                        Button {
                            showTiming = true
                        } label: {
                            let summary = TimingControls.summary(timing, extraSeconds: hasExtra ? Self.extraSeconds : 0)
                            VStack(alignment: .leading, spacing: 2) {
                                Label(summary.countdown, systemImage: "timer")
                                Text(summary.ending)
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 120, height: 44)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal)
        .padding(.bottom, 24)
        .sheet(isPresented: $showTiming) {
            NavigationStack {
                Form {
                    TimingControls(timing: timingBinding)
                }
                .navigationTitle("\(shot.title) timing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showTiming = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var recordButton: some View {
        let canPress = camera.phase == .ready || camera.phase == .recording
        return Button(action: recordTapped) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                if camera.phase == .recording || countdownRemaining != nil {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .disabled(!canPress)
        .opacity(canPress ? 1 : 0.4)
    }

    private var briefingCard: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Text("\(shot.title) · \(takeLabel)")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .padding(10)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                    }
                    if !shot.variants.isEmpty && fixedVariant == nil {
                        Picker("Version", selection: $variant) {
                            ForEach(shot.variants.indices, id: \.self) { index in
                                Text(shot.variants[index]).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(plan.before)
                        .foregroundStyle(Color.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(displaySteps, id: \.self) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(step.rangeLabel)
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Color.orange)
                                    .frame(width: 84, alignment: .leading)
                                Text(step.text)
                            }
                        }
                    }
                    if shot.canToggleInShot {
                        Toggle("I'm in this shot", isOn: $inShot)
                            .tint(.orange)
                    }
                    TimingControls(timing: timingBinding)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Text(startHint)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Button {
                        showBriefing = false
                    } label: {
                        Text("Set up the shot")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .foregroundStyle(Color.white)
                .padding(20)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 20))
                .padding(20)
                .padding(.top, 60)
            }
        }
    }

    private func countdownView(_ remaining: Int) -> some View {
        VStack(spacing: 8) {
            Text("\(remaining)")
                .font(.system(size: 120, weight: .heavy).monospacedDigit())
            Text("Get into position")
                .font(.headline)
            Text("Press the button or the remote to cancel")
                .font(.footnote)
                .opacity(0.8)
        }
        .foregroundStyle(Color.white)
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }

    private var permissionView: some View {
        VStack(spacing: 14) {
            Text("Camera access is off")
                .font(.title3.weight(.bold))
            Text("Turn on Camera and Microphone for Shot Guide in Settings.")
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Close") { dismiss() }
        }
        .foregroundStyle(Color.white)
        .padding(24)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    // MARK: What happens when

    private func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        location.start()
        if let coordinate = location.location?.coordinate {
            lowLight = SunCalc.elevation(at: Date(), latitude: coordinate.latitude, longitude: coordinate.longitude).degrees < 0
        }
        take = store.nextTake(tripID: tripID, shot: shot, day: day)
        variant = variantFor(take: take)
        timing = TimingStore.load(shot, plan: plan)
        showBriefing = plan.isInShot && !autoStart
        level.start()
        UIDevice.current.isBatteryMonitoringEnabled = true
        readBattery()
        if shot == .matchCut {
            loadGhost()
        }
        if shot == .dance {
            loadSong()
            danceStart = carryOnPoint == nil ? .fromTop : .carryOn
            routeName = Self.songRouteName()
        }
        if let minutes = store.minutesOfVideoLeft, minutes < 10 {
            message = "Only about \(minutes) minutes of 4K space left. Copy a trip to your SSD soon."
        }
        CameraController.requestAccess { allowed in
            if allowed {
                cameraAllowed = true
                camera.configure(plan.captureConfig)
            } else {
                permissionDenied = true
            }
        }
    }

    private func finish() {
        cancelCountdown()
        if camera.phase == .recording {
            camera.stopRecording()
        }
        camera.stop()
        level.stop()
        UIDevice.current.isBatteryMonitoringEnabled = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func readBattery() {
        let device = UIDevice.current
        battery = device.batteryLevel
        charging = device.batteryState == .charging || device.batteryState == .full
    }

    /// Each time the camera is ready: put MATCH CUT's zoom back, and start a quick clip straight away.
    private func cameraReady() {
        if let ghostZoom, !zoomRestored {
            zoomRestored = true
            camera.setZoom(display: ghostZoom)
        }
        if autoStart && !autoStarted && reviewClip == nil && !permissionDenied {
            autoStarted = true
            beginRecording()
        }
    }

    /// MATCH CUT: the most recent one on the phone, from any trip, as a see-through still and its zoom.
    private func loadGhost() {
        var newest: (clip: Clip, trip: Trip)? = nil
        for trip in store.trips {
            for clip in trip.clips where clip.shot == ShotType.matchCut.rawValue && clip.isOnPhone {
                if let current = newest, current.clip.recordedAt >= clip.recordedAt {
                    continue
                }
                newest = (clip, trip)
            }
        }
        guard let latest = newest else { return }
        ghostZoom = latest.clip.zoom
        let url = store.clipURL(latest.clip, in: latest.trip)
        Task { @MainActor in
            ghost = await Self.still(of: url, at: 3)
        }
    }

    private static func still(of url: URL, at seconds: Double) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        guard let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { return nil }
        return UIImage(cgImage: result.image)
    }

    // MARK: Guides drawn over the picture for some creative shots

    @ViewBuilder
    private var shotGuideOverlay: some View {
        switch plan.overlay {
        case .ghost?:
            ghostOverlay
        case .sizeBox?:
            sizeBox
        case .crosshair?:
            crosshair
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var ghostOverlay: some View {
        if let ghost, camera.phase != .recording {
            Image(uiImage: ghost)
                .resizable()
                .scaledToFill()
                .opacity(0.35)
                .ignoresSafeArea()
        }
    }

    private var sizeBox: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .frame(width: 230, height: 280)
            .overlay(alignment: .top) {
                Text("Head and shoulders")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(Color.yellow)
                    .offset(y: -26)
            }
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: 46, height: 46)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 2, height: 76)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 76, height: 2)
        }
    }

    private func planChanged() {
        timing = TimingStore.load(shot, plan: plan)
        showBriefing = plan.isInShot
        if cameraAllowed {
            camera.configure(plan.captureConfig)
        }
    }

    private func showFocus(at point: CGPoint) {
        focusPoint = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if focusPoint == point {
                focusPoint = nil
            }
        }
    }

    private func recordTapped() {
        if countdownRemaining != nil {
            cancelCountdown()
            return
        }
        switch camera.phase {
        case .recording:
            camera.stopRecording()
        case .ready:
            guard reviewClip == nil, !permissionDenied else { return }
            if shot == .dance && song.loadedURL == nil {
                message = "Pick a song first."
                showSongPicker = true
                return
            }
            message = nil
            showBriefing = false
            if timing.countdown > 0 {
                startCountdown()
            } else {
                startSong(lead: 0)
                beginRecording()
            }
        default:
            break
        }
    }

    private func startCountdown() {
        showBriefing = false
        let total = max(timing.countdown, 1)
        startSong(lead: Double(total))
        // The flash tells you when recording starts if you're in front of the phone.
        let useFlash = plan.isInShot && plan.lens != .front && camera.hasTorch
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for remaining in stride(from: total, through: 1, by: -1) {
                countdownRemaining = remaining
                if useFlash && remaining <= 3 {
                    camera.setTorch(true)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    camera.setTorch(false)
                    try? await Task.sleep(nanoseconds: 800_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if Task.isCancelled {
                    camera.setTorch(false)
                    return
                }
            }
            countdownRemaining = nil
            countdownTask = nil
            beginRecording()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
        camera.setTorch(false)
        song.stop()
    }

    private func beginRecording() {
        let now = Date()
        guard let url = store.newClipURL(tripID: tripID, shotName: shot.rawValue, take: take, date: now, day: day,
                                         fileExtension: "mov") else {
            message = "Couldn't find this trip's folder."
            return
        }
        let used = plan
        let coordinate = location.location?.coordinate
        zoomStarted = false
        marks = []
        firedCues = []
        takeMotion = nil
        startZoom = camera.displayZoom
        if used.exposure == .lockAtStart {
            camera.lockFocusAndExposure()
        }
        level.beginTake()
        // Lock the white balance for the take; a take just before at the same spot on the same lens shares it,
        // so they match in the edit.
        takeSettings = nil
        let reuse = Self.sameSpotWhiteBalance(in: store.trip(id: tripID), latitude: coordinate?.latitude,
                                              longitude: coordinate?.longitude, at: now, lens: used.lens)
        camera.beginTake(reuse: reuse, lens: used.lens) { settings in
            takeSettings = settings
        }
        songStartAtRecording = nil
        if shot == .dance {
            camera.onRecordingStarted = {
                songStartAtRecording = song.heardPosition
            }
        }
        camera.startRecording(to: url, latitude: coordinate?.latitude, longitude: coordinate?.longitude) { result in
            saveTake(result, plan: used, startedAt: now, latitude: coordinate?.latitude, longitude: coordinate?.longitude)
        }
    }

    private func markMoment() {
        guard camera.phase == .recording else { return }
        let time = camera.elapsed
        marks.append(time)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        markNote = "Marked at \(clockString(time))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if markNote == "Marked at \(clockString(time))" {
                markNote = nil
            }
        }
    }

    private func tick(_ value: Double) {
        guard camera.phase == .recording else { return }
        if let ramp = plan.zoomRamp, !zoomStarted, value >= ramp.startAt {
            zoomStarted = true
            camera.rampZoom(fromDisplay: ramp.from, toDisplay: ramp.to, duration: ramp.duration)
        }
        // CLONE: the flash blinks when it's time to move to the next spot.
        for (index, cue) in plan.flashCues.enumerated() where value >= cue && !firedCues.contains(index) {
            firedCues.insert(index)
            camera.blinkTorch()
        }
        if timing.stopsByItself, value >= stopTime {
            camera.stopRecording()
        }
        if shot == .dance && song.finished && value > 1 {
            camera.stopRecording()
        }
    }

    private func saveTake(_ result: RecordingResult?, plan used: ShotPlan, startedAt: Date, latitude: Double?, longitude: Double?) {
        // Put the zoom back where this shot starts, ready for the next take. MATCH CUT keeps the zoom it was
        // filmed at, so the next one lines up.
        if shot == .matchCut {
            camera.setZoom(display: startZoom)
        } else {
            camera.setLens(used.lens)
        }
        if used.exposure == .lockAtStart {
            camera.resetFocusAndExposure()
        }
        camera.endTake()
        let settings = takeSettings
        takeSettings = nil
        let motion = takeMotion ?? level.endTake()
        takeMotion = nil
        guard let result else {
            message = "That take didn't save. Try again."
            return
        }
        let takeMarks = marks
        let zoomAtStart = startZoom
        let songInfo: (name: String, url: URL)? = shot == .dance ? songs.selected.map { ($0.name, songs.url(for: $0)) } : nil
        let songStart = songStartAtRecording
        let check = Self.checkResult(motion, kind: shot.takeCheck(variantName: used.variantName), onTripod: used.isInShot)
        let prefill = Self.nearbyName(in: store.trip(id: tripID), latitude: latitude, longitude: longitude, at: startedAt)
        Task { @MainActor in
            let duration = await Self.duration(of: result.url) ?? result.elapsed
            let light = SunCalc.light(at: startedAt, latitude: latitude, longitude: longitude)
            let lens: String
            if let ramp = used.zoomRamp {
                lens = CameraController.formatZoom(ramp.from) + " to " + CameraController.formatZoom(ramp.to)
            } else {
                lens = result.lensLabel
            }
            var tags = light.tags
            if used.isInShot && shot != .timelapse {
                tags.append("me")
            }
            let clip = Clip(
                fileName: result.url.lastPathComponent,
                shot: shot.rawValue,
                take: used.take,
                variant: used.variantName,
                recordedAt: startedAt,
                timeZoneID: TimeZone.current.identifier,
                durationSeconds: duration,
                latitude: latitude,
                longitude: longitude,
                light: light.label,
                lens: lens,
                fps: result.fps,
                resolution: result.resolution,
                inShot: used.isInShot,
                tags: tags,
                favourite: false,
                notes: "",
                marks: takeMarks.isEmpty ? nil : takeMarks,
                name: prefill,
                day: day,
                shake: motion?.shake,
                tilt: motion?.tilt,
                check: check?.text,
                checkPassed: check?.passed,
                zoom: zoomAtStart,
                songName: songInfo?.name,
                songFile: songInfo.flatMap { store.attachSong($0.url, name: $0.name, tripID: tripID) },
                songStart: songStart,
                colourProfile: result.log ? Clip.appleLog : Clip.normalColour,
                whiteBalance: settings?.whiteBalance,
                iso: settings?.iso,
                shutter: settings?.shutter)
            store.addClip(clip, to: tripID)
            if prefill != nil {
                // Named after the spot you're still at, so the file gets the name straight away.
                store.applyFileName(clipID: clip.id, tripID: tripID)
            }
            reviewNote = prefill == nil ? nil : "Same as your last clip here"
            if shot == .matchCut, let saved = store.trip(id: tripID)?.clips.first(where: { $0.id == clip.id }),
               let trip = store.trip(id: tripID) {
                ghostZoom = zoomAtStart
                ghost = await Self.still(of: store.clipURL(saved, in: trip), at: 3)
            }
            reviewClip = store.trip(id: tripID)?.clips.first(where: { $0.id == clip.id }) ?? clip
        }
    }

    /// The take check: steady and level, or what went wrong. Small tilts pass, as the edit can straighten them.
    static func checkResult(_ motion: TakeMotion?, kind: TakeCheckKind, onTripod: Bool) -> (text: String, passed: Bool)? {
        guard kind != .none, let motion else { return nil }
        var problems: [String] = []
        var passed = true
        if motion.shake > (onTripod ? 3.0 : 6.0) {
            problems.append(onTripod ? "the tripod moved or shook" : "shaky")
            passed = false
        } else if motion.shake > (onTripod ? 1.2 : 3.0) {
            problems.append(onTripod ? "the tripod wobbled a little" : "a bit shaky")
            passed = false
        }
        var tiltNote: String? = nil
        if kind == .steadyAndLevel, let tilt = motion.tilt, abs(tilt) >= 2 {
            let degrees = Int(abs(tilt).rounded())
            if abs(tilt) >= 5 {
                problems.append("tilted \(degrees)°")
                passed = false
            } else {
                tiltNote = "Tilted \(degrees)°, which the edit can straighten."
            }
        }
        if problems.isEmpty {
            let base = kind == .steadyAndLevel && tiltNote == nil ? "Steady and level" : "Steady"
            return (tiltNote.map { base + ". " + $0 } ?? base, true)
        }
        let joined = problems.joined(separator: " and ")
        let first: String = joined.prefix(1).uppercased()
        let rest = String(joined.dropFirst())
        return (first + rest + ". Another take?", passed)
    }

    /// The white balance of a take filmed in the last 15 minutes on the same lens, if you're still within
    /// 300 m of it (or, without a location, just by time).
    static func sameSpotWhiteBalance(in trip: Trip?, latitude: Double?, longitude: Double?, at date: Date,
                                     lens: LensChoice) -> WhiteBalance? {
        guard let trip else { return nil }
        let recent = trip.clips.filter {
            $0.whiteBalance?.lens == lens.rawValue && $0.recordedAt <= date && date.timeIntervalSince($0.recordedAt) < 15 * 60
        }
        guard let last = recent.max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
        if let latitude, let longitude, let lastLatitude = last.latitude, let lastLongitude = last.longitude {
            let here = CLLocation(latitude: latitude, longitude: longitude)
            let there = CLLocation(latitude: lastLatitude, longitude: lastLongitude)
            return here.distance(from: there) <= 300 ? last.whiteBalance : nil
        }
        return last.whiteBalance
    }

    /// The name of the last named clip, if you're still near it: within 300 m, or within 20 minutes
    /// when there's no location. Walk on to somewhere new and the name box starts empty.
    static func nearbyName(in trip: Trip?, latitude: Double?, longitude: Double?, at date: Date) -> String? {
        guard let trip else { return nil }
        let named = trip.clips.filter { $0.displayName != nil }
        guard let last = named.max(by: { $0.recordedAt < $1.recordedAt }), let name = last.displayName else { return nil }
        if let latitude, let longitude, let lastLatitude = last.latitude, let lastLongitude = last.longitude {
            let here = CLLocation(latitude: latitude, longitude: longitude)
            let there = CLLocation(latitude: lastLatitude, longitude: lastLongitude)
            return here.distance(from: there) <= 300 ? name : nil
        }
        return date.timeIntervalSince(last.recordedAt) < 20 * 60 ? name : nil
    }

    private func reviewDismissed() {
        take = store.nextTake(tripID: tripID, shot: shot, day: day)
        variant = variantFor(take: take)
        reviewNote = nil
        if shot == .dance {
            danceStart = carryOnPoint == nil ? .fromTop : .carryOn
        }
        guard let trip = store.trip(id: tripID), shot != .quick, shot != .dance else { return }
        if let fixedVariant {
            // One half of a transition: done once that half has a take.
            let half = ShotSlot(shot: shot, half: fixedVariant)
            if half.takeCount(in: trip, day: day) >= 1, let name = half.variantName {
                message = "\(name) half done. Film another, or tap ✕ to pick the next shot."
            }
            return
        }
        let target = tripType.target(for: shot)
        if trip.takeCount(of: shot, day: day) >= target {
            let noun = target == 1 ? "take" : "takes"
            message = "All \(target) \(noun) done. Film an extra, or tap ✕ to pick the next shot."
        }
    }

    private static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

/// DANCE: where in the song a take starts.
enum DanceStart: Hashable {
    /// 10 seconds before where the last take with this song ended, so swaps between spots overlap.
    case carryOn
    case fromTop
    case picked
}

// MARK: DANCE

extension ShotCameraView {
    /// 10 seconds before where the last DANCE take with this song on this trip ended.
    var carryOnPoint: Double? {
        guard let name = songs.selected?.name, let trip = store.trip(id: tripID) else { return nil }
        let takes = trip.clips.filter { $0.shot == ShotType.dance.rawValue && $0.songName == name && $0.songStart != nil }
        guard let last = takes.max(by: { $0.recordedAt < $1.recordedAt }), let start = last.songStart else { return nil }
        return max(0, start + last.durationSeconds - 10)
    }

    var danceStartPoint: Double {
        switch danceStart {
        case .carryOn: return carryOnPoint ?? 0
        case .fromTop: return 0
        case .picked: return pickedPoint
        }
    }

    func loadSong() {
        guard let selected = songs.selected else {
            song.stop()
            return
        }
        if !song.load(songs.url(for: selected)) {
            message = "That song couldn't be played. Pick another."
        }
    }

    /// Starts the song so the chosen point lands as recording starts: `lead` seconds early, or later from the very
    /// start of the song when the point is closer to the start than that.
    func startSong(lead: Double) {
        guard shot == .dance, song.loadedURL != nil else { return }
        let point = danceStartPoint
        let early = min(lead, point)
        song.play(from: point - early, after: lead - early)
    }

    /// The headphones the song plays in, like "Jody's AirPods Pro", or "" for the phone's speaker.
    static func songRouteName() -> String {
        let headphones: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .airPlay]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.first { headphones.contains($0.portType) }?.portName ?? ""
    }

    var songPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            songTitleButton
            if songs.selected != nil {
                startPicker
                if danceStart == .picked {
                    Button("Starting at \(clockString(pickedPoint)) · Change") {
                        showPointPicker = true
                    }
                    .font(.caption.weight(.semibold))
                }
                Text(routeLine)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showSongPicker) {
            SongPickerSheet()
                .environmentObject(songs)
        }
        .sheet(isPresented: $showPointPicker) {
            pointSheet
        }
        .onChange(of: danceStart) { _, start in
            if start == .picked {
                showPointPicker = true
            }
        }
    }

    private var routeLine: String {
        routeName.isEmpty
            ? "Plays on the phone's speaker. Connect your AirPods to hear it better."
            : "Plays in \(routeName)"
    }

    private var songTitleButton: some View {
        Button {
            showSongPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundStyle(Color.orange)
                Text(songs.selected?.name ?? "Pick a song")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(songs.selected == nil ? "" : "Change")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }

    private var startPicker: some View {
        Picker("Start", selection: $danceStart) {
            if let carry = carryOnPoint {
                Text("Carry on \(clockString(carry))").tag(DanceStart.carryOn)
            }
            Text("From the top").tag(DanceStart.fromTop)
            Text("Pick a point").tag(DanceStart.picked)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var pointSheet: some View {
        if let selected = songs.selected {
            SongPointSheet(songURL: songs.url(for: selected), point: $pickedPoint)
        }
    }
}
