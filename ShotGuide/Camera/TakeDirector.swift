import AVFoundation
import QuartzCore
import UIKit

/// Says what's next in your ear while you film a shot you're in (1.24), when AirPods or other headphones are in. The
/// camera sets the sound up so the voice goes to them and never into the clip. With no headphones it stays quiet:
/// on the phone's speaker, the clip would hear it.
final class VoicePrompts {
    private let synthesizer = AVSpeechSynthesizer()
    /// On for the shots whose sound is set up for it: the ones you're in on the tripod.
    var enabled = false

    /// Says it after anything already being said, so "Got you" isn't cut off by "Recording in five".
    func say(_ words: String) {
        guard enabled, !words.isEmpty, Self.headphonesIn else { return }
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-GB")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Headphones are what's playing, never the phone's speaker or a speaker nearby.
    static var headphonesIn: Bool {
        let ports: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
    }
}

/// Dims the screen while a shot you're in records on the tripod (1.24): nobody's looking at it, and a bright screen in
/// the sun adds a lot of heat. It dims when you press record and comes back up when the take ends, so setting up stays
/// bright.
enum ScreenDimmer {
    private static var saved: CGFloat? = nil

    @MainActor
    static func dim() {
        guard saved == nil, let screen = currentScreen else { return }
        saved = screen.brightness
        screen.brightness = min(screen.brightness, 0.05)
    }

    @MainActor
    static func restore() {
        guard let value = saved else { return }
        saved = nil
        currentScreen?.brightness = value
    }

    @MainActor
    private static var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }
}

/// Runs the signals while you film a shot you're in on the tripod, when you can't see the screen (1.24). Five
/// flashes, one a second, lead into each new step, the same as the countdown; a fast flicker at the end means you're
/// done and can walk back. With headphones in, a voice says what's next as the flashes start. It also runs ONE TAKE's
/// parts, and MATCH CUT finding your size. Used on the main thread.
final class TakeDirector: ObservableObject {
    let voice = VoicePrompts()

    private weak var camera: CameraController?
    private let finder = PersonFinder()

    private enum Action {
        case blink
        case say(String)
    }

    private struct Cue {
        let at: Double
        let action: Action
    }

    /// The signals still to come, in time order, in seconds of the take.
    private var cues: [Cue] = []

    // MARK: ONE TAKE

    /// A ONE TAKE as it's filmed.
    struct OneTakeRun {
        var parts: [OneTakePart]
        var lengths: [Double]
        var move: MatchMove
        var index = 0
        /// When each part reached began, in seconds of the clip.
        var starts: [Double] = [0]
        /// When the current part's own time began: after it's found you, for MATCH CUT.
        var clock: Double = 0
        /// When the last part ended and you set off back to the phone.
        var walkBackAt: Double? = nil
        /// MATCH CUT's part, finding your size before your move.
        var finding = false
    }

    @Published private(set) var run: OneTakeRun? = nil
    private var hold: PhoneHold = .sidewaysLeft

    // MARK: Finding your size

    /// MATCH CUT finding you: zooming to your size on its own, or in a ONE TAKE, waiting for you to walk to it.
    struct Finding {
        /// Your size in your first take of the move, or nil when this is it.
        var target: Double?
        var zooms: Bool
        var readings: [Double] = []
        var settleUntil: CFTimeInterval = 0
        var lastHint: CFTimeInterval = 0
        var found: (Double?) -> Void
    }

    @Published private(set) var finding: Finding? = nil

    var isFinding: Bool { finding != nil }

    func attach(_ camera: CameraController) {
        self.camera = camera
    }

    // MARK: Signals

    /// Five flashes leading into `time`, one a second, and the voice saying what's next as they start.
    private func leadIn(to time: Double, saying words: String?) {
        for second in 1...5 {
            cues.append(Cue(at: time - Double(6 - second), action: .blink))
        }
        if let words {
            cues.append(Cue(at: time - 5, action: .say(words)))
        }
        cues.sort { $0.at < $1.at }
    }

    /// A take that follows its walkthrough: 5 flashes into each step there's room for (the step before is 5 seconds or
    /// more), so you know when to move on without seeing the screen.
    func startTimeline(_ steps: [GuideStep]) {
        cues = []
        run = nil
        for index in steps.indices.dropFirst() where steps[index].start - steps[index - 1].start >= 5 {
            leadIn(to: steps[index].start, saying: "Next: " + steps[index].headline)
        }
    }

