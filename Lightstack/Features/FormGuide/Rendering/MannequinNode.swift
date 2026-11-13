import SceneKit
import UIKit
import simd

/// Palette used by the mannequin and the scene. Kept in one place so tests and the scene controller agree.
struct MannequinPalette {
    var body: UIColor
    var muscle: UIColor
    var primary: UIColor
    var secondary: UIColor
    var visor: UIColor

    static func make(dark: Bool) -> MannequinPalette {
        let trait = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let accent = UIColor(AppTheme.accent).resolvedColor(with: trait)
        let body = UIColor(red: 0.70, green: 0.73, blue: 0.77, alpha: 1)
        let muscle = UIColor(red: 0.63, green: 0.67, blue: 0.72, alpha: 1)
        return MannequinPalette(body: body, muscle: muscle, primary: accent,
                                secondary: mix(accent, UIColor(red: 0.86, green: 0.89, blue: 0.88, alpha: 1), 0.62),
                                visor: UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1))
    }

    static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }
}

/// A stylised training mannequin built from lofted meshes. `apply(_:)` only moves nodes; no geometry is rebuilt.
final class MannequinNode: SCNNode {

    enum SegmentKind: String {
        case lowerTorso, upperTorso, neck, head
        case leftThigh, leftShin, leftFoot, rightThigh, rightShin, rightFoot
        case leftUpperArm, leftForearm, leftHand, rightUpperArm, rightForearm, rightHand
    }

    /// A rigid piece positioned from two joints. `length` is the distance from its origin to its far end.
    struct Segment {
        let kind: SegmentKind
        let node: SCNNode
        let from: GuideJoint
        let to: GuideJoint
        let length: Float
    }

    private(set) var segments: [Segment] = []
    private var segmentNodes: [SegmentKind: SCNNode] = [:]
    private var muscleMaterials: [MuscleGroup: SCNMaterial] = [:]
    private var muscleNodes: [MuscleGroup: [SCNNode]] = [:]
    private let bodyMaterial = SCNMaterial()
    private let visorMaterial = SCNMaterial()
    private(set) var palette: MannequinPalette
    private(set) var primaryHighlight: Set<MuscleGroup> = []
    private(set) var secondaryHighlight: Set<MuscleGroup> = []

