import SceneKit
import UIKit
import simd

// MARK: - Timeline

/// Playback maths: one rep with a short hold at the start and at the furthest position.
struct GuideTimeline: Equatable {
    var repDuration: Double
    var speed: Double = 1
    /// Progress of the furthest position (the second hold).
    var peak: Float = 0.5
    var hold: Double = 0.35

    var movingDuration: Double { max(repDuration, 0.1) / max(speed, 0.05) }
    var cycleDuration: Double { movingDuration + 2 * hold }

    /// Rep progress 0...1 at an elapsed time (loops).
    func progress(at elapsed: Double) -> Float {
        var t = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        if t < 0 { t += cycleDuration }
        if t < hold { return 0 }
        t -= hold
        let toPeak = Double(peak) * movingDuration
        if t < toPeak { return Float(t / movingDuration) }
        t -= toPeak
        if t < hold { return peak }
        t -= hold
        return min(peak + Float(t / movingDuration), 1)
    }

    /// Elapsed time (within one cycle) that shows `progress`; the inverse of `progress(at:)`.
    func time(forProgress p: Float) -> Double {
        let p = min(max(p, 0), 1)
        if p <= 0 { return 0 }
        if p <= peak { return hold + Double(p) * movingDuration }
        return hold + Double(peak) * movingDuration + hold + Double(p - peak) * movingDuration
    }
}

// MARK: - Camera framing

enum CameraFraming {
    struct Result {
        var position: SIMD3<Float>
        var target: SIMD3<Float>
        var distance: Float
    }

    static let fieldOfView: Float = 35
    static let elevationDegrees: Float = 11

    /// Direction from the target towards the camera (unit).
    static func direction(for preset: GuideCameraPreset, elevationDegrees: Float = elevationDegrees) -> SIMD3<Float> {
        let az: Float
        switch preset {
        case .front: az = 0
        case .side: az = -90
        case .threeQuarter: az = -42
        case .back: az = 180
        }
        let a = az * .pi / 180, e = elevationDegrees * .pi / 180
        return SIMD3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
    }

    /// Points covering the figure (with body thickness) and props over sampled frames of the motion.
    static func samplePoints(of motion: ExerciseGuideMotion, samples: Int = 24) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        func add(_ p: SIMD3<Float>, pad: Float) {
            out.append(p)
            guard pad > 0 else { return }
            for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
                out.append(p + axis * pad); out.append(p - axis * pad)
            }
        }
        // Tall equipment (cable towers, racks) must not shrink the figure: prop points are capped just above the figure.
        var figureTop: Float = 0
        let frames = (0...samples).map { motion.frame(at: Float($0) / Float(samples)) }
        for frame in frames { for j in GuideJoint.allCases { figureTop = max(figureTop, frame.pose.position(j).y + 0.12) } }
        let cap = figureTop + 0.25
        for frame in frames {
            for joint in GuideJoint.allCases { add(frame.pose.position(joint), pad: joint == .head ? 0.13 : 0.07) }
            for prop in frame.props { addPoints(of: prop) { p, pad in add(SIMD3(p.x, min(p.y, cap), p.z), pad: pad) } }
        }
        add(SIMD3(0, 0, 0), pad: 0.05)
        return out
    }

    private static func addPoints(of prop: GuideProp, _ add: (SIMD3<Float>, Float) -> Void) {
        switch prop {
        case let .barbell(center, axis, length, plate):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            add(center + a * (length / 2), max(plate, 0.03))
            add(center - a * (length / 2), max(plate, 0.03))
        case let .ezBar(center, axis):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            add(center + a * 0.5, 0.1)
            add(center - a * 0.5, 0.1)
        case let .dumbbell(center, _): add(center, 0.15)
        case let .kettlebell(center): add(center, 0.2)
        case let .cable(from, to): add(from, 0.02); add(to, 0.02)
        case let .handle(center, axis, length):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            add(center + a * (length / 2), 0.03); add(center - a * (length / 2), 0.03)
        case let .box(center, size, rotation, _):
            for sx: Float in [-0.5, 0.5] { for sy: Float in [-0.5, 0.5] { for sz: Float in [-0.5, 0.5] {
                add(center + rotation.act(SIMD3(size.x * sx, size.y * sy, size.z * sz)), 0)
            } } }
        case let .cylinder(from, to, radius, _): add(from, radius); add(to, radius)
        case let .mat(center, size):
            add(center + SIMD3(size.x / 2, 0, size.y / 2), 0); add(center - SIMD3(size.x / 2, 0, size.y / 2), 0)
        }
    }

    /// Camera that frames the whole bounding box from `preset`, looking near `focusHeight`.
    static func frame(points: [SIMD3<Float>], preset: GuideCameraPreset, focusHeight: Float,
                      aspect: Float, fieldOfViewDegrees: Float = fieldOfView, margin: Float = 1.08) -> Result {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        if points.isEmpty { lo = .zero; hi = SIMD3(0, 1.8, 0) }
        let centre = (lo + hi) / 2
        let height = hi.y - lo.y
        let focusY = min(max(focusHeight, centre.y - 0.15 * height), centre.y + 0.15 * height)
        let target = SIMD3(centre.x, focusY, centre.z)
        let toCamera = direction(for: preset)
        let forward = -toCamera
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let ky = tan(fieldOfViewDegrees * .pi / 360)
        let kx = ky * max(aspect, 0.2)
        var distance: Float = 1.2
        for p in points {
            let d = p - target
            let depth = simd_dot(d, forward)
            let needX = abs(simd_dot(d, right)) * margin / kx - depth
            let needY = abs(simd_dot(d, up)) * margin / ky - depth
            distance = max(distance, needX, needY)
        }
        return Result(position: target + toCamera * distance, target: target, distance: distance)
    }
}

