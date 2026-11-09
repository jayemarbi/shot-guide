import Foundation

/// Changes to one shot for a type of trip: more or fewer takes, how much it matters, what to film, and how many a
/// light day asks for.
struct ShotTuning {
    var target: Int? = nil
    var tier: ShotTier? = nil
    /// What to film here, on the trip page and the camera. Every type has one for every shot (1.26).
    var summary: String? = nil
    /// The takes a light day asks for, where the type changes it: the place's signature shot (1.26).
    var lightDay: Int? = nil
    /// Optional roles that count here, like WIDE's vertical hero at waterfalls, which are tall (1.26).
    var alsoCounts: [String] = []
}

/// What kind of trip, or day of a trip, it is. Each type tunes the shot list: which shots count,
/// how many takes they need, and the tips on the trip page and camera. General is the standard list.
enum TripType: String, Codable, CaseIterable, Identifiable {
    case mountain
    case falls
    case beach
    case city
    case road
    case snow
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mountain: return "Mountain and hiking"
        case .falls: return "Waterfalls and rainforest"
        case .beach: return "Beach and coast"
        case .city: return "City"
        case .road: return "Road trip"
        case .snow: return "Snow"
        case .general: return "General"
        }
    }

    var subtitle: String {
        switch self {
        case .mountain: return "The trail, the summit, the big view"
        case .falls: return "Moving water, ferns and moss, the sound of the falls"
        case .beach: return "Waves, sand, cliffs, sunrise and sunset"
        case .city: return "Streets, food, crowds and lights"
        case .road: return "The drive and the stops along the way"
        case .snow: return "Filmed a little brighter, so snow stays white"
        case .general: return "The standard shot list, for anything else"
        }
    }

    var symbol: String {
        switch self {
        case .mountain: return "mountain.2.fill"
        case .falls: return "leaf.fill"
        case .beach: return "beach.umbrella.fill"
        case .city: return "building.2.fill"
        case .road: return "car.fill"
        case .snow: return "snowflake"
        case .general: return "map.fill"
        }
    }

    /// Snow fools the camera into making white look grey, so snow days film a little brighter.
    var exposureBias: Float { self == .snow ? 0.7 : 0 }

    func target(for shot: ShotType) -> Int {
        tuning(for: shot)?.target ?? shot.targetTakes
    }

    /// Core (everyday), full day or extra, for this type of trip.
    func tier(for shot: ShotType) -> ShotTier {
        tuning(for: shot)?.tier ?? shot.tier
    }

    /// Whether the shot counts towards a day at all (core or full day).
    func counts(_ shot: ShotType) -> Bool {
        tier(for: shot) != .extra
    }

    /// The takes a light day asks for: a little of each core shot, with the place's signature shot in it (1.26).
    func lightDayTarget(for shot: ShotType) -> Int {
        guard tier(for: shot) == .core else { return 0 }
        return min(tuning(for: shot)?.lightDay ?? shot.lightDayTakes, target(for: shot))
    }

    /// Optional roles of a shot that count on this type of day, like WIDE's vertical hero at waterfalls (1.26).
    func countsOptionalRoles(of shot: ShotType) -> [String] {
        tuning(for: shot)?.alsoCounts ?? []
    }

    func summary(for shot: ShotType) -> String {
        tuning(for: shot)?.summary ?? shot.summary
    }

    /// What to film for this type, shown on the camera before the set-up. Every type has one for every shot (1.26).
    func tip(for shot: ShotType) -> String? {
        tuning(for: shot)?.summary
    }

    func tuning(for shot: ShotType) -> ShotTuning? {
        switch self {
        case .mountain: return Self.mountainTuning[shot]
        case .falls: return Self.fallsTuning[shot]
        case .beach: return Self.beachTuning[shot]
        case .city: return Self.cityTuning[shot]
        case .road: return Self.roadTuning[shot]
        case .snow: return Self.snowTuning[shot]
        case .general: return Self.generalTuning[shot]
        }
    }

    // Each place gets the shots its reels need (1.26). Every type has a tip for every shot, so the trip page and the
    // camera always say what to film there. Mountains make slow edits from a few huge shots with you small in them;
    // falls and beaches run on moving water and slow motion; cities make fast edits from lots of short street shots;
    // road trips run on the drive and the same move at every stop. General is the standard list. A target is the
    // number of roles a shot needs (see Coverage.swift), and a light day is 10 clips with the place's signature shot.

    private static let generalTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Packing to leave, then back in bed lit by your phone"),
        .onTheWay: ShotTuning(summary: "The trip there: windows, roads, boats and trains"),
        .whip: ShotTuning(summary: "A fast whip from one place to the next"),
        .pov: ShotTuning(summary: "What your eyes see on the way in, and moving through"),
        .hyperlapse: ShotTuning(summary: "A slow walk towards something, sped up into a glide"),
        .follow: ShotTuning(summary: "Led by the hand towards the view"),
        .reaction: ShotTuning(summary: "Your first real look at the view"),
        .reveal: ShotTuning(summary: "The view opening up from behind something"),
        .oneTake: ShotTuning(summary: "WIDE, WALKAWAY, MOMENT, MATCH CUT and CLONE in one long take"),
        .wide: ShotTuning(summary: "The place on its own, you small in it, and another angle"),
        .slomo: ShotTuning(summary: "Water, waves, a splash or a jump, in bright light"),
        .talk: ShotTuning(summary: "One thing worth knowing: a fact, a feeling or a tip"),
        .walkaway: ShotTuning(summary: "You walking away into the view until you're small in it"),
        .tele: ShotTuning(summary: "You, small, under something huge, on the 5x"),
        .matchCut: ShotTuning(summary: "Your move, done the same way at every place"),
        .moment: ShotTuning(summary: "A real moment with the place, and one together"),
        .orbit: ShotTuning(summary: "A slow circle around your partner, the place turning behind"),
        .clone: ShotTuning(summary: "You at several spots in one locked-off frame"),
        .dance: ShotTuning(summary: "Your song, danced or lip-synced with the view behind you"),
        .silhouette: ShotTuning(summary: "The two of you against the sunset"),
        .bRoll: ShotTuning(summary: "Six kinds of footage that show the place, without you in it"),
        .detail: ShotTuning(summary: "Four close-ups: textures, objects, your hands, something only here"),
        .reflection: ShotTuning(summary: "The scene doubled in still water"),
        .wildlife: ShotTuning(summary: "Any animal worth a look, close on the 5x"),
        .food: ShotTuning(summary: "Local food, close and slow: the first bite, the pour, the steam"),
        .sounds: ShotTuning(summary: "Close-ups made for their sound: footsteps, a splash, a zip"),
        .ambient: ShotTuning(summary: "30 seconds of the place's own sound, nothing else"),
        .timelapse: ShotTuning(summary: "Clouds, light or crowds, sped up"),
        .voiceover: ShotTuning(summary: "What the place was like and how it felt, in your words"),
        .stay: ShotTuning(summary: "Your first walk into where you're staying")
    ]

    // Mountain and hiking: TELE counts every day and is on a light day, WILDLIFE counts on full days, and SLOMO is
    // an extra, as there's rarely water or spray to slow down.
    private static let mountainTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Boots and pack by the door, then aching legs in bed"),
        .onTheWay: ShotTuning(summary: "The drive in, the road winding up and the trailhead"),
        .whip: ShotTuning(summary: "Off the summit view, or onto the next trail"),
        .pov: ShotTuning(summary: "The trail ahead: roots, rocks, your boots"),
        .hyperlapse: ShotTuning(summary: "Up steps, a boardwalk or a ridge path towards the peak"),
        .follow: ShotTuning(summary: "Led up the last steps to the summit"),
        .reaction: ShotTuning(summary: "Your first look from the summit or the lookout"),
        .reveal: ShotTuning(summary: "The summit view opening up as you top the ridge"),
        .oneTake: ShotTuning(summary: "One long take from a summit or lookout with room to walk out"),
        .wide: ShotTuning(summary: "The range, and how far you've climbed"),
        .slomo: ShotTuning(tier: .extra, summary: "A jump on the summit, or hair and a jacket in the wind"),
        .talk: ShotTuning(summary: "The trail: how far, how hard, and whether it's worth it"),
        .walkaway: ShotTuning(summary: "You walking up the trail or along the ridge"),
        .tele: ShotTuning(tier: .core, summary: "You, small, on a ridge or the summit, the range stacked behind", lightDay: 1),
        .matchCut: ShotTuning(summary: "Your move on the summit or the ridge, the range behind"),
        .moment: ShotTuning(summary: "Lying back on the summit, a snack with the view, a hug at the top"),
        .orbit: ShotTuning(summary: "Round your partner on the summit, the range turning behind"),
        .clone: ShotTuning(summary: "All over a summit plateau or a wide rock shelf"),
        .dance: ShotTuning(summary: "On a summit or a ridge with the range behind you"),
        .silhouette: ShotTuning(summary: "On the ridge or the summit at sunset"),
        .bRoll: ShotTuning(summary: "Cloud on the peaks, other hikers, the summit sign, far ridges on the 5x", lightDay: 2),
        .detail: ShotTuning(summary: "Lichen and rock, wildflowers, your boots, the trail marker"),
        .reflection: ShotTuning(summary: "A peak in a still alpine lake or a puddle on the trail"),
        .wildlife: ShotTuning(tier: .fullDay, summary: "Wallabies, goats, deer, eagles"),
        .food: ShotTuning(summary: "Summit snacks, a thermos, lunch with a view"),
        .sounds: ShotTuning(summary: "Boots on gravel, poles on rock, a creek crossing"),
        .ambient: ShotTuning(summary: "Wind on the summit, birds on the trail"),
        .timelapse: ShotTuning(summary: "Clouds rolling over the peaks, or shadows crossing the valley"),
        .voiceover: ShotTuning(summary: "The climb, the view from the top, and how it felt"),
        .stay: ShotTuning(summary: "A hut, a cabin or the tent, with the mountains out the door")
    ]

    // Waterfalls and rainforest: SLOMO counts every day and is on a light day, WIDE counts its vertical hero (falls
    // are tall), WILDLIFE counts on full days, DETAIL asks for all five and AMBIENT for two. WALKAWAY needs one, and
    // SILHOUETTE is an extra, as a gorge rarely has open sky at sunset.
    private static let fallsTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Swimmers and a towel packed, then back in bed lit by your phone"),
        .onTheWay: ShotTuning(summary: "The drive up: winding roads, rainforest out the window"),
        .whip: ShotTuning(summary: "Off the falls, or into the next pool"),
        .pov: ShotTuning(summary: "The track in: ferns, roots, the first sound of water"),
        .hyperlapse: ShotTuning(summary: "Along a boardwalk through the rainforest towards the falls"),
        .follow: ShotTuning(summary: "Led along the track towards the sound of the falls"),
        .reaction: ShotTuning(summary: "Your first look at the falls"),
        .reveal: ShotTuning(summary: "Tilt up from the pool to the falls, or the falls through the trees"),
        .oneTake: ShotTuning(summary: "One long take from the rocks by the pool, with room to walk out"),
        .wide: ShotTuning(target: 4, summary: "The whole falls, top to pool, and upright for the vertical hero",
                          alsoCounts: ["vertical-hero"]),
        .slomo: ShotTuning(target: 2, tier: .core, summary: "Water hitting the pool, spray or a jump in: film it in the sun",
                           lightDay: 1),
        .talk: ShotTuning(summary: "The walk in: how long, how hard, and whether you can swim"),
        .walkaway: ShotTuning(target: 1, summary: "You walking towards the falls along the track or the rocks"),
        .tele: ShotTuning(summary: "You, small, at the foot of the falls"),
        .matchCut: ShotTuning(summary: "Your move on the rocks in front of the falls"),
        .moment: ShotTuning(summary: "Feet in the pool, a swim, spray on your face"),
        .orbit: ShotTuning(summary: "Round your partner on a rock, the falls turning behind"),
        .clone: ShotTuning(summary: "Around the pool and the rocks below the falls"),
        .dance: ShotTuning(summary: "On a rock in front of the falls"),
        .silhouette: ShotTuning(tier: .extra, summary: "Against the bright falls, or at a lookout at sunset"),
        .bRoll: ShotTuning(summary: "Mist, people at the pool, flowing water, the track sign, the lip on the 5x", lightDay: 2),
        .detail: ShotTuning(target: 5, summary: "Moss, ferns, drops on leaves, your hand in the water"),
        .reflection: ShotTuning(summary: "The falls in a still rock pool"),
        .wildlife: ShotTuning(target: 1, tier: .fullDay, summary: "Water dragons, birds, turtles at the pool"),
        .food: ShotTuning(summary: "A picnic by the pool, or a café on the drive"),
        .sounds: ShotTuning(summary: "A splash, water over stones, rain on leaves"),
        .ambient: ShotTuning(target: 2, summary: "30 seconds of the falls, nothing else"),
        .timelapse: ShotTuning(summary: "Mist and light moving through the falls"),
        .voiceover: ShotTuning(summary: "The walk in, the sound of the falls, the swim"),
        .stay: ShotTuning(summary: "A rainforest cabin or a treehouse")
    ]

    // Beach and coast: SLOMO counts every day and is on a light day (beaches are bright, which slow motion needs),
    // and REFLECTION counts on full days, for wet sand doubling the sky.
    private static let beachTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Towels and sunscreen packed, then sandy and sun-tired in bed"),
        .onTheWay: ShotTuning(summary: "The coast road and the first glimpse of water"),
        .whip: ShotTuning(summary: "Off the waves, or onto the next beach"),
        .pov: ShotTuning(summary: "Walking down onto the sand"),
        .hyperlapse: ShotTuning(summary: "Along a jetty, a boardwalk or the waterline"),
        .follow: ShotTuning(summary: "Led down the sand into the water"),
        .reaction: ShotTuning(summary: "Your first look at the water from the dunes or the lookout"),
        .reveal: ShotTuning(summary: "The beach opening up below you, or tilt up from the water"),
        .oneTake: ShotTuning(summary: "One long take on the sand, the sea in front and room to walk out"),
        .wide: ShotTuning(summary: "The whole bay and the coastline"),
        .slomo: ShotTuning(target: 2, tier: .core, summary: "Waves breaking, a splash, a run into the water", lightDay: 1),
        .talk: ShotTuning(summary: "The beach: getting there, the swim, the best time to come"),
        .walkaway: ShotTuning(summary: "You walking along the waterline"),
        .tele: ShotTuning(summary: "You, small, at the water's edge"),
        .matchCut: ShotTuning(summary: "Your move on the sand with the sea behind"),
        .moment: ShotTuning(summary: "Running into the water, lying on the sand, a swim together"),
        .orbit: ShotTuning(summary: "Round your partner at the water's edge"),
        .clone: ShotTuning(summary: "All over the sand: sitting, swimming, walking the waterline"),
        .dance: ShotTuning(summary: "On the sand with the sea behind you"),
        .silhouette: ShotTuning(summary: "On the sand or the rocks at sunrise or sunset"),
        .bRoll: ShotTuning(summary: "Sea spray, surfers, breaking waves, the surf club flags, the coast on the 5x", lightDay: 2),
        .detail: ShotTuning(summary: "Sand, shells, rock pools, water on rocks"),
        .reflection: ShotTuning(tier: .fullDay, summary: "Wet sand at low tide, or a rock pool, doubling the sky"),
        .wildlife: ShotTuning(summary: "Birds, crabs, dolphins offshore"),
        .food: ShotTuning(summary: "Fish and chips, ice cream, a beach café"),
        .sounds: ShotTuning(summary: "Waves dragging pebbles, footsteps in sand, a splash"),
        .ambient: ShotTuning(summary: "30 seconds of waves"),
        .timelapse: ShotTuning(summary: "The tide, clouds, or the sun going down"),
        .voiceover: ShotTuning(summary: "The water, the light, and how the day felt"),
        .stay: ShotTuning(summary: "A beach house, a deck or a room facing the water")
    ]

    // City: more of the small stuff (B-ROLL 7, DETAIL 5, FOOD every day and on a light day, HYPERLAPSE and FOLLOW on
    // full days) and less of the big views (REVEAL and WALKAWAY need one, one WIDE on a light day, SILHOUETTE an
    // extra, as city sunsets need a rooftop).
    private static let cityTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Packing for the city, then home and tired in bed"),
        .onTheWay: ShotTuning(summary: "Trains, trams and the drive in"),
        .whip: ShotTuning(summary: "Off one street and onto the next"),
        .pov: ShotTuning(summary: "Walking the streets at eye level"),
        .hyperlapse: ShotTuning(tier: .fullDay, summary: "A crowded street towards a landmark, or over a long bridge"),
        .follow: ShotTuning(target: 1, tier: .fullDay, summary: "Led by the hand through the crowd"),
        .reaction: ShotTuning(summary: "Your first look at the skyline or the square"),
        .reveal: ShotTuning(target: 1, summary: "Round a corner onto the skyline or a landmark"),
        .oneTake: ShotTuning(summary: "One long take in a quiet square or park with room to walk out"),
        .wide: ShotTuning(summary: "The skyline or the street, and its scale", lightDay: 1),
        .slomo: ShotTuning(summary: "A crowd crossing, pigeons taking off, a splash"),
        .talk: ShotTuning(summary: "The city: what to see, where to eat, how to get around"),
        .walkaway: ShotTuning(target: 1, summary: "You walking away down a street or across a square"),
        .tele: ShotTuning(summary: "You, small, under the towers"),
        .matchCut: ShotTuning(summary: "Your move in a square or a street with a landmark behind"),
        .moment: ShotTuning(summary: "Coffee with a view, sitting on steps, wandering together"),
        .orbit: ShotTuning(summary: "Round your partner in a quiet square"),
        .clone: ShotTuning(summary: "Around a quiet square or a set of steps"),
        .dance: ShotTuning(summary: "In a square or on steps with the city behind you"),
        .silhouette: ShotTuning(tier: .extra, summary: "Against the sunset from a rooftop or a bridge"),
        .bRoll: ShotTuning(target: 7,
                           summary: "Seven kinds today: streets, people, traffic, signs, and a park or the sun between towers"),
        .detail: ShotTuning(target: 5, summary: "Signs, coffee, neon, tickets, textures"),
        .reflection: ShotTuning(summary: "The skyline in a puddle or a fountain"),
        .wildlife: ShotTuning(summary: "Pigeons, gulls, a cat in a doorway"),
        .food: ShotTuning(target: 2, tier: .core, summary: "Street food and cafés, close and slow", lightDay: 1),
        .sounds: ShotTuning(summary: "A coffee machine, a tram bell, footsteps on cobbles"),
        .ambient: ShotTuning(summary: "30 seconds of street sound"),
        .timelapse: ShotTuning(target: 2, summary: "Traffic or crowds at blue hour"),
        .voiceover: ShotTuning(summary: "The streets, the food, and the feel of the place"),
        .stay: ShotTuning(summary: "A hotel room with a view over the city")
    ]

    // Road trip: ON THE WAY counts every day and is on a light day, MATCH CUT counts every day (the same move at every
    // stop), TIMELAPSE counts on full days, REVEAL and WALKAWAY need one as there's less time at each stop, and SLOMO
    // is an extra.
    private static let roadTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Bags in the boot, then home and road-tired in bed"),
        .onTheWay: ShotTuning(target: 4, tier: .core,
                              summary: "The road ahead, out the window, the side mirror and each stop", lightDay: 1),
        .whip: ShotTuning(summary: "Out of one stop and into the next"),
        .pov: ShotTuning(summary: "Walking from the car at each stop"),
        .hyperlapse: ShotTuning(summary: "Down a long straight road, or a path from the car park"),
        .follow: ShotTuning(summary: "Led from the car to the lookout"),
        .reaction: ShotTuning(summary: "Your first look at each stop"),
        .reveal: ShotTuning(target: 1, summary: "Each stop opening up as you walk from the car"),
        .oneTake: ShotTuning(summary: "One long take at a stop with a big view and room to walk out"),
        .wide: ShotTuning(summary: "Each stop and its scale"),
        .slomo: ShotTuning(tier: .extra, summary: "Dust kicked up on a dirt road, a jump at a stop"),
        .talk: ShotTuning(summary: "The drive: the route, how long it takes, the stops worth making"),
        .walkaway: ShotTuning(target: 1, summary: "You walking from the car out into the view"),
        .tele: ShotTuning(summary: "You, small, on a long straight road or under a big landscape"),
        .matchCut: ShotTuning(tier: .core, summary: "Your move at every stop, done the same way each time"),
        .moment: ShotTuning(summary: "Sitting on the bonnet with the view, a stretch at a lookout"),
        .orbit: ShotTuning(summary: "Round your partner at a lookout"),
        .clone: ShotTuning(summary: "Around the car at a big, empty stop"),
        .dance: ShotTuning(summary: "Beside the car at a big, empty stop"),
        .silhouette: ShotTuning(summary: "Against the sunset beside the road or on the car"),
        .bRoll: ShotTuning(summary: "Passing cars, signs, the town at each stop, the road on the 5x", lightDay: 2),
        .detail: ShotTuning(summary: "Road signs, the dash, a map, details at each stop"),
        .reflection: ShotTuning(summary: "The sky and hills in a roadside lake or dam"),
        .wildlife: ShotTuning(summary: "Kangaroos, cows, horses or birds along the way"),
        .food: ShotTuning(summary: "Roadside bakeries, diners and servo coffee"),
        .sounds: ShotTuning(summary: "Doors shutting, the indicator, tyres on gravel"),
        .ambient: ShotTuning(summary: "30 seconds at a stop: wind, birds, a passing car"),
        .timelapse: ShotTuning(tier: .fullDay, summary: "The road from the dash, or the sky at a stop"),
        .voiceover: ShotTuning(summary: "The route, the stops and the road in between"),
        .stay: ShotTuning(summary: "A motel, a cabin or a campsite along the way")
    ]

    // Snow: SLOMO counts every day and is on a light day, and TELE counts every day, as you small and dark on white
    // stands out more than anything else.
    private static let snowTuning: [ShotType: ShotTuning] = [
        .home: ShotTuning(summary: "Beanie and gloves packed, then warm in bed"),
        .onTheWay: ShotTuning(summary: "The drive up: snowy roads and trees"),
        .whip: ShotTuning(summary: "Off the white slope, or onto the next one"),
        .pov: ShotTuning(summary: "Footsteps in the snow"),
        .hyperlapse: ShotTuning(summary: "Along a snowy path or through the village"),
        .follow: ShotTuning(summary: "Led through the snow towards the view"),
        .reaction: ShotTuning(summary: "Your first look at the snow"),
        .reveal: ShotTuning(summary: "The white valley opening up"),
        .oneTake: ShotTuning(summary: "One long take on a flat snowfield with room to walk out"),
        .wide: ShotTuning(summary: "The snowfield and the peaks"),
        .slomo: ShotTuning(target: 2, tier: .core, summary: "Snow being thrown, kicked or falling", lightDay: 1),
        .talk: ShotTuning(summary: "The snow: getting there, what to wear, the best runs or walks"),
        .walkaway: ShotTuning(summary: "You walking away through fresh snow, leaving footprints"),
        .tele: ShotTuning(tier: .core, summary: "You, small and dark against the white"),
        .matchCut: ShotTuning(summary: "Your move in the snow with the peaks behind"),
        .moment: ShotTuning(summary: "Snow angels, a snowball fight, snow thrown into the light"),
        .orbit: ShotTuning(summary: "Round your partner in the snow"),
        .clone: ShotTuning(summary: "All over a flat snowfield"),
        .dance: ShotTuning(summary: "In the snow with the peaks behind you"),
        .silhouette: ShotTuning(summary: "Against the pink glow on the snow at sunset"),
        .bRoll: ShotTuning(summary: "Skiers, falling snow, the lifts, chalets, the peaks on the 5x", lightDay: 2),
        .detail: ShotTuning(summary: "Frost, snowflakes on your glove, icicles"),
        .reflection: ShotTuning(summary: "Snowy peaks in a lake that hasn't frozen"),
        .wildlife: ShotTuning(summary: "Elk, deer or wombats in the snow"),
        .food: ShotTuning(summary: "Hot chocolate by the fire"),
        .sounds: ShotTuning(summary: "Boots crunching, skis on snow, a snowball hitting"),
        .ambient: ShotTuning(summary: "Snow crunching, wind, the quiet"),
        .timelapse: ShotTuning(summary: "Clouds over the snowy peaks"),
        .voiceover: ShotTuning(summary: "The cold, the quiet, and how it felt"),
        .stay: ShotTuning(summary: "A cabin or a chalet with the snow outside")
    ]
}

/// One day of a trip. Every trip starts with day 1 and you add the rest as you go. A day can move on
/// to a new place (its clips are named after it) and have its own type.
struct TripDay: Codable, Hashable, Identifiable {
    var number: Int
    var startedAt: Date
    var place: String
    var fileCode: String
    var type: TripType
    var latitude: Double?
    var longitude: Double?

    var id: Int { number }

    /// "Day 1 · Sat 14 Nov"
    var label: String {
        "Day \(number) · " + Self.dateFormatter.string(from: startedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()
}
