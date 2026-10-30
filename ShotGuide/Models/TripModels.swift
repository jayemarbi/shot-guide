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

    var shotType: ShotType? { ShotType(rawValue: shot) }
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

    var regionLine: String {
        [state, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func takes(of shot: ShotType) -> [Clip] {
        clips.filter { $0.shot == shot.rawValue }.sorted { $0.take < $1.take }
    }

    func takeCount(of shot: ShotType) -> Int {
        clips.filter { $0.shot == shot.rawValue }.count
    }

    var targetTotal: Int {
        ShotType.allCases.reduce(0) { $0 + $1.targetTakes }
    }

    var doneTotal: Int {
        ShotType.allCases.reduce(0) { $0 + min(takeCount(of: $1), $1.targetTakes) }
    }
}
