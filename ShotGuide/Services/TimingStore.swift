import Foundation

/// Remembers the countdown and stopping choices you make for each shot (separately for in-hand
/// and in-the-shot versions, and for each version of a shot, like TALK's Walking or REVEAL's Tilt up).
/// A shot you've never changed uses its plan's defaults.
enum TimingStore {
    private static func key(_ shot: ShotType, plan: ShotPlan) -> String {
        let base = "timing.\(shot.rawValue).\(plan.isInShot ? "inShot" : "inHand")"
        guard !shot.variants.isEmpty, let version = plan.variantName else { return base }
        return base + "." + version
    }

    static func load(_ shot: ShotType, plan: ShotPlan) -> ShotTiming {
        guard let data = UserDefaults.standard.data(forKey: key(shot, plan: plan)),
              let saved = try? JSONDecoder().decode(ShotTiming.self, from: data) else {
            return plan.defaultTiming
        }
        return saved
    }

    static func save(_ timing: ShotTiming, shot: ShotType, plan: ShotPlan) {
        if let data = try? JSONEncoder().encode(timing) {
            UserDefaults.standard.set(data, forKey: key(shot, plan: plan))
        }
    }
}
