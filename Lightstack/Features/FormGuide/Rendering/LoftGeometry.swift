import SceneKit
import simd

/// One cross-section of a lofted shape: an ellipse (half-widths rx along X, rz along Z) at height y,
/// its centre shifted by (cx, cz).
struct LoftRing {
    var y: Float
    var rx: Float
    var rz: Float
    var cx: Float = 0
    var cz: Float = 0
}

/// Builds smooth, lathe-like meshes from a list of elliptical rings stacked along +Y.
/// Normals are computed from the surface tangents, so the result is smooth without a lighting seam.
enum LoftBuilder {

    static func geometry(rings: [LoftRing], segments: Int = 28) -> SCNGeometry {
        precondition(rings.count >= 2)
        let n = segments
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(rings.count * n)
        for ring in rings {
            for k in 0..<n {
                let a = Float(k) / Float(n) * 2 * .pi
                positions.append(SIMD3(ring.cx + ring.rx * sin(a), ring.y, ring.cz + ring.rz * cos(a)))
            }
        }
        func index(_ i: Int, _ k: Int) -> Int { i * n + ((k % n) + n) % n }

        var normals = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: positions.count)
        for i in 0..<rings.count {
            let i0 = max(i - 1, 0), i1 = min(i + 1, rings.count - 1)
            for k in 0..<n {
                let tAround = positions[index(i, k + 1)] - positions[index(i, k - 1)]
                let tAlong = positions[index(i1, k)] - positions[index(i0, k)]
                var nrm = simd_cross(tAlong, tAround)
                if simd_length(nrm) < 1e-9 {
                    // A pole: the normal points along the axis.
                    nrm = SIMD3(0, i == 0 ? -1 : 1, 0)
                }
                nrm = simd_normalize(nrm)
                if (i == 0 || i == rings.count - 1), max(rings[i].rx, rings[i].rz) < 0.03 { nrm = SIMD3(0, i == 0 ? -1 : 1, 0) }
                // Orient outwards from the ring centre.
                let centre = SIMD3(rings[i].cx, rings[i].y, rings[i].cz)
                let radial = positions[index(i, k)] - centre
                let flat = SIMD3(radial.x, 0, radial.z)
                if simd_length(flat) > 1e-6, simd_dot(nrm, flat) < 0 { nrm = -nrm }
                normals[index(i, k)] = nrm
            }
        }
        var indices: [Int32] = []
        for i in 0..<(rings.count - 1) {
            for k in 0..<n {
                let a = Int32(index(i, k)), b = Int32(index(i, k + 1))
                let c = Int32(index(i + 1, k)), d = Int32(index(i + 1, k + 1))
                // Counter-clockwise seen from outside.
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let vSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let nSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vSource, nSource], elements: [element])
    }

    /// Catmull-Rom interpolation of key values along 0...1 positions.
    static func smoothSample(_ keys: [(t: Float, v: Float)], at t: Float) -> Float {
        guard keys.count >= 2 else { return keys.first?.v ?? 0 }
        if t <= keys[0].t { return keys[0].v }
        if t >= keys[keys.count - 1].t { return keys[keys.count - 1].v }
        var i = 0
        while i + 1 < keys.count - 1, keys[i + 1].t < t { i += 1 }
        let p1 = keys[i], p2 = keys[i + 1]
        let p0 = i > 0 ? keys[i - 1] : (t: 2 * p1.t - p2.t, v: 2 * p1.v - p2.v)
        let p3 = i + 2 < keys.count ? keys[i + 2] : (t: 2 * p2.t - p1.t, v: 2 * p2.v - p1.v)
        let u = (t - p1.t) / max(p2.t - p1.t, 1e-6)
        // Non-uniform Catmull-Rom on values with tangents scaled to the span.
        let m1 = (p2.v - p0.v) / max(p2.t - p0.t, 1e-6) * (p2.t - p1.t)
        let m2 = (p3.v - p1.v) / max(p3.t - p1.t, 1e-6) * (p2.t - p1.t)
        let u2 = u * u, u3 = u2 * u
        return (2 * u3 - 3 * u2 + 1) * p1.v + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * p2.v + (u3 - u2) * m2
    }

    /// A tapered limb along +Y from y = 0 to y = `length`, with hemispherical end caps of radius `startCap`/`endCap`
    /// centred on the end points. `profile` holds (position 0...1, rx, rz, cz).
    static func limb(length: Float, profile: [(t: Float, rx: Float, rz: Float, cz: Float)],
                     startCap: Float, endCap: Float, bodyRings: Int = 14, capRings: Int = 6,
                     segments: Int = 28) -> SCNGeometry {
        let rxKeys = profile.map { (t: $0.t, v: $0.rx) }
        let rzKeys = profile.map { (t: $0.t, v: $0.rz) }
        let czKeys = profile.map { (t: $0.t, v: $0.cz) }
        var rings: [LoftRing] = []
        // Start cap (pole first).
        if startCap > 0 {
            let r0x = rxKeys[0].v, r0z = rzKeys[0].v, c0 = czKeys[0].v
            for j in 0..<capRings {
                let phi = Float(capRings - j) / Float(capRings) * (.pi / 2)
                rings.append(LoftRing(y: -startCap * sin(phi), rx: r0x * cos(phi), rz: r0z * cos(phi), cz: c0))
            }
        }
        for j in 0...bodyRings {
            let t = Float(j) / Float(bodyRings)
            rings.append(LoftRing(y: t * length, rx: smoothSample(rxKeys, at: t), rz: smoothSample(rzKeys, at: t),
                                  cz: smoothSample(czKeys, at: t)))
        }
        if endCap > 0 {
            let last = profile.count - 1
            let r1x = rxKeys[last].v, r1z = rzKeys[last].v, c1 = czKeys[last].v
            for j in 1...capRings {
                let phi = Float(j) / Float(capRings) * (.pi / 2)
                rings.append(LoftRing(y: length + endCap * sin(phi), rx: r1x * cos(phi), rz: r1z * cos(phi), cz: c1))
            }
        }
        return geometry(rings: rings, segments: segments)
    }

    /// Ring function of a tapered limb (same shape as `limb(...)`), including its end caps for y outside 0...length.
    static func limbSurface(length: Float, profile: [(t: Float, rx: Float, rz: Float, cz: Float)],
                            startCap: Float, endCap: Float) -> (Float) -> LoftRing {
        let rxKeys = profile.map { (t: $0.t, v: $0.rx) }
        let rzKeys = profile.map { (t: $0.t, v: $0.rz) }
        let czKeys = profile.map { (t: $0.t, v: $0.cz) }
        return { y in
            if y < 0, startCap > 0 {
                let c = sqrt(max(1 - min(-y / startCap, 1) * min(-y / startCap, 1), 0))
                return LoftRing(y: y, rx: rxKeys[0].v * c, rz: rzKeys[0].v * c, cz: czKeys[0].v)
            }
            if y > length, endCap > 0 {
                let k = min((y - length) / endCap, 1)
                let c = sqrt(max(1 - k * k, 0))
                return LoftRing(y: y, rx: rxKeys[rxKeys.count - 1].v * c, rz: rzKeys[rzKeys.count - 1].v * c,
                                cz: czKeys[czKeys.count - 1].v)
            }
            let t = min(max(y / length, 0), 1)
            return LoftRing(y: y, rx: smoothSample(rxKeys, at: t), rz: smoothSample(rzKeys, at: t), cz: smoothSample(czKeys, at: t))
        }
    }

    /// Ring function from key rings along y (torso, head).
    static func keyedSurface(_ keys: [(y: Float, rx: Float, rz: Float, cz: Float)]) -> (Float) -> LoftRing {
        let rx = keys.map { (t: $0.y, v: $0.rx) }
        let rz = keys.map { (t: $0.y, v: $0.rz) }
        let cz = keys.map { (t: $0.y, v: $0.cz) }
        return { y in LoftRing(y: y, rx: smoothSample(rx, at: y), rz: smoothSample(rz, at: y), cz: smoothSample(cz, at: y)) }
    }

    /// A muscle patch: a grid laid on the body surface (angles in degrees around the section; 0 = front (+Z), 90 = +X,
    /// 180 = back). It rises `height` above the surface in the middle and sinks below it at the border, so it reads as a
    /// soft relief that is flush with the body. `widthScale` tapers the angular width from the bottom (y0) to the top (y1).
    static func patch(surface: (Float) -> LoftRing, aCenter: Float, aHalf: Float, y0: Float, y1: Float,
                      height: Float, widthScale: (bottom: Float, top: Float) = (1, 1),
                      columns: Int = 12, rows: Int = 16) -> SCNGeometry {
        func env(_ x: Float) -> Float { pow(max(sin(.pi * x), 0), 0.55) }
        let sink: Float = 0.004
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = []
        func point(_ i: Int, _ j: Int) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
            let v = Float(i) / Float(rows), u = Float(j) / Float(columns)
            let y = y0 + (y1 - y0) * v
            let r = surface(y)
            let half = aHalf * (widthScale.bottom + (widthScale.top - widthScale.bottom) * v)
            let a = (aCenter + half * (2 * u - 1)) * .pi / 180
            let h = -sink + (height + sink) * env(u) * env(v)
            let n = simd_normalize(SIMD3(sin(a) / max(r.rx, 1e-4), 0, cos(a) / max(r.rz, 1e-4)))
            let base = SIMD3(r.cx + r.rx * sin(a), y, r.cz + r.rz * cos(a))
            return (base + n * h, n)
        }
        var grid: [[SIMD3<Float>]] = [], outward: [[SIMD3<Float>]] = []
        for i in 0...rows {
            var row: [SIMD3<Float>] = [], nr: [SIMD3<Float>] = []
            for j in 0...columns { let q = point(i, j); row.append(q.p); nr.append(q.n) }
            grid.append(row); outward.append(nr)
        }
        // Smooth normals from the grid, oriented outwards.
        var flipWinding = false
        for i in 0...rows {
            for j in 0...columns {
                let i0 = max(i - 1, 0), i1 = min(i + 1, rows), j0 = max(j - 1, 0), j1 = min(j + 1, columns)
                let tv = grid[i1][j] - grid[i0][j], tu = grid[i][j1] - grid[i][j0]
                var n = simd_cross(tu, tv)
                if simd_length(n) < 1e-12 { n = outward[i][j] } else { n = simd_normalize(n) }
                if i == rows / 2, j == columns / 2 { flipWinding = simd_dot(n, outward[i][j]) < 0 }
                pos.append(grid[i][j]); nrm.append(n)
            }
        }
        if flipWinding { nrm = nrm.map { -$0 } }
        var idx: [Int32] = []
        let w = columns + 1
        for i in 0..<rows {
            for j in 0..<columns {
                let a = Int32(i * w + j), b = Int32(i * w + j + 1), c = Int32((i + 1) * w + j), d = Int32((i + 1) * w + j + 1)
                if flipWinding { idx.append(contentsOf: [a, c, b, b, c, d]) } else { idx.append(contentsOf: [a, b, c, b, d, c]) }
            }
        }
        let vs = SCNGeometrySource(vertices: pos.map { SCNVector3($0.x, $0.y, $0.z) })
        let ns = SCNGeometrySource(normals: nrm.map { SCNVector3($0.x, $0.y, $0.z) })
        return SCNGeometry(sources: [vs, ns], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// A closed ellipsoid centred at the origin.
    static func ellipsoid(rx: Float, ry: Float, rz: Float, rings: Int = 14, segments: Int = 24) -> SCNGeometry {
        var out: [LoftRing] = []
        for j in 0...rings {
            let phi = -Float.pi / 2 + Float(j) / Float(rings) * .pi
            out.append(LoftRing(y: ry * sin(phi), rx: rx * cos(phi), rz: rz * cos(phi)))
        }
        return geometry(rings: out, segments: segments)
    }
}

