import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

/// Films one shot. Phone-in-hand shots get live prompts; in-the-shot shots get a timeline,
/// a countdown (with the flash blinking for the last 5 seconds), a clean screen and an instant replay. On the tripod,
/// 5 flashes lead into each new step while it records, and a fast flicker means walk back (1.24).
struct ShotCameraView: View {
    let tripID: UUID
    let shot: ShotType
    /// The day of the trip the clips are filed under.
    let day: Int
    /// Opened from a transition's Out or In row: stick to that half for every take.
    let fixedVariant: Int?
    /// The creative role tapped on the trip page, if one was.
    let initialRole: String?

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
    /// The creative role being filmed, for shots with roles (REVEAL's is its version).
    @State private var roleID: String? = nil
    /// The take just saved, to see what it did for coverage once its review closes.
    @State private var lastClipID: UUID? = nil
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
    /// Golden or blue hour when the white balance was last set between takes.
    @State private var lockedGlow: SunCalc.Glow? = nil
    @State private var micName = ""
    /// The flashes and voice while you're in the shot, ONE TAKE's parts and MATCH CUT finding your size (1.24).
    @StateObject private var director = TakeDirector()
    /// ONE TAKE: the parts, their lengths and MATCH CUT's move, remembered between takes.
    @State private var oneTakeSetup = OneTakeSetup.load()
    /// Bumped when MATCH CUT's size for a move is cleared, to redraw.
    @State private var sizeVersion = 0
    @State private var takeMotion: TakeMotion? = nil
    /// White balance, ISO and shutter as the take started.
    @State private var takeSettings: TakeSettings? = nil
    @State private var startZoom: Double = 1
    @State private var reviewNote: String? = nil
    /// DANCE: where in the song the next take starts, the song's position when the last take started recording,
    /// and where the song plays (AirPods or the phone's speaker).
    @State private var danceStart: DanceStart = .fromTop
    @State private var pickedPoint: Double = 0
    @State private var showSongPicker = false
    @State private var showPointPicker = false
    @State private var songStartAtRecording: Double? = nil
    @State private var routeName = ""

    /// Ticks every 30 seconds, to notice golden and blue hour starting and ending while the camera is open.
    private let lightClock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(tripID: UUID, shot: ShotType, day: Int, fixedVariant: Int? = nil, role: String? = nil) {
        self.tripID = tripID
        self.shot = shot
        self.day = day
        self.fixedVariant = fixedVariant
        self.initialRole = role
        let tapped = role.flatMap { shot.role(withID: $0) }
        _inShot = State(initialValue: tapped?.inShot ?? (shot.defaultGroup == .inShot))
        _showBriefing = State(initialValue: shot.defaultGroup == .inShot || !HowItWorks.seen(shot, role: role))
    }

    /// The day's trip type, which tunes the takes, the tips and, for snow, the brightness.
    private var tripType: TripType {
        store.trip(id: tripID)?.day(day).type ?? .general
    }

    /// The version for the next take: the half you picked on the trip page, or the shot's usual pattern.
    private func variantFor(take: Int) -> Int {
        if shot == .matchCut && fixedVariant == nil {
            // The move you did last, so you keep repeating it from place to place (1.24).
            return MatchCutStore.lastMove.rawValue
        }
        return fixedVariant ?? shot.defaultVariant(forTake: take)
    }

    /// MATCH CUT's move for this take.
    private var currentMove: MatchMove {
        MatchMove(rawValue: variant) ?? .runAcross
    }

