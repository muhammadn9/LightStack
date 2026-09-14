import SwiftUI
import SceneKit
import simd

// MARK: - File-private helpers

private func pbrMaterial(color: UIColor, roughness: Double, metalness: Double) -> SCNMaterial {
    let mat = SCNMaterial()
    mat.lightingModel = .physicallyBased
    mat.diffuse.contents = color
    mat.roughness.contents = NSNumber(value: roughness)
    mat.metalness.contents = NSNumber(value: metalness)
    return mat
}

private func withVirtualJoints(_ frame: [String: simd_float3]) -> [String: simd_float3] {
    var f = frame
    if let ls = f["leftShoulder"], let rs = f["rightShoulder"] {
        f["_shoulderMid"] = (ls + rs) / 2
    }
    if let lh = f["leftHip"], let rh = f["rightHip"] {
        f["_hipMid"] = (lh + rh) / 2
    }
    if let neck = f["neck"] {
        f["_head"] = simd_float3(neck.x, neck.y + 0.15, neck.z)
    }
    return f
}

// MARK: - SkeletonSceneView

/// Renders an animated 3D volumetric skeleton in an SCNView.
/// Uses Timer-driven LERP interpolation for smooth slow-motion playback.
/// Equipment nodes track wrist positions each frame.
struct SkeletonSceneView: UIViewRepresentable {

    let frames: [[String: simd_float3]]
    let tintColor: UIColor
    var equipmentType: EquipmentType = .none
    /// Timer tick rate. Controls frameAdvance: ≤4.5fps → 0.35 frames/tick (study mode), else 0.50 (comparison mode).
    var fps: Double = 6

    // Virtual joints _shoulderMid / _hipMid / _head are computed per frame via withVirtualJoints.
    private let bones: [(String, String, BoneCategory)] = [
        ("_shoulderMid", "_hipMid",        .spine),
        ("_shoulderMid", "neck",           .neck),
        ("leftShoulder",  "rightShoulder", .shoulderBar),
        ("leftHip",       "rightHip",      .hipBar),
        ("leftShoulder",  "leftHip",       .sideRib),
        ("rightShoulder", "rightHip",      .sideRib),
        ("leftShoulder",  "leftElbow",     .upperArm),
        ("leftElbow",     "leftWrist",     .forearm),
        ("rightShoulder", "rightElbow",    .upperArm),
        ("rightElbow",    "rightWrist",    .forearm),
        ("leftHip",       "leftKnee",      .thigh),
        ("leftKnee",      "leftAnkle",     .shin),
        ("rightHip",      "rightKnee",     .thigh),
        ("rightKnee",     "rightAnkle",    .shin),
    ]

    enum BoneCategory {
        case spine, neck, shoulderBar, hipBar, sideRib
        case upperArm, forearm, thigh, shin
    }

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
        addEquipment(to: scene, equipmentType: equipmentType, coordinator: coordinator)
        coordinator.startAnimation(fps: fps)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {}

    // MARK: - Lighting

