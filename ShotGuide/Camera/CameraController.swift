import AVFoundation
import UIKit

struct CaptureConfig: Equatable {
    var lens: LensChoice
    var fps: Int
    var stabilisation: Stabilisation
    var timelapseInterval: Double?
    /// Brighter (snow) or darker (silhouettes) than the camera would choose by itself.
    var exposureBias: Float = 0
    /// DANCE: a song plays (in AirPods or on the speaker) while the phone's own mic records.
    var playsMusic: Bool = false
    /// Shots you're in on the tripod: with headphones in, a voice says each step in your ear while the phone's own mic
    /// records (1.24). The sound is set up as for DANCE, keeping stereo and wind reduction.
    var speaksPrompts: Bool = false
    /// The shot zooms from one lens to another while it films (REVEAL's auto zoom), which needs the 3-lens camera (1.25).
    var zoomsAcrossLenses: Bool = false
    /// The phone signals you with the flash during this shot (the shots you're in, on the back camera) (1.25).
    var usesFlash: Bool = false
}

struct RecordingResult {
    let url: URL
    let fps: Int
    let resolution: String
    let lensLabel: String
    let elapsed: Double
    /// Recorded in Apple Log (false: the phone's normal colour, where Log isn't available).
    let log: Bool
    /// A wide clip, filmed with the phone sideways.
    let sideways: Bool
}

/// The white balance a take was locked to: the camera's gains, and the same as a temperature and tint.
struct WhiteBalance: Codable, Hashable {
    var red: Float
    var green: Float
    var blue: Float
    var kelvin: Int
    var tint: Int
    /// The lens it was measured on, as gains only carry over to the same camera.
    var lens: String
}

