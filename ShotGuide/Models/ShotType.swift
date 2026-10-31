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

    var rangeLabel: String {
        if let end {
            return "\(Self.number(start))–\(Self.number(end)) s"
        }
        return "\(Self.number(start)) s on"
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// A zoom the app performs itself, in the zoom values shown on screen (0.5x to 2x).
struct ZoomRamp: Hashable {
    let from: Double
    let to: Double
    let startAt: Double
    let duration: Double
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
    var autoStop: Double? = nil
    var countdown: Int = 5
    var zoomRamp: ZoomRamp? = nil
    var before: String = ""
    var steps: [GuideStep] = []
    var variantName: String? = nil

    var isInShot: Bool { group == .inShot }

    var captureConfig: CaptureConfig {
        CaptureConfig(lens: lens, fps: fps, stabilisation: stabilisation, timelapseInterval: timelapseInterval)
    }
}

/// Where a shot sits on the trip page.
enum ShotSection {
    case doFirst
    case anyOrder
    case transitions
}

enum ShotType: String, CaseIterable, Codable, Identifiable {
    case reaction = "REACTION"
    case reveal = "REVEAL"
    case timelapse = "TIMELAPSE"
    case wide = "WIDE"
    case walkaway = "WALKAWAY"
    case tele = "TELE"
    case detail = "DETAIL"
    case pov = "POV"
    case talk = "TALK"
    case ambient = "AMBIENT"
    case slomo = "SLOMO"
    case transition = "TRANSITION"
    case secondAngle = "SECONDANGLE"
    case bodyWipe = "BODYWIPE"
    case whip = "WHIP"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secondAngle: return "SECOND ANGLE"
        case .bodyWipe: return "BODY WIPE"
        default: return rawValue
        }
    }

    var targetTakes: Int {
        switch self {
        case .reveal, .wide, .walkaway, .transition, .bodyWipe, .whip: return 2
        case .detail, .talk: return 3
        default: return 1
        }
    }

    /// Worth getting in the first two minutes at a new place.
    var doFirst: Bool { self == .reaction || self == .reveal || self == .timelapse }

    var section: ShotSection {
        if doFirst { return .doFirst }
        switch self {
        case .transition, .bodyWipe, .whip: return .transitions
        default: return .anyOrder
        }
    }

    /// BODY WIPE and WHIP are extras, so they don't count towards a trip's total.
    var countsTowardTotal: Bool { self != .bodyWipe && self != .whip }

    var defaultGroup: ShotGroup {
        switch self {
        case .reaction, .timelapse, .walkaway, .tele, .talk, .secondAngle, .bodyWipe: return .inShot
        default: return .inHand
        }
    }

    /// WIDE and SLOMO can be filmed in your hand or with you in them.
    var canToggleInShot: Bool { self == .wide || self == .slomo }

    var variants: [String] {
        switch self {
        case .reveal: return ["Auto zoom", "Walk reveal"]
        case .transition, .bodyWipe, .whip: return ["Out", "In"]
        default: return []
        }
    }

    /// Transitions alternate: odd takes are the Out half, even takes the In half.
    func defaultVariant(forTake take: Int) -> Int {
        if section == .transitions { return take % 2 == 0 ? 1 : 0 }
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
        case .detail: return "Close-ups and textures"
        case .pov: return "What your eyes see on the way"
        case .talk: return "One line to camera"
        case .ambient: return "20 seconds of pure sound"
        case .slomo: return "Water, waves or a jump in slow motion"
        case .transition: return "Cover and uncover the lens"
        case .secondAngle: return "You getting the hero shot"
        case .bodyWipe: return "Walk past the lens into the next place"
        case .whip: return "Whip pan from one place to the next"
        }
    }

    func plan(take: Int, inShot: Bool, variant: Int) -> ShotPlan {
        let variantIndex = variants.isEmpty ? 0 : min(max(variant, 0), variants.count - 1)
        let variantName: String? = variants.isEmpty ? nil : variants[variantIndex]

        switch self {
        case .reaction:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .front, fps: 30, stabilisation: .standard,
                autoStop: nil, countdown: 3,
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
                lens: .wide, fps: 30, stabilisation: .cinematic,
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
                timelapseInterval: 1, autoStop: nil, countdown: 5,
                before: "Tripod on solid ground. If the light is steady, hold on the screen to lock exposure.",
                steps: [
                    GuideStep(start: 0, end: nil, text: "Leave it running. 10 minutes makes 20 seconds of video.")
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
                lens: .ultraWide, fps: 30, stabilisation: .off,
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

        case .detail:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .cinematic,
                autoStop: 6,
                before: "Get close and tap the detail to focus first.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Hold steady."),
                    GuideStep(start: 1, end: 5, text: "Hold, or slide very slowly."),
                    GuideStep(start: 5, end: 6, text: "Done.")
                ])

        case .pov:
            return ShotPlan(
                shot: self, take: take, group: .inHand,
                lens: .wide, fps: 30, stabilisation: .strongest,
                autoStop: 15,
                before: "Phone at chest height.",
                steps: [
                    GuideStep(start: 0, end: 2, text: "Start moving slowly."),
                    GuideStep(start: 2, end: 12, text: "Walk smoothly: feet, hands, the track ahead."),
                    GuideStep(start: 12, end: 15, text: "Ease to a stop.")
                ])

        case .talk:
            return ShotPlan(
                shot: self, take: take, group: .inShot,
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: nil, countdown: 5,
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
                    GuideStep(start: 0, end: 20, text: "Stay silent. Keep still.")
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
                    before: "This one ends a place.",
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
                before: "This one starts the next place.",
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
                autoStop: nil, countdown: 5,
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
                    lens: .wide, fps: 30, stabilisation: .off,
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
                lens: .wide, fps: 30, stabilisation: .off,
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
                    lens: .wide, fps: 30, stabilisation: .off,
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
                lens: .wide, fps: 30, stabilisation: .off,
                autoStop: 3,
                before: "This one starts the next place. Point left of the scene, then whip right, same as the Out half.",
                steps: [
                    GuideStep(start: 0, end: 1, text: "Whip fast to the right and land on the scene."),
                    GuideStep(start: 1, end: 3, text: "Hold steady.")
                ],
                variantName: variantName)
        }
    }
}
