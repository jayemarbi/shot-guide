import Foundation

// Creative coverage (1.19): what a day's footage can make, not just how many takes it has.
//
// Shots that need several takes give each take a creative role, like WIDE's establishing view or B-ROLL's
// movement. One take fills one role, and repeats of a role are extras, so the counters reward variety.
//
// A take goes through four stages:
//   recorded for its role → technically acceptable (passed the take check, or the shot has none, and wasn't
//   stopped early) → provisionally covered → confirmed usable, once you've marked it Usable or starred it.
// A failed take only counts if you deliberately use it anyway. Review is never required.

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
    /// Whether you're in the shot for this role. nil leaves it to the "I'm in this shot" switch.
    var inShot: Bool? = nil
    /// Not part of the shot's target, like WIDE's vertical hero.
    var isOptional: Bool = false
    /// A swap-in, for when a place doesn't have what one of the usual roles needs, like B-ROLL's people at a
    /// remote lookout. It counts like any other role.
    var isSubstitute: Bool = false
}

extension ShotType {
    /// The creative roles of a shot, the usual ones first, then swap-ins. Empty for shots that just need takes.
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
                                + "that's changing."),
                CoverageRole(id: "vertical-hero", title: "Vertical hero",
                             purpose: "An upright, full-screen version of the best view, for reels that play full screen.",
                             isOptional: true)
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
        default:
            return []
        }
    }

    /// REVEAL's roles are its versions, picked with the same buttons.
    var rolesAreVariants: Bool { self == .reveal }

    func role(withID id: String) -> CoverageRole? {
        roles.first { $0.id == id }
    }

    /// How much this shot matters on a day, before trip types change it.
    var tier: ShotTier {
        switch self {
        case .wide, .bRoll, .detail, .pov, .reveal, .walkaway, .moment, .ambient:
            return .core
        case .reaction, .tele, .talk, .slomo, .matchCut, .silhouette:
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
    /// Only roles still `open` are suggested.
    func nextRole(after current: String?, open: Set<String>) -> CoverageRole? {
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
    /// REVEAL's versions, and WIDE and WALKAWAY, which changed with the take number.
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
        default:
            return nil
        }
    }

    /// Stopped well before its planned length (under 60% of it), or under 3 seconds for a take you stopped yourself.
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

    /// Whether this take can fill coverage: you marked it Usable (which overrides a failed check), or it's
    /// technically acceptable and you haven't marked it not usable.
    var countsAsCoverage: Bool {
        if let usable {
            return usable
        }
        return technicallyAcceptable
    }

    /// You've looked at it and it's good: marked Usable, or starred as the best take when it passed its check.
    /// A star alone never overrides a failed check.
    var confirmedUsable: Bool {
        if let usable {
            return usable
        }
        return favourite && technicallyAcceptable
    }
}

/// What a take does for coverage, for the trip page and the catalogue.
enum CoverageStatus: String {
    /// Fills part of its shot's target, and you've confirmed it's usable.
    case confirmed
    /// Fills part of the target for now: technically fine, not yet confirmed.
    case provisional
    /// Usable, but its role (or the shot) already had a take. Welcome all the same.
    case extra
    /// Failed the take check, and not used anyway.
    case retake
    /// Stopped well short of its length, and not used anyway.
    case short
    /// You marked it not usable.
    case rejected
}

/// How far one row of the trip page has got on a day.
struct SlotCoverage {
    struct RoleLine: Identifiable {
        let role: CoverageRole
        /// Takes filmed for this role that count as coverage.
        let usable: Int
        /// Of those, the ones you've confirmed.
        let confirmed: Int
        /// Takes filmed for it that don't count.
        let retakes: Int
        /// Whether one of its takes fills the target.
        let fillsTarget: Bool

        var id: String { role.id }
        var covered: Bool { usable > 0 }
    }

    let target: Int
    /// Takes that fill the target, never more than it.
    let done: Int
    /// Of those, the ones you've confirmed.
    let confirmedDone: Int
    /// Every role, optional ones and swap-ins included. Empty for shots without roles.
    let roles: [RoleLine]
    /// Usable takes without a role (older takes and imports) that fill the target.
    let unsorted: Int
    let statuses: [UUID: CoverageStatus]

    var complete: Bool { done >= target }
    var fullyConfirmed: Bool { complete && confirmedDone >= target }

    /// Usable takes beyond the target.
    var extras: Int {
        statuses.values.filter { $0 == .extra }.count
    }

