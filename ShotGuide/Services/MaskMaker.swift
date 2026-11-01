import AVFoundation
import CoreImage
import Vision

/// Makes a cutout mask for a clip: a black-and-white video with the same length and timing as the clip,
/// white wherever you are in the frame. The editor uses it to put places behind you or inside your outline.
/// It uses Apple's person segmentation on the phone, so nothing is uploaded anywhere.
enum MaskMaker {
    enum MaskError: Error {
        case noVideo
        case cannotRead
        case cannotWrite
    }

    /// The short side of the mask video, in pixels. 1080 matches a 1080x1920 edit.
    static let shortSide: CGFloat = 1080

    static func makeMask(for clipURL: URL, to maskURL: URL, look: CubeLUT? = nil) async throws {
        let asset = AVURLAsset(url: clipURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MaskError.noVideo
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

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
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        // A sequence handler keeps the outline steady from one frame to the next.
        let handler = VNSequenceRequestHandler()
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var started = false
        var written = 0
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
                var source = frame
                if let look, let graded = Self.graded(frame, look: look, context: context, pool: &lookPool) {
                    source = graded
                }
                var image = CIImage(cvPixelBuffer: source).oriented(orientation)
                image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard (try? handler.perform([request], on: image)) != nil,
                      let maskBuffer = request.results?.first?.pixelBuffer else { return false }
                let mask = CIImage(cvPixelBuffer: maskBuffer)
                guard mask.extent.width > 0, mask.extent.height > 0 else { return false }
                let fitted = mask
                    .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / mask.extent.width,
                                                       y: CGFloat(height) / mask.extent.height))
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