    private func setupLighting(scene: SCNScene) {
        scene.lightingEnvironment.intensity = 0.0

        // Ambient — soft fill
        addLight(to: scene, type: .ambient, intensity: 280,
                 color: UIColor(white: 1, alpha: 1), euler: SCNVector3(0, 0, 0))
        // Key — warm top-left
        addLight(to: scene, type: .directional, intensity: 950,
                 color: UIColor(red: 1.0, green: 0.95, blue: 0.80, alpha: 1),
                 euler: SCNVector3(-Float.pi / 5, -Float.pi / 6, 0))
        // Fill — cool right
        addLight(to: scene, type: .directional, intensity: 380,
                 color: UIColor(red: 0.72, green: 0.85, blue: 1.0, alpha: 1),
                 euler: SCNVector3(-Float.pi / 8, Float.pi / 3, 0))
        // Rim — cool back
        addLight(to: scene, type: .directional, intensity: 180,
                 color: UIColor(red: 0.62, green: 0.76, blue: 1.0, alpha: 1),
                 euler: SCNVector3(Float.pi / 4, Float.pi, 0))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.9, 2.8)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func addLight(to scene: SCNScene, type: SCNLight.LightType,
                          intensity: CGFloat, color: UIColor, euler: SCNVector3) {
        let light = SCNLight()
        light.type = type
        light.intensity = intensity
        light.color = color
        let node = SCNNode()
        node.light = light
        node.eulerAngles = euler
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Equipment

    private func addEquipment(to scene: SCNScene, equipmentType: EquipmentType, coordinator: Coordinator) {
        let metalMat = pbrMaterial(color: UIColor(white: 0.75, alpha: 1), roughness: 0.12, metalness: 0.82)
        let benchMat = pbrMaterial(color: UIColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1),
                                   roughness: 0.80, metalness: 0.0)

        switch equipmentType {
        case .none: break

        case .bench:
            let bench = SCNBox(width: 0.6, height: 0.42, length: 1.7, chamferRadius: 0.03)
            bench.materials = [benchMat]
            let benchNode = SCNNode(geometry: bench)
            benchNode.position = SCNVector3(0, 0.21, 0)
            scene.rootNode.addChildNode(benchNode)

        case .barbell:
            let bar = makeBarbellNode(metalMat: metalMat)
            bar.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
            if let lw = frames.first?["leftWrist"], let rw = frames.first?["rightWrist"] {
                let mid = (lw + rw) / 2
                bar.position = SCNVector3(mid.x, mid.y, mid.z)
            } else {
                bar.position = SCNVector3(0, 1.45, 0)
            }
            scene.rootNode.addChildNode(bar)
            coordinator.movableEquipmentNodes["barbell"] = bar

        case .benchAndBarbell:
            let bench = SCNBox(width: 0.6, height: 0.42, length: 1.7, chamferRadius: 0.03)
            bench.materials = [benchMat]
            let benchNode = SCNNode(geometry: bench)
            benchNode.position = SCNVector3(0, 0.21, 0)
            scene.rootNode.addChildNode(benchNode)

            let bar = makeBarbellNode(metalMat: metalMat)
            bar.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
            if let lw = frames.first?["leftWrist"], let rw = frames.first?["rightWrist"] {
                let mid = (lw + rw) / 2
                bar.position = SCNVector3(mid.x, mid.y, mid.z)
            } else {
                bar.position = SCNVector3(0, 1.15, 0.15)
            }
            scene.rootNode.addChildNode(bar)
            coordinator.movableEquipmentNodes["barbell"] = bar

        case .pullUpBar:
            let barGeo = SCNCylinder(radius: 0.030, height: 1.4)
            barGeo.materials = [metalMat]
            let barNode = SCNNode(geometry: barGeo)
            barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            barNode.position = SCNVector3(0, 2.3, 0)
            scene.rootNode.addChildNode(barNode)

        case .dumbbells:
            for (sideSign, wristKey, dbKey) in [(-1.0, "leftWrist", "leftDumbbell"),
                                                 (1.0, "rightWrist", "rightDumbbell")] as [(Double, String, String)] {
                let xPos = Float(sideSign) * 0.25
                let baseY = frames.first?[wristKey]?.y ?? 1.3
                let container = SCNNode()
                container.position = SCNVector3(xPos, baseY, 0)

                let shaft = SCNCylinder(radius: 0.03, height: 0.25)
                shaft.materials = [metalMat]
                let shaftNode = SCNNode(geometry: shaft)
                shaftNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                container.addChildNode(shaftNode)

                for endX: Float in [-0.14, 0.14] {
                    let cap = SCNCylinder(radius: 0.055, height: 0.06)
                    cap.materials = [metalMat]
                    let capNode = SCNNode(geometry: cap)
                    capNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    capNode.position = SCNVector3(endX, 0, 0)
                    container.addChildNode(capNode)
                }
                scene.rootNode.addChildNode(container)
                coordinator.movableEquipmentNodes[dbKey] = container
            }
        }
    }

