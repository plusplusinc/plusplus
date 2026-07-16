import RealityKit
import Foundation

/// Code-generated meshes beyond RealityKit's primitives — still zero
/// bundled assets, just math. The only one so far: a cylinder with
/// rounded edges around its perimeter (Dave's spec for weight plates:
/// "still cylinders, just with rounded edges") built as a lathe — a
/// rounded-rectangle half-profile revolved around the Y axis.
@MainActor
enum MascotMeshes {
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

        var descriptor = MeshDescriptor(name: "roundedCylinder")
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
