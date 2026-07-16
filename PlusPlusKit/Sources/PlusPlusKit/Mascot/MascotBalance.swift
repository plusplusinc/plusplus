import Foundation

/// THIS bot's mass model — segment masses TRACKING its own mesh
/// volumes in rough liters (the head alone is ~8 L; the limbs are
/// slender), each hung at the segment midpoint, plus the demo bar's
/// mass at the palm midpoint. ONE source of truth shared by the balance
/// invariants and the authoring path servos (a baked descent leans the
/// torso until the center of mass rides over the feet — the same
/// continuous coordination a real lifter does by feel). Approximate by
/// design, but re-check it whenever a silhouette changes: the build-88
/// muscle/feet pass slimmed the legs (lathes vs boxes, −~17% thigh /
/// −~34% shin) and nearly halved the feet, and the table moved with it.
public enum MascotBalance {
    /// Keyed by the segment's child joint; `.root` is the pelvis.
    /// `.wrist` includes the hand; `.ankle` includes the foot.
    public static let segmentMasses: [MascotJoint: Double] = [
        .root: 5.2, .spine: 6.5, .chest: 6.6, .neck: 0.3, .head: 8.4,
        .leftElbow: 0.6, .rightElbow: 0.6,
        .leftWrist: 0.6, .rightWrist: 0.6,
        .leftKnee: 1.4, .rightKnee: 1.4,
        .leftAnkle: 1.0, .rightAnkle: 1.0,
    ]
    /// The demo barbell (small lathe plates — a teaching bar).
    public static let barMass = 2.0

    /// The support polygon: x/z extents of every contact point
    /// currently ON the ground (sole corners and palm pads within the
    /// contact threshold), padded by half a contact patch. Two planted
    /// feet make the familiar wide box; a heel-up foot shrinks it to
    /// the toe caps; a single-leg stance narrows x to one foot — the
    /// polygon FOLLOWS the contact, which is what balance really is.
    /// Contact points are modeled on the foot's CENTERLINE, so x grows
    /// by the mesh half-width; the sole corners already are the z
    /// extremes, so z gets only a small contact-patch edge.
    public static func supportPolygon(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        contactThreshold: Double = 0.02,
        halfWidthX: Double = 0.03,
        patchZ: Double = 0.005
    ) -> (x: ClosedRange<Double>, z: ClosedRange<Double>)? {
        var points: [Vec3] = []
        for point in pose.solePoints(skeleton: skeleton) where point.y <= contactThreshold {
            points.append(point)
        }
        for pad in MascotCollision.palmSpheres(pose: pose, skeleton: skeleton)
        where pad.from.y - pad.radius <= contactThreshold {
            points.append(pad.from)
        }
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minZ = first.z, maxZ = first.z
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        return ((minX - halfWidthX)...(maxX + halfWidthX), (minZ - patchZ)...(maxZ + patchZ))
    }

    /// The whole-body (plus held bar) center of mass.
    public static func centerOfMass(
        pose: MascotPose,
        props: [MascotProp],
        skeleton: MascotSkeleton = .standard
    ) -> Vec3 {
        let frames = pose.jointFrames(skeleton: skeleton)
        var moment = Vec3.zero
        var mass = 0.0
        for (joint, m) in segmentMasses {
            guard let p = frames[joint]?.position else { continue }
            var anchor = p
            if joint != .root, let parent = joint.parent, let pp = frames[parent]?.position {
                anchor = 0.5 * (p + pp)
            }
            moment = moment + m * anchor
            mass += m
        }
        if props.contains(.barbell),
           let left = frames[.leftWrist], let right = frames[.rightWrist] {
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            moment = moment + barMass * (0.5 * (leftPalm + rightPalm))
            mass += barMass
        }
        return (1.0 / mass) * moment
    }
}
