import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UIKit

/// Small pictures of clips (1.28): a frame from a video, a photo shrunk down, kept while the app is open. Apple Log
/// clips are put through your look, so they don't look grey.
enum Thumbnails {
    private static let cache = NSCache<NSString, UIImage>()
    private static let maxSide: CGFloat = 480

    static func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    static func make(_ url: URL, isPhoto: Bool, isLog: Bool, cube: CubeLUT?) async -> UIImage? {
        if let hit = cached(url) {
            return hit
        }
        let image: UIImage?
        if isPhoto {
            image = photo(url)
        } else if isLog, let cube {
            image = await logFrame(url, cube: cube)
        } else {
            image = await videoFrame(url)
        }
        if let image {
            cache.setObject(image, forKey: url.path as NSString)
        }
        return image
    }

    /// Forgets a clip's picture, when its file is renamed or deleted.
    static func forget(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }

    private static func photo(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// A second in, or a third of the way through a shorter clip.
    private static func frameTime(_ asset: AVAsset) async -> CMTime {
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let seconds = duration.isFinite && duration > 0 ? min(1, duration / 3) : 0
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private static func videoFrame(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        let time = await frameTime(asset)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }

    /// One frame read as the camera's raw values and put through the look, like the review screen shows it.
    private static func logFrame(_ url: URL, cube: CubeLUT) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let transform = try? await track.load(.preferredTransform),
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let start = await frameTime(asset)
        reader.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading(), let sample = output.copyNextSampleBuffer(),
              let frame = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var image = cube.apply(to: CIImage(cvPixelBuffer: frame, options: [.colorSpace: NSNull()]))
            .oriented(MaskMaker.orientation(of: transform))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height, 1))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let picture = context.createCGImage(image, from: image.extent, format: .RGBA8,
                                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return UIImage(cgImage: picture)
    }
}

/// A clip's picture, filling whatever frame it's given.
struct ClipThumbnail: View {
    let url: URL
    let clip: Clip

    @EnvironmentObject var looks: LookLibrary
    @State private var image: UIImage? = nil

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .task(id: url) {
                await load()
            }
    }

    private var symbol: String {
        if !clip.isOnPhone { return "externaldrive.fill" }
        if clip.isAudio { return "waveform" }
        if clip.isPhoto { return "photo" }
        return "film"
    }

    private func load() async {
        guard clip.isOnPhone, !clip.isAudio else { return }
        if let hit = Thumbnails.cached(url) {
            image = hit
            return
        }
        image = await Thumbnails.make(url, isPhoto: clip.isPhoto, isLog: clip.isLog, cube: clip.isLog ? looks.gradingCube : nil)
    }
}

extension Clip {
    /// The shot's name for lists, like "B-ROLL", or "FROM PHOTOS" for something added that hasn't been given one.
    var shotTitle: String {
        if let shotType {
            return shotType.title
        }
        return shot == MediaImporter.shotName ? "FROM PHOTOS" : shot
    }

    /// "Local character · take 9", or with the shot as well, "B-ROLL · Local character · take 9".
    func takeLine(withShot: Bool) -> String {
        let row = ShotRow.forClip(self)
        let what: String
        if withShot {
            what = row?.title ?? shotTitle
        } else if let role = row?.roleInfo {
            what = role.title
        } else if let row, let index = row.half ?? row.variant, row.shot.variants.indices.contains(index) {
            what = row.shot.variants[index]
        } else {
            what = shotTitle
        }
        return what + " · take \(take)"
    }
}

/// One clip in a list: its picture, its name, what it was filmed for, and its length.
struct ClipRow: View {
    let clip: Clip
    let url: URL
    /// Whether the line under the name says the shot, for lists that mix them.
    var withShot = true

    private var lengthText: String {
        if clip.isPhoto { return "Photo" }
        return clip.isOnPhone ? String(format: "%.0f s", clip.durationSeconds) : "On SSD"
    }

