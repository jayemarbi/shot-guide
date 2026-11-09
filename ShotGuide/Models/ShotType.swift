import Foundation

/// Phone in your hand (live prompts) or you in the shot (timeline first, clean screen).
enum ShotGroup: String, Codable {
    case inHand
    case inShot
}

enum LensChoice: String, Codable, CaseIterable {
    case ultraWide
    case wide
    case tele
    case front
}

/// Which way to hold the phone for a shot. Every reel is watched upright, so most shots are filmed that way, framed as
/// they'll be seen rather than cropped from a wide clip in the edit (1.25.1).
enum Filming {
    /// The big views, where the place is the star: filmed wide, so the grand scenes keep their width for the cinematic
    /// edits. An upright slice of a 4K landscape clip is still sharp enough for a full-screen reel.
    case landscape
    /// Everything else: you, people and things up close, and the moving shots, filmed as the reels play.
    case portrait
    /// Set by each version or role instead: REVEAL's versions and B-ROLL's roles go different ways (1.25.1).
    case either

    var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        case .either: return "Portrait or landscape"
        }
    }

    /// For the How it works card: "Landscape, on the tripod."
    var cardTitle: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        case .either: return "Portrait or landscape"
        }
    }

    var symbol: String {
        switch self {
        case .landscape: return "iphone.landscape"
        case .portrait: return "iphone"
        case .either: return "rotate.right"
        }
    }
}

/// What the phone is on for a shot.
enum Mount: Equatable {
    case tripod
    /// For smooth moving shots.
    case gimbal
    case handheld

    var title: String {
        switch self {
        case .tripod: return "Tripod"
        case .gimbal: return "Gimbal"
        case .handheld: return "Handheld"
        }
    }

    /// "Landscape, on the tripod."
    var phrase: String {
        switch self {
        case .tripod: return "on the tripod"
        case .gimbal: return "on the gimbal"
        case .handheld: return "handheld"
        }
    }
}

enum Stabilisation: String, Codable {
    case off
    case standard
    case cinematic
    case strongest
}

struct GuideStep: Hashable {
    let start: Double
    let end: Double?
    let text: String

    /// Rough times for the walkthrough, like "2–10 s" or, for long shots, "1–10 min".
    var rangeLabel: String {
        let whole = { (value: Double) in value.truncatingRemainder(dividingBy: 60) == 0 }
        if max(start, end ?? 0) >= 60, whole(start), end.map(whole) ?? true {
            if let end {
                return "\(Self.number(start / 60))–\(Self.number(end / 60)) min"
            }
            return "\(Self.number(start / 60)) min on"
        }
        if let end {
            return "\(Self.number(start))–\(Self.number(end)) s"
        }
        return "\(Self.number(start)) s on"
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The first few words, like "Walk smoothly towards it", for the prompt while you film (1.23): the text up to its
    /// first colon, full stop or semicolon.
    var headline: String {
        var cut = text.endIndex
        for mark in [": ", ". ", "; "] {
            if let range = text.range(of: mark), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        var words = String(text[..<cut])
        if words.hasSuffix(".") {
            words.removeLast()
        }
        return words.isEmpty ? text : words
    }
}

/// A zoom the app performs itself, in the zoom values shown on screen (like 0.5x to 2x).
struct ZoomRamp: Hashable {
    let from: Double
    let to: Double
    let startAt: Double
    let duration: Double
}

/// When a take starts and stops. Every shot has the same options, and the app remembers your choices for each shot.
struct ShotTiming: Codable, Equatable {
    /// Seconds to count down before recording starts. 0 starts straight away.
    var countdown: Int
    /// Stop after `length` seconds, or keep rolling until you stop it.
    var stopsByItself: Bool
    var length: Double
}

/// A guide drawn over the camera picture for some creative shots.
enum ShotOverlay {
    /// A crosshair to keep your target in the middle, for HYPERLAPSE.
    case crosshair
}

/// How the camera handles brightness for a shot.
enum ExposureStyle {
    case auto
    /// Focus and exposure lock when recording starts, so nothing shifts while you move around (CLONE, ONE TAKE).
    case lockAtStart
    /// Darker, so you stay black against the sky (SILHOUETTE).
    case silhouette
}

/// What the take check looks at after a take.
enum TakeCheckKind {
    /// Moving shots, where shake is part of the shot.
    case none
    /// Close-ups: steadiness only, as there's often no horizon.
    case steady
    case steadyAndLevel
}

/// Everything the camera screen needs to film one take of one shot.
struct ShotPlan {
    var shot: ShotType
    var take: Int
    var group: ShotGroup
    var lens: LensChoice = .wide
    var fps: Int = 30
    var stabilisation: Stabilisation = .standard
    var timelapseInterval: Double? = nil
    /// Where the timeline ends, for shots that stop by themselves unless you change it.
    var autoStop: Double? = nil
    /// A sensible length if you switch a you-stop-it shot to stop by itself.
    var manualLength: Double = 30
    var countdown: Int = 5
    var zoomRamp: ZoomRamp? = nil
    var before: String = ""
    var steps: [GuideStep] = []
    var variantName: String? = nil
    var overlay: ShotOverlay? = nil
    var exposure: ExposureStyle = .auto
    /// Added to the camera's exposure: brighter for snow, darker for silhouettes.
    var exposureBias: Float = 0
    /// Where you are in the frame, for the shots you're in. Shown under Setup on the How it works card.
    var placement: String? = nil
    /// What the phone is on: the tripod, the gimbal or your hand.
    var mount: Mount = .handheld
    /// The creative role this take is filmed for, for shots with roles (1.19).
    var role: CoverageRole? = nil
    /// How to hold the phone when the role changes it: WIDE's vertical hero is upright. nil is the shot's usual way.
    var filming: Filming? = nil

    var isInShot: Bool { group == .inShot }

    /// You're in it with the phone on the tripod, its back camera facing you: you can't see the screen (1.24).
    var facesAwayOnTripod: Bool {
        isInShot && mount == .tripod && lens != .front && timelapseInterval == nil
    }

    /// The flash (and, with headphones in, a voice) leads into each step while it records: the shots you're in on the
    /// tripod. Not DANCE, which the song leads, or HOME, often filmed in the dark (1.24).
    var signalsDuringTake: Bool {
        facesAwayOnTripod && shot != .dance && shot != .home
    }

    /// The screen dims from when you press record until the take ends, as nobody's looking at it (1.24).
    var dimsScreen: Bool {
        facesAwayOnTripod
    }

    var captureConfig: CaptureConfig {
        CaptureConfig(lens: lens, fps: fps, stabilisation: stabilisation, timelapseInterval: timelapseInterval,
                      exposureBias: exposureBias, playsMusic: shot == .dance, speaksPrompts: signalsDuringTake,
                      zoomsAcrossLenses: zoomRamp != nil, usesFlash: isInShot && lens != .front)
    }

    /// Phone-in-hand shots start straight away; shots you're in count you in.
    var defaultTiming: ShotTiming {
        ShotTiming(countdown: isInShot ? countdown : 0, stopsByItself: autoStop != nil, length: autoStop ?? manualLength)
    }

    /// The steps that start and stop a take, like getting going and easing to a stop, keep their length when it
    /// changes; the longer ones are the action, and stretch or shrink (1.23).
    static let shortStep: Double = 3

    /// The timeline fitted to how the take ends. With no end (you stop it yourself) the last step stays open.
    /// At the length the steps were written for, they're as written. At any other length the short steps (3 seconds
    /// or less) keep their length and the longer ones, the main action, share the rest in proportion, so a longer take
    /// means more of the action rather than a longer stop (1.23). When every step is short, or the take is shorter than
    /// the short steps together, they all change in proportion. Times are whole seconds, and the last step ends exactly
    /// at the end. Since 1.24 this goes for the shots you're in too: the flashes follow the steps, wherever they fall.
    func timeline(endingAt end: Double?) -> [GuideStep] {
        guard let end else {
            guard let last = steps.last else { return steps }
            return Array(steps.dropLast()) + [GuideStep(start: last.start, end: nil, text: last.text)]
        }
        guard let first = steps.first, end > first.start else { return steps }
        // Each step's length as written: to its end, the next step's start, or the end of the take.
        let lengths: [Double] = steps.indices.map { index in
            let step = steps[index]
            let stop = step.end ?? (index + 1 < steps.count ? steps[index + 1].start : end)
            return max(0, stop - step.start)
        }
        let written = lengths.reduce(0, +)
        if abs(first.start + written - end) < 0.01 {
            return steps.indices.map { index in
                GuideStep(start: steps[index].start, end: steps[index].start + lengths[index], text: steps[index].text)
            }
        }
        let room = end - first.start
        let fixed = lengths.filter { $0 <= Self.shortStep }.reduce(0, +)
        let stretchy = written - fixed
        let fitted: [Double]
        if stretchy > 0 && room > fixed {
            fitted = lengths.map { $0 <= Self.shortStep ? $0 : $0 * (room - fixed) / stretchy }
        } else if written > 0 {
            fitted = lengths.map { $0 * room / written }
        } else {
            fitted = lengths.map { _ in room / Double(lengths.count) }
        }
        var timeline: [GuideStep] = []
        var clock = first.start
        for index in steps.indices {
            let start = clock.rounded()
            clock += fitted[index]
            let stop = index == steps.count - 1 ? end : min(clock.rounded(), end)
            if stop > start {
                timeline.append(GuideStep(start: start, end: stop, text: steps[index].text))
            }
        }
        return timeline.isEmpty ? [GuideStep(start: first.start, end: end, text: first.text)] : timeline
    }
}

/// The shots, in no particular order. TripPhase sets the order they appear in on the trip page.
enum ShotType: String, CaseIterable, Codable, Identifiable {
    case onTheWay = "ONTHEWAY"
    case reaction = "REACTION"
    case reveal = "REVEAL"
    case timelapse = "TIMELAPSE"
    case wide = "WIDE"
    case walkaway = "WALKAWAY"
    case tele = "TELE"
    case moment = "MOMENT"
    case follow = "FOLLOW"
    case detail = "DETAIL"
    case food = "FOOD"
    case pov = "POV"
    case talk = "TALK"
    case ambient = "AMBIENT"
    case slomo = "SLOMO"
    case whip = "WHIP"
    /// Sound only, recorded on its own screen rather than the camera.
    case voiceover = "VOICEOVER"
    // Creative shots, filed in the day's order with the rest on the trip page.
    case matchCut = "MATCHCUT"
    case clone = "CLONE"
    case orbit = "ORBIT"
    case hyperlapse = "HYPERLAPSE"
    case silhouette = "SILHOUETTE"
    case reflection = "REFLECTION"
    case sounds = "SOUNDS"
    /// Animals up close, on the 5x.
    case wildlife = "WILDLIFE"
    /// At home or the gate, before you go and after you're back: the shots that start and end a reel.
    case home = "HOME"
    /// A few seconds of anything that shows the place, without you: the shots that fill out every reel.
    case bRoll = "BROLL"
    /// Dancing or lip-syncing to a song that plays in your AirPods, timed to the recording.
    case dance = "DANCE"
    /// Walking into where you're staying, for stay tours.
    case stay = "STAY"
    /// Several shots you're in, from one tripod set-up, in one long take (1.24). Its parts count as takes of their shots.
    case oneTake = "ONETAKE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onTheWay: return "ON THE WAY"
        case .matchCut: return "MATCH CUT"
        case .bRoll: return "B-ROLL"
        case .oneTake: return "ONE TAKE"
        default: return rawValue
        }
    }

