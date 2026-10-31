import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A video handed over by the Photos picker, copied somewhere the app can keep it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            PickedMovie(url: try MediaImporter.copyToTemporary(received.file, fallbackExtension: "mov"))
        }
    }
}

/// A photo handed over by the Photos picker, in its original format.
struct PickedImage: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            PickedImage(url: try MediaImporter.copyToTemporary(received.file, fallbackExtension: "jpg"))
        }
    }
}

/// Brings photos and videos from the Camera app, a drone or a GoPro into a trip, named, located, timed and
/// tagged like the clips Shot Guide films, so they're catalogued and copied to the SSD with the rest.
enum MediaImporter {
    static let shotName = "IMPORT"

    struct MediaInfo {
        var date: Date?
        var latitude: Double?
        var longitude: Double?
        var duration: Double = 0
        var fps: Int = 0
        var resolution = ""
    }

    static func copyToTemporary(_ file: URL, fallbackExtension: String) throws -> URL {
        let fileExtension = file.pathExtension.isEmpty ? fallbackExtension : file.pathExtension.lowercased()
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + fileExtension)
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }

    /// Returns how many items were added.
    @MainActor
    static func importItems(_ items: [PhotosPickerItem], tripID: UUID, store: TripStore,
                            status: @escaping (String) -> Void) async -> Int {
        var added = 0
        for (index, item) in items.enumerated() {
            status("Adding \(index + 1) of \(items.count) from Photos…")
            let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                let source: URL?
                if isMovie {
                    source = try await item.loadTransferable(type: PickedMovie.self)?.url
                } else {
                    source = try await item.loadTransferable(type: PickedImage.self)?.url
                }
                guard let source else { continue }
                defer { try? FileManager.default.removeItem(at: source) }
                if try await add(source, isMovie: isMovie, tripID: tripID, store: store) {
                    added += 1
                }
            } catch {
                // Skip anything that couldn't be read and carry on with the rest.
            }
        }
        return added
    }

    @MainActor
    private static func add(_ source: URL, isMovie: Bool, tripID: UUID, store: TripStore) async throws -> Bool {
        guard let trip = store.trip(id: tripID) else { return false }
        let info = isMovie ? await movieInfo(source) : imageInfo(source)
        let date = info.date ?? trip.createdAt
        let latitude = info.latitude ?? trip.latitude
        let longitude = info.longitude ?? trip.longitude
        let take = store.nextTake(tripID: tripID, shotName: shotName)
        let fileExtension = source.pathExtension.isEmpty ? (isMovie ? "mov" : "jpg") : source.pathExtension.lowercased()
        guard let destination = store.newClipURL(tripID: tripID, shotName: shotName, take: take, date: date,
                                                 fileExtension: fileExtension) else { return false }
        try FileManager.default.copyItem(at: source, to: destination)

        let light = SunCalc.light(at: date, latitude: latitude, longitude: longitude)
        var tags = light.tags
        for tag in await TagSuggester.suggestions(for: destination) where !tags.contains(tag) {
            tags.append(tag)
        }
        let clip = Clip(
            fileName: destination.lastPathComponent,
            shot: shotName,
            take: take,
            variant: nil,
            recordedAt: date,
            timeZoneID: TimeZone.current.identifier,
            durationSeconds: info.duration,
            latitude: latitude,
            longitude: longitude,
            light: light.label,
            lens: isMovie ? "Added video" : "Added photo",
            fps: info.fps,
            resolution: info.resolution,
            inShot: false,
            tags: tags,
            favourite: false,
            notes: "")
        store.addClip(clip, to: tripID)
        return true
    }

    // MARK: Reading when and where it was taken

    static func movieInfo(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        let asset = AVURLAsset(url: url)
        if let item = try? await asset.load(.creationDate), let date = try? await item.load(.dateValue) {
            info.date = date
        }
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            info.duration = seconds.isFinite ? seconds : 0
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let rate = try? await track.load(.nominalFrameRate) {
                info.fps = Int(rate.rounded())
            }
            if let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                info.resolution = "\(Int(abs(rect.width)))x\(Int(abs(rect.height)))"
            }
        }
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata where item.identifier == .quickTimeMetadataLocationISO6709 || item.commonKey == .commonKeyLocation {
                if let text = try? await item.load(.stringValue), let point = parseISO6709(text) {
                    info.latitude = point.latitude
                    info.longitude = point.longitude
                    break
                }
            }
        }
        return info
    }

    static func imageInfo(_ url: URL) -> MediaInfo {
        var info = MediaInfo()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return info }
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            info.resolution = "\(width)x\(height)"
        }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
                info.date = formatter.date(from: original + offset)
            }
            if info.date == nil {
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                formatter.timeZone = .current
                info.date = formatter.date(from: original)
            }
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let north = (gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N") != "S"
            let east = (gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E") != "W"
            info.latitude = north ? latitude : -latitude
            info.longitude = east ? longitude : -longitude
        }
        return info
    }

    /// Reads a location like "+27.4698+153.0251+010.000/".
    static func parseISO6709(_ text: String) -> (latitude: Double, longitude: Double)? {
        var numbers: [Double] = []
        var current = ""
        for character in text {
            if character == "+" || character == "-" {
                if let value = Double(current) {
                    numbers.append(value)
                }
                current = String(character)
            } else if character.isNumber || character == "." {
                current.append(character)
            } else {
                break
            }
        }
        if let value = Double(current) {
            numbers.append(value)
        }
        guard numbers.count >= 2, abs(numbers[0]) <= 90, abs(numbers[1]) <= 180 else { return nil }
        return (numbers[0], numbers[1])
    }
}
