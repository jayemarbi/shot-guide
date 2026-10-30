import SwiftUI
import UIKit

/// Lays chips out in rows, wrapping to the next row when one fills up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
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