    /// How many takes a day needs. For shots with roles (see Coverage.swift) it's how many different roles: the
    /// same role filmed twice is an extra, not two.
    var targetTakes: Int {
        switch self {
        case .reveal, .walkaway, .moment, .pov, .follow, .food, .whip, .wildlife: return 2
        case .wide, .talk, .onTheWay, .sounds: return 3
        case .detail: return 4
        case .bRoll: return 6
        default: return 1
        }
    }

    /// WHIP comes in two halves: Out ends a place, In starts the next.
    var isTransition: Bool { self == .whip }

    /// Often filmed inside, where the room's lights set the colour, so golden and blue hour leave them on automatic.
    var oftenIndoors: Bool { self == .food || self == .home || self == .stay }

    /// Whether the shot counts towards a day at all: core and full-day shots do (see `tier` in Coverage.swift).
    /// Extras depend on the day (a partner to follow, food, animals, an interesting trip there, somewhere special
    /// to stay), and the creative shots and TIMELAPSE are there whenever they're worth it.
    var countsTowardTotal: Bool {
        tier != .extra
    }

    /// Which way to hold the phone (1.25.1). The big views stay landscape, so the grand scenes keep their width;
    /// everything else is filmed upright, as the reels are watched. REVEAL and B-ROLL say for each version or role, and
    /// a few versions and roles go the other way from their shot (WIDE's vertical hero, MATCH CUT's snap). The camera
    /// records whichever way the phone is actually held.
    var filming: Filming {
        switch self {
        case .wide, .tele, .walkaway, .silhouette, .timelapse, .reflection, .matchCut, .onTheWay, .wildlife, .oneTake:
            return .landscape
        case .reveal, .bRoll:
            return .either
        default:
            return .portrait
        }
    }

    var defaultGroup: ShotGroup {
        switch self {
        case .reaction, .timelapse, .walkaway, .tele, .moment, .talk, .home: return .inShot
        case .matchCut, .clone, .silhouette, .dance, .oneTake: return .inShot
        default: return .inHand
        }
    }

    /// WIDE and SLOMO can be filmed in your hand or with you in them.
    var canToggleInShot: Bool { self == .wide || self == .slomo }

    var variants: [String] {
        switch self {
        case .reveal: return ["Auto zoom", "Walk reveal", "Tilt up"]
        case .talk: return ["Tripod", "Walking"]
        case .reaction: return ["1x", "0.5x"]
        case .matchCut: return MatchMove.allCases.map { $0.title }
        case .whip: return ["Out", "In"]
        case .home: return ["Before", "After"]
        default: return []
        }
    }