    private var plan: ShotPlan {
        var plan = shot.plan(take: take, inShot: inShot, variant: variant, role: roleID)
        // 60 fps lets an edit slow movement down, but it needs light. Once the sun is down, 30 fps looks better.
        if lowLight && plan.fps == 60 {
            plan.fps = 30
        }
        if shot == .oneTake {
            // Your parts and lengths (1.24).
            plan.steps = oneTakeSetup.steps()
            plan.manualLength = oneTakeSetup.total
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
        camera.phase == .recording || camera.phase == .finishing || countdownRemaining != nil || director.isFinding
    }

    private var takeLabel: String {
        if shot == .dance || shot == .oneTake {
            return "take \(take)"
        }
        if shot == .matchCut {
            return "\(currentMove.title) · take \(take)"
        }
        if fixedVariant != nil, let half = plan.variantName {
            return shot.isTransition ? "\(half) half" : half.lowercased()
        }
        if let role = currentRole {
            return "\(role.title) · take \(take)"
        }
        let target = tripType.target(for: shot)
        return take > target ? "extra take \(take)" : "take \(take) of \(target)"
    }

    /// The creative role being filmed: picked with the role buttons, or REVEAL's version.
    private var currentRole: CoverageRole? {
        fixedVariant == nil ? plan.role : nil
    }

    /// This shot's progress, for shots with roles: today's, or the place's once the day has been at more than one.
    private var shotCoverage: SlotCoverage? {
        guard !shot.roles.isEmpty, fixedVariant == nil, let trip = store.trip(id: tripID) else { return nil }
        return roleCoverage(in: trip)
    }

    /// The place you're filming at, on a day that's been at more than one (1.21). nil on a day at one place.
    private func placeNow(in trip: Trip) -> PlaceNow? {
        let coordinate = location.location?.coordinate
        let startsNew = trip.nextClipStartsScene(day: day, latitude: coordinate?.latitude,
                                                 longitude: coordinate?.longitude, at: Date())
        return trip.placeNow(day: day, startsNew: startsNew)
    }

    /// The roles covered at the place you're at, for the shots tracked at each place, or today otherwise and when
    /// the day has been at one place. A second waterfall gets its own set while the day's counts carry on.
    private func roleCoverage(in trip: Trip) -> SlotCoverage {
        coverageHere(of: shot, in: trip)
    }

    /// Any shot's roles where you are: at the place for the shots tracked at each place, or today. ONE TAKE fills its
    /// parts' roles from these (1.24).
    private func coverageHere(of shot: ShotType, in trip: Trip) -> SlotCoverage {
        let slot = ShotSlot(shot: shot, half: nil)
        if shot.perPlace, let place = placeNow(in: trip) {
            return trip.coverage(for: slot, day: day, at: place)
        }
        return trip.coverage(for: slot, day: day)
    }

    /// How to hold the phone for this take: the shot's way, unless the role changes it (WIDE's vertical hero).
    private var filming: Filming {
        plan.filming ?? shot.filming
    }

    /// Switches to a role: REVEAL's version, or the role's own plan. Roles you're in, or not, by their nature set
    /// "I'm in this shot" to match.
    private func selectRole(_ id: String) {
        guard let role = shot.role(withID: id) else { return }
        if shot.rolesAreVariants {
            if let index = shot.roles.firstIndex(where: { $0.id == id }) {
                variant = index
            }
        } else {
            roleID = id
        }
        if let fixed = role.inShot {
            inShot = fixed
        }
    }

    /// The role to start on: the one tapped on the trip page, or the next one the day still needs.
    private func chooseStartingRole() {
        guard !shot.roles.isEmpty, fixedVariant == nil else { return }
        if let initialRole, shot.role(withID: initialRole) != nil {
            selectRole(initialRole)
        } else if let next = shot.nextRole(after: nil, open: shotCoverage?.openRoleIDs ?? []) {
            selectRole(next.id)
        }
    }

    /// The role buttons, with a tick on the ones today (or this place, on a day at more than one) already has.
    /// Swap-ins come after the usual roles.
    private var rolePicker: some View {
        let lines = shotCoverage?.roles ?? []
        let current = currentRole?.id
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lines) { line in
                    Button {
                        selectRole(line.role.id)
                    } label: {
                        HStack(spacing: 4) {
                            if line.covered {
                                Image(systemName: "checkmark")
                            } else if line.role.isSubstitute {
                                Image(systemName: "arrow.triangle.swap")
                            } else if line.role.isOptional {
                                Image(systemName: "plus")
                            }
                            Text(line.role.title)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(line.role.id == current ? Color.orange : Color.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(line.role.id == current ? Color.black : Color.white)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: MATCH CUT and ONE TAKE (1.24)

    /// MATCH CUT's moves, with the one you're on highlighted.
    private func movePicker(_ moves: [MatchMove]) -> some View {
        moveChips(moves, selected: currentMove) { move in
            variant = move.rawValue
        }
    }

    /// One chip per move, each with how many places you've filmed it at across every trip, so you can see your set
    /// growing.
    private func moveChips(_ moves: [MatchMove], selected: MatchMove, choose: @escaping (MatchMove) -> Void) -> some View {
        let trips = store.trips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moves) { move in
                    let places = move.places(in: trips)
                    let isOn = move == selected
                    let spoken: String = places == 0 ? move.title
                        : "\(move.title), filmed at \(places) \(places == 1 ? "place" : "places")"
                    Button {
                        choose(move)
                    } label: {
                        HStack(spacing: 5) {
                            Text(move.title)
                            if places > 0 {
                                Text("\(places)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background((isOn ? Color.black : Color.white).opacity(0.18), in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.orange : Color.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(isOn ? Color.black : Color.white)
                    }
                    .accessibilityLabel(spoken)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// MATCH CUT: the size it zooms you to for this move, set by your first take of it, and starting it again.
    @ViewBuilder
    private var matchCutSizeRow: some View {
        let _ = sizeVersion
        let move = currentMove
        if let size = MatchCutStore.size(for: move) {
            VStack(alignment: .leading, spacing: 6) {
                Label("It zooms until you're the size you were in your first \(move.title): "
                      + "\(Int((size * 100).rounded()))% of the frame's height.", systemImage: "person.crop.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                Button("New size: let this take set it") {
                    MatchCutStore.setSize(nil, for: move)
                    sizeVersion += 1
                }
                .font(.subheadline.weight(.semibold))
                .tint(.orange)
            }
        } else {
            Label("Your first \(move.title) sets your size. Every take after it zooms until you're that size again.",
                  systemImage: "person.crop.rectangle")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    /// What each part you're filming counts as where you are.
    private var oneTakeFills: [OneTakeFill] {
        guard let trip = store.trip(id: tripID) else { return [] }
        return trip.oneTakePlan(oneTakeSetup.parts, day: day, at: placeNow(in: trip))
    }

    /// ONE TAKE's parts: tap the circle to leave one out or put it back, the time to change how long it runs, and
    /// MATCH CUT's move. Remembered for next time.
    private var oneTakePartsEditor: some View {
        let fills = oneTakeFills
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(OneTakePart.allCases) { part in
                oneTakePartRow(part, fill: fills.first { $0.part == part })
            }
            Text(oneTakeTotalLine)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    private func oneTakePartRow(_ part: OneTakePart, fill: OneTakeFill?) -> some View {
        let included = oneTakeSetup.includes(part)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    oneTakeSetup.toggle(part)
                    oneTakeSetup.save()
                } label: {
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(included ? Color.orange : Color.white.opacity(0.5))
                }
                .accessibilityLabel(included ? "Leave out \(part.title)" : "Put back \(part.title)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(part == .matchCut ? "MATCH CUT · \(oneTakeSetup.matchMove.title)" : part.title)
                        .font(.headline)
                    Text(oneTakeFillLine(fill, included: included))
                        .font(.caption)
                        .foregroundStyle(included && fill?.adds == true ? Color.green : Color.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                if included {
                    Menu {
                        ForEach(OneTakePart.lengthChoices, id: \.self) { seconds in
                            Button(clockString(seconds)) {
                                oneTakeSetup.lengths[part.rawValue] = seconds
                                oneTakeSetup.save()
                            }
                        }
                    } label: {
                        Text(clockString(oneTakeSetup.length(of: part)))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("\(part.title) runs \(clockString(oneTakeSetup.length(of: part)))")
                }
            }
            if included {
                Text(part.doing(move: oneTakeSetup.matchMove))
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.75))
                if part == .matchCut {
                    moveChips(MatchMove.allCases.filter { $0.fitsOneTake }, selected: oneTakeSetup.matchMove) { move in
                        oneTakeSetup.move = move.rawValue
                        oneTakeSetup.save()
                    }
                }
            }
        }
        .opacity(included ? 1 : 0.6)
    }

    /// "Counts as WIDE · Establishing", or what it'll be if that's filmed here already.
    private func oneTakeFillLine(_ fill: OneTakeFill?, included: Bool) -> String {
        guard included else { return "Left out this time" }
        guard let fill else { return "" }
        return fill.adds ? "Counts as \(fill.title)" : "\(fill.title), an extra here"
    }

    /// "About 6:00 before you walk back, roughly 2.7 GB."
    private var oneTakeTotalLine: String {
        let total = oneTakeSetup.total
        // Roughly how much a minute of 4K takes on the phone.
        let perMinute = plan.fps >= 60 ? 0.45 : 0.2
        let gigabytes = total / 60 * perMinute
        var line = "About \(clockString(total)) before you walk back, roughly \(String(format: "%.1f", gigabytes)) GB. "
            + "It keeps rolling after that until you stop it."
        if let minutes = store.minutesOfVideoLeft, Double(minutes) * 0.2 < gigabytes {
            line += " That's more than the space left on the phone, so copy a trip to your SSD first."
        }
        return line
    }

    /// Changes to timing are remembered for this shot.
    private var timingBinding: Binding<ShotTiming> {
        Binding(
            get: { timing },
            set: { newValue in
                timing = newValue
                TimingStore.save(newValue, shot: shot, plan: plan)
            })
    }

    /// The timeline fitted to how this take will end, plus the extra seconds as their own step.
    private var displaySteps: [GuideStep] {
        if shot == .oneTake {
            // As it goes: where each part really started, as your remote can move you on early (1.24).
            return (camera.phase == .recording ? director.liveSteps(now: camera.elapsed) : nil) ?? plan.steps
        }
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
        if shot == .matchCut {
            return buttons + " The light stays on while it finds you and goes off once you're framed. Then 5 flashes, and "
                + "it's rolling. If it can't find you, your remote starts it at the size you are."
        }
        var hint = buttons
        if timing.countdown == 0 {
            hint += " Recording starts straight away."
        } else if plan.lens != .front && plan.isInShot {
            hint += " The flash blinks 5 times, one a second, before recording starts."
        }
        if shot == .oneTake {
            hint += " 5 flashes lead into each part, and a fast flicker after the last one means walk back. Your remote "
                + "moves you on to the next part whenever you're ready."
        } else if plan.signalsDuringTake {
            hint += " While it records, 5 flashes lead into each new step, and a fast flicker means you're done."
        }
        if plan.signalsDuringTake {
            hint += " With AirPods in, you'll hear what's next too."
        }
        return hint
    }

    var body: some View {
        events(screen)
    }

    private var screen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(
                session: camera.session,
                hold: level.hold,
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
                onButton: { remotePressed() },
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
                if showsPrompt && level.hold == .upright {
                    // Held upright: the prompt sits just under the bar at the top.
                    promptStrip
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
                Spacer()
                if showsPrompt && level.hold == .upsideDown {
                    // Upside down, the top of the frame is by the record button: the prompt sits just past it.
                    promptStrip
                        .rotationEffect(.degrees(180))
                        .padding(.bottom, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)
                }
                bottomControls
            }

            facingLayer

            promptLayer

            if showBriefing && !isBusy && !permissionDenied {
                briefingCard
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // Leaving the app: the screen's brightness goes back to yours.
                ScreenDimmer.restore()
            }
            .onChange(of: camera.phase) { oldPhase, phase in
                if oldPhase == .recording {
                    // The take has ended: no more signals, and the screen comes back up (1.24).
                    director.takeEnded()
                    ScreenDimmer.restore()
                    // Sum up the shake and tilt before the phone gets lowered. A ONE TAKE did it as you set off back.
                    if takeMotion == nil {
                        takeMotion = level.endTake()
                    }
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
            .onReceive(lightClock) { _ in refreshLightLock() }
            .onAppear(perform: start)
            .onDisappear(perform: finish)
            .onChange(of: camera.elapsed) { _, value in
                tick(value)
            }
            .onChange(of: inShot) { _, _ in planChanged() }
            .onChange(of: variant) { _, _ in planChanged() }
            .onChange(of: roleID) { _, _ in planChanged() }
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
                if let tilt = level.tilt, let off = level.offLevel, abs(off) < 20 {
                    let isLevel = abs(off) < 1
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
                    filmingLine
                    if let glow = glowNow {
                        Label(glow == .golden ? "Golden hour: keeping the warm light" : "Blue hour: keeping the blue light",
                              systemImage: glow == .golden ? "sun.horizon.fill" : "moon.stars.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(glow == .golden ? Color.orange : Color.cyan)
                    }
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
            if shot.canToggleInShot && currentRole?.inShot == nil {
                Toggle("I'm in this shot", isOn: $inShot)
                    .tint(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5), in: Capsule())
            }
            if !shot.roles.isEmpty && fixedVariant == nil {
                rolePicker
            } else if shot == .matchCut {
                movePicker(MatchMove.allCases)
            } else if !shot.variants.isEmpty && fixedVariant == nil {
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
        if director.isFinding && camera.phase != .recording {
            notice("Finding you: stand where you'll do it, facing the phone. The light goes off once you're framed. "
                + "Tap the button to cancel.")
        } else if camera.phase == .recording {
            if plan.timelapseInterval != nil {
                lapseTimer
            } else if !camera.rolling {
                // Asked to record, but the camera hasn't started yet: just after it opens, that can take a moment.
                notice("Starting…")
            }
            // A shot you're holding gets its prompt along the top of the frame instead (promptLayer), out of the middle.
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

    /// The words in the middle of the screen. They turn to face you when the phone is sideways.
    private var facingLayer: some View {
        GeometryReader { geometry in
            let hold = level.hold
            let across = hold.isSideways ? geometry.size.height : geometry.size.width
            VStack(spacing: 14) {
                holdBanner
                centreOverlay
                if hold != .upright && !isBusy && !plan.isInShot && !plan.before.isEmpty {
                    beforeNote
                }
                if let countdownRemaining {
                    countdownView(countdownRemaining)
                }
            }
            .frame(width: min(across, 640))
            .rotationEffect(.degrees(hold.screenRotation))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .animation(.easeInOut(duration: 0.3), value: hold)
        }
        .allowsHitTesting(false)
    }

    /// Whether the phone is held the way this shot is filmed.
    private var heldRight: Bool {
        switch filming {
        case .landscape: return level.hold.isSideways
        case .portrait: return !level.hold.isSideways
        case .either: return true
        }
    }

    /// Shown while the phone is held the other way from how this shot is filmed.
    @ViewBuilder
    private var holdBanner: some View {
        if !heldRight && camera.phase == .ready && countdownRemaining == nil && reviewClip == nil && !permissionDenied
            && !showBriefing {
            let landscape = filming == .landscape
            VStack(spacing: 10) {
                Image(systemName: landscape ? "iphone.landscape" : "iphone")
                    .font(.system(size: 48))
                    .symbolEffect(.pulse)
                Text(landscape ? "Turn the phone to landscape" : "Turn the phone to portrait")
                    .font(.title3.weight(.bold))
                Text(landscape ? "This shot is for the wide, cinematic edits." : "This one is for full-screen reels.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white)
            .padding(20)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)
        }
    }

    /// Which way this shot is filmed and what the phone goes on, and whether it's held that way, under the
    /// shot's name: "Landscape · Tripod".
    private var filmingLine: some View {
        let landscapeNow = level.hold.isSideways
        let text: String
        let symbol: String
        let colour: Color
        switch filming {
        case .landscape:
            text = landscapeNow ? "Landscape" : "Turn to landscape"
            symbol = landscapeNow ? "checkmark.circle.fill" : "iphone.landscape"
            colour = landscapeNow ? .green : .orange
        case .portrait:
            text = landscapeNow ? "Turn to portrait" : "Portrait"
            symbol = landscapeNow ? "iphone" : "checkmark.circle.fill"
            colour = landscapeNow ? .orange : .green
        case .either:
            text = landscapeNow ? "Landscape" : "Portrait"
            symbol = landscapeNow ? "iphone.landscape" : "iphone"
            colour = Color.white.opacity(0.8)
        }
        return Label(text + " · " + plan.mount.title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(colour)
    }

    /// The card's first setup line: which way to hold the phone and what it goes on, like "Landscape, on the tripod."
    private var filmingNote: some View {
        let filming = self.filming
        return Label("\(filming.cardTitle), \(plan.mount.phrase).", systemImage: filming.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filming == .either ? Color.white : filming.colour)
    }

    /// How to film it, in the middle of the screen while the phone is turned.
    private var beforeNote: some View {
        Text(plan.before)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white)
            .padding(10)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
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

    /// Whether a take's prompt is showing: whenever you can see the screen while you film. That's the shots you're
    /// holding, and since 1.24 the ones on the front camera (TALK), REACTION once it's turned round to the view, and
    /// ONE TAKE while you're behind the phone. Not a time-lapse, which has its own clock in the middle.
    private var showsPrompt: Bool {
        camera.phase == .recording && camera.rolling && plan.timelapseInterval == nil
            && (!plan.isInShot || plan.lens == .front || shot == .reaction || shot == .oneTake)
    }

    /// The step to do now while you film a shot you're holding sideways (1.23): small, along the top of the frame as
    /// you see it, turned to face you and out of the middle. Held upright or upside down, it sits by the bars of
    /// buttons instead (see `screen`).
    private var promptLayer: some View {
        GeometryReader { geometry in
            let hold = level.hold
            VStack(spacing: 0) {
                if showsPrompt && hold.isSideways {
                    promptStrip
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .frame(width: geometry.size.height, height: geometry.size.width, alignment: .top)
            .rotationEffect(.degrees(hold.screenRotation))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    /// The clock, what to do now in a few words, a bar for this step, and what's next and when, like "At 0:22 · Ease
    /// to a stop". The times match the walkthrough's, including for a length you've changed.
    @ViewBuilder
    private var promptStrip: some View {
        let steps = displaySteps
        let now = camera.elapsed
        if let index = steps.lastIndex(where: { now >= $0.start }) {
            let step = steps[index]
            let next: GuideStep? = index + 1 < steps.count ? steps[index + 1] : nil
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(timing.stopsByItself ? "\(clockString(now)) / \(clockString(stopTime))" : clockString(now))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Text(step.headline)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let end = step.end {
                    ProgressView(value: min(1, max(0, (now - step.start) / max(end - step.start, 0.1))))
                        .tint(.orange)
                }
                if let next {
                    Text("At \(clockString(next.start)) · \(next.headline)")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 300, alignment: .leading)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
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
            if !isBusy && !plan.isInShot && !plan.before.isEmpty && level.hold == .upright {
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
                    if !isBusy {
                        Button {
                            showBriefing = true
                        } label: {
                            Label("How it works", systemImage: "list.bullet")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 10)
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
                    } else if shot == .oneTake && camera.phase == .recording && director.run?.walkBackAt == nil {
                        // The same as your remote: on to the next part (1.24).
                        Button {
                            _ = director.remoteNext(at: camera.elapsed)
                        } label: {
                            Label("Next part", systemImage: "forward.fill")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.5), in: Capsule())
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
                    TimingControls(timing: timingBinding, showsStopping: shot != .oneTake)
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
                if camera.phase == .recording || countdownRemaining != nil || director.isFinding {
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
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.orange)
                    }
                    if !shot.roles.isEmpty && fixedVariant == nil {
                        rolePicker
                        if let role = currentRole {
                            Text(role.purpose)
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    } else if shot == .matchCut {
                        movePicker(MatchMove.allCases)
                        Text(currentMove.summary + ". " + currentMove.cut)
                            .foregroundStyle(Color.white.opacity(0.85))
                        matchCutSizeRow
                    } else if !shot.variants.isEmpty && fixedVariant == nil {
                        Picker("Version", selection: $variant) {
                            ForEach(shot.variants.indices, id: \.self) { index in
                                Text(shot.variants[index]).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    cardHeading("Setup")
                    filmingNote
                    Text(plan.before)
                        .foregroundStyle(Color.white.opacity(0.8))
                    if let placement = plan.placement {
                        cardHeading("Where you are")
                        Text(placement)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    if shot == .oneTake {
                        cardHeading("Parts")
                        oneTakePartsEditor
                    } else {
                        cardHeading("Walkthrough")
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
                    }
                    if !shot.tips.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(shot.tips, id: \.self) { tip in
                                    Label(tip, systemImage: "lightbulb")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.85))
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text("Optional tips")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white)
                        }
                        .tint(.orange)
                    }
                    if shot.canToggleInShot && currentRole?.inShot == nil {
                        Toggle("I'm in this shot", isOn: $inShot)
                            .tint(.orange)
                    }
                    TimingControls(timing: timingBinding, showsStopping: shot != .oneTake)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Text(startHint)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Button {
                        showBriefing = false
                        HowItWorks.markSeen(shot, role: currentRole?.id)
                    } label: {
                        Text(plan.isInShot ? "Set up the shot" : "Got it")
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

    private func cardHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.top, 4)
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
        chooseStartingRole()
        timing = TimingStore.load(shot, plan: plan)
        showBriefing = plan.isInShot || !HowItWorks.seen(shot, role: currentRole?.id)
        level.start()
        director.attach(camera)
        director.voice.enabled = plan.signalsDuringTake
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
        director.takeEnded()
        director.voice.stop()
        if camera.phase == .recording {
            camera.stopRecording()
        }
        camera.stop()
        level.stop()
        ScreenDimmer.restore()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Each time the camera is ready: set the white balance for golden and blue hour.
    private func cameraReady() {
        lockedGlow = glowNow
        camera.setDaylightLock(lockedGlow != nil)
    }

    /// Golden or blue hour right now, for a shot filmed outside. Then the white balance locks to daylight, so warm
    /// light stays warm and blue light stays blue instead of being evened out.
    private var glowNow: SunCalc.Glow? {
        guard !shot.oftenIndoors, let coordinate = location.location?.coordinate else { return nil }
        return SunCalc.glow(at: Date(), latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Checked every 30 seconds, for when golden hour starts or blue hour ends while the camera is open.
    private func refreshLightLock() {
        let glow = glowNow
        guard glow != lockedGlow, camera.phase == .ready, countdownRemaining == nil else { return }
        lockedGlow = glow
        camera.setDaylightLock(glow != nil)
    }

    // MARK: Guides drawn over the picture for some creative shots

    @ViewBuilder
    private var shotGuideOverlay: some View {
        switch plan.overlay {
        case .crosshair?:
            crosshair
        case nil:
            EmptyView()
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
        director.voice.enabled = plan.signalsDuringTake
        showBriefing = plan.isInShot || !HowItWorks.seen(shot, role: currentRole?.id)
        if cameraAllowed {
            camera.configure(plan.captureConfig)
            // Setting the camera up again puts the white balance back on automatic.
            lockedGlow = glowNow
            camera.setDaylightLock(lockedGlow != nil)
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
        if director.isFinding && camera.phase != .recording {
            cancelFinding()
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
            if plan.dimsScreen {
                // Nobody's looking at it from here, and a bright screen heats the phone (1.24).
                ScreenDimmer.dim()
            }
            if shot == .matchCut {
                startFinding()
            } else if timing.countdown > 0 {
                startCountdown()
            } else {
                startSong(lead: 0)
                beginRecording()
            }
        default:
            break
        }
    }

    /// Volume up or your Bluetooth remote: the same as the red button, except that in a ONE TAKE it moves you on to
    /// the next part (and stops the take after the last one), and while MATCH CUT is finding you it starts at the size
    /// you are (1.24).
    private func remotePressed() {
        if director.isFinding && camera.phase != .recording {
            director.goAnyway()
            return
        }
        if shot == .oneTake && camera.phase == .recording {
            if !director.remoteNext(at: camera.elapsed) {
                camera.stopRecording()
            }
            return
        }
        recordTapped()
    }

    /// MATCH CUT: with the light on, finds you and zooms until you're the size you were in your first take of the move,
    /// then the light goes off and the countdown starts (1.24). Your first take sets the size.
    private func startFinding() {
        let move = currentMove
        MatchCutStore.lastMove = move
        director.voice.say("Stand where you'll do it, facing the phone.")
        director.startFinding(move: move, zooms: true, hold: level.hold) { size in
            if MatchCutStore.size(for: move) == nil, let size {
                MatchCutStore.setSize(size, for: move)
                sizeVersion += 1
            }
            director.voice.say("Got you.")
            startCountdown()
        }
    }

    private func cancelFinding() {
        director.stopFinding()
        ScreenDimmer.restore()
    }

    private func startCountdown() {
        showBriefing = false
        let total = max(timing.countdown, 1)
        startSong(lead: Double(total))
        // The flash tells you when recording starts if you're in front of the phone: 5 blinks, one a second (1.24).
        let useFlash = plan.isInShot && plan.lens != .front && camera.hasTorch
        let speaks = plan.signalsDuringTake
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for remaining in stride(from: total, through: 1, by: -1) {
                countdownRemaining = remaining
                if speaks && remaining == min(total, 5) {
                    director.voice.say(remaining == 5 ? "Recording in five" : "Recording in \(remaining)")
                }
                if useFlash && remaining <= 5 {
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
        ScreenDimmer.restore()
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
        takeMotion = nil
        startZoom = camera.displayZoom
        if used.exposure == .lockAtStart {
            camera.lockFocusAndExposure()
        }
        level.beginTake()
        // Lock the white balance for the take: to daylight in golden and blue hour, otherwise shared with a take just
        // before at the same spot on the same lens, so they match in the edit.
        takeSettings = nil
        let glow = glowNow
        let reuse = glow == nil ? Self.sameSpotWhiteBalance(in: store.trip(id: tripID), latitude: coordinate?.latitude,
                                                            longitude: coordinate?.longitude, at: now, lens: used.lens) : nil
        camera.beginTake(reuse: reuse, daylight: glow != nil, lens: used.lens) { settings in
            takeSettings = settings
        }
        songStartAtRecording = nil
        if shot == .dance {
            camera.onRecordingStarted = {
                songStartAtRecording = song.heardPosition
            }
        }
        // How long the take is set to run, so a take stopped well short doesn't count as coverage. Time-lapses
        // are left out: their video is far shorter than the time they run.
        let planned: Double? = timing.stopsByItself && used.timelapseInterval == nil ? stopTime : nil
        camera.startRecording(to: url, hold: level.hold, latitude: coordinate?.latitude, longitude: coordinate?.longitude) { result in
            saveTake(result, plan: used, startedAt: now, latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                     plannedLength: planned)
        }
        // The signals while it records, for when you can't see the screen (1.24).
        if shot == .oneTake {
            oneTakeSetup.save()
            let parts = oneTakeSetup.parts
            director.startOneTake(parts: parts, lengths: parts.map { oneTakeSetup.length(of: $0) },
                                  move: oneTakeSetup.matchMove, hold: level.hold)
        } else if used.signalsDuringTake {
            director.startTimeline(used.timeline(endingAt: timing.stopsByItself ? timing.length : nil))
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
        // The flashes into each step, and ONE TAKE's parts (1.24).
        director.tick(value)
        if shot == .oneTake, director.run?.walkBackAt != nil, takeMotion == nil {
            // The take check stops as you set off back: picking the phone up to stop it isn't the tripod shaking.
            takeMotion = level.endTake()
        }
        if timing.stopsByItself, shot != .oneTake, value >= stopTime {
            camera.stopRecording()
            if plan.facesAwayOnTripod {
                director.walkBack()
            }
        }
        if shot == .dance && song.finished && value > 1 {
            camera.stopRecording()
            director.walkBack()
        }
    }

    private func saveTake(_ result: RecordingResult?, plan used: ShotPlan, startedAt: Date, latitude: Double?, longitude: Double?,
                          plannedLength: Double?) {
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
        // ONE TAKE: the parts as you filmed them, where you moved on (1.24).
        let oneTakeRun = shot == .oneTake ? director.finishOneTake() : nil
        guard let result else {
            if let problem = camera.startProblem {
                message = "That take didn't start. The camera said \u{201C}\(problem)\u{201D}. Try again."
            } else {
                message = "That take didn't save. Try again."
            }
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
            if shot == .wildlife {
                tags.append("wildlife")
            }
            // ONE TAKE: each part as a take of its shot, for the role it fills where you are. Worked out before the
            // clip joins its scene, while the place is still the one you were filming (1.24).
            var parts: [ClipPart]? = nil
            if let oneTakeRun, let trip = store.trip(id: tripID) {
                let reached = Array(oneTakeRun.parts.prefix(oneTakeRun.starts.count))
                let fills = trip.oneTakePlan(reached, day: day, at: placeNow(in: trip))
                parts = oneTakeRun.clipParts(duration: duration, fills: fills) { partShot in
                    store.nextTake(tripID: tripID, shotName: partShot.rawValue, day: day)
                }
            }
            // The scene: the app's suggestion from where and when, or your choice for this clip if you made one.
            let scene = store.sceneForNewClip(tripID: tripID, day: day, latitude: latitude, longitude: longitude, at: startedAt)
            // Its name: a new place's is the one you gave it; otherwise your last clip's here, or the place's (1.21).
            let placeName = scene.isNew ? scene.placeName : (prefill ?? scene.placeName)
            var clip = Clip(
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
                name: placeName,
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
                shutter: settings?.shutter,
                orientation: result.sideways ? Clip.landscape : Clip.portrait,
                role: used.role?.id,
                scene: scene.scene,
                sceneConfirmed: scene.confirmed ? true : nil,
                plannedLength: plannedLength)
            clip.parts = parts
            store.addClip(clip, to: tripID)
            lastClipID = clip.id
            if placeName != nil {
                // Named after the spot you're still at, so the file gets the name straight away.
                store.applyFileName(clipID: clip.id, tripID: tripID)
            }
            if placeName == nil {
                reviewNote = nil
            } else {
                reviewNote = !scene.isNew && prefill != nil ? "Same as your last clip here" : "Named after this place"
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
        let filmedID = lastClipID
        lastClipID = nil
        take = store.nextTake(tripID: tripID, shot: shot, day: day)
        if shot.roles.isEmpty || fixedVariant != nil {
            variant = variantFor(take: take)
        }
        reviewNote = nil
        if shot == .dance {
            danceStart = carryOnPoint == nil ? .fromTop : .carryOn
        }
        guard let trip = store.trip(id: tripID), shot != .dance else { return }
        if let fixedVariant {
            // One half of a transition: done once that half has a take.
            let half = ShotSlot(shot: shot, half: fixedVariant)
            if half.takeCount(in: trip, day: day) >= 1, let name = half.variantName {
                message = shot.isTransition
                    ? "\(name) half done. Film another, or tap ✕ to pick the next shot."
                    : "Done. Film another, or tap ✕ to pick the next shot."
            }
            return
        }
        let place = shot.perPlace ? placeNow(in: trip) : nil
        let coverage = shot.roles.isEmpty ? trip.coverage(for: ShotSlot(shot: shot, half: nil), day: day)
            : roleCoverage(in: trip)
        let filmed = filmedID.flatMap { id in trip.clips.first(where: { $0.id == id }) }
        if let filmed, !filmed.countsAsCoverage {
            // Not counted: say why, and stay on the same role for another go.
            let reason = filmed.usable == false ? "You marked that take not usable"
                : filmed.checkPassed == false ? (filmed.check ?? "That take failed its check") : "That take stopped early"
            message = "\(reason), so it doesn't count yet. Film it again, or open it later and choose Use anyway."
            return
        }
        if shot == .oneTake {
            // What the parts counted as (1.24).
            if let filmed {
                let names = (filmed.parts ?? []).map { $0.takeTitle }
                message = names.isEmpty
                    ? "That take stopped before its first part, so it doesn't count for anything."
                    : "Saved as " + Self.listed(names) + ". From a new spot, another ONE TAKE fills the second roles."
            }
            return
        }
        if shot.roles.isEmpty {
            if let place, filmed != nil {
                // A shot tracked at each place, on a day at more than one: this place has its own now.
                message = "\(shot.title) filmed at \(place.name ?? "this place"). Film another, or tap ✕ to pick the next shot."
            } else if coverage.complete {
                let noun = coverage.target == 1 ? "take" : "takes"
                message = "All \(coverage.target) \(noun) done. Film an extra, or tap ✕ to pick the next shot."
            }
            return
        }
        let finished = currentRole?.title
        if let next = shot.nextRole(after: currentRole?.id, open: coverage.openRoleIDs) {
            selectRole(next.id)
            message = (finished.map { "\($0) done. " } ?? "") + "Next: \(next.title)."
        } else if coverage.complete {
            let optional = coverage.openOptionalRoles.map { $0.title }
            let more = optional.isEmpty ? "More takes are welcome as extras" : "Optional: \(optional.joined(separator: ", "))"
            let whereCovered = place.map { "at \($0.name ?? "this place")" } ?? "for today"
            message = "\(shot.title) is covered \(whereCovered). \(more), or tap ✕ to pick the next shot."
        }
    }

    /// "A, B and C".
    static func listed(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

/// The How it works card opens by itself for shots you're in, before every take, and for the rest the first
/// time you open them. The How it works button brings it back any time.
enum HowItWorks {
    /// Per shot, and per creative role since 1.19, so each role's card shows the first time you film it.
    private static func key(_ shot: ShotType, role: String?) -> String {
        "howItWorks.seen." + shot.rawValue + (role.map { ".role." + $0 } ?? "")
    }

    static func seen(_ shot: ShotType, role: String? = nil) -> Bool {
        UserDefaults.standard.bool(forKey: key(shot, role: role))
    }

    static func markSeen(_ shot: ShotType, role: String? = nil) {
        UserDefaults.standard.set(true, forKey: key(shot, role: role))
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