// MARK: - Scene appearance

struct GuideSceneAppearance: Equatable {
    var isDark: Bool

    var background: UIColor {
        let trait = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        return UIColor(AppTheme.background).resolvedColor(with: trait)
    }
}

// MARK: - Controller

/// Owns the SceneKit scene (floor, lights, camera, mannequin, props) and the playback state.
final class GuideSceneController: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let mannequin: MannequinNode
    let propRenderer = GuidePropRenderer()

    /// Called with the rep progress whenever playback advances (main queue).
    var onProgress: ((Float) -> Void)?
    /// Hook the SwiftUI view uses to switch continuous rendering on and off.
    weak var attachedView: SCNView? { didSet { syncView() } }

    private(set) var motion: ExerciseGuideMotion?
    private(set) var timeline = GuideTimeline(repDuration: 4)
    private(set) var progress: Float = 0
    private(set) var cameraPreset: GuideCameraPreset = .side
    private(set) var cameraTarget = SIMD3<Float>(0, 0.9, 0)
    private(set) var appearance: GuideSceneAppearance
    private(set) var viewAspect: Float = 1

    private var cycleTime: Double = 0
    private var lastRenderTime: TimeInterval?
    private var samplePoints: [SIMD3<Float>] = []
    private var floorNode = SCNNode()
    private var shadowFloorNode = SCNNode()

    var isPlaying: Bool {
        didSet { if oldValue != isPlaying { lastRenderTime = nil; syncView() } }
    }

    /// 1 or 0.5.
    var speed: Double = 1 {
        didSet {
            guard oldValue != speed else { return }
            let p = progress
            timeline.speed = speed
            cycleTime = timeline.time(forProgress: p)
        }
    }

    /// Distance limits for pinch zoom, set from the framing.
    private(set) var minDistance: Float = 1.2
    private(set) var maxDistance: Float = 9

    init(appearance: GuideSceneAppearance = GuideSceneAppearance(isDark: true), startsPlaying: Bool = true) {
        self.appearance = appearance
        self.mannequin = MannequinNode(palette: .make(dark: appearance.isDark))
        self.isPlaying = startsPlaying
        super.init()
        buildScene()
    }

    // MARK: Scene

    private func buildScene() {
        scene.rootNode.addChildNode(mannequin)
        scene.rootNode.addChildNode(propRenderer.rootNode)
        scene.background.contents = appearance.background
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 0.55

        floorNode = SCNNode()
        let plane = SCNPlane(width: 14, height: 14)
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .constant
        floorMat.diffuse.contents = Self.floorTexture(background: appearance.background, dark: appearance.isDark)
        floorMat.diffuse.mipFilter = .linear
        floorMat.isDoubleSided = false
        floorMat.writesToDepthBuffer = true
        plane.materials = [floorMat]
        floorNode.geometry = plane
        floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floorNode.position = SCNVector3(0, -0.0005, 0)
        floorNode.name = "floor"
        scene.rootNode.addChildNode(floorNode)

        let shadowPlane = SCNPlane(width: 14, height: 14)
        let shadowMat = SCNMaterial()
        shadowMat.lightingModel = .shadowOnly
        shadowMat.writesToDepthBuffer = false
        shadowPlane.materials = [shadowMat]
        shadowFloorNode.geometry = shadowPlane
        shadowFloorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadowFloorNode.position = SCNVector3(0, 0.0004, 0)
        shadowFloorNode.name = "floorShadow"
        scene.rootNode.addChildNode(shadowFloorNode)

        addLights()

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(CameraFraming.fieldOfView)
        camera.projectionDirection = .vertical
        camera.zNear = 0.1
        camera.zFar = 60
        camera.wantsHDR = false
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.simdPosition = SIMD3(-3, 1.4, 2)
        cameraNode.simdLook(at: SIMD3(0, 0.9, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    }

    private func addLights() {
        func node(_ light: SCNLight, from: SIMD3<Float>, to: SIMD3<Float> = SIMD3(0, 0.8, 0), name: String) -> SCNNode {
            let n = SCNNode()
            n.light = light
            n.name = name
            n.simdPosition = from
            n.simdLook(at: to, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            return n
        }
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1000
        key.temperature = 6200
        key.castsShadow = true
        key.shadowRadius = 9
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.shadowBias = 0.002
        key.automaticallyAdjustsShadowProjection = true
        key.maximumShadowDistance = 14
        scene.rootNode.addChildNode(node(key, from: SIMD3(-1.6, 4.2, 3.0), name: "key"))

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.temperature = 8200
        scene.rootNode.addChildNode(node(fill, from: SIMD3(3.0, 1.8, 2.2), name: "fill"))

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 700
        rim.temperature = 7400
        scene.rootNode.addChildNode(node(rim, from: SIMD3(1.4, 3.0, -3.2), name: "rim"))

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 90
        ambient.temperature = 6800
        let amb = SCNNode()
        amb.light = ambient
        amb.name = "ambient"
        scene.rootNode.addChildNode(amb)
    }

    /// Procedural studio environment (equirectangular): soft sky, darker floor, a few softbox highlights.
    static func environmentImage() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.62, alpha: 1).cgColor,
                          UIColor(white: 0.30, alpha: 1).cgColor, UIColor(white: 0.16, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.47, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(white: 1, alpha: 0.9).setFill()
            for rect in [CGRect(x: 60, y: 40, width: 90, height: 50), CGRect(x: 300, y: 30, width: 120, height: 40),
                         CGRect(x: 190, y: 90, width: 40, height: 30)] {
                cg.fill(rect)
            }
        }
    }

    /// Floor: soft radial falloff into the background with a faint grid so depth reads.
    static func floorTexture(background: UIColor, dark: Bool) -> UIImage {
        let side: CGFloat = 1024
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let centre = CGPoint(x: side / 2, y: side / 2)
        let lighten: CGFloat = dark ? 0.085 : -0.045
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        background.getRed(&r, green: &g, blue: &b, alpha: &a)
        let inner = UIColor(red: min(max(r + lighten, 0), 1), green: min(max(g + lighten, 0), 1),
                            blue: min(max(b + lighten * 1.1, 0), 1), alpha: 1)
        let line = dark ? UIColor(white: 1, alpha: 0.07) : UIColor(white: 0, alpha: 0.07)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            background.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            // Grid every 0.5 m (14 m plane over 1024 px).
            let step = side / 28
            cg.setLineWidth(1.4)
            line.setStroke()
            var x: CGFloat = 0
            while x <= side {
                cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: side))
                cg.move(to: CGPoint(x: 0, y: x)); cg.addLine(to: CGPoint(x: side, y: x))
                x += step
            }
            cg.strokePath()
            // Radial fade: floor tint in the middle, the background colour at the edge (hides the grid too).
            let colors = [inner.withAlphaComponent(0.0).cgColor, inner.withAlphaComponent(0.55).cgColor,
                          background.withAlphaComponent(0.0).cgColor, background.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0, 0.18, 0.45, 0.72]) {
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: side / 2, options: [])
            }
        }
    }

    func setAppearance(_ new: GuideSceneAppearance) {
        guard new != appearance else { return }
        appearance = new
        scene.background.contents = new.background
        floorNode.geometry?.firstMaterial?.diffuse.contents = Self.floorTexture(background: new.background, dark: new.isDark)
        mannequin.setPalette(.make(dark: new.isDark))
    }

    // MARK: Motion

    func load(motion: ExerciseGuideMotion, animatedHighlight: Bool = true) {
        self.motion = motion
        samplePoints = CameraFraming.samplePoints(of: motion)
        timeline = GuideTimeline(repDuration: motion.repDuration, speed: speed, peak: Self.peakProgress(of: motion))
        mannequin.setHighlight(primary: Set(motion.primaryMuscles), secondary: Set(motion.secondaryMuscles), animated: animatedHighlight)
        cycleTime = 0
        lastRenderTime = nil
        propRenderer.clear()
        setCamera(motion.defaultCamera, animated: false)
        applyProgress(0, notify: true)
    }

    /// Progress at which the figure is furthest from its starting pose.
    static func peakProgress(of motion: ExerciseGuideMotion) -> Float {
        let start = motion.frame(at: 0).pose
        var best: (p: Float, d: Float) = (0.5, -1)
        for i in 1..<40 {
            let p = Float(i) / 40
            let pose = motion.frame(at: p).pose
            var d: Float = 0
            for j in GuideJoint.allCases { d += simd_length(pose.position(j) - start.position(j)) }
            if d > best.d + 1e-4 { best = (p, d) }
        }
        return best.d > 0.05 ? best.p : 0.5
    }

    func setHighlight(primary: Set<MuscleGroup>, secondary: Set<MuscleGroup>) {
        mannequin.setHighlight(primary: primary, secondary: secondary)
    }

    /// Scrub: shows `p` and keeps playback aligned with it.
    func setProgress(_ p: Float) {
        let clamped = min(max(p, 0), 1)
        cycleTime = timeline.time(forProgress: clamped)
        applyProgress(clamped, notify: true)
    }

    /// Advances playback by `dt` seconds (when playing). Exposed for tests.
    func advance(by dt: TimeInterval) {
        guard isPlaying, motion != nil else { return }
        cycleTime = (cycleTime + dt).truncatingRemainder(dividingBy: timeline.cycleDuration)
        applyProgress(timeline.progress(at: cycleTime), notify: true)
    }

    private func applyProgress(_ p: Float, notify: Bool) {
        progress = p
        guard let motion else { return }
        let frame = motion.frame(at: p)
        mannequin.apply(frame.pose)
        propRenderer.update(frame.props)
        if notify, let onProgress {
            DispatchQueue.main.async { onProgress(p) }
        }
    }

    // MARK: Camera

    func updateAspect(_ aspect: Float) {
        guard aspect.isFinite, aspect > 0.1, abs(aspect - viewAspect) > 0.01 else { return }
        viewAspect = aspect
        if motion != nil { setCamera(cameraPreset, animated: false) }
    }

    func setCamera(_ preset: GuideCameraPreset, animated: Bool) {
        cameraPreset = preset
        let focus = motion?.focusHeight ?? 0.9
        let framing = CameraFraming.frame(points: samplePoints, preset: preset, focusHeight: focus, aspect: viewAspect)
        cameraTarget = framing.target
        minDistance = max(framing.distance * 0.45, 0.9)
        maxDistance = framing.distance * 2.2
        let orientation = Self.lookOrientation(from: framing.position, to: framing.target)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraNode.simdPosition = framing.position
            cameraNode.simdOrientation = orientation
            SCNTransaction.commit()
        } else {
            cameraNode.simdPosition = framing.position
            cameraNode.simdOrientation = orientation
        }
        if let view = attachedView {
            view.defaultCameraController.target = SCNVector3(framing.target.x, framing.target.y, framing.target.z)
        }
    }

    static func lookOrientation(from position: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        // Camera looks down local -Z.
        return simd_quatf(simd_float3x3(columns: (right, up, -forward)))
    }

    // MARK: View sync

    private func syncView() {
        guard let view = attachedView else { return }
        let playing = isPlaying
        DispatchQueue.main.async {
            view.rendersContinuously = playing
            view.isPlaying = playing
        }
    }

    // MARK: SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastRenderTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastRenderTime = time
        if isPlaying, dt > 0 { advance(by: dt) }
        clampCameraDistance()
    }

    /// Keeps pinch zoom within sensible limits and the camera above the floor.
    private func clampCameraDistance() {
        let target = cameraTarget
        let pos = cameraNode.simdWorldPosition
        let offset = pos - target
        let dist = simd_length(offset)
        guard dist > 1e-4 else { return }
        var clamped = min(max(dist, minDistance), maxDistance)
        var newPos = target + offset / dist * clamped
        if newPos.y < 0.12 {
            newPos.y = 0.12
            clamped = simd_length(newPos - target)
        }
        if abs(clamped - dist) > 1e-3 || newPos.y != pos.y {
            cameraNode.simdWorldPosition = newPos
            cameraNode.simdOrientation = Self.lookOrientation(from: newPos, to: target)
        }
    }
}
