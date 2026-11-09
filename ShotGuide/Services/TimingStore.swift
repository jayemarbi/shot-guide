import Foundation

/// Remembers the countdown and stopping choices you make for each shot (separately for in-hand
/// and in-the-shot versions, and for each version of a shot, like TALK's Walking or REVEAL's Tilt up).
/// Since 1.19 each creative role keeps its own too, like WIDE's Establishing and Me in the view.
/// A shot you've never changed uses its plan's defaults.
enum TimingStore {
    /// Shots that became something else, so a length set for the old one doesn't carry over: CLONE is a long take since
    /// 1.24, not 25 seconds.
    private static let renewed: [ShotType: String] = [.clone: ".1.24"]

    /// The key used before roles: per shot, mode and version.
    private static func shotKey(_ shot: ShotType, plan: ShotPlan) -> String {
        let base = "timing.\(shot.rawValue).\(plan.isInShot ? "inShot" : "inHand")" + (renewed[shot] ?? "")
        guard !shot.variants.isEmpty, let version = plan.variantName else { return base }
        return base + "." + version
    }

    /// Per role, for shots with roles. REVEAL's roles are its versions, which are already in the key.
    private static func key(_ shot: ShotType, plan: ShotPlan) -> String {
        let base = shotKey(shot, plan: plan)
        guard shot.variants.isEmpty, let role = plan.role else { return base }
        return base + ".role." + role.id
    }

    /// A role you've never changed starts from what you set for the whole shot before 1.19, if you set anything,
    /// so your own lengths and countdowns carry over. Changing a role then saves it for that role alone.
    static func load(_ shot: ShotType, plan: ShotPlan) -> ShotTiming {
        for candidate in [key(shot, plan: plan), shotKey(shot, plan: plan)] {
            if let data = UserDefaults.standard.data(forKey: candidate),
               let saved = try? JSONDecoder().decode(ShotTiming.self, from: data) {
                return saved
            }
        }
        return plan.defaultTiming
    }

    static func save(_ timing: ShotTiming, shot: ShotType, plan: ShotPlan) {
        if let data = try? JSONEncoder().encode(timing) {
            UserDefaults.standard.set(data, forKey: key(shot, plan: plan))
        }
    }
}
