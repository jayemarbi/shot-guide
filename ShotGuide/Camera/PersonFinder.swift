import CoreGraphics
import CoreVideo
import ImageIO
import QuartzCore
import Vision

/// Finds you in the camera's preview frames, for MATCH CUT (1.24): how tall you are in the frame, as a share of its
/// height, with Apple's person detection on the phone. Nothing leaves the phone.
final class PersonFinder {
    /// Called on the main thread about five times a second with your height in the frame (0 to 1), or nil when
    /// nobody's found.
    var onMeasure: ((Double?) -> Void)?

    private let queue = DispatchQueue(label: "shotguide.personfinder")
    private let lock = NSLock()
    private var busy = false
    private var lastLook: CFTimeInterval = 0
    private var orientation: CGImagePropertyOrientation = .up
    private var upperBodyOnly = false

    /// Which way the frames need turning for you to be upright, from how the phone's held, and whether to measure all
    /// of you or just your head and shoulders (for close-ups).
    func setUp(hold: PhoneHold, upperBodyOnly: Bool) {
        lock.lock()
        orientation = Self.orientation(for: hold)
        self.upperBodyOnly = upperBodyOnly
        lock.unlock()
    }

    /// The preview's frames come upright for the phone held upright. Held sideways, you lie across them: top of the
    /// phone to the left, your head points to the frame's right edge, so it's turned a quarter anticlockwise.
    static func orientation(for hold: PhoneHold) -> CGImagePropertyOrientation {
        switch hold {
        case .upright: return .up
        case .sidewaysLeft: return .left
        case .sidewaysRight: return .right
        case .upsideDown: return .down
        }
    }

    /// From the camera's data queue, with every preview frame. It looks at one every 0.2 seconds, one at a time.
    func process(_ buffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        lock.lock()
        guard !busy, now - lastLook >= 0.2 else {
            lock.unlock()
            return
        }
        busy = true
        lastLook = now
        let orientation = self.orientation
        let upperBody = upperBodyOnly
        lock.unlock()

        queue.async {
            let request = VNDetectHumanRectanglesRequest()
            request.upperBodyOnly = upperBody
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
            var height: Double? = nil
            if (try? handler.perform([request])) != nil, let people = request.results, !people.isEmpty {
                // Whoever's biggest and nearest the middle: you, rather than someone passing in the background.
                if let best = people.max(by: { Self.score($0.boundingBox) < Self.score($1.boundingBox) }) {
                    height = Double(best.boundingBox.height)
                }
            }
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
            DispatchQueue.main.async {
                self.onMeasure?(height)
            }
        }
    }

    private static func score(_ box: CGRect) -> Double {
        let dx = Double(box.midX) - 0.5
        let dy = Double(box.midY) - 0.5
        let offCentre = (dx * dx + dy * dy).squareRoot()
        return Double(box.width * box.height) * max(0.1, 1 - offCentre * 1.5)
    }
}
