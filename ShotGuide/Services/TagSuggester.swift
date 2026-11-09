import AVFoundation
import Foundation
import ImageIO
import Vision

/// Suggests tags by looking at a clip (three frames from it) or a photo with the iPhone's built-in image recognition.
enum TagSuggester {
    static func suggest(for url: URL, completion: @escaping ([String]) -> Void) {
        Task.detached(priority: .userInitiated) {
            let result = await suggestions(for: url)
            await MainActor.run { completion(result) }
        }
    }

    static func suggestions(for url: URL) async -> [String] {
        let fileExtension = url.pathExtension.lowercased()
        if ["m4a", "wav"].contains(fileExtension) {
            return []
        }
        if ["heic", "heif", "jpg", "jpeg", "png", "dng"].contains(fileExtension) {
            guard let image = thumbnail(of: url) else { return [] }
            return classify(image).sorted()
        }
        var found = Set<String>()
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 768, height: 768)
        if let duration = try? await asset.load(.duration) {
            let seconds = max(CMTimeGetSeconds(duration), 0)
            for fraction in [0.25, 0.5, 0.75] {
                let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
                if let frame = try? await generator.image(at: time) {
                    found.formUnion(classify(frame.image))
                }
            }
        }
        return found.sorted()
    }

    /// A small, upright copy of a photo.
    static func thumbnail(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 768
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func classify(_ image: CGImage) -> Set<String> {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        var tags = Set<String>()
        for observation in request.results ?? [] where observation.confidence >= 0.3 {
            if let tag = TagVocabulary.visionMap[observation.identifier] {
                tags.insert(tag)
            }
        }
        return tags
    }
}
