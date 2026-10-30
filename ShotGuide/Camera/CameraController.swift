import AVFoundation
import UIKit

struct CaptureConfig: Equatable {
    var lens: LensChoice
    var fps: Int
    var stabilisation: Stabilisation
    var timelapseInterval: Double?
}

struct RecordingResult {
    let url: URL
    let fps: Int
    let resolution: String
    let lensLabel: String
    let elapsed: Double
}

enum CameraError: Error {
    case cannotAdd
}

/// Runs the iPhone camera with the settings each shot needs, and records movies or time-lapses.
final class CameraController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case ready
        case recording
        case finishing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var lensLabel: String = ""
    @Published private(set) var formatLabel: String = ""
    @Published private(set) var exposureLocked = false
    @Published private(set) var availableLenses: [LensChoice] = []
    @Published private(set) var lensTitles: [LensChoice: String] = [:]
    @Published private(set) var currentLens: LensChoice = .wide
    @Published private(set) var hasTorch = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "shotguide.camera.session")
    private let dataQueue = DispatchQueue(label: "shotguide.camera.data")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let dataOutput = AVCaptureVideoDataOutput()

    // Session-queue state
    private var device: AVCaptureDevice?
    private var config: CaptureConfig?
    private var exposureBias: Float = 0

    // Main-thread state
    private var mainConfig: CaptureConfig?
    private var activeFPS = 30
    private var activeResolution = ""
    private var startTime: CFTimeInterval = 0
    private var ticker: Timer?
    private var finishHandler: ((RecordingResult?) -> Void)?

    // Time-lapse state, used on dataQueue
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var lapseInterval: Double = 1
    private var lapseFrames: Int64 = 0
    private var lapseLast: CMTime = .invalid
    private var lapseActive = false

    // MARK: Permissions

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { videoAllowed in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion(videoAllowed) }
            }
        }
    }

    // MARK: Setting up a shot

    func configure(_ newConfig: CaptureConfig) {
        mainConfig = newConfig
        sessionQueue.async {
            if self.config == newConfig, self.session.isRunning {
                DispatchQueue.main.async { self.phase = .ready }
                return
            }
            self.config = newConfig
            self.applyConfiguration(newConfig)
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.config = nil
        }
    }

    private func report(_ phase: Phase) {
        DispatchQueue.main.async { self.phase = phase }
    }

    private func applyConfiguration(_ config: CaptureConfig) {
        let isLapse = config.timelapseInterval != nil

        session.beginConfiguration()
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard let device = Self.pickDevice(for: config) else {
            session.commitConfiguration()
            report(.failed("No camera is available."))
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotAdd }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            report(.failed("The camera couldn't be opened."))
            return
        }
        self.device = device

        if !isLapse,
           let microphone = AVCaptureDevice.default(for: .audio),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
        }

        if isLapse {
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            }
        } else if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        if let format = Self.pickFormat(device: device, fps: config.fps) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                if format.supportedColorSpaces.contains(.sRGB) {
                    device.activeColorSpace = .sRGB
                }
                device.unlockForConfiguration()
            } catch {}
        }

        let connection = isLapse ? dataOutput.connection(with: .video) : movieOutput.connection(with: .video)
        if let connection {
            if !isLapse, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = Self.stabilisationMode(config.stabilisation, format: device.activeFormat)
            }
            if config.lens == .front, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            if !isLapse, movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }
        session.commitConfiguration()

        // Frame rate, zoom, focus and exposure go on after the commit, because adding an input resets them.
        let fps = Self.clampFPS(config.fps, format: device.activeFormat)
        do {
            try device.lockForConfiguration()
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.videoZoomFactor = Self.clampZoom(Self.zoomFactor(for: config.lens, device: device), device: device)
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(0, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
        exposureBias = 0

        if !session.isRunning {
            session.startRunning()
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let resolution = "\(dimensions.width)x\(dimensions.height)"
        let lenses = Self.lenses(for: device, config: config)
        var titles: [LensChoice: String] = [:]
        for lens in lenses {
            titles[lens] = Self.label(for: lens, device: device)
        }
        let label = Self.label(for: config.lens, device: device)
        let formatText = "\(Self.resolutionName(dimensions)) · " + (isLapse ? "Time-lapse" : "\(fps) fps")
        let torch = device.hasTorch
        DispatchQueue.main.async {
            self.activeFPS = isLapse ? 30 : fps
            self.activeResolution = resolution
            self.availableLenses = lenses
            self.lensTitles = titles
            self.currentLens = config.lens
            self.lensLabel = label
            self.formatLabel = formatText
            self.hasTorch = torch
            self.exposureLocked = false
            self.phase = .ready
        }
    }

    // MARK: Lenses and zoom

    func setLens(_ lens: LensChoice) {
        sessionQueue.async {
            guard let device = self.device, lens != .front else { return }
            let factor = Self.clampZoom(Self.zoomFactor(for: lens, device: device), device: device)
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: factor, withRate: 8)
                device.unlockForConfiguration()
            } catch {}
            let label = Self.label(for: lens, device: device)
            DispatchQueue.main.async {
                self.currentLens = lens
                self.lensLabel = label
            }
        }
    }

    /// Zooms smoothly between two on-screen zoom values (e.g. 0.5x to 2x) over a set time.
    func rampZoom(fromDisplay: Double, toDisplay: Double, duration: Double) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let multiplier = Self.displayMultiplier(device)
            let from = Self.clampZoom(CGFloat(fromDisplay / multiplier), device: device)
            let to = Self.clampZoom(CGFloat(toDisplay / multiplier), device: device)
            let doublings = abs(log2(Double(to) / Double(from)))
            let rate = Float(doublings / max(duration, 0.1))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: to, withRate: max(rate, 0.05))
                device.unlockForConfiguration()
            } catch {}
            let label = Self.formatZoom(Double(to) * multiplier)
            DispatchQueue.main.async { self.lensLabel = label }
        }
    }

    // MARK: Focus, exposure and the flash

    /// Tap: focus and expose there. Hold: also lock both.
    func focus(at devicePoint: CGPoint, lock: Bool) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if lock {
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async { self.exposureLocked = lock }
        }
    }

    /// Drag up to brighten, down to darken.
    func nudgeExposure(by delta: Float) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let bias = min(max(self.exposureBias + delta, device.minExposureTargetBias), device.maxExposureTargetBias)
            self.exposureBias = bias
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(bias, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async {
            guard let device = self.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if on {
                    if device.isTorchModeSupported(.on) {
                        device.torchMode = .on
                    }
                } else if device.torchMode != .off {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Recording

    func startRecording(to url: URL, latitude: Double?, longitude: Double?, onFinish: @escaping (RecordingResult?) -> Void) {
        guard phase == .ready else { return }
        finishHandler = onFinish
        elapsed = 0
        phase = .recording
        let interval = mainConfig?.timelapseInterval
        sessionQueue.async {
            if let interval {
                self.startLapse(to: url, interval: interval, latitude: latitude, longitude: longitude)
            } else {
                self.movieOutput.metadata = Self.locationMetadata(latitude: latitude, longitude: longitude)
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording() {
        guard phase == .recording else { return }
        phase = .finishing
        ticker?.invalidate()
        ticker = nil
        let isLapse = mainConfig?.timelapseInterval != nil
        sessionQueue.async {
            if isLapse {
                self.finishLapse()
            } else if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                // Stop was pressed before recording had started; try again in a moment.
                self.sessionQueue.asyncAfter(deadline: .now() + 0.5) {
                    if self.movieOutput.isRecording {
                        self.movieOutput.stopRecording()
                    } else {
                        DispatchQueue.main.async { self.deliver(url: nil) }
                    }
                }
            }
        }
    }

    private func recordingStarted() {
        startTime = CACurrentMediaTime()
        elapsed = 0
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = CACurrentMediaTime() - self.startTime
        }
    }

    private func deliver(url: URL?) {
        ticker?.invalidate()
        ticker = nil
        let result = url.map {
            RecordingResult(url: $0, fps: activeFPS, resolution: activeResolution, lensLabel: lensLabel, elapsed: elapsed)
        }
        phase = .ready
        let handler = finishHandler
        finishHandler = nil
        handler?(result)
    }

    static func locationMetadata(latitude: Double?, longitude: Double?) -> [AVMetadataItem] {
        guard let latitude, let longitude else { return [] }
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataLocationISO6709
        item.dataType = kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709 as String
        item.value = String(format: "%+09.5f%+010.5f/", latitude, longitude) as NSString
        return [item]
    }

    // MARK: Time-lapse

    private func startLapse(to url: URL, interval: Double, latitude: Double?, longitude: Double?) {
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            var settings = dataOutput.recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov) ?? [:]
            if settings.isEmpty, let device {
                let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                settings = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height)
                ]
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            // Frames arrive sideways; this turns the finished video upright.
            input.transform = CGAffineTransform(rotationAngle: .pi / 2)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            guard writer.canAdd(input) else { throw CameraError.cannotAdd }
            writer.add(input)
            writer.metadata = Self.locationMetadata(latitude: latitude, longitude: longitude)
            guard writer.startWriting() else { throw writer.error ?? CameraError.cannotAdd }
            writer.startSession(atSourceTime: .zero)
            dataQueue.async {
                self.writer = writer
                self.writerInput = input
                self.adaptor = adaptor
                self.lapseInterval = interval
                self.lapseFrames = 0
                self.lapseLast = .invalid
                self.lapseActive = true
            }
            DispatchQueue.main.async { self.recordingStarted() }
        } catch {
            DispatchQueue.main.async { self.deliver(url: nil) }
        }
    }

    private func finishLapse() {
        dataQueue.async {
            self.lapseActive = false
            guard let writer = self.writer, let input = self.writerInput else {
                DispatchQueue.main.async { self.deliver(url: nil) }
                return
            }
            let frames = self.lapseFrames
            let url = writer.outputURL
            self.writer = nil
            self.writerInput = nil
            self.adaptor = nil
            if frames == 0 {
                writer.cancelWriting()
                DispatchQueue.main.async { self.deliver(url: nil) }
                return
            }
            input.markAsFinished()
            writer.finishWriting {
                let succeeded = writer.status == .completed
                DispatchQueue.main.async { self.deliver(url: succeeded ? url : nil) }
            }
        }
    }

    // MARK: Picking the camera, format and settings

    static func pickDevice(for config: CaptureConfig) -> AVCaptureDevice? {
        if config.lens == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        if config.fps > 60 {
            // High frame rates come from the main (1x) camera on its own.
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// The best 16:9, 8-bit format that reaches the frame rate: 4K first, then 1080p.
    static func pickFormat(device: AVCaptureDevice, fps: Int) -> AVCaptureDevice.Format? {
        let wanted = Double(fps)
        let eightBit: Set<FourCharCode> = [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        func topRate(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
        }
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let isWidescreen = Int(dimensions.width) * 9 == Int(dimensions.height) * 16
            return eightBit.contains(CMFormatDescriptionGetMediaSubType(format.formatDescription))
                && topRate(format) >= wanted - 0.5
                && isWidescreen
        }
        func score(_ format: AVCaptureDevice.Format) -> Int {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            var points = 0
            if dimensions.width == 3840 {
                points += 1000
            } else if dimensions.width == 1920 {
                points += 500
            } else {
                points += Int(dimensions.width) / 20
            }
            if format.isVideoStabilizationModeSupported(.cinematicExtended) { points += 40 }
            if !format.isVideoBinned { points += 20 }
            if CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                points += 5
            }
            return points
        }
        return candidates.max { score($0) < score($1) }
    }

    static func clampFPS(_ fps: Int, format: AVCaptureDevice.Format) -> Int {
        let ranges = format.videoSupportedFrameRateRanges
        let top = ranges.map { $0.maxFrameRate }.max() ?? 30
        let bottom = ranges.map { $0.minFrameRate }.min() ?? 1
        return Int(min(max(Double(fps), bottom), top).rounded(.down))
    }

    static func stabilisationMode(_ wanted: Stabilisation, format: AVCaptureDevice.Format) -> AVCaptureVideoStabilizationMode {
        let order: [AVCaptureVideoStabilizationMode]
        switch wanted {
        case .off:
            return .off
        case .standard:
            order = [.standard]
        case .cinematic:
            order = [.cinematicExtended, .cinematic, .standard]
        case .strongest:
            order = [.cinematicExtendedEnhanced, .cinematicExtended, .cinematic, .standard]
        }
        return order.first { format.isVideoStabilizationModeSupported($0) } ?? .off
    }

    static func hasConstituent(_ device: AVCaptureDevice, _ type: AVCaptureDevice.DeviceType) -> Bool {
        device.constituentDevices.contains { $0.deviceType == type }
    }

    /// On phones with an ultra wide, the camera's zoom factor 1 is what the Camera app calls 0.5x.
    static func displayMultiplier(_ device: AVCaptureDevice) -> Double {
        hasConstituent(device, .builtInUltraWideCamera) ? 0.5 : 1.0
    }

    static func zoomFactor(for lens: LensChoice, device: AVCaptureDevice) -> CGFloat {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let hasUltraWide = hasConstituent(device, .builtInUltraWideCamera)
        switch lens {
        case .ultraWide, .front:
            return 1
        case .wide:
            return hasUltraWide ? (switchOvers.first ?? 2) : 1
        case .tele:
            if hasConstituent(device, .builtInTelephotoCamera), let last = switchOvers.last {
                return last
            }
            return hasUltraWide ? 4 : 2
        }
    }

    static func clampZoom(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        min(max(factor, device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, 40))
    }

    static func lenses(for device: AVCaptureDevice, config: CaptureConfig) -> [LensChoice] {
        guard config.lens != .front, config.fps <= 60 else { return [] }
        var lenses: [LensChoice] = []
        if hasConstituent(device, .builtInUltraWideCamera) { lenses.append(.ultraWide) }
        lenses.append(.wide)
        if hasConstituent(device, .builtInTelephotoCamera) { lenses.append(.tele) }
        return lenses.count > 1 ? lenses : []
    }

    static func label(for lens: LensChoice, device: AVCaptureDevice) -> String {
        if lens == .front { return "Front" }
        return formatZoom(Double(zoomFactor(for: lens, device: device)) * displayMultiplier(device))
    }

    static func formatZoom(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))x" : String(format: "%.1fx", rounded)
    }

    static func resolutionName(_ dimensions: CMVideoDimensions) -> String {
        switch dimensions.width {
        case 3840: return "4K"
        case 1920: return "1080p"
        case 1280: return "720p"
        default: return "\(dimensions.width)×\(dimensions.height)"
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.recordingStarted() }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        var succeeded = true
        if let error = error as NSError? {
            succeeded = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        }
        DispatchQueue.main.async { self.deliver(url: succeeded ? outputFileURL : nil) }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard lapseActive, let input = writerInput, let adaptor else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lapseLast.isValid, CMTimeGetSeconds(CMTimeSubtract(time, lapseLast)) < lapseInterval {
            return
        }
        guard input.isReadyForMoreMediaData, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Each kept frame becomes one frame of a 30 fps video.
        if adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: lapseFrames, timescale: 30)) {
            lapseFrames += 1
            lapseLast = time
        }
    }
}
