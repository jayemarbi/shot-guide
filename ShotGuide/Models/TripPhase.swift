import Foundation

/// One shot, or one half of WHIP or HOME, as the counting sees it.
struct ShotSlot: Identifiable, Hashable {
    let shot: ShotType
    /// For WHIP: 0 is the Out half (ends a place), 1 the In half (starts one). For HOME: Before and After.
    /// nil is the whole shot.
    let half: Int?
    /// The creative role to open the camera on, when one was tapped. nil lets the camera pick the next one needed.
    var role: String? = nil

    var id: String { shot.rawValue + (half.map { "-\($0)" } ?? "") + (role.map { "." + $0 } ?? "") }

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

    func tier(for type: TripType) -> ShotTier {
        type.tier(for: shot)
    }

    func lightDayTarget(for type: TripType) -> Int {
        half == nil ? type.lightDayTarget(for: shot) : 0
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
        let takes = trip.allTakes.filter { $0.shot == shot.rawValue && $0.dayNumber == day }
        guard let variantName else { return takes.count }
        return takes.filter { $0.variant == variantName }.count
    }
}

/// One row on a part of the day's list (1.28): a shot, one of its roles, WHIP's or HOME's half, or one of TALK's
/// versions or MATCH CUT's moves. Each row is filmed one way, so the camera opens on exactly the shot you tapped and
/// has nothing to choose.
struct ShotRow: Identifiable, Hashable {
    let shot: ShotType
    var half: Int? = nil
    var role: String? = nil
    /// TALK's version or MATCH CUT's move, which the camera sticks to.
    var variant: Int? = nil

    var id: String { key + (variant.map { "~\($0)" } ?? "") }

    /// What "Not today" saves: "TELE", "WHIP-1", "WIDE.establishing".
    var key: String {
        role.map { slot.key(role: $0) } ?? slot.key
    }

    /// The shot as the counting sees it.
    var slot: ShotSlot { ShotSlot(shot: shot, half: half) }

    var roleInfo: CoverageRole? { role.flatMap { shot.role(withID: $0) } }

    /// The version the camera sticks to: WHIP's or HOME's half, TALK's version or MATCH CUT's move.
    var fixedVariant: Int? { half ?? variant }

    /// "WIDE · Establishing", "WHIP · IN", "TALK · One line", "MATCH CUT · Leap".
    var title: String {
        if let half, half < shot.variants.count {
            return "\(shot.title) · \(shot.variants[half].uppercased())"
        }
        if let roleInfo {
            return "\(shot.title) · \(roleInfo.title)"
        }
        if let variant, variant < shot.variants.count {
            return "\(shot.title) · \(shot.variants[variant])"
        }
        return shot.title
    }

    /// Its name on a list grouped by shot, like "Atmosphere" under B-roll.
    var shortTitle: String {
        roleInfo?.title ?? title
    }

    /// Whether you're in it: its role says, or the shot's usual way.
    var inShot: Bool {
        roleInfo?.inShot ?? (shot.defaultGroup == .inShot)
    }

    /// The version its plan is made for.
    var variantIndex: Int {
        if shot.rolesAreVariants, let role, let index = shot.roles.firstIndex(where: { $0.id == role }) {
            return index
        }
        return fixedVariant ?? 0
    }

    /// The plan for its first take: what the phone goes on, which way it's held, the lens and the length.
    var plan: ShotPlan {
        shot.plan(take: 1, inShot: inShot, variant: variantIndex, role: shot.rolesAreVariants ? nil : role)
    }

    var mount: Mount { plan.mount }

    var filming: Filming { plan.filming ?? shot.filming }

    /// Roughly how long one take takes, setting up included, in seconds (1.28): for "about 15 min" on each group.
    var secondsPerTake: Double {
        let plan = self.plan
        let length: Double = plan.timelapseInterval != nil ? 600 : (plan.autoStop ?? plan.manualLength)
        let countdown = Double(plan.isInShot ? plan.countdown : 0)
        let setUp: Double
        switch plan.mount {
        case .tripod: setUp = 75
        case .gimbal: setUp = 45
        case .handheld: setUp = 30
        }
        return length + countdown + setUp
    }
}