    /// Takes that need another go: failed, short or not usable.
    var retakes: Int {
        statuses.values.filter { $0 == .retake || $0 == .short || $0 == .rejected }.count
    }

    /// Roles that would add to the target: not covered yet, not optional.
    var openRoleIDs: Set<String> {
        guard !complete else { return [] }
        return Set(roles.filter { !$0.role.isOptional && !$0.covered }.map { $0.role.id })
    }

    /// The usual roles still open, for "what's missing" lists. Swap-ins aren't listed: they stand in for these.
    var missingRoles: [CoverageRole] {
        guard !complete else { return [] }
        return roles.filter { !$0.role.isOptional && !$0.role.isSubstitute && !$0.covered }.map { $0.role }
    }

    /// Optional roles not filmed yet, like WIDE's vertical hero.
    var openOptionalRoles: [CoverageRole] {
        roles.filter { $0.role.isOptional && !$0.covered }.map { $0.role }
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
    /// How many roles or takes this row needs for a level of coverage on a day of a type.
    func goal(_ level: CoverageLevel, type: TripType) -> Int {
        switch tier(for: type) {
        case .core:
            return level == .light ? lightDayTarget(for: type) : target(for: type)
        case .fullDay:
            return level == .full ? target(for: type) : 0
        case .extra:
            return 0
        }
    }
}

/// One row still short of a level.
struct MissingCoverage: Identifiable {
    let slot: ShotSlot
    let needed: Int
    /// The usual roles still open, for rows with roles.
    let roles: [CoverageRole]

    var id: String { slot.id }

    /// "WIDE: Another angle", "B-ROLL: 2 more (People, Movement, Transition or a swap-in)", "TELE: 1 take".
    var line: String {
        let name = slot.title
        if roles.isEmpty {
            return "\(name): \(needed) \(needed == 1 ? "take" : "takes")"
        }
        let names = roles.map { $0.title }
        if needed >= names.count {
            return "\(name): " + names.joined(separator: ", ")
        }
        let swap = slot.shot.roles.contains { $0.isSubstitute } ? " or a swap-in" : ""
        return "\(name): \(needed) more from " + Self.list(names) + swap
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }
}

/// A day's progress at each level.
struct DayCoverage {
    var doneByLevel: [CoverageLevel: Int] = [:]
    var targetByLevel: [CoverageLevel: Int] = [:]
    /// Confirmed takes that fill the full day's targets.
    var confirmed = 0