    var body: some View {
        HStack(spacing: 12) {
            ClipThumbnail(url: url, clip: clip)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(clip.displayName ?? "No name yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(clip.displayName == nil ? Color.secondary : Color.primary)
                    if clip.favourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.yellow)
                    }
                    if clip.checkPassed == false {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(clip.takeLine(withShot: withShot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let about = clip.about, !about.isEmpty {
                    Text(about)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(lengthText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
    }
}

/// Which clips a list shows (1.28): one shot's, or one name's.
enum ClipFilter: Hashable {
    /// A shot's raw value, like "BROLL", or the one for clips added from Photos.
    case shot(String)
    /// A name you gave, or nil for clips with none yet.
    case name(String?)

    func matches(_ clip: Clip) -> Bool {
        switch self {
        case .shot(let shot): return clip.shot == shot
        case .name(let name): return clip.displayName == name
        }
    }
}

/// A day's clips in groups, for the trip page: by shot or by name, each a count to tap into.
struct ClipGroup: Identifiable {
    let filter: ClipFilter
    let title: String
    /// The shots in it, for a name's group: "WIDE, B-ROLL, DETAIL".
    let detail: String?
    let count: Int

    var id: ClipFilter { filter }

    /// By shot: the shots with the most clips first.
    static func byShot(_ clips: [Clip]) -> [ClipGroup] {
        var counts: [String: Int] = [:]
        var first: [String: Date] = [:]
        var titles: [String: String] = [:]
        for clip in clips {
            counts[clip.shot, default: 0] += 1
            first[clip.shot] = min(first[clip.shot] ?? clip.recordedAt, clip.recordedAt)
            titles[clip.shot] = clip.shotTitle
        }
        return counts.keys.sorted { a, b in
            counts[a] != counts[b] ? counts[a, default: 0] > counts[b, default: 0] : first[a, default: .distantPast] < first[b, default: .distantPast]
        }.map { ClipGroup(filter: .shot($0), title: titles[$0] ?? $0, detail: nil, count: counts[$0] ?? 0) }
    }

    /// By name: in the order you first filmed there, with the clips you haven't named last.
    static func byName(_ clips: [Clip]) -> [ClipGroup] {
        var order: [String?] = []
        var grouped: [String?: [Clip]] = [:]
        for clip in clips.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            let name = clip.displayName
            if grouped[name] == nil {
                order.append(name)
            }
            grouped[name, default: []].append(clip)
        }
        order = order.filter { $0 != nil } + order.filter { $0 == nil }
        return order.map { name in
            let members = grouped[name] ?? []
            var shots: [String] = []
            for clip in members where !shots.contains(clip.shotTitle) {
                shots.append(clip.shotTitle)
            }
            return ClipGroup(filter: .name(name), title: name ?? "No name yet", detail: shots.joined(separator: ", "),
                             count: members.count)
        }
    }
}

/// One shot's clips, or one name's, on a day (1.28). Tap one to watch it, rename it, tag it or delete it.
struct ClipGroupView: View {
    let tripID: UUID
    let day: Int
    let group: ClipGroup

    @EnvironmentObject var store: TripStore
    @State private var selected: Clip? = nil

    var body: some View {
        let trip = store.trip(id: tripID)
        let clips = (trip?.clips(onDay: day) ?? []).filter { group.filter.matches($0) }
            .sorted { $0.recordedAt > $1.recordedAt }
        List {
            Section {
                if clips.isEmpty {
                    Text("Nothing here any more.")
                        .foregroundStyle(.secondary)
                }
                ForEach(clips) { clip in
                    Button {
                        selected = clip
                    } label: {
                        if let trip {
                            ClipRow(clip: clip, url: store.clipURL(clip, in: trip), withShot: isByName)
                        }
                    }
                }
            } header: {
                Text(clips.count == 1 ? "1 clip" : "\(clips.count) clips, newest first")
            } footer: {
                Text("Tap a clip to watch it, rename it, tag it or delete it.")
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { clip in
            ReviewView(tripID: tripID, clipID: clip.id, autoplay: false, preselectSuggestions: false, title: "Clip")
        }
    }

    private var isByName: Bool {
        if case .name = group.filter { return true }
        return false
    }
}