/// Rows on a part's list that go together: what the phone goes on, so the tripod only goes up once (1.28), or by kind
/// on B-roll, where nearly everything is in your hand.
struct RowGroup: Identifiable {
    let id: String
    let title: String
    /// What the phone goes on, for groups made that way.
    let mount: Mount?
    let rows: [ShotRow]
}

/// The parts of a day (1.28), each its own list: the order you'd film them in, getting there, walking in, the first
/// look, you at the spot and leaving, plus B-roll, grabbed any time, and what's filmed at home before and after.
enum TripPhase: String, CaseIterable, Identifiable {
    case onTheWay
    case arriving
    case firstLook
    case atTheSpot
    case leaving
    case bRoll
    case atHome

    var id: String { rawValue }

    /// The parts with a button each under Your day, in order. B-roll (any time) and At home sit apart.
    static let dayParts: [TripPhase] = [.onTheWay, .arriving, .firstLook, .atTheSpot, .leaving]

    var title: String {
        switch self {
        case .onTheWay: return "On the way"
        case .arriving: return "Arriving"
        case .firstLook: return "First look"
        case .atTheSpot: return "At the spot"
        case .leaving: return "Leaving"
        case .bRoll: return "B-roll"
        case .atHome: return "At home"
        }
    }

    /// The line at the top of its list.
    var intro: String {
        switch self {
        case .onTheWay:
            return "The trip there, all in your hand. Never film while you're the one driving."
        case .arriving:
            return "Walking in, before you've seen the view. On the gimbal, or in your hand without one."
        case .firstLook:
            return "Your first two minutes. Film REACTION before you've seen the view, then REVEAL."
        case .atTheSpot:
            return "You in the view. The handheld shots first, then put the tripod up once for the rest."
        case .leaving:
            return "As you go: whip away from the view, then walk into where you're staying."
        case .bRoll:
            return "The place without you. Grab these any time, all day. All handheld except TIMELAPSE."
        case .atHome:
            return "Before and after the trip."
        }
    }

    /// The rows in the order you'd film them, the creative ones apart.
    var rows: [ShotRow] {
        switch self {
        case .onTheWay:
            return ["getting-going", "window", "road-ahead", "pulling-in"].map { ShotRow(shot: .onTheWay, role: $0) }
        case .arriving:
            return [ShotRow(shot: .pov, role: "through"), ShotRow(shot: .pov, role: "approach"), ShotRow(shot: .follow)]
        case .firstLook:
            return [ShotRow(shot: .reaction), ShotRow(shot: .reveal, role: "walk-reveal"),
                    ShotRow(shot: .reveal, role: "tilt-up"), ShotRow(shot: .reveal, role: "auto-zoom")]
        case .atTheSpot:
            return [
                ShotRow(shot: .whip, half: 1),
                ShotRow(shot: .wide, role: "establishing"),
                ShotRow(shot: .wide, role: "alternative"),
                ShotRow(shot: .wide, role: "vertical-hero"),
                ShotRow(shot: .slomo, role: "water"),
                ShotRow(shot: .wide, role: "human-scale"),
                ShotRow(shot: .walkaway, role: "into-view"),
                ShotRow(shot: .walkaway, role: "new-spot"),
                ShotRow(shot: .tele),
                ShotRow(shot: .moment, role: "with-place"),
                ShotRow(shot: .moment, role: "together"),
                ShotRow(shot: .slomo, role: "you")
            ]
        case .leaving:
            return [ShotRow(shot: .whip, half: 0), ShotRow(shot: .stay)]
        case .bRoll:
            return bRollGroups.flatMap { $0.rows }
        case .atHome:
            return [ShotRow(shot: .home, half: 0), ShotRow(shot: .home, half: 1), ShotRow(shot: .talk, variant: 0),
                    ShotRow(shot: .voiceover)]
        }
    }