    /// As the take's clock ticks, in seconds since it started recording.
    func tick(_ now: Double) {
        while let first = cues.first, first.at <= now {
            cues.removeFirst()
            fire(first.action)
        }
        if let current = run, !current.finding, current.walkBackAt == nil, current.index < current.parts.count,
           now >= current.clock + current.lengths[current.index] {
            advance(at: now)
        }
    }

    private func fire(_ action: Action) {
        switch action {
        case .blink:
            camera?.blinkTorch()
        case .say(let words):
            voice.say(words)
        }
    }

    /// You're done: the fast flicker, and walk back in your ear.
    func walkBack(saying words: String = "Done. Walk back to the phone.") {
        camera?.flickerTorch()
        voice.say(words)
    }

    /// The take has stopped: no more signals. A ONE TAKE's parts stay until they're saved.
    func takeEnded() {
        cues = []
        stopFinding()
    }

    // MARK: ONE TAKE

    func startOneTake(parts: [OneTakePart], lengths: [Double], move: MatchMove, hold: PhoneHold) {
        cues = []
        self.hold = hold
        run = OneTakeRun(parts: parts, lengths: lengths, move: move)
        beginPart(at: 0)
    }

    /// The current part starts: its signals, or for MATCH CUT, finding your size first.
    private func beginPart(at now: Double) {
        guard var current = run, current.index < current.parts.count else { return }
        current.clock = now
        if current.parts[current.index] == .matchCut {
            current.finding = true
            run = current
            let move = current.move
            voice.say("\(move.title). Walk slowly towards the phone until the light goes off.")
            startFinding(move: move, zooms: false, hold: hold) { [weak self] size in
                // Your first take of a move sets your size, wherever it was.
                if MatchCutStore.size(for: move) == nil, let size {
                    MatchCutStore.setSize(size, for: move)
                }
                self?.matchCutFound()
            }
            return
        }
        run = current
        scheduleSignals(for: current)
    }

    /// MATCH CUT's part has found you: 5 flashes count you into your move, and the part's time starts then.
    private func matchCutFound() {
        guard var current = run, let now = camera?.elapsed else { return }
        current.finding = false
        current.clock = now + 5
        run = current
        leadIn(to: now + 5, saying: "Got you. Your move in five.")
        cues.append(Cue(at: now + 5, action: .say("Go")))
        cues.sort { $0.at < $1.at }
        scheduleSignals(for: current)
    }

    /// The current part's signals: 5 flashes into the next part, and for clones a nudge to a new spot every 30
    /// seconds, then 5 flashes into walking out for the last 30. The last part ends with the walk-back flicker instead.
    private func scheduleSignals(for current: OneTakeRun) {
        let part = current.parts[current.index]
        let end = current.clock + current.lengths[current.index]
        if part == .clones && end - current.clock >= 60 {
            var nudge = current.clock + 30
            while nudge <= end - 60 {
                leadIn(to: nudge, saying: "New spot")
                nudge += 30
            }
            leadIn(to: end - 30, saying: "Walk out, and leave it empty")
        }
        if current.index + 1 < current.parts.count {
            let next = current.parts[current.index + 1]
            leadIn(to: end, saying: "Next: " + GuideStep(start: 0, end: nil, text: next.text(move: current.move)).headline)
        }
    }

    private func advance(at now: Double) {
        guard var current = run else { return }
        if current.finding {
            stopFinding()
            current.finding = false
        }
        cues = []
        current.index += 1
        if current.index < current.parts.count {
            current.starts.append(now)
            run = current
            beginPart(at: now)
        } else {
            current.walkBackAt = now
            run = current
            walkBack(saying: "That's everything. Walk back to the phone, and stop it when you get there.")
        }
    }

    /// Your remote in a ONE TAKE: on to the next part, or while MATCH CUT's part is finding you, your move now at the
    /// size you are. After the last part it returns false: stop the take.
    func remoteNext(at now: Double) -> Bool {
        guard let current = run, current.walkBackAt == nil else { return false }
        if current.finding {
            goAnyway()
            return true
        }
        advance(at: now)
        return true
    }

    /// The parts as filmed, once the take has stopped. Clears the run.
    func finishOneTake() -> OneTakeRun? {
        let finished = run
        run = nil
        return finished
    }

