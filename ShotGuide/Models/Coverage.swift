import Foundation

// Creative coverage (1.19): what a day's footage can make, not just how many takes it has.
//
// Shots that need several takes give each take a creative role, like WIDE's establishing view or B-ROLL's
// movement. One take fills one role, and repeats of a role are extras, so the counters reward variety.
//
// Since 1.28 every take you keep counts: deleting one is how you say no, and there's nothing to confirm. Rows you swipe
// away for the day ("Not today", when the place doesn't have them) stop counting until they're filmed or put back.

/// How much a shot matters on a day.
enum ShotTier: String, Codable {
    /// Part of the everyday coverage.
    case core
    /// Worth adding on a content-rich day.
    case fullDay
    /// Optional. Welcome at any time, but it never counts towards a day.
    case extra

    /// After a shot's summary on the trip page. Core shots don't need one.
    var label: String? {
        switch self {
        case .core: return nil
        case .fullDay: return "full day"
        case .extra: return "extra"
        }
    }
}

/// One creative purpose a shot is filmed for, like WIDE's establishing view. The id is saved with each take and
/// goes in the catalogue, so it never changes; the title and purpose can be reworded.
struct CoverageRole: Hashable, Identifiable {
    let id: String
    let title: String
    let purpose: String
    /// Whether you're in the shot for this role. nil goes by the shot's usual way.
    var inShot: Bool? = nil
    /// Not part of the shot's target, like WIDE's vertical hero.
    var isOptional: Bool = false
    /// A swap-in, for when a place doesn't have what one of the usual roles needs, like B-ROLL's people at a
    /// remote lookout. It counts like any other role.
    var isSubstitute: Bool = false
}