    /// The creative shots, in a drop-down at the bottom of the list: pick any you want today (1.28).
    var creative: [ShotRow] {
        switch self {
        case .atTheSpot:
            return [ShotRow(shot: .oneTake), ShotRow(shot: .matchCut), ShotRow(shot: .clone), ShotRow(shot: .orbit),
                    ShotRow(shot: .dance), ShotRow(shot: .silhouette), ShotRow(shot: .talk, variant: 1)]
        case .arriving:
            return [ShotRow(shot: .hyperlapse)]
        default:
            return []
        }
    }

    /// The order the groups come in, by what the phone goes on: the quick ones in your hand first, then the tripod
    /// set-up. First look starts with REACTION in your hand and the walk on the gimbal.
    private var mountOrder: [Mount] {
        switch self {
        case .firstLook: return [.handheld, .gimbal, .tripod]
        case .arriving, .leaving: return [.handheld, .gimbal, .tripod]
        default: return [.handheld, .tripod, .gimbal]
        }
    }

    /// The rows in groups: by kind on B-roll, otherwise by what the phone goes on, each in the order of the day.
    var groups: [RowGroup] {
        switch self {
        case .bRoll:
            return bRollGroups
        case .atHome:
            return [RowGroup(id: "home", title: "At home", mount: nil, rows: rows)]
        default:
            let all = rows
            return mountOrder.compactMap { mount in
                let matching = all.filter { $0.mount == mount }
                return matching.isEmpty ? nil : RowGroup(id: mount.title, title: mount.title, mount: mount, rows: matching)
            }
        }
    }

    /// B-roll by kind, as nearly all of it is in your hand.
    private var bRollGroups: [RowGroup] {
        [
            RowGroup(id: "broll", title: "B-roll", mount: nil, rows: ShotType.bRoll.roles.map { ShotRow(shot: .bRoll, role: $0.id) }),
            RowGroup(id: "detail", title: "Detail", mount: nil, rows: ShotType.detail.roles.map { ShotRow(shot: .detail, role: $0.id) }),
            RowGroup(id: "sound", title: "Sound", mount: nil, rows: [ShotRow(shot: .ambient), ShotRow(shot: .sounds)]),
            RowGroup(id: "more", title: "More", mount: nil,
                     rows: [ShotRow(shot: .wildlife), ShotRow(shot: .food), ShotRow(shot: .reflection)]),
            RowGroup(id: "tripod", title: "On the tripod", mount: .tripod, rows: [ShotRow(shot: .timelapse)])
        ]
    }

    /// Every row, the creative ones included.
    var allRows: [ShotRow] {
        rows + creative
    }

    /// The shots as the counting sees them, each once.
    var slots: [ShotSlot] {
        var result: [ShotSlot] = []
        for row in allRows where !result.contains(row.slot) {
            result.append(row.slot)
        }
        return result
    }

    static var allSlots: [ShotSlot] {
        var result: [ShotSlot] = []
        for part in allCases {
            for slot in part.slots where !result.contains(slot) {
                result.append(slot)
            }
        }
        return result
    }

    /// Every row on every list, each once.
    static var allRows: [ShotRow] {
        allCases.flatMap { $0.allRows }
    }
}

extension TripPhase {
    /// Under its button on the trip page (1.28): what's in it, like "Handheld 5 · tripod 7 · creative".
    var buttonLine: String {
        switch self {
        case .firstLook:
            return "Film REACTION before you look"
        case .leaving:
            return "WHIP · OUT, then where you're staying"
        case .bRoll:
            return "The place without you, all day"
        case .atHome:
            return "Before and after the trip"
        default:
            let groups = self.groups
            var line: String
            if groups.count == 1, let group = groups.first, let mount = group.mount {
                let count = group.rows.count
                line = "\(count) \(count == 1 ? "shot" : "shots"), all \(mount == .handheld ? "in your hand" : mount.phrase)"
            } else {
                line = groups.enumerated().map { index, group in
                    "\(index == 0 ? group.title : group.title.lowercased()) \(group.rows.count)"
                }.joined(separator: " · ")
            }
            if creative.count == 1, let only = creative.first {
                line += ", plus " + only.title
            } else if !creative.isEmpty {
                line += " · creative"
            }
            return line
        }
    }
}