    /// Still shots get checked for shake and tilt, close-ups for shake only, and moving shots not at all.
    func takeCheck(variantName: String?) -> TakeCheckKind {
        switch self {
        case .wide, .tele, .slomo, .ambient, .timelapse, .moment, .walkaway, .matchCut, .clone, .silhouette, .dance, .oneTake:
            return .steadyAndLevel
        case .talk:
            return variantName == "Walking" ? .none : .steadyAndLevel
        case .reveal:
            return variantName == "Auto zoom" ? .steadyAndLevel : .none
        case .detail, .food, .reflection, .sounds, .wildlife, .home, .bRoll:
            return .steady
        default:
            return .none
        }
    }

    /// WHIP alternates: odd takes are the Out half, even takes the In half.
    func defaultVariant(forTake take: Int) -> Int {
        if isTransition { return take % 2 == 0 ? 1 : 0 }
        return 0
    }

    var summary: String {
        switch self {
        case .reaction: return "Your first look at the view"
        case .reveal: return "The view opens up"
        case .timelapse: return "Clouds, light or crowds, sped up"
        case .wide: return "The place, you in it, and another angle"
        case .walkaway: return "You walk into the scene"
        case .tele: return "You, small, under something huge"
        case .moment: return "Real moments, with the place and together"
        case .follow: return "Being led by the hand towards the view"
        case .onTheWay: return "The trip there: windows, roads, boats"
        case .food: return "Local food, close and slow"
        case .detail: return "Four different close-ups"
        case .pov: return "What your eyes see on the way"
        case .talk: return "Talking to camera, on the tripod or walking"
        case .ambient: return "30 seconds of pure sound"
        case .slomo: return "Water, waves or a jump in slow motion"
        case .whip: return "Whip pan from one place to the next"
        case .voiceover: return "Your voice, for narration and captions"
        case .matchCut: return "One move, done once at every place, cut together"
        case .clone: return "One long take of you all over the frame, for clones"
        case .orbit: return "A slow circle around your partner"
        case .hyperlapse: return "A slow walk, sped up into a glide"
        case .dance: return "Dance or lip-sync to your song, with the view behind you"
        case .silhouette: return "The two of you against the sunset"
        case .reflection: return "The scene doubled in still water"
        case .sounds: return "Close-ups made for their sound"
        case .wildlife: return "Animals up close, on the 5x"
        case .home: return "Before you go and after you're back"
        case .bRoll: return "Six different kinds of footage that show the place"
        case .stay: return "Walking into where you're staying"
        case .oneTake: return "WIDE, WALKAWAY, MOMENT, MATCH CUT and CLONE in one long take"
        }
    }

    /// The plan for a take. `role` is one of the shot's creative roles; nil picks its usual one (for WIDE, the
    /// one that matches `inShot`). REVEAL's role is its version.
    func plan(take: Int, inShot: Bool, variant: Int, role: String? = nil) -> ShotPlan {
        var plan = basePlan(take: take, inShot: inShot, variant: variant, role: role)
        if rolesAreVariants {
            let index = variants.isEmpty ? 0 : min(max(variant, 0), variants.count - 1)
            plan.role = index < roles.count ? roles[index] : nil
        } else {
            plan.role = resolvedRole(role, inShot: inShot)
        }
        plan.placement = placement(for: plan)
        plan.mount = mount(for: plan)
        return plan
    }

    /// The role a take is filmed for: the one asked for if it's one of this shot's, otherwise the usual one.
    func resolvedRole(_ id: String?, inShot: Bool) -> CoverageRole? {
        guard !roles.isEmpty else { return nil }
        if let id, let match = role(withID: id) {
            return match
        }
        if self == .wide {
            return role(withID: inShot ? "human-scale" : "establishing")
        }
        return roles.first
    }

    /// What the phone goes on: the tripod for still shots, the gimbal for smooth moving ones, your hand for the rest.
    private func mount(for plan: ShotPlan) -> Mount {
        switch self {
        case .reveal:
            return plan.variantName == variants.first ? .tripod : .gimbal
        case .talk:
            return plan.variantName == "Walking" ? .gimbal : .tripod
        case .wide, .slomo:
            return plan.isInShot ? .tripod : .handheld
        case .timelapse, .walkaway, .tele, .moment, .matchCut, .clone, .silhouette, .dance, .home, .oneTake:
            return .tripod
        case .follow, .pov, .orbit, .hyperlapse, .stay:
            return .gimbal
        default:
            return .handheld
        }
    }

    /// The mounts a shot can use across its versions, for the trip page: "Tripod", or "Handheld or tripod" for
    /// WIDE, which can be filmed with you in it.
    var mountSummary: String {
        let inShot = defaultGroup == .inShot
        var plans = [plan(take: 1, inShot: inShot, variant: 0)]
        if canToggleInShot {
            plans.append(plan(take: 1, inShot: !inShot, variant: 0))
        }
        for index in variants.indices.dropFirst() {
            plans.append(plan(take: 1, inShot: inShot, variant: index))
        }
        var mounts: [Mount] = []
        for candidate in plans where !mounts.contains(candidate.mount) {
            mounts.append(candidate.mount)
        }
        let words = mounts.enumerated().map { $0.offset == 0 ? $0.element.title : $0.element.title.lowercased() }
        return words.joined(separator: " or ")
    }

    /// Where you are in the frame, for the shots you're in.
    private func placement(for plan: ShotPlan) -> String? {
        let firstHalf = plan.variantName == variants.first
        switch self {
        case .reaction:
            return "Arm's length, the phone facing you, your face in the top half of the frame and the view coming in behind "
                + "you. Then the phone turns round to the view."
        case .wide:
            guard plan.isInShot else { return nil }
            if plan.role?.id == "vertical-hero" {
                return "Small, in the lower half of the upright frame and near the middle, with the view rising above you."
            }
            return "Small, on the left or right third line and low in the frame, with your back to the lens, looking out at the view."
        case .walkaway:
            return "Start just beside the phone, out of shot. Walk straight away from it into the view and stop on a third "
                + "line, small against it."
        case .tele:
            return "30 to 50 m out and tiny, on the bottom third: on a ridge, a rock or the shoreline, side-on or with your back "
                + "to the lens."
        case .moment:
            return "In the lower half of the frame, side-on to the lens, with the view filling the top."
        case .follow:
            return "Only your arm: it reaches into the bottom of the frame, holding their hand. They're a step ahead, in the middle."
        case .talk:
            return firstHalf
                ? "Head and shoulders, a little off centre, with your eyes on the top third line and the view behind you."
                : "Arm's length, a little above eye level, with your face in the top half of the frame and the trail or "
                    + "the view behind you."
        case .slomo:
            return plan.isInShot ? "In the middle of the frame where the action is: mid-jump, at the water's edge or under the spray." : nil
        case .matchCut:
            switch MatchMove.named(plan.variantName) ?? .runAcross {
            case .runAcross:
                return "Side-on, on the line you'll run along, in the middle of the frame while it finds your size. Then out "
                    + "of shot to the left, and across."
            case .leap:
                return "In the middle of the frame, with room above your head for the jump."
            case .armsOut:
                return "In the middle of the frame. Face the phone while it finds your size, then turn to the view."
            case .spin, .fallBack:
                return "In the middle of the frame, facing the phone."
            case .snap:
                return "Head and shoulders in the middle of the upright frame, looking at the lens."
            case .ridgeWalk:
                return "Tiny and side-on, on a ridge, a dune or the shoreline 30 to 50 m away, against the sky."
            }
        case .clone:
            return "A different spot each time, spread left and right and nearer and further away, as only two or three of "
                + "you fit side by side upright. Keep each spot clear of the ones before, so you don't overlap yourself."
        case .oneTake:
            return "You start behind the phone, out of shot. The parts take you out into the view and back again."
        case .silhouette:
            return "Low in the frame against the brightest part of the sky, side-on, a little apart so there's sky between you."
        case .dance:
            return "Full body in the middle of the upright frame, with space above your head and the view big behind you."
        case .home:
            return firstHalf
                ? "In the middle of the frame, doing the ordinary thing: zipping your bag, at the window, sitting at the gate."
                : "Lying in bed, your face lit by your phone, in the lower half of the frame."
        default:
            return nil
        }
    }