extension ShotType {
    /// The creative roles of a shot, the usual ones first, then swap-ins. Empty for shots that just need takes. Since
    /// 1.28 each is a row of its own on the lists, so the camera films exactly the one you tapped.
    var roles: [CoverageRole] {
        switch self {
        case .wide:
            return [
                CoverageRole(id: "establishing", title: "Establishing",
                             purpose: "A clean, cinematic view that shows the place, its scale and atmosphere, with no one in it.",
                             inShot: false),
                CoverageRole(id: "human-scale", title: "Me in the view",
                             purpose: "You, or the two of you, small in the big view: walking, standing, looking out or doing "
                                + "something natural.",
                             inShot: true),
                CoverageRole(id: "alternative", title: "Another angle",
                             purpose: "A clearly different shot of the place: a new viewpoint, height, side or lens, or a scene "
                                + "that's changing.",
                             inShot: false),
                CoverageRole(id: "vertical-hero", title: "Vertical hero",
                             purpose: "An upright, full-screen version of the best view, for reels that play full screen.",
                             inShot: false, isOptional: true)
            ]
        case .bRoll:
            return [
                CoverageRole(id: "atmosphere", title: "Atmosphere",
                             purpose: "Light, weather and mood: mist, clouds, sun through the trees, rain on water.", inShot: false),
                CoverageRole(id: "people", title: "People",
                             purpose: "Someone doing something: walkers, a guide, a market, people at the lookout. Small or from "
                                + "behind is fine.", inShot: false),
                CoverageRole(id: "movement", title: "Movement",
                             purpose: "Something moving through the frame: traffic, flags, waves, birds, a train.", inShot: false),
                CoverageRole(id: "local", title: "Local character",
                             purpose: "What makes this place this place: signs, landmarks, buildings, local things.", inShot: false),
                CoverageRole(id: "lens-angle", title: "New lens or angle",
                             purpose: "A contrasting look: the 5x on something far away, or very low, very high or through "
                                + "something.", inShot: false),
                CoverageRole(id: "transition", title: "Transition",
                             purpose: "A shot that moves the edit on: walking past something close to the lens, a door, a pan "
                                + "away, a passing car.", inShot: false),
                CoverageRole(id: "nature", title: "Nature",
                             purpose: "Swap in when the place is missing one of the others: plants, animals or water, something "
                                + "alive in the scene.", inShot: false, isSubstitute: true),
                CoverageRole(id: "into-light", title: "Into the light",
                             purpose: "Swap in when the place is missing one of the others: face the sun for flare, glowing "
                                + "edges or silhouettes.", inShot: false, isSubstitute: true)
            ]
        case .detail:
            return [
                CoverageRole(id: "texture", title: "Texture",
                             purpose: "Rock, bark, sand, ice, the surface of the water.", inShot: false),
                CoverageRole(id: "object", title: "Object",
                             purpose: "A sign, a map, a ticket, your gear, a cup of coffee.", inShot: false),
                CoverageRole(id: "hands", title: "Hands",
                             purpose: "Your hand touching something: rock, water, a rail, a leaf.", inShot: false),
                CoverageRole(id: "foreground", title: "Foreground",
                             purpose: "Something close and sharp with the view soft behind it: flowers, a fence, leaves.",
                             inShot: false),
                CoverageRole(id: "only-here", title: "Only here",
                             purpose: "A small detail you'd only find here.", inShot: false),
                CoverageRole(id: "nature", title: "Nature",
                             purpose: "Swap in when the place is missing one of the others: a leaf, a flower, drops of water, "
                                + "an insect.", inShot: false, isSubstitute: true)
            ]
        case .pov:
            return [
                CoverageRole(id: "approach", title: "Approach",
                             purpose: "Heading towards something: the track ahead, the path to the view, the walk up to the door.",
                             inShot: false),
                CoverageRole(id: "through", title: "Moving through",
                             purpose: "Being in the place: through the forest, the market or along the water, looking around "
                                + "as you go.", inShot: false)
            ]
        case .reveal:
            // The same order as `variants`: a role is a version.
            return [
                CoverageRole(id: "auto-zoom", title: "Auto zoom",
                             purpose: "From wide to the focal point, with the app doing the zoom.", inShot: false),
                CoverageRole(id: "walk-reveal", title: "Walk reveal",
                             purpose: "Walk or rise from behind something until the view opens up.", inShot: false),
                CoverageRole(id: "tilt-up", title: "Tilt up",
                             purpose: "From the water or the ground up to the view.", inShot: false)
            ]
        case .walkaway:
            return [
                CoverageRole(id: "into-view", title: "Into the view",
                             purpose: "Walking away from the lens into the view until you're small against it.", inShot: true),
                CoverageRole(id: "new-spot", title: "New spot or action",
                             purpose: "A second walk somewhere different, or with a new action: look back over your shoulder, "
                                + "take your partner's hand, stop at the edge.", inShot: true)
            ]
        case .moment:
            return [
                CoverageRole(id: "with-place", title: "With the place",
                             purpose: "Enjoying the place itself: touching the water, lying in the grass, taking in the view, "
                                + "exploring.", inShot: true),
                CoverageRole(id: "together", title: "Together",
                             purpose: "A real moment with your partner: laughing, a kiss, walking hand in hand, a spin. On your "
                                + "own, a real reaction.", inShot: true)
            ]
        case .onTheWay:
            // 1.28: four kinds of journey shot, so you can pick exactly the one you're getting.
            return [
                CoverageRole(id: "getting-going", title: "Getting going",
                             purpose: "The start of the trip: bags going in, the airport, boarding, the first coffee.",
                             inShot: false),
                CoverageRole(id: "window", title: "Window",
                             purpose: "The world sliding past the glass of a plane, a train, a bus or the car.", inShot: false),
                CoverageRole(id: "road-ahead", title: "Road ahead",
                             purpose: "Where you're heading: the road through the windscreen, the track, the water over the bow.",
                             inShot: false),
                CoverageRole(id: "pulling-in", title: "Pulling in",
                             purpose: "Arriving: the welcome sign, the car park, the trailhead, the first sight of the place.",
                             inShot: false)
            ]
        case .slomo:
            // 1.28: water in your hand, or you on the tripod. You in it counts on the days that ask for two.
            return [
                CoverageRole(id: "water", title: "Water and motion",
                             purpose: "Water, waves, spray or snow, slowed right down.", inShot: false),
                CoverageRole(id: "you", title: "You in it",
                             purpose: "A jump, a splash or a hair flick, slowed right down.", inShot: true, isOptional: true)
            ]
        default:
            return []
        }
    }