    private func makeBarbellNode(metalMat: SCNMaterial) -> SCNNode {
        let container = SCNNode()

        let bar = SCNCylinder(radius: 0.018, height: 1.8)
        bar.materials = [metalMat]
        container.addChildNode(SCNNode(geometry: bar))

        // Plates at ±0.85 along bar's local Y axis
        for side: Float in [-0.85, 0.85] {
            let plate = SCNTorus(ringRadius: 0.12, pipeRadius: 0.030)
            plate.materials = [metalMat]
            let plateNode = SCNNode(geometry: plate)
            plateNode.position = SCNVector3(0, side, 0)
            container.addChildNode(plateNode)
        }
        return container
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var frames: [[String: simd_float3]] = []
        var jointNodes: [String: SCNNode] = [:]
        var boneNodes: [String: SCNNode] = [:]          // key: "a--b"
        var boneConnections: [(String, String)] = []
        var movableEquipmentNodes: [String: SCNNode] = [:]

        private var currentT: Double = 0
        private var frameAdvance: Double = 0.50
        private var frameTimer: Timer?

        var muscleBulkNodes: [String: SCNNode] = [:]  // key: muscle name

        func buildNodes(
            in scene: SCNScene,
            bones: [(String, String, SkeletonSceneView.BoneCategory)],
            tintColor: UIColor
        ) {
            guard let firstFrame = frames.first else { return }
            let frame = withVirtualJoints(firstFrame)

            let skinColor = UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 1.0)
            let muscleColor = UIColor(red: 0.75, green: 0.30, blue: 0.28, alpha: 0.85)
            let torsoColor = skinColor

            // 4 landmark joint spheres (shoulders + hips) — larger for smooth connections
            for name in ["leftShoulder", "rightShoulder", "leftHip", "rightHip"] {
                guard let pos = frame[name] else { continue }
                let sphere = SCNSphere(radius: 0.045)
                sphere.materials = [pbrMaterial(color: skinColor, roughness: 0.55, metalness: 0.02)]
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(pos.x, pos.y, pos.z)
                scene.rootNode.addChildNode(node)
                jointNodes[name] = node
            }

            // Elbow and knee joints — smooth connectors
            for name in ["leftElbow", "rightElbow", "leftKnee", "rightKnee"] {
                guard let pos = frame[name] else { continue }
                let sphere = SCNSphere(radius: 0.038)
                sphere.materials = [pbrMaterial(color: skinColor, roughness: 0.55, metalness: 0.02)]
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(pos.x, pos.y, pos.z)
                scene.rootNode.addChildNode(node)
                jointNodes[name] = node
            }

            // Head sphere with neck connector
            if let headPos = frame["_head"] {
                let head = SCNSphere(radius: 0.10)
                head.materials = [pbrMaterial(color: skinColor, roughness: 0.60, metalness: 0.0)]
                let headNode = SCNNode(geometry: head)
                headNode.position = SCNVector3(headPos.x, headPos.y, headPos.z)
                scene.rootNode.addChildNode(headNode)
                jointNodes["_head"] = headNode
            }

            // Capsule bones
            for (aName, bName, category) in bones {
                guard let posA = frame[aName], let posB = frame[bName] else { continue }
                let radius = capsuleRadius(for: category)
                let color: UIColor
                switch category {
                case .spine, .neck, .shoulderBar, .hipBar, .sideRib:
                    color = torsoColor
                case .upperArm, .forearm:
                    color = skinColor
                case .thigh, .shin:
                    color = skinColor
                }
                let node = makeBoneCapsule(from: posA, to: posB, capRadius: radius, color: color)
                scene.rootNode.addChildNode(node)
                boneNodes["\(aName)--\(bName)"] = node
                boneConnections.append((aName, bName))
            }

            // Muscle bulk overlays
            buildMuscleBulk(in: scene, frame: frame, muscleColor: muscleColor, skinColor: skinColor)
        }