// MARK: - Small math helpers shared by the renderer

enum GuideMath {
    static func toVec(_ v: SIMD3<Float>) -> SCNVector3 { SCNVector3(v.x, v.y, v.z) }

    /// Rotation with local +Y along `y` and local +Z as close to `zRef` as possible (local X = Y x Z).
    static func basis(y: SIMD3<Float>, zRef: SIMD3<Float>) -> simd_quatf {
        let yy = FigureSolver.safeNormalize(y)
        var z = zRef - yy * simd_dot(zRef, yy)
        if simd_length(z) < 1e-4 {
            let alt: SIMD3<Float> = abs(yy.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
            z = alt - yy * simd_dot(alt, yy)
        }
        z = simd_normalize(z)
        let x = simd_cross(yy, z)
        return simd_quatf(simd_float3x3(columns: (x, yy, z)))
    }

    /// Rotation with local +Y along `y` and local +X as close to `xRef` as possible.
    static func basis(y: SIMD3<Float>, xRef: SIMD3<Float>) -> simd_quatf {
        let yy = FigureSolver.safeNormalize(y)
        var x = xRef - yy * simd_dot(xRef, yy)
        if simd_length(x) < 1e-4 {
            let alt: SIMD3<Float> = abs(yy.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
            x = alt - yy * simd_dot(alt, yy)
        }
        x = simd_normalize(x)
        let z = simd_cross(x, yy)
        return simd_quatf(simd_float3x3(columns: (x, yy, z)))
    }

    static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / max(b - a, 1e-6), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
