import AVFoundation
import AVKit
import SwiftUI
import UIKit

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// The picture through the look (Apple Log made to look normal, plus the highlight stripes), drawn over
    /// the plain preview. The plain one still sits underneath for working out where taps land.
    let lookLayer = LookRenderer.makeLayer()

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees this cast.
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(lookLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(lookLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lookLayer.frame = bounds
        CATransaction.commit()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        lookLayer.contentsScale = scale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        lookLayer.drawableSize = size
        LookRenderer.shared.attachPreview(lookLayer, pixelSize: size)
    }
}

/// The live camera picture. Tap to focus, hold to lock focus and exposure, drag up or down with one finger
/// for brightness, pinch to zoom. Volume up, Camera Control and Bluetooth shutter remotes call `onButton`;
/// volume down calls `onSecondaryButton`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Which way up the phone is held, so dragging up brightens whichever way it's turned.
    var hold: PhoneHold = .upright
    var onTap: (CGPoint, CGPoint) -> Void
    var onHold: (CGPoint, CGPoint) -> Void
    var onDrag: (CGFloat) -> Void
    var onButton: () -> Void
    /// Volume down. While recording it marks the moment; otherwise it starts, like the other buttons.
    var onSecondaryButton: () -> Void
    /// The pinch's scale since it began, and whether it's starting, moving or done.
    var onPinch: (CGFloat, UIGestureRecognizer.State) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let coordinator = context.coordinator
        coordinator.view = view

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.6
        view.addGestureRecognizer(hold)
        let drag = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.dragged(_:)))
        // One finger only, so a two-finger pinch doesn't change the brightness too.
        drag.maximumNumberOfTouches = 1
        view.addGestureRecognizer(drag)
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        view.addGestureRecognizer(pinch)

        let buttons = AVCaptureEventInteraction(
            primary: { event in
                if event.phase == .ended {
                    coordinator.parent.onButton()
                }
            },
            secondary: { event in
                if event.phase == .ended {
                    coordinator.parent.onSecondaryButton()
                }
            })
        view.addInteraction(buttons)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
        uiView.setNeedsLayout()
    }

    final class Coordinator: NSObject {
        var parent: CameraPreview
        weak var view: PreviewView?

        init(parent: CameraPreview) {
            self.parent = parent
        }

        private func points(for gesture: UIGestureRecognizer) -> (view: CGPoint, device: CGPoint)? {
            guard let view else { return nil }
            let location = gesture.location(in: view)
            return (location, view.previewLayer.captureDevicePointConverted(fromLayerPoint: location))
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let point = points(for: gesture) else { return }
            parent.onTap(point.view, point.device)
        }

        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let point = points(for: gesture) else { return }
            parent.onHold(point.view, point.device)
        }

        @objc func dragged(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            // Up as you see it: up the screen when it's upright, across it when it's sideways.
            let towardsBottom: CGFloat
            switch parent.hold {
            case .upright: towardsBottom = translation.y
            case .sidewaysLeft: towardsBottom = -translation.x
            case .sidewaysRight: towardsBottom = translation.x
            case .upsideDown: towardsBottom = -translation.y
            }
            parent.onDrag(towardsBottom)
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            parent.onPinch(gesture.scale, gesture.state)
        }
    }
}