    init(palette: MannequinPalette = .make(dark: true)) {
        self.palette = palette
        super.init()
        name = "mannequin"
        configureMaterials()
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Materials

    private static func pbr(_ color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private func configureMaterials() {
        bodyMaterial.lightingModel = .physicallyBased
        bodyMaterial.diffuse.contents = palette.body
        bodyMaterial.roughness.contents = 0.52
        bodyMaterial.metalness.contents = 0.0
        visorMaterial.lightingModel = .physicallyBased
        visorMaterial.diffuse.contents = palette.visor
        visorMaterial.roughness.contents = 0.22
        visorMaterial.metalness.contents = 0.0
        for group in MuscleGroup.allCases {
            let m = Self.pbr(palette.muscle, roughness: 0.5)
            m.name = "muscle.\(group.rawValue)"
            muscleMaterials[group] = m
        }
    }

    /// Current diffuse colour of a muscle group's material (model value, not the animated presentation value).
    func muscleColor(_ group: MuscleGroup) -> UIColor? {
        muscleMaterials[group]?.diffuse.contents as? UIColor
    }

    func muscleMaterial(_ group: MuscleGroup) -> SCNMaterial? { muscleMaterials[group] }

    func setPalette(_ new: MannequinPalette) {
        palette = new
        bodyMaterial.diffuse.contents = new.body
        visorMaterial.diffuse.contents = new.visor
        refreshHighlightColours(animated: false)
    }

    // MARK: Highlight

    func setHighlight(primary: Set<MuscleGroup>, secondary: Set<MuscleGroup>, animated: Bool = true) {
        primaryHighlight = primary
        secondaryHighlight = secondary.subtracting(primary)
        refreshHighlightColours(animated: animated)
    }

    private func refreshHighlightColours(animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.3 : 0
        for group in MuscleGroup.allCases {
            guard let m = muscleMaterials[group] else { continue }
            if primaryHighlight.contains(group) {
                m.diffuse.contents = palette.primary
                m.emission.contents = MannequinPalette.mix(palette.primary, .black, 0.80)
                m.roughness.contents = 0.38
            } else if secondaryHighlight.contains(group) {
                m.diffuse.contents = palette.secondary
                m.emission.contents = MannequinPalette.mix(palette.secondary, .black, 0.85)
                m.roughness.contents = 0.45
            } else {
                m.diffuse.contents = palette.muscle
                m.emission.contents = UIColor.black
                m.roughness.contents = 0.5
            }
        }
        SCNTransaction.commit()
    }

    // MARK: Construction

    private func addSegment(_ kind: SegmentKind, from: GuideJoint, to: GuideJoint, length: Float,
                            geometry: SCNGeometry, material: SCNMaterial? = nil) -> SCNNode {
        geometry.materials = [material ?? bodyMaterial]
        let node = SCNNode(geometry: geometry)
        node.name = kind.rawValue
        addChildNode(node)
        segments.append(Segment(kind: kind, node: node, from: from, to: to, length: length))
        segmentNodes[kind] = node
        return node
    }

    private func attachEllipsoid(_ group: MuscleGroup, to parent: SCNNode, center: SIMD3<Float>, radii: SIMD3<Float>) {
        guard let material = muscleMaterials[group] else { return }
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 22
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        // Sink the shape slightly into the body so it reads as a soft relief, not a blob.
        var c = center
        let radial = SIMD2<Float>(center.x, center.z)
        let rl = simd_length(radial)
        if rl > 0.02 { let k = max(rl - 0.007, 0) / rl; c.x *= k; c.z *= k }
        node.simdPosition = c
        node.simdScale = radii
        node.name = "m.\(group.rawValue)"
        parent.addChildNode(node)
        muscleNodes[group, default: []].append(node)
    }

    /// Adds a muscle shape to a limb. `x` is "outward positive"; limb frames point down, so local x is flipped per side.
    private func attachLimbMuscle(_ group: MuscleGroup, kinds: (left: SegmentKind, right: SegmentKind),
                                  out: Float, y: Float, z: Float, radii: SIMD3<Float>) {
        if let l = segmentNodes[kinds.left] {
            attachEllipsoid(group, to: l, center: SIMD3(-out, y, z), radii: radii)
        }
        if let r = segmentNodes[kinds.right] {
            attachEllipsoid(group, to: r, center: SIMD3(out, y, z), radii: radii)
        }
    }

    private func attachTorsoMuscle(_ group: MuscleGroup, kind: SegmentKind, x: Float, y: Float, z: Float,
                                   radii: SIMD3<Float>, mirrored: Bool = true) {
        guard let node = segmentNodes[kind] else { return }
        attachEllipsoid(group, to: node, center: SIMD3(x, y, z), radii: radii)
        if mirrored, abs(x) > 1e-5 {
            attachEllipsoid(group, to: node, center: SIMD3(-x, y, z), radii: radii)
        }
    }

    private func build() {
        typealias P = FigureProportions
        typealias L = LoftBuilder

        // Torso, in two overlapping pieces so the spine can bend.
        func torso(_ keys: [(y: Float, rx: Float, rz: Float, cz: Float)], rings: Int) -> SCNGeometry {
            let yMin = keys.first?.y ?? 0, yMax = keys.last?.y ?? 1
            let rx = keys.map { (t: $0.y, v: $0.rx) }
            let rz = keys.map { (t: $0.y, v: $0.rz) }
            let cz = keys.map { (t: $0.y, v: $0.cz) }
            var out: [LoftRing] = []
            for i in 0...rings {
                let y = yMin + (yMax - yMin) * Float(i) / Float(rings)
                out.append(LoftRing(y: y, rx: L.smoothSample(rx, at: y), rz: L.smoothSample(rz, at: y), cz: L.smoothSample(cz, at: y)))
            }
            return L.geometry(rings: out, segments: 36)
        }
        let lowerTorso = addSegment(.lowerTorso, from: .pelvis, to: .spineMid, length: P.spineLower,
            geometry: torso([(-0.118, 0.012, 0.012, 0), (-0.108, 0.05, 0.04, 0), (-0.09, 0.098, 0.07, -0.004),
                             (-0.05, 0.138, 0.092, -0.010), (0.0, 0.155, 0.10, -0.012), (0.07, 0.152, 0.100, -0.006),
                             (0.16, 0.140, 0.094, 0.0), (0.22, 0.134, 0.090, 0.004), (0.255, 0.134, 0.090, 0.006),
                             (0.285, 0.07, 0.05, 0.006)], rings: 22))
        let upperTorso = addSegment(.upperTorso, from: .spineMid, to: .chest, length: P.spineUpper,
            geometry: torso([(-0.03, 0.095, 0.07, 0.0), (0.0, 0.134, 0.090, 0.004), (0.07, 0.148, 0.098, 0.008),
                             (0.14, 0.166, 0.105, 0.012), (0.20, 0.176, 0.110, 0.012), (0.245, 0.168, 0.098, 0.004),
                             (0.275, 0.128, 0.078, -0.006), (0.30, 0.074, 0.060, -0.010),
                             (0.322, 0.046, 0.046, -0.010), (0.333, 0.016, 0.016, -0.010)], rings: 26))
        _ = lowerTorso; _ = upperTorso

        _ = addSegment(.neck, from: .chest, to: .head, length: 0.20,
            geometry: L.limb(length: 0.20, profile: [(0, 0.052, 0.054, -0.004), (0.5, 0.047, 0.049, 0.0), (1, 0.046, 0.048, 0.006)],
                             startCap: 0, endCap: 0, bodyRings: 6))

        let headGeo: SCNGeometry = {
            let keys: [(t: Float, v: Float)] = [(-0.118, 0.012), (-0.108, 0.034), (-0.09, 0.052), (-0.05, 0.070), (0, 0.078),
                                                (0.05, 0.078), (0.09, 0.067), (0.113, 0.042), (0.125, 0.012)]
            let zKeys: [(t: Float, v: Float)] = [(-0.118, 0.012), (-0.108, 0.04), (-0.09, 0.066), (-0.05, 0.086), (0, 0.097),
                                                 (0.05, 0.095), (0.09, 0.083), (0.113, 0.052), (0.125, 0.014)]
            let cKeys: [(t: Float, v: Float)] = [(-0.118, 0.03), (-0.09, 0.026), (-0.05, 0.012), (0, 0.0), (0.05, -0.002),
                                                 (0.09, -0.004), (0.125, -0.006)]
            var rings: [LoftRing] = []
            for i in 0...24 {
                let y = -0.118 + 0.243 * Float(i) / 24
                rings.append(LoftRing(y: y, rx: L.smoothSample(keys, at: y), rz: L.smoothSample(zKeys, at: y),
                                      cz: L.smoothSample(cKeys, at: y)))
            }
            return L.geometry(rings: rings, segments: 32)
        }()
        let head = addSegment(.head, from: .head, to: .head, length: 0, geometry: headGeo)
        // Face: a dark visor band and a soft nose make the facing direction obvious.
        let visor = SCNNode(geometry: L.ellipsoid(rx: 0.071, ry: 0.030, rz: 0.060, rings: 12, segments: 24))
        visor.geometry?.materials = [visorMaterial]
        visor.simdPosition = SIMD3(0, 0.014, 0.044)
        visor.simdEulerAngles = SIMD3(0.10, 0, 0)
        visor.name = "visor"
        head.addChildNode(visor)
        let nose = SCNNode(geometry: L.ellipsoid(rx: 0.010, ry: 0.020, rz: 0.015, rings: 8, segments: 14))
        nose.geometry?.materials = [bodyMaterial]
        nose.simdPosition = SIMD3(0, -0.028, 0.092)
        nose.simdEulerAngles = SIMD3(-0.35, 0, 0)
        nose.name = "nose"
        head.addChildNode(nose)

        for (side, prefix) in [(Float(1), "left"), (Float(-1), "right")] {
            _ = side
            let thighKind: SegmentKind = prefix == "left" ? .leftThigh : .rightThigh
            let shinKind: SegmentKind = prefix == "left" ? .leftShin : .rightShin
            let footKind: SegmentKind = prefix == "left" ? .leftFoot : .rightFoot
            let upperKind: SegmentKind = prefix == "left" ? .leftUpperArm : .rightUpperArm
            let foreKind: SegmentKind = prefix == "left" ? .leftForearm : .rightForearm
            let handKind: SegmentKind = prefix == "left" ? .leftHand : .rightHand
            let hip: GuideJoint = prefix == "left" ? .leftHip : .rightHip
            let knee: GuideJoint = prefix == "left" ? .leftKnee : .rightKnee
            let ankle: GuideJoint = prefix == "left" ? .leftAnkle : .rightAnkle
            let toe: GuideJoint = prefix == "left" ? .leftToe : .rightToe
            let shoulder: GuideJoint = prefix == "left" ? .leftShoulder : .rightShoulder
            let elbow: GuideJoint = prefix == "left" ? .leftElbow : .rightElbow
            let wrist: GuideJoint = prefix == "left" ? .leftWrist : .rightWrist
            let hand: GuideJoint = prefix == "left" ? .leftHand : .rightHand

            _ = addSegment(thighKind, from: hip, to: knee, length: P.thigh,
                geometry: L.limb(length: P.thigh, profile: [(0, 0.078, 0.082, 0), (0.22, 0.075, 0.080, 0.004),
                                                             (0.6, 0.063, 0.067, 0.002), (1, 0.050, 0.051, 0)],
                                 startCap: 0.078, endCap: 0.050))
            _ = addSegment(shinKind, from: knee, to: ankle, length: P.shin,
                geometry: L.limb(length: P.shin, profile: [(0, 0.050, 0.051, 0), (0.12, 0.051, 0.054, -0.002),
                                                            (0.30, 0.050, 0.060, -0.010), (0.55, 0.041, 0.044, -0.004),
                                                            (1, 0.030, 0.031, 0)],
                                 startCap: 0.050, endCap: 0.031))
            _ = addSegment(footKind, from: ankle, to: toe, length: P.foot, geometry: Self.footGeometry())
            _ = addSegment(upperKind, from: shoulder, to: elbow, length: P.upperArm,
                geometry: L.limb(length: P.upperArm, profile: [(0, 0.056, 0.057, 0), (0.30, 0.050, 0.053, 0),
                                                                (0.65, 0.043, 0.046, 0), (1, 0.039, 0.039, 0)],
                                 startCap: 0.056, endCap: 0.039))
            _ = addSegment(foreKind, from: elbow, to: wrist, length: P.forearm,
                geometry: L.limb(length: P.forearm, profile: [(0, 0.039, 0.040, 0), (0.25, 0.044, 0.046, 0),
                                                              (0.6, 0.035, 0.035, 0), (1, 0.027, 0.025, 0)],
                                 startCap: 0.039, endCap: 0.027))
            // Hand: a mitten that wraps the grip axis (local X = grip axis, local Y = wrist to grip centre).
            let handGeo = L.limb(length: P.hand + 0.015,
                                 profile: [(0, 0.028, 0.021, 0), (0.35, 0.040, 0.027, 0), (0.75, 0.047, 0.033, 0), (1, 0.044, 0.032, 0)],
                                 startCap: 0.022, endCap: 0.030, bodyRings: 8, capRings: 5, segments: 24)
            _ = addSegment(handKind, from: wrist, to: hand, length: P.hand, geometry: handGeo)
        }

        addMuscles()
    }

    /// Foot built in its own frame: local Y runs ankle to toe, local Z is the foot's "up", local X is across.
    private static func footGeometry() -> SCNGeometry {
        let tanP: Float = 0.4364, off: Float = -0.0873
        func sole(_ s: Float) -> Float { off + tanP * s }
        let keys: [(s: Float, hx: Float, thick: Float)] = [
            (-0.074, 0.010, 0.012), (-0.066, 0.024, 0.040), (-0.048, 0.034, 0.075), (-0.010, 0.038, 0.106),
            (0.04, 0.039, 0.092), (0.10, 0.042, 0.070), (0.16, 0.046, 0.054), (0.20, 0.047, 0.046),
            (0.232, 0.040, 0.034), (0.252, 0.026, 0.022), (0.262, 0.010, 0.012)
        ]
        let hx = keys.map { (t: $0.s, v: $0.hx) }
        let th = keys.map { (t: $0.s, v: $0.thick) }
        var rings: [LoftRing] = []
        let count = 22
        let s0 = keys.first?.s ?? 0, s1 = keys.last?.s ?? 1
        for i in 0...count {
            let s = s0 + (s1 - s0) * Float(i) / Float(count)
            let thick = LoftBuilder.smoothSample(th, at: s)
            let bottom = sole(s)
            rings.append(LoftRing(y: s, rx: LoftBuilder.smoothSample(hx, at: s), rz: thick / 2, cz: bottom + thick / 2))
        }
        return LoftBuilder.geometry(rings: rings, segments: 28)
    }

    private func addMuscles() {
        let thighs = (left: SegmentKind.leftThigh, right: SegmentKind.rightThigh)
        let shins = (left: SegmentKind.leftShin, right: SegmentKind.rightShin)
        let arms = (left: SegmentKind.leftUpperArm, right: SegmentKind.rightUpperArm)
        let fores = (left: SegmentKind.leftForearm, right: SegmentKind.rightForearm)

        // Legs
        attachLimbMuscle(.quads, kinds: thighs, out: 0.0, y: 0.215, z: 0.047, radii: SIMD3(0.036, 0.150, 0.030))
        attachLimbMuscle(.quads, kinds: thighs, out: 0.041, y: 0.205, z: 0.022, radii: SIMD3(0.034, 0.140, 0.034))
        attachLimbMuscle(.quads, kinds: thighs, out: -0.036, y: 0.325, z: 0.030, radii: SIMD3(0.027, 0.072, 0.027))
        attachLimbMuscle(.hamstrings, kinds: thighs, out: 0.0, y: 0.21, z: -0.046, radii: SIMD3(0.050, 0.150, 0.030))
        attachLimbMuscle(.adductors, kinds: thighs, out: -0.048, y: 0.17, z: -0.004, radii: SIMD3(0.028, 0.120, 0.042))
        attachLimbMuscle(.calves, kinds: shins, out: 0.020, y: 0.115, z: -0.050, radii: SIMD3(0.027, 0.095, 0.033))
        attachLimbMuscle(.calves, kinds: shins, out: -0.020, y: 0.115, z: -0.050, radii: SIMD3(0.027, 0.095, 0.033))

        // Arms (upper arm local y runs shoulder to elbow)
        attachLimbMuscle(.frontDelts, kinds: arms, out: 0.004, y: 0.05, z: 0.040, radii: SIMD3(0.036, 0.066, 0.030))
        attachLimbMuscle(.sideDelts, kinds: arms, out: 0.044, y: 0.05, z: 0.0, radii: SIMD3(0.028, 0.066, 0.040))
        attachLimbMuscle(.rearDelts, kinds: arms, out: 0.004, y: 0.05, z: -0.042, radii: SIMD3(0.036, 0.062, 0.030))
        attachLimbMuscle(.biceps, kinds: arms, out: 0.0, y: 0.125, z: 0.032, radii: SIMD3(0.028, 0.075, 0.026))
        attachLimbMuscle(.triceps, kinds: arms, out: 0.0, y: 0.125, z: -0.034, radii: SIMD3(0.032, 0.090, 0.028))
        attachLimbMuscle(.triceps, kinds: arms, out: 0.026, y: 0.115, z: -0.010, radii: SIMD3(0.022, 0.080, 0.030))
        attachLimbMuscle(.forearms, kinds: fores, out: 0.0, y: 0.085, z: 0.026, radii: SIMD3(0.040, 0.100, 0.026))
        attachLimbMuscle(.forearms, kinds: fores, out: 0.010, y: 0.095, z: -0.024, radii: SIMD3(0.034, 0.090, 0.028))

        // Torso (local X is the body's left; mirrored)
        attachTorsoMuscle(.chest, kind: .upperTorso, x: 0.082, y: 0.186, z: 0.092, radii: SIMD3(0.088, 0.064, 0.030))
        attachTorsoMuscle(.lats, kind: .upperTorso, x: 0.118, y: 0.095, z: -0.068, radii: SIMD3(0.052, 0.130, 0.032))
        attachTorsoMuscle(.traps, kind: .upperTorso, x: 0.065, y: 0.258, z: -0.062, radii: SIMD3(0.082, 0.062, 0.030))
        attachTorsoMuscle(.upperBack, kind: .upperTorso, x: 0.050, y: 0.155, z: -0.088, radii: SIMD3(0.062, 0.075, 0.022))
        attachTorsoMuscle(.lowerBack, kind: .lowerTorso, x: 0.046, y: 0.150, z: -0.080, radii: SIMD3(0.042, 0.100, 0.022))
        for (i, y) in [Float(0.035), 0.095, 0.155, 0.215].enumerated() {
            let w: Float = i == 3 ? 0.028 : 0.031
            attachTorsoMuscle(.abs, kind: .lowerTorso, x: 0.0335, y: y, z: 0.090, radii: SIMD3(w, 0.031, 0.016))
        }
        attachTorsoMuscle(.obliques, kind: .lowerTorso, x: 0.118, y: 0.150, z: 0.010, radii: SIMD3(0.030, 0.090, 0.068))
        attachTorsoMuscle(.glutes, kind: .lowerTorso, x: 0.068, y: -0.030, z: -0.082, radii: SIMD3(0.066, 0.068, 0.040))
        attachTorsoMuscle(.hipFlexors, kind: .lowerTorso, x: 0.078, y: 0.0, z: 0.080, radii: SIMD3(0.036, 0.062, 0.028))
    }

    // MARK: Posing

    /// Moves every segment to the pose. Cheap: transforms only.
    func apply(_ pose: FigurePose) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }

        func p(_ j: GuideJoint) -> SIMD3<Float> { pose.position(j) }
        let pelvisFront = pose.pelvisRotation.act(SIMD3(0, 0, 1))
        let chestFront = pose.chestRotation.act(SIMD3(0, 0, 1))

        place(.lowerTorso, origin: p(.pelvis), orientation: GuideMath.basis(y: p(.spineMid) - p(.pelvis), zRef: pelvisFront))
        place(.upperTorso, origin: p(.spineMid), orientation: GuideMath.basis(y: p(.chest) - p(.spineMid), zRef: chestFront))
        let headFront = pose.headRotation.act(SIMD3(0, 0, 1))
        place(.neck, origin: p(.chest), orientation: GuideMath.basis(y: p(.head) - p(.chest), zRef: headFront))
        place(.head, origin: p(.head), orientation: pose.headRotation)

        for left in [true, false] {
            let hip: GuideJoint = left ? .leftHip : .rightHip
            let knee: GuideJoint = left ? .leftKnee : .rightKnee
            let ankle: GuideJoint = left ? .leftAnkle : .rightAnkle
            let toe: GuideJoint = left ? .leftToe : .rightToe
            let shoulder: GuideJoint = left ? .leftShoulder : .rightShoulder
            let elbow: GuideJoint = left ? .leftElbow : .rightElbow
            let wrist: GuideJoint = left ? .leftWrist : .rightWrist
            let hand: GuideJoint = left ? .leftHand : .rightHand
            let grip = left ? pose.leftGripAxis : pose.rightGripAxis

            // Legs: the knee points to the front of the thigh and the back of the shin's calf.
            let legFront = Self.limbFront(root: p(hip), mid: p(knee), end: p(ankle), bendSign: 1, fallback: pelvisFront)
            place(left ? .leftThigh : .rightThigh, origin: p(hip),
                  orientation: GuideMath.basis(y: p(knee) - p(hip), zRef: legFront))
            place(left ? .leftShin : .rightShin, origin: p(knee),
                  orientation: GuideMath.basis(y: p(ankle) - p(knee), zRef: legFront))

            // Foot: up-normal is the shin direction projected off the foot line, with a little world-up for stability.
            let footY = FigureSolver.safeNormalize(p(toe) - p(ankle), fallback: SIMD3(0, 0, 1))
            let shinUp = FigureSolver.safeNormalize(p(knee) - p(ankle))
            let up = SIMD3<Float>(0, 1, 0)
            let n = (shinUp - footY * simd_dot(shinUp, footY)) + 0.35 * (up - footY * simd_dot(up, footY))
            place(left ? .leftFoot : .rightFoot, origin: p(ankle), orientation: GuideMath.basis(y: footY, zRef: n))

            // Arms: the front of the upper arm is the side the forearm folds towards.
            let armFront = Self.limbFront(root: p(shoulder), mid: p(elbow), end: p(wrist), bendSign: -1, fallback: chestFront)
            place(left ? .leftUpperArm : .rightUpperArm, origin: p(shoulder),
                  orientation: GuideMath.basis(y: p(elbow) - p(shoulder), zRef: armFront))
            place(left ? .leftForearm : .rightForearm, origin: p(elbow),
                  orientation: GuideMath.basis(y: p(wrist) - p(elbow), zRef: armFront))
            place(left ? .leftHand : .rightHand, origin: p(wrist),
                  orientation: GuideMath.basis(y: p(hand) - p(wrist), xRef: grip))
        }
    }

