import SceneKit
import UIKit
import simd

/// Draws the equipment of a `GuideFrame`. Nodes are reused while the prop list keeps the same structure.
final class GuidePropRenderer {

    /// Structure of one prop: anything that forces new geometry. Positions and box sizes are not part of it.
    enum Signature: Hashable {
        case barbell(lengthMM: Int, plateMM: Int)
        case ezBar
        case dumbbell
        case kettlebell
        case cable
        case handle(lengthMM: Int)
        case box(GuideProp.BoxKind)
        case cylinder(GuideProp.BoxKind)
        case mat
    }

    let rootNode = SCNNode()
    private(set) var rebuildCount = 0
    private var entries: [(signature: Signature, node: SCNNode)] = []

    init() { rootNode.name = "props" }

    var propNodeCount: Int { rootNode.childNodes.count }

    // MARK: Public

    func update(_ props: [GuideProp]) {
        let signatures = props.map(Self.signature(of:))
        if signatures != entries.map(\.signature) { rebuild(signatures) }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        for (index, prop) in props.enumerated() { Self.position(entries[index].node, for: prop) }
        SCNTransaction.commit()
    }

    func clear() {
        entries.forEach { $0.node.removeFromParentNode() }
        entries = []
    }

    // MARK: Structure

    static func signature(of prop: GuideProp) -> Signature {
        switch prop {
        case let .barbell(_, _, length, plate): return .barbell(lengthMM: Int((length * 1000).rounded()), plateMM: Int((plate * 1000).rounded()))
        case .ezBar: return .ezBar
        case .dumbbell: return .dumbbell
        case .kettlebell: return .kettlebell
        case .cable: return .cable
        case let .handle(_, _, length): return .handle(lengthMM: Int((length * 1000).rounded()))
        case let .box(_, _, _, kind): return .box(kind)
        case let .cylinder(_, _, _, kind): return .cylinder(kind)
        case .mat: return .mat
        }
    }

    private func rebuild(_ signatures: [Signature]) {
        rebuildCount += 1
        clear()
        for sig in signatures {
            let node = Self.makeNode(sig)
            rootNode.addChildNode(node)
            entries.append((sig, node))
        }
    }

    // MARK: Materials

