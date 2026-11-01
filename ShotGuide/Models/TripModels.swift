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
    /// What you called it, like "Lower Falls". It goes on the end of the file name.
    var name: String? = nil
    /// The day of the trip it was filmed on. nil means day 1 (clips from before days existed).
    var day: Int? = nil
    /// The take check: how much the phone shook (degrees a second, ignoring slow smooth moves)
    /// and how far it leaned (degrees, + is clockwise).
    var shake: Double? = nil
    var tilt: Double? = nil
    /// What the take check said, like "Steady and level", and whether the take passed.
    var check: String? = nil
    var checkPassed: Bool? = nil
    /// The zoom on screen when the take started, like 1 or 2.5. MATCH CUT uses it to line up the next one.
    var zoom: Double? = nil
    /// The file was removed from the phone after it was copied to the SSD. The trip still lists it.
    var removedFromPhone: Bool? = nil
    /// DANCE: the song, its copy in the trip folder, and where in the song (seconds) the clip's first frame is.
    var songName: String? = nil
    var songFile: String? = nil
    var songStart: Double? = nil
    /// "Apple Log", or "Normal" where Log wasn't available for the shot. nil for clips from before 1.9
    /// and ones added from Photos.
    var colourProfile: String? = nil
    /// The white balance the take was locked to, and the ISO and shutter speed (seconds) as it started.
    var whiteBalance: WhiteBalance? = nil
    var iso: Int? = nil
    var shutter: Double? = nil

    static let appleLog = "Apple Log"
    static let normalColour = "Normal"

    var shotType: ShotType? { ShotType(rawValue: shot) }

    var isLog: Bool { colourProfile == Clip.appleLog }

    /// "1/60", for the catalogue and the review screen.
    var shutterText: String? {
        guard let shutter, shutter > 0 else { return nil }
        if shutter >= 1 {
            return String(format: "%.1fs", shutter)
        }
        return "1/\(Int((1 / shutter).rounded()))"
    }

    var dayNumber: Int { day ?? 1 }

    var isOnPhone: Bool { removedFromPhone != true }

    /// The name, or nil when there isn't one.
    var displayName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Added from Photos rather than filmed in Shot Guide.
    var isAdded: Bool { lens.hasPrefix("Added") }

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
    /// Every day of the trip, from day 1. nil for trips from before days existed: they have one General day.
    var days: [TripDay]? = nil

    var regionLine: String {
        [state, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var allDays: [TripDay] {
        if let days, !days.isEmpty {
            return days.sorted { $0.number < $1.number }
        }
        return [TripDay(number: 1, startedAt: createdAt, place: place, fileCode: fileCode, type: .general,
                        latitude: latitude, longitude: longitude)]
    }

    var lastDayNumber: Int {
        allDays.last?.number ?? 1
    }

    func day(_ number: Int) -> TripDay {
        let all = allDays
        return all.first { $0.number == number } ?? all[0]
    }

    func clips(onDay number: Int) -> [Clip] {
        clips.filter { $0.dayNumber == number }
    }

    func takeCount(of shot: ShotType, day number: Int) -> Int {
        clips.filter { $0.shot == shot.rawValue && $0.dayNumber == number }.count
    }

    /// Counted row by row on the trip page, so a transition needs both its Out and In halves.
    func targetTotal(day number: Int) -> Int {
        let type = day(number).type
        return TripPhase.allSlots.filter { $0.counts(for: type) }.reduce(0) { $0 + $1.target(for: type) }
    }

    func doneTotal(day number: Int) -> Int {
        let type = day(number).type
        return TripPhase.allSlots.filter { $0.counts(for: type) }.reduce(0) {
            $0 + min($1.takeCount(in: self, day: number), $1.target(for: type))
        }
    }

    var targetTotal: Int {
        allDays.reduce(0) { $0 + targetTotal(day: $1.number) }
    }

    var doneTotal: Int {
        allDays.reduce(0) { $0 + doneTotal(day: $1.number) }
    }

    /// "14 November 2026", or "14–15 November 2026 · 2 days" once the trip has more than one day.
    var dateLine: String {
        let all = allDays
        guard all.count > 1, let first = all.first, let last = all.last else {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: createdAt)
        }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: first.startedAt, to: last.startedAt) + " · \(all.count) days"
    }
}
