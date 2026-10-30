import AVFoundation
import Foundation
import Vision

/// Suggests tags by looking at frames from a clip with the iPhone's built-in image recognition.
enum TagSuggester {
    static func suggest(for url: URL, completion: @escaping ([String]) -> Void) {
        Task.detached(priority: .userInitiated) {
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
            let result = found.sorted()
            await MainActor.run { completion(result) }
        }
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