        private func buildMuscleBulk(
            in scene: SCNScene,
            frame: [String: simd_float3],
            muscleColor: UIColor,
            skinColor: UIColor
        ) {
            let muscleMat = pbrMaterial(color: muscleColor, roughness: 0.50, metalness: 0.03)
            let skinMat = pbrMaterial(color: skinColor.withAlphaComponent(0.5), roughness: 0.60, metalness: 0.0)

            // Chest (pectoralis major) — flattened capsule between shoulders, offset forward
            if let ls = frame["leftShoulder"], let rs = frame["rightShoulder"],
               let mid = frame["_shoulderMid"], let hipMid = frame["_hipMid"] {
                let chestWidth = CGFloat(simd_length(rs - ls)) * 0.85
                let chestPos = simd_float3(mid.x, mid.y - 0.05, mid.z + 0.04)
                let chest = SCNCapsule(capRadius: 0.06, height: max(0.01, chestWidth - 0.12))
                chest.materials = [muscleMat]
                let chestNode = SCNNode(geometry: chest)
                chestNode.position = SCNVector3(chestPos.x, chestPos.y, chestPos.z)
                chestNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                chestNode.scale = SCNVector3(1.0, 0.6, 1.2)
                scene.rootNode.addChildNode(chestNode)
                muscleBulkNodes["chest"] = chestNode

                // Abs/core — along spine
                let absPos = (mid + hipMid) / 2
                let absHeight = CGFloat(simd_length(mid - hipMid)) * 0.6
                let abs = SCNCapsule(capRadius: 0.065, height: max(0.01, absHeight))
                abs.materials = [muscleMat]
                let absNode = SCNNode(geometry: abs)
                absNode.position = SCNVector3(absPos.x, absPos.y, absPos.z + 0.02)
                absNode.scale = SCNVector3(0.9, 1.0, 0.7)
                scene.rootNode.addChildNode(absNode)
                muscleBulkNodes["abs"] = absNode

                // Lats — wider back muscles
                let latsPos = simd_float3(mid.x, mid.y - 0.06, mid.z - 0.03)
                let lats = SCNCapsule(capRadius: 0.07, height: max(0.01, chestWidth - 0.08))
                lats.materials = [muscleMat]
                let latsNode = SCNNode(geometry: lats)
                latsNode.position = SCNVector3(latsPos.x, latsPos.y, latsPos.z)
                latsNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                latsNode.scale = SCNVector3(1.0, 0.5, 1.1)
                scene.rootNode.addChildNode(latsNode)
                muscleBulkNodes["lats"] = latsNode
            }

            // Deltoids — shoulder caps
            for (shoulderKey, sign) in [("leftShoulder", Float(-1)), ("rightShoulder", Float(1))] {
                guard let sp = frame[shoulderKey] else { continue }
                let deltoid = SCNSphere(radius: 0.055)
                deltoid.materials = [muscleMat]
                let dNode = SCNNode(geometry: deltoid)
                dNode.position = SCNVector3(sp.x + sign * 0.01, sp.y + 0.01, sp.z)
                dNode.scale = SCNVector3(1.2, 0.9, 1.0)
                scene.rootNode.addChildNode(dNode)
                muscleBulkNodes["\(shoulderKey)_deltoid"] = dNode
            }

            // Biceps and Triceps
            for side in ["left", "right"] {
                let shoulderKey = "\(side)Shoulder"
                let elbowKey = "\(side)Elbow"
                guard let sp = frame[shoulderKey], let ep = frame[elbowKey] else { continue }
                let armMid = (sp + ep) / 2
                let armLen = CGFloat(simd_length(ep - sp))

                // Bicep — front of upper arm
                let bicep = SCNCapsule(capRadius: 0.042, height: max(0.01, armLen * 0.55))
                bicep.materials = [muscleMat]
                let bicepNode = SCNNode(geometry: bicep)
                bicepNode.position = SCNVector3(armMid.x, armMid.y, armMid.z + 0.015)
                orient(node: bicepNode, toward: ep - sp)
                scene.rootNode.addChildNode(bicepNode)
                muscleBulkNodes["\(side)Bicep"] = bicepNode

                // Tricep — back of upper arm
                let tricep = SCNCapsule(capRadius: 0.038, height: max(0.01, armLen * 0.50))
                tricep.materials = [muscleMat]
                let tricepNode = SCNNode(geometry: tricep)
                tricepNode.position = SCNVector3(armMid.x, armMid.y, armMid.z - 0.015)
                orient(node: tricepNode, toward: ep - sp)
                scene.rootNode.addChildNode(tricepNode)
                muscleBulkNodes["\(side)Tricep"] = tricepNode
            }

            // Quads, Hamstrings, Glutes, Calves
            for side in ["left", "right"] {
                let hipKey = "\(side)Hip"
                let kneeKey = "\(side)Knee"
                let ankleKey = "\(side)Ankle"
                guard let hp = frame[hipKey], let kp = frame[kneeKey] else { continue }
                let thighMid = (hp + kp) / 2
                let thighLen = CGFloat(simd_length(kp - hp))

                // Glute — at hip
                let glute = SCNSphere(radius: 0.065)
                glute.materials = [muscleMat]
                let gluteNode = SCNNode(geometry: glute)
                gluteNode.position = SCNVector3(hp.x, hp.y - 0.02, hp.z - 0.025)
                gluteNode.scale = SCNVector3(1.0, 0.8, 1.1)
                scene.rootNode.addChildNode(gluteNode)
                muscleBulkNodes["\(side)Glute"] = gluteNode

                // Quad — front of thigh
                let quad = SCNCapsule(capRadius: 0.055, height: max(0.01, thighLen * 0.6))
                quad.materials = [muscleMat]
                let quadNode = SCNNode(geometry: quad)
                quadNode.position = SCNVector3(thighMid.x, thighMid.y, thighMid.z + 0.02)
                orient(node: quadNode, toward: kp - hp)
                scene.rootNode.addChildNode(quadNode)
                muscleBulkNodes["\(side)Quad"] = quadNode

                // Hamstring — back of thigh
                let hamstring = SCNCapsule(capRadius: 0.048, height: max(0.01, thighLen * 0.55))
                hamstring.materials = [muscleMat]
                let hamNode = SCNNode(geometry: hamstring)
                hamNode.position = SCNVector3(thighMid.x, thighMid.y, thighMid.z - 0.02)
                orient(node: hamNode, toward: kp - hp)
                scene.rootNode.addChildNode(hamNode)
                muscleBulkNodes["\(side)Hamstring"] = hamNode

                // Calf
                if let ap = frame[ankleKey] {
                    let calfMid = (kp + ap) / 2
                    let calfLen = CGFloat(simd_length(ap - kp))
                    let calf = SCNCapsule(capRadius: 0.040, height: max(0.01, calfLen * 0.5))
                    calf.materials = [muscleMat]
                    let calfNode = SCNNode(geometry: calf)
                    calfNode.position = SCNVector3(calfMid.x, calfMid.y + Float(calfLen) * 0.1, calfMid.z - 0.01)
                    orient(node: calfNode, toward: ap - kp)
                    scene.rootNode.addChildNode(calfNode)
                    muscleBulkNodes["\(side)Calf"] = calfNode
                }
            }

            // Semi-transparent skin layer over torso
            if let sm = frame["_shoulderMid"], let hm = frame["_hipMid"] {
                let torsoLen = CGFloat(simd_length(sm - hm))
                let torsoMid = (sm + hm) / 2
                let skin = SCNCapsule(capRadius: 0.10, height: max(0.01, torsoLen * 0.6))
                skin.materials = [skinMat]
                let skinNode = SCNNode(geometry: skin)
                skinNode.position = SCNVector3(torsoMid.x, torsoMid.y, torsoMid.z)
                skinNode.scale = SCNVector3(0.85, 1.0, 0.75)
                scene.rootNode.addChildNode(skinNode)
                muscleBulkNodes["torsoSkin"] = skinNode
            }
        }

