import SceneKit
import UIKit
import simd

/// Palette used by the mannequin and the scene. Kept in one place so tests and the scene controller agree.
struct MannequinPalette {
    var body: UIColor
    var muscle: UIColor
    var primary: UIColor
    var secondary: UIColor
    var accentEdge: UIColor

    static func make(dark: Bool) -> MannequinPalette {
        let trait = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let accent = UIColor(AppTheme.accent).resolvedColor(with: trait)
        // Warm neutral "clay": light enough to read on the dark stage, mid enough to hold shape on the light stage.
        let body = dark ? UIColor(red: 0.80, green: 0.78, blue: 0.76, alpha: 1) : UIColor(red: 0.67, green: 0.65, blue: 0.63, alpha: 1)
        let muscle = mix(body, .black, dark ? 0.10 : 0.14)
        let primary = dark ? mix(accent, .white, 0.0) : mix(accent, UIColor(red: 0.10, green: 0.75, blue: 0.25, alpha: 1), 0.45)
        let secondary = dark ? mix(accent, UIColor(red: 0.92, green: 0.93, blue: 0.90, alpha: 1), 0.58)
                             : mix(accent, UIColor(red: 0.90, green: 0.93, blue: 0.88, alpha: 1), 0.55)
        return MannequinPalette(body: body, muscle: muscle, primary: primary, secondary: secondary, accentEdge: accent)
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
/// Muscles are lofted relief patches laid exactly on the body surface (tone-on-tone until highlighted).
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
    private var surfaces: [SegmentKind: (Float) -> LoftRing] = [:]
    private var muscleMaterials: [MuscleGroup: SCNMaterial] = [:]
    private var muscleNodes: [MuscleGroup: [SCNNode]] = [:]
    private let bodyMaterial = SCNMaterial()
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
        bodyMaterial.roughness.contents = 0.62
        bodyMaterial.metalness.contents = 0.0
        for group in MuscleGroup.allCases {
            let m = Self.pbr(palette.muscle, roughness: 0.6)
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
                m.emission.contents = MannequinPalette.mix(palette.primary, .black, 0.72)
                m.roughness.contents = 0.42
            } else if secondaryHighlight.contains(group) {
                m.diffuse.contents = palette.secondary
                m.emission.contents = MannequinPalette.mix(palette.secondary, .black, 0.85)
                m.roughness.contents = 0.5
            } else {
                m.diffuse.contents = palette.muscle
                m.emission.contents = UIColor.black
                m.roughness.contents = 0.6
            }
        }
        SCNTransaction.commit()
    }

    // MARK: Construction

    private func addSegment(_ kind: SegmentKind, from: GuideJoint, to: GuideJoint, length: Float,
                            geometry: SCNGeometry, surface: ((Float) -> LoftRing)? = nil) {
        geometry.materials = [bodyMaterial]
        let node = SCNNode(geometry: geometry)
        node.name = kind.rawValue
        addChildNode(node)
        segments.append(Segment(kind: kind, node: node, from: from, to: to, length: length))
        segmentNodes[kind] = node
        if let surface { surfaces[kind] = surface }
    }

    /// Lays a muscle patch on a segment. Angles: 0 = front, 90 = body left (+X) for the torso, 180 = back.
    private func patch(_ group: MuscleGroup, _ kind: SegmentKind, a: Float, half: Float, y0: Float, y1: Float,
                       h: Float, taper: (Float, Float) = (1, 1)) {
        guard let node = segmentNodes[kind], let surface = surfaces[kind], let material = muscleMaterials[group] else { return }
        let geo = LoftBuilder.patch(surface: surface, aCenter: a, aHalf: half, y0: y0, y1: y1, height: h,
                                    widthScale: (taper.0, taper.1))
        geo.materials = [material]
        let n = SCNNode(geometry: geo)
        n.name = "m.\(group.rawValue)"
        node.addChildNode(n)
        muscleNodes[group, default: []].append(n)
    }

    /// Torso patch on both sides (angle `a` is for the body's left; the right side mirrors it).
    private func torsoPatch(_ group: MuscleGroup, _ kind: SegmentKind, a: Float, half: Float, y0: Float, y1: Float,
                            h: Float, taper: (Float, Float) = (1, 1)) {
        patch(group, kind, a: a, half: half, y0: y0, y1: y1, h: h, taper: taper)
        patch(group, kind, a: -a, half: half, y0: y0, y1: y1, h: h, taper: taper)
    }

    /// Limb patch on both limbs. Angles are given for the right limb (90 = outer side); the left limb mirrors them,
    /// because limb frames point down, so local +X is outwards on the right and inwards on the left.
    private func limbPatch(_ group: MuscleGroup, _ kinds: (left: SegmentKind, right: SegmentKind), a: Float, half: Float,
                           y0: Float, y1: Float, h: Float, taper: (Float, Float) = (1, 1)) {
        patch(group, kinds.right, a: a, half: half, y0: y0, y1: y1, h: h, taper: taper)
        patch(group, kinds.left, a: -a, half: half, y0: y0, y1: y1, h: h, taper: taper)
    }

    private func build() {
        typealias P = FigureProportions
        typealias L = LoftBuilder

        func torso(_ keys: [(y: Float, rx: Float, rz: Float, cz: Float)], rings: Int) -> (SCNGeometry, (Float) -> LoftRing) {
            let surface = L.keyedSurface(keys)
            let yMin = keys.first?.y ?? 0, yMax = keys.last?.y ?? 1
            var out: [LoftRing] = []
            for i in 0...rings { out.append(surface(yMin + (yMax - yMin) * Float(i) / Float(rings))) }
            return (L.geometry(rings: out, segments: 40), surface)
        }
        // Torso in two overlapping pieces so the spine can bend. Wide shoulders and lats, clear waist, deep chest.
        let lower = torso([(-0.118, 0.012, 0.012, 0), (-0.108, 0.05, 0.04, 0), (-0.09, 0.104, 0.074, -0.004),
                           (-0.05, 0.150, 0.098, -0.010), (0.0, 0.164, 0.106, -0.012), (0.07, 0.150, 0.102, -0.006),
                           (0.16, 0.128, 0.094, 0.0), (0.22, 0.126, 0.092, 0.004), (0.255, 0.130, 0.092, 0.006),
                           (0.285, 0.07, 0.05, 0.006)], rings: 24)
        addSegment(.lowerTorso, from: .pelvis, to: .spineMid, length: P.spineLower, geometry: lower.0, surface: lower.1)
        let upper = torso([(-0.03, 0.095, 0.07, 0.0), (0.0, 0.130, 0.090, 0.004), (0.07, 0.160, 0.102, 0.008),
                           (0.14, 0.184, 0.112, 0.014), (0.20, 0.190, 0.118, 0.016), (0.245, 0.178, 0.106, 0.008),
                           (0.275, 0.140, 0.086, -0.004), (0.30, 0.088, 0.068, -0.010),
                           (0.322, 0.054, 0.056, -0.008), (0.333, 0.020, 0.020, -0.008)], rings: 28)
        addSegment(.upperTorso, from: .spineMid, to: .chest, length: P.spineUpper, geometry: upper.0, surface: upper.1)

        addSegment(.neck, from: .chest, to: .head, length: 0.20,
            geometry: L.limb(length: 0.20, profile: [(0, 0.058, 0.060, -0.004), (0.5, 0.050, 0.052, 0.0), (1, 0.048, 0.050, 0.006)],
                             startCap: 0, endCap: 0, bodyRings: 6))

        let headKeys: [(y: Float, rx: Float, rz: Float, cz: Float)] = [
            (-0.118, 0.012, 0.012, 0.03), (-0.108, 0.034, 0.040, 0.03), (-0.09, 0.052, 0.066, 0.026), (-0.05, 0.068, 0.084, 0.012),
            (0, 0.076, 0.095, 0), (0.05, 0.076, 0.094, -0.002), (0.09, 0.066, 0.082, -0.004), (0.113, 0.042, 0.052, -0.006),
            (0.125, 0.012, 0.014, -0.006)]
        let headSurface = L.keyedSurface(headKeys)
        var headRings: [LoftRing] = []
        for i in 0...26 { headRings.append(headSurface(-0.118 + 0.243 * Float(i) / 26)) }
        addSegment(.head, from: .head, to: .head, length: 0, geometry: L.geometry(rings: headRings, segments: 36), surface: headSurface)
        if let head = segmentNodes[.head] {
            // Neutral face: a soft brow ridge and a nose make the facing direction readable.
            func feature(_ name: String, _ rx: Float, _ ry: Float, _ rz: Float, at p: SIMD3<Float>, pitch: Float = 0) {
                let n = SCNNode(geometry: L.ellipsoid(rx: rx, ry: ry, rz: rz, rings: 10, segments: 20))
                n.geometry?.materials = [bodyMaterial]
                n.simdPosition = p
                n.simdEulerAngles = SIMD3(pitch, 0, 0)
                n.name = name
                head.addChildNode(n)
            }
            feature("brow", 0.058, 0.011, 0.020, at: SIMD3(0, 0.030, 0.074), pitch: -0.1)
            feature("nose", 0.011, 0.024, 0.017, at: SIMD3(0, -0.012, 0.092), pitch: -0.30)
            feature("chin", 0.026, 0.016, 0.020, at: SIMD3(0, -0.085, 0.060), pitch: 0.2)
            feature("earL", 0.008, 0.024, 0.016, at: SIMD3(0.075, -0.010, -0.004))
            feature("earR", 0.008, 0.024, 0.016, at: SIMD3(-0.075, -0.010, -0.004))
        }

        for prefix in ["left", "right"] {
            let l = prefix == "left"
            let thighKind: SegmentKind = l ? .leftThigh : .rightThigh
            let shinKind: SegmentKind = l ? .leftShin : .rightShin
            let footKind: SegmentKind = l ? .leftFoot : .rightFoot
            let upperKind: SegmentKind = l ? .leftUpperArm : .rightUpperArm
            let foreKind: SegmentKind = l ? .leftForearm : .rightForearm
            let handKind: SegmentKind = l ? .leftHand : .rightHand
            let hip: GuideJoint = l ? .leftHip : .rightHip
            let knee: GuideJoint = l ? .leftKnee : .rightKnee
            let ankle: GuideJoint = l ? .leftAnkle : .rightAnkle
            let toe: GuideJoint = l ? .leftToe : .rightToe
            let shoulder: GuideJoint = l ? .leftShoulder : .rightShoulder
            let elbow: GuideJoint = l ? .leftElbow : .rightElbow
            let wrist: GuideJoint = l ? .leftWrist : .rightWrist
            let hand: GuideJoint = l ? .leftHand : .rightHand

            func limb(_ kind: SegmentKind, _ from: GuideJoint, _ to: GuideJoint, _ length: Float,
                      _ profile: [(t: Float, rx: Float, rz: Float, cz: Float)], _ startCap: Float, _ endCap: Float) {
                addSegment(kind, from: from, to: to, length: length,
                           geometry: L.limb(length: length, profile: profile, startCap: startCap, endCap: endCap, bodyRings: 16),
                           surface: L.limbSurface(length: length, profile: profile, startCap: startCap, endCap: endCap))
            }
            limb(thighKind, hip, knee, P.thigh, [(0, 0.086, 0.090, 0), (0.18, 0.086, 0.091, 0.004), (0.5, 0.072, 0.077, 0.004),
                                                 (0.8, 0.058, 0.062, 0.002), (1, 0.052, 0.054, 0)], 0.086, 0.052)
            limb(shinKind, knee, ankle, P.shin, [(0, 0.052, 0.054, 0), (0.12, 0.054, 0.058, -0.002), (0.30, 0.052, 0.064, -0.012),
                                                 (0.55, 0.042, 0.048, -0.006), (1, 0.031, 0.033, 0)], 0.052, 0.033)
            addSegment(footKind, from: ankle, to: toe, length: P.foot, geometry: Self.footGeometry())
            limb(upperKind, shoulder, elbow, P.upperArm, [(0, 0.062, 0.064, 0), (0.30, 0.058, 0.062, 0), (0.62, 0.049, 0.053, 0),
                                                          (1, 0.041, 0.042, 0)], 0.064, 0.041)
            limb(foreKind, elbow, wrist, P.forearm, [(0, 0.041, 0.042, 0), (0.22, 0.048, 0.050, 0), (0.6, 0.038, 0.038, 0),
                                                     (1, 0.028, 0.026, 0)], 0.041, 0.028)
            // Hand: a mitten that wraps the grip axis (local X = grip axis, local Y = wrist to grip centre).
            let handGeo = L.limb(length: P.hand + 0.015,
                                 profile: [(0, 0.030, 0.023, 0), (0.35, 0.042, 0.029, 0), (0.75, 0.049, 0.034, 0), (1, 0.046, 0.033, 0)],
                                 startCap: 0.024, endCap: 0.031, bodyRings: 8, capRings: 5, segments: 24)
            addSegment(handKind, from: wrist, to: hand, length: P.hand, geometry: handGeo)
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
        let upper = SegmentKind.upperTorso, lower = SegmentKind.lowerTorso

        // Legs (right-limb angles: 0 front, 90 outer, 180 back, -90 inner)
        limbPatch(.quads, thighs, a: 10, half: 62, y0: 0.05, y1: 0.40, h: 0.014, taper: (0.75, 1))
        limbPatch(.hamstrings, thighs, a: 180, half: 62, y0: 0.06, y1: 0.40, h: 0.012, taper: (0.85, 1))
        limbPatch(.adductors, thighs, a: -88, half: 30, y0: 0.04, y1: 0.33, h: 0.010, taper: (1, 0.6))
        limbPatch(.calves, shins, a: 180, half: 60, y0: 0.04, y1: 0.32, h: 0.014, taper: (1, 0.8))

        // Arms
        limbPatch(.frontDelts, arms, a: -5, half: 38, y0: -0.035, y1: 0.15, h: 0.012, taper: (0.7, 1))
        limbPatch(.sideDelts, arms, a: 86, half: 38, y0: -0.035, y1: 0.15, h: 0.012, taper: (0.7, 1))
        limbPatch(.rearDelts, arms, a: 178, half: 38, y0: -0.035, y1: 0.15, h: 0.012, taper: (0.7, 1))
        limbPatch(.biceps, arms, a: -5, half: 40, y0: 0.09, y1: 0.26, h: 0.011, taper: (0.9, 0.75))
        limbPatch(.triceps, arms, a: 175, half: 62, y0: 0.07, y1: 0.27, h: 0.011, taper: (1, 0.8))
        limbPatch(.forearms, fores, a: 0, half: 62, y0: 0.02, y1: 0.20, h: 0.008, taper: (1, 0.7))
        limbPatch(.forearms, fores, a: 180, half: 62, y0: 0.02, y1: 0.20, h: 0.008, taper: (1, 0.7))

        // Torso (angles for the body's left; mirrored)
        torsoPatch(.chest, upper, a: 41, half: 40, y0: 0.115, y1: 0.235, h: 0.016, taper: (0.85, 1))
        torsoPatch(.lats, upper, a: 128, half: 30, y0: -0.02, y1: 0.20, h: 0.014, taper: (0.5, 1))
        torsoPatch(.lats, lower, a: 130, half: 24, y0: 0.17, y1: 0.265, h: 0.010, taper: (0.8, 0.5))
        torsoPatch(.traps, upper, a: 143, half: 38, y0: 0.19, y1: 0.325, h: 0.014, taper: (1, 0.55))
        torsoPatch(.upperBack, upper, a: 163, half: 18, y0: 0.04, y1: 0.19, h: 0.012)
        torsoPatch(.lowerBack, lower, a: 166, half: 14, y0: 0.04, y1: 0.25, h: 0.011)
        for (y0, y1) in [(Float(0.03), Float(0.085)), (0.09, 0.145), (0.15, 0.205), (0.21, 0.258)] {
            torsoPatch(.abs, lower, a: 9, half: 8.5, y0: y0, y1: y1, h: 0.009)
        }
        torsoPatch(.obliques, lower, a: 56, half: 24, y0: 0.05, y1: 0.255, h: 0.010, taper: (0.8, 1))
        torsoPatch(.glutes, lower, a: 142, half: 38, y0: -0.105, y1: 0.03, h: 0.018, taper: (0.8, 1))
        torsoPatch(.hipFlexors, lower, a: 36, half: 18, y0: -0.07, y1: 0.03, h: 0.009)
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
