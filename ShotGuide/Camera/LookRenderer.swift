import AVFoundation
import CoreImage
import Metal
import QuartzCore
import SwiftUI
import UIKit

/// Shows Apple Log pictures through the look: the live camera (with stripes where highlights are close to
/// blowing out) and clips played back on the review screen. Nothing here changes what's recorded.
/// Colour management is off throughout, so the camera's raw Log values go straight into the look.
/// Each picture is drawn into a pixel buffer, top row first like any video frame, and shown by a video layer,
/// so it comes out the right way up on every phone.
final class LookRenderer {
    static let shared = LookRenderer()

    let context: CIContext
    private let lock = NSLock()
    private var cube: CubeLUT?
    private weak var previewRenderer: AVSampleBufferVideoRenderer?
    private var previewSize: CGSize = .zero
    private var lastPreview: CFTimeInterval = 0
    /// Buffers for the live camera, only used on the camera's frame queue.
    private let previewFrames = FramePool()

    /// Highlight warning levels, as raw values: Log footage is close to clipping well before 1.
    static let logZebraLevel: Float = 0.87
    static let normalZebraLevel: Float = 0.97

    private init() {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func setCube(_ cube: CubeLUT?) {
        lock.lock()
        self.cube = cube
        lock.unlock()
    }

    var currentCube: CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        return cube
    }

    /// A layer that shows the pictures. `filling` crops to fill it, like the camera; otherwise the whole picture fits inside.
    static func makeLayer(filling: Bool) -> AVSampleBufferDisplayLayer {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = filling ? .resizeAspectFill : .resizeAspect
        return layer
    }

    /// The camera screen's layer, and its size in pixels. Called on the main thread when it's laid out.
    func attachPreview(_ layer: AVSampleBufferDisplayLayer, pixelSize: CGSize) {
        let renderer = layer.sampleBufferRenderer
        lock.lock()
        previewRenderer = renderer
        previewSize = pixelSize
        lock.unlock()
    }

    // MARK: Live camera

    /// One camera frame, on the camera's frame queue, turned by `orientation` to show the right way up.
    /// Drawn at up to 30 a second.
    func renderPreview(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, log: Bool) {
        let now = CACurrentMediaTime()
        lock.lock()
        let renderer = previewRenderer
        let size = previewSize
        let cube = log ? self.cube : nil
        let tooSoon = now - lastPreview < 1.0 / 31.0
        if !tooSoon { lastPreview = now }
        lock.unlock()
        guard !tooSoon, let renderer, size.width > 1, size.height > 1 else { return }
        var image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        guard !image.extent.isEmpty else { return }
        image = Self.fill(image.oriented(orientation), into: size)
        let shown = cube?.apply(to: image) ?? image
        let output = Self.zebras(on: shown, raw: image, level: log ? Self.logZebraLevel : Self.normalZebraLevel, size: size)
        show(output, size: size, frames: previewFrames, on: renderer)
    }

    // MARK: Playback

    /// One frame of a clip being played back, made small enough to fit inside `bounds` (in pixels); the layer
    /// fits it to the screen.
    func renderClipFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, within bounds: CGSize,
                         frames: FramePool, on renderer: AVSampleBufferVideoRenderer) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        var image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        guard !image.extent.isEmpty else { return }
        image = image.oriented(orientation)
        let extent = image.extent
        let scale = min(1, bounds.width / extent.width, bounds.height / extent.height)
        let size = CGSize(width: max(2, (extent.width * scale / 2).rounded() * 2),
                          height: max(2, (extent.height * scale / 2).rounded() * 2))
        image = Self.fill(image, into: size)
        let shown = currentCube?.apply(to: image) ?? image
        show(shown, size: size, frames: frames, on: renderer)
    }

    // MARK: Drawing

    /// Draws the picture into a fresh buffer and puts it on screen straight away.
    private func show(_ image: CIImage, size: CGSize, frames: FramePool, on renderer: AVSampleBufferVideoRenderer) {
        // The layer stops after the app has been in the background; clearing it starts it again.
        if renderer.status == .failed {
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData,
              let buffer = frames.buffer(width: Int(size.width), height: Int(size.height)) else { return }
        context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
        guard let sample = frames.sample(for: buffer) else { return }
        renderer.enqueue(sample)
    }

    // MARK: Fitting and the highlight warning

    /// Scales and crops to fill `size`, centred, like the camera preview.
    static func fill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        var out = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        out = out.transformed(by: CGAffineTransform(translationX: -(out.extent.width - size.width) / 2,
                                                    y: -(out.extent.height - size.height) / 2))
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Scales to fit inside `size`, centred.
    static func fit(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        let scale = min(size.width / extent.width, size.height / extent.height)
        let out = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return out.transformed(by: CGAffineTransform(translationX: (size.width - out.extent.width) / 2,
                                                     y: (size.height - out.extent.height) / 2))
    }

    private static let stripes: CIImage? = {
        let filter = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.9),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputWidth": 7,
            "inputSharpness": 1
        ])
        return filter?.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
    }()

    /// Diagonal stripes over anything brighter than `level` in the raw picture.
    static func zebras(on shown: CIImage, raw: CIImage, level: Float, size: CGSize) -> CIImage {
        guard let stripes else { return shown }
        let rect = CGRect(origin: .zero, size: size)
        let mask = raw
            .applyingFilter("CIMaximumComponent")
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": level])
            .cropped(to: rect)
        let striped = stripes.cropped(to: rect).composited(over: shown)
        return striped.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: shown,
            kCIInputMaskImageKey: mask
        ]).cropped(to: rect)
    }
}

