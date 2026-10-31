import Foundation

/// Remembers the countdown and stopping choices you make for each shot (separately for in-hand
/// and in-the-shot versions). A shot you've never changed uses its plan's defaults.
enum TimingStore {
    private static func key(_ shot: ShotType, inShot: Bool) -> String {
        "timing.\(shot.rawValue).\(inShot ? "inShot" : "inHand")"
    }

    static func load(_ shot: ShotType, plan: ShotPlan) -> ShotTiming {
        guard let data = UserDefaults.standard.data(forKey: key(shot, inShot: plan.isInShot)),
              let saved = try? JSONDecoder().decode(ShotTiming.self, from: data) else {
            return plan.defaultTiming
        }
        return saved
    }

    static func save(_ timing: ShotTiming, shot: ShotType, inShot: Bool) {
        if let data = try? JSONEncoder().encode(timing) {
            UserDefaults.standard.set(data, forKey: key(shot, inShot: inShot))
        }
    }
}
