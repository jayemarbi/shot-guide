import SwiftUI

/// A script as lines to read (1.28): TALK at home and VOICEOVER scroll through it at about the pace you read aloud.
struct Teleprompter {
    let lines: [String]

    /// Words a second at speed 1: most people read aloud at about two and a half.
    static let wordsPerSecond = 2.6
    /// A breath between lines.
    static let pause = 0.5
    /// The speeds the − and + buttons step through.
    static let slowest = 0.6
    static let fastest = 1.6

    init(script: String) {
        lines = Self.split(script)
    }

    /// The script's sentences, a line each. Its own line breaks always start a new one.
    static func split(_ script: String) -> [String] {
        var result: [String] = []
        for paragraph in script.components(separatedBy: .newlines) {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var found: [String] = []
            trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) { sentence, _, _, _ in
                let line = (sentence ?? "").trimmingCharacters(in: .whitespaces)
                if !line.isEmpty {
                    found.append(line)
                }
            }
            result += found.isEmpty ? [trimmed] : found
        }
        return result
    }

    /// How long a line takes to say at speed 1, with a breath after it.
    static func seconds(for line: String) -> Double {
        let words = line.split(whereSeparator: { $0.isWhitespace }).count
        return max(1.2, Double(words) / wordsPerSecond) + pause
    }

    /// The line to read once `read` seconds of the script have gone by at speed 1. `lines.count` once it's all read.
    func index(at read: Double) -> Int {
        guard read > 0 else { return 0 }
        var clock = 0.0
        for (index, line) in lines.enumerated() {
            clock += Self.seconds(for: line)
            if read < clock {
                return index
            }
        }
        return lines.count
    }

    /// Roughly how long the whole script takes at a speed, in seconds.
    func length(speed: Double) -> Double {
        lines.reduce(0) { $0 + Self.seconds(for: $1) } / max(speed, 0.1)
    }
}

/// The lines to read, under the lens while TALK at home records (1.28): the one to say now, big, the next ones
/// smaller. − and + change the pace, even while it's rolling; the speed is remembered.
struct TeleprompterPanel: View {
    let script: String?
    /// Seconds since recording started, or nil when it isn't recording.
    let elapsed: Double?
    /// When reading starts, in seconds after recording does: after the take's "get ready" step.
    var startsAt: Double = 2
    var onEdit: () -> Void

    @AppStorage("teleprompter.speed") private var speed = 1.0
    /// How much of the script has gone by, at speed 1. It moves on by each tick times the speed, so changing the speed
    /// mid-take doesn't jump.
    @State private var read = 0.0
    @State private var lastElapsed: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let script {
                let prompter = Teleprompter(script: script)
                let current = elapsed == nil ? 0 : prompter.index(at: read)
                lines(prompter.lines, current: current)
                if elapsed != nil && current >= prompter.lines.count {
                    Text("That's the script. Stop whenever you're ready.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                controls(prompter)
            } else {
                Text("No script yet")
                    .font(.headline)
                Text("Paste in the one written from your place facts, and it scrolls here while you talk.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
                Button("Add your script", action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .tint(.orange)
            }
        }
        .foregroundStyle(Color.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: elapsed) { _, value in
            advance(to: value)
        }
    }

    /// The line before, the one to say now and the two after it.
    private func lines(_ all: [String], current: Int) -> some View {
        let first = max(0, current - 1)
        let last = min(all.count, current + 3)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(first..<max(first, last), id: \.self) { index in
                Text(all[index])
                    .font(index == current ? .system(size: 26, weight: .semibold) : .system(size: 19))
                    .foregroundStyle(index == current ? Color.white : Color.white.opacity(index < current ? 0.3 : 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
    }

    private func controls(_ prompter: Teleprompter) -> some View {
        HStack(spacing: 10) {
            Button {
                speed = max(Teleprompter.slowest, ((speed - 0.1) * 10).rounded() / 10)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 34, height: 30)
            }
            .disabled(speed <= Teleprompter.slowest + 0.01)
            Text("Speed \(String(format: "%.1f", speed))×")
                .font(.caption.weight(.semibold).monospacedDigit())
            Button {
                speed = min(Teleprompter.fastest, ((speed + 0.1) * 10).rounded() / 10)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 34, height: 30)
            }
            .disabled(speed >= Teleprompter.fastest - 0.01)
            Spacer(minLength: 8)
            if elapsed == nil {
                Text("About \(clockString(prompter.length(speed: speed)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("New script", action: onEdit)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }

    private func advance(to value: Double?) {
        guard let value else {
            read = 0
            lastElapsed = nil
            return
        }
        let previous = lastElapsed ?? 0
        lastElapsed = value
        // Reading starts after the get-ready step.
        let from = max(previous, startsAt)
        if value > from {
            read += (value - from) * speed
        }
    }
}

/// The script for TALK at home or VOICEOVER (1.28): paste it in, change it, or start one from the place facts.
struct ScriptSheet: View {
    let tripID: UUID
    let shot: ShotType

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false

    private var trip: Trip? { store.trip(id: tripID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                } footer: {
                    Text("Paste in the script written from your place facts, or write your own. Each sentence is a line on "
                        + "the teleprompter.")
                }
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        DispatchQueue.main.async { text = pasted }
                    }
                    .tint(.orange)
                    if let draft = trip?.draftScript() {
                        Button {
                            text = draft
                        } label: {
                            Label("Start from your place facts", systemImage: "list.bullet.clipboard")
                        }
                    }
                    if !text.isEmpty {
                        Button(role: .destructive) {
                            text = ""
                        } label: {
                            Label("Clear it", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(shot == .voiceover ? "VOICEOVER script" : "TALK script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setScript(text, for: shot, tripID: tripID)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                text = trip?.script(for: shot) ?? ""
            }
        }
    }
}

extension Trip {
    /// A first go at a script from the place facts (1.28), to change as you like. nil until there are facts.
    func draftScript() -> String? {
        guard let facts = allDays.compactMap({ dayFacts($0.number) }).first(where: { !$0.isEmpty }) else { return nil }
        func clean(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        var lines = ["This is \(place)."]
        let distance = clean(facts.distance)
        let time = clean(facts.time)
        if !distance.isEmpty && !time.isEmpty {
            lines.append("It's \(distance), and it took us \(time).")
        } else if !distance.isEmpty {
            lines.append("It's \(distance).")
        } else if !time.isEmpty {
            lines.append("It took us \(time).")
        }
        let best = clean(facts.bestBit)
        if !best.isEmpty {
            lines.append("The best bit: \(best).")
        }
        if !facts.costs.isEmpty {
            let total = Trip.total(facts.costs)
            let each = people > 1 ? total / Double(people) : total
            lines.append("It cost us \(Money.format(each, currency: currency))\(people > 1 ? " each" : "").")
        }
        let tips = clean(facts.tips)
        if !tips.isEmpty {
            lines.append(tips + ".")
        }
        if let rating = facts.rating {
            lines.append("I'd give it \(TripFacts.score(rating)) out of 10.")
        }
        let region = state.isEmpty ? country : state
        if !region.isEmpty {
            lines.append("Save this for your \(region) trip.")
        }
        return lines.joined(separator: "\n")
    }
}