/// What a row on a part's list shows on its right (1.28).
enum RowStatus: Equatable {
    /// Swiped away for today, and not filmed.
    case notToday
    /// Filmed: how many takes count. Green.
    case filmed(Int)
    /// Takes that count, out of what it needs today.
    case progress(done: Int, target: Int)
    /// Not part of the target, like WIDE's vertical hero.
    case optional
    /// Stands in for a usual role the place doesn't have.
    case swapIn
    /// Doesn't count today, like the creative shots: welcome whenever it's worth it.
    case extra
    /// Its shot already has what it needs today, so this would be an extra.
    case spare

    /// Still needed today, and how many takes.
    var stillNeeded: Int {
        if case .progress(let done, let target) = self {
            return max(0, target - done)
        }
        return 0
    }
}

extension Trip {
    /// Takes filmed on a day for one row: its role, half or version.
    func takes(of row: ShotRow, day number: Int) -> [Clip] {
        allTakes.filter { take in
            guard take.shot == row.shot.rawValue, take.dayNumber == number, take.countsAsCoverage else { return false }
            if let half = row.half {
                return row.shot.variants.indices.contains(half) && take.variant == row.shot.variants[half]
            }
            if let role = row.role {
                return take.roleID == role
            }
            if let variant = row.variant {
                return row.shot.variants.indices.contains(variant) && take.variant == row.shot.variants[variant]
            }
            return true
        }
    }

    /// What a row shows on a day (1.28).
    func status(of row: ShotRow, day number: Int) -> RowStatus {
        let type = day(number).type
        let filmed = takes(of: row, day: number).count
        guard row.slot.tier(for: type) != .extra else {
            return filmed > 0 ? .filmed(filmed) : .extra
        }
        let coverage = self.coverage(for: row.slot, day: number)
        if let role = row.role, let line = coverage.line(for: role) {
            if line.notToday {
                return .notToday
            }
            if line.covered {
                return .filmed(line.usable)
            }
            if line.role.isOptional {
                return .optional
            }
            if line.role.isSubstitute {
                return .swapIn
            }
            return coverage.complete ? .spare : .progress(done: 0, target: 1)
        }
        if coverage.notToday {
            return .notToday
        }
        return .progress(done: coverage.done, target: coverage.target)
    }

    /// Whether a row is swiped away for a day.
    func isNotToday(_ row: ShotRow, day number: Int) -> Bool {
        day(number).notToday?.contains(row.key) == true
    }

    /// Whether a row can be swiped away for a day: it counts today, it's one of the usual ones and nothing's been
    /// filmed for it yet. Optional rows, swap-ins and extras never count against the day, so there's nothing to swipe.
    func canSetAside(_ row: ShotRow, day number: Int) -> Bool {
        let type = day(number).type
        guard row.slot.tier(for: type) != .extra, takes(of: row, day: number).isEmpty else { return false }
        if let role = row.roleInfo {
            let usual = row.shot.roles(for: type).first { $0.id == role.id }
            return usual.map { !$0.isOptional && !$0.isSubstitute } ?? false
        }
        return true
    }

    /// Roughly how long the rows of a group still need today, in whole minutes. nil when none of them count today,
    /// 0 once they're all done.
    func minutesLeft(in rows: [ShotRow], day number: Int) -> Int? {
        let type = day(number).type
        let counting = rows.filter { $0.slot.tier(for: type) != .extra }
        guard !counting.isEmpty else { return nil }
        var seconds = 0.0
        for row in counting {
            seconds += Double(status(of: row, day: number).stillNeeded) * row.secondsPerTake
        }
        return Int((seconds / 60).rounded(.up))
    }
}
