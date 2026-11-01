import AVFoundation
import SwiftUI
import UIKit

/// Records VOICEOVER: your voice only, for narration. Shows what to talk about, which mic is
/// recording and how loud you are, then plays it back so you can tag or redo it.
struct VoiceoverView: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()

    @State private var take = 1
    @State private var fileURL: URL? = nil
    @State private var startedAt = Date()
    @State private var reviewClip: Clip? = nil
    @State private var message: String? = nil

    private var plan: ShotPlan {
        ShotType.voiceover.plan(take: take, inShot: false, variant: 0)
    }

    private var currentStep: GuideStep? {
        guard recorder.isRecording else { return nil }
        return plan.steps.last { recorder.elapsed >= $0.start }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(plan.before)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Talk about")
                        .font(.headline)
                    ForEach(plan.steps, id: \.self) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(step.rangeLabel)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .frame(width: 72, alignment: .leading)
                            Text(step.text)
                                .fontWeight(currentStep == step ? .bold : .regular)
                        }
                        .opacity(currentStep == nil || currentStep == step ? 1 : 0.45)
                    }
                }

                Spacer()

                VStack(spacing: 14) {
                    Text(clockString(recorder.elapsed))
                        .font(.system(size: 56, weight: .bold).monospacedDigit())
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(recorder.level > 0.9 ? Color.red : Color.orange)
                                .frame(width: geometry.size.width * recorder.level)
                        }
                    }
                    .frame(height: 8)
                    if !recorder.micName.isEmpty {
                        Label("Mic: \(recorder.micName)", systemImage: "mic.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: recordTapped) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            if recorder.isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 64, height: 64)
                            }
                        }
                    }
                    .disabled(recorder.permissionDenied)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("VOICEOVER · take \(take)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if recorder.isRecording {
                            saveTake()
                        }
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            take = store.nextTake(tripID: tripID, shot: .voiceover, day: day)
            recorder.prepare()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            recorder.finish()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: recorder.permissionDenied) { _, denied in
            if denied {
                message = "Microphone access is off for Shot Guide. Turn it on in Settings."
            }
        }
        .sheet(item: $reviewClip, onDismiss: {
            take = store.nextTake(tripID: tripID, shot: .voiceover, day: day)
        }) { clip in
            ReviewView(tripID: tripID, clipID: clip.id, autoplay: true, preselectSuggestions: false, title: "VOICEOVER · take \(clip.take)")
        }
    }

    private func recordTapped() {
        if recorder.isRecording {
            saveTake()
            return
        }
        message = nil
        let now = Date()
        guard let url = store.newClipURL(tripID: tripID, shotName: ShotType.voiceover.rawValue, take: take, date: now,
                                         day: day, fileExtension: "m4a") else {
            message = "Couldn't find this trip's folder."
            return
        }
        if recorder.start(to: url) {
            fileURL = url
            startedAt = now
        } else {
            message = "The recording didn't start. Try again."
        }
    }

    private func saveTake() {
        guard let url = fileURL, let length = recorder.stop() else { return }
        fileURL = nil
        guard length > 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let coordinate = location.location?.coordinate
        let light = SunCalc.light(at: startedAt, latitude: coordinate?.latitude, longitude: coordinate?.longitude)
        let clip = Clip(
            fileName: url.lastPathComponent,
            shot: ShotType.voiceover.rawValue,
            take: take,
            variant: nil,
            recordedAt: startedAt,
            timeZoneID: TimeZone.current.identifier,
            durationSeconds: length,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            light: light.label,
            lens: "Audio",
            fps: 0,
            resolution: "",
            inShot: false,
            tags: [],
            favourite: false,
            notes: "",
            day: day)
        store.addClip(clip, to: tripID)
        reviewClip = clip
    }
}
