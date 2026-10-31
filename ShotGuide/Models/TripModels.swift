import Foundation

struct Clip: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var shot: String
    var take: Int
    var variant: String?
    var recordedAt: Date
    var timeZoneID: String
    var durationSeconds: Double
    var latitude: Double?
    var longitude: Double?
    var light: String
    var lens: String
    var fps: Int
    var resolution: String
    var inShot: Bool
    var tags: [String]
    var favourite: Bool
    var notes: String
    /// A black-and-white video of where you are in each frame, for cutout effects. Made when the trip is copied.
    var maskFileName: String? = nil
    /// Subtitles (.srt) of what you said, made when the trip is copied.
    var captionsFileName: String? = nil
    /// What you said, as text. Empty once a clip has been checked and had no speech.
    var transcript: String? = nil
    /// Seconds into the clip where you tapped Mark during recording.
    var marks: [Double]? = nil

    var shotType: ShotType? { ShotType(rawValue: shot) }

    var isPhoto: Bool {
        ["heic", "heif", "jpg", "jpeg", "png", "dng"].contains((fileName as NSString).pathExtension.lowercased())
    }

    var isAudio: Bool {
        (fileName as NSString).pathExtension.lowercased() == "m4a"
    }
}

/// Details about the place, for text on screen and "things to know before you go" reels.
struct TripFacts: Codable, Hashable {
    var distance = ""
    var time = ""
    var elevation = ""
    var difficulty = ""
    var cost = ""
    var parking = ""
    var gettingThere = ""
    var bestTime = ""
    var tips = ""

    init() {}

    // Each field is optional when reading, so facts saved by older versions still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distance = try container.decodeIfPresent(String.self, forKey: .distance) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
        elevation = try container.decodeIfPresent(String.self, forKey: .elevation) ?? ""
        difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty) ?? ""
        cost = try container.decodeIfPresent(String.self, forKey: .cost) ?? ""
        parking = try container.decodeIfPresent(String.self, forKey: .parking) ?? ""
        gettingThere = try container.decodeIfPresent(String.self, forKey: .gettingThere) ?? ""
        bestTime = try container.decodeIfPresent(String.self, forKey: .bestTime) ?? ""
        tips = try container.decodeIfPresent(String.self, forKey: .tips) ?? ""
    }

    private var labelled: [(String, String)] {
        [("Distance", distance), ("Time", time), ("Elevation gain", elevation), ("Difficulty", difficulty),
         ("Cost", cost), ("Parking", parking), ("Getting there", gettingThere), ("Best time to go", bestTime), ("Tips", tips)]
            .map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
    }

    var isEmpty: Bool { labelled.isEmpty }

    /// One line for the trip page, like "8 km return · 3 hours · Hard · Free".
    var summary: String {
        [distance, time, difficulty, cost]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The facts as plain text, for facts.txt next to the clips.
    var text: String {
        labelled.map { "\($0.0): \($0.1)" }.joined(separator: "\n") + "\n"
    }
}

struct Trip: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var place: String
    var fileCode: String
    var state: String
    var country: String
    var countryCode: String
    var continent: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    /// Relative to the app's Documents folder, e.g. "Library/Oceania/Australia/Queensland/2026-11-08 Mount Barney".
    var folderPath: String
    var clips: [Clip] = []
    var facts: TripFacts? = nil

    var regionLine: String {
        [state, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func takes(of shot: ShotType) -> [Clip] {
        clips.filter { $0.shot == shot.rawValue }.sorted { $0.take < $1.take }
    }

    func takeCount(of shot: ShotType) -> Int {
        clips.filter { $0.shot == shot.rawValue }.count
    }

    /// Counted row by row on the trip page, so a transition needs both its Out and In halves.
    var targetTotal: Int {
        TripPhase.allSlots.filter { $0.shot.countsTowardTotal }.reduce(0) { $0 + $1.target }
    }

    var doneTotal: Int {
        TripPhase.allSlots.filter { $0.shot.countsTowardTotal }.reduce(0) { $0 + min($1.takeCount(in: self), $1.target) }
    }
}
