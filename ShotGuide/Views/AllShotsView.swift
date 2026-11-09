import SwiftUI

/// Every shot in the order of the day, like the trip page, with what it's for, what you'd see in it and how to get it
/// right (1.20). Read only: it changes nothing on the trip and doesn't open the camera.
struct AllShotsView: View {
    /// The day's trip type, so the summaries and counts match the trip page.
    let type: TripType

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Every shot in the order of the day, like the trip page. Tap one for what you'd see in it and "
                            + "how to get it right.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("Shown for \(type.title.lowercased()) days", systemImage: type.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.vertical, 2)
                }
                ForEach(TripPhase.allCases) { phase in
                    Section {
                        ForEach(phase.slots) { slot in
                            NavigationLink(value: slot) {
                                AllShotsRow(slot: slot, type: type)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.title)
                            Text(phase.guidePlace)
                                .font(.footnote)
                                .fontWeight(.regular)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("All shots")
            .navigationDestination(for: ShotSlot.self) { slot in
                ShotGuidePage(slot: slot, type: type)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A shot as the trip page shows it, without the counts.
private struct AllShotsRow: View {
    let slot: ShotSlot
    let type: TripType

    var body: some View {
        let shot = slot.shot
        let summary = slot.summary(for: type)
        let tierLabel = slot.tier(for: type).label
        HStack(spacing: 12) {
            Image(systemName: shot.defaultGroup == .inShot ? "person.fill" : "hand.raised.fill")
                .frame(width: 28)
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .font(.headline)
                Text(tierLabel.map { summary + " · " + $0 } ?? summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if shot != .voiceover {
                    FilmingTag(filming: shot.filming, mount: shot.mountSummary)
                        .padding(.top, 1)
                }
            }
        }
    }
}

/// One shot's page: what it's for and when, what you'd see in it, each role or version with its settings and set-up,
/// and the tips.
struct ShotGuidePage: View {
    let slot: ShotSlot
    let type: TripType

    private var shot: ShotType { slot.shot }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot.summary(for: type))
                    if shot != .voiceover {
                        FilmingTag(filming: shot.filming, mount: shot.mountSummary)
                    }
                    Text(levelLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let phase = slot.guidePhase {
                        Text("\(phase.title) · \(phase.guidePlace)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Section {
                Text(slot.scenery)
                    .font(.subheadline)
            } header: {
                Text("What you'd see")
            }
            Section {
                ForEach(GuideWay.ways(for: slot)) { way in
                    GuideWayRow(way: way, shot: shot)
                }
            } header: {
                Text(waysTitle)
            } footer: {
                Text("The camera sets these up for you. Lengths include the couple of seconds it adds at the end, and "
                    + "follow any timing you've changed.")
            }
            if !shot.tips.isEmpty {
                Section {
                    ForEach(shot.tips, id: \.self) { tip in
                        Text(tip)
                            .font(.subheadline)
                    }
                } header: {
                    Text("Tips")
                }
            }
        }
        .navigationTitle(slot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Everyday: 3 different roles a day, 2 on a light day."
    private var levelLine: String {
        let target = slot.target(for: type)
        let unit: String
        if slot.half == nil && shot.rolesAreVariants {
            unit = target == 1 ? "version" : "different versions"
        } else if slot.half == nil && !shot.roles.isEmpty {
            unit = target == 1 ? "role" : "different roles"
        } else {
            unit = target == 1 ? "take" : "takes"
        }
        switch slot.tier(for: type) {
        case .core:
            let light = slot.lightDayTarget(for: type)
            return "Everyday: \(target) \(unit) a day" + (light > 0 ? ", \(light) on a light day." : ".")
        case .fullDay:
            return "Full day: \(target) \(unit) a day."
        case .extra:
            return "Extra: film it whenever it's worth it."
        }
    }

    private var waysTitle: String {
        if slot.half != nil {
            return "How to film it"
        }
        if shot.rolesAreVariants {
            return "Versions"
        }
        if !shot.roles.isEmpty {
            return "Roles"
        }
        return shot.variants.isEmpty ? "How to film it" : "Versions"
    }
}

private struct GuideWayRow: View {
    let way: GuideWay
    let shot: ShotType

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title = way.title {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if let note = way.note {
                        Text("· " + note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(way.settings(for: shot), id: \.self) { line in
                Text(line)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
            if let purpose = way.purpose {
                Text(purpose)
                    .font(.subheadline)
            }
            if let before = way.before {
                Text(before)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let placement = way.placement {
                Text("Where you stand: " + placement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One way to film a slot: one of its roles, one of its versions, or the shot itself.
struct GuideWay: Identifiable {
    let id: String
    let title: String?
    let purpose: String?
    /// "optional" or "swap-in".
    let note: String?
    /// The plan to film it, or two when it can be in your hand or with you in it (the usual way first).
    let plans: [ShotPlan]

    /// What to do before you start, from the usual way.
    var before: String? {
        guard let text = plans.first?.before, !text.isEmpty else { return nil }
        return text
    }

    /// Where you are in the frame, for the ways you're in.
    var placement: String? {
        plans.compactMap { $0.placement }.first
    }

    /// "0.5x · 22 s · handheld", or one line each way: "In your hand · 1x · 27 s" and
    /// "With you in it · 1x · 27 s · tripod · 10 s countdown".
    func settings(for shot: ShotType) -> [String] {
        if shot == .voiceover {
            return ["Sound only, on its own screen · you stop it"]
        }
        return plans.map { GuideWay.settingsLine($0, shot: shot, eachWay: plans.count > 1) }
    }

    private static func settingsLine(_ plan: ShotPlan, shot: ShotType, eachWay: Bool) -> String {
        let timing = TimingStore.load(shot, plan: plan)
        var parts: [String] = []
        if eachWay {
            parts.append(plan.isInShot ? "With you in it" : "In your hand")
        }
        parts.append(lensWord(plan.lens))
        if plan.timelapseInterval != nil {
            parts.append("time-lapse")
        } else if plan.fps > 30 {
            parts.append("\(plan.fps) fps")
        }
        if timing.stopsByItself {
            let extra = plan.timelapseInterval == nil ? ShotCameraView.extraSeconds : 0
            parts.append(lengthWords(timing.length + extra))
        } else {
            parts.append("you stop it")
        }
        if !(eachWay && !plan.isInShot) {
            parts.append(plan.mount.title.lowercased())
        }
        if timing.countdown > 0 {
            parts.append("\(timing.countdown) s countdown")
        }
        if let filming = plan.filming, filming != shot.filming {
            parts.append(filming.title.lowercased())
        }
        return parts.joined(separator: " · ")
    }

    private static func lensWord(_ lens: LensChoice) -> String {
        switch lens {
        case .ultraWide: return "0.5x"
        case .wide: return "1x"
        case .tele: return "telephoto"
        case .front: return "front camera"
        }
    }

    private static func lengthWords(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds.rounded())) s" : clockString(seconds)
    }

    /// The roles of a role shot, the versions of REVEAL and TALK, the one half of WHIP or HOME, or the shot itself.
    static func ways(for slot: ShotSlot) -> [GuideWay] {
        let shot = slot.shot
        let usual = shot.defaultGroup == .inShot

        func plans(variant: Int, role: String?, inShot fixed: Bool?) -> [ShotPlan] {
            if let fixed {
                return [shot.plan(take: 1, inShot: fixed, variant: variant, role: role)]
            }
            let first = shot.plan(take: 1, inShot: usual, variant: variant, role: role)
            guard shot.canToggleInShot else {
                return [first]
            }
            return [first, shot.plan(take: 1, inShot: !usual, variant: variant, role: role)]
        }

        if let half = slot.half {
            return [GuideWay(id: "half", title: nil, purpose: nil, note: nil,
                             plans: plans(variant: half, role: nil, inShot: nil))]
        }
        if shot.rolesAreVariants {
            let roles = shot.roles
            return shot.variants.indices.map { index in
                GuideWay(id: "version-\(index)", title: shot.variants[index],
                         purpose: index < roles.count ? roles[index].purpose : nil, note: nil,
                         plans: plans(variant: index, role: nil, inShot: nil))
            }
        }
        if !shot.roles.isEmpty {
            return shot.roles.map { role in
                GuideWay(id: role.id, title: role.title, purpose: role.purpose,
                         note: role.isOptional ? "optional" : (role.isSubstitute ? "swap-in" : nil),
                         plans: plans(variant: 0, role: role.id, inShot: role.inShot))
            }
        }
        if !shot.variants.isEmpty {
            return shot.variants.indices.map { index in
                // MATCH CUT's versions are its moves: what you do, and where the edit cuts (1.24).
                let move = shot == .matchCut ? MatchMove(rawValue: index) : nil
                return GuideWay(id: "version-\(index)", title: shot.variants[index],
                                purpose: move.map { $0.summary + ". " + $0.cut }, note: nil,
                                plans: plans(variant: index, role: nil, inShot: nil))
            }
        }
        if shot == .oneTake {
            // Its parts as you've set them, with what each counts as (1.24).
            let setup = OneTakeSetup.load()
            let parts = setup.parts.map { part -> String in
                let name = part == .matchCut ? "MATCH CUT · \(setup.matchMove.title)" : part.shot.title
                return "\(part.title) (\(name)) \(clockString(setup.length(of: part)))"
            }
            var plan = shot.plan(take: 1, inShot: true, variant: 0)
            plan.steps = setup.steps()
            plan.manualLength = setup.total
            return [GuideWay(id: "shot", title: nil,
                             purpose: "Parts: " + parts.joined(separator: ", ") + ", then you walk back.", note: nil,
                             plans: [plan])]
        }
        return [GuideWay(id: "shot", title: nil, purpose: nil, note: nil,
                         plans: plans(variant: 0, role: nil, inShot: nil))]
    }
}

extension TripPhase {
    /// Where you'll be for this part of the day, for the All shots page.
    var guidePlace: String {
        switch self {
        case .onTheWay: return "At home, then on the road there"
        case .arriving: return "Walking in: the trail, the boardwalk or the street"
        case .firstLook: return "Where the view first opens up"
        case .atTheSpot: return "At the view: the lookout, the summit, the beach or the falls"
        case .bRoll: return "All around the place, whenever you've a spare minute"
        case .leaving: return "Heading off, then where you're staying, and home"
        }
    }
}

extension ShotSlot {
    /// The part of the day this row sits in on the trip page.
    var guidePhase: TripPhase? {
        TripPhase.allCases.first { phase in
            phase.slots.contains { $0.shot == shot && $0.half == half }
        }
    }

    /// What you'd expect to see in this shot, and the kinds of places it's filmed.
    var scenery: String {
        switch (shot, half) {
        case (.home, 0?):
            return "The quiet start, at home or on the way out: your bag half packed on the bed, boots by the door, a last "
                + "look out the window at the weather, or sitting at the gate with a coffee. Ordinary moments that set up "
                + "the trip."
        case (.home, 1?):
            return "Back home at night, lying in bed lit only by your phone as you scroll through the day. A dark room and "
                + "a tired smile: the full stop at the end of a reel."
        case (.whip, 0?):
            return "The end of a place: hold on the view you're leaving, like the summit, the bay or your café table, then "
                + "whip the phone sideways into a blur that cuts to the next place."
        case (.whip, 1?):
            return "The start of a new place: the phone whips in from a blur and lands on where you've arrived, like the "
                + "trailhead sign, the first sight of the beach, the falls through the trees or a street corner."
        default:
            return shot.scenery
        }
    }
}

extension ShotType {
    /// What you'd expect to see in a shot like this, and the kinds of places it's filmed, for the All shots page.
    var scenery: String {
        switch self {
        case .home:
            return "The ordinary moments that bookend a trip: packing, a last look out the window, the gate, and back in "
                + "bed at night, lit by your phone."
        case .onTheWay:
            return "The trip there, mostly through glass: a winding road climbing into the hills, rainforest flicking past "
                + "the window, the coast road with the sea beside you, a ferry's wake, or the wing over the clouds. Side "
                + "mirrors, dashboards and train windows make natural frames."
        case .whip:
            return "A fast sideways whip that joins two places: the end of one view blurs into the start of the next, like "
                + "the summit into the beach, or the trail into the city."
        case .pov:
            return "What your eyes see walking in: the track ahead through the trees and ferns, a ridge trail with the "
                + "range falling away beside you, a boardwalk over the dunes, footsteps in fresh snow, or a busy street at "
                + "eye level. Your boots or hands in the frame now and then make it feel like you're there."
        case .hyperlapse:
            return "A slow walk turned into a smooth glide, with something to aim at: a boardwalk through the rainforest "
                + "towards the falls, a long jetty, a bridge, a path along the beach, or a crowded square towards a tower."
        case .follow:
            return "Your partner leading you by the hand a step ahead, with the place opening up past them: down a forest "
                + "track, up the last steps to a lookout, along the sand to the water, or through a busy market."
        case .reaction:
            return "Your face as the view hits you for the first time: stepping out of the trees at a lookout, reaching the "
                + "summit, the falls appearing round the last bend, or the beach opening up below. Real surprise, wind in "
                + "your hair, and the view coming in behind you."
        case .reveal:
            return "Something hides the view, then it opens up: rising over a rock to the valley below, stepping past ferns "
                + "to find the falls, tilting up from rock pools to the whole bay, or rounding a corner onto the skyline."
        case .wide:
            return "The whole place in one frame: the range rolling away from the summit, the falls from top to pool, the "
                + "curve of the bay and the coastline, a city skyline, or a snowfield under the peaks. Then the same view "
                + "with you small in it, and from a different angle."
        case .slomo:
            return "Water and motion slowed right down: spray off the falls, a wave breaking over rocks, a jump into a "
                + "waterhole, sand kicked up on the beach, snow thrown into the air, or a hair flick in bright sun."
        case .talk:
            return "You talking to the camera with the view behind you: at a lookout, sitting on a summit rock, at the "
                + "water's edge, or walking a trail or a street with the phone just above your eyes."
        case .walkaway:
            return "You walking away from the camera into the scene: up a trail, along a ridge, down the waterline, across "
                + "a rock shelf towards the falls, or down a quiet lane. A path leading into the view does half the work."
        case .tele:
            return "You tiny under something huge, stacked up by the telephoto: on a ridge with a peak towering behind, at "
                + "the foot of a waterfall, on a headland under the cliffs, or at the base of a city tower."
        case .matchCut:
            return "One move, done once at every place, the same size in the frame each time: a run across the summit, "
                + "a leap at the falls, arms out on the beach, a spin in the snow. Cut together on the same moment of the "
                + "move, it looks like one move while the places change around you."
        case .moment:
            return "Real, unposed moments together with the place around you: lying in the grass at a lookout, a kiss at "
                + "the waterhole, walking hand in hand along the sand, a slow spin in the snow, or coffee with a view."
        case .orbit:
            return "A slow circle around your partner as they stand still or look out, with the background turning behind "
                + "them: on a summit, a rock in the river, the end of a jetty, or a quiet plaza."
        case .clone:
            return "A few minutes of you all over one still frame, doing something different at each spot: sitting on a "
                + "rock, pointing at the view, reading a map, with the frame empty at the start and end. The edit puts "
                + "several of you in at once. It works best somewhere open in even light, like a summit plateau, the "
                + "sand or a lawn."
        case .dance:
            return "You dancing or lip-syncing with a big view behind you: a lookout over the valley, the beach at sunset, "
                + "a mountain meadow, or a rooftop over the city."
        case .silhouette:
            return "The two of you as black shapes against a glowing sky: on a ridge at sunset, the beach at golden hour, a "
                + "headland, or the end of a jetty, with the sun low behind you."
        case .bRoll:
            return "The place without you, in short shots: mist through the trees, hikers on the trail, clouds over the "
                + "range, waves rolling in, signs and traffic in the city, or cows by the road. Anything that moves cuts "
                + "in well."
        case .detail:
            return "The place up close: moss and ferns, drops on leaves, sand and shells, rock pools, frost and icicles, a "
                + "trail sign, coffee on a café table, or your hand on rock or in the water."
        case .reflection:
            return "The scene doubled in still water: a mountain in a calm lake at dawn, the falls in a rock pool, the sky "
                + "in wet sand at low tide, or city lights in a puddle after rain."
        case .wildlife:
            return "Animals from a distance, on the telephoto: birds in the canopy, a lizard on a warm rock, goats on the "
                + "cliffs, crabs on the sand, dolphins offshore, or deer in the snow."
        case .food:
            return "Local food, close and slow: a bakery stop on the drive, breakfast at a café, street food steaming, a "
                + "pub meal after the hike, or fish and chips on the beach."
        case .sounds:
            return "Close-ups made for their sound: boots crunching on a gravel track, a stick snapping, a creek running "
                + "over stones, waves dragging pebbles, a café's coffee machine, or a fire crackling."
        case .ambient:
            return "Thirty seconds of sound with the camera still: the roar of the falls, wind on the summit, birdsong on "
                + "the trail, waves on the sand, a busy street, or the hush of falling snow."
        case .timelapse:
            return "Time sped up while you sit and rest: clouds rolling over the peaks, mist drifting through the falls, "
                + "the tide going out, the sun going down, or traffic and crowds at blue hour."
        case .voiceover:
            return "No pictures: your voice telling the story of the day, recorded somewhere quiet like the car, your room "
                + "or a bench."
        case .stay:
            return "Walking into where you're staying for the first time: the door opening, the view from the window, the "
                + "bed, the balcony. A cabin in the trees, a beach house deck, a tent with a view, or a hotel room over "
                + "the city."
        case .oneTake:
            return "One tripod spot with a big view, and you moving through it: the empty lookout, you walking out to "
                + "the edge of the falls or the ridge, standing small in the view, coming back for a real moment, your "
                + "MATCH CUT move, then you all over the frame for clones. A path or ledge leading out into the view does "
                + "half the work."
        }
    }
}
