import AVFoundation
import CoreImage
import Vision

/// Makes a cutout mask for a clip: a black-and-white video with the same length and timing as the clip,
/// white wherever you are in the frame. The editor uses it to put places behind you or inside your outline.
/// It uses Apple's person detection and cutout on the phone, so nothing is uploaded anywhere.
///
/// Since 1.25 it finds you first, then cuts you out from a close-up of that part of the full-size frame. Apple's cutout
/// works on a small copy of the picture, so from the whole frame anyone a few metres away came back as nothing: on the
/// test day, every wide shot's mask was empty.
///
/// Since 1.27.1 the cutout also keeps track of you once you're found. The person finder can miss someone small and
/// still (on the 1.27 test, standing with arms crossed 7 m away, for 25 seconds), and after a second it went back to
/// the whole frame, where someone that small is lost. Now wherever the cutout still finds you counts as seeing you,
/// and the close-up follows you there.
enum MaskMaker {
    enum MaskError: Error {
        case noVideo
        case cannotRead
        case cannotWrite
    }

    /// The short side of the mask video, in pixels. 1080 matches a 1080x1920 edit.
    static let shortSide: CGFloat = 1080
    /// The closest it zooms in: a quarter of the frame across, for someone far away.
    static let closestWindow: CGFloat = 0.25
    /// With you this big in the frame, the whole frame is used, as before 1.25.
    static let wholeFrameAbove: CGFloat = 0.7

    static func makeMask(for clipURL: URL, to maskURL: URL, look: CubeLUT? = nil) async throws {
        let asset = AVURLAsset(url: clipURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MaskError.noVideo
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = try await track.load(.nominalFrameRate)

        // iPhone video is stored sideways with a note to turn it; turn each frame upright first.
        let orientation = Self.orientation(of: transform)
        let sideways = orientation == .left || orientation == .right
        let upright = sideways ? CGSize(width: naturalSize.height, height: naturalSize.width) : naturalSize
        let scale = shortSide / max(min(upright.width, upright.height), 1)
        let width = Int((upright.width * scale / 2).rounded()) * 2
        let height = Int((upright.height * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MaskError.cannotRead }
        reader.add(output)

        try? FileManager.default.removeItem(at: maskURL)
        let writer = try AVAssetWriter(outputURL: maskURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw MaskError.cannotWrite }
        writer.add(input)

        guard reader.startReading() else { throw reader.error ?? MaskError.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? MaskError.cannotWrite }

        // No colour management, so the mask's blacks and whites pass straight through.
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let cutout = VNGeneratePersonSegmentationRequest()
        cutout.qualityLevel = .balanced
        cutout.outputPixelFormat = kCVPixelFormatType_OneComponent8
        // A sequence handler keeps the outline steady from one frame to the next. The part of the frame it's given is
        // always the same size, and moves smoothly, so that still works when it's zoomed in on you.
        let handler = VNSequenceRequestHandler()
        let finder = VNDetectHumanRectanglesRequest()
        finder.upperBodyOnly = false
        // Looking for you in every frame, or every other one at 50 fps and up.
        let findEvery = frameRate >= 50 ? 2 : 1
        var window = Window.whole
        var lastSeen = -1_000
        let holdFrames = Int(max(frameRate, 24))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let black = CIImage(color: .black).cropped(to: bounds)
        var started = false
        var written = 0
        var frameIndex = 0
        var lookPool: CVPixelBufferPool? = nil

        while let sample = output.copyNextSampleBuffer() {
            guard let frame = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if !started {
                // Same timeline as the clip, so mask frame N lines up with clip frame N.
                writer.startSession(atSourceTime: CMTimeMinimum(time, .zero))
                started = true
            }
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    reader.cancelReading()
                    try? FileManager.default.removeItem(at: maskURL)
                    throw writer.error ?? MaskError.cannotWrite
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw MaskError.cannotWrite }

            let appended: Bool = autoreleasepool {
                let thisFrame = frameIndex
                var finderSawYou = false
                var source = frame
                if let look, let graded = Self.graded(frame, look: look, context: context, pool: &lookPool) {
                    source = graded
                }
                // The frame upright, at full size.
                var full = CIImage(cvPixelBuffer: source).oriented(orientation)
                full = full.transformed(by: CGAffineTransform(translationX: -full.extent.minX, y: -full.extent.minY))
                let fullSize = full.extent.size
                guard fullSize.width > 0, fullSize.height > 0 else { return false }

                // Where you are: the people in a mask-sized copy of the frame.
                if frameIndex % findEvery == 0 {
                    let small = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let found = (try? VNImageRequestHandler(ciImage: small, options: [:]).perform([finder])) != nil
                    let people = found ? (finder.results ?? []).map(\.boundingBox) : []
                    if let target = Window.around(people) {
                        window = window.following(target)
                        lastSeen = frameIndex
                        finderSawYou = true
                    } else if frameIndex - lastSeen > holdFrames {
                        // Gone for a second: back to the whole frame, in case you're there but not spotted.
                        window = .whole
                    }
                }
                frameIndex += 1

                // That part of the frame, at the mask's size. `used` stays this frame's part, as following you moves
                // `window` on for the next one.
                let used = window
                let area = CGRect(x: used.x * fullSize.width, y: used.y * fullSize.height,
                                  width: used.size * fullSize.width, height: used.size * fullSize.height)
                let zoom = CGFloat(width) / max(area.width, 1)
                let part = full.cropped(to: area)
                    .transformed(by: CGAffineTransform(translationX: -area.minX, y: -area.minY))
                    .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
                guard (try? handler.perform([cutout], on: part)) != nil,
                      let maskBuffer = cutout.results?.first?.pixelBuffer else { return false }
                let mask = CIImage(cvPixelBuffer: maskBuffer)
                guard mask.extent.width > 0, mask.extent.height > 0 else { return false }

                // Where the cutout found you: that counts as seeing you, and when the finder missed you, the close-up
                // moves to follow you for the next frame (1.27.1).
                if let box = Self.personBox(in: maskBuffer, window: used) {
                    lastSeen = thisFrame
                    if !finderSawYou, let target = Window.around([box]) {
                        window = window.following(target)
                    }
                }

                // Back where that part sits in the frame, black everywhere else.
                let placed = mask
                    .transformed(by: CGAffineTransform(scaleX: used.size * CGFloat(width) / mask.extent.width,
                                                       y: used.size * CGFloat(height) / mask.extent.height))
                    .transformed(by: CGAffineTransform(translationX: used.x * CGFloat(width), y: used.y * CGFloat(height)))
                let fitted = placed.composited(over: black)
                    .cropped(to: bounds)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
                    ])
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { return false }
                context.render(fitted, to: buffer, bounds: bounds, colorSpace: nil)
                return adaptor.append(buffer, withPresentationTime: time)
            }
            if appended {
                written += 1
            }
        }