        func startAnimation(fps: Double = 6) {
            frameAdvance = fps <= 4.5 ? 0.35 : 0.50
            frameTimer?.invalidate()
            frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
                guard let self, self.frames.count > 1 else { return }
                self.currentT += self.frameAdvance
                if self.currentT >= Double(self.frames.count) { self.currentT = 0 }
                let idxA = Int(self.currentT) % self.frames.count
                let idxB = (idxA + 1) % self.frames.count
                let t = Float(self.currentT - Double(Int(self.currentT)))
                let blended = self.lerpFrames(self.frames[idxA], self.frames[idxB], t: t)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.06
                self.applyFrame(blended)
                SCNTransaction.commit()
            }
        }

        private func lerpFrames(
            _ a: [String: simd_float3],
            _ b: [String: simd_float3],
            t: Float
        ) -> [String: simd_float3] {
            var result: [String: simd_float3] = [:]
            for (key, posA) in a {
                result[key] = simd_mix(posA, b[key] ?? posA, simd_float3(repeating: t))
            }
            return result
        }

        private func applyFrame(_ rawFrame: [String: simd_float3]) {
            let frame = withVirtualJoints(rawFrame)

            // Landmark joint spheres + head
            for (name, node) in jointNodes {
                if let pos = frame[name] {
                    node.position = SCNVector3(pos.x, pos.y, pos.z)
                }
            }

            // Bone capsules
            for (aName, bName) in boneConnections {
                guard let boneNode = boneNodes["\(aName)--\(bName)"],
                      let posA = frame[aName],
                      let posB = frame[bName] else { continue }
                updateBone(node: boneNode, from: posA, to: posB)
            }

            // Animated equipment
            if let barbellNode = movableEquipmentNodes["barbell"],
               let lw = frame["leftWrist"], let rw = frame["rightWrist"] {
                let mid = (lw + rw) / 2
                barbellNode.position = SCNVector3(mid.x, mid.y, mid.z)
                orient(node: barbellNode, toward: rw - lw)
            }
            if let leftDb = movableEquipmentNodes["leftDumbbell"],
               let lw = frame["leftWrist"] {
                leftDb.position = SCNVector3(lw.x, lw.y, lw.z)
            }
            if let rightDb = movableEquipmentNodes["rightDumbbell"],
               let rw = frame["rightWrist"] {
                rightDb.position = SCNVector3(rw.x, rw.y, rw.z)
            }
        }

        // MARK: - Bone geometry helpers

        func makeBoneCapsule(
            from a: simd_float3, to b: simd_float3,
            capRadius: CGFloat, color: UIColor
        ) -> SCNNode {
            let diff = b - a
            let length = CGFloat(simd_length(diff))
            guard length > 0.001 else { return SCNNode() }

            let capsule = SCNCapsule(capRadius: capRadius,
                                     height: max(0.001, length - 2 * capRadius))
            capsule.materials = [pbrMaterial(color: color, roughness: 0.55, metalness: 0.05)]

            let node = SCNNode(geometry: capsule)
            let mid = (a + b) / 2
            node.position = SCNVector3(mid.x, mid.y, mid.z)
            orient(node: node, toward: diff)
            return node
        }

        func updateBone(node: SCNNode, from a: simd_float3, to b: simd_float3) {
            let diff = b - a
            let length = CGFloat(simd_length(diff))
            guard length > 0.001,
                  let capsule = node.geometry as? SCNCapsule else { return }

            capsule.height = max(0.001, length - 2 * capsule.capRadius)
            let mid = (a + b) / 2
            node.position = SCNVector3(mid.x, mid.y, mid.z)
            orient(node: node, toward: diff)
        }

        private func capsuleRadius(for category: SkeletonSceneView.BoneCategory) -> CGFloat {
            switch category {
            case .spine:       return 0.075
            case .neck:        return 0.040
            case .shoulderBar: return 0.038
            case .hipBar:      return 0.038
            case .sideRib:     return 0.035
            case .upperArm:    return 0.050
            case .forearm:     return 0.042
            case .thigh:       return 0.062
            case .shin:        return 0.050
            }
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
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            } else {
                node.rotation = SCNVector4(0, 0, 0, 0)
            }
        }

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
        if lower.contains("bench press") || lower.contains("chest press")
            || lower.contains("incline press") || lower.contains("decline press") {
            return .benchAndBarbell
        } else if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("barbell") {
            return .barbell
        } else if lower.contains("pull up") || lower.contains("pullup") || lower.contains("pull-up")
            || lower.contains("chin up") || lower.contains("chin-up") {
            return .pullUpBar
        } else if lower.contains("dumbbell") {
            return .dumbbells
        } else {
            return .none
        }
    }
}
