import AVFoundation
import Foundation

/// Records sound only, for VOICEOVER, and reports the level and which microphone is in use.
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    /// 0 is silence, 1 is loud.
    @Published private(set) var level: Double = 0
    @Published private(set) var micName = ""
    @Published private(set) var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var routeObserver: NSObjectProtocol?

    func prepare() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.permissionDenied = !granted
                if granted {
                    self.activateSession()
                }
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.micName = MicCheck.currentMicName() ?? ""
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? session.setActive(true)
        micName = MicCheck.currentMicName() ?? ""
    }

    func start(to url: URL) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return false }
        self.recorder = recorder
        elapsed = 0
        isRecording = true
        micName = MicCheck.currentMicName() ?? ""
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let decibels = Double(recorder.averagePower(forChannel: 0))
            self.level = min(max((decibels + 50) / 50, 0), 1)
            self.elapsed = recorder.currentTime
        }
        return true
    }

    /// Stops recording and returns how long it ran, in seconds.
    @discardableResult
    func stop() -> Double? {
        guard let recorder, isRecording else { return nil }
        let length = recorder.currentTime
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        isRecording = false
        level = 0
        return length
    }

    func finish() {
        stop()
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        routeObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Which microphone is recording, so you know your wireless mic is working before you talk.
enum MicCheck {
    static func currentMicName() -> String? {
        guard let input = AVAudioSession.sharedInstance().currentRoute.inputs.first else { return nil }
        return input.portType == .builtInMic ? "iPhone mic" : input.portName
    }
}
