import SwiftUI
import UIKit

/// Lays chips out in rows, wrapping to the next row when one fills up. A chip wider than a whole row gets a row of
/// its own, at the row's width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Each chip's natural size, or its size at the row's width when it wouldn't fit on a row at all.
    private func sizes(of subviews: Subviews, maxWidth: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let natural = subview.sizeThatFits(.unspecified)
            guard natural.width > maxWidth else { return natural }
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for size in sizes(of: subviews, maxWidth: maxWidth) {
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for (subview, size) in zip(subviews, sizes(of: subviews, maxWidth: bounds.width)) {
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct TagChip: View {
    let text: String
    let isOn: Bool
    let isSuggested: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSuggested {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
                Text(text)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Color.orange : Color.white.opacity(0.1), in: Capsule())
            .foregroundStyle(isOn ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
}

/// Tag chips grouped like the spec, plus a box for adding your own.
struct TagEditor: View {
    @Binding var selected: Set<String>
    var suggested: Set<String>
    @EnvironmentObject var tagLibrary: TagLibrary
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tags")
                .font(.headline)
            if !suggested.isEmpty {
                Label("Spotted in the shot: " + tagLibrary.ordered(suggested).joined(separator: ", "), systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(tagLibrary.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(group.tags, id: \.self) { tag in
                            TagChip(text: tag, isOn: selected.contains(tag), isSuggested: suggested.contains(tag)) {
                                toggle(tag)
                            }
                        }
                    }
                }
            }
            HStack {
                TextField("Add your own tag", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) {
            selected.remove(tag)
        } else {
            selected.insert(tag)
        }
    }

    private func addTag() {
        if let tag = tagLibrary.add(newTag) {
            selected.insert(tag)
        }
        newTag = ""
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

func clockString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}

extension Filming {
    var colour: Color {
        switch self {
        case .landscape: return .orange
        case .portrait: return .cyan
        case .either: return .secondary
        }
    }
}

/// Which way to hold the phone for a shot, and what it goes on, under its name on the trip page:
/// "Landscape · Tripod".
struct FilmingTag: View {
    let filming: Filming
    var mount: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Label(filming.title, systemImage: filming.symbol)
            if let mount {
                Text("· " + mount)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(filming.colour)
    }
}

/// A name box with the names you've used on this trip and its town, one tap to reuse (1.28).
struct NameField: View {
    @Binding var name: String
    let suggestions: [String]
    var placeholder = "Name it, like Bear Lake"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            if suggestions.isEmpty {
                Text("Names you use show up here, one tap to reuse.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        TagChip(text: suggestion, isOn: suggestion == name.trimmingCharacters(in: .whitespaces),
                                isSuggested: false) {
                            name = suggestion
                        }
                    }
                }
            }
        }
    }
}

extension Trip {
    /// Names to offer for a clip (1.28): the ones used on this trip, latest first, then its towns.
    func nameSuggestions(limit: Int = 6) -> [String] {
        var names: [String] = []
        for clip in clips.sorted(by: { $0.recordedAt > $1.recordedAt }) {
            if let name = clip.displayName, !names.contains(name) {
                names.append(name)
            }
            if names.count == limit {
                break
            }
        }
        for day in allDays {
            if let town = town(onDay: day.number), !names.contains(town), names.count < limit + 1 {
                names.append(town)
            }
        }
        return names
    }
}

/// Picks which shot a clip added from Photos is (1.28), from the rows on the lists, part by part.
struct ShotTypeMenu: View {
    let current: ShotRow?
    let choose: (ShotRow?) -> Void

    /// Every row a clip from another camera could be: not WHIP's halves, ONE TAKE or MATCH CUT, which need the camera,
    /// or VOICEOVER, which is sound.
    static func choices(in part: TripPhase) -> [ShotRow] {
        part.allRows.filter { row in
            row.shot != .whip && row.shot != .oneTake && row.shot != .matchCut && row.shot != .voiceover
        }
    }

    var body: some View {
        Menu {
            Button("Not set") { choose(nil) }
            ForEach(TripPhase.allCases) { part in
                let rows = Self.choices(in: part)
                if !rows.isEmpty {
                    Section(part.title) {
                        ForEach(rows) { row in
                            Button(row.title) { choose(row) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current?.title ?? "Not set")
                    .fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
        }
    }
}

extension TripStore {
    /// Gives a clip added from Photos the shot of a row, or takes it off again (1.28).
    func setShot(of row: ShotRow?, clipID: UUID, tripID: UUID) {
        guard let row else {
            setShot(MediaImporter.shotName, role: nil, variant: nil, clipID: clipID, tripID: tripID)
            return
        }
        let variant = row.fixedVariant.flatMap { row.shot.variants.indices.contains($0) ? row.shot.variants[$0] : nil }
        setShot(row.shot.rawValue, role: row.role, variant: variant, clipID: clipID, tripID: tripID)
    }
}
