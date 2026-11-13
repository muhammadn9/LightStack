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
    /// Typical width / height of the 3D view inside the stage (contact sheets and tests use it).
    static let stageAspect: Float = 1.6
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

    /// Points that drive the framing over sampled frames: the figure's joints (with body thickness), held equipment
    /// (bars, dumbbells, handles) and the support the body touches (pads, seats, platforms, mats).
    /// Racks, cable towers, machine frames and weight stacks are left out so they never shrink the figure (they may be cropped).
    static func samplePoints(of motion: ExerciseGuideMotion, samples: Int = 24) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        func add(_ p: SIMD3<Float>, pad: Float) {
            out.append(p)
            guard pad > 0 else { return }
            for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
                out.append(p + axis * pad); out.append(p - axis * pad)
            }
        }
        let frames = (0...samples).map { motion.frame(at: Float($0) / Float(samples)) }
        for frame in frames {
            for joint in GuideJoint.allCases {
                let pad: Float
                switch joint {
                case .head: pad = 0.12
                case .leftToe, .rightToe, .leftAnkle, .rightAnkle: pad = 0.05
                case .pelvis, .spineMid, .chest: pad = 0.13
                default: pad = 0.07
                }
                add(frame.pose.position(joint), pad: pad)
            }
            for prop in frame.props { addPoints(of: prop, add) }
        }
        add(SIMD3(0, 0, 0), pad: 0.05)
        return out
    }

    private static func addPoints(of prop: GuideProp, _ add: (SIMD3<Float>, Float) -> Void) {
        switch prop {
        case let .barbell(center, axis, length, plate):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            let half = min(length / 2, 0.85)
            add(center + a * half, max(plate, 0.03))
            add(center - a * half, max(plate, 0.03))
        case let .ezBar(center, axis):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            add(center + a * 0.4, 0.06)
            add(center - a * 0.4, 0.06)
        case let .dumbbell(center, _): add(center, 0.1)
        case let .kettlebell(center): add(center, 0.14)
        case .cable: break
        case let .handle(center, axis, length):
            let a = FigureSolver.safeNormalize(axis, fallback: SIMD3(1, 0, 0))
            add(center + a * (length / 2), 0.03); add(center - a * (length / 2), 0.03)
        case let .box(center, size, rotation, kind):
            guard kind == .pad || kind == .platform else { return }
            for sx: Float in [-0.5, 0.5] { for sy: Float in [-0.5, 0.5] { for sz: Float in [-0.5, 0.5] {
                add(center + rotation.act(SIMD3(size.x * sx, size.y * sy, size.z * sz)), 0)
            } } }
        case let .cylinder(from, to, radius, kind):
            guard kind == .pad || kind == .platform else { return }
            add(from, radius); add(to, radius)
        case let .mat(center, size):
            add(center + SIMD3(size.x / 2, 0, size.y / 2), 0); add(center - SIMD3(size.x / 2, 0, size.y / 2), 0)
        }
    }

    /// Fraction (0...1+) of the view's limiting dimension that `points` occupy when seen through `result`.
    static func fillFraction(points: [SIMD3<Float>], result: Result, aspect: Float,
                             fieldOfViewDegrees: Float = fieldOfView) -> Float {
        let forward = simd_normalize(result.target - result.position)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let ky = tan(fieldOfViewDegrees * .pi / 360), kx = ky * aspect
        var lx: Float = .greatestFiniteMagnitude, hx: Float = -.greatestFiniteMagnitude
        var ly = lx, hy = hx
        for p in points {
            let d = p - result.position
            let z = max(simd_dot(d, forward), 0.05)
            let nx = simd_dot(d, right) / z / kx, ny = simd_dot(d, up) / z / ky
            lx = min(lx, nx); hx = max(hx, nx); ly = min(ly, ny); hy = max(hy, ny)
        }
        return max(hx - lx, hy - ly) / 2
    }

    /// Fraction of the view the framed content should fill along its limiting dimension.
    static let targetFill: Float = 0.85

    /// Camera that frames all `points` from `preset` so they fill about `targetFill` of the limiting dimension, centred.
    static func frame(points: [SIMD3<Float>], preset: GuideCameraPreset, focusHeight: Float,
                      aspect: Float, fieldOfViewDegrees: Float = fieldOfView, margin: Float = 1 / targetFill) -> Result {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        if points.isEmpty { lo = .zero; hi = SIMD3(0, 1.8, 0) }
        var target = (lo + hi) / 2
        let toCamera = direction(for: preset)
        let forward = -toCamera
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let ky = tan(fieldOfViewDegrees * .pi / 360)
        let kx = ky * max(aspect, 0.2)
        var distance: Float = 1.2
        for _ in 0..<4 {
            distance = 1.2
            for p in points {
                let d = p - target
                let depth = simd_dot(d, forward)
                let needX = abs(simd_dot(d, right)) * margin / kx - depth
                let needY = abs(simd_dot(d, up)) * margin / ky - depth
                distance = max(distance, needX, needY)
            }
            // Re-centre on the projected extents (perspective shifts the visual centre).
            let cam = target + toCamera * distance
            var lx: Float = .greatestFiniteMagnitude, hx: Float = -.greatestFiniteMagnitude
            var ly = lx, hy = hx
            for p in points {
                let d = p - cam
                let z = max(simd_dot(d, forward), 0.05)
                let nx = simd_dot(d, right) / z, ny = simd_dot(d, up) / z
                lx = min(lx, nx); hx = max(hx, nx); ly = min(ly, ny); hy = max(hy, ny)
            }
            target += right * ((lx + hx) / 2 * distance) + up * ((ly + hy) / 2 * distance)
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
    private var rimNodes: [SCNNode] = []

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
        // Distance fog in the background colour fades the floor and grid out, so there is no visible horizon edge.
        scene.fogColor = appearance.background
        scene.fogStartDistance = 4.6
        scene.fogEndDistance = 8.5
        scene.fogDensityExponent = 1.4

        floorNode = SCNNode()
        let plane = SCNPlane(width: 24, height: 24)
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

        let shadowPlane = SCNPlane(width: 24, height: 24)
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
        rimNodes.forEach { cameraNode.addChildNode($0) }
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

        // Rim lights ride with the camera and shine from behind the figure towards it, so the silhouette separates
        // from the background from every angle.
        for (i, dir) in [SIMD3<Float>(-0.55, -0.30, 0.78), SIMD3<Float>(0.55, -0.25, 0.80)].enumerated() {
            let rim = SCNLight()
            rim.type = .directional
            rim.intensity = i == 0 ? 900 : 650
            rim.temperature = 7600
            let n = SCNNode()
            n.light = rim
            n.name = "rim\(i)"
            n.simdLook(at: dir, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            rimNodes.append(n)
        }

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
        let line = dark ? UIColor(white: 1, alpha: 0.055) : UIColor(white: 0, alpha: 0.06)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            background.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            // Grid every 0.5 m (24 m plane over 1024 px).
            let step = side / 48
            cg.setLineWidth(1.2)
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
        scene.fogColor = new.background
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

    // Orbit state relative to the preset framing (the controller owns the camera; SceneKit's own camera control is off).
    private var presetDistance: Float = 4
    private var orbitAzimuth: Float = 0
    private var orbitElevation: Float = 0
    private var zoom: Float = 1

    func setCamera(_ preset: GuideCameraPreset, animated: Bool) {
        cameraPreset = preset
        let focus = motion?.focusHeight ?? 0.9
        let framing = CameraFraming.frame(points: samplePoints, preset: preset, focusHeight: focus, aspect: viewAspect)
        cameraTarget = framing.target
        presetDistance = framing.distance
        orbitAzimuth = 0; orbitElevation = 0; zoom = 1
        minDistance = max(framing.distance * 0.45, 0.9)
        maxDistance = framing.distance * 2.2
        placeCamera(animated: animated)
    }

    /// Turntable orbit by screen-space deltas (radians).
    func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        orbitAzimuth += deltaAzimuth
        orbitElevation = min(max(orbitElevation + deltaElevation, -0.3), 1.2)
        placeCamera(animated: false)
    }

    func pinch(scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        zoom = min(max(zoom / scale, 0.45), 2.2)
        placeCamera(animated: false)
    }

    private func placeCamera(animated: Bool) {
        let d = CameraFraming.direction(for: cameraPreset)
        let az = atan2(d.x, d.z) + orbitAzimuth
        let el = min(max(asin(d.y) + orbitElevation, 0.02), 1.3)
        let dir = SIMD3<Float>(sin(az) * cos(el), sin(el), cos(az) * cos(el))
        let pos = cameraTarget + dir * (presetDistance * zoom)
        let orientation = Self.lookOrientation(from: pos, to: cameraTarget)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraNode.simdPosition = pos
            cameraNode.simdOrientation = orientation
            SCNTransaction.commit()
        } else {
            cameraNode.simdPosition = pos
            cameraNode.simdOrientation = orientation
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
    }
}
