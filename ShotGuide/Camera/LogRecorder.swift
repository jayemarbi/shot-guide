import AVFoundation
import VideoToolbox

/// Records Apple Log as 10-bit HEVC (1.25). The phone's own movie recorder only films Apple Log as ProRes, which can't
/// film 4K60 to the phone and makes files over ten times the size, so the app refused it and every clip came out in
/// the normal colour. Now, for Log, the app writes the movie itself from the camera's frames and the mic's sound, the
/// way pro camera apps do.
///
/// The frames are kept as the sensor sees them, wide, and the movie is marked to turn the way the phone was held, as
/// the phone's own recorder does. Everything runs on `queue`; `start` and `stop` hand over to it.
final class LogRecorder: NSObject {
    let videoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "shotguide.camera.log", qos: .userInitiated)

    /// One take to record.
    struct Take {
        let url: URL
        /// Turns the wide frames the way the phone was held.
        let transform: CGAffineTransform
        let fps: Int
        let metadata: [AVMetadataItem]
        /// The camera's own suggestion for the sound, when it has one.
        let audioSettings: [String: Any]?
        /// The clock the frames are timed by.
        let clock: CMClock
    }

    enum RecorderError: LocalizedError {
        case cannotWrite
        var errorDescription: String? { "The movie couldn't be written." }
    }

    // Used on `queue`
    private var take: Take?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStart: CMTime = .invalid
    private var lastVideoEnd: CMTime = .invalid
    private var started = false
    private var failed = false
    private var onStarted: ((Double) -> Void)?
    private var onFailed: ((String, Bool) -> Void)?
    /// When stop was pressed: frames from before it are still on their way, as steadying the picture holds them back.
    private var stopTime: CMTime = .invalid
    private var stopCompletion: ((URL?, String?) -> Void)?
    /// The mic's sound format, seen as its sound arrives, for when the camera has no suggestion.
    private var audioFormat: CMAudioFormatDescription?
    /// Counts takes, so the check on a take that never got going can't catch a later one.
    private var takeNumber = 0

    override init() {
        super.init()
        // Every frame is kept while recording: a dropped frame would be a jump in the clip.
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
    }

    /// Asks the camera for 10-bit frames, which keep all of Apple Log. False when it can't give them, and then the shot
    /// films in the normal colour instead. Call once the camera's format is set.
    func chooseTenBit() -> Bool {
        let tenBit = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        guard videoOutput.availableVideoPixelFormatTypes.contains(tenBit) else { return false }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: tenBit]
        return true
    }

    /// Starts a take. The movie begins with the next frame from the camera. `onStarted` is called on the main thread
    /// once it's in the file, with how many seconds ago that frame was filmed, so the take's clock can match the clip;
    /// `onFailed` with what went wrong, and whether the take had started.
    func start(_ take: Take, onStarted: @escaping (Double) -> Void, onFailed: @escaping (String, Bool) -> Void) {
        queue.async {
            self.clear()
            self.takeNumber += 1
            let number = self.takeNumber
            self.take = take
            self.onStarted = onStarted
            self.onFailed = onFailed
            // No picture from the camera: say so, rather than wait for ever.
            self.queue.asyncAfter(deadline: .now() + 6) {
                guard self.takeNumber == number, self.take != nil, !self.started, !self.failed else { return }
                self.fail("No picture came from the camera.")
            }
        }
    }

    /// Ends the take at `time`, when stop was pressed, and finishes the file. Frames filmed before then are still added
    /// as they arrive, for up to 2 seconds. `completion` gets the movie, or nil and what went wrong (nil too when it was
    /// stopped before it started). Called on any thread.
    func stop(at time: CMTime, completion: @escaping (URL?, String?) -> Void) {
        queue.async {
            guard self.writer != nil, self.started, !self.failed else {
                let wasFailed = self.failed
                self.writer?.cancelWriting()
                if let url = self.take?.url {
                    try? FileManager.default.removeItem(at: url)
                }
                self.clear()
                // A failure has already been reported.
                if !wasFailed {
                    completion(nil, nil)
                }
                return
            }
            self.stopTime = time
            self.stopCompletion = completion
            let number = self.takeNumber
            self.queue.asyncAfter(deadline: .now() + 2) {
                guard self.takeNumber == number, self.stopCompletion != nil else { return }
                self.finish()
            }
        }
    }

    /// Closes the file once the last frame is in.
    private func finish() {
        guard let writer, let completion = stopCompletion else { return }
        stopCompletion = nil
        if lastVideoEnd.isValid {
            // The sound ends with the last frame, so the clip doesn't run on with no picture.
            writer.endSession(atSourceTime: lastVideoEnd)
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        // Written in pieces while filming, it's put back together into an ordinary movie as it finishes.
        let url = writer.outputURL
        clear()
        writer.finishWriting {
            if writer.status == .completed {
                completion(url, nil)
            } else {
                completion(nil, Self.describe(writer.error))
            }
        }
    }

    private func clear() {
        take = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        sessionStart = .invalid
        lastVideoEnd = .invalid
        started = false
        failed = false
        onStarted = nil
        onFailed = nil
        stopTime = .invalid
        stopCompletion = nil
    }

    private func fail(_ problem: String) {
        guard !failed else { return }
        failed = true
        let hadStarted = started
        writer?.cancelWriting()
        if let url = take?.url {
            try? FileManager.default.removeItem(at: url)
        }
        writer = nil
        videoInput = nil
        audioInput = nil
        take = nil
        // A stop that was waiting gets nothing: the failure is what's reported.
        stopCompletion = nil
        let callback = onFailed
        DispatchQueue.main.async { callback?(problem, hadStarted) }
    }

    static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "The movie couldn't be written." }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            return "The phone is out of space."
        }
        return error.localizedFailureReason ?? error.localizedDescription
    }

    // MARK: Writing

    private func appendVideo(_ sample: CMSampleBuffer) {
        guard let take, !failed else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if stopTime.isValid, CMTimeCompare(time, stopTime) > 0 {
            // The first frame filmed after stop was pressed: the take is complete.
            finish()
            return
        }
        if writer == nil {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
            do {
                try begin(take, width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels), at: time)
            } catch {
                fail(Self.describe(error))
                return
            }
        }
        guard let writer, let input = videoInput else { return }
        // Only when the writer can't keep up, which a frame in the file can't fix.
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sample) {
            let frame = CMTime(value: 1, timescale: CMTimeScale(max(take.fps, 1)))
            lastVideoEnd = CMTimeAdd(time, frame)
            if !started {
                started = true
                // How long ago this frame was filmed: steadying the picture can hold frames back by up to a second.
                let now = CMTimeGetSeconds(CMClockGetTime(take.clock))
                let age = now - CMTimeGetSeconds(time)
                let lag = age.isFinite ? min(max(age, 0), 1.5) : 0
                let callback = onStarted
                DispatchQueue.main.async { callback?(lag) }
            }
        } else if writer.status == .failed {
            fail(Self.describe(writer.error))
        }
    }

    private func appendAudio(_ sample: CMSampleBuffer) {
        if let format = CMSampleBufferGetFormatDescription(sample) {
            audioFormat = format
        }
        guard started, !failed, let input = audioInput, sessionStart.isValid else { return }
        // Sound from before the first frame is left out.
        guard CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), sessionStart) >= 0,
              input.isReadyForMoreMediaData else { return }
        input.append(sample)
    }

    /// Opens the file with the first frame, now its size is known.
    private func begin(_ take: Take, width: Int, height: Int, at time: CMTime) throws {
        let writer = try AVAssetWriter(outputURL: take.url, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = false
        // Written in pieces, so a take cut short (a call, a flat battery) still plays up to the last few seconds.
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        writer.metadata = take.metadata

        guard let settings = Self.videoSettings(width: width, height: height, fps: take.fps, writer: writer) else {
            throw RecorderError.cannotWrite
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        video.transform = take.transform
        guard writer.canAdd(video) else { throw RecorderError.cannotWrite }
        writer.add(video)

        var audio: AVAssetWriterInput? = nil
        if let settings = audioSettings(take, writer: writer) {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }

        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        videoInput = video
        audioInput = audio
        sessionStart = time
    }

    /// HEVC with 10 bits per colour, which keeps all of Apple Log, at a rate with plenty left for grading. The fullest
    /// settings the phone takes, down to the essentials.
    static func videoSettings(width: Int, height: Int, fps: Int, writer: AVAssetWriter) -> [String: Any]? {
        let full: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate(width: width, height: height, fps: fps),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoExpectedSourceFrameRateKey: fps,
            // A key frame every second keeps the clip quick to scrub through in the edit.
            AVVideoMaxKeyFrameIntervalKey: max(fps, 1),
            AVVideoAllowFrameReorderingKey: true
        ]
        let tenBitOnly: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate(width: width, height: height, fps: fps),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String
        ]
        let rateOnly: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate(width: width, height: height, fps: fps)
        ]
        // No colour settings: the frames carry Apple Log's own, and asking for others would have them converted.
        for compression in [full, tenBitOnly, rateOnly] {
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression
            ]
            if writer.canApply(outputSettings: settings, forMediaType: .video) {
                return settings
            }
        }
        return nil
    }

    /// About 60 Mbit/s for 4K at 30 fps and 100 at 60 (roughly 450 and 750 MB a minute), less at 24 and 25 fps. 1080p
    /// gets at least 20.
    static func bitRate(width: Int, height: Int, fps: Int) -> Int {
        let size = Double(width * height) / (3840 * 2160)
        let speed = pow(Double(max(fps, 1)) / 30, 0.75)
        return max(Int(60_000_000 * size * speed), 20_000_000)
    }

    /// AAC like the phone's own recorder: the camera's suggestion, or else made to match the mic.
    private func audioSettings(_ take: Take, writer: AVAssetWriter) -> [String: Any]? {
        if let suggested = take.audioSettings, !suggested.isEmpty,
           writer.canApply(outputSettings: suggested, forMediaType: .audio) {
            return suggested
        }
        guard let format = audioFormat,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return nil }
        let channels = max(1, min(Int(description.mChannelsPerFrame), 2))
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: description.mSampleRate > 0 ? description.mSampleRate : 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 2 ? 256_000 : 128_000
        ]
        if channels == 2 {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        return writer.canApply(outputSettings: settings, forMediaType: .audio) ? settings : nil
    }
}

extension LogRecorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            appendVideo(sampleBuffer)
        } else if output === audioOutput {
            appendAudio(sampleBuffer)
        }
    }
}