    /// The roles on a day of a type: the same roles, with any optional one the type counts made a usual one, like
    /// WIDE's vertical hero at waterfalls (1.26).
    func roles(for type: TripType) -> [CoverageRole] {
        let counted = type.countsOptionalRoles(of: self)
        guard !counted.isEmpty else { return roles }
        return roles.map { role in
            var role = role
            if counted.contains(role.id) {
                role.isOptional = false
            }
            return role
        }
    }

    /// REVEAL's roles are its versions.
    var rolesAreVariants: Bool { self == .reveal }

    func role(withID id: String) -> CoverageRole? {
        roles.first { $0.id == id }
    }

    /// How much this shot matters on a day, before trip types change it. The creative shots and the ones filmed at
    /// home never count, whatever this says (see `TripType.tier`).
    var tier: ShotTier {
        switch self {
        case .wide, .bRoll, .detail, .pov, .reveal, .walkaway, .moment, .ambient:
            return .core
        case .reaction, .tele, .slomo:
            return .fullDay
        default:
            return .extra
        }
    }

    /// The takes a light day asks for, from the core shots: any roles.
    var lightDayTakes: Int {
        switch self {
        case .bRoll: return 3
        case .wide, .detail: return 2
        case .pov, .reveal, .moment: return 1
        default: return 0
        }
    }

    /// The roles to suggest next after `current`: the usual roles after it, then the ones before it, then swap-ins.
    /// Only roles still `open` are suggested. The day's type can make an optional role a usual one (1.26).
    func nextRole(after current: String?, open: Set<String>, type: TripType) -> CoverageRole? {
        let roles = self.roles(for: type)
        let usual = roles.filter { !$0.isOptional && !$0.isSubstitute }
        let start = current.flatMap { id in usual.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        let rotated = Array(usual[min(start, usual.count)...]) + Array(usual[..<min(start, usual.count)])
        if let next = rotated.first(where: { open.contains($0.id) }) {
            return next
        }
        return roles.first { $0.isSubstitute && open.contains($0.id) }
    }
}

// MARK: Which takes count

extension Clip {
    /// The role this take was filmed for. Takes from before 1.19 get one only where the old version shows it:
    /// REVEAL's versions, and WIDE and WALKAWAY, which changed with the take number. SLOMO's takes from before 1.28 go
    /// by whether you were in them.
    var roleID: String? {
        guard let type = shotType else { return nil }
        let ids = type.roles.map { $0.id }
        if let role {
            return ids.contains(role) ? role : nil
        }
        guard !isAdded else { return nil }
        switch type {
        case .reveal:
            guard let variant, let index = type.variants.firstIndex(of: variant), index < ids.count else { return nil }
            return ids[index]
        case .walkaway:
            return take % 2 == 0 ? "new-spot" : "into-view"
        case .wide:
            if inShot {
                return "human-scale"
            }
            return take % 2 == 0 ? "alternative" : "establishing"
        case .slomo:
            return inShot ? "you" : "water"
        default:
            return nil
        }
    }

    /// Stopped well before its planned length (under 60% of it), or under 3 seconds for a take you stopped yourself.
    /// Since 1.28 it's only a hint after the take: a take you keep counts.
    var stoppedShort: Bool {
        guard !isAdded, !isPhoto else { return false }
        if let plannedLength, plannedLength > 0 {
            return durationSeconds < plannedLength * 0.6
        }
        return durationSeconds < 3
    }

    /// Passed the take check, or the shot has none, and wasn't stopped short.
    var technicallyAcceptable: Bool {
        checkPassed != false && !stoppedShort
    }

