import SwiftUI
import SceneKit

/// SceneKit view for a `GuideSceneController`: turntable orbit, pinch zoom, double-tap to reset the camera preset.
struct GuideSceneView: UIViewRepresentable {
    let controller: GuideSceneController
    var isDark: Bool
    /// Called when the user starts dragging or pinching the scene.
    var onInteraction: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.delegate = controller
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = controller.appearance.background
        view.allowsCameraControl = true
        let cc = view.defaultCameraController
        cc.interactionMode = .orbitTurntable
        cc.inertiaEnabled = true
        cc.minimumVerticalAngle = 1
        cc.maximumVerticalAngle = 80
        cc.target = SCNVector3(controller.cameraTarget.x, controller.cameraTarget.y, controller.cameraTarget.z)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.interacted(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.interacted(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        controller.attachedView = view
        if UIAccessibility.isReduceMotionEnabled { controller.isPlaying = false }
        // Static scenes still need one frame.
        view.rendersContinuously = controller.isPlaying
        view.isPlaying = controller.isPlaying
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onInteraction = onInteraction
        controller.setAppearance(GuideSceneAppearance(isDark: isDark))
        view.backgroundColor = controller.appearance.background
        let size = view.bounds.size
        if size.width > 1, size.height > 1 { controller.updateAspect(Float(size.width / size.height)) }
        view.rendersContinuously = controller.isPlaying
        view.isPlaying = controller.isPlaying
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.delegate = nil
        view.isPlaying = false
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let controller: GuideSceneController
        var onInteraction: (() -> Void)?
        init(controller: GuideSceneController) { self.controller = controller }

        @objc func interacted(_ g: UIGestureRecognizer) {
            if g.state == .began { onInteraction?() }
        }

        @objc func doubleTap() { controller.setCamera(controller.cameraPreset, animated: true) }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
