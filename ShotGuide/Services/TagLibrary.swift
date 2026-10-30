import Foundation

/// The starter tags plus any you add yourself, so every tag is spelled the same way every time.
final class TagLibrary: ObservableObject {
    @Published private(set) var custom: [String] = []

    private let storageKey = "customTags"

    init() {
        custom = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    var groups: [TagGroup] {
        custom.isEmpty ? TagVocabulary.groups : TagVocabulary.groups + [TagGroup(name: "Your tags", tags: custom)]
    }

    func normalise(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
    }

    /// Adds a tag to the list if it's new, and returns it in its normal spelling.
    func add(_ raw: String) -> String? {
        let tag = normalise(raw)
        guard !tag.isEmpty else { return nil }
        if !TagVocabulary.allStarterTags.contains(tag) && !custom.contains(tag) {
            custom.append(tag)
            UserDefaults.standard.set(custom, forKey: storageKey)
        }
        return tag
    }

    /// Tags in list order (starter tags first, then yours, then anything else).
    func ordered(_ tags: Set<String>) -> [String] {
        let order = TagVocabulary.allStarterTags + custom
        let known = order.filter { tags.contains($0) }
        let others = tags.subtracting(order).sorted()
        return known + others
    }
}
