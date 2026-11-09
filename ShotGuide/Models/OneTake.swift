import Foundation

/// ONE TAKE (1.24): one long take from one tripod set-up, filming several shots in a row so you're not walking back
/// to the phone between them. The phone can't change anything mid-take (its spot, height, lens, frame rate and
/// exposure stay put), so the shots that join are the ones that only differ in what you do. Each part counts as a
/// take of its shot, for the role it still needs where you are: one part, one role.
enum OneTakePart: String, CaseIterable, Codable, Identifiable {
    case emptyFrame
    case walkIn
    case inView
    case moment
    case matchCut
    case clones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emptyFrame: return "Empty frame"
        case .walkIn: return "Walk in"
        case .inView: return "In the view"
        case .moment: return "Your moment"
        case .matchCut: return "MATCH CUT move"
        case .clones: return "Clones"
        }
    }

    /// The shot it counts as.
    var shot: ShotType {
        switch self {
        case .emptyFrame, .inView: return .wide
        case .walkIn: return .walkaway
        case .moment: return .moment
        case .matchCut: return .matchCut
        case .clones: return .clone
        }
    }

    /// Seconds, until you change it. Long, so nothing's rushed: the edit trims.
    var defaultLength: Double {
        switch self {
        case .emptyFrame, .walkIn, .matchCut: return 30
        case .inView, .moment: return 60
        case .clones: return 150
        }
    }

    /// You're in every part but the empty frame.
    var inShot: Bool {
        self != .emptyFrame
    }

    /// The roles it can fill, in order: it takes the first one not filmed yet where you are.
    var roleOrder: [String] {
        switch self {
        case .emptyFrame: return ["establishing", "alternative"]
        case .walkIn: return ["into-view", "new-spot"]
        case .inView: return ["human-scale", "alternative"]
        case .moment: return ["with-place", "together"]
        case .matchCut, .clones: return []
        }
    }

    /// What you do, for the walkthrough. The words before the colon are the prompt, and what you hear.
    func text(move: MatchMove) -> String {
        switch self {
        case .emptyFrame:
            return "Empty frame: stay behind the phone, out of shot."
        case .walkIn:
            return "Walk in: past the phone and out into the view. Don't look back."
        case .inView:
            return "In the view: stop on a third line, small against it. Look out, take a few steps, sit, point something out."
        case .moment:
            return "Your moment: walk back about halfway. Touch the water, lie back in the grass, a spin together."
        case .matchCut:
            return "\(move.title): while the light's on, walk slowly towards the phone from further back and stop when it "
                + "goes off. Then 5 flashes, and do your move once."
        case .clones:
            return "Clones: something different at 3 or 4 spots, all about the same distance from the phone. In the last "
                + "30 seconds, walk out and leave it empty."
        }
    }

    /// What you do, without the part's name in front: "Stay behind the phone, out of shot."
    func doing(move: MatchMove) -> String {
        let full = text(move: move)
        guard let colon = full.range(of: ": ") else { return full }
        let rest = full[colon.upperBound...]
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    static let walkBackText = "Walk back: to the phone, and stop it when you get there."

    /// The lengths the timing offers for a part.
    static let lengthChoices: [Double] = [10, 15, 20, 30, 45, 60, 90, 120, 150, 180, 240, 300, 420, 600]

    /// The shots a ONE TAKE can film.
    static let shots: [ShotType] = [.wide, .walkaway, .moment, .matchCut, .clone]

    /// Where each part you reached is in the clip: from where it began to where the next one began, where you set off
    /// back, or where the take stopped. `starts` has one entry per part reached, the first at 0.
    static func filmedRanges(starts: [Double], walkBackAt: Double?, duration: Double) -> [(start: Double, end: Double)] {
        starts.indices.map { index -> (start: Double, end: Double) in
            let start = starts[index]
            let next = index + 1 < starts.count ? starts[index + 1] : (walkBackAt ?? duration)
            return (start: start, end: max(start, min(next, duration)))
        }
    }
}

