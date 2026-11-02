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

/// Which way to hold the phone for a shot.
enum Filming {
    /// The place is the star: filmed wide, for the letterboxed, cinematic edits.
    case sideways
    /// You talking or up close: filmed tall, for full-screen reels.
    case upright
    /// Whichever suits.
    case either

    var title: String {
        switch self {
        case .sideways: return "Sideways"
        case .upright: return "Upright"
        case .either: return "Either way"
        }
    }

    var symbol: String {
        switch self {
        case .sideways: return "iphone.landscape"
        case .upright: return "iphone"
        case .either: return "rotate.right"
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
    /// A see-through still of your last MATCH CUT, to line the next one up.
    case ghost
    /// A box to keep the person the same size in, for DOLLY ZOOM.
    case sizeBox
    /// A crosshair to keep your target in the middle, for HYPERLAPSE.
    case crosshair
}

/// How the camera handles brightness for a shot.
enum ExposureStyle {
    case auto
    /// Focus and exposure lock when recording starts, so nothing shifts while you move around (CLONE).
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
    /// Seconds into the take when the flash blinks, to tell you to move.
    var flashCues: [Double] = []
    var exposure: ExposureStyle = .auto
    /// Added to the camera's exposure: brighter for snow, darker for silhouettes.
    var exposureBias: Float = 0
    /// Where you are in the frame, for the shots you're in. Shown under Setup on the How it works card.
    var placement: String? = nil

    var isInShot: Bool { group == .inShot }

    var captureConfig: CaptureConfig {
        CaptureConfig(lens: lens, fps: fps, stabilisation: stabilisation, timelapseInterval: timelapseInterval,
                      exposureBias: exposureBias, playsMusic: shot == .dance)
    }

    /// Phone-in-hand shots start straight away; shots you're in count you in.
    var defaultTiming: ShotTiming {
        ShotTiming(countdown: isInShot ? countdown : 0, stopsByItself: autoStop != nil, length: autoStop ?? manualLength)
    }

    /// The timeline fitted to how the take ends: the last step runs to the chosen length,
    /// or stays open when you stop it yourself. Steps after a shorter length are dropped.
    func timeline(endingAt end: Double?) -> [GuideStep] {
        guard let end else {
            guard let last = steps.last else { return steps }
            return Array(steps.dropLast()) + [GuideStep(start: last.start, end: nil, text: last.text)]
        }
        var kept = steps.filter { $0.start < end }
        if let last = kept.last {
            kept[kept.count - 1] = GuideStep(start: last.start, end: end, text: last.text)
        }
        return kept
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
    case transition = "TRANSITION"
    case secondAngle = "SECONDANGLE"
    case bodyWipe = "BODYWIPE"
    case whip = "WHIP"
    /// Sound only, recorded on its own screen rather than the camera.
    case voiceover = "VOICEOVER"
    // Creative shots: extras for creative edits.
    case matchCut = "MATCHCUT"
    case clone = "CLONE"
    case jump = "JUMP"
    case rise = "RISE"
    case orbit = "ORBIT"
    case dollyZoom = "DOLLYZOOM"
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
    /// Quick clip: straight to recording with no guidance, for moments that won't wait.
    case quick = "QUICK"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secondAngle: return "SECOND ANGLE"
        case .bodyWipe: return "BODY WIPE"
        case .onTheWay: return "ON THE WAY"
        case .matchCut: return "MATCH CUT"
        case .dollyZoom: return "DOLLY ZOOM"
        case .quick: return "QUICK CLIP"
        case .bRoll: return "B-ROLL"
        default: return rawValue
        }
    }

    var targetTakes: Int {
        switch self {
        case .reveal, .wide, .walkaway, .moment, .follow, .food, .transition, .bodyWipe, .whip, .jump, .wildlife: return 2
        case .detail, .talk, .onTheWay, .sounds: return 3
        case .bRoll: return 6
        default: return 1
        }
    }

    /// Transitions come in two halves: Out ends a place, In starts the next.
    var isTransition: Bool { self == .transition || self == .bodyWipe || self == .whip || self == .jump }

    /// Extras depend on the day (a partner to follow, food, animals, an interesting trip there), so they
    /// don't count towards a trip's total. Nor do the transitions, the creative shots, SECOND ANGLE and quick
    /// clips. MATCH CUT and SILHOUETTE count: the saved reels use them a lot.
    var countsTowardTotal: Bool {
        switch self {
        case .bodyWipe, .whip, .transition, .follow, .food, .onTheWay, .voiceover, .wildlife, .home, .secondAngle: return false
        case .clone, .jump, .rise, .orbit, .dollyZoom, .hyperlapse, .reflection, .sounds, .dance, .quick:
            return false
        default: return true
        }
    }

    /// Which way to hold the phone. The big views go sideways, for the cinematic edits; you talking or up close
    /// stays upright, for full-screen reels.
    var filming: Filming {
        switch self {
        case .wide, .tele, .walkaway, .moment, .silhouette, .timelapse, .reflection, .matchCut, .onTheWay, .wildlife, .home,
             .bRoll:
            return .sideways
        case .talk, .reaction, .pov, .food, .follow, .transition, .whip, .bodyWipe, .jump:
            return .upright
        default:
            return .either
        }
    }

    var defaultGroup: ShotGroup {
        switch self {
        case .reaction, .timelapse, .walkaway, .tele, .moment, .talk, .secondAngle, .bodyWipe, .home: return .inShot
        case .matchCut, .clone, .jump, .silhouette, .dance: return .inShot
        default: return .inHand
        }
    }

    /// WIDE and SLOMO can be filmed in your hand or with you in them.
    var canToggleInShot: Bool { self == .wide || self == .slomo }

    var variants: [String] {
        switch self {
        case .reveal: return ["Auto zoom", "Walk reveal"]
        case .transition, .bodyWipe, .whip, .jump: return ["Out", "In"]
        case .home: return ["Before", "After"]
        default: return []
        }
    }

    /// Still shots get checked for shake and tilt, close-ups for shake only, and moving shots not at all.
    func takeCheck(variantName: String?) -> TakeCheckKind {
        switch self {
        case .wide, .tele, .slomo, .ambient, .timelapse, .talk, .moment, .walkaway, .secondAngle, .bodyWipe, .transition,
             .matchCut, .clone, .jump, .silhouette, .dance:
            return .steadyAndLevel
        case .reveal:
            return variantName == "Auto zoom" ? .steadyAndLevel : .none
        case .detail, .food, .reflection, .sounds, .wildlife, .home, .bRoll:
            return .steady
        default:
            return .none
        }
    }

    /// Transitions alternate: odd takes are the Out half, even takes the In half.
    func defaultVariant(forTake take: Int) -> Int {
        if isTransition { return take % 2 == 0 ? 1 : 0 }
        return 0
    }

    var summary: String {
        switch self {
        case .reaction: return "Your first look at the view"
        case .reveal: return "The view opens up"
        case .timelapse: return "Clouds, light or crowds, sped up"
        case .wide: return "The whole place and its scale"
        case .walkaway: return "You walk into the scene"
        case .tele: return "You, small, under something huge"
        case .moment: return "A real moment together, filmed from the tripod"
        case .follow: return "Being led by the hand towards the view"
        case .onTheWay: return "The trip there: windows, roads, boats"
        case .food: return "Local food, close and slow"
        case .detail: return "Close-ups and textures"
        case .pov: return "What your eyes see on the way"
        case .talk: return "One line to camera"
        case .ambient: return "20 seconds of pure sound"
        case .slomo: return "Water, waves or a jump in slow motion"
        case .transition: return "Cover and uncover the lens"
        case .secondAngle: return "You getting the hero shot"
        case .bodyWipe: return "Walk past the lens into the next place"
        case .whip: return "Whip pan from one place to the next"
        case .voiceover: return "Your voice, for narration and captions"
        case .matchCut: return "The same pose at every spot, cut together"
        case .clone: return "Three of you in one frame"
        case .jump: return "Jump out of one place and into the next"
        case .rise: return "Rise from behind something to reveal the view"
        case .orbit: return "A slow circle around your partner"
        case .dollyZoom: return "Walk back while the app zooms in"
        case .hyperlapse: return "A slow walk, sped up into a glide"
        case .dance: return "Dance or lip-sync to your song, with the view behind you"
        case .silhouette: return "The two of you against the sunset"
        case .reflection: return "The scene doubled in still water"
        case .sounds: return "Close-ups made for their sound"
        case .wildlife: return "Animals up close, on the 5x"
        case .home: return "Before you go and after you're back"
        case .bRoll: return "5 seconds of anything that shows the place"
        case .quick: return "Straight to recording, no guidance"
        }
    }

    func plan(take: Int, inShot: Bool, variant: Int) -> ShotPlan {
        var plan = basePlan(take: take, inShot: inShot, variant: variant)
        plan.placement = placement(for: plan)
        return plan
    }

    /// Where you are in the frame, for the shots you're in.
    private func placement(for plan: ShotPlan) -> String? {
        let firstHalf = plan.variantName == variants.first
        switch self {
        case .reaction:
            return "Arm's length, your face in the top half of the frame. As you turn, the view comes in behind you."
        case .wide:
            return plan.isInShot
                ? "Small, on the left or right third line and low in the frame, with your back to the lens, looking out at the view."
                : nil
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
            return "Head and shoulders, a little off centre, with your eyes on the top third line and the view behind you."
        case .slomo:
            return plan.isInShot ? "In the middle of the frame where the action is: mid-jump, at the water's edge or under the spray." : nil
        case .secondAngle:
            return "In the middle of the frame, side-on, so your other camera and the view you're filming are both in shot."
        case .bodyWipe:
            return firstHalf
                ? "Just out of shot on the left to start, then walking past the lens close enough to fill the whole frame."
                : "Right in front of the lens, filling the frame, then walking off to the right into the scene."
        case .matchCut:
            return "Exactly where your see-through outline was last time: the same spot, the same size, the same pose."
        case .clone:
            return "Three spots across the frame that don't overlap, all about the same distance from the phone."
        case .jump:
            return "In the middle, with the top edge of the frame just above your head."
        case .silhouette:
            return "Low in the frame against the brightest part of the sky, side-on, a little apart so there's sky between you."
        case .dance:
            return "Full body in the middle third of the frame, with space above your head and the view big behind you."
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
                    "Turn so the view ends up behind you, not beside you."]
        case .reveal:
            return ["The closer the thing blocking the view, the bigger the reveal.",
                    "Golden hour reveals look best with the sun off to one side."]
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
                    "Smile first and leave a beat at the end. It gives the edit room."]
        case .ambient:
            return ["Turn your body to block the wind.",
                    "No talking or footsteps: the sound is the point."]
        case .slomo:
            return ["Bright light only. Slow motion goes grainy in the shade.",
                    "A jump into water, a splash or a hair flick all work."]
        case .transition, .bodyWipe, .whip, .jump:
            return ["Move the same way in both halves, so the cut lines up.",
                    self == .bodyWipe ? "A dark top wipes cleanest." : "Commit to it. A half-hearted move doesn't hide the cut."]
        case .secondAngle:
            return ["Good for a behind-the-scenes or how-I-got-the-shot reel."]
        case .matchCut:
            return ["Pick one pose, like arms out or a jump, and repeat it at every stop.",
                    "Wear the same jacket each time so it reads as one journey."]
        case .clone:
            return ["Overcast light or shade works best, as shadows don't cut out.",
                    "Do something different at each spot."]
        case .rise:
            return ["Rise with your legs, not your arms.",
                    "The closer the foreground, the bigger the reveal."]
        case .orbit:
            return ["Keep them the same size all the way round.",
                    "Slower looks smoother."]
        case .dollyZoom:
            return ["A far-off background, like mountains, shows the effect best.",
                    "Check the ground behind you before you start."]
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
                    "Signs with the place's name are great for titles."]
        case .voiceover, .quick:
            return []
        }
    }

    private func basePlan(take: Int, inShot: Bool, variant: Int) -> ShotPlan {
        let variantIndex = variants.isEmpty ? 0 : min(max(variant, 0), variants.count - 1)
        let variantName: String? = variants.isEmpty ? nil : variants[variantIndex]

        switch self {
        case .reaction:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .front, fps: 30, stabilisation: .standard,
                autoStop: nil, manualLength: 40, countdown: 3,
                before: "Front camera at arm's length. Start before you can see the view.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Walk up. Don't look at the view yet."),
                    GuideStep(start: 10, end: 20, text: "First look. React how you really feel."),
                    GuideStep(start: 20, end: 30, text: "Keep rolling. Look between the view and the lens."),
                    GuideStep(start: 30, end: nil, text: "Stop when you're ready.")
                ])

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
                    variantName: variantName)
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
                variantName: variantName)

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
            let lens: LensChoice = take % 2 == 0 ? .wide : .ultraWide
            if inShot {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: lens, fps: 30, stabilisation: .off,
                    autoStop: 12, countdown: 10,
                    before: "Tripod. Use the 10-second countdown to walk to your spot, and stand small in the frame.",
                    steps: [
                        GuideStep(start: 0, end: 10, text: "Stand still and look out at the view."),
                        GuideStep(start: 10, end: 12, text: "Hold.")
                    ])
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: lens, fps: 30, stabilisation: .cinematic,
                autoStop: 12,
                before: lens == .ultraWide ? "Show the whole place and its scale." : "Same again at 1x.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Brace your elbows."),
                    GuideStep(start: 2, end: 10, text: "Hold the frame. No panning."),
                    GuideStep(start: 10, end: 12, text: "Keep holding.")
                ])

        case .walkaway:
            let lookBack = take % 2 == 0
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .ultraWide, fps: 60, stabilisation: .off,
                autoStop: 16, countdown: 5,
                before: lookBack
                    ? "Tripod at knee or hip height. This take, look back over your shoulder."
                    : "Tripod at knee or hip height.",
                steps: lookBack
                    ? [
                        GuideStep(start: 0, end: 2, text: "Empty frame. You're just out of shot beside the phone."),
                        GuideStep(start: 2, end: 10, text: "Walk in and keep going."),
                        GuideStep(start: 10, end: 12, text: "Stop and look out at the view."),
                        GuideStep(start: 12, end: 16, text: "Look back over your shoulder at the lens.")
                    ]
                    : [
                        GuideStep(start: 0, end: 2, text: "Empty frame. You're just out of shot beside the phone."),
                        GuideStep(start: 2, end: 10, text: "Walk in and keep going. Don't look back."),
                        GuideStep(start: 10, end: 14, text: "Stop and look out at the view."),
                        GuideStep(start: 14, end: 16, text: "Hold still.")
                    ])

        case .tele:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .tele, fps: 30, stabilisation: .off,
                autoStop: 20, countdown: 45,
                before: "Tripod. Use the 45-second countdown to walk 30–50 m out.",
                steps: [
                    GuideStep(start: 0, end: 10, text: "Stand still, facing the view."),
                    GuideStep(start: 10, end: 20, text: "Walk slowly across the frame.")
                ])

        case .moment:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: 30, countdown: 10,
                before: "Tripod, with the view behind you. It films at 60 fps so the moment can be slowed down a little. "
                    + "For a mountain that looms bigger, set up further back and use the zoom lens. "
                    + "Ideas: lie back in the flowers, a kiss in front of the view, a slow spin, walking hand in hand.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Get comfortable. Don't look at the camera."),
                    GuideStep(start: 5, end: 25, text: "Have the moment. Keep it real and keep moving gently."),
                    GuideStep(start: 25, end: 30, text: "Hold still in the last moment.")
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
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 6,
                before: "Get close to something small: moss, water, rock, a sign, your hands. Tap it to focus first.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Hold steady."),
                    GuideStep(start: 1, end: 5, text: "Hold, or slide very slowly."),
                    GuideStep(start: 5, end: 6, text: "Done.")
                ])

        case .pov:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .strongest,
                autoStop: 15,
                before: "Phone at chest height, pointing where you're going, with your feet, hands or the track ahead in frame.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Start moving slowly."),
                    GuideStep(start: 2, end: 12, text: "Walk smoothly: feet, hands, the track ahead."),
                    GuideStep(start: 12, end: 15, text: "Ease to a stop.")
                ])

        case .talk:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: nil, manualLength: 20, countdown: 5,
                before: "Tripod at eye level, mic clipped on. Do three takes.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Look at the lens and smile."),
                    GuideStep(start: 2, end: 15, text: "Say one thing about this place."),
                    GuideStep(start: 15, end: nil, text: "Hold a beat, then stop.")
                ])

        case .ambient:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 20,
                before: "Point at the sound: water, wind in the trees, birds.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Point at the sound and hold."),
                    GuideStep(start: 2, end: 18, text: "Stay silent. Keep still."),
                    GuideStep(start: 18, end: 20, text: "Hold.")
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

        case .transition:
            if variantIndex == 0 {
                return ShotPlan(
                    shot: self, take: take, group: .inHand,
                    lens: .wide, fps: 30, stabilisation: .cinematic,
                    autoStop: 5,
                    before: "This one ends a place. Film the scene, then cover the lens with your palm.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Film the scene."),
                        GuideStep(start: 2, end: 4, text: "Cover the lens with your hand."),
                        GuideStep(start: 4, end: 5, text: "Hold the black.")
                    ],
                    variantName: variantName)
            }
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 5,
                before: "This one starts the next place. Start with your palm over the lens, then pull it away.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Start with your hand over the lens."),
                    GuideStep(start: 1, end: 3, text: "Pull your hand away."),
                    GuideStep(start: 3, end: 5, text: "Hold on the scene.")
                ],
                variantName: variantName)

        case .secondAngle:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .ultraWide, fps: 30, stabilisation: .off,
                autoStop: nil, manualLength: 60, countdown: 5,
                before: "Mini tripod. This phone films you getting the hero shot on your other camera.",
                steps: [
                    GuideStep(start: 0, end: 5, text: "Walk in with your gear."),
                    GuideStep(start: 5, end: 20, text: "Set up your other camera and check the frame."),
                    GuideStep(start: 20, end: 35, text: "Get into position and do the take."),
                    GuideStep(start: 35, end: 45, text: "Walk back and check it."),
                    GuideStep(start: 45, end: nil, text: "Stop when you're done.")
                ])

        case .bodyWipe:
            if variantIndex == 0 {
                return ShotPlan(
                    shot: self, take: take, group: .inShot,
                    lens: .wide, fps: 60, stabilisation: .off,
                    autoStop: 6, countdown: 5,
                    before: "This one ends a place. Tripod at chest height, right beside your path. "
                        + "Walk left to right, brushing past the lens so you fill the frame.",
                    steps: [
                        GuideStep(start: 0, end: 2, text: "Scene only. You're just out of shot on the left."),
                        GuideStep(start: 2, end: 4, text: "Walk left to right, close past the lens, filling the frame."),
                        GuideStep(start: 4, end: 6, text: "Keep going until you're out of shot.")
                    ],
                    variantName: variantName)
            }
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: 6, countdown: 5,
                before: "This one starts the next place. Walk the same way as the Out half: left to right.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Stand right in front of the lens, filling the frame."),
                    GuideStep(start: 1, end: 3, text: "Walk off to the right, revealing the scene."),
                    GuideStep(start: 3, end: 6, text: "Keep walking into the scene, or out of shot.")
                ],
                variantName: variantName)

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
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .cinematic,
                autoStop: 5,
                before: "Anything that shows the place: a sign, people, traffic, flags in the wind, the car park, your boots. "
                    + "Keep the subject in the middle. It stops by itself, so grab a few in a row.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Frame it with the subject in the middle."),
                    GuideStep(start: 1, end: 5, text: "Hold still, or drift very slowly. Let things move in the frame.")
                ])

        case .quick:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 60, stabilisation: .cinematic,
                autoStop: nil, manualLength: 30, countdown: 0,
                before: "",
                steps: [GuideStep(start: 0, end: nil, text: "Rolling. Stop when you're done.")])

        default:
            return creativePlan(take: take, variant: variantIndex, variantName: variantName)
        }
    }

    /// The creative shots.
    private func creativePlan(take: Int, variant: Int, variantName: String?) -> ShotPlan {
        switch self {
        case .matchCut:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 6, countdown: 10,
                before: "Tripod at the same height as last time. Line the frame up with the see-through still of your last "
                    + "MATCH CUT, then do the same pose: arms out, a spin, a jump or a look back.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Stand where your outline was."),
                    GuideStep(start: 2, end: 5, text: "Do the pose once, cleanly, at the same speed as before."),
                    GuideStep(start: 5, end: 6, text: "Hold.")
                ],
                overlay: .ghost)

        case .clone:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 25, countdown: 10,
                before: "Tripod only: the phone can't move at all. Focus and exposure lock when recording starts. "
                    + "Pick three spots that don't overlap. Overcast light or shade works best, as shadows don't cut out.",
                steps: [
                    GuideStep(start: 0, end: 4, text: "Spot 1: hold your pose."),
                    GuideStep(start: 4, end: 10, text: "Flash: walk to spot 2 and hold."),
                    GuideStep(start: 10, end: 16, text: "Flash: walk to spot 3 and hold."),
                    GuideStep(start: 16, end: 19, text: "Flash: walk out of the frame."),
                    GuideStep(start: 19, end: 25, text: "The empty scene. Stay out of shot.")
                ],
                flashCues: [4, 10, 16],
                exposure: .lockAtStart)

        case .jump:
            let steps = [
                GuideStep(start: 0, end: 2, text: "Stand in the middle, ready."),
                GuideStep(start: 2, end: 4, text: "Jump straight up, right out of the top of the frame."),
                GuideStep(start: 4, end: 5, text: "Land and hold.")
            ]
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 60, stabilisation: .off,
                autoStop: 5, countdown: 5,
                before: variant == 0
                    ? "This one ends a place. Tripod low, framed so the top edge is just above your head."
                    : "This one starts the next place. The same lens, framing and jump as the Out half.",
                steps: steps,
                variantName: variantName)

        case .rise:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .ultraWide, fps: 60, stabilisation: .strongest,
                autoStop: 11,
                before: "Start low behind something close, like a rock, long grass or a railing, so none of the view "
                    + "shows. Rise with your legs, not your arms.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Hold on the foreground."),
                    GuideStep(start: 1, end: 9, text: "Rise slowly and evenly. Keep the phone level."),
                    GuideStep(start: 9, end: 11, text: "Hold on the view.")
                ])

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

        case .dollyZoom:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .strongest,
                autoStop: 8,
                zoomRamp: ZoomRamp(from: 1, to: 3, startAt: 1, duration: 6),
                before: "Start 1 metre from them, framed from the chest up, with a far-off background behind. "
                    + "Check the ground behind you first. The app does the zoom.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Fit their head and shoulders in the box."),
                    GuideStep(start: 1, end: 7, text: "Walk backwards slowly as it zooms. Keep them filling the box."),
                    GuideStep(start: 7, end: 8, text: "Stop and hold.")
                ],
                overlay: .sizeBox)

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
                before: "Turn the phone sideways so the camera is in a bottom corner, 1 to 2 cm above still water. "
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
                before: "Tripod, framed wide with the view big and you full-body in it. Put your AirPods in: the song "
                    + "starts during the countdown, so your part lands as recording starts. At each new spot, carry on from "
                    + "10 seconds before where you stopped, or dance it from the top.",
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
