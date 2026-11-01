import AVFoundation
import CoreImage
import Photos

/// Makes a copy of an Apple Log clip with the look applied, as a normal video, and saves it to Photos:
/// for posting a story straight from the phone. The clip itself stays in Log.
enum GradedCopy {
    enum CopyError: LocalizedError {
        case noVideo
        case cannotRead
        case cannotWrite
        case notAllowed

        var errorDescription: String? {
            switch self {
            case .noVideo, .cannotRead: return "The clip couldn't be read."
            case .cannotWrite: return "The copy couldn't be made."
            case .notAllowed: return "Shot Guide isn't allowed to add to Photos. You can allow it in Settings › Shot Guide › Photos."
            }
        }
    }

    static func saveToPhotos(clipURL: URL, cube: CubeLUT, progress: @escaping (Double) -> Void) async throws {
        let name = clipURL.deletingPathExtension().lastPathComponent + "_graded.mov"
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        try await render(clipURL, to: copy, cube: cube, progress: progress)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CopyError.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: copy, options: nil)
        }
    }

    /// Reads every frame without colour conversion, puts it through the look, and writes a Rec.709 video
    /// with the original sound.
    static func render(_ source: URL, to destination: URL, cube: CubeLUT, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw CopyError.noVideo }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let audioFormat = try await audioTrack?.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw CopyError.cannotRead }
        reader.add(videoOut)

        let width = Int(size.width), height = Int(size.height)
        let bitRate = width * height >= 3840 * 2160 ? 40_000_000 : 16_000_000
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoIn.expectsMediaDataInRealTime = false
        videoIn.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(videoIn) else { throw CopyError.cannotWrite }
        writer.add(videoIn)
        // The sound is copied across as it is, when both sides can take it.
        var audioIn: AVAssetWriterInput?
        var audioOut: AVAssetReaderTrackOutput?
        if let audioTrack {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            input.expectsMediaDataInRealTime = false
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if writer.canAdd(input), reader.canAdd(out) {
                writer.add(input)
                reader.add(out)
                audioIn = input
                audioOut = out
            }
        }

        guard reader.startReading() else { throw reader.error ?? CopyError.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? CopyError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        let context = LookRenderer.shared.context
        let videoQueue = DispatchQueue(label: "shotguide.graded.video")
        let audioQueue = DispatchQueue(label: "shotguide.graded.audio")
        let group = DispatchGroup()

        group.enter()
        videoIn.requestMediaDataWhenReady(on: videoQueue) {
            while videoIn.isReadyForMoreMediaData {
                guard let sample = videoOut.copyNextSampleBuffer() else {
                    videoIn.markAsFinished()
                    group.leave()
                    return
                }
                guard let frame = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                autoreleasepool {
                    var out: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                    guard let out else { return }
                    let image = cube.apply(to: CIImage(cvPixelBuffer: frame, options: [.colorSpace: NSNull()]))
                    context.render(image, to: out)
                    _ = adaptor.append(out, withPresentationTime: time)
                }
                if duration > 0 {
                    progress(min(0.99, time.seconds / duration))
                }
            }
        }
        if let audioIn, let audioOut {
            group.enter()
            audioIn.requestMediaDataWhenReady(on: audioQueue) {
                while audioIn.isReadyForMoreMediaData {
                    guard let sample = audioOut.copyNextSampleBuffer() else {
                        audioIn.markAsFinished()
                        group.leave()
                        return
                    }
                    audioIn.append(sample)
                }
            }
        }

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { done.resume() }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CopyError.cannotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CopyError.cannotWrite }
        progress(1)
    }
}
