import SwiftUI
import SceneKit
import simd

/// Renders an animated 3D stick-figure skeleton in an SCNView.
/// Joint spheres animate across frames via CAKeyframeAnimation;
/// bone cylinders are drawn statically for the first frame.
struct SkeletonSceneView: UIViewRepresentable {

    let frames: [[String: simd_float3]]
    let tintColor: UIColor

    private let bones: [(String, String)] = [
        ("leftShoulder", "rightShoulder"),
        ("leftShoulder", "leftElbow"),    ("leftElbow", "leftWrist"),
        ("rightShoulder", "rightElbow"),  ("rightElbow", "rightWrist"),
        ("leftShoulder", "leftHip"),      ("rightShoulder", "rightHip"),
        ("leftHip", "rightHip"),
        ("leftHip", "leftKnee"),          ("leftKnee", "leftAnkle"),
        ("rightHip", "rightKnee"),        ("rightKnee", "rightAnkle"),
        ("neck", "leftShoulder"),         ("neck", "rightShoulder"),
    ]

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.scene = buildScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {}

    // MARK: - Scene Construction

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.8, 2.5)
        scene.rootNode.addChildNode(cameraNode)

        let floorNode = SCNNode(geometry: SCNFloor())
        floorNode.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.15, alpha: 1)
        scene.rootNode.addChildNode(floorNode)

        guard !frames.isEmpty else { return scene }

        // Build one sphere node per joint
        let jointNames = Array(frames[0].keys)
        var jointNodes: [String: SCNNode] = [:]

        for name in jointNames {
            let sphere = SCNSphere(radius: 0.025)
            sphere.firstMaterial?.diffuse.contents = tintColor
            sphere.firstMaterial?.emission.contents = tintColor.withAlphaComponent(0.3)
            let node = SCNNode(geometry: sphere)
            if let pos = frames[0][name] {
                node.position = SCNVector3(pos.x, pos.y, pos.z)
            }
            scene.rootNode.addChildNode(node)
            jointNodes[name] = node
        }

        // Animate joint spheres across frames
        let frameDuration = 0.12
        for (name, node) in jointNodes {
            let positions = frames.compactMap { frame -> NSValue? in
                guard let p = frame[name] else { return nil }
                return NSValue(scnVector3: SCNVector3(p.x, p.y, p.z))
            }
            guard positions.count > 1 else { continue }

            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = positions
            anim.duration = Double(positions.count) * frameDuration
            anim.repeatCount = .infinity
            anim.calculationMode = .linear
            node.addAnimation(anim, forKey: "position")
        }

        // Draw static bone cylinders for the first frame
        for (aName, bName) in bones {
            guard
                let posA = frames[0][aName],
                let posB = frames[0][bName]
            else { continue }
            let cylinder = boneCylinder(from: posA, to: posB)
            scene.rootNode.addChildNode(cylinder)
        }

        return scene
    }

    private func boneCylinder(from a: simd_float3, to b: simd_float3) -> SCNNode {
        let diff = b - a
        let length = simd_length(diff)
        guard length > 0.001 else { return SCNNode() }

        let cylinder = SCNCylinder(radius: 0.012, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = tintColor.withAlphaComponent(0.6)

        let node = SCNNode(geometry: cylinder)
        let mid = (a + b) / 2
        node.position = SCNVector3(mid.x, mid.y, mid.z)

        let up = simd_float3(0, 1, 0)
        let dir = simd_normalize(diff)
        let axis = simd_cross(up, dir)
        let dot = simd_dot(up, dir)
        let angle = acos(max(-1, min(1, dot)))

        if simd_length(axis) > 0.001 {
            node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        }

        return node
    }
}