    private func place(_ kind: SegmentKind, origin: SIMD3<Float>, orientation: simd_quatf) {
        guard let node = segmentNodes[kind] else { return }
        node.simdPosition = origin
        node.simdOrientation = orientation
    }

    /// Direction the "front" of a limb faces, from the way its middle joint sticks out of the root-end line.
    /// Falls back smoothly to `fallback` when the limb is nearly straight.
    static func limbFront(root: SIMD3<Float>, mid: SIMD3<Float>, end: SIMD3<Float>, bendSign: Float,
                          fallback: SIMD3<Float>) -> SIMD3<Float> {
        let axis = end - root
        let len = simd_length(axis)
        guard len > 1e-5 else { return fallback }
        let dir = axis / len
        let rel = mid - root
        let off = rel - dir * simd_dot(rel, dir)
        let mag = simd_length(off)
        let w = GuideMath.smoothstep(0.012, 0.05, mag)
        var fb = fallback - dir * simd_dot(fallback, dir)
        if simd_length(fb) < 1e-4 {
            let alt = SIMD3<Float>(0, 1, 0)
            fb = alt - dir * simd_dot(alt, dir)
        }
        fb = FigureSolver.safeNormalize(fb, fallback: SIMD3(0, 0, 1))
        guard mag > 1e-6 else { return fb }
        let v = (off / mag) * bendSign * w + fb * (1 - w)
        return FigureSolver.safeNormalize(v, fallback: fb)
    }

    // MARK: Test hooks

    /// World-space endpoints of a segment (its origin and the far end along its local Y).
    func endpoints(of kind: SegmentKind) -> (start: SIMD3<Float>, end: SIMD3<Float>)? {
        guard let seg = segments.first(where: { $0.kind == kind }) else { return nil }
        let start = seg.node.simdWorldPosition
        let end = seg.node.simdConvertPosition(SIMD3(0, seg.length, 0), to: nil)
        return (start, end)
    }

    var muscleShapeCounts: [MuscleGroup: Int] { muscleNodes.mapValues(\.count) }
}