    func done(_ level: CoverageLevel) -> Int { doneByLevel[level] ?? 0 }
    func target(_ level: CoverageLevel) -> Int { targetByLevel[level] ?? 0 }
    func complete(_ level: CoverageLevel) -> Bool { done(level) >= target(level) }
}

extension Trip {
    /// How far a row has got on a day: which roles are covered, and what each take does.
    func coverage(for slot: ShotSlot, day number: Int) -> SlotCoverage {
        let type = day(number).type
        let target = slot.target(for: type)
        var takes = clips.filter { $0.shot == slot.shot.rawValue && $0.dayNumber == number }
        if let name = slot.variantName {
            takes = takes.filter { $0.variant == name }
        }
        // Confirmed takes first, then in the order they were filmed, so a confirmed take is the one that fills
        // its role.
        takes.sort { first, second in
            if first.confirmedUsable != second.confirmedUsable {
                return first.confirmedUsable
            }
            return first.recordedAt < second.recordedAt
        }

        var statuses: [UUID: CoverageStatus] = [:]
        for take in takes where !take.countsAsCoverage {
            if take.usable == false {
                statuses[take.id] = .rejected
            } else {
                statuses[take.id] = take.checkPassed == false ? .retake : .short
            }
        }
        let usable = takes.filter { $0.countsAsCoverage }
        let roles = slot.half == nil ? slot.shot.roles : []
        var done = 0
        var confirmedDone = 0
        var lines: [SlotCoverage.RoleLine] = []
        var unsortedCount = 0
        var filling: Set<String> = []

        func fill(_ take: Clip) {
            statuses[take.id] = take.confirmedUsable ? .confirmed : .provisional
            done += 1
            if take.confirmedUsable {
                confirmedDone += 1
            }
        }

        if roles.isEmpty {
            for take in usable {
                if done < target {
                    fill(take)
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
            // One take per role, the usual roles before swap-ins. Repeats of a role are extras.
            let ordered = roles.filter { !$0.isOptional && !$0.isSubstitute } + roles.filter { $0.isSubstitute }
            for role in ordered where done < target {
                if let take = byRole[role.id]?.first {
                    fill(take)
                    filling.insert(role.id)
                }
            }
            for take in unsorted where done < target {
                fill(take)
                unsortedCount += 1
            }
            for take in usable where statuses[take.id] == nil {
                statuses[take.id] = .extra
            }
            for role in roles {
                let filmed = takes.filter { $0.roleID == role.id }
                let usableTakes = filmed.filter { $0.countsAsCoverage }
                lines.append(SlotCoverage.RoleLine(
                    role: role,
                    usable: usableTakes.count,
                    confirmed: usableTakes.filter { $0.confirmedUsable }.count,
                    retakes: filmed.count - usableTakes.count,
                    fillsTarget: filling.contains(role.id)))
            }
        }
        return SlotCoverage(target: target, done: done, confirmedDone: confirmedDone, roles: lines,
                            unsorted: unsortedCount, statuses: statuses)
    }

    /// The day's progress at each level. Light counts towards everyday, and everyday towards full: every level
    /// adds up the same takes, with its own goal for each row.
    func dayCoverage(_ number: Int) -> DayCoverage {
        let type = day(number).type
        var result = DayCoverage()
        for slot in TripPhase.allSlots {
            let fullGoal = slot.goal(.full, type: type)
            guard fullGoal > 0 else { continue }
            let coverage = self.coverage(for: slot, day: number)
            for level in CoverageLevel.allCases {
                let goal = slot.goal(level, type: type)
                result.doneByLevel[level, default: 0] += min(coverage.done, goal)
                result.targetByLevel[level, default: 0] += goal
            }
            result.confirmed += min(coverage.confirmedDone, fullGoal)
        }
        return result
    }

    /// Rows still short of a level, in the order of the day.
    func missing(_ level: CoverageLevel, day number: Int) -> [MissingCoverage] {
        let type = day(number).type
        var result: [MissingCoverage] = []
        for slot in TripPhase.allSlots {
            let goal = slot.goal(level, type: type)
            guard goal > 0 else { continue }
            let coverage = self.coverage(for: slot, day: number)
            let needed = goal - min(coverage.done, goal)
            guard needed > 0 else { continue }
            result.append(MissingCoverage(slot: slot, needed: needed, roles: coverage.missingRoles))
        }
        return result
    }

    /// The next useful thing to film on a day: the first row of the lowest unfinished level, in the order of the
    /// day, with the role it still needs.
    func nextSuggestion(day number: Int) -> ShotSuggestion? {
        for level in CoverageLevel.allCases {
            if let first = missing(level, day: number).first {
                let coverage = self.coverage(for: first.slot, day: number)
                let role = first.slot.shot.nextRole(after: nil, open: coverage.openRoleIDs)
                return ShotSuggestion(shot: first.slot.shot, half: first.slot.half, role: role?.id)
            }
        }
        return nil
    }
}

// MARK: Scenes

/// The five things a short story about one place needs. Each is filled by shots you already film.
enum SceneIngredient: String, CaseIterable, Identifiable {
    case establish
    case approach
    case interact
    case experience
    case atmosphere

    var id: String { rawValue }

    var title: String {
        switch self {
        case .establish: return "Establish"
        case .approach: return "Approach"
        case .interact: return "Interact"
        case .experience: return "Experience"
        case .atmosphere: return "Atmosphere"
        }
    }

    var hint: String {
        switch self {
        case .establish: return "Show the place"
        case .approach: return "You arriving or moving towards it"
        case .interact: return "A meaningful action or detail"
        case .experience: return "You enjoying it or reacting to it"
        case .atmosphere: return "Its visuals or natural sound"
        }
    }

    /// Shots to film for it, best first. The trip page picks the first one the day still needs.
    var suggestions: [ShotSuggestion] {
        switch self {
        case .establish:
            return [ShotSuggestion(shot: .wide, role: "establishing"), ShotSuggestion(shot: .reveal),
                    ShotSuggestion(shot: .wide, role: "alternative")]
        case .approach:
            return [ShotSuggestion(shot: .pov, role: "approach"), ShotSuggestion(shot: .walkaway, role: "into-view"),
                    ShotSuggestion(shot: .pov, role: "through")]
        case .interact:
            return [ShotSuggestion(shot: .detail, role: "hands"), ShotSuggestion(shot: .moment, role: "with-place"),
                    ShotSuggestion(shot: .detail)]
        case .experience:
            return [ShotSuggestion(shot: .moment, role: "together"), ShotSuggestion(shot: .wide, role: "human-scale"),
                    ShotSuggestion(shot: .reaction)]
        case .atmosphere:
            return [ShotSuggestion(shot: .ambient), ShotSuggestion(shot: .bRoll, role: "atmosphere"),
                    ShotSuggestion(shot: .bRoll)]
        }
    }
}

/// A shot, and optionally the half or role to open it on.
struct ShotSuggestion: Hashable {
    let shot: ShotType
    var half: Int? = nil
    var role: String? = nil

    var slot: ShotSlot {
        ShotSlot(shot: shot, half: half, role: role)
    }

    var title: String {
        if let half, half < shot.variants.count {
            return "\(shot.title) · \(shot.variants[half])"
        }
        guard let role, let match = shot.role(withID: role) else { return shot.title }
        return "\(shot.title) · \(match.title)"
    }
}

extension Clip {
    /// The part of a scene's story this take fills. One take fills one part.
    var sceneIngredient: SceneIngredient? {
        guard let type = shotType else { return nil }
        let role = roleID
        switch type {
        case .wide:
            return role == "human-scale" ? .experience : .establish
        case .reveal:
            return .establish
        case .pov, .walkaway, .follow, .onTheWay, .hyperlapse, .stay:
            return .approach
        case .detail, .food, .sounds, .slomo, .matchCut, .clone:
            return .interact
        case .moment:
            return role == "with-place" ? .interact : .experience
        case .reaction, .talk, .silhouette, .tele, .orbit, .dance:
            return .experience
        case .ambient, .bRoll, .timelapse, .reflection, .wildlife:
            return .atmosphere
        case .whip, .home, .voiceover:
            return nil
        }
    }
}

/// The clips filmed at one place on a day.
struct ClipScene: Identifiable {
    let number: Int
    let clips: [Clip]

    var id: Int { number }

    /// The place's name, like "Twin Falls", or "Scene 2" before it has one.
    var name: String {
        placeName ?? "Scene \(number)"
    }

    /// The name most of its clips share (the first one given, if it's a tie), set by naming the place or the clips
    /// (1.21). nil until a clip there has a name.
    var placeName: String? {
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

    /// Every clip's place in the scene confirmed by you. Otherwise the grouping is the app's suggestion.
    var confirmed: Bool {
        !clips.isEmpty && clips.allSatisfy { $0.sceneConfirmed == true }
    }

    /// What the scene has, from takes that count.
    var ingredients: Set<SceneIngredient> {
        Set(clips.filter { $0.countsAsCoverage }.compactMap { $0.sceneIngredient })
    }
}

/// Your choice for the next clip of a day: start a new scene, or stay in the last one, whatever the distance.
struct SceneChoice: Codable, Hashable {
    var day: Int
    var startsNew: Bool
    /// The new place's name, when you named it with New place (1.21). Its clips get it.
    var name: String? = nil
}

extension Trip {
    /// The app's suggestion: a new scene starts when a clip is over 1 km from the one before it or, without
    /// locations, 45 minutes after it. You can correct any of it.
    static let sceneDistance: Double = 1000
    static let sceneGap: TimeInterval = 45 * 60

    static func isNewScene(previousLatitude: Double?, previousLongitude: Double?, previousDate: Date,
                           latitude: Double?, longitude: Double?, date: Date) -> Bool {
        if let lat1 = previousLatitude, let lon1 = previousLongitude, let lat2 = latitude, let lon2 = longitude {
            return distanceMetres(lat1, lon1, lat2, lon2) > sceneDistance
        }
        return date.timeIntervalSince(previousDate) > sceneGap
    }

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

    /// Each clip's scene on a day. Clips filmed since 1.19 keep the scene they were given; older clips and imports
    /// are worked out with the same rule, in the order they were filmed.
    func sceneNumbers(onDay number: Int) -> [UUID: Int] {
        let dayClips = clips(onDay: number).sorted { $0.recordedAt < $1.recordedAt }
        var next = (dayClips.compactMap { $0.scene }.max() ?? 0) + 1
        var result: [UUID: Int] = [:]
        var previous: Clip? = nil
        var current: Int? = nil
        for clip in dayClips {
            if let stored = clip.scene {
                current = stored
            } else if let previous, current != nil,
                      !Self.isNewScene(previousLatitude: previous.latitude, previousLongitude: previous.longitude,
                                       previousDate: previous.recordedAt, latitude: clip.latitude,
                                       longitude: clip.longitude, date: clip.recordedAt) {
                // Same scene as the clip before.
            } else {
                current = next
                next += 1
            }
            result[clip.id] = current
            previous = clip
        }
        return result
    }

    /// The day's scenes, in the order they were filmed.
    func scenes(onDay number: Int) -> [ClipScene] {
        let numbers = sceneNumbers(onDay: number)
        let dayClips = clips(onDay: number).sorted { $0.recordedAt < $1.recordedAt }
        var order: [Int] = []
        var grouped: [Int: [Clip]] = [:]
        for clip in dayClips {
            guard let scene = numbers[clip.id] else { continue }
            if grouped[scene] == nil {
                order.append(scene)
            }
            grouped[scene, default: []].append(clip)
        }
        return order.map { ClipScene(number: $0, clips: grouped[$0] ?? []) }
    }

    /// The app's suggestion: whether a clip filmed here and now would start a new scene on the day.
    func suggestsNewScene(day number: Int, latitude: Double?, longitude: Double?, at date: Date) -> Bool {
        guard let last = clips(onDay: number).max(by: { $0.recordedAt < $1.recordedAt }) else { return true }
        return Self.isNewScene(previousLatitude: last.latitude, previousLongitude: last.longitude,
                               previousDate: last.recordedAt, latitude: latitude, longitude: longitude, date: date)
    }

    /// The scene for a clip filmed here and now, and whether that's your choice (confirmed) or the app's suggestion.
    func sceneForNewClip(day number: Int, latitude: Double?, longitude: Double?, at date: Date) -> (scene: Int, confirmed: Bool) {
        let numbers = sceneNumbers(onDay: number)
        let highest = numbers.values.max() ?? 0
        let choice = nextScene?.day == number ? nextScene : nil
        guard let last = clips(onDay: number).max(by: { $0.recordedAt < $1.recordedAt }),
              let lastScene = numbers[last.id] else {
            return (highest + 1, choice != nil)
        }
        if let choice {
            return (choice.startsNew ? highest + 1 : lastScene, true)
        }
        if suggestsNewScene(day: number, latitude: latitude, longitude: longitude, at: date) {
            return (highest + 1, false)
        }
        return (lastScene, false)
    }

    /// Saves the worked-out scene of every clip on a day, so changing one scene doesn't move the others.
    mutating func fixScenes(onDay number: Int) {
        let numbers = sceneNumbers(onDay: number)
        for index in clips.indices where clips[index].dayNumber == number && clips[index].scene == nil {
            clips[index].scene = numbers[clips[index].id]
        }
    }

    /// Joins a scene to the one filmed before it.
    mutating func mergeScene(_ scene: Int, onDay number: Int) {
        fixScenes(onDay: number)
        let order = scenes(onDay: number).map { $0.number }
        guard let position = order.firstIndex(of: scene), position > 0 else { return }
        let into = order[position - 1]
        for index in clips.indices where clips[index].dayNumber == number && clips[index].scene == scene {
            clips[index].scene = into
            clips[index].sceneConfirmed = true
        }
    }

    /// Starts a new scene at a clip: it and the later clips of its scene move to the new one.
    mutating func splitScene(at clipID: UUID) {
        guard let clip = clips.first(where: { $0.id == clipID }) else { return }
        let number = clip.dayNumber
        fixScenes(onDay: number)
        guard let current = clips.first(where: { $0.id == clipID })?.scene else { return }
        let newScene = (clips.filter { $0.dayNumber == number }.compactMap { $0.scene }.max() ?? 0) + 1
        for index in clips.indices where clips[index].dayNumber == number && clips[index].scene == current {
            if clips[index].recordedAt >= clip.recordedAt {
                clips[index].scene = newScene
                clips[index].sceneConfirmed = true
            }
        }
    }

    /// Moves one clip into another scene of its day.
    mutating func moveClip(_ clipID: UUID, toScene scene: Int) {
        guard let position = clips.firstIndex(where: { $0.id == clipID }) else { return }
        fixScenes(onDay: clips[position].dayNumber)
        clips[position].scene = scene
        clips[position].sceneConfirmed = true
    }

    /// Marks a scene as right: its clips' places in it are confirmed.
    mutating func confirmScene(_ scene: Int, onDay number: Int) {
        fixScenes(onDay: number)
        for index in clips.indices where clips[index].dayNumber == number && clips[index].scene == scene {
            clips[index].sceneConfirmed = true
        }
    }

    /// Names (or renames) a place (1.21): its clips without a name, or with the place's old name, get this one. Clips
    /// you gave a name of their own keep it. Returns the clips that changed, so their files can be renamed to match.
    mutating func namePlace(_ scene: Int, onDay number: Int, name: String) -> [UUID] {
        fixScenes(onDay: number)
        let old = scenes(onDay: number).first { $0.number == scene }?.placeName
        var named: [UUID] = []
        for index in clips.indices where clips[index].dayNumber == number && clips[index].scene == scene {
            let current = clips[index].displayName
            guard current == nil || current == old, current != name else { continue }
            clips[index].name = name
            named.append(clips[index].id)
        }
        return named
    }
}

// MARK: The place you're at

extension ShotType {
    /// The shots that show what makes each place its own, tracked at each place on a day at more than one (1.22): a
    /// second waterfall gets its own REACTION, REVEAL, WIDE, TELE, WALKAWAY, MOMENT, SLOMO, MATCH CUT and AMBIENT. The
    /// rest, like B-ROLL, DETAIL and POV, are gathered for the day as a whole.
    var perPlace: Bool {
        switch self {
        case .reaction, .reveal, .wide, .tele, .walkaway, .moment, .slomo, .matchCut, .ambient:
            return true
        default:
            return false
        }
    }
}

/// Where your next clip goes on a day that's been at more than one place (1.21): one of the day's scenes, or a new
/// place with no clips yet.
struct PlaceNow: Equatable {
    /// The scene, or nil for a new place your next clip starts.
    let scene: Int?
    /// Its name, if it has one.
    let name: String?

    /// "At Twin Falls", "At Scene 2" or "At the new place", over the role buttons.
    var caption: String {
        if let name {
            return "At \(name)"
        }
        return scene.map { "At Scene \($0)" } ?? "At the new place"
    }
}

extension Trip {
    /// Whether your next clip starts a new scene: your choice if you made one, otherwise the app's suggestion from
    /// where you are and when you filmed last.
    func nextClipStartsScene(day number: Int, latitude: Double?, longitude: Double?, at date: Date) -> Bool {
        if let choice = nextScene, choice.day == number {
            return choice.startsNew
        }
        return suggestsNewScene(day: number, latitude: latitude, longitude: longitude, at: date)
    }

    /// The place you're filming at, once a day has been at more than one, or is about to be. nil for a day at one
    /// place, where the role buttons follow the whole day as before.
    func placeNow(day number: Int, startsNew: Bool) -> PlaceNow? {
        let dayScenes = scenes(onDay: number)
        guard let last = dayScenes.last else { return nil }
        if startsNew {
            let chosen = nextScene?.day == number ? nextScene?.name : nil
            return PlaceNow(scene: nil, name: chosen)
        }
        guard dayScenes.count > 1 else { return nil }
        return PlaceNow(scene: last.number, name: last.placeName)
    }

    /// A row's roles at one place: only the takes filmed there count. The day's own counts are unchanged, so a role
    /// filmed again at a second place is still an extra for the day.
    func coverage(for slot: ShotSlot, day number: Int, at place: PlaceNow) -> SlotCoverage {
        var here: Set<UUID> = []
        if let scene = place.scene, let match = scenes(onDay: number).first(where: { $0.number == scene }) {
            here = Set(match.clips.map { $0.id })
        }
        var atPlace = self
        atPlace.clips = clips.filter { $0.dayNumber != number || here.contains($0.id) }
        return atPlace.coverage(for: slot, day: number)
    }
}

// MARK: The catalogue

/// A clip's coverage details for the catalogue.
struct ClipCoverageInfo {
    var status: CoverageStatus? = nil
    var scene: Int? = nil
    var sceneName: String? = nil
}

extension Trip {
    /// Every clip's coverage status and scene.
    func coverageByClip() -> [UUID: ClipCoverageInfo] {
        var result: [UUID: ClipCoverageInfo] = [:]
        for tripDay in allDays {
            for slot in TripPhase.allSlots {
                for (id, status) in coverage(for: slot, day: tripDay.number).statuses {
                    result[id, default: ClipCoverageInfo()].status = status
                }
            }
            for scene in scenes(onDay: tripDay.number) {
                for clip in scene.clips {
                    result[clip.id, default: ClipCoverageInfo()].scene = scene.number
                    result[clip.id, default: ClipCoverageInfo()].sceneName = scene.name
                }
            }
        }
        return result
    }
}