    /// Whether this take counts (1.28): every take you keep. Deleting one is how you say no. A take marked not usable
    /// before 1.28 still doesn't.
    var countsAsCoverage: Bool {
        usable != false
    }
}

/// What a take does for coverage, for the catalogue.
enum CoverageStatus: String {
    /// Fills part of its row's target.
    case counts
    /// Kept, but its role (or the shot) already had a take. Welcome all the same.
    case extra
    /// Marked not usable, before 1.28.
    case rejected
}

/// How far one shot (or WHIP's or HOME's half) has got on a day.
struct SlotCoverage {
    struct RoleLine: Identifiable {
        let role: CoverageRole
        /// Takes filmed for this role that count.
        let usable: Int
        /// Whether one of its takes fills the target.
        let fillsTarget: Bool
        /// Swiped away for today and not filmed, so it doesn't count (1.28).
        let notToday: Bool

        var id: String { role.id }
        var covered: Bool { usable > 0 }
    }

    /// What it needs today, once rows swiped away are left out.
    let target: Int
    /// Takes that fill the target, never more than it.
    let done: Int
    /// Every role, optional ones and swap-ins included. Empty for shots without roles.
    let roles: [RoleLine]
    /// Takes without a role (older takes and imports) that fill the target.
    let unsorted: Int
    let statuses: [UUID: CoverageStatus]
    /// A shot without roles, or a half, swiped away for today and not filmed (1.28).
    let notToday: Bool
    /// Takes filmed today, whether they count or not.
    let filmed: Int

    var complete: Bool { done >= target }

    /// Takes beyond the target.
    var extras: Int {
        statuses.values.filter { $0 == .extra }.count
    }

    /// Roles that would add to the target: not covered yet, not optional, not swiped away.
    var openRoleIDs: Set<String> {
        guard !complete else { return [] }
        return Set(roles.filter { !$0.role.isOptional && !$0.covered && !$0.notToday }.map { $0.role.id })
    }

    /// Optional roles not filmed yet, like WIDE's vertical hero.
    var openOptionalRoles: [CoverageRole] {
        roles.filter { $0.role.isOptional && !$0.covered }.map { $0.role }
    }

    func line(for roleID: String) -> RoleLine? {
        roles.first { $0.role.id == roleID }
    }
}

/// Light, everyday and full coverage of a day. They build on each other: the same takes count towards all three,
/// and you can stop whenever you're happy with what you've got.
enum CoverageLevel: Int, CaseIterable, Identifiable {
    case light
    case everyday
    case full

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .light: return "Light day"
        case .everyday: return "Everyday"
        case .full: return "Full day"
        }
    }
}

extension ShotSlot {
    /// How many roles or takes this row needs for a level of coverage on a day of a type, from what it needs today
    /// (`target`, once rows swiped away are left out).
    func goal(_ level: CoverageLevel, type: TripType, target: Int) -> Int {
        switch tier(for: type) {
        case .core:
            return level == .light ? min(lightDayTarget(for: type), target) : target
        case .fullDay:
            return level == .full ? target : 0
        case .extra:
            return 0
        }
    }

    /// The key a row is swiped away by (1.28): "TELE", "WHIP-1".
    var key: String {
        shot.rawValue + (half.map { "-\($0)" } ?? "")
    }

    /// The key of one of its roles: "WIDE.establishing".
    func key(role: String) -> String {
        key + "." + role
    }
}

/// A day's progress at each level.
struct DayCoverage {
    var doneByLevel: [CoverageLevel: Int] = [:]
    var targetByLevel: [CoverageLevel: Int] = [:]

    func done(_ level: CoverageLevel) -> Int { doneByLevel[level] ?? 0 }
    func target(_ level: CoverageLevel) -> Int { targetByLevel[level] ?? 0 }
    func complete(_ level: CoverageLevel) -> Bool { done(level) >= target(level) }
}