    /// Optional tips on the How it works card.
    var tips: [String] {
        switch self {
        case .onTheWay:
            return ["A car's side mirror with the road behind it makes a great frame.",
                    "Film from the shady side, and wipe the window first."]
        case .reaction:
            return ["Say what you'd really say. A real reaction beats a big one.",
                    "Turn the phone round slowly, so the view comes in smoothly.",
                    "1x keeps your face and the view behind you; 0.5x gets more of the place in."]
        case .reveal:
            return ["The closer the thing blocking the view, the bigger the reveal.",
                    "Golden hour reveals look best with the sun off to one side.",
                    "For Tilt up, start on something worth seeing on its own: clear water, rocks, flowers or your feet."]
        case .timelapse:
            return ["Clouds over peaks, shadows crossing a valley or a sunset work best.",
                    "Something still in the foreground, like a rock or a tree, makes the movement behind it stand out.",
                    "Plug in a power bank for long ones."]
        case .wide:
            return ["On the first WIDE of a place, leave sky above so there's room for a title.",
                    "Stand still. The stillness is what makes it look cinematic."]
        case .walkaway:
            return ["Walk slower than feels natural.",
                    "Follow a path or a ridge that leads into the view."]
        case .tele:
            return ["Put yourself under something huge, like a peak, a cliff or a waterfall. The 5x stacks it behind you.",
                    "Wear something bright, like red or orange, so you stand out when you're tiny."]
        case .moment:
            return ["Lie back in the grass, a kiss in front of the view, walking hand in hand, a slow spin.",
                    "Forget the camera and keep moving gently."]
        case .follow:
            return ["Keep your arm straight and the phone level.",
                    "Flat ground is smoothest. Steps make it bounce."]
        case .detail:
            return ["Look for texture and movement: water drops, grass in the wind, light through leaves.",
                    "Your hand touching something, like rock, water or a rail, makes it feel like you were there."]
        case .food:
            return ["Side light from a window looks best.",
                    "Catch the first bite, the pour or the steam."]
        case .pov:
            return ["Lie back in the grass and film your boots with the view beyond them.",
                    "Bend your knees and walk heel to toe to keep it smooth."]
        case .talk:
            return ["Say one specific thing: a fact, a feeling or a tip.",
                    "Smile first and leave a beat at the end. It gives the edit room.",
                    "Walking: go slower than feels natural, and keep the phone a little above your eyes."]
        case .ambient:
            return ["Turn your body to block the wind.",
                    "No talking or footsteps: the sound is the point."]
        case .slomo:
            return ["Bright light only. Slow motion goes grainy in the shade.",
                    "A jump into water, a splash or a hair flick all work."]
        case .whip:
            return ["Whip the same way in both halves, so the cut lines up.",
                    "Commit to it. A half-hearted whip doesn't hide the cut."]
        case .matchCut:
            return ["Keep one move for the whole trip, and across trips: it becomes your signature.",
                    "Your first take of a move sets your size. Tap New size if you want to start again.",
                    "Wear the same jacket each time so it reads as one journey."]
        case .clone:
            return ["Overcast light or shade works best, as shadows don't cut out.",
                    "Do something different at each spot.",
                    "The empty frame at the start and end is what the edit puts the clones on, so stay out of it."]
        case .orbit:
            return ["Keep them the same size all the way round.",
                    "Slower looks smoother."]
        case .hyperlapse:
            return ["Small, even steps, with the target in the crosshair.",
                    "Paths, bridges and boardwalks give it somewhere to go."]
        case .silhouette:
            return ["Clear shapes read best: arms out, a jump, holding hands.",
                    "Film in the 15 minutes either side of sunset, with the sun behind you."]
        case .reflection:
            return ["Calm water is best, often first thing in the morning.",
                    "Someone walking through the scene makes it."]
        case .sounds:
            return ["Footsteps on gravel, a splash, a zip, a can opening.",
                    "Block the wind with your body."]
        case .dance:
            return ["Know your part before you get there.",
                    "At each new spot, carry on from 10 seconds before where you stopped."]
        case .wildlife:
            return ["Never feed or follow an animal. Stay back and let the 5x get close.",
                    "Wait for a moment: a look up, a chew, a step."]
        case .home:
            return ["For the After half, turn the room lights off so it's just the phone's glow.",
                    "Keep it simple and quiet: these start and end a reel."]
        case .bRoll:
            return ["Things that move are best: people walking, flags, water, traffic, clouds.",
                    "Signs with the place's name are great for titles.",
                    "On the 5x, peaks and skies at different times of day can cut together behind one walk."]
        case .oneTake:
            return ["Your remote moves you on to the next part whenever you're ready.",
                    "Leave MATCH CUT or CLONE out when the spot doesn't suit them, and film them on their own further along.",
                    "A second ONE TAKE from a new spot fills the second roles: WIDE · Another angle and WALKAWAY · New "
                        + "spot or action.",
                    "Your moment counts as MOMENT · With the place. Film MOMENT · Together on its own, upright."]
        case .stay:
            return ["Film it the moment you arrive, before you unpack, with the curtains open and the lights on.",
                    "Walk in slowly and let your first reaction happen.",
                    "Afterwards, grab DETAIL shots of the best bits."]
        case .voiceover:
            return []
        }
    }

