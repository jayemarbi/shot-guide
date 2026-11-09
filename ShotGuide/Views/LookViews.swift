import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Picks the look Apple Log footage is shown through: Standard, or a .cube LUT added from Files.
struct LookSheet: View {
    @EnvironmentObject var looks: LookLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(looks.looks) { look in
                        Button {
                            looks.selectedFile = look.fileName
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(look.name)
                                    if look.isAsRecorded {
                                        Text("The flat, grey picture as it's recorded, with the most left for grading")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if look.fileName == nil {
                                        Text("Apple Log made to look like the normal camera")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if looks.selected == look {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.orange)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(Color.primary)
                        .deleteDisabled(look.isBuiltIn)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            looks.delete(looks.looks[index])
                        }
                    }
                } footer: {
                    Text("Clips are always recorded in Apple Log where the phone allows it, which keeps the most for grading. "
                        + "The look only changes what you see while filming and reviewing, and the graded copies you save to "
                        + "Photos (Standard while you've picked no look).")
                }
                Section {
                    Button {
                        importing = true
                    } label: {
                        Label("Add a look from Files", systemImage: "folder")
                    }
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(Color.red)
                    }
                } footer: {
                    Text("A 3D .cube LUT made for Apple Log footage. Looks are kept in On My iPhone › Shot Guide › Looks.")
                }
            }
            .navigationTitle("Look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    try looks.add(from: url)
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
            .onAppear { looks.reload() }
        }
    }
}

/// Plays an Apple Log clip through the look, with play, pause and a scrubber.
struct LogClipPlayer: View {
    let player: AVPlayer
    let orientation: CGImagePropertyOrientation
    let lookName: String
    /// A wide clip, filmed with the phone sideways.
    var wide: Bool = false

    @State private var playing = false
    @State private var position: Double = 0
    @State private var duration: Double = 1
    @State private var scrubbing = false

    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            LookPlayer(player: player, orientation: orientation)
                .aspectRatio(wide ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
                .frame(maxHeight: 400)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    Text("LOG · \(lookName.uppercased())")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                }
                .onTapGesture { toggle() }
            HStack(spacing: 12) {
                Button {
                    toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32)
                }
                Slider(value: $position, in: 0...max(duration, 0.1), onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing {
                        seek(to: position)
                    }
                })
                .onChange(of: position) { _, value in
                    if scrubbing {
                        seek(to: value)
                    }
                }
                Text(clockString(position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(clock) { _ in
            playing = player.rate > 0
            if let length = player.currentItem?.duration.seconds, length.isFinite, length > 0 {
                duration = length
            }
            let now = player.currentTime().seconds
            if !scrubbing, now.isFinite {
                position = min(now, duration)
            }
        }
    }

    private func toggle() {
        if player.rate > 0 {
            player.pause()
        } else {
            if position >= duration - 0.05 {
                seek(to: 0)
            }
            player.play()
        }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