extension Trip {
    /// How far a shot has got on a day: which roles are covered, and what each take does. Rows swiped away for the day
    /// lower its target, but only when the others couldn't make it up: DETAIL needs 4 of its 5 kinds, so one swiped
    /// away changes nothing, a second takes it to 3 (1.28).
    func coverage(for slot: ShotSlot, day number: Int) -> SlotCoverage {
        let tripDay = day(number)
        let type = tripDay.type
        let away = Set(tripDay.notToday ?? [])
        var target = slot.target(for: type)
        // A ONE TAKE counts as its parts, each a take of its own shot (1.24).
        var takes = allTakes.filter { $0.shot == slot.shot.rawValue && $0.dayNumber == number }
        if let name = slot.variantName {
            takes = takes.filter { $0.variant == name }
        }
        takes.sort { $0.recordedAt < $1.recordedAt }

        var statuses: [UUID: CoverageStatus] = [:]
        for take in takes where !take.countsAsCoverage {
            statuses[take.id] = .rejected
        }
        let usable = takes.filter { $0.countsAsCoverage }
        let roles = slot.half == nil ? slot.shot.roles(for: type) : []
        var done = 0
        var lines: [SlotCoverage.RoleLine] = []
        var unsortedCount = 0
        var rowAway = false

        if roles.isEmpty {
            if usable.isEmpty && away.contains(slot.key) {
                rowAway = true
                target = 0
            }
            for take in usable {
                if done < target {
                    statuses[take.id] = .counts
                    done += 1
                } else {
                    statuses[take.id] = .extra
                }
            }
        } else {
            var byRole: [String: [Clip]] = [:]
            var unsorted: [Clip] = []
            for take in usable {
                if let id = take.roleID {
                    byRole[id, default: []].append(take)
                } else {
                    unsorted.append(take)
                }
            }
            let counted = roles.filter { !$0.isOptional && !$0.isSubstitute }
            // Swiped away and not filmed today.
            let awayRoles = Set(roles.filter { byRole[$0.id] == nil && away.contains(slot.key(role: $0.id)) }.map { $0.id })
            let countedAway = counted.filter { awayRoles.contains($0.id) }.count
            let spare = max(0, counted.count - target)
            target = max(0, target - max(0, countedAway - spare))

            // One take per role, the usual roles before swap-ins. Repeats of a role are extras.
            var filling: Set<String> = []
            for role in counted + roles.filter({ $0.isSubstitute }) where done < target {
                if let take = byRole[role.id]?.first {
                    statuses[take.id] = .counts
                    done += 1
                    filling.insert(role.id)
                }
            }
            for take in unsorted where done < target {
                statuses[take.id] = .counts
                done += 1
                unsortedCount += 1
            }
            for take in usable where statuses[take.id] == nil {
                statuses[take.id] = .extra
            }
            for role in roles {
                lines.append(SlotCoverage.RoleLine(role: role, usable: byRole[role.id]?.count ?? 0,
                                                   fillsTarget: filling.contains(role.id),
                                                   notToday: awayRoles.contains(role.id)))
            }
        }
        return SlotCoverage(target: target, done: done, roles: lines, unsorted: unsortedCount, statuses: statuses,
                            notToday: rowAway, filmed: takes.count)
    }

    /// The day's progress at each level. Light counts towards everyday, and everyday towards full: every level
    /// adds up the same takes, with its own goal for each row.
    func dayCoverage(_ number: Int) -> DayCoverage {
        let type = day(number).type
        var result = DayCoverage()
        for slot in TripPhase.allSlots where slot.tier(for: type) != .extra {
            let coverage = self.coverage(for: slot, day: number)
            for level in CoverageLevel.allCases {
                let goal = slot.goal(level, type: type, target: coverage.target)
                result.doneByLevel[level, default: 0] += min(coverage.done, goal)
                result.targetByLevel[level, default: 0] += goal
            }
        }
        return result
    }