    private func basePlan(take: Int, inShot: Bool, variant: Int, role: String?) -> ShotPlan {
        let variantIndex = variants.isEmpty ? 0 : min(max(variant, 0), variants.count - 1)
        let variantName: String? = variants.isEmpty ? nil : variants[variantIndex]
        // The role's id, or "" for shots without roles (and REVEAL, whose role is its version).
        let roleID = rolesAreVariants ? "" : (resolvedRole(role, inShot: inShot)?.id ?? "")

        switch self {
        case .reaction:
            // The back camera, for the best picture, held facing you: you can't see the screen until you turn the
            // phone round to the view (1.24). 60 fps, so the moment can be slowed down.
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: variantIndex == 1 ? .ultraWide : .wide, fps: 60, stabilisation: .cinematic,
                autoStop: nil, manualLength: 40, countdown: 5,
                before: "Back camera, held at arm's length facing you, screen away. Start before you can see the view. "
                    + "Once you've reacted, turn the phone round to show what you're looking at, all in one take.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Walk up. Don't look at the view yet."),
                    GuideStep(start: 10, end: 20, text: "First look. React how you really feel."),
                    GuideStep(start: 20, end: 30, text: "Turn the phone round slowly to the view."),
                    GuideStep(start: 30, end: nil, text: "Hold on the view, then stop.")
                ],
                variantName: variantName)

        case .reveal:
            if variantIndex == 0 {
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .ultraWide, fps: 30, stabilisation: .cinematic,
                    autoStop: 10,
                    zoomRamp: ZoomRamp(from: 0.5, to: 2.0, startAt: 2, duration: 5),
                    before: "Point at your focal point: a peak, a waterfall. The app does the zoom.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Frame it wide and hold."),
                        GuideStep(start: 2, end: 7, text: "Zooming in. Keep the focal point centred."),
                        GuideStep(start: 7, end: 10, text: "Hold on the focal point.")
                    ],
                    variantName: variantName,
                    filming: .landscape)
            }
            if variantIndex == 2 {
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "Stand at the edge and point the phone down at the water, the rocks or your feet. "
                        + "Then tilt slowly up until the view fills the frame.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Hold on the water or the ground."),
                        GuideStep(start: 2, end: 8, text: "Tilt up slowly and evenly."),
                        GuideStep(start: 8, end: 10, text: "Hold on the view.")
                    ],
                    variantName: variantName,
                    filming: .portrait)
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .cinematic,
                autoStop: 11,
                before: "Find something in front of the view: a rock, trees, a ridge.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Start on something blocking the view."),
                    GuideStep(start: 2, end: 8, text: "Walk or rise slowly until it opens up."),
                    GuideStep(start: 8, end: 11, text: "Hold on the view.")
                ],
                variantName: variantName,
                filming: .portrait)

        case .timelapse:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .ultraWide, fps: 30, stabilisation: .off,
                timelapseInterval: 1, autoStop: nil, manualLength: 600, countdown: 5,
                before: "Tripod on solid ground. If the light is steady, hold on the screen to lock exposure.",
                steps: [
                    GuideStep(start: 0, end: 60, text: "Step back and leave the tripod alone."),
                    GuideStep(start: 60, end: 600, text: "Leave it running. 10 minutes makes 20 seconds of video."),
                    GuideStep(start: 600, end: nil, text: "That's plenty. Stop whenever you like.")
                ],
                variantName: "1 frame a second")

        case .wide:
            switch roleID {
            case "human-scale":
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .ultraWide, fps: 30, stabilisation: .off,
                    autoStop: 45, countdown: 10,
                    before: "Tripod. Use the 10-second countdown to walk to your spot, small in the frame. On your own or "
                        + "together.",
                    steps: [
                        GuideStep(start: 0, end: 5, text: "Stand still and look out at the view."),
                        GuideStep(start: 5, end: 40, text: "Do something natural: walk a few steps, look around, sit, point something out."),
                        GuideStep(start: 40, end: 45, text: "Hold still.")
                    ])
            case "alternative":
                if inShot {
                    return ShotPlan(
                        shot: self, take: take, group: .inShot,
                        lens: .wide, fps: 30, stabilisation: .off,
                        autoStop: 40, countdown: 10,
                        before: "Tripod somewhere new: higher, lower, further back or the other side, at 1x. Walk to your "
                            + "spot in the countdown.",
                        steps: [
                            GuideStep(start: 0, end: 5, text: "Get into your spot and look out."),
                            GuideStep(start: 5, end: 35, text: "Let the scene play: move a little, look around."),
                            GuideStep(start: 35, end: 40, text: "Hold still.")
                        ])
                }
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 25,
                    before: "Move before you film: higher, lower, further back or the other side. Or switch lens. If "
                        + "something's happening, like clouds moving or people passing, let it run longer, up to a minute.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Frame it and brace your elbows."),
                        GuideStep(start: 2, end: 23, text: "Hold still and let the scene develop."),
                        GuideStep(start: 23, end: 25, text: "Keep holding.")
                    ])
            case "vertical-hero":
                if inShot {
                    return ShotPlan(
                        shot: self, take: take, group: .inShot,
                        lens: .ultraWide, fps: 30, stabilisation: .off,
                        autoStop: 30, countdown: 10,
                        before: "Phone upright on the tripod. Walk to your spot in the countdown, small in the lower half of "
                            + "the frame.",
                        steps: [
                            GuideStep(start: 0, end: 5, text: "Stand still, facing the view."),
                            GuideStep(start: 5, end: 27, text: "Hold, or move slowly. Stay near the middle."),
                            GuideStep(start: 27, end: 30, text: "Hold still.")
                        ],
                        filming: .portrait)
                }
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .ultraWide, fps: 30, stabilisation: .cinematic,
                    autoStop: 20,
                    before: "Hold the phone upright. Horizon on the bottom third, the top third for sky and a title. Keep "
                        + "what matters near the middle: on TikTok and Reels, captions and buttons cover the bottom and "
                        + "right edges.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Frame it upright and brace."),
                        GuideStep(start: 2, end: 18, text: "Hold the frame. No panning."),
                        GuideStep(start: 18, end: 20, text: "Keep holding.")
                    ],
                    filming: .portrait)
            default:
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .ultraWide, fps: 30, stabilisation: .cinematic,
                    autoStop: 20,
                    before: "Show the whole place and its scale, with no one in it. Leave sky above for a title, and find "
                        + "something interesting for the foreground. A tripod helps.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Brace your elbows, or settle the tripod."),
                        GuideStep(start: 2, end: 18, text: "Hold the frame. No panning. Let the place breathe."),
                        GuideStep(start: 18, end: 20, text: "Keep holding.")
                    ])
            }

        case .walkaway:
            if roleID == "new-spot" {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .ultraWide, fps: 60, stabilisation: .off,
                    autoStop: 30, countdown: 5,
                    before: "Somewhere different from your first walk: a new path, a closer frame or another direction. "
                        + "Tripod at knee or hip height. This time, add an action: look back over your shoulder, take "
                        + "your partner's hand or stop right at the edge.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Empty frame. You're just out of shot beside the phone."),
                        GuideStep(start: 2, end: 16, text: "Walk in and keep going."),
                        GuideStep(start: 16, end: 22, text: "Stop and look out at the view."),
                        GuideStep(start: 22, end: 30, text: "Your action: look back over your shoulder, or reach for their hand.")
                    ])
            }
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .ultraWide, fps: 60, stabilisation: .off,
                autoStop: 30, countdown: 5,
                before: "Tripod at knee or hip height, with a path or ridge leading into the view.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Empty frame. You're just out of shot beside the phone."),
                    GuideStep(start: 2, end: 18, text: "Walk in and keep going. Don't look back."),
                    GuideStep(start: 18, end: 27, text: "Stop and look out at the view."),
                    GuideStep(start: 27, end: 30, text: "Hold still.")
                ])

        case .tele:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .tele, fps: 30, stabilisation: .off,
                autoStop: 40, countdown: 45,
                before: "Tripod. Use the 45-second countdown to walk 30–50 m out.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Stand still, facing the view."),
                    GuideStep(start: 10, end: 40, text: "Walk slowly across the frame.")
                ])

        case .moment:
            if roleID == "together" {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .wide, fps: 60, stabilisation: .off,
                    autoStop: 60, countdown: 10,
                    before: "Tripod, with the view behind you. Something real together: laughing, a kiss, walking hand in "
                        + "hand, a slow spin. On your own, a real reaction to the place. It films at 60 fps so the moment "
                        + "can be slowed down a little.",
                    steps: [
                        GuideStep(start: 0, end: 5, text: "Get comfortable. Don't look at the camera."),
                        GuideStep(start: 5, end: 55, text: "Have the moment. Keep it real and keep moving gently."),
                        GuideStep(start: 55, end: 60, text: "Hold still in the last moment.")
                    ])
            }
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: 60, countdown: 10,
                before: "Tripod, with the view behind you. Enjoy the place itself: touch the water, lie back in the grass, "
                    + "take in the view, explore. For a mountain that looms bigger, set up further back and use the zoom lens.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Get comfortable. Don't look at the camera."),
                    GuideStep(start: 5, end: 55, text: "Enjoy the place. Keep it real and keep moving gently."),
                    GuideStep(start: 55, end: 60, text: "Hold still in the last moment.")
                ])

        case .follow:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .strongest,
                autoStop: 15,
                before: "Your partner holds your hand and leads you towards the view. "
                    + "Film from your other hand, with their hand and the view in frame.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Their hand in yours, reaching back towards the lens."),
                    GuideStep(start: 2, end: 12, text: "Let them lead you. Keep your arm and the phone steady."),
                    GuideStep(start: 12, end: 15, text: "Slow down as the view opens up.")
                ])

        case .onTheWay:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .strongest,
                autoStop: 10,
                before: "The trip there: a plane window, the road ahead, a boat's wake, your bag going on. "
                    + "At a window, hold the phone close to the glass to cut reflections.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Frame it and hold steady."),
                    GuideStep(start: 2, end: 8, text: "Let the movement do the work. Keep the phone still."),
                    GuideStep(start: 8, end: 10, text: "Hold.")
                ])

        case .food:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 8,
                before: "Get close and tap the food to focus. Window light or outdoors looks best.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Start close on the food."),
                    GuideStep(start: 2, end: 6, text: "Slide slowly across it, or catch the first bite or pour."),
                    GuideStep(start: 6, end: 8, text: "Hold.")
                ])

        case .detail:
            switch roleID {
            case "object":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 6,
                    before: "Something that tells the story: a sign, a map, a ticket, your gear, a cup. Tap it to focus first.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Hold steady."),
                        GuideStep(start: 1, end: 5, text: "Hold, or slide very slowly."),
                        GuideStep(start: 5, end: 6, text: "Done.")
                    ])
            case "hands":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "Your hand touching something: rock, water, a rail, a leaf. Film with your other hand, close in.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Frame the spot, with your hand just out of shot."),
                        GuideStep(start: 2, end: 8, text: "Reach in and touch it slowly."),
                        GuideStep(start: 8, end: 10, text: "Hold.")
                    ])
            case "foreground":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "Get close to something sharp in front, like flowers, a fence or leaves, with the view soft behind it. "
                        + "Tap the close thing to focus.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Hold steady."),
                        GuideStep(start: 1, end: 7, text: "Hold, or slide slowly past it."),
                        GuideStep(start: 7, end: 8, text: "Done.")
                    ])
            case "only-here":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "A small detail you'd only find here: a carving, a local sign, a special plant. Tap it to focus first.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Hold steady."),
                        GuideStep(start: 1, end: 7, text: "Hold, or slide very slowly."),
                        GuideStep(start: 7, end: 8, text: "Done.")
                    ])
            case "nature":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "Swap-in for a detail this place doesn't have: a leaf, a flower, drops of water, an insect. Get close "
                        + "and tap it to focus.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Hold steady."),
                        GuideStep(start: 1, end: 7, text: "Hold still. Let it move if it's alive."),
                        GuideStep(start: 7, end: 8, text: "Done.")
                    ])
            default:
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "Get close to a surface: rock, bark, sand, ice or the water. Tap it to focus first.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Hold steady."),
                        GuideStep(start: 1, end: 7, text: "Hold, or slide very slowly across it."),
                        GuideStep(start: 7, end: 8, text: "Done.")
                    ])
            }

        case .pov:
            if roleID == "through" {
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .strongest,
                    autoStop: 20,
                    before: "Moving through the place: the forest, the market, along the water. Chest height, and look "
                        + "around as you go.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Start moving slowly."),
                        GuideStep(start: 2, end: 17, text: "Walk smoothly and look around: up, to the side, at what's there."),
                        GuideStep(start: 17, end: 20, text: "Ease to a stop.")
                    ])
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .strongest,
                autoStop: 15,
                before: "Heading towards something: the track ahead, the path to the view. Phone at chest height, pointing "
                    + "where you're going, with your feet, hands or the track in frame.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Start moving slowly."),
                    GuideStep(start: 2, end: 12, text: "Walk smoothly towards it: feet, hands, the track ahead."),
                    GuideStep(start: 12, end: 15, text: "Ease to a stop.")
                ])

        case .talk:
            if variantIndex == 1 {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .front, fps: 30, stabilisation: .strongest,
                    autoStop: nil, manualLength: 30, countdown: 3,
                    before: "Front camera, on the gimbal or at arm's length, mic clipped on. Walk slowly and talk to the "
                        + "lens like you're telling a friend about this place. Do three takes.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Start walking. Eyes on the lens."),
                        GuideStep(start: 2, end: 25, text: "Say where you are and why it's worth coming."),
                        GuideStep(start: 25, end: nil, text: "Slow down, hold a beat, then stop.")
                    ],
                    variantName: variantName)
            }
            // The front camera, like Walking, so you can see yourself (1.24).
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .front, fps: 30, stabilisation: .off,
                autoStop: nil, manualLength: 20, countdown: 5,
                before: "Front camera on the tripod at eye level, so you can see yourself, mic clipped on. Do three takes.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Look at the lens and smile."),
                    GuideStep(start: 2, end: 15, text: "Say one thing about this place."),
                    GuideStep(start: 15, end: nil, text: "Hold a beat, then stop.")
                ],
                variantName: variantName)

        case .ambient:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 30,
                before: "Point at the sound: water, wind in the trees, birds.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Point at the sound and hold."),
                    GuideStep(start: 2, end: 28, text: "Stay silent. Keep still."),
                    GuideStep(start: 28, end: 30, text: "Hold.")
                ])

        case .slomo:
            if inShot {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .wide, fps: 120, stabilisation: .off,
                    autoStop: 8, countdown: 5,
                    before: "Tripod. Bright light works best for slow motion.",
                    steps: [
                        GuideStep(start: 0, end: 3, text: "Get set."),
                        GuideStep(start: 3, end: 6, text: "Jump, splash or flick your hair."),
                        GuideStep(start: 6, end: 8, text: "Hold.")
                    ])
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 120, stabilisation: .standard,
                autoStop: 5,
                before: "Water, waves or a jump. Bright light works best.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Frame the action."),
                    GuideStep(start: 1, end: 4, text: "Keep still. Catch the moment."),
                    GuideStep(start: 4, end: 5, text: "Done.")
                ])

        case .whip:
            if variantIndex == 0 {
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .off,
                    autoStop: 3,
                    before: "This one ends a place. Hold on the scene, then whip the phone hard to the right.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Hold on the scene."),
                        GuideStep(start: 2, end: 3, text: "Whip fast to the right!")
                    ],
                    variantName: variantName)
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: 3,
                before: "This one starts the next place. Point left of the scene, then whip right, same as the Out half.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Whip fast to the right and land on the scene."),
                    GuideStep(start: 1, end: 3, text: "Hold steady.")
                ],
                variantName: variantName)

        case .voiceover:
            // Recorded by VoiceoverView, which shows these as talking points.
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: nil, manualLength: 60, countdown: 0,
                before: "Somewhere quiet, like the car on the way back. Hold the phone a hand's width from your mouth.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Where you are and how you got here."),
                    GuideStep(start: 10, end: 25, text: "What it was like. The moment that got you."),
                    GuideStep(start: 25, end: nil, text: "One tip for anyone going. Stop when you're done.")
                ])

        case .wildlife:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .tele, fps: 60, stabilisation: .cinematic,
                autoStop: nil, manualLength: 20,
                before: "Stay well back and let the 5x get you close. Brace your elbows on a rock, a rail or your knees, "
                    + "or use the tripod.",
                steps: [
                    GuideStep(start: 0, end: 3, text: "Frame it with room on the side it's facing."),
                    GuideStep(start: 3, end: 15, text: "Hold steady. Wait for it to look up, chew or move."),
                    GuideStep(start: 15, end: nil, text: "Keep rolling while it's doing something. Stop when it's done.")
                ])

        case .home:
            let leaving = variantIndex == 0
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 20, countdown: 5,
                before: leaving
                    ? "Before you go. Prop the phone on a shelf, a bench or the tripod. Ideas: zipping up your bag, "
                        + "a last look out the window, waiting at the gate."
                    : "After you're back. Prop the phone on the bedside table or the tripod. Lie in bed at night, "
                        + "lit only by your phone, scrolling through the trip.",
                steps: [
                    GuideStep(start: 0, end: 3, text: "Get settled. Don't look at the lens."),
                    GuideStep(start: 3, end: 17, text: leaving
                              ? "Get ready to go: pack, look out, wait."
                              : "Scroll, smile at the screen, stare at the ceiling."),
                    GuideStep(start: 17, end: 20, text: "Hold still.")
                ],
                variantName: variantName)

        case .bRoll:
            switch roleID {
            case "people":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "Someone doing something: walkers, a guide, a market stall, people at the lookout. Small or from behind "
                        + "is fine.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 10, text: "Hold still and let them move through.")
                    ],
                    filming: .portrait)
            case "movement":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "Something moving through the frame: traffic, flags, waves, birds, a train. Hold still and let it move.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 10, text: "Hold still. Let it move through the frame.")
                    ],
                    filming: .landscape)
            case "local":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "What makes this place this place: a sign with its name, a landmark, buildings, local things.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it with the subject in the middle."),
                        GuideStep(start: 1, end: 8, text: "Hold still, or drift very slowly.")
                    ],
                    filming: .portrait)
            case "lens-angle":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .tele, fps: 60, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "A contrasting look: the 5x on something far away, or go very low, very high or film through something.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 10, text: "Hold very still. Long lenses show every shake.")
                    ],
                    filming: .landscape)
            case "transition":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 6,
                    before: "A shot that moves the edit on: walk past something close to the lens, a door opening, a slow pan away, "
                        + "a car passing close.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Get ready."),
                        GuideStep(start: 1, end: 6, text: "Let something pass close to the lens, or pan away.")
                    ],
                    filming: .portrait)
            case "nature":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 10,
                    before: "Swap-in for a role this place doesn't have: plants, animals or water, something alive in the scene.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 10, text: "Hold still, or drift very slowly.")
                    ],
                    filming: .portrait)
            case "into-light":
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 8,
                    before: "Swap-in for a role this place doesn't have: face the sun for flare, glowing edges or silhouettes. Keep "
                        + "the sun just behind something.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 8, text: "Hold still, or drift slowly past the sun.")
                    ],
                    filming: .portrait)
            default:
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 60, stabilisation: .cinematic,
                    autoStop: 12,
                    before: "Light, weather and mood: mist, clouds, sun through the trees, rain on water. Hold still and let it be.",
                    steps: [
                        GuideStep(start: 0, end: 1, text: "Frame it and hold."),
                        GuideStep(start: 1, end: 12, text: "Hold still. Let the light and weather do the work.")
                    ],
                    filming: .landscape)
            }

        case .stay:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .ultraWide, fps: 30, stabilisation: .cinematic,
                autoStop: nil, manualLength: 30,
                before: "Somewhere special to stay? Film it the moment you arrive. Start outside with the door shut, then "
                    + "walk in slowly with it rolling and say what you really think.",
                steps: [
                    GuideStep(start: 0, end: 3, text: "Hold on the door, then open it."),
                    GuideStep(start: 3, end: 15, text: "Walk in slowly. Say what you really think."),
                    GuideStep(start: 15, end: nil, text: "Show the best bits: the view, the bed, the bath. Stop when you're done.")
                ])

        default:
            return creativePlan(take: take, variant: variantIndex, variantName: variantName)
        }
    }

    /// The creative shots.
    private func creativePlan(take: Int, variant: Int, variantName: String?) -> ShotPlan {
        switch self {
        case .matchCut:
            return Self.matchCutPlan(take: take, move: MatchMove(rawValue: variant) ?? .runAcross)

        case .clone:
            // One long take with everything locked: you all over the frame, and empty at the start and end, for the edit
            // to make the clones (1.24).
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 180, countdown: 10,
                before: "Tripod only: the phone can't move at all. Focus, exposure and white balance lock when recording "
                    + "starts. Start with the frame empty, then go about the scene doing different things in different "
                    + "spots: 5 flashes mean it's time for a new one. Walk out at the end and leave it empty. The edit "
                    + "makes the clones.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Empty frame. Stay out of shot beside the phone."),
                    GuideStep(start: 10, end: 40, text: "Walk in to your first spot and do something: sit, look out, take a photo."),
                    GuideStep(start: 40, end: 70, text: "New spot: something different."),
                    GuideStep(start: 70, end: 100, text: "New spot: something different."),
                    GuideStep(start: 100, end: 130, text: "New spot: something different."),
                    GuideStep(start: 130, end: 160, text: "New spot: something different."),
                    GuideStep(start: 160, end: 180, text: "Walk out of the frame and leave it empty.")
                ],
                exposure: .lockAtStart)

        case .oneTake:
            // The parts you've chosen, each counting as a take of its shot. The camera screen builds the steps from
            // your parts and lengths; these are the usual ones (1.24).
            let setup = OneTakeSetup()
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .ultraWide, fps: 60, stabilisation: .off,
                autoStop: nil, manualLength: setup.total, countdown: 10,
                before: "Tripod at hip height, landscape, the view in front. Tap a part to leave it out, or change how long it "
                    + "runs: each part counts as a take of its shot. Focus, exposure and white balance lock when it starts, "
                    + "so every part matches. It keeps rolling after the last part to catch you walking back: stop it when "
                    + "you get there.",
                steps: setup.steps(),
                exposure: .lockAtStart)

        case .orbit:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .strongest,
                autoStop: 10,
                before: "Your partner stands still, 1.5 to 2 metres away. Phone at chest height, elbows in, knees bent.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Hold, with them in the middle."),
                    GuideStep(start: 1, end: 9, text: "Walk sideways in a slow arc. Keep them centred and the same distance away."),
                    GuideStep(start: 9, end: 10, text: "Hold.")
                ])

        case .hyperlapse:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .ultraWide, fps: 30, stabilisation: .strongest,
                autoStop: 60,
                before: "Pick something straight ahead to aim at, like a tree, a sign or the lookout rail. "
                    + "Small, smooth steps. It needs good light.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Put your target in the crosshair."),
                    GuideStep(start: 2, end: 58, text: "Walk slowly. Keep the target in the crosshair. Don't turn."),
                    GuideStep(start: 58, end: 60, text: "Ease to a stop.")
                ],
                overlay: .crosshair)

        case .silhouette:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 20, countdown: 10,
                before: "Tripod low, so you're against the sky. Best in the 15 minutes either side of sunset, with the sun "
                    + "behind you. The picture is darkened so you stay black against the sky.",
                steps: [
                    GuideStep(start: 0, end: 3, text: "Walk in and stand side-on, a little apart."),
                    GuideStep(start: 3, end: 17, text: "Move slowly: hold hands, a spin, a kiss, a jump."),
                    GuideStep(start: 17, end: 20, text: "Hold your last pose.")
                ],
                exposure: .silhouette)

        case .reflection:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .ultraWide, fps: 30, stabilisation: .standard,
                autoStop: 12,
                before: "Turn the phone to landscape so the camera is in a bottom corner, 1 to 2 cm above still water. "
                    + "Don't let it touch.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Frame half reflection, half scene."),
                    GuideStep(start: 2, end: 10, text: "Hold still. Someone walking through looks great."),
                    GuideStep(start: 10, end: 12, text: "Hold.")
                ])

        case .dance:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: nil, manualLength: 60, countdown: 10,
                before: "Tripod, phone upright, set back far enough for all of you with the view behind. Put your AirPods "
                    + "in: the song starts during the countdown, so your part lands as recording starts. At each new spot, "
                    + "carry on from 10 seconds before where you stopped, or dance it from the top.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "In position as your part of the song comes in."),
                    GuideStep(start: 2, end: nil,
                              text: "Dance or lip-sync. Stop with your remote or the red button, or let the song finish.")
                ])

        default:
            // SOUNDS. Wind noise reduction and stereo are on for every clip that records sound.
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 8,
                before: "Get the phone 20 to 50 cm from the sound: footsteps, a splash, a can opening, a zip. No talking. "
                    + "Block the wind with your body.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Quiet."),
                    GuideStep(start: 2, end: 6, text: "Make the sound once."),
                    GuideStep(start: 6, end: 8, text: "Quiet again.")
                ])
        }
    }
}

