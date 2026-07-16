import Foundation

/// THIS bot's mass model — segment masses proportional to its own mesh
/// volumes in liters (the head alone is ~8 L; the limbs are skinny
/// capsules), each hung at the segment midpoint, plus the demo bar's
/// mass at the palm midpoint. ONE source of truth shared by the balance
/// invariants and the authoring path servos (a baked descent leans the
/// torso until the center of mass rides over the feet — the same
/// continuous coordination a real lifter does by feel).
public enum MascotBalance {
    /// Keyed by the segment's child joint; `.root` is the pelvis.
    public static let segmentMasses: [MascotJoint: Double] = [
        .root: 5.2, .spine: 6.5, .chest: 6.6, .neck: 0.3, .head: 8.4,
        .leftElbow: 0.65, .rightElbow: 0.65,
        .leftWrist: 0.65, .rightWrist: 0.65,
        .leftKnee: 1.5, .rightKnee: 1.5,
        .leftAnkle: 1.5, .rightAnkle: 1.5,
    ]
    /// The demo barbell (small lathe plates — a teaching bar).
    public static let barMass = 2.0

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
