import SwiftUI
import SceneKit
import simd

/// Renders an animated 3D stick-figure skeleton in an SCNView.
/// Uses a Timer-driven frame loop via SCNSceneRendererDelegate so that
/// both joint spheres AND bone cylinders update together each tick.
struct SkeletonSceneView: UIViewRepresentable {

    let frames: [[String: simd_float3]]
    let tintColor: UIColor
    var equipmentType: EquipmentType = .none

    // Bone connections (parent → child). Keyed "a--b" in coordinator.
    private let bones: [(String, String, BoneCategory)] = [
        // Spine / torso
        ("neck", "leftShoulder",  .torso),
        ("neck", "rightShoulder", .torso),
        ("leftShoulder",  "rightShoulder", .torso),
        ("leftShoulder",  "leftHip",  .torso),
        ("rightShoulder", "rightHip", .torso),
        ("leftHip",  "rightHip", .torso),
        // Arms
        ("leftShoulder",  "leftElbow",  .arm),
        ("leftElbow",     "leftWrist",  .arm),
        ("rightShoulder", "rightElbow", .arm),
        ("rightElbow",    "rightWrist", .arm),
        // Legs
        ("leftHip",  "leftKnee",  .leg),
        ("leftKnee", "leftAnkle", .leg),
        ("rightHip",  "rightKnee",  .leg),
        ("rightKnee", "rightAnkle", .leg),
    ]

