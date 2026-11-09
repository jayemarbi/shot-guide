import Foundation

/// MATCH CUT's moves (1.24): one move, done the same way once at every place, then cut together in the edit so it
/// looks like one move while the places change around you. The camera zooms to make you the same size as your first
/// take of the move, so you don't have to match your distance from the phone.
enum MatchMove: Int, CaseIterable, Identifiable {
    case runAcross
    case leap
    case armsOut
    case spin
    case fallBack
    case snap
    case ridgeWalk

    var id: Int { rawValue }

    /// Saved with each take as its version, so it never changes.
    var title: String {
        switch self {
        case .runAcross: return "Run across"
        case .leap: return "Leap"
        case .armsOut: return "Arms out"
        case .spin: return "Spin"
        case .fallBack: return "Fall back"
        case .snap: return "Snap"
        case .ridgeWalk: return "Ridge walk"
        }
    }

    /// What you do, in a few words.
    var summary: String {
        switch self {
        case .runAcross: return "Side-on, across the frame from one side to the other"
        case .leap: return "One big jump in the middle of the frame"
        case .armsOut: return "Back to the lens, arms rising out wide to the view"
        case .spin: return "One turn on the spot"
        case .fallBack: return "Falling backwards onto grass, sand or snow"
        case .snap: return "Close up, upright: snap your fingers"
        case .ridgeWalk: return "Tiny on the 5x, walking along a ridge or shoreline"
        }
    }

    /// Where the edit cuts from one place to the next.
    var cut: String {
        switch self {
        case .runAcross: return "The edit cuts mid-stride, so one run carries on through every place."
        case .leap: return "The edit cuts at the top of the jump."
        case .armsOut: return "The edit cuts as your arms open."
        case .spin: return "The edit cuts when your back's to the lens."
        case .fallBack: return "The edit cuts mid-fall, so you land somewhere else."
        case .snap: return "The edit cuts on the snap."
        case .ridgeWalk: return "The edit changes the sky behind you every few steps."
        }
    }

    /// The moves filmed the way ONE TAKE films (tripod at hip height, 0.5x, 60 fps), so a move in a ONE TAKE matches
    /// the same move filmed on its own. Snap and Ridge walk need their own set-up.
    var fitsOneTake: Bool {
        self != .snap && self != .ridgeWalk
    }

    /// Snap is close up, so it sizes you by your head and shoulders rather than all of you.
    var measuresUpperBody: Bool {
        self == .snap
    }

    static func named(_ title: String?) -> MatchMove? {
        allCases.first { $0.title == title }
    }

    /// How many places you've filmed this move at, across every trip: each place on each day counts once.
    func places(in trips: [Trip]) -> Int {
        var seen = Set<String>()
        for trip in trips {
            for take in trip.allTakes where take.shot == ShotType.matchCut.rawValue && take.variant == title
                && take.countsAsCoverage {
                seen.insert("\(trip.id.uuidString)-\(take.dayNumber)-\(take.scene.map { String($0) } ?? "day")")
            }
        }
        return seen.count
    }
}

/// What MATCH CUT remembers between takes and trips (1.24): how big you are in the frame for each move, set by your
/// first take of it, and the move you used last.
enum MatchCutStore {
    private static func sizeKey(_ move: MatchMove) -> String {
        "matchCut.size." + move.title
    }

    /// How tall you were in the frame, as a share of its height (0 to 1). nil until your first take of the move.
    static func size(for move: MatchMove) -> Double? {
        let value = UserDefaults.standard.double(forKey: sizeKey(move))
        return value > 0 ? value : nil
    }

    static func setSize(_ size: Double?, for move: MatchMove) {
        if let size, size > 0 {
            UserDefaults.standard.set(size, forKey: sizeKey(move))
        } else {
            UserDefaults.standard.removeObject(forKey: sizeKey(move))
        }
    }

    /// The move picked last, so the next MATCH CUT starts on it and you keep repeating it.
    static var lastMove: MatchMove {
        get { MatchMove(rawValue: UserDefaults.standard.integer(forKey: "matchCut.lastMove")) ?? .runAcross }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "matchCut.lastMove") }
    }
}