    private static func pbr(_ color: UIColor, roughness: CGFloat, metalness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private static let steel = pbr(UIColor(white: 0.78, alpha: 1), roughness: 0.28, metalness: 1.0)
    private static let darkSteel = pbr(UIColor(white: 0.20, alpha: 1), roughness: 0.38, metalness: 0.9)
    private static let plateMaterial = pbr(UIColor(white: 0.10, alpha: 1), roughness: 0.55, metalness: 0.1)
    private static let plateRim = pbr(UIColor(white: 0.55, alpha: 1), roughness: 0.4, metalness: 0.8)
    private static let rubber = pbr(UIColor(white: 0.07, alpha: 1), roughness: 0.85, metalness: 0)
    private static let padMaterial = pbr(UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1), roughness: 0.62, metalness: 0)
    private static let frameMaterial = pbr(UIColor(red: 0.24, green: 0.26, blue: 0.29, alpha: 1), roughness: 0.42, metalness: 0.85)
    private static let stackMaterial = pbr(UIColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1), roughness: 0.35, metalness: 0.9)
    private static let stackGap = pbr(UIColor(white: 0.08, alpha: 1), roughness: 0.6, metalness: 0.2)
    private static let platformMaterial = pbr(UIColor(red: 0.29, green: 0.30, blue: 0.33, alpha: 1), roughness: 0.55, metalness: 0.3)
    private static let matMaterial = pbr(UIColor(red: 0.20, green: 0.30, blue: 0.40, alpha: 1), roughness: 0.8, metalness: 0)
    private static let cableMaterial = pbr(UIColor(white: 0.62, alpha: 1), roughness: 0.4, metalness: 0.9)
    private static let kettlebellMaterial = pbr(UIColor(white: 0.10, alpha: 1), roughness: 0.45, metalness: 0.55)

    // MARK: Geometry builders

    /// Cylinder along local X (so axes given as bar directions map directly).
    private static func xCylinder(radius: CGFloat, length: CGFloat, material: SCNMaterial, at x: Float = 0) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: length)
        g.radialSegmentCount = 28
        g.materials = [material]
        let node = SCNNode(geometry: g)
        node.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        node.simdPosition = SIMD3(x, 0, 0)
        return node
    }

    private static func makeNode(_ sig: Signature) -> SCNNode {
        let node = SCNNode()
        switch sig {
        case let .barbell(lengthMM, plateMM):
            let length = CGFloat(lengthMM) / 1000
            let plate = CGFloat(plateMM) / 1000 * 0.80   // slightly smaller plates keep the body visible
            node.name = "barbell"
            node.addChildNode(xCylinder(radius: 0.0145, length: length * 0.62, material: steel))
            let sleeveLen = length * 0.19
            for side: Float in [1, -1] {
                let sleeveX = side * Float(length * 0.5 - sleeveLen / 2)
                node.addChildNode(xCylinder(radius: 0.025, length: sleeveLen, material: steel, at: sleeveX))
                node.addChildNode(xCylinder(radius: 0.019, length: 0.02, material: darkSteel, at: side * Float(length * 0.5 - sleeveLen - 0.005)))
                if plate > 0.04 {
                    let inner = Float(length * 0.5 - sleeveLen + 0.035)
                    for (i, thickness) in [CGFloat(0.046), 0.032].enumerated() {
                        let r = i == 0 ? plate : plate * 0.72
                        let x = side * (inner + Float(i) * 0.05)
                        node.addChildNode(xCylinder(radius: r, length: thickness, material: plateMaterial, at: x))
                        node.addChildNode(xCylinder(radius: 0.034, length: thickness + 0.004, material: plateRim, at: x))
                    }
                }
            }
        case .ezBar:
            node.name = "ezBar"
            // A cambered bar: straight ends joined by a zig-zag middle, with small plates.
            let pts: [SIMD3<Float>] = [SIMD3(-0.46, 0, 0), SIMD3(-0.20, 0, 0), SIMD3(-0.12, 0, 0.034), SIMD3(-0.05, 0, -0.034),
                                       SIMD3(0.05, 0, -0.034), SIMD3(0.12, 0, 0.034), SIMD3(0.20, 0, 0), SIMD3(0.46, 0, 0)]
            for i in 0..<(pts.count - 1) { node.addChildNode(segmentNode(pts[i], pts[i + 1], radius: 0.0145, material: steel)) }
            for side: Float in [1, -1] {
                node.addChildNode(xCylinder(radius: 0.022, length: 0.10, material: steel, at: side * 0.51))
                node.addChildNode(xCylinder(radius: 0.095, length: 0.034, material: plateMaterial, at: side * 0.43))
            }
        case .dumbbell:
            node.name = "dumbbell"
            node.addChildNode(xCylinder(radius: 0.016, length: 0.13, material: steel))
            for side: Float in [1, -1] {
                node.addChildNode(xCylinder(radius: 0.058, length: 0.075, material: darkSteel, at: side * 0.1)
                )
                node.addChildNode(xCylinder(radius: 0.040, length: 0.012, material: steel, at: side * 0.064))
            }
        case .kettlebell:
            node.name = "kettlebell"
            let ball = SCNSphere(radius: 0.105)
            ball.segmentCount = 32
            ball.materials = [kettlebellMaterial]
            node.addChildNode(SCNNode(geometry: ball))
            let handle = SCNTorus(ringRadius: 0.062, pipeRadius: 0.014)
            handle.materials = [kettlebellMaterial]
            let h = SCNNode(geometry: handle)
            h.simdPosition = SIMD3(0, 0.125, 0)
            h.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            node.addChildNode(h)
        case .cable:
            node.name = "cable"
            let g = SCNCylinder(radius: 0.0065, height: 1)
            g.radialSegmentCount = 8
            g.materials = [cableMaterial]
            node.addChildNode(SCNNode(geometry: g))
        case let .handle(lengthMM):
            node.name = "handle"
            let length = CGFloat(lengthMM) / 1000
            node.addChildNode(xCylinder(radius: 0.012, length: length, material: steel))
            node.addChildNode(xCylinder(radius: 0.017, length: length * 0.55, material: rubber))
            for side: Float in [1, -1] {
                node.addChildNode(xCylinder(radius: 0.020, length: 0.014, material: darkSteel, at: side * Float(length / 2)))
            }
        case let .box(kind):
            node.name = "box.\(kind.rawValue)"
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            box.materials = [boxMaterial(kind)]
            let body = SCNNode(geometry: box)
            body.name = "body"
            node.addChildNode(body)
            if kind == .weightStack {
                for i in 0..<7 {
                    let slab = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
                    slab.geometry?.materials = [stackGap]
                    slab.name = "slab\(i)"
                    node.addChildNode(slab)
                }
            }
        case let .cylinder(kind):
            node.name = "cylinder.\(kind.rawValue)"
            let g = SCNCylinder(radius: 1, height: 1)
            g.radialSegmentCount = 20
            g.materials = [boxMaterial(kind)]
            node.addChildNode(SCNNode(geometry: g))
        case .mat:
            node.name = "mat"
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            box.materials = [matMaterial]
            node.addChildNode(SCNNode(geometry: box))
        }
        return node
    }

    private static func boxMaterial(_ kind: GuideProp.BoxKind) -> SCNMaterial {
        switch kind {
        case .pad: return padMaterial
        case .frame: return frameMaterial
        case .weightStack: return stackMaterial
        case .platform: return platformMaterial
        }
    }

    /// A thin cylinder between two points, expressed in the parent's space.
    private static func segmentNode(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let length = simd_length(b - a)
        let g = SCNCylinder(radius: radius, height: CGFloat(length))
        g.radialSegmentCount = 16
        g.materials = [material]
        let node = SCNNode(geometry: g)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(b - a))
        return node
    }

    // MARK: Placement

    private static func orientation(from base: SIMD3<Float>, to dir: SIMD3<Float>) -> simd_quatf {
        let d = FigureSolver.safeNormalize(dir, fallback: base)
        if simd_dot(base, d) < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1)) }
        return simd_quatf(from: base, to: d)
    }

    private static func position(_ node: SCNNode, for prop: GuideProp) {
        switch prop {
        case let .barbell(center, axis, _, _):
            node.simdPosition = center
            node.simdOrientation = orientation(from: SIMD3(1, 0, 0), to: axis)
        case let .ezBar(center, axis):
            node.simdPosition = center
            node.simdOrientation = orientation(from: SIMD3(1, 0, 0), to: axis)
        case let .dumbbell(center, axis):
            node.simdPosition = center
            node.simdOrientation = orientation(from: SIMD3(1, 0, 0), to: axis)
        case let .kettlebell(center):
            node.simdPosition = center
        case let .cable(from, to):
            let d = to - from
            let len = max(simd_length(d), 1e-4)
            node.simdPosition = (from + to) / 2
            node.simdOrientation = orientation(from: SIMD3(0, 1, 0), to: d)
            node.simdScale = SIMD3(1, len, 1)
        case let .handle(center, axis, _):
            node.simdPosition = center
            node.simdOrientation = orientation(from: SIMD3(1, 0, 0), to: axis)
        case let .box(center, size, rotation, kind):
            node.simdPosition = center
            node.simdOrientation = rotation
            layoutBox(node, size: size, kind: kind)
        case let .cylinder(from, to, radius, _):
            let d = to - from
            node.simdPosition = (from + to) / 2
            node.simdOrientation = orientation(from: SIMD3(0, 1, 0), to: d)
            node.simdScale = SIMD3(radius, max(simd_length(d), 1e-4), radius)
        case let .mat(center, size):
            node.simdPosition = center
            node.simdScale = SIMD3(size.x, 0.012, size.y)
            node.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        }
    }

    /// Boxes use a unit box whose geometry is resized in place, so chamfers keep their shape.
    private static func layoutBox(_ node: SCNNode, size: SIMD3<Float>, kind: GuideProp.BoxKind) {
        guard let body = node.childNode(withName: "body", recursively: false),
              let box = body.geometry as? SCNBox else { return }
        let w = CGFloat(size.x), h = CGFloat(size.y), l = CGFloat(size.z)
        if abs(box.width - w) > 1e-5 || abs(box.height - h) > 1e-5 || abs(box.length - l) > 1e-5 {
            box.width = w; box.height = h; box.length = l
            let smallest = max(min(w, min(h, l)), 0.004)
            let factor: CGFloat = kind == .pad ? 0.42 : (kind == .frame ? 0.18 : 0.12)
            box.chamferRadius = smallest * factor
            box.chamferSegmentCount = 3
        }
        if kind == .weightStack {
            for i in 0..<7 {
                guard let slab = node.childNode(withName: "slab\(i)", recursively: false) else { continue }
                let y = Float(h) * (-0.5 + (Float(i) + 1) / 8)
                slab.simdPosition = SIMD3(0, y, 0)
                slab.simdScale = SIMD3(size.x + 0.002, 0.004, size.z + 0.002)
            }
        }
    }
}
