import CoreMotion
import Foundation

/// How much the phone shook and leaned during one take, for the take check.
struct TakeMotion {
    /// Shake in degrees a second. Slow, smooth movement is left out, so only jitter counts.
    let shake: Double
    /// Average lean in degrees, + is clockwise. nil if the phone was mostly flat or pointing up or down.
    let tilt: Double?
}

/// How far the phone is tilted left or right, for the level line on the camera screen,
/// and the shake and tilt during a take, for the take check.
final class LevelMeter: ObservableObject {
    /// Degrees the phone is turned clockwise from upright. nil when it's lying flat or pointing straight up or down.
    @Published private(set) var tilt: Double? = nil

    private struct Sample {
        let time: TimeInterval
        let jitter: Double
        let tilt: Double?
    }

    private let manager = CMMotionManager()
    // Take check, on the main queue.
    private var recording = false
    private var samples: [Sample] = []
    private var smoothX = 0.0
    private var smoothY = 0.0
    private var smoothZ = 0.0
    private var smoothed = false

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity
            let lean: Double? = abs(gravity.z) > 0.85 ? nil : atan2(gravity.x, -gravity.y) * 180 / Double.pi
            self.tilt = lean
            self.record(motion, lean: lean)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = nil
        recording = false
        samples = []
    }

    /// Starts collecting shake and tilt for a take.
    func beginTake() {
        samples = []
        smoothed = false
        recording = true
    }

    /// Stops collecting and sums up the take, leaving out the moments the record button was pressed.
    func endTake() -> TakeMotion? {
        guard recording else { return nil }
        recording = false
        let all = samples
        samples = []
        guard let first = all.first?.time, let last = all.last?.time else { return nil }
        let middle = all.filter { $0.time > first + 0.7 && $0.time < last - 0.7 }
        let used = middle.count >= 15 ? middle : all
        guard !used.isEmpty else { return nil }
        let squares = used.reduce(0.0) { $0 + $1.jitter * $1.jitter }
        let shake = (squares / Double(used.count)).squareRoot()
        let leans = used.compactMap { $0.tilt }
        let tilt: Double? = leans.count * 2 >= used.count ? leans.reduce(0, +) / Double(leans.count) : nil
        return TakeMotion(shake: shake, tilt: tilt)
    }

    /// Jitter is the turning speed left over once the slow, smooth part is taken away.
    private func record(_ motion: CMDeviceMotion, lean: Double?) {
        guard recording else { return }
        let rate = motion.rotationRate
        if !smoothed {
            smoothX = rate.x
            smoothY = rate.y
            smoothZ = rate.z
            smoothed = true
        }
        let blend = 0.15
        smoothX += blend * (rate.x - smoothX)
        smoothY += blend * (rate.y - smoothY)
        smoothZ += blend * (rate.z - smoothZ)
        let dx = rate.x - smoothX
        let dy = rate.y - smoothY
        let dz = rate.z - smoothZ
        let jitter = (dx * dx + dy * dy + dz * dz).squareRoot() * 180 / Double.pi
        samples.append(Sample(time: motion.timestamp, jitter: jitter, tilt: lean))
    }
}
