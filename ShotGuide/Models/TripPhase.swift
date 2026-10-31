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

    var target: Int { half == nil ? shot.targetTakes : 1 }

    var summary: String {
        switch (shot, half) {
        case (.transition, 0?): return "Cover the lens with your hand to end this place"
        case (.transition, 1?): return "Pull your hand off the lens to start here"
        case (.bodyWipe, 0?): return "Walk across the lens to end this place"
        case (.bodyWipe, 1?): return "Step away from the lens to start here"
        case (.whip, 0?): return "Whip away from the view to end this place"
        case (.whip, 1?): return "Whip in and land on the view to start here"
        default: return shot.summary
        }
    }

    func takeCount(in trip: Trip) -> Int {
        let takes = trip.takes(of: shot)
        guard let variantName else { return takes.count }
        return takes.filter { $0.variant == variantName }.count
    }
}

/// The trip page in the order you'll film it: getting there, arriving, the first look, your time at
/// the spot (easiest first, the ones worth taking your time over last), and leaving.
enum TripPhase: String, CaseIterable, Identifiable {
    case onTheWay
    case arriving
    case firstLook
    case atTheSpot
    case leaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onTheWay: return "On the way"
        case .arriving: return "Arriving"
        case .firstLook: return "First look"
        case .atTheSpot: return "At the spot"
        case .leaving: return "Leaving"
        }
    }

    var footer: String {
        switch self {
        case .onTheWay:
            return "The trip there."
        case .arriving:
            return "As you get there. The In halves start this place in an edit."
        case .firstLook:
            return "Your first two minutes. Film REACTION before you've seen the view."
        case .atTheSpot:
            return "Easiest first, down to the ones worth taking your time over. TIMELAPSE ties up the phone, "
                + "so save it for when you sit down for a while, like waiting for sunset."
        case .leaving:
            return "As you go. The Out halves end this place in an edit. "
                + "Shots marked extra are for when the day allows, so they don't count towards the total."
        }
    }

    var slots: [ShotSlot] {
        switch self {
        case .onTheWay:
            return [ShotSlot(shot: .onTheWay, half: nil)]
        case .arriving:
            return [
                ShotSlot(shot: .transition, half: 1),
                ShotSlot(shot: .whip, half: 1),
                ShotSlot(shot: .bodyWipe, half: 1),
                ShotSlot(shot: .pov, half: nil),
                ShotSlot(shot: .follow, half: nil)
            ]
        case .firstLook:
            return [ShotSlot(shot: .reaction, half: nil), ShotSlot(shot: .reveal, half: nil)]
        case .atTheSpot:
            let shots: [ShotType] = [.ambient, .detail, .food, .wide, .slomo, .talk, .walkaway, .tele, .secondAngle, .moment, .timelapse]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .leaving:
            return [
                ShotSlot(shot: .transition, half: 0),
                ShotSlot(shot: .whip, half: 0),
                ShotSlot(shot: .bodyWipe, half: 0)
            ]
        }
    }

    static var allSlots: [ShotSlot] {
        allCases.flatMap { $0.slots }
    }
}