    /// The walkthrough as it's going: the parts so far where they really started, the rest at their lengths from where
    /// the current one will end. While MATCH CUT's part is still finding you, it ends at the earliest 5 seconds and its
    /// length from now.
    func liveSteps(now: Double) -> [GuideStep]? {
        guard let current = run else { return nil }
        var steps: [GuideStep] = []
        var clock = now
        for index in current.parts.indices {
            let text = current.parts[index].text(move: current.move)
            if index < current.starts.count {
                let start = current.starts[index]
                let end: Double
                if index + 1 < current.starts.count {
                    end = current.starts[index + 1]
                } else if let walkBack = current.walkBackAt {
                    end = walkBack
                } else if current.finding {
                    end = max(now, start) + 5 + current.lengths[index]
                } else {
                    end = current.clock + current.lengths[index]
                }
                steps.append(GuideStep(start: start, end: end, text: text))
                clock = end
            } else {
                steps.append(GuideStep(start: clock, end: clock + current.lengths[index], text: text))
                clock += current.lengths[index]
            }
        }
        steps.append(GuideStep(start: current.walkBackAt ?? clock, end: nil, text: OneTakePart.walkBackText))
        return steps
    }

    // MARK: Finding your size

    /// Looks for you with the light on until you're the size you were in your first take of the move, then turns the
    /// light off and calls `found` with your size. On its own MATCH CUT zooms to you; in a ONE TAKE the zoom can't move,
    /// so you walk until you're the right size.
    func startFinding(move: MatchMove, zooms: Bool, hold: PhoneHold, found: @escaping (Double?) -> Void) {
        guard let camera else { return }
        finding = Finding(target: MatchCutStore.size(for: move), zooms: zooms, found: found)
        finder.setUp(hold: hold, upperBodyOnly: move.measuresUpperBody)
        finder.onMeasure = { [weak self] height in
            self?.measured(height)
        }
        camera.setPersonFinder(finder)
        camera.setTorch(true)
    }

    func stopFinding() {
        guard finding != nil else { return }
        finding = nil
        finder.onMeasure = nil
        camera?.setPersonFinder(nil)
        camera?.setTorch(false)
    }

    /// Your remote while it's finding you: go now, at the size you are.
    func goAnyway() {
        guard let current = finding else { return }
        let size = current.readings.last
        stopFinding()
        current.found(size)
    }

    private func measured(_ height: Double?) {
        guard var current = finding, let camera else { return }
        let now = CACurrentMediaTime()
        guard now >= current.settleUntil else { return }
        guard let height, height > 0.03 else {
            current.readings = []
            hint("Stand in the middle, facing the phone.", in: &current, at: now)
            finding = current
            return
        }
        current.readings.append(height)
        if current.readings.count > 3 {
            current.readings.removeFirst()
        }
        let average = current.readings.reduce(0, +) / Double(current.readings.count)
        let spread = (current.readings.max() ?? 0) - (current.readings.min() ?? 0)
        let still = current.readings.count == 3 && spread <= 0.06 * average
        if let target = current.target {
            let ratio = target / height
            if abs(ratio - 1) <= 0.07 {
                if still {
                    finish(current, size: target)
                    return
                }
            } else if current.zooms {
                let zoom = camera.displayZoom
                let wanted = zoom * ratio
                let reachable = min(max(wanted, camera.zoomLimits.lowerBound), min(camera.zoomLimits.upperBound, 10))
                if abs(reachable - zoom) / zoom > 0.02 {
                    camera.rampZoom(toDisplay: reachable)
                    current.readings = []
                    current.settleUntil = now + 0.4 + abs(log2(reachable / zoom)) / 4
                } else {
                    // As far as the zoom goes: you need to move.
                    hint(wanted < zoom ? "Step back a little." : "Come a little closer.", in: &current, at: now)
                }
            } else {
                hint(ratio > 1 ? "Come a little closer." : "Step back a little.", in: &current, at: now)
            }
        } else if still {
            // Your first take of this move: you're standing still, so this is your size from now on.
            finish(current, size: average)
            return
        }
        finding = current
    }

    private func finish(_ current: Finding, size: Double?) {
        stopFinding()
        current.found(size)
    }

    private func hint(_ words: String, in current: inout Finding, at now: CFTimeInterval) {
        guard now - current.lastHint > 6 else { return }
        current.lastHint = now
        voice.say(words)
    }
}
