import Foundation

struct TagGroup: Identifiable, Hashable {
    let name: String
    let tags: [String]
    var id: String { name }
}

enum TagVocabulary {
    static let groups: [TagGroup] = [
        TagGroup(name: "Water", tags: ["waterfall", "beach", "ocean", "river", "creek", "lake", "swimming hole", "rock pool", "reef", "island"]),
        TagGroup(name: "Land", tags: ["mountain", "summit", "ridge", "cliff", "canyon", "gorge", "cave", "valley", "forest", "rainforest", "desert", "rocks", "flowers", "snow"]),
        TagGroup(name: "Sky and light", tags: ["sunrise", "sunset", "golden hour", "blue hour", "night", "stars", "clouds", "fog", "storm", "rainbow", "aurora"]),
        TagGroup(name: "Wildlife", tags: ["wildlife", "whale", "dolphin", "bird", "kangaroo", "koala"]),
        TagGroup(name: "Activity", tags: ["hiking", "scrambling", "swimming", "surfing", "camping", "road trip", "boat", "flight"]),
        TagGroup(name: "People", tags: ["me", "couple", "mates", "crowd", "empty"]),
        TagGroup(name: "Mood", tags: ["calm", "epic", "romantic", "playful", "cosy"]),
        TagGroup(name: "Places", tags: ["city", "lookout", "track"])
    ]

    static var allStarterTags: [String] {
        groups.flatMap { $0.tags }
    }

    /// Labels from the iPhone's built-in image recognition, mapped onto our tags.
    static let visionMap: [String: String] = [
        "waterfall": "waterfall",
        "beach": "beach",
        "shore": "beach",
        "ocean": "ocean",
        "coral_reef": "reef",
        "underwater": "reef",
        "river": "river",
        "waterways": "river",
        "creek": "creek",
        "lake": "lake",
        "island": "island",
        "mountain": "mountain",
        "hill": "mountain",
        "cliff": "cliff",
        "canyon": "canyon",
        "cave": "cave",
        "rocks": "rocks",
        "desert": "desert",
        "sand_dune": "desert",
        "snow": "snow",
        "glacier": "snow",
        "iceberg": "snow",
        "blizzard": "snow",
        "forest": "forest",
        "jungle": "rainforest",
        "flower": "flowers",
        "cloudy": "clouds",
        "storm": "storm",
        "thunderstorm": "storm",
        "lightning": "storm",
        "night_sky": "stars",
        "aurora": "aurora",
        "rainbow": "rainbow",
        "haze": "fog",
        "animal": "wildlife",
        "bird": "bird",
        "whale": "whale",
        "dolphin": "dolphin",
        "kangaroo": "kangaroo",
        "koala": "koala",
        "crowd": "crowd",
        "hiking": "hiking",
        "trail": "track",
        "camping": "camping",
        "tent": "camping",
        "swimming": "swimming",
        "surfing": "surfing",
        "boat": "boat",
        "kayak": "boat",
        "watercraft": "boat",
        "road": "road trip",
        "car": "road trip",
        "cityscape": "city",
        "street": "city",
        "building": "city"
    ]
}
