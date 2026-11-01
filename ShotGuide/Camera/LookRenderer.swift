import AVFoundation
import CoreImage
import Metal
import QuartzCore
import UIKit

/// Shows Apple Log pictures through the look: the live camera (with stripes where highlights are close to
/// blowing out) and clips played back on the review screen. Nothing here changes what's recorded.
/// Colour management is off throughout, so the camera's raw Log values go straight into the look.
final class LookRenderer {
    static let shared = LookRenderer()

    let device: MTLDevice?
    let context: CIContext
    private let queue: MTLCommandQueue?
    private let lock = NSLock()
    private var cube: CubeLUT?
    private weak var previewLayer: CAMetalLayer?
    private var previewSize: CGSize = .zero
    private var lastPreview: CFTimeInterval = 0
    /// Set once by a tiny test render: whether Core Image draws into Metal textures upside down.
    private var flipsTextures = false

    /// Highlight warning levels, as raw values: Log footage is close to clipping well before 1.
    static let logZebraLevel: Float = 0.87
    static let normalZebraLevel: Float = 0.97

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false
        ]
        if let device {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
        flipsTextures = measureFlip()
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

    static func makeLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = shared.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = false
        layer.contentsGravity = .resizeAspectFill
        return layer
    }

    /// The camera screen's layer, and its size in pixels. Called when it's laid out.
    func attachPreview(_ layer: CAMetalLayer, pixelSize: CGSize) {
        lock.lock()
        previewLayer = layer
        previewSize = pixelSize
        lock.unlock()
    }

    // MARK: Live camera

    /// One camera frame, on the camera's frame queue. Drawn at up to 30 a second.
    func renderPreview(_ pixelBuffer: CVPixelBuffer, front: Bool, log: Bool) {
        let now = CACurrentMediaTime()
        lock.lock()
        let layer = previewLayer
        let size = previewSize
        let cube = log ? self.cube : nil
        let tooSoon = now - lastPreview < 1.0 / 31.0
        if !tooSoon { lastPreview = now }
        lock.unlock()
        guard !tooSoon, let layer, size.width > 1, size.height > 1 else { return }
        var image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        guard !image.extent.isEmpty else { return }
        image = Self.fill(image.oriented(front ? .leftMirrored : .right), into: size)
        let shown = cube?.apply(to: image) ?? image
        let output = Self.zebras(on: shown, raw: image, level: log ? Self.logZebraLevel : Self.normalZebraLevel, size: size)
        draw(output, into: layer, size: size)
    }

    // MARK: Playback

    /// One frame of a clip being played back, drawn to fit inside the layer.
    func renderClipFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, into layer: CAMetalLayer, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        var image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        guard !image.extent.isEmpty else { return }
        image = Self.fit(image.oriented(orientation), into: size)
        let shown = currentCube?.apply(to: image) ?? image
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        draw(shown.composited(over: black), into: layer, size: size)
    }

    // MARK: Drawing

    private func draw(_ image: CIImage, into layer: CAMetalLayer, size: CGSize) {
        guard let queue, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        var output = image
        if flipsTextures {
            output = output.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -size.height))
        }
        let bounds = CGRect(origin: .zero, size: size)
        context.render(output, to: drawable.texture, commandBuffer: buffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws a 2x2 picture, red on top, into a texture and reads it back, to learn which way up
    /// Core Image draws into Metal textures on this phone.
    private func measureFlip() -> Bool {
        guard let device, let queue else { return false }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return false }
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 1, width: 2, height: 1))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 1))
        context.render(red.composited(over: blue), to: texture, commandBuffer: buffer,
                       bounds: CGRect(x: 0, y: 0, width: 2, height: 2), colorSpace: CGColorSpaceCreateDeviceRGB())
        buffer.commit()
        buffer.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: 16)
        texture.getBytes(&pixels, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        // BGRA: the first pixel is the texture's top-left. Red there means the picture came out upright.
        let topIsRed = pixels[2] > 128 && pixels[0] < 128
        let topIsBlue = pixels[0] > 128 && pixels[2] < 128
        return topIsBlue && !topIsRed
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

/// Plays a clip on the review screen through the look. Frames come from the player without any colour
/// conversion, so Apple Log clips look the way they did while filming.
final class LookPlayerUIView: UIView {
    let metalLayer = LookRenderer.makeLayer()
    private var output: AVPlayerItemVideoOutput?
    private var link: CADisplayLink?
    private weak var item: AVPlayerItem?
    var orientation: CGImagePropertyOrientation = .right

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(metalLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
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
        LookRenderer.shared.renderClipFrame(buffer, orientation: orientation, into: metalLayer, size: metalLayer.drawableSize)
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
