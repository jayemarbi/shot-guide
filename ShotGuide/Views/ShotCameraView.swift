import AVFoundation
import SwiftUI
import UIKit

/// Films one shot. Phone-in-hand shots get live prompts; in-the-shot shots get a timeline,
/// a countdown (with the flash blinking for the last 3 seconds), a clean screen and an instant replay.
struct ShotCameraView: View {
    let tripID: UUID
    let shot: ShotType

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()

    @State private var inShot: Bool
    @State private var variant = 0
    @State private var take = 1
    @State private var showBriefing: Bool
    @State private var countdownLength = 5
    @State private var countdownRemaining: Int? = nil
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var cameraAllowed = false
    @State private var permissionDenied = false
    @State private var focusPoint: CGPoint? = nil
    @State private var reviewClip: Clip? = nil
    @State private var zoomStarted = false
    @State private var message: String? = nil
    @State private var started = false

    init(tripID: UUID, shot: ShotType) {
        self.tripID = tripID
        self.shot = shot
        _inShot = State(initialValue: shot.defaultGroup == .inShot)
        _showBriefing = State(initialValue: shot.defaultGroup == .inShot)
    }

    private var plan: ShotPlan {
        shot.plan(take: take, inShot: inShot, variant: variant)
    }

    private var isBusy: Bool {
        camera.phase == .recording || camera.phase == .finishing || countdownRemaining != nil
    }

    private var takeLabel: String {
        take > shot.targetTakes ? "extra take \(take)" : "take \(take) of \(shot.targetTakes)"
    }

    private var countdownChoices: [Int] {
        Array(Set([3, 5, 10, 30, 45, plan.countdown])).sorted()
    }

    private var startHint: String {
        if plan.lens == .front {
            return "Start with the red button or a volume button."
        }
        return "Start with the red button, a volume button or your Bluetooth remote. The flash blinks for the last 3 seconds before recording starts."
    }

    var body: some View {
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
                onButton: { recordTapped() })
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
                title: "\(shot.title) · take \(clip.take)")
        }
    }

    // MARK: Pieces of the screen

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

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(shot.title) · \(takeLabel)")
                        .font(.headline)
                    Text([camera.lensLabel, camera.formatLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
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
            if !shot.variants.isEmpty {
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
        let steps = plan.steps
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
                    Text(clockString(camera.elapsed))
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
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 120, height: 44)

                Spacer()
                recordButton
                Spacer()

                Color.clear.frame(width: 120, height: 44)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal)
        .padding(.bottom, 24)
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
                    Text(plan.before)
                        .foregroundStyle(Color.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.steps, id: \.self) { step in
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Countdown")
                            .font(.subheadline.weight(.semibold))
                        Picker("Countdown", selection: $countdownLength) {
                            ForEach(countdownChoices, id: \.self) { seconds in
                                Text("\(seconds) s").tag(seconds)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
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
        take = store.nextTake(tripID: tripID, shot: shot)
        variant = shot.defaultVariant(forTake: take)
        countdownLength = plan.countdown
        showBriefing = plan.isInShot
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
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func planChanged() {
        countdownLength = plan.countdown
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
            message = nil
            if plan.isInShot {
                startCountdown()
            } else {
                beginRecording()
            }
        default:
            break
        }
    }

    private func startCountdown() {
        showBriefing = false
        let total = max(countdownLength, 1)
        let useFlash = plan.lens != .front && camera.hasTorch
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
    }

    private func beginRecording() {
        let now = Date()
        guard let url = store.newClipURL(tripID: tripID, shot: shot, take: take, date: now) else {
            message = "Couldn't find this trip's folder."
            return
        }
        let used = plan
        let coordinate = location.location?.coordinate
        zoomStarted = false
        camera.startRecording(to: url, latitude: coordinate?.latitude, longitude: coordinate?.longitude) { result in
            saveTake(result, plan: used, startedAt: now, latitude: coordinate?.latitude, longitude: coordinate?.longitude)
        }
    }

    private func tick(_ value: Double) {
        guard camera.phase == .recording else { return }
        if let ramp = plan.zoomRamp, !zoomStarted, value >= ramp.startAt {
            zoomStarted = true
            camera.rampZoom(fromDisplay: ramp.from, toDisplay: ramp.to, duration: ramp.duration)
        }
        if let stopAt = plan.autoStop, value >= stopAt {
            camera.stopRecording()
        }
    }

    private func saveTake(_ result: RecordingResult?, plan used: ShotPlan, startedAt: Date, latitude: Double?, longitude: Double?) {
        // Put the zoom back where this shot starts, ready for the next take.
        camera.setLens(used.lens)
        guard let result else {
            message = "That take didn't save. Try again."
            return
        }
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
                notes: "")
            store.addClip(clip, to: tripID)
            reviewClip = clip
        }
    }

    private func reviewDismissed() {
        take = store.nextTake(tripID: tripID, shot: shot)
        variant = shot.defaultVariant(forTake: take)
        let count = store.trip(id: tripID)?.takeCount(of: shot) ?? 0
        if count >= shot.targetTakes {
            let noun = shot.targetTakes == 1 ? "take" : "takes"
            message = "All \(shot.targetTakes) \(noun) done. Film an extra, or tap ✕ to pick the next shot."
        }
    }

    private static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