/// What a part of a ONE TAKE counts as where you're filming: the take of its shot, and the role it fills.
struct OneTakeFill: Hashable {
    let part: OneTakePart
    let role: String?
    /// Whether it adds to what's still needed here, rather than being an extra.
    let adds: Bool

    /// "WIDE · Establishing", or "MATCH CUT".
    var title: String {
        guard let role, let match = part.shot.role(withID: role) else { return part.shot.title }
        return "\(part.shot.title) · \(match.title)"
    }
}

extension Trip {
    /// What each part of a ONE TAKE counts as where you are (1.24): for the shots with roles, the first of the part's
    /// roles not filmed yet here and not taken by an earlier part of the same take, or else its first role, as an extra.
    /// The shots tracked at each place (1.22) go by the place you're at; CLONE goes by the day.
    func oneTakePlan(_ parts: [OneTakePart], day number: Int, at place: PlaceNow?) -> [OneTakeFill] {
        var taken: Set<String> = []
        var result: [OneTakeFill] = []
        for part in parts {
            let slot = ShotSlot(shot: part.shot, half: nil)
            let coverage: SlotCoverage
            if part.shot.perPlace, let place {
                coverage = self.coverage(for: slot, day: number, at: place)
            } else {
                coverage = self.coverage(for: slot, day: number)
            }
            guard let firstRole = part.roleOrder.first else {
                let key = part.shot.rawValue
                result.append(OneTakeFill(part: part, role: nil, adds: !coverage.complete && !taken.contains(key)))
                taken.insert(key)
                continue
            }
            let covered = Set(coverage.roles.filter { $0.covered }.map { $0.role.id })
            let free = part.roleOrder.filter { !taken.contains(part.shot.rawValue + "." + $0) }
            let role = free.first(where: { !covered.contains($0) }) ?? free.first ?? firstRole
            taken.insert(part.shot.rawValue + "." + role)
            result.append(OneTakeFill(part: part, role: role, adds: coverage.openRoleIDs.contains(role)))
        }
        return result
    }
}

/// Which parts a ONE TAKE films, how long each one runs and MATCH CUT's move, remembered between takes.
struct OneTakeSetup: Codable, Equatable {
    /// Parts you've left out.
    var leftOut: [String] = []
    /// Seconds, for parts you've changed.
    var lengths: [String: Double] = [:]
    var move: Int = MatchMove.runAcross.rawValue

    func includes(_ part: OneTakePart) -> Bool {
        !leftOut.contains(part.rawValue)
    }

    func length(of part: OneTakePart) -> Double {
        lengths[part.rawValue] ?? part.defaultLength
    }

    var parts: [OneTakePart] {
        OneTakePart.allCases.filter { includes($0) }
    }

    var matchMove: MatchMove {
        let chosen = MatchMove(rawValue: move) ?? .runAcross
        return chosen.fitsOneTake ? chosen : .runAcross
    }

    /// Seconds for the parts together, before walking back.
    var total: Double {
        parts.reduce(0) { $0 + length(of: $1) }
    }

    mutating func toggle(_ part: OneTakePart) {
        if includes(part) {
            // Keep at least one part.
            guard parts.count > 1 else { return }
            leftOut.append(part.rawValue)
        } else {
            leftOut.removeAll { $0 == part.rawValue }
        }
    }

    /// The walkthrough: each part for its length, then walking back, which runs until you stop it.
    func steps() -> [GuideStep] {
        var clock = 0.0
        var steps: [GuideStep] = []
        for part in parts {
            let length = self.length(of: part)
            steps.append(GuideStep(start: clock, end: clock + length, text: part.text(move: matchMove)))
            clock += length
        }
        steps.append(GuideStep(start: clock, end: nil, text: OneTakePart.walkBackText))
        return steps
    }

    private static let key = "oneTake.setup"

