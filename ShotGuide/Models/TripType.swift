import Foundation

/// Changes to one shot for a type of trip: more or fewer takes, how much it matters, and what to film.
struct ShotTuning {
    var target: Int? = nil
    var tier: ShotTier? = nil
    var summary: String? = nil
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

    /// The takes a light day asks for: a little of each core shot.
    func lightDayTarget(for shot: ShotType) -> Int {
        tier(for: shot) == .core ? min(shot.lightDayTakes, target(for: shot)) : 0
    }

    func summary(for shot: ShotType) -> String {
        tuning(for: shot)?.summary ?? shot.summary
    }

    /// What to film for this type, shown on the camera. nil when the type has nothing special for the shot.
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
        case .general: return nil
        }
    }

    // A first draft from general know-how. The reel breakdowns will sharpen these. Since 1.19 a target is the
    // number of creative roles a shot needs (see Coverage.swift): falls have five kinds of DETAIL to fill.

    private static let mountainTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(summary: "The drive in and the trailhead"),
        .pov: ShotTuning(summary: "The trail ahead: roots, rocks, your boots"),
        .reveal: ShotTuning(summary: "The summit view opening up"),
        .ambient: ShotTuning(summary: "Wind on the summit, birds on the trail"),
        .wide: ShotTuning(summary: "The range, and how far you've climbed"),
        .walkaway: ShotTuning(summary: "You walking up the trail or along the ridge"),
        .tele: ShotTuning(summary: "You, small, on the ridge or the summit"),
        .timelapse: ShotTuning(summary: "Clouds rolling over the peaks"),
        .wildlife: ShotTuning(summary: "Goats, deer, marmots, eagles")
    ]

    private static let fallsTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(summary: "The drive up: winding roads, rainforest out the window"),
        .pov: ShotTuning(summary: "The track in: ferns, roots, the first sound of water"),
        .reveal: ShotTuning(summary: "The falls opening up through the trees"),
        .ambient: ShotTuning(target: 2, summary: "30 seconds of the falls, nothing else"),
        .detail: ShotTuning(target: 5, summary: "Moss, ferns, drops on leaves"),
        .wide: ShotTuning(summary: "The whole falls, top to pool"),
        .slomo: ShotTuning(target: 3, summary: "Water hitting the pool, at 120 fps"),
        .tele: ShotTuning(summary: "You, small, at the foot of the falls"),
        .timelapse: ShotTuning(summary: "Mist and light moving through the falls"),
        .wildlife: ShotTuning(summary: "Birds, lizards, anything at the water")
    ]

    private static let beachTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(summary: "The coast road and the first glimpse of water"),
        .pov: ShotTuning(summary: "Walking down onto the sand"),
        .reveal: ShotTuning(summary: "The beach opening up below you"),
        .ambient: ShotTuning(summary: "30 seconds of waves"),
        .detail: ShotTuning(summary: "Sand, shells, rock pools, water on rocks"),
        .wide: ShotTuning(summary: "The whole bay and the coastline"),
        .slomo: ShotTuning(target: 2, summary: "Waves breaking, a splash, a run into the water"),
        .walkaway: ShotTuning(summary: "You walking along the waterline"),
        .tele: ShotTuning(summary: "You, small, at the water's edge"),
        .timelapse: ShotTuning(summary: "The tide, clouds or the sun going down"),
        .wildlife: ShotTuning(summary: "Birds, crabs, dolphins offshore")
    ]

    private static let cityTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(summary: "Trains, trams and the drive in"),
        .pov: ShotTuning(summary: "Walking the streets at eye level"),
        .follow: ShotTuning(target: 1, tier: .fullDay, summary: "Led by the hand through the crowd"),
        .reveal: ShotTuning(summary: "Round a corner onto the skyline"),
        .ambient: ShotTuning(summary: "30 seconds of street sound"),
        .detail: ShotTuning(summary: "Signs, coffee, neon, textures"),
        .food: ShotTuning(target: 2, tier: .core, summary: "Street food and cafes, close and slow"),
        .bRoll: ShotTuning(summary: "Streets, people, traffic, signs and lights"),
        .wide: ShotTuning(summary: "The skyline or the street, and its scale"),
        .slomo: ShotTuning(summary: "A crowd crossing, pigeons, a splash"),
        .tele: ShotTuning(summary: "You, small, under the towers"),
        .timelapse: ShotTuning(target: 2, summary: "Traffic or crowds at blue hour")
    ]

    private static let roadTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(target: 4, tier: .core, summary: "The road ahead, out the window and at each stop"),
        .pov: ShotTuning(summary: "Walking from the car at each stop"),
        .detail: ShotTuning(summary: "Road signs, the dash, maps, details at each stop"),
        .wide: ShotTuning(summary: "Each stop and its scale"),
        .timelapse: ShotTuning(summary: "The road from the dash, or the sky at a stop")
    ]

    private static let snowTuning: [ShotType: ShotTuning] = [
        .onTheWay: ShotTuning(summary: "The drive up: snowy roads and trees"),
        .pov: ShotTuning(summary: "Footsteps in the snow"),
        .reveal: ShotTuning(summary: "The white valley opening up"),
        .ambient: ShotTuning(summary: "Snow crunching, wind, the quiet"),
        .detail: ShotTuning(summary: "Frost, snowflakes, icicles"),
        .wide: ShotTuning(summary: "The snowfield and the peaks"),
        .slomo: ShotTuning(target: 2, summary: "Snow being thrown, kicked or falling"),
        .tele: ShotTuning(summary: "You, small, in the snowfield"),
        .timelapse: ShotTuning(summary: "Clouds over the snowy peaks"),
        .wildlife: ShotTuning(summary: "Elk and deer in the snow")
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