extension ShotType {
    /// MATCH CUT, one plan per move (1.24). The tripod moves share ONE TAKE's set-up (0.5x, 60 fps), so a move filmed
    /// in a ONE TAKE matches the same move filmed on its own. Before the countdown, the camera finds you and zooms to
    /// the size you were in your first take of the move, so the 5 flashes come once you're framed.
    static func matchCutPlan(take: Int, move: MatchMove) -> ShotPlan {
        let lead = "Tripod at hip height. Press record and stand where you'll do it, facing the phone: while the light's "
            + "on, it zooms to the size you were in your first take of this move. When the light goes off, 5 flashes, "
            + "then it's rolling."
        func make(lens: LensChoice = .ultraWide, fps: Int = 60, autoStop: Double, before: String,
                  steps: [GuideStep], filming: Filming? = nil) -> ShotPlan {
            ShotPlan(shot: .matchCut, take: take, group: .inShot,
                     lens: lens, fps: fps, stabilisation: .off,
                     autoStop: autoStop, countdown: 5,
                     before: before, steps: steps, variantName: move.title, filming: filming)
        }
        switch move {
        case .runAcross:
            return make(
                autoStop: 15,
                before: lead + " Then walk out of shot to the left, and run across on the flashes.",
                steps: [
                    GuideStep(start: 0, end: 8, text: "Walk out of shot to the left."),
                    GuideStep(start: 8, end: 13, text: "Run across the frame and out the right."),
                    GuideStep(start: 13, end: 15, text: "Stay out of shot.")
                ])
        case .leap:
            return make(
                autoStop: 10,
                before: lead,
                steps: [
                    GuideStep(start: 0, end: 5, text: "Stand in the middle, ready."),
                    GuideStep(start: 5, end: 8, text: "Leap, once, as big as you can."),
                    GuideStep(start: 8, end: 10, text: "Land and hold.")
                ])
        case .armsOut:
            return make(
                autoStop: 12,
                before: lead + " Then turn to face the view.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Turn to the view, arms down."),
                    GuideStep(start: 5, end: 10, text: "Raise your arms out wide, slowly."),
                    GuideStep(start: 10, end: 12, text: "Hold.")
                ])
        case .spin:
            return make(
                autoStop: 10,
                before: lead,
                steps: [
                    GuideStep(start: 0, end: 5, text: "Stand facing the phone."),
                    GuideStep(start: 5, end: 8, text: "Spin round once."),
                    GuideStep(start: 8, end: 10, text: "Hold.")
                ])
        case .fallBack:
            return make(
                autoStop: 10,
                before: lead + " Somewhere soft behind you: grass, sand or snow.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Stand facing the phone, the soft ground behind you."),
                    GuideStep(start: 5, end: 8, text: "Fall backwards."),
                    GuideStep(start: 8, end: 10, text: "Lie still.")
                ])
        case .snap:
            return make(
                lens: .wide, autoStop: 8,
                before: "Phone upright on the tripod at chest height, close in. Press record and look at the lens: while "
                    + "the light's on, it zooms to the size you were in your first Snap. When it goes off, 5 flashes, then "
                    + "it's rolling.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Look at the lens."),
                    GuideStep(start: 5, end: 6, text: "Snap!"),
                    GuideStep(start: 6, end: 8, text: "Hold.")
                ],
                filming: .portrait)
        case .ridgeWalk:
            return make(
                lens: .tele, fps: 30, autoStop: 25,
                before: "Tripod facing a ridge, a dune or a shoreline 30 to 50 m away. Press record and walk out with the light "
                    + "on: when you stop, it zooms to the size you were in your first Ridge walk, and the light goes off. "
                    + "Then 5 flashes, and walk.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Stand still, side-on."),
                    GuideStep(start: 5, end: 25, text: "Walk slowly along the ridge, at an even pace.")
                ])
        }
    }
}