    enum BoneCategory { case torso, arm, leg }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(white: 0.06, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.delegate = context.coordinator

        let scene = SCNScene()
        scnView.scene = scene

        setupLighting(scene: scene)

        guard !frames.isEmpty else { return scnView }

        let coordinator = context.coordinator
        coordinator.frames = frames
        coordinator.buildNodes(in: scene, bones: bones, tintColor: tintColor)
        addEquipment(to: scene, equipmentType: equipmentType)
        coordinator.startAnimation()

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {}

    // MARK: - Lighting

    private func setupLighting(scene: SCNScene) {
        scene.lightingEnvironment.intensity = 0

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 600
        ambient.color = UIColor(white: 1, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 800
        directional.color = UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
        let dirNode = SCNNode()
        dirNode.light = directional
        dirNode.eulerAngles = SCNVector3(-Float.pi / 5, -Float.pi / 6, 0)
        scene.rootNode.addChildNode(dirNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.8, 2.8)
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Equipment

    private func addEquipment(to scene: SCNScene, equipmentType: EquipmentType) {
        switch equipmentType {
        case .none: break

        case .bench:
            let bench = SCNBox(width: 0.6, height: 0.42, length: 1.7, chamferRadius: 0.02)
            bench.firstMaterial?.diffuse.contents = UIColor(white: 0.2, alpha: 1)
            let benchNode = SCNNode(geometry: bench)
            benchNode.position = SCNVector3(0, 0.21, 0)
            scene.rootNode.addChildNode(benchNode)

        case .barbell:
            let bar = SCNCylinder(radius: 0.015, height: 1.8)
            bar.firstMaterial?.diffuse.contents = UIColor(white: 0.7, alpha: 1)
            let barNode = SCNNode(geometry: bar)
            barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            barNode.position = SCNVector3(0, 1.45, 0)
            scene.rootNode.addChildNode(barNode)
            // Plates
            for side: Float in [-0.85, 0.85] {
                let plate = SCNTorus(ringRadius: 0.12, pipeRadius: 0.025)
                plate.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 1)
                let plateNode = SCNNode(geometry: plate)
                plateNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                plateNode.position = SCNVector3(side, 1.45, 0)
                scene.rootNode.addChildNode(plateNode)
            }

        case .benchAndBarbell:
            // Bench
            let bench = SCNBox(width: 0.6, height: 0.42, length: 1.7, chamferRadius: 0.02)
            bench.firstMaterial?.diffuse.contents = UIColor(white: 0.2, alpha: 1)
            let benchNode = SCNNode(geometry: bench)
            benchNode.position = SCNVector3(0, 0.21, 0)
            scene.rootNode.addChildNode(benchNode)
            // Barbell above
            let bar = SCNCylinder(radius: 0.015, height: 1.8)
            bar.firstMaterial?.diffuse.contents = UIColor(white: 0.7, alpha: 1)
            let barNode = SCNNode(geometry: bar)
            barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            barNode.position = SCNVector3(0, 1.45, -0.1)
            scene.rootNode.addChildNode(barNode)
            for side: Float in [-0.85, 0.85] {
                let plate = SCNTorus(ringRadius: 0.12, pipeRadius: 0.025)
                plate.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 1)
                let plateNode = SCNNode(geometry: plate)
                plateNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                plateNode.position = SCNVector3(side, 1.45, -0.1)
                scene.rootNode.addChildNode(plateNode)
            }

        case .pullUpBar:
            let bar = SCNCylinder(radius: 0.025, height: 1.4)
            bar.firstMaterial?.diffuse.contents = UIColor(white: 0.6, alpha: 1)
            let barNode = SCNNode(geometry: bar)
            barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            barNode.position = SCNVector3(0, 2.3, 0)
            scene.rootNode.addChildNode(barNode)

        case .dumbbells:
            for (xPos, wristKey) in [(-0.25, "leftWrist"), (0.25, "rightWrist")] as [(Float, String)] {
                let baseY: Float = frames.first?[wristKey]?.y ?? 1.3
                let shaft = SCNCylinder(radius: 0.03, height: 0.25)
                shaft.firstMaterial?.diffuse.contents = UIColor(white: 0.35, alpha: 1)
                let shaftNode = SCNNode(geometry: shaft)
                shaftNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                shaftNode.position = SCNVector3(xPos, baseY, 0)
                scene.rootNode.addChildNode(shaftNode)
                for endX: Float in [-0.14, 0.14] {
                    let cap = SCNCylinder(radius: 0.055, height: 0.06)
                    cap.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                    let capNode = SCNNode(geometry: cap)
                    capNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    capNode.position = SCNVector3(xPos + endX, baseY, 0)
                    scene.rootNode.addChildNode(capNode)
                }
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var frames: [[String: simd_float3]] = []
        var jointNodes: [String: SCNNode] = [:]
        var boneNodes: [String: SCNNode] = [:]   // key: "a--b"
        var boneConnections: [(String, String)] = []
        private var currentFrameIndex = 0
        private var frameTimer: Timer?

        func buildNodes(
            in scene: SCNScene,
            bones: [(String, String, SkeletonSceneView.BoneCategory)],
            tintColor: UIColor
        ) {
            guard let firstFrame = frames.first else { return }

            let legColor = tintColor.withAlphaComponent(0.85)
            let torsoColor = UIColor(white: 0.92, alpha: 1)
            let headColor = UIColor(white: 0.88, alpha: 1)

            // Joint spheres
            for (name, pos) in firstFrame {
                let radius: CGFloat
                switch name {
                case "leftShoulder", "rightShoulder", "leftHip", "rightHip": radius = 0.035
                case "leftElbow", "rightElbow", "leftKnee", "rightKnee":     radius = 0.025
                default:                                                       radius = 0.02
                }
                let sphere = SCNSphere(radius: radius)
                sphere.firstMaterial?.diffuse.contents = tintColor
                sphere.firstMaterial?.emission.contents = tintColor.withAlphaComponent(0.25)
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(pos.x, pos.y, pos.z)
                scene.rootNode.addChildNode(node)
                jointNodes[name] = node
            }

            // Head sphere above neck
            if let neckPos = firstFrame["neck"] {
                let head = SCNSphere(radius: 0.08)
                head.firstMaterial?.diffuse.contents = headColor
                let headNode = SCNNode(geometry: head)
                headNode.position = SCNVector3(neckPos.x, neckPos.y + 0.15, neckPos.z)
                scene.rootNode.addChildNode(headNode)
                jointNodes["_head"] = headNode
            }

            // Bone cylinders
            for (aName, bName, category) in bones {
                guard let posA = firstFrame[aName], let posB = firstFrame[bName] else { continue }
                let boneRadius: CGFloat = (category == .arm) ? 0.014 : 0.018
                let boneColor: UIColor
                switch category {
                case .torso: boneColor = torsoColor
                case .arm:   boneColor = tintColor.withAlphaComponent(0.9)
                case .leg:   boneColor = legColor
                }
                let node = makeBoneCylinder(from: posA, to: posB, radius: boneRadius, color: boneColor)
                scene.rootNode.addChildNode(node)
                boneNodes["\(aName)--\(bName)"] = node
                boneConnections.append((aName, bName))
            }

            // Head bone (neck → _head)
            if let neckPos = firstFrame["neck"] {
                let headPos = simd_float3(neckPos.x, neckPos.y + 0.15, neckPos.z)
                let node = makeBoneCylinder(from: neckPos, to: headPos, radius: 0.014, color: torsoColor)
                scene.rootNode.addChildNode(node)
                boneNodes["neck--_head"] = node
                boneConnections.append(("neck", "_head"))
            }
        }

        func startAnimation(fps: Double = 8) {
            frameTimer?.invalidate()
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
                guard let self, !self.frames.isEmpty else { return }
                self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frames.count
                self.applyFrame(self.frames[self.currentFrameIndex])
            }
        }

        private func applyFrame(_ frame: [String: simd_float3]) {
            // Update joint spheres
            for (name, node) in jointNodes {
                if name == "_head" {
                    if let neckPos = frame["neck"] {
                        node.position = SCNVector3(neckPos.x, neckPos.y + 0.15, neckPos.z)
                    }
                } else if let pos = frame[name] {
                    node.position = SCNVector3(pos.x, pos.y, pos.z)
                }
            }

            // Update bone cylinders
            for (aName, bName) in boneConnections {
                guard let boneNode = boneNodes["\(aName)--\(bName)"] else { continue }
                let posA: simd_float3?
                let posB: simd_float3?
                if aName == "_head" {
                    posA = frame["neck"].map { simd_float3($0.x, $0.y + 0.15, $0.z) }
                } else {
                    posA = frame[aName]
                }
                if bName == "_head" {
                    posB = frame["neck"].map { simd_float3($0.x, $0.y + 0.15, $0.z) }
                } else {
                    posB = frame[bName]
                }
                guard let a = posA, let b = posB else { continue }
                updateBone(node: boneNode, from: a, to: b)
            }
        }

        // MARK: - Bone geometry helpers

        func makeBoneCylinder(
            from a: simd_float3, to b: simd_float3,
            radius: CGFloat, color: UIColor
        ) -> SCNNode {
            let diff = b - a
            let length = simd_length(diff)
            guard length > 0.001 else { return SCNNode() }

            let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
            cylinder.firstMaterial?.diffuse.contents = color
            cylinder.firstMaterial?.specular.contents = UIColor(white: 0.4, alpha: 1)

            let node = SCNNode(geometry: cylinder)
            let mid = (a + b) / 2
            node.position = SCNVector3(mid.x, mid.y, mid.z)
            orient(node: node, toward: diff)
            return node
        }

        func updateBone(node: SCNNode, from a: simd_float3, to b: simd_float3) {
            let diff = b - a
            let length = simd_length(diff)
            guard length > 0.001,
                  let cylinder = node.geometry as? SCNCylinder else { return }

            cylinder.height = CGFloat(length)
            let mid = (a + b) / 2
            node.position = SCNVector3(mid.x, mid.y, mid.z)
            orient(node: node, toward: diff)
        }

        private func orient(node: SCNNode, toward diff: simd_float3) {
            let dir = simd_normalize(diff)
            let up = simd_float3(0, 1, 0)
            let axis = simd_cross(up, dir)
            let dot = simd_dot(up, dir)
            let angle = acos(max(-1, min(1, dot)))

            if simd_length(axis) > 0.001 {
                node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
            } else if dot < 0 {
                // Anti-parallel: rotate 180° around X
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            } else {
                node.rotation = SCNVector4(0, 0, 0, 0)
            }
        }

        // SCNSceneRendererDelegate — not used for per-frame updates (Timer handles it)
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {}

        deinit { frameTimer?.invalidate() }
    }
}

// MARK: - Equipment Type

enum EquipmentType {
    case none
    case bench
    case barbell
    case benchAndBarbell
    case pullUpBar
    case dumbbells

    static func equipment(for exerciseName: String) -> EquipmentType {
        let lower = exerciseName.lowercased()
        if lower.contains("bench press") || lower.contains("chest press") || lower.contains("incline press") || lower.contains("decline press") {
            return .benchAndBarbell
        } else if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("barbell") {
            return .barbell
        } else if lower.contains("pull up") || lower.contains("pullup") || lower.contains("pull-up") || lower.contains("chin up") || lower.contains("chin-up") {
            return .pullUpBar
        } else if lower.contains("dumbbell") {
            return .dumbbells
        } else {
            return .none
        }
    }
}
