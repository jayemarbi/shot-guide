import Foundation

/// One row on the trip page: a whole shot, or one half of WHIP or HOME.
struct ShotSlot: Identifiable, Hashable {
    let shot: ShotType
    /// For WHIP: 0 is the Out half (ends a place), 1 the In half (starts one). For HOME: Before and After.
    /// nil is the whole shot.
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

    /// Takes this row needs. A half needs one; whole shots follow the day's trip type.
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
        case (.whip, 0?): return "Whip away from the view to end this place"
        case (.whip, 1?): return "Whip in and land on the view to start here"
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

/// The trip page in the order you'll film it through the day: getting there, walking in, the first look, you at the
/// spot (easiest first, the ones worth taking your time over last, SILHOUETTE at sunset), B-roll of the place to grab
/// all day, and leaving, back to where you're staying.
enum TripPhase: String, CaseIterable, Identifiable {
    case onTheWay
    case arriving
    case firstLook
    case atTheSpot
    case bRoll
    case leaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onTheWay: return "On the way"
        case .arriving: return "Arriving"
        case .firstLook: return "First look"
        case .atTheSpot: return "At the spot"
        case .bRoll: return "B-roll"
        case .leaving: return "Leaving"
        }
    }

    var footer: String {
        switch self {
        case .onTheWay:
            return "Before you go, and the trip there. HOME · BEFORE and HOME · AFTER (under Leaving) start and end a reel."
        case .arriving:
            return "As you walk in, before you've seen the view. WHIP · IN starts this place in an edit, and FOLLOW is "
                + "the last few steps to the view."
        case .firstLook:
            return "Your first two minutes. Film REACTION before you've seen the view. REVEAL can zoom in, walk out from "
                + "behind something or tilt up from the ground."
        case .atTheSpot:
            return "You in the view, easiest first, down to the ones worth taking your time over. TALK can be on the "
                + "tripod or walking, CLONE works best in shade, and SILHOUETTE needs the sun low behind you, so it's last."
        case .bRoll:
            return "The place without you, to fill out any reel. Grab these whenever you've got a spare minute, all day. "
                + "REFLECTION needs still water, often first thing in the morning. TIMELAPSE ties up the phone, so save "
                + "it for when you sit down for a while, like waiting for sunset."
        case .leaving:
            return "As you go. WHIP · OUT ends this place in an edit, and VOICEOVER is best somewhere quiet, like the car. "
                + "STAY is for when you first walk into where you're sleeping, and HOME · AFTER for once you're home. "
                + "Shots marked extra are for when the day allows, so they don't count towards the total."
        }
    }

    var slots: [ShotSlot] {
        switch self {
        case .onTheWay:
            return [ShotSlot(shot: .home, half: 0), ShotSlot(shot: .onTheWay, half: nil)]
        case .arriving:
            return [
                ShotSlot(shot: .whip, half: 1),
                ShotSlot(shot: .pov, half: nil),
                ShotSlot(shot: .hyperlapse, half: nil),
                ShotSlot(shot: .follow, half: nil)
            ]
        case .firstLook:
            return [ShotSlot(shot: .reaction, half: nil), ShotSlot(shot: .reveal, half: nil)]
        case .atTheSpot:
            let shots: [ShotType] = [.wide, .slomo, .talk, .walkaway, .tele, .matchCut, .moment, .orbit, .clone, .dance,
                                     .silhouette]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .bRoll:
            let shots: [ShotType] = [.bRoll, .detail, .reflection, .wildlife, .food, .sounds, .ambient, .timelapse]
            return shots.map { ShotSlot(shot: $0, half: nil) }
        case .leaving:
            return [
                ShotSlot(shot: .whip, half: 0),
                ShotSlot(shot: .voiceover, half: nil),
                ShotSlot(shot: .stay, half: nil),
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