/// What the camera was set to as a take started, for the catalogue.
struct TakeSettings {
    var whiteBalance: WhiteBalance? = nil
    var iso: Int? = nil
    /// Seconds, like 0.0167 for 1/60.
    var shutter: Double? = nil
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
    /// The lens button to highlight. nil after a pinch, when the zoom sits between lenses.
    @Published private(set) var currentLens: LensChoice? = .wide
    @Published private(set) var hasTorch = false
    /// The zoom on screen right now, like 1 or 2.5.
    @Published private(set) var displayZoom: Double = 1
    /// This shot records in Apple Log.
    @Published private(set) var logActive = false
    /// Why the last take couldn't start recording, in the camera's words. nil when it started.
    @Published private(set) var startProblem: String? = nil
    /// The file is actually recording (it can take a moment after recording is asked for).
    @Published private(set) var rolling = false
    /// The zooms this camera can do, as shown on screen, like 0.5 to 15 (1.24).
    @Published private(set) var zoomLimits: ClosedRange<Double> = 0.5...10
    /// Why this shot isn't filming in Log when it would be, said before you film (1.25). nil when it's in Log, and for
    /// slow motion and time-lapses, which are always the normal colour.
    @Published private(set) var logNote: String? = nil
    /// This shot signals you with the flash, but the camera it needs has none (1.25).
    @Published private(set) var flashNote: String? = nil
    /// The lens of the single camera in use, nil for the 3-lens camera (1.25): white balance only carries over between
    /// takes on the same camera.
    @Published private(set) var deviceLens: LensChoice? = nil
    /// Why a take that had started couldn't be saved (1.25).
    @Published private(set) var saveProblem: String? = nil

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "shotguide.camera.session")
    private let dataQueue = DispatchQueue(label: "shotguide.camera.data")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let dataOutput = AVCaptureVideoDataOutput()
    /// Small frames for drawing the preview through the look.
    private let previewOutput = AVCaptureVideoDataOutput()
    /// Writes Apple Log as 10-bit HEVC, for every shot that films in Log (1.25).
    private let logRecorder = LogRecorder()

    // Session-queue state
    private var device: AVCaptureDevice?
    private var config: CaptureConfig?
    private var exposureBias: Float = 0
    private var pinchStart: CGFloat = 1
    /// Stop was pressed while a take was still waiting for the camera to be able to record.
    private var startCancelled = false
    /// This shot films in Log, through `logRecorder` (1.25).
    private var recordsLog = false
    /// The frame rate the camera is set to.
    private var recordFPS = 30
    /// Golden or blue hour: the white balance stays on daylight, even when the camera's set up again (1.25).
    private var daylightLockOn = false

    // Main-thread state
    private var mainConfig: CaptureConfig?
    private var activeFPS = 30
    private var activeLog = false
    private var activeResolution = ""
    private var activeSideways = false
    private var startTime: CFTimeInterval = 0
    private var ticker: Timer?
    private var finishHandler: ((RecordingResult?) -> Void)?
    /// Called on the main thread the moment the file starts recording, for timing a song to the clip.
    var onRecordingStarted: (() -> Void)?

    // Time-lapse state, used on dataQueue
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var lapseInterval: Double = 1
    private var lapseFrames: Int64 = 0
    private var lapseLast: CMTime = .invalid
    private var lapseActive = false
    private var previewFront = false
    private var previewLog = false
    /// MATCH CUT: looks for you in the preview frames (1.24). Used on dataQueue.
    private var personFinder: PersonFinder?

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

    /// Sets the camera up for a shot. `logRefusal` says why Log has just turned out not to work on this camera, and then
    /// the shot is set up again in the normal colour.
    private func applyConfiguration(_ config: CaptureConfig, logRefusal: String? = nil) {
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

        // With a song playing, or a voice to talk in your ear (1.24), the app sets up the sound itself so it can go to
        // AirPods in full quality while the phone's own mic records. Otherwise the camera sets it up.
        let playsToHeadphones = config.playsMusic || config.speaksPrompts
        session.automaticallyConfiguresApplicationAudioSession = !playsToHeadphones
        if config.playsMusic {
            Self.prepareMusicAudioSession()
        } else if config.speaksPrompts {
            Self.preparePromptAudioSession()
        }

        var hasMic = false
        if !isLapse,
           let microphone = AVCaptureDevice.default(for: .audio),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
            hasMic = true
            // Stereo and wind noise reduction where the phone's own mics support them. A clip-on mic stays as it is.
            // DANCE skips them: the song replaces the clip's sound in the edit anyway.
            if !config.playsMusic && microphoneInput.isMultichannelAudioModeSupported(.stereo) {
                microphoneInput.multichannelAudioMode = .stereo
            }
            if !config.playsMusic && microphoneInput.isWindNoiseRemovalSupported {
                microphoneInput.isWindNoiseRemovalEnabled = true
            }
        }

        // Apple Log wherever this camera has it at the shot's frame rate, as it keeps the most for grading. Since 1.25
        // the app writes it itself, as 10-bit HEVC: the phone's own recorder only offers Log as ProRes, so until then
        // every clip fell back to the normal colour. Slow motion (over 60 fps) and time-lapses stay in the normal colour.
        let wantsLog = !isLapse && config.fps <= 60
        let logFormat = wantsLog && logRefusal == nil ? Self.pickLogFormat(device: device, fps: config.fps) : nil
        var recordsLog = false
        var logProblem: String? = logRefusal
        if isLapse {
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
            }
        } else {
            if logFormat != nil, session.canAddOutput(logRecorder.videoOutput) {
                session.addOutput(logRecorder.videoOutput)
                if hasMic, session.canAddOutput(logRecorder.audioOutput) {
                    session.addOutput(logRecorder.audioOutput)
                }
                recordsLog = true
            } else {
                addMovieOutput()
            }
            // A second, screen-sized feed for the preview, drawn through the look.
            previewOutput.alwaysDiscardsLateVideoFrames = true
            previewOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            previewOutput.automaticallyConfiguresOutputBufferDimensions = false
            previewOutput.deliversPreviewSizedOutputBuffers = true
            previewOutput.setSampleBufferDelegate(self, queue: dataQueue)
            if session.canAddOutput(previewOutput) {
                session.addOutput(previewOutput)
            } else if recordsLog {
                // Seeing the shot comes first: without room for both, it films in the normal colour.
                for output in [logRecorder.videoOutput, logRecorder.audioOutput] as [AVCaptureOutput]
                where session.outputs.contains(output) {
                    session.removeOutput(output)
                }
                recordsLog = false
                logProblem = "the phone can't show the picture while it films Log"
                addMovieOutput()
                if session.canAddOutput(previewOutput) {
                    session.addOutput(previewOutput)
                }
            }
        }

        if let format = (recordsLog ? logFormat : nil) ?? Self.pickFormat(device: device, fps: config.fps) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                if recordsLog {
                    device.activeColorSpace = .appleLog
                } else if format.supportedColorSpaces.contains(.sRGB) {
                    device.activeColorSpace = .sRGB
                }
                device.unlockForConfiguration()
            } catch {}
        }

        let recordOutput: AVCaptureOutput = isLapse ? dataOutput : (recordsLog ? logRecorder.videoOutput : movieOutput)
        if let connection = recordOutput.connection(with: .video) {
            if !isLapse {
                // The phone's recorder turns its clip by the connection's angle, set again as each take starts. Log
                // frames stay as the sensor sees them, wide, and the clip is turned as it's written.
                let angle: CGFloat = recordsLog ? 0 : 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = Self.stabilisationMode(config.stabilisation, format: device.activeFormat)
            }
            if config.lens == .front, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            if !isLapse, !recordsLog, movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
        }
        // The look's frames come already turned upright for the portrait screen, and never mirrored, so how they're
        // drawn doesn't depend on which way the sensor sits. The front camera is mirrored when it's drawn.
        if !isLapse, let previewConnection = previewOutput.connection(with: .video) {
            if previewConnection.isVideoRotationAngleSupported(90) {
                previewConnection.videoRotationAngle = 90
            }
            if previewConnection.isVideoMirroringSupported {
                previewConnection.automaticallyAdjustsVideoMirroring = false
                previewConnection.isVideoMirrored = false
            }
        }
        session.commitConfiguration()

        if recordsLog {
            // Log needs its 10 bits, which can only be asked for now the format's in place. Without them, the shot is
            // set up again in the normal colour.
            if device.activeColorSpace != .appleLog || !logRecorder.chooseTenBit() {
                applyConfiguration(config, logRefusal: "this camera can't give it the 10-bit picture it needs")
                return
            }
        } else if !isLapse {
            chooseHEVC()
        }
        self.recordsLog = recordsLog
        if wantsLog && !recordsLog && logProblem == nil {
            if config.lens == .front {
                logProblem = "the front camera has no Log"
            } else if device.isVirtualDevice {
                logProblem = "the 3-lens camera this shot needs has no Log"
            } else if logFormat == nil {
                logProblem = "this camera has no Log at \(config.fps) fps"
            } else {
                logProblem = "the phone couldn't set up Log recording"
            }
        }
        let logText = logProblem.map { "Not filming in Log: \($0)." }
        let flashText = config.usesFlash && !device.hasTorch
            ? "This camera has no flash, so the signals only come through your AirPods." : nil
        let singleLens = Self.singleLens(device)
        let front = config.lens == .front
        let previewInLog = recordsLog
        dataQueue.async {
            self.previewFront = front
            self.previewLog = previewInLog
        }

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
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            // Golden and blue hour: back on daylight, as setting the camera up again (like changing lens) put it on
            // automatic (1.25).
            if daylightLockOn, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                device.setWhiteBalanceModeLocked(with: Self.clampGains(Self.daylightGains(device), device: device),
                                                 completionHandler: nil)
            }
            let bias = min(max(config.exposureBias, device.minExposureTargetBias), device.maxExposureTargetBias)
            device.setExposureTargetBias(bias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
        exposureBias = config.exposureBias
        recordFPS = isLapse ? 30 : fps
        let startZoom = Double(device.videoZoomFactor) * Self.displayMultiplier(device)

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
        // The lens actually in use: a phone without the shot's lens films it on the main camera.
        let shownLens = singleLens ?? config.lens
        let label = Self.label(for: shownLens, device: device)
        let formatText = "\(Self.resolutionName(dimensions)) · " + (isLapse ? "Time-lapse" : "\(fps) fps")
            + (recordsLog ? " · Log" : " · Normal colour")
        let torch = device.hasTorch
        let multiplier = Self.displayMultiplier(device)
        let lowest = Double(device.minAvailableVideoZoomFactor) * multiplier
        let highest = max(lowest, Double(min(device.maxAvailableVideoZoomFactor, 40)) * multiplier)
        DispatchQueue.main.async {
            self.zoomLimits = lowest...highest
            self.activeFPS = isLapse ? 30 : fps
            self.activeLog = recordsLog
            self.logActive = recordsLog
            self.logNote = logText
            self.flashNote = flashText
            self.deviceLens = singleLens
            self.activeResolution = resolution
            self.availableLenses = lenses
            self.lensTitles = titles
            self.currentLens = shownLens
            self.lensLabel = label
            self.formatLabel = formatText
            self.hasTorch = torch
            self.exposureLocked = false
            self.displayZoom = startZoom
            self.phase = .ready
        }
    }

    /// The phone's own recorder, for the shots in the normal colour. Inside a configuration.
    private func addMovieOutput() {
        guard session.canAddOutput(movieOutput) else { return }
        session.addOutput(movieOutput)
        // Since iOS 26 the recorder can start a moment after the camera, so the picture shows sooner. Here it starts
        // with the camera, so a take can begin the moment the camera is ready.
        if #available(iOS 26.0, *), movieOutput.isDeferredStartSupported {
            movieOutput.isDeferredStartEnabled = false
        }
    }

    /// Sets the phone's recorder to HEVC again now the format's in place: set only inside the configuration, it can be
    /// reset to the format's default. On the session queue.
    private func chooseHEVC() {
        guard let connection = movieOutput.connection(with: .video),
              movieOutput.availableVideoCodecTypes.contains(.hevc) else { return }
        movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
    }

    // MARK: Lenses and zoom

    /// Changes lens. On the 3-lens camera it zooms there. Otherwise each lens is its own camera (1.25), and changing
    /// lens sets the camera up again, which takes a moment.
    func setLens(_ lens: LensChoice) {
        sessionQueue.async {
            guard let device = self.device else { return }
            if let own = Self.singleLens(device), own != lens, own != .front, lens != .front, var config = self.config {
                config.lens = lens
                self.config = config
                DispatchQueue.main.async { self.mainConfig?.lens = lens }
                self.applyConfiguration(config)
                return
            }
            self.jumpZoom(to: lens, device: device)
        }
    }

    /// After a take: undoes any pinch zoom (1.25). A single camera goes back to its own lens, so a lens you picked
    /// stays picked; the 3-lens camera goes back to `lens`, the shot's own.
    func resetZoom(to lens: LensChoice) {
        sessionQueue.async {
            guard let device = self.device else { return }
            self.jumpZoom(to: Self.singleLens(device) ?? lens, device: device)
        }
    }

    /// Jumps to a lens's zoom on the camera in use. On the session queue.
    private func jumpZoom(to lens: LensChoice, device: AVCaptureDevice) {
        let factor = Self.clampZoom(Self.zoomFactor(for: lens, device: device), device: device)
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: factor, withRate: 8)
            device.unlockForConfiguration()
        } catch {}
        let label = Self.label(for: lens, device: device)
        let zoom = Double(factor) * Self.displayMultiplier(device)
        DispatchQueue.main.async {
            self.currentLens = lens
            self.lensLabel = label
            self.displayZoom = zoom
        }
    }

    /// Jumps to an on-screen zoom, like 2.5x. MATCH CUT uses it to start where the last one was.
    func setZoom(display value: Double) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let multiplier = Self.displayMultiplier(device)
            let factor = Self.clampZoom(CGFloat(value / multiplier), device: device)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
            } catch {}
            let zoom = Double(factor) * multiplier
            DispatchQueue.main.async {
                self.lensLabel = Self.formatZoom(zoom)
                self.currentLens = nil
                self.displayZoom = zoom
            }
        }
    }

    /// Zooms smoothly to an on-screen zoom, like 1.4x: MATCH CUT matching your size (1.24).
    func rampZoom(toDisplay value: Double) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let multiplier = Self.displayMultiplier(device)
            let factor = Self.clampZoom(CGFloat(value / multiplier), device: device)
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: factor, withRate: 4)
                device.unlockForConfiguration()
            } catch {}
            let zoom = Double(factor) * multiplier
            DispatchQueue.main.async {
                self.lensLabel = Self.formatZoom(zoom)
                self.currentLens = nil
                self.displayZoom = zoom
            }
        }
    }

    /// Pinch to zoom. `scale` is how far the fingers have spread since the pinch began.
    /// Stops at 20x; past the 5x lens it's digital zoom.
    func pinchZoom(scale: CGFloat, began: Bool) {
        sessionQueue.async {
            guard let device = self.device else { return }
            if began {
                self.pinchStart = device.videoZoomFactor
            }
            let multiplier = Self.displayMultiplier(device)
            let ceiling = CGFloat(20 / multiplier)
            let factor = min(Self.clampZoom(self.pinchStart * scale, device: device), max(ceiling, device.minAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
            } catch {}
            let zoom = Double(factor) * multiplier
            DispatchQueue.main.async {
                self.lensLabel = Self.formatZoom(zoom)
                self.currentLens = nil
                self.displayZoom = zoom
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
            let zoom = Double(to) * multiplier
            DispatchQueue.main.async {
                self.lensLabel = Self.formatZoom(zoom)
                self.displayZoom = zoom
            }
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

    /// Holds focus and exposure where they are, so nothing shifts while you move around the frame (CLONE).
    func lockFocusAndExposure() {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async { self.exposureLocked = true }
        }
    }

    /// Back to following the scene, after a take that locked focus and exposure.
    func resetFocusAndExposure() {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
            DispatchQueue.main.async { self.exposureLocked = false }
        }
    }

    /// A quick blink of the flash, to tell you to move during a take.
    func blinkTorch() {
        setTorch(true)
        sessionQueue.asyncAfter(deadline: .now() + 0.25) {
            self.setTorch(false)
        }
    }

    /// The flash flickering fast for a few seconds: you're done, walk back to the phone (1.24).
    func flickerTorch(seconds: Double = 3) {
        let flashes = Int(seconds / 0.2)
        for index in 0..<flashes {
            sessionQueue.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                self.setTorch(true)
            }
            sessionQueue.asyncAfter(deadline: .now() + Double(index) * 0.2 + 0.1) {
                self.setTorch(false)
            }
        }
    }

    /// Starts or stops looking for you in the preview, for MATCH CUT (1.24).
    func setPersonFinder(_ finder: PersonFinder?) {
        dataQueue.async {
            self.personFinder = finder
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

    // MARK: White balance for a take

    /// Daylight, in kelvin: what golden and blue hour lock to, so warm light stays warm and blue light stays blue.
    static let daylightKelvin: Float = 5600

    /// Locks the white balance for a take, so the colour can't drift partway through: to daylight in golden and blue
    /// hour, to `reuse` (from a take just before, at the same spot, on the same lens), or to what the camera has
    /// settled on. Reports it, with the ISO and shutter speed, for the catalogue.
    /// Since 1.25 most shots film on a single camera, which lets the colour be set; the 3-lens camera only lets it be
    /// held where it is, so its takes can't be matched. `lens` is the shot's, used for the 3-lens camera.
    func beginTake(reuse: WhiteBalance?, daylight: Bool, lens: LensChoice, completion: @escaping (TakeSettings) -> Void) {
        sessionQueue.async {
            guard let device = self.device else {
                DispatchQueue.main.async { completion(TakeSettings()) }
                return
            }
            // Gains only carry over to the same camera.
            let camera = Self.singleLens(device) ?? lens
            var balance: WhiteBalance? = nil
            do {
                try device.lockForConfiguration()
                if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    var gains = device.deviceWhiteBalanceGains
                    if daylight {
                        gains = Self.daylightGains(device)
                    } else if let reuse, reuse.lens == camera.rawValue {
                        gains = AVCaptureDevice.WhiteBalanceGains(redGain: reuse.red, greenGain: reuse.green, blueGain: reuse.blue)
                    }
                    // Only real numbers: just after the camera opens it may not have worked the colour out yet,
                    // and then it stays automatic for the take.
                    if [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({ $0.isFinite && $0 > 0 }) {
                        gains = Self.clampGains(gains, device: device)
                        device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                        balance = Self.whiteBalance(gains, device: device, lens: camera)
                    }
                } else if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                    balance = Self.whiteBalance(Self.clampGains(device.deviceWhiteBalanceGains, device: device), device: device, lens: camera)
                }
                device.unlockForConfiguration()
            } catch {}
            let seconds = CMTimeGetSeconds(device.exposureDuration)
            let iso = device.iso
            let settings = TakeSettings(whiteBalance: balance,
                                        iso: iso.isFinite && iso > 0 ? Int(iso.rounded()) : nil,
                                        shutter: seconds.isFinite && seconds > 0 ? seconds : nil)
            DispatchQueue.main.async { completion(settings) }
        }
    }

    /// In golden and blue hour the white balance stays on daylight between takes too, so the picture on screen has
    /// the colour the takes will have. Otherwise it's automatic.
    func setDaylightLock(_ on: Bool) {
        sessionQueue.async {
            self.daylightLockOn = on
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if on, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    device.setWhiteBalanceModeLocked(with: Self.clampGains(Self.daylightGains(device), device: device),
                                                     completionHandler: nil)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    static func daylightGains(_ device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: daylightKelvin,
                                                                                                tint: 0))
    }

    /// Back to automatic white balance after a take, or to daylight in golden and blue hour.
    func endTake() {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if self.daylightLockOn, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    device.setWhiteBalanceModeLocked(with: Self.clampGains(Self.daylightGains(device), device: device),
                                                     completionHandler: nil)
                } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    static func clampGains(_ gains: AVCaptureDevice.WhiteBalanceGains, device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let top = device.maxWhiteBalanceGain
        func clamp(_ value: Float) -> Float { value.isFinite ? min(max(value, 1), top) : 1 }
        return AVCaptureDevice.WhiteBalanceGains(redGain: clamp(gains.redGain), greenGain: clamp(gains.greenGain), blueGain: clamp(gains.blueGain))
    }

    static func whiteBalance(_ gains: AVCaptureDevice.WhiteBalanceGains, device: AVCaptureDevice, lens: LensChoice) -> WhiteBalance {
        let values = device.temperatureAndTintValues(for: gains)
        func whole(_ value: Float) -> Int { value.isFinite ? Int(value.rounded()) : 0 }
        return WhiteBalance(red: gains.redGain, green: gains.greenGain, blue: gains.blueGain,
                            kelvin: whole(values.temperature), tint: whole(values.tint), lens: lens.rawValue)
    }

    // MARK: Recording

    /// Records the way the phone is held, like the Camera app: turn it sideways and the clip comes out wide and
    /// the right way up. The front camera always records upright.
    func startRecording(to url: URL, hold: PhoneHold, latitude: Double?, longitude: Double?,
                        onFinish: @escaping (RecordingResult?) -> Void) {
        guard phase == .ready else { return }
        finishHandler = onFinish
        elapsed = 0
        phase = .recording
        let interval = mainConfig?.timelapseInterval
        let used: PhoneHold = mainConfig?.lens == .front ? .upright : hold
        activeSideways = used.isSideways
        startProblem = nil
        saveProblem = nil
        rolling = false
        sessionQueue.async {
            self.startCancelled = false
            if let interval {
                self.startLapse(to: url, interval: interval, hold: used, latitude: latitude, longitude: longitude)
            } else if self.recordsLog {
                self.startLog(to: url, hold: used, latitude: latitude, longitude: longitude, triesLeft: 60)
            } else {
                self.startMovie(to: url, hold: used, latitude: latitude, longitude: longitude, triesLeft: 60)
            }
        }
    }

    /// Starts a take in Apple Log (1.25), once the camera's running: the movie begins with its next frame. Like the
    /// phone's recorder, it waits up to about 6 seconds for the camera.
    private func startLog(to url: URL, hold: PhoneHold, latitude: Double?, longitude: Double?, triesLeft: Int) {
        guard !startCancelled else { return }
        guard session.isRunning, session.outputs.contains(logRecorder.videoOutput) else {
            if triesLeft > 0 {
                sessionQueue.asyncAfter(deadline: .now() + 0.1) {
                    self.startLog(to: url, hold: hold, latitude: latitude, longitude: longitude, triesLeft: triesLeft - 1)
                }
            } else {
                DispatchQueue.main.async {
                    self.startProblem = "The camera isn't running."
                    self.deliver(url: nil)
                }
            }
            return
        }
        let sound = session.outputs.contains(logRecorder.audioOutput)
            ? logRecorder.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
            : nil
        let take = LogRecorder.Take(url: url,
                                    transform: CGAffineTransform(rotationAngle: hold.recordingAngle * .pi / 180),
                                    fps: recordFPS,
                                    metadata: Self.locationMetadata(latitude: latitude, longitude: longitude),
                                    audioSettings: sound,
                                    clock: session.synchronizationClock ?? CMClockGetHostTimeClock())
        logRecorder.start(take, onStarted: { [weak self] lag in
            // The take's clock starts when its first frame was filmed, so marks and steps line up with the clip.
            self?.recordingStarted(lag: lag)
        }, onFailed: { [weak self] problem, hadStarted in
            guard let self else { return }
            if hadStarted {
                self.saveProblem = problem
            } else {
                self.startProblem = problem
            }
            self.deliver(url: nil)
        })
    }

    /// Starts the movie once the camera can record, on the session queue. Since iOS 26 the recorder only gets going
    /// a moment after the camera opens, and asking it to record before then raises an exception that would crash the
    /// app. So a refusal is caught and the start tried again every 0.1 seconds. After about 6 seconds it gives up and
    /// the take is reported as not saved, with what the camera said.
    private func startMovie(to url: URL, hold: PhoneHold, latitude: Double?, longitude: Double?, triesLeft: Int) {
        guard !startCancelled else { return }
        var problem: String? = "The camera isn't running."
        let connection = movieOutput.connection(with: .video)
        if session.isRunning, session.outputs.contains(movieOutput), let connection, connection.isEnabled, connection.isActive {
            if connection.isVideoRotationAngleSupported(hold.recordingAngle) {
                connection.videoRotationAngle = hold.recordingAngle
            }
            movieOutput.metadata = Self.locationMetadata(latitude: latitude, longitude: longitude)
            let refused = SGCatchException {
                // HEVC again right before recording, as Apple's own camera sample does, so the codec can't have slipped
                // back to ProRes.
                if self.movieOutput.availableVideoCodecTypes.contains(.hevc) {
                    self.movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
            problem = refused.map { Self.shortReason($0.reason ?? $0.name.rawValue) }
        }
        guard let problem else { return }
        if triesLeft > 0 {
            sessionQueue.asyncAfter(deadline: .now() + 0.1) {
                self.startMovie(to: url, hold: hold, latitude: latitude, longitude: longitude, triesLeft: triesLeft - 1)
            }
        } else {
            DispatchQueue.main.async {
                self.startProblem = problem
                self.deliver(url: nil)
            }
        }
    }

    /// AVFoundation's reasons start with the method's name, like "*** -[AVCaptureMovieFileOutput ...] No active/enabled
    /// connections". This keeps the words after it.
    static func shortReason(_ text: String) -> String {
        guard let range = text.range(of: "] ") else { return text }
        return String(text[range.upperBound...])
    }

    func stopRecording() {
        guard phase == .recording else { return }
        phase = .finishing
        ticker?.invalidate()
        ticker = nil
        let isLapse = mainConfig?.timelapseInterval != nil
        // The moment stop was pressed, by the camera's clock: a Log take keeps the frames filmed before it.
        let pressed = CMClockGetTime(session.synchronizationClock ?? CMClockGetHostTimeClock())
        sessionQueue.async {
            if isLapse {
                self.finishLapse()
            } else if self.recordsLog {
                // A start still waiting for the camera mustn't go ahead.
                self.startCancelled = true
                self.logRecorder.stop(at: pressed) { url, problem in
                    DispatchQueue.main.async {
                        if url == nil, let problem {
                            self.saveProblem = problem
                        }
                        self.deliver(url: url)
                    }
                }
            } else if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                // Stop was pressed before recording had started: don't let a waiting start go ahead, and try again in
                // a moment in case it already has.
                self.startCancelled = true
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

    /// `lag`: how long ago the take's first frame was filmed, so its clock matches the clip.
    private func recordingStarted(lag: Double = 0) {
        rolling = true
        startTime = CACurrentMediaTime() - lag
        onRecordingStarted?()
        elapsed = 0
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = CACurrentMediaTime() - self.startTime
        }
    }

    private func deliver(url: URL?) {
        rolling = false
        ticker?.invalidate()
        ticker = nil
        let result = url.map {
            RecordingResult(url: $0, fps: activeFPS, resolution: activeResolution, lensLabel: lensLabel, elapsed: elapsed,
                            log: activeLog, sideways: activeSideways)
        }
        phase = .ready
        let handler = finishHandler
        finishHandler = nil
        handler?(result)
    }

    /// Plays to AirPods in full quality (not the phone-call mode Bluetooth mics need), or the loudspeaker
    /// without them, and records from the phone's own mic.
    static func prepareMusicAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try? audio.setActive(true)
        if let builtIn = audio.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? audio.setPreferredInput(builtIn)
        }
    }

    /// The shots you're in on the tripod (1.24): the voice plays to AirPods in full quality, or nowhere without them, and
    /// the clip records from a mic you've plugged in, or else the phone's own. AirPods only ever play this way, so their
    /// mic is never the one recording.
    static func preparePromptAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try? audio.setActive(true)
        let inputs = audio.availableInputs ?? []
        let plugged = inputs.first { $0.portType == .usbAudio || $0.portType == .headsetMic }
        if let input = plugged ?? inputs.first(where: { $0.portType == .builtInMic }) {
            try? audio.setPreferredInput(input)
        }
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

    private func startLapse(to url: URL, interval: Double, hold: PhoneHold, latitude: Double?, longitude: Double?) {
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
            // Frames arrive as the camera sees them, wide with the top of the phone to the left. This turns the
            // finished video the way the phone was held.
            input.transform = CGAffineTransform(rotationAngle: hold.recordingAngle * .pi / 180)
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

    /// The camera for a shot (1.25): the single camera for its lens, as that's what films Apple Log and lets the white
    /// balance be set. The 3-lens camera, which zooms smoothly from lens to lens, is only for shots that zoom across
    /// lenses while filming, and for a shot that signals with the flash on a lens with no flash of its own (the ultra
    /// wide), as long as it films Log too.
    static func pickDevice(for config: CaptureConfig) -> AVCaptureDevice? {
        if config.lens == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        let main = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if config.fps > 60 {
            // High frame rates come from the main (1x) camera on its own.
            return main
        }
        let multi = multiLensCamera()
        if config.zoomsAcrossLenses, let multi {
            return multi
        }
        guard let single = singleCamera(for: config.lens) ?? main else { return multi }
        if config.usesFlash, !single.hasTorch, let multi, multi.hasTorch,
           pickLogFormat(device: multi, fps: config.fps) != nil {
            return multi
        }
        return single
    }

    /// The camera that zooms smoothly from lens to lens, where the phone has one.
    static func multiLensCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// The back camera for a lens on its own.
    static func singleCamera(for lens: LensChoice) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide: return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .tele: return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        case .wide: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .front: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    /// Which lens a single camera is. nil for the 3-lens camera.
    static func singleLens(_ device: AVCaptureDevice) -> LensChoice? {
        if device.position == .front { return .front }
        switch device.deviceType {
        case .builtInUltraWideCamera: return .ultraWide
        case .builtInTelephotoCamera: return .tele
        case .builtInWideAngleCamera: return .wide
        default: return nil
        }
    }

    /// The telephoto's zoom as the Camera app shows it, like 5x on the 16 Pro or 3x on the 15 Pro: from where the 3-lens
    /// camera hands over to it.
    static let teleZoom: Double = {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back),
           let last = triple.virtualDeviceSwitchOverVideoZoomFactors.last?.doubleValue, last > 0 {
            // The 3-lens camera counts from the ultra wide, which shows as 0.5x.
            return last * 0.5
        }
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back),
           let first = dual.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue, first > 0 {
            return first
        }
        return 2
    }()

    /// A lens's zoom as shown on screen, for the single cameras.
    static func lensZoom(_ lens: LensChoice) -> Double {
        switch lens {
        case .ultraWide: return 0.5
        case .wide, .front: return 1
        case .tele: return teleZoom
        }
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

    /// The best 16:9 format that records Apple Log at the frame rate: 4K first. nil when there isn't one,
    /// like for some slow-motion rates.
    static func pickLogFormat(device: AVCaptureDevice, fps: Int) -> AVCaptureDevice.Format? {
        let wanted = Double(fps)
        func topRate(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
        }
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let isWidescreen = Int(dimensions.width) * 9 == Int(dimensions.height) * 16
            return format.supportedColorSpaces.contains(.appleLog) && topRate(format) >= wanted - 0.5 && isWidescreen
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
            if CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
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

    /// Turns the camera's zoom factor into what the Camera app shows. A single camera's factor 1 is its own lens, like
    /// 0.5x for the ultra wide; on the 3-lens camera, factor 1 is the ultra wide.
    static func displayMultiplier(_ device: AVCaptureDevice) -> Double {
        if let lens = singleLens(device) {
            return lensZoom(lens)
        }
        return hasConstituent(device, .builtInUltraWideCamera) ? 0.5 : 1.0
    }

    static func zoomFactor(for lens: LensChoice, device: AVCaptureDevice) -> CGFloat {
        // A single camera is at its own lens with no zoom.
        if singleLens(device) != nil {
            return 1
        }
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

    /// The lens buttons. On the 3-lens camera, the lenses it zooms between; otherwise every back camera the phone has,
    /// each its own camera.
    static func lenses(for device: AVCaptureDevice, config: CaptureConfig) -> [LensChoice] {
        guard config.lens != .front, config.fps <= 60 else { return [] }
        var lenses: [LensChoice] = []
        if singleLens(device) == nil {
            if hasConstituent(device, .builtInUltraWideCamera) { lenses.append(.ultraWide) }
            lenses.append(.wide)
            if hasConstituent(device, .builtInTelephotoCamera) { lenses.append(.tele) }
        } else {
            if singleCamera(for: .ultraWide) != nil { lenses.append(.ultraWide) }
            lenses.append(.wide)
            if singleCamera(for: .tele) != nil { lenses.append(.tele) }
        }
        return lenses.count > 1 ? lenses : []
    }

    static func label(for lens: LensChoice, device: AVCaptureDevice) -> String {
        if lens == .front { return "Front" }
        if singleLens(device) != nil {
            return formatZoom(lensZoom(lens))
        }
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
        if let frame = CMSampleBufferGetImageBuffer(sampleBuffer) {
            LookRenderer.shared.renderPreview(frame, orientation: Self.upright(connection, front: previewFront), log: previewLog)
            if output === previewOutput, let finder = personFinder {
                finder.process(frame)
            }
        }
        guard output === dataOutput, lapseActive, let input = writerInput, let adaptor else { return }
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

    /// How to turn a frame from this connection so it shows the right way up on the portrait screen. The preview's
    /// frames already come upright; the time-lapse's come the way the sensor sits. The front camera shows mirrored.
    static func upright(_ connection: AVCaptureConnection, front: Bool) -> CGImagePropertyOrientation {
        if abs(connection.videoRotationAngle - 90) < 1 {
            return front ? .upMirrored : .up
        }
        return front ? .leftMirrored : .right
    }
}
