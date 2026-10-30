import Foundation

/// Keeps every trip in its own folder: Library/<continent>/<country>/<state>/<date> <place>/,
/// with the clips, a catalog.csv for spreadsheets and a trip.json for the app.
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []

    let documents: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        load()
    }

    var libraryURL: URL {
        documents.appendingPathComponent("Library", isDirectory: true)
    }

    func folderURL(for trip: Trip) -> URL {
        documents.appendingPathComponent(trip.folderPath, isDirectory: true)
    }

    func trip(id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    // MARK: Loading and saving

    func load() {
        var found: [Trip] = []
        if let enumerator = FileManager.default.enumerator(at: libraryURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent == "trip.json" {
                if let data = try? Data(contentsOf: url), let trip = try? decoder.decode(Trip.self, from: data) {
                    found.append(trip)
                }
            }
        }
        trips = found.sorted { $0.createdAt > $1.createdAt }
    }

    private func write(_ trip: Trip) throws {
        let folder = folderURL(for: trip)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = try encoder.encode(trip)
        try json.write(to: folder.appendingPathComponent("trip.json"), options: .atomic)
        let csv = Self.catalogCSV(for: trip)
        try Data(csv.utf8).write(to: folder.appendingPathComponent("catalog.csv"), options: .atomic)
    }

    private func replace(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        try? write(trip)
    }

    // MARK: Trips

    @discardableResult
    func createTrip(place: String, fileCode: String, state: String, countryCode: String, continent: String,
                    latitude: Double?, longitude: Double?) throws -> Trip {
        let now = Date()
        let country = countryCode.isEmpty ? "" : GeoData.countryName(countryCode)
        let day = Self.dayString(now, timeZone: .current)
        let parents = [
            "Library",
            Self.safe(continent.isEmpty ? "Unknown continent" : continent),
            Self.safe(country.isEmpty ? "Unknown country" : country),
            Self.safe(state.isEmpty ? "Unknown state" : state)
        ]
        var folderName = Self.safe("\(day) \(place)")
        var relative = (parents + [folderName]).joined(separator: "/")
        var counter = 2
        while FileManager.default.fileExists(atPath: documents.appendingPathComponent(relative).path) {
            folderName = Self.safe("\(day) \(place) (\(counter))")
            relative = (parents + [folderName]).joined(separator: "/")
            counter += 1
        }
        let trip = Trip(
            place: place,
            fileCode: Self.fileCode(for: fileCode.isEmpty ? place : fileCode),
            state: state,
            country: country,
            countryCode: countryCode,
            continent: continent,
            latitude: latitude,
            longitude: longitude,
            createdAt: now,
            folderPath: relative)
        try write(trip)
        trips.insert(trip, at: 0)
        return trip
    }

    func deleteTrip(_ id: UUID) {
        guard let trip = self.trip(id: id) else { return }
        try? FileManager.default.removeItem(at: folderURL(for: trip))
        trips.removeAll { $0.id == id }
    }

    // MARK: Clips

    func nextTake(tripID: UUID, shot: ShotType) -> Int {
        guard let trip = self.trip(id: tripID) else { return 1 }
        return (trip.clips.filter { $0.shot == shot.rawValue }.map { $0.take }.max() ?? 0) + 1
    }

    /// Where the next clip goes, named the playbook way: Place_YYYY-MM-DD_SHOT_##.mov
    func newClipURL(tripID: UUID, shot: ShotType, take: Int, date: Date) -> URL? {
        guard let trip = self.trip(id: tripID) else { return nil }
        let folder = folderURL(for: trip)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let day = Self.dayString(date, timeZone: .current)
        var number = take
        var url = folder.appendingPathComponent(Self.clipName(code: trip.fileCode, day: day, shot: shot, take: number))
        while FileManager.default.fileExists(atPath: url.path) {
            number += 1
            url = folder.appendingPathComponent(Self.clipName(code: trip.fileCode, day: day, shot: shot, take: number))
        }
        return url
    }

    func addClip(_ clip: Clip, to tripID: UUID) {
        guard var trip = self.trip(id: tripID) else { return }
        trip.clips.append(clip)
        replace(trip)
    }

    func updateClip(_ clip: Clip, in tripID: UUID) {
        guard var trip = self.trip(id: tripID), let index = trip.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        trip.clips[index] = clip
        replace(trip)
    }

    func deleteClip(_ clipID: UUID, from tripID: UUID) {
        guard var trip = self.trip(id: tripID), let clip = trip.clips.first(where: { $0.id == clipID }) else { return }
        try? FileManager.default.removeItem(at: folderURL(for: trip).appendingPathComponent(clip.fileName))
        trip.clips.removeAll { $0.id == clipID }
        replace(trip)
    }

    func clipURL(_ clip: Clip, in trip: Trip) -> URL {
        folderURL(for: trip).appendingPathComponent(clip.fileName)
    }

    // MARK: Export

    /// Packs a trip into one .zip at the top of the app's folder, keeping the
    /// Library/<continent>/<country>/<state>/ folders inside it.
    func exportTrip(_ trip: Trip, completion: @escaping (Result<URL, Error>) -> Void) {
        let source = folderURL(for: trip)
        let relative = trip.folderPath
        let destination = documents.appendingPathComponent(Self.safe(source.lastPathComponent) + ".zip")
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: staging) }
            do {
                let stagedTrip = staging.appendingPathComponent(relative, isDirectory: true)
                try fileManager.createDirectory(at: stagedTrip, withIntermediateDirectories: true)
                for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    let target = stagedTrip.appendingPathComponent(item.lastPathComponent)
                    do {
                        try fileManager.linkItem(at: item, to: target)
                    } catch {
                        try fileManager.copyItem(at: item, to: target)
                    }
                }
                let root = staging.appendingPathComponent("Library", isDirectory: true)
                var coordinatorError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: root, options: [.forUploading], error: &coordinatorError) { zipURL in
                    do {
                        if fileManager.fileExists(atPath: destination.path) {
                            try fileManager.removeItem(at: destination)
                        }
                        try fileManager.copyItem(at: zipURL, to: destination)
                    } catch {
                        copyError = error
                    }
                }
                if let coordinatorError { throw coordinatorError }
                if let copyError { throw copyError }
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    var freeSpaceText: String {
        guard let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " free"
    }

    // MARK: Names, dates and the catalogue

    static func clipName(code: String, day: String, shot: ShotType, take: Int) -> String {
        "\(code)_\(day)_\(shot.rawValue)_\(String(format: "%02d", take)).mov"
    }

    /// "Mount Barney" becomes "MountBarney". Accents are dropped so names work everywhere.
    static func fileCode(for text: String) -> String {
        let plain = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let words = plain.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let code = words.map { word -> String in
            let first = word.prefix(1).uppercased()
            return first + word.dropFirst()
        }.joined()
        let ascii = code.unicodeScalars.filter { $0.isASCII }.map { String($0) }.joined()
        return ascii.isEmpty ? "Trip" : String(ascii.prefix(40))
    }

    /// Makes a name safe for folders on the phone and on Windows.
    static func safe(_ text: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = text.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        format(date, "yyyy-MM-dd", timeZone: timeZone)
    }

    static func timeString(_ date: Date, timeZone: TimeZone) -> String {
        format(date, "HH:mm:ss", timeZone: timeZone)
    }

    private static func format(_ date: Date, _ pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static let catalogColumns = [
        "file", "place", "state", "country", "continent", "latitude", "longitude", "date", "time", "light",
        "shot", "take", "in_shot", "lens", "fps", "resolution", "length_s", "tags", "favourite", "notes"
    ]

    static func catalogCSV(for trip: Trip) -> String {
        var lines = [catalogColumns.joined(separator: ",")]
        for clip in trip.clips.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            let zone = TimeZone(identifier: clip.timeZoneID) ?? .current
            let row: [String] = [
                clip.fileName,
                trip.place,
                trip.state,
                trip.country,
                trip.continent,
                clip.latitude.map { String(format: "%.6f", $0) } ?? "",
                clip.longitude.map { String(format: "%.6f", $0) } ?? "",
                dayString(clip.recordedAt, timeZone: zone),
                timeString(clip.recordedAt, timeZone: zone),
                clip.light,
                clip.shot,
                String(clip.take),
                clip.inShot ? "yes" : "no",
                clip.lens,
                String(clip.fps),
                clip.resolution,
                String(format: "%.1f", clip.durationSeconds),
                clip.tags.joined(separator: "; "),
                clip.favourite ? "yes" : "no",
                clip.notes
            ]
            lines.append(row.map { csvField($0) }.joined(separator: ","))
        }
        // The byte-order mark makes Excel on Windows read accents correctly.
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
