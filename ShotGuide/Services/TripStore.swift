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
        let factsURL = folder.appendingPathComponent("facts.txt")
        if let facts = trip.facts, !facts.isEmpty {
            try Data(("\(trip.place)\n\n" + facts.text).utf8).write(to: factsURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: factsURL)
        }
    }

    private func replace(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        try? write(trip)
    }

    // MARK: Trips

    @discardableResult
    func createTrip(place: String, fileCode: String, state: String, countryCode: String, continent: String,
                    latitude: Double?, longitude: Double?, type: TripType) throws -> Trip {
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
        let code = Self.fileCode(for: fileCode.isEmpty ? place : fileCode)
        var trip = Trip(
            place: place,
            fileCode: code,
            state: state,
            country: country,
            countryCode: countryCode,
            continent: continent,
            latitude: latitude,
            longitude: longitude,
            createdAt: now,
            folderPath: relative)
        trip.days = [TripDay(number: 1, startedAt: now, place: place, fileCode: code, type: type,
                             latitude: latitude, longitude: longitude)]
        try write(trip)
        trips.insert(trip, at: 0)
        return trip
    }

    func deleteTrip(_ id: UUID) {
        guard let trip = self.trip(id: id) else { return }
        try? FileManager.default.removeItem(at: folderURL(for: trip))
        trips.removeAll { $0.id == id }
    }

    func updateFacts(_ facts: TripFacts, tripID: UUID) {
        guard var trip = self.trip(id: tripID) else { return }
        trip.facts = facts.isEmpty ? nil : facts
        replace(trip)
    }

    // MARK: Days

    /// Starts the next day: at the same place as the day before, or at a new one (`place`), with its own type.
    /// Returns the new day's number.
    @discardableResult
    func addDay(tripID: UUID, place: String?, type: TripType, latitude: Double?, longitude: Double?) -> Int? {
        guard var trip = self.trip(id: tripID) else { return nil }
        var days = trip.allDays
        guard let last = days.last else { return nil }
        let number = last.number + 1
        let newPlace = (place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let day: TripDay
        if newPlace.isEmpty {
            day = TripDay(number: number, startedAt: Date(), place: last.place, fileCode: last.fileCode, type: type,
                          latitude: latitude ?? last.latitude, longitude: longitude ?? last.longitude)
        } else {
            day = TripDay(number: number, startedAt: Date(), place: newPlace, fileCode: Self.fileCode(for: newPlace), type: type,
                          latitude: latitude, longitude: longitude)
        }
        days.append(day)
        trip.days = days
        replace(trip)
        return number
    }

    func setType(_ type: TripType, day number: Int, tripID: UUID) {
        guard var trip = self.trip(id: tripID) else { return }
        var days = trip.allDays
        guard let index = days.firstIndex(where: { $0.number == number }) else { return }
        days[index].type = type
        trip.days = days
        replace(trip)
    }

    // MARK: Clips

    /// Takes are numbered day by day, so each day starts again at take 1.
    func nextTake(tripID: UUID, shot: ShotType, day: Int) -> Int {
        nextTake(tripID: tripID, shotName: shot.rawValue, day: day)
    }

    func nextTake(tripID: UUID, shotName: String, day: Int) -> Int {
        guard let trip = self.trip(id: tripID) else { return 1 }
        return (trip.clips.filter { $0.shot == shotName && $0.dayNumber == day }.map { $0.take }.max() ?? 0) + 1
    }

    /// Where the next clip goes, named the playbook way: Place_YYYY-MM-DD_SHOT_##.mov, with the clip's name on
    /// the end once it has one. The place is the day's, so a day somewhere new is named after where you are.
    func newClipURL(tripID: UUID, shotName: String, take: Int, date: Date, day: Int, fileExtension: String) -> URL? {
        guard let trip = self.trip(id: tripID) else { return nil }
        let folder = folderURL(for: trip)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let code = trip.day(day).fileCode
        let dateText = Self.dayString(date, timeZone: .current)
        var number = take
        var url = folder.appendingPathComponent(
            Self.clipName(code: code, day: dateText, shotName: shotName, take: number, fileExtension: fileExtension))
        while FileManager.default.fileExists(atPath: url.path) {
            number += 1
            url = folder.appendingPathComponent(
                Self.clipName(code: code, day: dateText, shotName: shotName, take: number, fileExtension: fileExtension))
        }
        return url
    }

    /// The file name a clip should have, from its day, date, shot, take and name.
    func expectedFileName(for clip: Clip, in trip: Trip) -> String {
        let zone = TimeZone(identifier: clip.timeZoneID) ?? .current
        let fileExtension = (clip.fileName as NSString).pathExtension
        return Self.clipName(
            code: trip.day(clip.dayNumber).fileCode,
            day: Self.dayString(clip.recordedAt, timeZone: zone),
            shotName: clip.shot,
            take: clip.take,
            name: clip.displayName,
            fileExtension: fileExtension.isEmpty ? "mov" : fileExtension)
    }

    /// Renames a clip's files, with its cutout mask and captions, to match its shot, take and name.
    /// The copy on the SSD is renamed to match the next time the trip is copied.
    func applyFileName(clipID: UUID, tripID: UUID) {
        guard var trip = self.trip(id: tripID), let index = trip.clips.firstIndex(where: { $0.id == clipID }) else { return }
        var clip = trip.clips[index]
        let wanted = expectedFileName(for: clip, in: trip)
        guard wanted != clip.fileName else { return }
        let folder = folderURL(for: trip)
        let fileManager = FileManager.default
        var newName = wanted
        if clip.isOnPhone {
            newName = Self.freeName(wanted, in: folder)
            do {
                try fileManager.moveItem(at: folder.appendingPathComponent(clip.fileName), to: folder.appendingPathComponent(newName))
            } catch {
                return
            }
        }
        let newBase = (newName as NSString).deletingPathExtension
        if let mask = clip.maskFileName {
            let newMask = newBase + "_mask.mov"
            try? fileManager.moveItem(at: folder.appendingPathComponent(mask), to: folder.appendingPathComponent(newMask))
            clip.maskFileName = newMask
        }
        if let captions = clip.captionsFileName {
            let newCaptions = newBase + ".srt"
            try? fileManager.moveItem(at: folder.appendingPathComponent(captions), to: folder.appendingPathComponent(newCaptions))
            clip.captionsFileName = newCaptions
        }
        clip.fileName = newName
        trip.clips[index] = clip
        replace(trip)
    }

    /// Gives a clip added from Photos a shot type, like TIMELAPSE, so it sorts and counts with the rest.
    func setShot(_ shotName: String, clipID: UUID, tripID: UUID) {
        guard var trip = self.trip(id: tripID), let index = trip.clips.firstIndex(where: { $0.id == clipID }),
              trip.clips[index].shot != shotName else { return }
        let day = trip.clips[index].dayNumber
        let others = trip.clips.filter { $0.shot == shotName && $0.dayNumber == day && $0.id != clipID }
        trip.clips[index].shot = shotName
        trip.clips[index].take = (others.map { $0.take }.max() ?? 0) + 1
        replace(trip)
        applyFileName(clipID: clipID, tripID: tripID)
    }

    /// `wanted`, or wanted-2, wanted-3… if a file of that name is already in the folder.
    static func freeName(_ wanted: String, in folder: URL) -> String {
        let base = (wanted as NSString).deletingPathExtension
        let fileExtension = (wanted as NSString).pathExtension
        var candidate = wanted
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(counter).\(fileExtension)"
            counter += 1
        }
        return candidate
    }

    /// Free space on the phone, in bytes.
    var freeBytes: Int64? {
        (try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Roughly how many minutes of 4K video still fit, at about 200 MB a minute.
    var minutesOfVideoLeft: Int? {
        freeBytes.map { Int(max($0, 0) / 200_000_000) }
    }

    /// "About 45 min of 4K space left", or "About 3 hours of 4K space left".
    var spaceLeftText: String? {
        guard let minutes = minutesOfVideoLeft else { return nil }
        if minutes >= 120 {
            return "About \(minutes / 60) hours of 4K space left"
        }
        return "About \(minutes) min of 4K space left"
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
        // The clip, plus its cutout mask and captions if it has them.
        let folder = folderURL(for: trip)
        for name in [clip.fileName, clip.maskFileName, clip.captionsFileName].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        trip.clips.removeAll { $0.id == clipID }
        replace(trip)
    }

    func clipURL(_ clip: Clip, in trip: Trip) -> URL {
        folderURL(for: trip).appendingPathComponent(clip.fileName)
    }

    /// DANCE songs copied into a trip's folder start with this, so they're never mistaken for clips.
    static let songPrefix = "SONG_"

    /// Copies a DANCE song into the trip's folder (once), so it goes to the SSD with the clips for matching the
    /// edit to the beat. Returns its file name there.
    func attachSong(_ source: URL, name: String, tripID: UUID) -> String? {
        guard let trip = self.trip(id: tripID) else { return nil }
        let folder = folderURL(for: trip)
        let slug = Self.nameSlug(name)
        let fileExtension = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let fileName = Self.songPrefix + (slug.isEmpty ? "Song" : slug) + "." + fileExtension
        let destination = folder.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                return nil
            }
        }
        return fileName
    }

    // MARK: Export

    /// The top folder a trip goes into on a drive or PC: Shot Guide/<continent>/<country>/<state>/<date place>/.
    static let exportFolderName = "Shot Guide"

    struct CopySummary {
        /// Where the trip went, e.g. "Shot Guide › Oceania › Australia › Queensland › 2026-11-08 Mount Barney".
        let path: String
        let copied: Int
        let alreadyThere: Int
        /// Media files now safely on the drive (same size as on the phone), so they can come off the phone.
        let verified: Set<String>
    }

    /// Copies a trip onto a drive or folder you pick, such as an SSD plugged into the phone, into
    /// Shot Guide/<continent>/<country>/<state>/<date place>/ beside the trips already there.
    /// Clips already on the drive are skipped, so copying the same trip again only adds new takes.
    func copyTrip(_ trip: Trip, to picked: URL,
                  progress: @escaping (Int, Int) -> Void,
                  completion: @escaping (Result<CopySummary, Error>) -> Void) {
        let source = folderURL(for: trip)
        let inside = Self.pathInsideLibrary(trip.folderPath)
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let accessing = picked.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    picked.stopAccessingSecurityScopedResource()
                }
            }
            do {
                // Picking the drive itself or the Shot Guide folder on it both end up in the same place.
                let root = picked.lastPathComponent == Self.exportFolderName
                    ? picked
                    : picked.appendingPathComponent(Self.exportFolderName, isDirectory: true)
                let target = root.appendingPathComponent(inside, isDirectory: true)
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                // Clips renamed since the last copy are renamed on the drive too, rather than copied again.
                Self.applyRenames(for: trip, at: target)

                // Videos first and the catalogue last, so the catalogue on the drive never lists a missing clip.
                let items = try fileManager.contentsOfDirectory(
                    at: source, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true }
                    .sorted { lhs, rhs in
                        let lhsVideo = Self.isVideo(lhs)
                        let rhsVideo = Self.isVideo(rhs)
                        if lhsVideo != rhsVideo {
                            return lhsVideo
                        }
                        return lhs.lastPathComponent < rhs.lastPathComponent
                    }

                var copied = 0
                var alreadyThere = 0
                var verified: Set<String> = []
                for (index, item) in items.enumerated() {
                    DispatchQueue.main.async { progress(index + 1, items.count) }
                    let copy = target.appendingPathComponent(item.lastPathComponent)
                    if fileManager.fileExists(atPath: copy.path) {
                        // A video of the same size is already there. A different size means an earlier copy was cut short.
                        if Self.isVideo(item), Self.fileSize(item) == Self.fileSize(copy) {
                            if Self.isClip(item) {
                                alreadyThere += 1
                            }
                            verified.insert(item.lastPathComponent)
                            continue
                        }
                        try fileManager.removeItem(at: copy)
                    }
                    try fileManager.copyItem(at: item, to: copy)
                    if Self.isClip(item) {
                        copied += 1
                    }
                    if Self.isVideo(item), Self.fileSize(item) == Self.fileSize(copy) {
                        verified.insert(item.lastPathComponent)
                    }
                }

                let parts = [root.lastPathComponent] + inside.split(separator: "/").map(String.init)
                let summary = CopySummary(path: parts.joined(separator: " › "), copied: copied, alreadyThere: alreadyThere,
                                          verified: verified)
                DispatchQueue.main.async { completion(.success(summary)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Reads the trip.json left on the drive by the last copy, and renames any clip (with its mask and captions)
    /// whose name has changed since, so the drive doesn't end up with both names.
    private static func applyRenames(for trip: Trip, at target: URL) {
        let fileManager = FileManager.default
        guard let data = try? Data(contentsOf: target.appendingPathComponent("trip.json")) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let onDrive = try? decoder.decode(Trip.self, from: data) else { return }
        var before: [UUID: Clip] = [:]
        for clip in onDrive.clips {
            before[clip.id] = clip
        }
        for clip in trip.clips {
            guard let old = before[clip.id] else { continue }
            let pairs: [(String?, String?)] = [
                (old.fileName, clip.fileName),
                (old.maskFileName, clip.maskFileName),
                (old.captionsFileName, clip.captionsFileName)
            ]
            for (from, to) in pairs {
                guard let from, let to, from != to else { continue }
                let source = target.appendingPathComponent(from)
                let destination = target.appendingPathComponent(to)
                if fileManager.fileExists(atPath: source.path) && !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.moveItem(at: source, to: destination)
                }
            }
        }
    }

    /// After a copy: takes the clips (and their cutout masks) that are safely on the drive off the phone.
    /// The trip keeps listing them, with their names, tags and counts. Returns how many clips came off.
    @discardableResult
    func freeUpSpace(tripID: UUID, verified: Set<String>) -> Int {
        guard var trip = self.trip(id: tripID) else { return 0 }
        let folder = folderURL(for: trip)
        var removed = 0
        for index in trip.clips.indices {
            let clip = trip.clips[index]
            guard clip.isOnPhone, verified.contains(clip.fileName) else { continue }
            // A mask that didn't make it to the drive keeps its clip on the phone too, for the next copy.
            if let mask = clip.maskFileName, !verified.contains(mask) { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(clip.fileName))
            if let mask = clip.maskFileName {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(mask))
            }
            trip.clips[index].removedFromPhone = true
            removed += 1
        }
        replace(trip)
        return removed
    }

    /// "Library/Oceania/Australia/Queensland/2026-11-08 Mount Barney" becomes "Oceania/Australia/Queensland/2026-11-08 Mount Barney".
    static func pathInsideLibrary(_ folderPath: String) -> String {
        let prefix = "Library/"
        return folderPath.hasPrefix(prefix) ? String(folderPath.dropFirst(prefix.count)) : folderPath
    }

    /// Clips, masks, voiceovers and anything added from Photos: copied first, and skipped when already on the drive.
    static let mediaExtensions: Set<String> = ["mov", "mp4", "m4v", "m4a", "heic", "heif", "jpg", "jpeg", "png", "dng"]

    static func isVideo(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    /// A clip you filmed, as opposed to a cutout mask made from one.
    static func isClip(_ url: URL) -> Bool {
        isVideo(url) && !url.lastPathComponent.hasSuffix("_mask.mov") && !url.lastPathComponent.hasPrefix(songPrefix)
    }

    static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Packs a trip into one .zip at the top of the app's folder, keeping the
    /// Shot Guide/<continent>/<country>/<state>/ folders inside it, the same as copying to a drive.
    func exportTrip(_ trip: Trip, completion: @escaping (Result<URL, Error>) -> Void) {
        let source = folderURL(for: trip)
        let relative = Self.exportFolderName + "/" + Self.pathInsideLibrary(trip.folderPath)
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
                let root = staging.appendingPathComponent(Self.exportFolderName, isDirectory: true)
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

    static func clipName(code: String, day: String, shotName: String, take: Int, name: String? = nil,
                         fileExtension: String) -> String {
        var base = "\(code)_\(day)_\(shotName)_\(String(format: "%02d", take))"
        let slug = name.map { nameSlug($0) } ?? ""
        if !slug.isEmpty {
            base += "_" + slug
        }
        return base + "." + fileExtension
    }

    /// "Lower Falls" becomes "Lower-Falls": letters, numbers and hyphens only, so it works on any drive.
    static func nameSlug(_ text: String) -> String {
        let plain = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let words = plain.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let joined = words.joined(separator: "-")
        let ascii = joined.unicodeScalars.filter { $0.isASCII }.map { String($0) }.joined()
        return String(ascii.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
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
        "shot", "take", "in_shot", "lens", "fps", "resolution", "length_s", "tags", "favourite", "notes",
        "variant", "mask_file", "captions_file", "transcript", "marks_s",
        "name", "trip", "day", "trip_type", "shake_dps", "tilt_deg", "take_check", "zoom", "on_phone",
        "song", "song_file", "song_start_s",
        "profile", "white_balance_k", "tint", "iso", "shutter",
        "orientation"
    ]

    static func catalogCSV(for trip: Trip) -> String {
        var lines = [catalogColumns.joined(separator: ",")]
        for clip in trip.clips.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            lines.append(catalogRow(clip, trip: trip).map { csvField($0) }.joined(separator: ","))
        }
        // The byte-order mark makes Excel on Windows read accents correctly.
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func catalogRow(_ clip: Clip, trip: Trip) -> [String] {
        let zone = TimeZone(identifier: clip.timeZoneID) ?? .current
        let day = trip.day(clip.dayNumber)
        let first: [String] = [
            clip.fileName,
            day.place,
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
            clip.notes,
            clip.variant ?? "",
            clip.maskFileName ?? "",
            clip.captionsFileName ?? "",
            clip.transcript ?? "",
            (clip.marks ?? []).map { String(format: "%.1f", $0) }.joined(separator: "; ")
        ]
        let added: [String] = [
            clip.displayName ?? "",
            trip.place,
            String(clip.dayNumber),
            day.type.rawValue,
            clip.shake.map { String(format: "%.2f", $0) } ?? "",
            clip.tilt.map { String(format: "%.1f", $0) } ?? "",
            clip.check ?? "",
            clip.zoom.map { String(format: "%.1f", $0) } ?? "",
            clip.isOnPhone ? "yes" : "no",
            clip.songName ?? "",
            clip.songFile ?? "",
            clip.songStart.map { String(format: "%.3f", $0) } ?? ""
        ]
        let colour: [String] = [
            clip.colourProfile ?? "",
            clip.whiteBalance.map { String($0.kelvin) } ?? "",
            clip.whiteBalance.map { String($0.tint) } ?? "",
            clip.iso.map { String($0) } ?? "",
            clip.shutterText ?? "",
            clip.orientationLabel ?? ""
        ]
        return first + added + colour
    }

    static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