        input.markAsFinished()
        if reader.status == .failed || written == 0 {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: maskURL)
            throw reader.error ?? MaskError.cannotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: maskURL)
            throw writer.error ?? MaskError.cannotWrite
        }
    }

    /// The part of the frame the cutout looks at: the same shape as the frame, `size` of it across, its corner at `x`,
    /// `y` (fractions of the frame, from the bottom left). Same shape, so it's always the same size once scaled.
    struct Window: Equatable {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat

        static let whole = Window(x: 0, y: 0, size: 1)

        /// Around the people found, with room for arms, hair and feet. nil when nobody was found; the whole frame when
        /// they fill most of it.
        static func around(_ people: [CGRect]) -> Window? {
            guard let first = people.first else { return nil }
            let box = people.dropFirst().reduce(first) { $0.union($1) }
            let wide = box.width * 1.6
            let tall = box.height * 1.3
            let size = min(max(max(wide, tall), MaskMaker.closestWindow), 1)
            if size >= MaskMaker.wholeFrameAbove {
                return .whole
            }
            return Window(x: box.midX - size / 2, y: box.midY - size / 2, size: size).insideFrame()
        }

        /// Kept within the frame.
        func insideFrame() -> Window {
            Window(x: min(max(x, 0), 1 - size), y: min(max(y, 0), 1 - size), size: size)
        }

        func contains(_ other: Window) -> Bool {
            other.x >= x - 0.0001 && other.y >= y - 0.0001
                && other.x + other.size <= x + size + 0.0001 && other.y + other.size <= y + size + 0.0001
        }

        /// Moves part of the way to `target` each frame, so the cutout doesn't jitter, but jumps when you'd otherwise
        /// be cut off.
        func following(_ target: Window) -> Window {
            let eased = Window(x: x + (target.x - x) * 0.3, y: y + (target.y - y) * 0.3,
                               size: size + (target.size - size) * 0.3).insideFrame()
            return eased.contains(target) ? eased : target
        }
    }

    /// The box around you in a cutout of the part of the frame `window` covers, in the frame's terms (fractions from the
    /// bottom left, like the person finder's), or nil when there's hardly anything there. Every fourth pixel across and
    /// down is plenty to keep track (1.27.1).
    static func personBox(in mask: CVPixelBuffer, window: Window) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0, rowBytes >= width else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let step = 4
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var found = 0
        var looked = 0
        var y = 0
        while y < height {
            let row = pixels + y * rowBytes
            var x = 0
            while x < width {
                looked += 1
                if row[x] > 127 {
                    found += 1
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
                x += step
            }
            y += step
        }
        // A person, not a speck: at least a five-hundredth of the part.
        guard found >= 8, Double(found) / Double(max(looked, 1)) >= 0.002 else { return nil }
        let across = CGFloat(width)
        let down = CGFloat(height)
        let left = window.x + CGFloat(minX) / across * window.size
        let right = window.x + CGFloat(min(maxX + step, width)) / across * window.size
        // The cutout's rows run down from the top; the frame's fractions run up from the bottom.
        let bottom = window.y + (1 - CGFloat(min(maxY + step, height)) / down) * window.size
        let top = window.y + (1 - CGFloat(minY) / down) * window.size
        guard right > left, top > bottom else { return nil }
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// A frame put through a look (raw values in, no colour management), for clips filmed in Apple Log.
    static func graded(_ frame: CVPixelBuffer, look: CubeLUT, context: CIContext, pool: inout CVPixelBufferPool?) -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(frame),
                kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(frame),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }
        context.render(look.apply(to: CIImage(cvPixelBuffer: frame, options: [.colorSpace: NSNull()])), to: out)
        return out
    }

    /// Which way the clip's frames are stored, from its track transform.
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let degrees = Int((atan2(Double(transform.b), Double(transform.a)) * 180 / Double.pi).rounded())
        switch degrees {
        case 90: return .right
        case -90: return .left
        case 180, -180: return .down
        default: return .up
        }
    }
}
