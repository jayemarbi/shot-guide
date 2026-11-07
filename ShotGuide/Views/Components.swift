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

/// A small one-line chip for a creative role, or a part of a scene's story: green once it's covered, plain while
/// it's still to film, outlined when it's optional, a swap-in or no longer needed, and with an orange warning when
/// the last take for it didn't count.
///
/// Built from an image and a text rather than a `Label`: inside a list, a `Label` in a `FlowLayout` squeezed its
/// words out and left tall empty pills (1.19).
struct CoverageChip: View {
    enum Look {
        /// Covered by a take you've confirmed.
        case confirmed
        /// Covered by a take that counts for now.
        case covered
        /// A part of a scene's story that one of its clips already fills.
        case done
        /// Not covered yet: the last take for it didn't count.
        case retake
        /// Still to film.
        case toFilm
        /// Optional, like WIDE's vertical hero.
        case optional
        /// A swap-in for a usual role the place can't give.
        case swapIn
        /// Not needed any more: the shot is already covered, or the scene is behind you.
        case spare
    }

    let text: String
    let look: Look

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(look == .retake ? Color.orange : textColour)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(textColour)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fill, in: Capsule())
        .overlay {
            if isOutlined {
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text + ", " + stateWords)
    }

    private var symbol: String? {
        switch look {
        case .confirmed: return "checkmark.circle.fill"
        case .covered: return "checkmark.circle"
        case .done: return "checkmark"
        case .retake: return "exclamationmark.triangle.fill"
        case .optional: return "plus"
        case .swapIn: return "arrow.triangle.swap"
        case .toFilm, .spare: return nil
        }
    }

    private var isCovered: Bool {
        look == .confirmed || look == .covered || look == .done
    }

    private var isOutlined: Bool {
        look == .optional || look == .swapIn || look == .spare
    }

    private var textColour: Color {
        if isCovered {
            return .green
        }
        return isOutlined ? .secondary : Color.primary.opacity(0.85)
    }

    private var fill: Color {
        if isCovered {
            return Color.green.opacity(0.16)
        }
        return isOutlined ? .clear : Color.primary.opacity(0.1)
    }

    private var stateWords: String {
        switch look {
        case .confirmed: return "confirmed usable"
        case .covered: return "counts for now"
        case .done: return "covered"
        case .retake: return "the last take didn't count"
        case .toFilm: return "to film"
        case .optional: return "optional"
        case .swapIn: return "swap-in"
        case .spare: return "not needed"
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