    static func load() -> OneTakeSetup {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(OneTakeSetup.self, from: data) else {
            var fresh = OneTakeSetup()
            fresh.move = MatchCutStore.lastMove.fitsOneTake ? MatchCutStore.lastMove.rawValue : MatchMove.runAcross.rawValue
            return fresh
        }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// One part of a ONE TAKE as it was filmed: where it is in the clip, and the take of its shot it counts as.
struct ClipPart: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Its OneTakePart.
    var part: String
    var shot: String
    var take: Int
    var role: String? = nil
    /// MATCH CUT's move.
    var variant: String? = nil
    var inShot: Bool
    /// Seconds into the clip.
    var start: Double
    var end: Double
    /// Your verdict, like a take's: true is Usable, false Not usable, nil not checked yet.
    var usable: Bool? = nil

    var title: String {
        OneTakePart(rawValue: part)?.title ?? shot
    }

    /// The take it counts as: "WIDE · Establishing", "MATCH CUT · Run across" or "CLONE".
    var takeTitle: String {
        let type = ShotType(rawValue: shot)
        let name = type?.title ?? shot
        if let role, let match = type?.role(withID: role) {
            return "\(name) · \(match.title)"
        }
        if let variant {
            return "\(name) · \(variant)"
        }
        return name
    }
}

extension TakeDirector.OneTakeRun {
    /// The parts you reached, as filmed: where each is in the clip, and the take of its shot it counts as. A part
    /// under half a second (the take stopped just as it began) is left out. `firstTake` is the next take number of a
    /// shot on the day.
    func clipParts(duration: Double, fills: [OneTakeFill], firstTake: (ShotType) -> Int) -> [ClipPart] {
        let reached = Array(parts.prefix(starts.count))
        let ranges = OneTakePart.filmedRanges(starts: starts, walkBackAt: walkBackAt, duration: duration)
        var nextTakes: [ShotType: Int] = [:]
        var result: [ClipPart] = []
        for (index, part) in reached.enumerated() where index < ranges.count {
            let range = ranges[index]
            guard range.end - range.start >= 0.5 else { continue }
            let take = nextTakes[part.shot] ?? firstTake(part.shot)
            nextTakes[part.shot] = take + 1
            let fill = fills.first { $0.part == part }
            result.append(ClipPart(part: part.rawValue, shot: part.shot.rawValue, take: take, role: fill?.role,
                                   variant: part == .matchCut ? move.title : nil, inShot: part.inShot,
                                   start: range.start, end: range.end))
        }
        return result
    }
}

extension Clip {
    var isOneTake: Bool {
        shot == ShotType.oneTake.rawValue
    }

    /// This clip as takes of the shots it counts for: a ONE TAKE as itself and each of its parts as a take of its own
    /// shot (1.24), and any other clip as itself.
    var takes: [Clip] {
        guard isOneTake else { return [self] }
        return [self] + (parts ?? []).map { partTake($0) }
    }

    /// A ONE TAKE's part as a take of its shot, with the clip's place, time, light and check.
    func partTake(_ part: ClipPart) -> Clip {
        var take = self
        take.id = part.id
        take.shot = part.shot
        take.take = part.take
        take.variant = part.variant
        take.role = part.role
        take.recordedAt = recordedAt.addingTimeInterval(part.start)
        take.durationSeconds = max(0, part.end - part.start)
        // A part ends when you move on, so it isn't held to a planned length: it counts unless it's under 3 seconds.
        take.plannedLength = nil
        take.inShot = part.inShot
        // A part's own verdict, or else what you said about the whole take.
        take.usable = part.usable ?? usable
        take.favourite = false
        let inside = (marks ?? []).filter { $0 >= part.start && $0 < part.end }.map { $0 - part.start }
        take.marks = inside.isEmpty ? nil : inside
        take.parts = nil
        take.partOf = id
        return take
    }
}

extension Trip {
    /// Every take of every shot: the clips, with each ONE TAKE as itself and its parts (1.24). Coverage counts these.
    var allTakes: [Clip] {
        clips.flatMap { $0.takes }
    }
}
