import Foundation

/// What a shot's card says before the camera opens (1.28): what it is, where it goes in a reel, how to get it, and
/// ideas to pick from, each with a line on how. Every row on the lists has one, so there's always a reminder.
struct ShotCard {
    struct Idea: Hashable, Identifiable {
        let title: String
        let how: String

        var id: String { title }

        init(_ title: String, _ how: String) {
            self.title = title
            self.how = how
        }
    }

    let what: String
    let whereItGoes: String
    let how: [String]
    let ideas: [Idea]
}

extension ShotRow {
    /// Its card: its own, or its shot's.
    var card: ShotCard {
        ShotCards.all[id] ?? ShotCards.all[key] ?? ShotCards.all[shot.rawValue] ?? ShotCards.fallback(for: self)
    }

    /// The short line under its name on the lists, like "The place alone, before people walk in".
    var line: String {
        ShotCards.lines[id] ?? ShotCards.lines[key] ?? roleInfo?.purpose ?? slot.summary
    }

    /// The card's tags: what the phone goes on, which way to hold it, the lens and how long it runs, as you last set
    /// it for this shot.
    var tags: [String] {
        guard shot != .voiceover else { return ["Sound only", "Somewhere quiet"] }
        let plan = self.plan
        var tags = [plan.mount.title]
        let filming = plan.filming ?? shot.filming
        if filming != .either {
            tags.append(filming.title)
        }
        if let ramp = plan.zoomRamp {
            tags.append(ShotCards.zoomText(ramp.from) + " to " + ShotCards.zoomText(ramp.to))
        } else {
            tags.append(ShotCards.lensText(plan.lens))
        }
        if plan.fps > 60 {
            tags.append("Slow motion")
        }
        if plan.timelapseInterval != nil {
            tags.append("10 min or more")
        } else if shot == .oneTake {
            tags.append("About \(Int((OneTakeSetup.load().total / 60).rounded())) min")
        } else {
            let timing = TimingStore.load(shot, plan: plan)
            tags.append(timing.stopsByItself ? ShotCards.lengthText(timing.length) : "You stop it")
        }
        return tags
    }

    /// The row a clip was filmed for, to show it by its shot's name, like "ON THE WAY · Window". nil for a clip
    /// added from Photos that hasn't been given a shot yet.
    static func forClip(_ clip: Clip) -> ShotRow? {
        guard let shot = clip.shotType else { return nil }
        let variantIndex = clip.variant.flatMap { shot.variants.firstIndex(of: $0) }
        switch shot {
        case .whip, .home:
            return ShotRow(shot: shot, half: variantIndex)
        case .talk, .matchCut:
            return ShotRow(shot: shot, variant: variantIndex)
        default:
            return ShotRow(shot: shot, role: clip.roleID)
        }
    }
}

enum ShotCards {
    typealias Idea = ShotCard.Idea

    /// A card made from the shot's own words, for a row without one. The tests make sure every row has its own.
    static func fallback(for row: ShotRow) -> ShotCard {
        let plan = row.plan
        return ShotCard(what: row.roleInfo?.purpose ?? row.shot.summary, whereItGoes: "", how: [plan.before], ideas: [])
    }

    /// "0.5x", "1x", "5x" or "Front camera".
    static func lensText(_ lens: LensChoice) -> String {
        switch lens {
        case .ultraWide: return "0.5x"
        case .wide: return "1x"
        case .tele: return "5x"
        case .front: return "Front camera"
        }
    }

