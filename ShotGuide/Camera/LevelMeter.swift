import CoreMotion
import Foundation

/// How far the phone is tilted left or right, for the level line on the camera screen.
final class LevelMeter: ObservableObject {
    /// Degrees the phone is turned clockwise from upright. nil when it's lying flat or pointing straight up or down.
    @Published private(set) var tilt: Double? = nil

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            if abs(gravity.z) > 0.85 {
                self.tilt = nil
                return
            }
            self.tilt = atan2(gravity.x, -gravity.y) * 180 / Double.pi
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = nil
    }
}
