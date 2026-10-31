import SwiftUI

/// The countdown and stopping options. Every shot has the same ones.
struct TimingControls: View {
    @Binding var timing: ShotTiming

    static let countdownSteps: [Double] = [0, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600]
    static let lengthSteps: [Double] = [3, 5, 6, 8, 10, 12, 15, 20, 25, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200, 1800, 3600]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepPicker(
                title: "Countdown",
                systemImage: "timer",
                value: Binding(get: { Double(timing.countdown) }, set: { timing.countdown = Int($0) }),
                steps: Self.countdownSteps,
                format: { $0 == 0 ? "Off" : clockString($0) })

            Toggle(isOn: $timing.stopsByItself) {
                Label("Stops by itself", systemImage: "stop.circle")
            }
            .tint(.orange)

            if timing.stopsByItself {
                StepPicker(
                    title: "Length",
                    systemImage: "hourglass",
                    value: $timing.length,
                    steps: Self.lengthSteps,
                    format: { clockString($0) })
            } else {
                Text("Keeps rolling until you press stop, a volume button or your Bluetooth remote.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A one-line summary for the camera screen, like "10 s countdown · stops at 0:30".
    static func summary(_ timing: ShotTiming) -> (countdown: String, ending: String) {
        let countdown = timing.countdown == 0 ? "No countdown" : "\(clockString(Double(timing.countdown))) countdown"
        let ending = timing.stopsByItself ? "Stops at \(clockString(timing.length))" : "You stop it"
        return (countdown, ending)
    }
}

/// Minus and plus buttons that move through a list of sensible values, with the value itself
/// opening the full list to jump straight to one.
struct StepPicker: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let steps: [Double]
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            Button {
                if let lower = steps.last(where: { $0 < value }) {
                    value = lower
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .disabled(steps.first.map { value <= $0 } ?? true)

            Menu {
                ForEach(steps, id: \.self) { option in
                    Button(format(option)) {
                        value = option
                    }
                }
            } label: {
                Text(format(value))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 52)
            }

            Button {
                if let higher = steps.first(where: { $0 > value }) {
                    value = higher
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(steps.last.map { value >= $0 } ?? true)
        }
        .buttonStyle(.borderless)
    }
}