    static func zoomText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))x" : String(format: "%.1fx", rounded)
    }

    /// "10 s", "1 min", "1 min 30 s".
    static func lengthText(_ seconds: Double) -> String {
        let total = max(1, Int(seconds.rounded()))
        guard total >= 60 else { return "\(total) s" }
        let minutes = total / 60
        let rest = total % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }

    /// The short lines under each row's name, by `ShotRow.id`.
    static let lines: [String: String] = [
        "ONTHEWAY.getting-going": "Bags, the airport, the first coffee",
        "ONTHEWAY.window": "The world sliding past the glass",
        "ONTHEWAY.road-ahead": "Where you're heading, from the passenger seat",
        "ONTHEWAY.pulling-in": "The sign, the car park, the first sight",
        "POV.through": "Your eyes moving through the place",
        "POV.approach": "Heading towards the view",
        "FOLLOW": "Led by the hand towards the view",
        "HYPERLAPSE": "A slow walk, sped up into a glide",
        "REACTION": "Your face as you first see it",
        "REVEAL.walk-reveal": "Step out from behind something",
        "REVEAL.tilt-up": "From the water or the ground up to the view",
        "REVEAL.auto-zoom": "From wide in to the star of the place",
        "WHIP-1": "Whip in and land on the view",
        "WIDE.establishing": "The place alone, before people walk in",
        "WIDE.alternative": "A new viewpoint, height, side or lens",
        "WIDE.vertical-hero": "The best view, upright",
        "SLOMO.water": "Water, spray or waves in slow motion",
        "WIDE.human-scale": "You, small, in the big view",
        "WALKAWAY.into-view": "Walk away until you're small against it",
        "WALKAWAY.new-spot": "Somewhere new, or look back",
        "TELE": "You, small, under something huge",
        "MOMENT.with-place": "Touch the water, lie in the grass",
        "MOMENT.together": "A real moment with your partner",
        "SLOMO.you": "A jump, a splash or a hair flick",
        "ONETAKE": "Five tripod shots in one long take",
        "MATCHCUT": "Pick the move: run, leap, spin…",
        "CLONE": "You all over the frame, in shade",
        "ORBIT": "A slow circle around your partner",
        "DANCE": "To your song, with the view behind",
        "SILHOUETTE": "Sun low behind you: save it for sunset",
        "TALK~1": "One line to the front camera",
        "WHIP-0": "Whip away from the view to end here",
        "STAY": "Your first walk into where you're staying",
        "BROLL.atmosphere": "Mist, cloud, sun through the trees",
        "BROLL.people": "Walkers, a guide, the lookout crowd",
        "BROLL.movement": "Water, birds, cars, a flag",
        "BROLL.local": "Signs, landmarks, local things",
        "BROLL.lens-angle": "The 5x, or very low or very high",
        "BROLL.transition": "Walk past something close to the lens",
        "BROLL.nature": "Plants, animals or water",
        "BROLL.into-light": "Face the sun for flare and glow",
        "DETAIL.texture": "Rock, bark, ice, the water's surface",
        "DETAIL.object": "A sign, a map, a ticket, your coffee",
        "DETAIL.hands": "Your hand on rock, water or a rail",
        "DETAIL.foreground": "Something close, the view soft behind",
        "DETAIL.only-here": "A detail you'd only find here",
        "DETAIL.nature": "A leaf, a flower, drops of water",
        "AMBIENT": "30 seconds of pure sound",
        "SOUNDS": "Close-ups made for their sound",
        "WILDLIFE": "Animals up close, on the 5x",
        "FOOD": "Local food, close and slow",
        "REFLECTION": "The scene doubled in still water",
        "TIMELAPSE": "Clouds or light sped up, while you sit",
        "HOME-0": "Packing, a last look, the gate",
        "HOME-1": "Back home, in bed, lit by your phone",
        "TALK~0": "Your script, read to camera",
        "VOICEOVER": "Your script, read over the footage"
    ]

    /// The cards, by row: `ShotRow.id`, like "WIDE.establishing", "WHIP-1" or "TALK~0".
    static let all: [String: ShotCard] = {
        var cards: [String: ShotCard] = [:]

        // MARK: On the way

        cards["ONTHEWAY.getting-going"] = ShotCard(
            what: "The start of the trip: the moments before the journey really gets going.",
            whereItGoes: "The first seconds of a trip reel, before the first big view.",
            how: ["Find something happening: bags, a door, the gate, a coffee.",
                  "Hold the phone still and upright, and let it happen in front of you.",
                  "Ten seconds is plenty. Film two or three different moments."],
            ideas: [
                Idea("The bags going in the boot", "From low behind the car, the boot open, the bags landing in the frame."),
                Idea("Walking through the airport", "From behind at hip height, your partner and the bags rolling on ahead."),
                Idea("Your boarding pass", "Close, in your hand, with the gate or the plane soft behind it."),
                Idea("The first coffee of the day", "The cup on the dash or a café table, steam in the morning light."),
                Idea("Belts on, doors shut", "Close on the buckle clicking in, or the car door closing. Good for sound too."),
                Idea("The departures board", "Your flight on the board, then tilt down to the two of you walking past.")
            ])

        cards["ONTHEWAY.window"] = ShotCard(
            what: "The world sliding past a window on the way there: a plane, a train, a bus or the car.",
            whereItGoes: "Between places in a reel, or under a line of text like \u{201C}the drive in\u{201D}.",
            how: ["Put the lens right up to the glass so there's no reflection.",
                  "Pick the shady side, and wipe the window first.",
                  "Hold still for 10 seconds and let the world do the moving."],
            ideas: [
                Idea("Plane window at takeoff", "0.5x with the wing in a corner. Start before the wheels leave the ground."),
                Idea("The wing over the clouds", "Wait for the sun to catch the clouds, with the wing along the bottom third."),
                Idea("Trees flashing past the car window", "Focus on the far hills so the close trees blur past."),
                Idea("Rain running down the glass", "Tap to focus on the drops, with the lights or the hills soft behind."),
                Idea("Your hand on the glass", "Your hand flat on the window, the view going by beyond it."),
                Idea("A train window at golden hour", "Low sun across the fields, your reflection just showing in the glass.")
            ])

        cards["ONTHEWAY.road-ahead"] = ShotCard(
            what: "Where you're heading: the road through the windscreen, the track ahead, the water over the bow.",
            whereItGoes: "The journey in a reel: it says \u{201C}we're going somewhere\u{201D} in two seconds.",
            how: ["Low on the dash or against the windscreen, the road in the middle.",
                  "Only as the passenger. Never while you're the one driving.",
                  "Hold still for 15 seconds and let the road come to you."],
            ideas: [
                Idea("A bend into the mountains", "Wait for a curve with peaks behind it. The turn gives it movement."),
                Idea("A long straight road", "Centre the road so it runs to the horizon, the horizon on the top third."),
                Idea("Out of a tunnel", "Start in the dark and keep rolling as you come out into the light."),
                Idea("Over the bow of a boat", "Low at the front, the water rushing under and the coast ahead."),
                Idea("The side mirror", "The mirror in a corner, the road behind you in it and the view beside it."),
                Idea("Wipers in the rain", "The wipers sweeping across a wet, moody road ahead.")
            ])

        cards["ONTHEWAY.pulling-in"] = ShotCard(
            what: "Arriving: the first sight of the place as you get there.",
            whereItGoes: "The end of the journey and the start of the place, just before the first look.",
            how: ["Start rolling just before you get there.",
                  "Hold steady as the sign, the car park or the trailhead comes into view.",
                  "Keep going until you've stopped, about 10 seconds."],
            ideas: [
                Idea("The welcome sign", "Film it as you pass, or stop and frame it with the road behind it."),
                Idea("Into the car park", "The view behind the cars as you pull into a space."),
                Idea("The trailhead", "The trail sign, and the path disappearing into the trees."),
                Idea("Touching down", "The runway rushing up, then the wheels on the ground."),
                Idea("The ferry coming in", "The jetty getting closer over the bow."),
                Idea("The first glimpse", "The moment the mountain, the sea or the skyline shows through the window.")
            ])

        // MARK: Arriving

        cards["POV.through"] = ShotCard(
            what: "What your eyes see as you move through the place.",
            whereItGoes: "The middle of a reel: it takes the viewer along with you.",
            how: ["Phone at chest height, on the gimbal or in both hands.",
                  "Walk slowly, heel to toe with soft knees, and look around as you go.",
                  "Twenty seconds, then ease to a stop."],
            ideas: [
                Idea("Through the forest", "Ferns and trunks sliding past, light coming down through the canopy."),
                Idea("Along a boardwalk", "The boards leading the eye, water or bush either side."),
                Idea("Through a market", "At eye level past the stalls, people and colour on both sides."),
                Idea("Along the water's edge", "The waterline beside you, small waves running in."),
                Idea("Over a bridge", "The rail sliding past, the river below."),
                Idea("Under an arch of trees", "Tilt up a little to show the branches meeting overhead.")
            ])

        cards["POV.approach"] = ShotCard(
            what: "Heading towards something: the path to the view, the track ahead.",
            whereItGoes: "The build-up just before the reveal, so the view feels earned.",
            how: ["Phone at chest height, pointing where you're going.",
                  "Get your boots, your hands or the track in the frame now and then.",
                  "Walk smoothly for 15 seconds and ease to a stop."],
            ideas: [
                Idea("The last steps to the lookout", "The rail getting closer, the view opening up beyond it."),
                Idea("Your boots on the trail", "Tilt down a little so your steps lead the frame."),
                Idea("Up the stairs", "Steps rising ahead of you, sky at the top."),
                Idea("Towards the sound of the falls", "The track bending towards the noise, mist in the air."),
                Idea("Down onto the sand", "From the path over the dunes onto the beach."),
                Idea("Up to the door", "Walking up to the café, the cabin or the hut.")
            ])

        cards["FOLLOW"] = ShotCard(
            what: "Your partner leading you by the hand towards the view.",
            whereItGoes: "Couple reels and trip montages: it says \u{201C}come with me\u{201D}.",
            how: ["They hold your hand a step ahead and walk towards the view.",
                  "Film from your other hand, with their hand and the view in the frame.",
                  "Keep your arm straight and the phone level for 15 seconds."],
            ideas: [
                Idea("Up the last steps to the top", "Their hand pulling you up as the view opens behind them."),
                Idea("Along the sand into the water", "Running gently into the shallows together."),
                Idea("Through a busy street", "Weaving through people, their hair and the lights ahead."),
                Idea("Down the forest track", "Ferns either side, the light ahead of you both."),
                Idea("Out along a jetty", "Water all around, them looking back at you."),
                Idea("Into the spray of the falls", "Towards the mist, both of you getting wet.")
            ])

        cards["HYPERLAPSE"] = ShotCard(
            what: "A slow walk turned into a fast, smooth glide.",
            whereItGoes: "A punchy jump between places, or the build-up to a big view.",
            how: ["Pick something straight ahead to aim at: a tree, a sign, the rail.",
                  "Keep it in the crosshair and take small, even steps.",
                  "Walk for a minute without turning. It needs good light."],
            ideas: [
                Idea("Along a boardwalk", "The boards lead the eye, and the speed makes it glide."),
                Idea("Down a long jetty", "Aim at the end of the jetty and keep walking."),
                Idea("Through a crowded square", "Aim at a tower and let the people stream past."),
                Idea("Over a bridge", "The cables or the rails rushing past either side."),
                Idea("Up a ridge path", "Aim at the summit marker."),
                Idea("Through an avenue of trees", "The trunks flick past and the gap ahead grows.")
            ])

        // MARK: First look

        cards["REACTION"] = ShotCard(
            what: "Your face as you see the view for the first time.",
            whereItGoes: "The hook at the start of a reel, or the cut just before the big view.",
            how: ["Back camera at arm's length facing you, screen away. Start before you can see the view.",
                  "Walk up, look, and react how you really feel.",
                  "Then turn the phone round slowly to show what you're looking at."],
            ideas: [
                Idea("Stepping out of the trees", "Start in the forest and walk out onto the lookout."),
                Idea("The last bend before the falls", "Round the corner as the falls appear."),
                Idea("Topping the summit", "Climb the last few steps, then turn to the view."),
                Idea("Opening the curtains", "Your first look out of where you're staying."),
                Idea("Both of you at once", "Hold it wide enough for the two of you, then turn round."),
                Idea("Eyes shut, then open", "Get led to the spot with your eyes closed, then open them.")
            ])

        cards["REVEAL.walk-reveal"] = ShotCard(
            what: "Walking or rising from behind something until the view opens up.",
            whereItGoes: "The big moment of a reel: the payoff after the build-up.",
            how: ["Find something in front of the view: a rock, trees, a ridge.",
                  "Start on it, then walk or rise slowly until the view opens up.",
                  "Hold on the view for a few seconds at the end."],
            ideas: [
                Idea("Past a big rock", "Start with the rock filling the frame and step out sideways."),
                Idea("Through the trees", "Push through the last branches onto the view."),
                Idea("Over a ridge", "Start low behind the crest and rise as you walk up."),
                Idea("Round a corner", "Hug the wall, then step out onto the skyline or the street."),
                Idea("From behind your partner", "Start on their back, then step past them to what they're looking at."),
                Idea("Through a doorway", "From inside the hut or the café out onto the view.")
            ])

        cards["REVEAL.tilt-up"] = ShotCard(
            what: "From the water or the ground up to the view.",
            whereItGoes: "A one-shot reel on its own, or the opening of a place.",
            how: ["Stand at the edge and point the phone down at the water, the rocks or your feet.",
                  "Tilt up slowly and evenly.",
                  "Hold on the view at the end."],
            ideas: [
                Idea("Clear water to the falls", "Start on the stones under the water, then tilt up to the falls."),
                Idea("Your boots to the range", "Boots on the rock, then up to the mountains."),
                Idea("A rock pool to the bay", "From a pool at your feet up to the whole coastline."),
                Idea("Wildflowers to the peaks", "Close on the flowers, then up to the mountains."),
                Idea("Wet sand to the sunset", "The sky doubled in the sand, then up to the real one."),
                Idea("Straight down, then out", "Over a cliff edge, then up to the horizon.")
            ])

        cards["REVEAL.auto-zoom"] = ShotCard(
            what: "From the wide view in to the star of the place, with the app doing the zoom.",
            whereItGoes: "Pulls the eye to what matters: the peak, the falls, the tower.",
            how: ["Tripod, or brace yourself well. Frame it wide on 0.5x.",
                  "Put the star of the place in the middle of the frame.",
                  "Press record: the app zooms in smoothly over a few seconds."],
            ideas: [
                Idea("Into the summit", "From the whole range in to the one peak."),
                Idea("Into the falls", "From the gorge in to where the water drops."),
                Idea("Into a lighthouse", "From the whole headland in to the lighthouse."),
                Idea("Into a landmark", "From the skyline in to one tower."),
                Idea("Into your partner", "From the big view in to them, small on a rock."),
                Idea("Into an animal", "From the meadow in to the elk or deer grazing.")
            ])

        // MARK: At the spot

        cards["WHIP-1"] = ShotCard(
            what: "A fast whip from the side that lands on the view, to start this place in the edit.",
            whereItGoes: "The cut into a new place: it joins on to the last place's WHIP · OUT.",
            how: ["Point the phone to the left of the view.",
                  "Whip fast to the right and land on the view.",
                  "Hold steady for a couple of seconds."],
            ideas: [
                Idea("Onto the falls", "Land with the falls in the middle of the frame."),
                Idea("Onto the trail sign", "Land on the sign with the place's name."),
                Idea("Onto the big view", "Land on the range, the bay or the skyline."),
                Idea("Onto your partner", "Land on them looking out at the view.")
            ])

        cards["WIDE.establishing"] = ShotCard(
            what: "The place on its own: its size, its light and its mood, with no one in it.",
            whereItGoes: "The first shot of a reel, or the cut that says \u{201C}now we're somewhere new\u{201D}.",
            how: ["Find where the whole place shows. A bit of height helps.",
                  "Phone sideways. 0.5x for size, 1x if the view is far off.",
                  "Hold still for 20 seconds and let the scene do the moving."],
            ideas: [
                Idea("From where you first see it", "The view as it hit you, before anyone walks into it."),
                Idea("With a path or river leading in", "Put the trail or the river in a bottom corner, running towards the view. It pulls the eye in."),
                Idea("Framed through trees or rocks", "Dark edges in the corners make the bright view pop."),
                Idea("From above, looking down", "Climb a little higher than everyone else."),
                Idea("Sky above for a title", "Leave the top third as sky, so the place's name fits there."),
                Idea("Clouds or mist on the move", "Wait for something to move: the shot stays still, but it breathes.")
            ])

        cards["WIDE.alternative"] = ShotCard(
            what: "A clearly different shot of the same place.",
            whereItGoes: "The second shot of a place, so the edit can cut instead of sitting on one view.",
            how: ["Move before you film: higher, lower, further back or the other side.",
                  "Or change lens: 1x, or the 5x for a tighter look.",
                  "Hold still for 25 seconds. If something's happening, let it run."],
            ideas: [
                Idea("From the other side", "Walk round to see it from where few people stand."),
                Idea("Low to the ground", "Grass, rocks or water close in the bottom of the frame."),
                Idea("On the 5x", "Pick out one part: the top of the falls, a ridge, a building."),
                Idea("From further back", "Show what's around it: the valley, the coast, the city."),
                Idea("Into the light", "Film towards the sun for glow and mood."),
                Idea("Later in the day", "The same view in different light. Golden hour changes everything.")
            ])

        cards["WIDE.vertical-hero"] = ShotCard(
            what: "The best view, filmed upright, for reels that play full screen.",
            whereItGoes: "The full-screen moment of an upright reel: the opener or the ending.",
            how: ["Hold the phone upright, with the horizon on the bottom third.",
                  "Leave the top third for sky and a title.",
                  "Keep what matters near the middle: captions and buttons cover the edges."],
            ideas: [
                Idea("A tall waterfall", "Top to pool, all in one upright frame."),
                Idea("A peak above the trees", "The peak near the top, the forest below it."),
                Idea("A path running away", "The path from the bottom of the frame up into the view."),
                Idea("Cliffs and the sea", "Cliff top to waves in one tall frame."),
                Idea("Something tall in the city", "A tower or a spire, with sky above it."),
                Idea("A lone tree", "Upright, with plenty of sky.")
            ])

        cards["SLOMO.water"] = ShotCard(
            what: "Water, waves, spray or snow, slowed right down.",
            whereItGoes: "The calm, beautiful moments of a reel, often on a slow part of the song.",
            how: ["Bright light only: slow motion goes grainy in the shade.",
                  "Frame the action and hold the phone still.",
                  "Five seconds is plenty. Slowed down, it lasts much longer."],
            ideas: [
                Idea("Water hitting the pool", "Close on where the falls land, spray flying."),
                Idea("A wave on the rocks", "Wait for a big one and catch it bursting."),
                Idea("Your hand through a stream", "Drag your fingers through the water in the sun."),
                Idea("Snow thrown into the light", "Throw a handful up with the sun behind it."),
                Idea("Drops off a leaf", "Close on a leaf dripping after rain."),
                Idea("A stone into still water", "Drop it in and catch the splash and the rings.")
            ])

        cards["WIDE.human-scale"] = ShotCard(
            what: "You, or the two of you, small in the big view.",
            whereItGoes: "The heart of a travel reel: a person makes the place feel huge.",
            how: ["Tripod on 0.5x, the view filling the frame.",
                  "Use the 10-second countdown to walk to your spot, small, on a third line.",
                  "Stand, walk a few steps or look out: something natural."],
            ideas: [
                Idea("Looking out from the edge", "Your back to the camera, small on a rock or at the rail."),
                Idea("Sitting with the view", "On a rock or a log, taking it in."),
                Idea("Walking along the ridge", "Side-on, small against the sky."),
                Idea("The two of you side by side", "A little apart, so there's view between you."),
                Idea("Arms out at the top", "A simple shape that still reads when you're tiny."),
                Idea("At the water's edge", "Standing where the water meets the shore.")
            ])

        cards["WALKAWAY.into-view"] = ShotCard(
            what: "You walking away from the lens into the view, until you're small against it.",
            whereItGoes: "Openings and endings: walking off into the place.",
            how: ["Tripod at knee or hip height, with a path or ridge leading into the view.",
                  "Start just beside the phone, out of shot.",
                  "Walk straight away, slower than feels natural, and stop small on a third line."],
            ideas: [
                Idea("Up the trail", "The trail leads the eye, and you along it."),
                Idea("Along the ridge", "Side-on to the drop, the range ahead of you."),
                Idea("Down the waterline", "Footprints in the sand behind you."),
                Idea("Across the rocks to the falls", "Towards the spray, stopping at the edge."),
                Idea("Down a quiet lane", "Buildings either side, you walking away."),
                Idea("Through the meadow", "Long grass brushing your hands as you go.")
            ])

        cards["WALKAWAY.new-spot"] = ShotCard(
            what: "A second walk somewhere different, or with something new at the end.",
            whereItGoes: "Gives the edit a second choice, or a better ending.",
            how: ["Pick a new path, a closer frame or another direction.",
                  "Walk in from beside the phone, as before.",
                  "At the end, add an action: look back, reach for their hand, stop at the edge."],
            ideas: [
                Idea("Look back over your shoulder", "Stop, turn your head, a small smile."),
                Idea("Take your partner's hand", "Walk in together and link hands halfway."),
                Idea("Stop right at the edge", "Walk to the edge and stand still."),
                Idea("Sit down at the end", "Walk out and sit with the view."),
                Idea("Run the last bit", "Break into a jog towards the view."),
                Idea("Closer to the lens", "Start nearer, so you fill more of the frame as you go.")
            ])

        cards["TELE"] = ShotCard(
            what: "You, small, under something huge, stacked up by the 5x.",
            whereItGoes: "The \u{201C}how big is this?\u{201D} moment of a reel.",
            how: ["Tripod on the 5x, pointed at something huge: a peak, a cliff, the falls.",
                  "Use the 45-second countdown to walk 30 to 50 m out.",
                  "Stand still, then walk slowly across the frame."],
            ideas: [
                Idea("On a ridge, the peak behind", "The 5x makes the peak tower over you."),
                Idea("At the foot of the falls", "Tiny at the bottom, the water above you."),
                Idea("On the shoreline", "Small at the water's edge, the cliffs behind."),
                Idea("Under a tower", "On the pavement, the building rising above you."),
                Idea("In something bright", "Red or orange stands out when you're tiny."),
                Idea("Across the low sun", "Walk across the sunset for a dark shape.")
            ])

        cards["MOMENT.with-place"] = ShotCard(
            what: "Enjoying the place itself, for real: touching it, lying in it, taking it in.",
            whereItGoes: "The feeling of a reel: the shots that make people want to go.",
            how: ["Tripod with the view behind you, on 1x.",
                  "Forget the camera. Do something real, and keep moving gently.",
                  "It films at 60 fps, so the moment can be slowed down a little."],
            ideas: [
                Idea("Feet in the water", "Sit on a rock with your feet in the pool or the sea."),
                Idea("Lying back in the grass", "Arms out, looking at the sky."),
                Idea("Hands in the spray", "Reach into the mist of the falls."),
                Idea("Coffee with the view", "A thermos cup at the lookout."),
                Idea("Exploring the rocks", "Climbing, crouching, looking into a rock pool."),
                Idea("Catching your breath at the top", "Sit down at the summit and take it in.")
            ])

        cards["MOMENT.together"] = ShotCard(
            what: "A real moment with your partner, or a real reaction on your own.",
            whereItGoes: "Couple reels and endings: the warm moment people remember.",
            how: ["Tripod with the view behind you.",
                  "Don't look at the camera. Laugh, talk, move gently.",
                  "Let it run the full minute, so the real moment happens."],
            ideas: [
                Idea("A slow spin", "Hold hands and turn slowly."),
                Idea("Hand in hand", "Walk across the frame, the view behind you."),
                Idea("A kiss with the view", "Simple and real."),
                Idea("Laughing together", "Talk to each other and let it happen."),
                Idea("A hug at the top", "Right after the climb."),
                Idea("Sharing the view", "Point something out to each other.")
            ])

        cards["SLOMO.you"] = ShotCard(
            what: "A jump, a splash or a hair flick, slowed right down.",
            whereItGoes: "The fun beat of a reel, often right on the drop of the song.",
            how: ["Tripod, in bright light: slow motion needs it.",
                  "Stand in the middle of the frame, where the action will be.",
                  "Count in, then jump, splash or flick, once."],
            ideas: [
                Idea("A jump into the waterhole", "Side-on, the splash filling the frame."),
                Idea("A jump at the top", "Against the sky, arms up."),
                Idea("A hair flick in the sun", "Lit from behind, so your hair glows."),
                Idea("Kicking up water", "In the shallows, the spray catching the light."),
                Idea("Throwing snow up", "Both hands, with the sun behind it."),
                Idea("A run into the sea", "Towards the waves, spray flying.")
            ])

        // MARK: Creative

        cards["ONETAKE"] = ShotCard(
            what: "Five of your tripod shots in one long take, from one set-up.",
            whereItGoes: "A quick way to get WIDE, WALKAWAY, MOMENT, MATCH CUT and CLONE in one go.",
            how: ["Tripod at hip height, sideways, with room to walk out into the view.",
                  "Choose the parts and how long each runs on the camera's card.",
                  "Five flashes lead into each part. Your remote moves you on."],
            ideas: [
                Idea("A summit with room to walk", "Walk out along the top, stand small, come back."),
                Idea("A rock shelf at the falls", "Walk out towards the spray and back again."),
                Idea("An empty beach", "Walk down to the water and along it."),
                Idea("A quiet meadow", "Walk out through the grass and lie back in it.")
            ])

        cards["MATCHCUT"] = ShotCard(
            what: "One move, done the same way at every place, so the edit can cut between places mid-move.",
            whereItGoes: "Same frame, many places: some of the most-watched reels you've saved.",
            how: ["Tripod at hip height. Pick one move and keep it for the whole trip.",
                  "Press record and stand where you'll do it: it zooms until you're the same size as last time.",
                  "Five flashes, then do the move once."],
            ideas: [
                Idea("Run across", "Out of shot to the left, then run across the frame on the flashes."),
                Idea("Leap", "One big jump in the middle of the frame."),
                Idea("Arms out", "Back to the lens, arms rising out wide to the view."),
                Idea("Spin", "One turn on the spot, facing the phone."),
                Idea("Fall back", "Backwards onto grass, sand or snow."),
                Idea("Snap", "Close up and upright: snap your fingers and the place changes."),
                Idea("Ridge walk", "Tiny on the 5x, walking a ridge at the same pace every time.")
            ])

        cards["CLONE"] = ShotCard(
            what: "A few minutes of you all over one still frame, for clones.",
            whereItGoes: "Playful reels: several of you in one place at once.",
            how: ["Tripod only: the phone mustn't move. Shade or cloud works best.",
                  "Start with the frame empty, then go to a new spot each time it flashes.",
                  "Do something different at each spot, and walk out at the end."],
            ideas: [
                Idea("Sitting, standing, pointing", "Three different poses at three spots."),
                Idea("You taking your own photo", "One of you photographing another one."),
                Idea("Around a picnic", "Pouring, eating, lying back."),
                Idea("Spread near to far", "One close to the lens, one in the middle, one small at the back."),
                Idea("Lost and found", "One of you reading the map, another pointing the way.")
            ])

        cards["ORBIT"] = ShotCard(
            what: "A slow circle around your partner, the place turning behind them.",
            whereItGoes: "A smooth, cinematic moment between the bigger shots.",
            how: ["They stand still, 1.5 to 2 m away.",
                  "Gimbal, or both hands at chest height, elbows in and knees bent.",
                  "Walk sideways in a slow arc, keeping them in the middle."],
            ideas: [
                Idea("On the summit", "The range sweeping round behind them."),
                Idea("On a rock in the river", "Water all around as you circle."),
                Idea("At the end of a jetty", "Sea on every side."),
                Idea("In a quiet square", "The buildings turning behind them."),
                Idea("In the long grass", "Low and slow.")
            ])

        cards["DANCE"] = ShotCard(
            what: "You dancing or lip-syncing to your song, with the view behind you.",
            whereItGoes: "The cinematic dance reels you love: the song plays on while the places change.",
            how: ["Tripod, phone upright, far enough back for all of you.",
                  "AirPods in: the song starts in the countdown, so your part lands as it records.",
                  "At each new spot, carry on from 10 seconds before where you stopped."],
            ideas: [
                Idea("A lookout over the valley", "The big view filling the frame behind you."),
                Idea("The beach at sunset", "Warm light, the sea behind you."),
                Idea("A mountain meadow", "Wildflowers and peaks."),
                Idea("A rooftop over the city", "The skyline behind you."),
                Idea("One move at every spot", "Repeat a move, so the edit can cut on it.")
            ])

        cards["SILHOUETTE"] = ShotCard(
            what: "The two of you as dark shapes against a glowing sky.",
            whereItGoes: "Endings and slow, emotional moments, right at sunset.",
            how: ["Tripod low, so you're against the sky, with the sun behind you.",
                  "Best in the 15 minutes either side of sunset.",
                  "Stand side-on, a little apart, and move slowly."],
            ideas: [
                Idea("Holding hands", "Side-on, with a gap of sky between you."),
                Idea("Arms out", "A clear shape against the glow."),
                Idea("A jump", "Both of you at the same time."),
                Idea("A kiss", "Side-on, so the shapes meet."),
                Idea("Along the ridge", "Walking against the last of the light.")
            ])

        cards["TALK~1"] = ShotCard(
            what: "One line to the front camera at the spot, with the place behind you.",
            whereItGoes: "The hook at the start of a guide: proof you were really there.",
            how: ["Front camera at arm's length, a little above your eyes.",
                  "Say one line, like \u{201C}Nobody told me Colorado looked like this.\u{201D}",
                  "Do it two or three times and keep the best."],
            ideas: [
                Idea("Nobody told me", "\u{201C}Nobody told me Colorado looked like this.\u{201D}"),
                Idea("How far you came", "\u{201C}Two hours of walking for this.\u{201D}"),
                Idea("Your honest verdict", "\u{201C}Worth every single step.\u{201D}"),
                Idea("The one tip", "\u{201C}Get here early, or don't bother.\u{201D}"),
                Idea("A question", "\u{201C}Would you do this hike?\u{201D}")
            ])

        // MARK: Leaving

        cards["WHIP-0"] = ShotCard(
            what: "Hold on the view, then whip away fast, to end this place in the edit.",
            whereItGoes: "The cut out of a place: it joins on to the next place's WHIP · IN.",
            how: ["Hold on the view for two seconds.",
                  "Whip the phone hard to the right.",
                  "Whip the same way as your WHIP · IN, so the cut lines up."],
            ideas: [
                Idea("Off the big view", "Hold on the range or the bay, then whip."),
                Idea("Off the falls", "Hold on the falls, then whip."),
                Idea("Off your café table", "Coffee, then whip to the next place."),
                Idea("Off the sunset", "The last shot of the day, then whip home.")
            ])

        cards["STAY"] = ShotCard(
            what: "Your first walk into where you're staying.",
            whereItGoes: "Stay tours, and the \u{201C}where we slept\u{201D} part of a trip reel.",
            how: ["Film it the moment you arrive, before you unpack.",
                  "Start outside with the door shut, then walk in slowly with it rolling.",
                  "Say what you really think, and show the best bits."],
            ideas: [
                Idea("The door opening", "Start on the handle and push it open."),
                Idea("Straight to the view", "Walk to the window or out onto the balcony."),
                Idea("The bed and the bath", "A slow look at the best bits."),
                Idea("Opening the curtains", "Light flooding in."),
                Idea("Your first reaction", "Say it out loud.")
            ])

        // MARK: B-roll

        cards["BROLL.atmosphere"] = ShotCard(
            what: "Light, weather and mood: the feel of the place.",
            whereItGoes: "Under a line of text, or between the bigger shots, to set the mood.",
            how: ["Find something the light or the weather is doing.",
                  "Hold the phone still and let it happen.",
                  "Twelve seconds, no panning."],
            ideas: [
                Idea("Mist in the trees", "Morning mist drifting through the forest."),
                Idea("Clouds over the peaks", "Clouds moving across the tops."),
                Idea("Sun through the leaves", "Point up through the canopy for flickering light."),
                Idea("Rain on water", "Drops landing on a pool or a puddle."),
                Idea("Golden light on the grass", "Low sun across a meadow."),
                Idea("Your breath in the cold", "Or steam rising off water in the morning.")
            ])

        cards["BROLL.people"] = ShotCard(
            what: "Someone doing something: walkers, a guide, people at the lookout.",
            whereItGoes: "It shows the place is real and lived in. Small or from behind is fine.",
            how: ["Find people doing something, at a distance or from behind.",
                  "Hold still and let them move through the frame.",
                  "Ten seconds."],
            ideas: [
                Idea("Hikers on the trail", "Small on a switchback below you."),
                Idea("People at the lookout", "From behind, looking out."),
                Idea("A guide with a group", "Talking and pointing, from a distance."),
                Idea("Climbers on the rock", "On the 5x, from far away."),
                Idea("Someone fishing", "On the bank or a jetty."),
                Idea("A busy market", "Stalls and hands, faces small.")
            ])

        cards["BROLL.movement"] = ShotCard(
            what: "Something moving through the frame.",
            whereItGoes: "Gives a reel energy, and cuts well on the beat.",
            how: ["Find something that moves: water, birds, traffic, a flag.",
                  "Hold still and let it move through the frame.",
                  "Ten seconds."],
            ideas: [
                Idea("A river rushing past", "Close to the water, the current flowing through the frame."),
                Idea("Birds taking off", "Wait for the flock to lift."),
                Idea("Cars on the road below", "From a lookout above."),
                Idea("A flag in the wind", "Against the sky."),
                Idea("A train or a tram", "Let it cross the frame."),
                Idea("Waves rolling in", "From the sand, the waves running up to you.")
            ])

        cards["BROLL.local"] = ShotCard(
            what: "What makes this place this place.",
            whereItGoes: "Says where you are without a word, and makes a great title shot.",
            how: ["Find the sign, the landmark or the local thing.",
                  "Frame it with the subject in the middle.",
                  "Hold still, or drift very slowly, for eight seconds."],
            ideas: [
                Idea("The park's sign", "The name in the frame, the place behind it."),
                Idea("A trail marker", "With the trail running on behind it."),
                Idea("The landmark", "The famous building, bridge or peak."),
                Idea("A shop front", "The colours and the old signs."),
                Idea("A street sign", "The street's name, with the street behind it."),
                Idea("Something only here", "A carving, a statue, a local plant.")
            ])

        cards["BROLL.lens-angle"] = ShotCard(
            what: "A contrasting look at the place.",
            whereItGoes: "Breaks up the wide shots, so the edit doesn't feel the same all the way through.",
            how: ["Switch to the 5x, or go very low, very high, or film through something.",
                  "Hold very still: long lenses show every shake.",
                  "Ten seconds."],
            ideas: [
                Idea("A far ridge on the 5x", "Layers of mountains stacked up."),
                Idea("At ground level", "The phone on the ground, the path running away."),
                Idea("Through a gap", "Between rocks, leaves or fence posts."),
                Idea("Straight up", "Trees, cliffs or buildings from below."),
                Idea("Straight down", "From a bridge or a lookout."),
                Idea("Through a window", "The place framed from inside.")
            ])

        cards["BROLL.transition"] = ShotCard(
            what: "A shot that moves the edit on to what's next.",
            whereItGoes: "Between two shots or two places, to hide the cut.",
            how: ["Find something that can pass close to the lens: a tree, a post, a door.",
                  "Walk past it, let it pass, or pan away.",
                  "Six seconds is plenty."],
            ideas: [
                Idea("Past a tree trunk", "Walk past it so it wipes across the frame."),
                Idea("A door opening", "From the dark into the light."),
                Idea("A car passing close", "Near the road, the car filling the frame."),
                Idea("Pan up to the sky", "From the scene up into the sky."),
                Idea("Your hand over the lens", "Cover it, then pull your hand away."),
                Idea("Through a bush", "Push through leaves close to the lens.")
            ])

        cards["BROLL.nature"] = ShotCard(
            what: "Something alive in the scene: plants, animals or water.",
            whereItGoes: "A swap-in when the place is missing one of the other kinds.",
            how: ["Find something alive: a plant, a bird, moving water.",
                  "Get close and hold still.",
                  "Ten seconds."],
            ideas: [
                Idea("Wildflowers in the wind", "Low, with the flowers moving."),
                Idea("A bird on a branch", "On the 5x, with room on the side it's facing."),
                Idea("A stream over stones", "Close to the water."),
                Idea("Moss on a log", "Slide slowly along it."),
                Idea("A butterfly or a bee", "Wait for it to land.")
            ])

        cards["BROLL.into-light"] = ShotCard(
            what: "Facing the sun for flare, glowing edges or silhouettes.",
            whereItGoes: "A swap-in when the place is missing one of the others: warm, dreamy, cinematic.",
            how: ["Face the sun, with it just behind something: a tree, a rock, a person.",
                  "Let a little of it peek out for flare.",
                  "Hold still, or drift slowly past the sun."],
            ideas: [
                Idea("Sun through the trees", "Slide past a trunk so the sun peeks out."),
                Idea("Glowing grass", "Low sun behind long grass."),
                Idea("Your partner's outline", "The sun behind them, their edges glowing."),
                Idea("Sun on the water", "Sparkles on a lake or the sea."),
                Idea("Flare on the windscreen", "From the passenger seat, the low sun across the glass.")
            ])

        cards["DETAIL.texture"] = ShotCard(
            what: "The place up close: the surface of things.",
            whereItGoes: "Quick cutaways between the bigger shots. They make a reel feel rich.",
            how: ["Get close to a surface and tap it to focus.",
                  "Hold, or slide very slowly across it.",
                  "Eight seconds."],
            ideas: [
                Idea("Rock and lichen", "Side light makes the texture stand out."),
                Idea("Bark", "Slide slowly up the trunk."),
                Idea("Ripples on water", "Sun glinting on the surface."),
                Idea("Sand", "Wind moving the grains, or your footprints."),
                Idea("Ice or frost", "Close in on the crystals."),
                Idea("Old weathered wood", "A fence, a bench, a jetty.")
            ])

        cards["DETAIL.object"] = ShotCard(
            what: "Something that tells the story: a sign, a map, a ticket, your gear.",
            whereItGoes: "Shows what you did and used: great in guides and price lists.",
            how: ["Pick the thing and tap it to focus.",
                  "Hold steady, or slide very slowly.",
                  "Six seconds."],
            ideas: [
                Idea("The trail map", "On the board, or the one in your hand."),
                Idea("Your park pass", "On the dash, or in your hand at the gate."),
                Idea("Your boots", "Laced up, dusty from the trail."),
                Idea("Your coffee", "On the rail with the view behind it."),
                Idea("The menu", "At the café or the food truck."),
                Idea("Your pack and gear", "Laid out before you set off.")
            ])

        cards["DETAIL.hands"] = ShotCard(
            what: "Your hand touching the place.",
            whereItGoes: "Makes the viewer feel they're there with you.",
            how: ["Frame the spot with your hand just out of shot.",
                  "Reach in and touch it slowly.",
                  "Film with your other hand, close in, for ten seconds."],
            ideas: [
                Idea("Fingers in the water", "In a stream or the pool, the sun on it."),
                Idea("A hand on the rock", "Run your palm across it."),
                Idea("Through long grass", "Brushing the tops as you walk."),
                Idea("On the rail at the lookout", "The view soft beyond your hand."),
                Idea("Picking up a shell", "Or a stone from the creek."),
                Idea("Brushing off snow", "From a rail or a branch.")
            ])

        cards["DETAIL.foreground"] = ShotCard(
            what: "Something close and sharp, with the view soft behind it.",
            whereItGoes: "Adds depth: a cinematic way to show the place.",
            how: ["Get close to something in front: flowers, a fence, leaves.",
                  "Tap the close thing to focus, so the view goes soft.",
                  "Hold, or slide slowly past it, for eight seconds."],
            ideas: [
                Idea("Wildflowers and the peaks", "The flowers sharp, the mountains soft."),
                Idea("A fence and the field", "Slide along the fence posts."),
                Idea("Leaves and the falls", "The falls soft through the leaves."),
                Idea("A glass and the sunset", "Your drink sharp, the sun soft."),
                Idea("Grass and the lake", "Low in the grass at the shore.")
            ])

        cards["DETAIL.only-here"] = ShotCard(
            what: "A small detail you'd only find here.",
            whereItGoes: "The detail that makes this place different from everywhere else.",
            how: ["Look for what's unusual: a carving, a local sign, a special plant.",
                  "Tap it to focus first.",
                  "Hold steady for eight seconds."],
            ideas: [
                Idea("A carving or a plaque", "Close enough to read."),
                Idea("A local plant", "Something you won't see at home."),
                Idea("An old sign", "Faded paint, rusty edges."),
                Idea("Animal tracks", "In the mud or the snow."),
                Idea("Local food or craft", "At a market stall.")
            ])

        cards["DETAIL.nature"] = ShotCard(
            what: "A small living thing, up close.",
            whereItGoes: "A swap-in for a detail this place doesn't have.",
            how: ["Get close to a leaf, a flower, drops of water or an insect.",
                  "Tap it to focus.",
                  "Hold still, and let it move if it's alive."],
            ideas: [
                Idea("Drops on a leaf", "After rain, or in the spray."),
                Idea("A flower in the breeze", "Low, against the sky."),
                Idea("An insect on a stem", "Wait for it to move."),
                Idea("A pine cone or a seed pod", "On the ground, side-lit."),
                Idea("Dew on a web", "First thing in the morning.")
            ])

        cards["AMBIENT"] = ShotCard(
            what: "Thirty seconds of the place's own sound.",
            whereItGoes: "Under the whole edit, so the reel sounds like being there.",
            how: ["Point at the sound: water, wind, birds.",
                  "Stay silent and still. No talking, no footsteps.",
                  "Turn your body to block the wind."],
            ideas: [
                Idea("The roar of the falls", "Close enough to hear it, out of the spray."),
                Idea("Wind at the top", "Sheltered behind a rock, so it's the wind, not the rumble."),
                Idea("Birdsong on the trail", "Stop somewhere quiet and wait."),
                Idea("Waves on the sand", "Near the waterline."),
                Idea("A busy street", "On a corner, the city going by."),
                Idea("Rain on the roof", "From inside, the window open a little.")
            ])

        cards["SOUNDS"] = ShotCard(
            what: "Close-ups made for their sound.",
            whereItGoes: "Punchy sound cuts: footsteps, a splash, a zip, right on the beat.",
            how: ["Get the phone 20 to 50 cm from the sound.",
                  "Quiet, then make the sound once, then quiet again.",
                  "Block the wind with your body."],
            ideas: [
                Idea("Boots on gravel", "Close to the ground as you step."),
                Idea("A splash", "A stone, a hand or a foot in the water."),
                Idea("A zip on your pack", "Close in, one slow pull."),
                Idea("A can opening", "Right by the phone."),
                Idea("Pouring a coffee", "From the thermos into the cup."),
                Idea("A stick snapping", "Over your knee.")
            ])

        cards["WILDLIFE"] = ShotCard(
            what: "Animals up close, on the 5x.",
            whereItGoes: "Animals stop the scroll: a great opener, or a surprise in the middle.",
            how: ["Stay well back and let the 5x get close. Never feed or follow them.",
                  "Brace your elbows on a rock or a rail, or use the tripod.",
                  "Wait for a moment: a look up, a chew, a step."],
            ideas: [
                Idea("Elk or deer grazing", "Room on the side they're facing."),
                Idea("A bird on a branch", "Wait for it to turn its head."),
                Idea("A squirrel or a chipmunk", "Low, at its level."),
                Idea("Goats on the cliffs", "Small on the rock, the drop below."),
                Idea("Ducks on the lake", "Ripples spreading behind them."),
                Idea("Fish in clear water", "From a bridge, looking straight down.")
            ])

        cards["FOOD"] = ShotCard(
            what: "Local food, close and slow.",
            whereItGoes: "Food breaks up a reel and gets saved: cafés, snacks, the first bite.",
            how: ["Get close and tap the food to focus. Window light looks best.",
                  "Slide slowly across it, or catch the first bite, the pour or the steam.",
                  "Eight seconds."],
            ideas: [
                Idea("The first bite", "Close on the fork or the hand."),
                Idea("The pour", "Coffee, a beer, syrup."),
                Idea("Steam rising", "Against a dark background."),
                Idea("Snacks with a view", "On a rock at the lookout."),
                Idea("The menu board", "Chalk and prices, for cost guides."),
                Idea("Cheers", "Two cups or glasses meeting.")
            ])

        cards["REFLECTION"] = ShotCard(
            what: "The scene doubled in still water.",
            whereItGoes: "A calm, beautiful shot that stops the scroll.",
            how: ["Find still water. Lakes are calmest first thing in the morning.",
                  "Phone sideways, the camera just above the water. Don't let it touch.",
                  "Frame half reflection, half scene, and hold."],
            ideas: [
                Idea("Mountains in a calm lake", "Early, before the wind gets up."),
                Idea("The falls in a rock pool", "Low beside the pool."),
                Idea("Sky in wet sand", "At low tide, as the waves pull back."),
                Idea("Lights in a puddle", "After rain, in the city."),
                Idea("Someone walking through", "A figure doubled in the water."),
                Idea("Trees in a pond", "Autumn colours, twice.")
            ])

        cards["TIMELAPSE"] = ShotCard(
            what: "Clouds, light or crowds, sped up.",
            whereItGoes: "Time passing: the start or end of a day, or a breather in the edit.",
            how: ["Tripod on solid ground. Something still in front helps, like a rock or a tree.",
                  "Leave it running 10 minutes or more: that's 20 seconds of video.",
                  "Plug in a power bank for long ones."],
            ideas: [
                Idea("Clouds over the peaks", "Wide, with the range along the bottom."),
                Idea("The sun going down", "Start 20 minutes before sunset."),
                Idea("Shadows across a valley", "Late afternoon, from up high."),
                Idea("Mist through the falls", "From a spot out of the spray."),
                Idea("Traffic at blue hour", "From a bridge or a rooftop."),
                Idea("The tide going out", "On the beach, the water slipping away.")
            ])

        // MARK: At home

        cards["HOME-0"] = ShotCard(
            what: "The quiet start, at home before you go.",
            whereItGoes: "The opening of a trip reel, so the trip has a beginning.",
            how: ["Prop the phone on a shelf, a bench or the tripod.",
                  "Do the ordinary thing: pack, look out, wait.",
                  "Don't look at the lens. Twenty seconds."],
            ideas: [
                Idea("Zipping up your bag", "On the bed, half packed."),
                Idea("Boots by the door", "Ready to go."),
                Idea("A last look out the window", "Checking the weather."),
                Idea("Waiting at the gate", "With a coffee, the plane outside."),
                Idea("Locking the door", "Keys in hand, bag on your back.")
            ])

        cards["HOME-1"] = ShotCard(
            what: "Back home at night, lit only by your phone.",
            whereItGoes: "The end of a trip reel: the full stop.",
            how: ["Prop the phone on the bedside table or the tripod.",
                  "Turn the room lights off, so it's just your phone's glow.",
                  "Scroll, smile at the screen, stare at the ceiling."],
            ideas: [
                Idea("Scrolling through the trip", "A small smile at the screen."),
                Idea("The bag dropped by the door", "Still packed."),
                Idea("Unpacking", "Sand or dirt falling out of your boots."),
                Idea("Asleep with the phone on you", "The screen still glowing.")
            ])

        cards["TALK~0"] = ShotCard(
            what: "You talking to the camera about the trip, from a script made from your place facts.",
            whereItGoes: "Guides and stories: your face and voice carry the reel, with the trip's footage cut in.",
            how: ["Paste in your script, then set the phone on the tripod at eye level, by a window.",
                  "Front camera: the script scrolls just under the lens.",
                  "Read it a little slower than feels natural. Two or three takes."],
            ideas: [
                Idea("How to do it in a day", "The route, the stops, the timing."),
                Idea("What it cost", "Every cost, and the total each."),
                Idea("What I'd do differently", "Honest tips from the day."),
                Idea("Is it worth it?", "Your verdict, with the reasons."),
                Idea("The story of the day", "What happened, and how it felt.")
            ])

        cards["VOICEOVER"] = ShotCard(
            what: "Your voice over the footage, from a script that fits the edit.",
            whereItGoes: "Guides and itineraries: your words run over the trip's best shots.",
            how: ["Paste in your script.",
                  "Somewhere quiet. A wardrobe full of clothes kills the echo.",
                  "Hold the phone a hand's width from your mouth and read it through."],
            ideas: [
                Idea("The itinerary", "Where you went, in order, and when."),
                Idea("The costs", "What it all came to."),
                Idea("The story", "How the day went, and how it felt."),
                Idea("Tips for going", "What to know before you go.")
            ])

        return cards
    }()
}
