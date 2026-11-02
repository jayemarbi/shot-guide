import Foundation

/// One row on the trip page: a whole shot, or one half of a transition.
struct ShotSlot: Identifiable, Hashable {
    let shot: ShotType
    /// For transitions: 0 is the Out half (ends a place), 1 the In half (starts one). nil is the whole shot.
    let half: Int?

    var id: String { shot.rawValue + (half.map { "-\($0)" } ?? "") }

    var variantName: String? {
        guard let half, shot.variants.indices.contains(half) else { return nil }
        return shot.variants[half]
    }

    var title: String {
        guard let variantName else { return shot.title }
        return "\(shot.title) · \(variantName.uppercased())"
    }

    /// Takes this row needs. A transition half needs one; whole shots follow the day's trip type.
    func target(for type: TripType) -> Int {
        half == nil ? type.target(for: shot) : 1
    }

    func counts(for type: TripType) -> Bool {
        type.counts(shot)
    }

    func summary(for type: TripType) -> String {
        half == nil ? type.summary(for: shot) : summary
    }

    var summary: String {
        switch (shot, half) {
        case (.transition, 0?): return "Cover the lens with your hand to end this place"
        case (.transition, 1?): return "Pull your hand off the lens to start here"
        case (.bodyWipe, 0?): return "Walk across the lens to end this place"
        case (.bodyWipe, 1?): return "Step away from the lens to start here"
        case (.whip, 0?): return "Whip away from the view to end this place"
        case (.whip, 1?): return "Whip in and land on the view to start here"
        case (.jump, 0?): return "Jump up out of frame to end this place"
        case (.jump, 1?): return "The same jump here, so you land in this place"
        case (.home, 0?): return "Packing, a last look out the window, the gate"
        case (.home, 1?): return "In bed at night, lit by your phone, back home"
        default: return shot.summary
        }
    }

    func takeCount(in trip: Trip, day: Int) -> Int {
        let takes = trip.clips.filter { $0.shot == shot.rawValue && $0.dayNumber == day }
        guard let variantName else { return takes.count }
        return takes.filter { $0.variant == variantName }.count
    }
}

/// The trip page in the order you'll film it: getting there, arriving, the first look, you at the spot (easiest
/// first, the ones worth taking your time over last), B-roll of the place to grab all day, creative extras, and leaving.
enum TripPhase: String, CaseIterable, Identifiable {
    case onTheWay
    case arriving
    case firstLook
    case atTheSpot
    case bRoll
    case creative
    case leaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onTheWay: return "On the way"
        case .arriving: return "Arriving"
        case .firstLook: return "First look"
        case .atTheSpot: return "At the spot"
        case .bRoll: return "B-roll"
        case .creative: return "Creative"
        case .leaving: return "Leaving"
        }
    }

    var footer: String {
        switch self {
        case .onTheWay:
            return "Before you go, and the trip there. HOME · BEFORE and HOME · AFTER (under Leaving) start and end a reel."
        case .arriving:
            return "As you get there. The In halves start this place in an edit."
        case .firstLook:
            return "Your first two minutes. Film REACTION before you've seen the view."
        case .atTheSpot:
            return "You in the view, easiest first, down to the ones worth taking your time over. MATCH CUT is the same "
                + "pose at every spot and SILHOUETTE needs the sun low behind you; both need the tripod."
        case .bRoll:
            return "The place without you, to fill out any reel. Grab these whenever you've got a spare minute, all day. "
                + "TIMELAPSE ties up the phone, so save it for when you sit down for a while, like waiting for sunset."
        case .creative:
            return "Extras for creative edits, so they don't count towards the total. CLONE needs the tripod."
        case .leaving:
            return "As you go. The Out halves end this place in an edit, and VOICEOVER is best somewhere quiet, like the car. "
                + "HOME · AFTER is for once you're home. Shots marked extra are for when the day allows, so they don't "
                + "count towards the total."
        }
    }

    var slots: [ShotSlot] {
        switch self {
        case .onTheWay:
            return [ShotSlot(shot: .home, half: 0), ShotSlot(shot: .onTheWay, half: nil)]
        case .arriving:
            return [
                ShotSlot(shot: .transition, half: 1),
                ShotSlot(shot: .whip, half: 1),
                ShotSlot(shot: .bodyWipe, half: 1),
                ShotSlot(shot: .jump, half: 1),
                ShotSlot(shot: .pov, half: nil),
                ShotSlot(shot: .follow, half: nil)
            ]
        case .firstLook:
            return [ShotSlot(shot: .reaction, half: nil), ShotSlot(shot: .reveal, half: nil)]
        case .atTheSpot:
            let shots: [ShotType] = [.wide, .slomo, .talk, .walkaway, .tele, .matchCut, .moment, .silhouette]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .bRoll:
            let shots: [ShotType] = [.bRoll, .detail, .wildlife, .food, .sounds, .ambient, .timelapse]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .creative:
            let shots: [ShotType] = [.reflection, .rise, .orbit, .hyperlapse, .dollyZoom, .dance, .secondAngle, .clone]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .leaving:
            return [
                ShotSlot(shot: .transition, half: 0),
                ShotSlot(shot: .whip, half: 0),
                ShotSlot(shot: .bodyWipe, half: 0),
                ShotSlot(shot: .jump, half: 0),
                ShotSlot(shot: .voiceover, half: nil),
                ShotSlot(shot: .home, half: 1)
            ]
        }
    }

    /// The trip facts row sits at the end of Leaving, when you know how the day went.
    var showsTripFacts: Bool {
        switch self {
        case .leaving: return true
        default: return false
        }
    }

    static var allSlots: [ShotSlot] {
        allCases.flatMap { $0.slots }
    }
}