/// A few reusable picture buffers of one size, and the wrapping a video layer needs to show one at once.
/// Each pool is only used from one queue.
final class FramePool {
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0
    private var format: CMVideoFormatDescription?

    func buffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard width > 0, height > 0 else { return nil }
        if pool == nil || width != self.width || height != self.height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, attributes as CFDictionary, &created)
            pool = created
            self.width = width
            self.height = height
            format = nil
        }
        guard let pool else { return nil }
        // No more than 6 at once, so frames can't pile up if the screen falls behind.
        let limit: [String: Any] = [kCVPixelBufferPoolAllocationThresholdKey as String: 6]
        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, limit as CFDictionary, &made)
                == kCVReturnSuccess,
              let made else { return nil }
        // The looks are made for phone screens.
        CVBufferSetAttachment(made, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(made, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        return made
    }

    /// Wraps a drawn buffer so the layer shows it as soon as it gets it.
    func sample(for buffer: CVPixelBuffer) -> CMSampleBuffer? {
        if let current = format, CMVideoFormatDescriptionMatchesImageBuffer(current, imageBuffer: buffer) {
            // Same size and colour as the last one.
        } else {
            var created: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                         formatDescriptionOut: &created)
            format = created
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var wrapped: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &wrapped) == noErr,
              let wrapped else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(wrapped, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return wrapped
    }
}

/// Plays a clip on the review screen through the look. Frames come from the player without any colour
/// conversion, so Apple Log clips look the way they did while filming.
final class LookPlayerUIView: UIView {
    let pictureLayer = LookRenderer.makeLayer(filling: false)
    private let frames = FramePool()
    private var pixelSize: CGSize = .zero
    private var output: AVPlayerItemVideoOutput?
    private var link: CADisplayLink?
    private weak var item: AVPlayerItem?
    var orientation: CGImagePropertyOrientation = .right

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(pictureLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.frame = bounds
        CATransaction.commit()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func attach(_ player: AVPlayer) {
        guard let current = player.currentItem, current !== item else { return }
        if let item, let output {
            item.remove(output)
        }
        let newOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        current.add(newOutput)
        output = newOutput
        item = current
        if link == nil {
            let newLink = CADisplayLink(target: self, selector: #selector(tick))
            newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
    }

    func detach() {
        link?.invalidate()
        link = nil
        if let item, let output {
            item.remove(output)
        }
        output = nil
    }

    @objc private func tick() {
        guard let output else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        LookRenderer.shared.renderClipFrame(buffer, orientation: orientation, within: pixelSize, frames: frames,
                                            on: pictureLayer.sampleBufferRenderer)
    }
}

struct LookPlayer: UIViewRepresentable {
    let player: AVPlayer
    let orientation: CGImagePropertyOrientation

    func makeUIView(context: Context) -> LookPlayerUIView {
        let view = LookPlayerUIView()
        view.orientation = orientation
        view.attach(player)
        return view
    }

    func updateUIView(_ uiView: LookPlayerUIView, context: Context) {
        uiView.orientation = orientation
        uiView.attach(player)
    }

    static func dismantleUIView(_ uiView: LookPlayerUIView, coordinator: ()) {
        uiView.detach()
    }
}
