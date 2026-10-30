import AVFoundation
import AVKit
import SwiftUI
import UIKit

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees this cast.
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

/// The live camera picture. Tap to focus, hold to lock focus and exposure, drag up or down for brightness.
/// The volume buttons, Camera Control and Bluetooth shutter remotes call `onButton`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void
    var onHold: (CGPoint, CGPoint) -> Void
    var onDrag: (CGFloat) -> Void
    var onButton: () -> Void

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
        view.addGestureRecognizer(drag)

        let buttons = AVCaptureEventInteraction { event in
            if event.phase == .ended {
                coordinator.parent.onButton()
            }
        }
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
            parent.onDrag(translation.y)
        }
    }
}