    /// How far one part of the day has got (1.28): what its shots that count have, out of what they need today.
    func progress(of part: TripPhase, day number: Int) -> (done: Int, target: Int) {
        let type = day(number).type
        var done = 0
        var target = 0
        for slot in part.slots where slot.tier(for: type) != .extra {
            let coverage = self.coverage(for: slot, day: number)
            done += min(coverage.done, coverage.target)
            target += coverage.target
        }
        return (done, target)
    }
}

// MARK: Spots

/// Clips filmed close together on a day (1.28), worked out from where and when each was filmed. It goes in the
/// catalogue, so the edit can see which shots go together. Nothing on screen depends on it, and nothing is named for
/// you: you name your clips yourself.
struct ClipSpot: Identifiable {
    let number: Int
    let clips: [Clip]

    var id: Int { number }

    /// The name most of its clips share (the first one given, if it's a tie), like "Alberta Falls". nil until a clip
    /// there has one.
    var name: String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for name in clips.compactMap({ $0.displayName }) {
            if counts[name] == nil {
                order.append(name)
            }
            counts[name, default: 0] += 1
        }
        // max(by:) keeps the first of equal counts, so a tie goes to the name given first.
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }
}

extension Trip {
    /// A new spot starts more than 250 m from where the last one started or, without locations, after 20 minutes with
    /// nothing filmed. Close enough to keep two waterfalls on one trail apart (until 1.28, scenes went by a kilometre).
    static let spotDistance: Double = 250
    static let spotGap: TimeInterval = 20 * 60

    /// Distance over the earth's surface, in metres.
    static func distanceMetres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = lat1 * Double.pi / 180
        let phi2 = lat2 * Double.pi / 180
        let dPhi = (lat2 - lat1) * Double.pi / 180
        let dLambda = (lon2 - lon1) * Double.pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * radius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// The day's spots, in the order they were filmed.
    func spots(onDay number: Int) -> [ClipSpot] {
        let dayClips = clips(onDay: number).sorted { $0.recordedAt < $1.recordedAt }
        var result: [ClipSpot] = []
        var current: [Clip] = []
        // The spot's first clip with a location: the next one is measured from there, so a slow walk along a trail
        // doesn't drag one spot along with it.
        var anchor: Clip? = nil
        for clip in dayClips {
            if let last = current.last {
                let startsNew: Bool
                if let anchor, let lat1 = anchor.latitude, let lon1 = anchor.longitude,
                   let lat2 = clip.latitude, let lon2 = clip.longitude {
                    startsNew = Self.distanceMetres(lat1, lon1, lat2, lon2) > Self.spotDistance
                } else {
                    startsNew = clip.recordedAt.timeIntervalSince(last.recordedAt) > Self.spotGap
                }
                if startsNew {
                    result.append(ClipSpot(number: result.count + 1, clips: current))
                    current = []
                    anchor = nil
                }
            }
            current.append(clip)
            if anchor == nil, clip.latitude != nil, clip.longitude != nil {
                anchor = clip
            }
        }
        if !current.isEmpty {
            result.append(ClipSpot(number: result.count + 1, clips: current))
        }
        return result
    }
}

// MARK: The catalogue

/// A clip's coverage details for the catalogue.
struct ClipCoverageInfo {
    var status: CoverageStatus? = nil
    /// Its spot on the day (1.28), in the catalogue's scene columns.
    var scene: Int? = nil
    var sceneName: String? = nil
}

extension Trip {
    /// Every clip's coverage status and spot.
    func coverageByClip() -> [UUID: ClipCoverageInfo] {
        var result: [UUID: ClipCoverageInfo] = [:]
        for tripDay in allDays {
            for slot in TripPhase.allSlots {
                for (id, status) in coverage(for: slot, day: tripDay.number).statuses {
                    result[id, default: ClipCoverageInfo()].status = status
                }
            }
            for spot in spots(onDay: tripDay.number) {
                for clip in spot.clips {
                    result[clip.id, default: ClipCoverageInfo()].scene = spot.number
                    result[clip.id, default: ClipCoverageInfo()].sceneName = spot.name
                }
            }
        }
        return result
    }
}
