import RealityKit
import Foundation

/// Code-generated meshes beyond RealityKit's primitives — still zero
/// bundled assets, just math: lathes (half-profiles revolved around the
/// Y axis). `roundedCylinder` is the weight-plate spec ("still
/// cylinders, just with rounded edges"); `muscle` sweeps a smooth
/// radius curve down a limb so the body reads sculpted instead of
/// boxy (build-88: "a bit more human like shape … some approximation"
/// of muscle, deliberately NOT an anatomical model).
@MainActor
enum MascotMeshes {
    /// A limb segment as a surface of revolution: y = 0 at the joint,
    /// hanging down to y = -length, radius swept through `controls`
    /// (fraction-down-the-limb, radius) with Catmull-Rom smoothing —
    /// a deltoid cap, a quad bulge, a calf swell are all just control
    /// points. Ends are flat (the charcoal joint spheres cover them).
    /// ⚠️ The widest control of a COLLIDING limb must match its capsule
    /// radius in MascotCollision.segmentRadii — mesh and proof move
    /// together or not at all.
    static func muscle(
        length: Float,
        controls: [(t: Float, r: Float)],
        radialSegments: Int = 40,
        rings: Int = 28
    ) -> MeshResource? {
        guard controls.count >= 2, length > 0 else { return nil }

        // Catmull-Rom through the control radii, clamped at the ends.
        func radius(at t: Float) -> Float {
            let clamped = min(max(t, controls.first!.t), controls.last!.t)
            var k = 0
            while k < controls.count - 2 && clamped > controls[k + 1].t { k += 1 }
            let p1 = controls[k]
            let p2 = controls[k + 1]
            let p0 = k > 0 ? controls[k - 1] : p1
            let p3 = k + 2 < controls.count ? controls[k + 2] : p2
            let span = max(p2.t - p1.t, 1e-6)
            let u = (clamped - p1.t) / span
            let m1 = (p2.r - p0.r) / max(p2.t - p0.t, 1e-6) * span
            let m2 = (p3.r - p1.r) / max(p3.t - p1.t, 1e-6) * span
            let u2 = u * u
            let u3 = u2 * u
            return (2 * u3 - 3 * u2 + 1) * p1.r + (u3 - 2 * u2 + u) * m1
                + (-2 * u3 + 3 * u2) * p2.r + (u3 - u2) * m2
        }

        // Side profile top->bottom, with numeric slopes for normals,
        // then flat cap rings at both ends (normal straight up/down).
        var profile: [(r: Float, y: Float, nr: Float, ny: Float)] = []
        profile.append((0, 0, 0, 1))
        profile.append((radius(at: 0), 0, 0, 1))
        for k in 0...rings {
            let t = Float(k) / Float(rings)
            let r = radius(at: t)
            let dt: Float = 1.0 / Float(rings)
            let slope = (radius(at: min(t + dt, 1)) - radius(at: max(t - dt, 0)))
                / (2 * dt) / length  // dr/dy with y running downward
            // Surface-of-revolution normal: radial out, tipped by the
            // profile slope (a bulge widening downward faces up-and-out).
            let n = normalize(SIMD3<Float>(1, slope, 0))
            profile.append((r, -t * length, n.x, n.y))
        }
        profile.append((radius(at: 1), -length, 0, -1))
        profile.append((0, -length, 0, -1))

        return lathe(profile: profile, radialSegments: radialSegments, name: "muscle")
    }

    /// - Parameters:
    ///   - radius: cylinder radius (Y is the axis; rotate the entity to
    ///     point it elsewhere).
    ///   - height: full height along the axis.
    ///   - edgeRadius: the rim rounding; clamped to fit.
    static func roundedCylinder(
        radius: Float,
        height: Float,
        edgeRadius: Float,
        radialSegments: Int = 48,
        arcSegments: Int = 5
    ) -> MeshResource? {
        let e = min(edgeRadius, min(radius, height / 2) * 0.95)
        let h2 = height / 2

        // The half-profile as (r, y) points with (nr, ny) normals,
        // walked from the top axis to the bottom axis.
        var profile: [(r: Float, y: Float, nr: Float, ny: Float)] = []
        profile.append((0, h2, 0, 1))
        profile.append((radius - e, h2, 0, 1))
        // Top rim arc: normal sweeps from straight up to straight out.
        for k in 0...arcSegments {
            let phi = Float(k) / Float(arcSegments) * (.pi / 2)
            profile.append((
                (radius - e) + e * sin(phi),
                (h2 - e) + e * cos(phi),
                sin(phi),
                cos(phi)
            ))
        }
        profile.append((radius, -h2 + e, 1, 0))
        // Bottom rim arc.
        for k in 0...arcSegments {
            let phi = Float(k) / Float(arcSegments) * (.pi / 2)
            profile.append((
                radius - e * (1 - cos(phi)),
                (-h2 + e) - e * sin(phi),
                cos(phi),
                -sin(phi)
            ))
        }
        profile.append((radius - e, -h2, 0, -1))
        profile.append((0, -h2, 0, -1))

        return lathe(profile: profile, radialSegments: radialSegments, name: "roundedCylinder")
    }

    /// Revolves a half-profile of (radius, y) points with (radial, y)
    /// normals around the Y axis.
    private static func lathe(
        profile: [(r: Float, y: Float, nr: Float, ny: Float)],
        radialSegments: Int,
        name: String
    ) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let ringCount = profile.count
        let segments = radialSegments
        for point in profile {
            for s in 0...segments {
                let alpha = Float(s) / Float(segments) * 2 * .pi
                positions.append([point.r * cos(alpha), point.y, point.r * sin(alpha)])
                normals.append(normalize(SIMD3(point.nr * cos(alpha), point.ny, point.nr * sin(alpha))))
            }
        }
        func vertex(_ ring: Int, _ s: Int) -> UInt32 {
            UInt32(ring * (segments + 1) + s)
        }
        for ring in 0..<(ringCount - 1) {
            for s in 0..<segments {
                let a = vertex(ring, s)
                let b = vertex(ring, s + 1)
                let c = vertex(ring + 1, s)
                let d = vertex(ring + 1, s + 1)
                // Emitted double-sided: winding mistakes on a hand-built
                // lathe show up as invisible faces only on device, so we
                // simply pay the (tiny) duplicate-triangle cost.
                indices.append(contentsOf: [a, c, b, b, c, d])
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        guard length > 0 else { return [0, 1, 0] }
        return v / length
    }
}
