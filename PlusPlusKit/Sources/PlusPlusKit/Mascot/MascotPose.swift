import Foundation

/// One instant of the mascot: where the hips are, how every joint is
/// rotated, and how hard it is working. Joints absent from `joints` are
/// at rest (zero). `effort` is the authored exertion channel (0 relaxed,
/// 1 grinding); the face and breathing derive from it, and it
/// interpolates exactly like a joint angle.
public struct MascotPose: Equatable, Sendable {
    /// Hip displacement from the rest hip position (NOT an absolute
    /// height): a squat's descent is a negative-y translation here.
    public var rootTranslation: Vec3
    /// Whole-body orientation, applied at the root before any joint —
    /// how floor work (push-up, plank) tips the rig horizontal.
    public var rootRotation: EulerAngles
    public var joints: [MascotJoint: EulerAngles]
    public var effort: Double

    public init(
        rootTranslation: Vec3 = .zero,
        rootRotation: EulerAngles = .zero,
        joints: [MascotJoint: EulerAngles] = [:],
        effort: Double = 0
    ) {
        self.rootTranslation = rootTranslation
        self.rootRotation = rootRotation
        self.joints = joints
        self.effort = effort
    }

    public func angles(_ joint: MascotJoint) -> EulerAngles {
        joints[joint] ?? .zero
    }

    public func lerp(to other: MascotPose, t: Double) -> MascotPose {
        var blended: [MascotJoint: EulerAngles] = [:]
        for joint in Set(joints.keys).union(other.joints.keys) {
            blended[joint] = angles(joint).lerp(to: other.angles(joint), t: t)
        }
        return MascotPose(
            rootTranslation: rootTranslation.lerp(to: other.rootTranslation, t: t),
            rootRotation: rootRotation.lerp(to: other.rootRotation, t: t),
            joints: blended,
            effort: effort + t * (other.effort - effort)
        )
    }

    /// Forward kinematics: the world position of every joint. This is
    /// what makes authored animations numerically testable on Linux —
    /// feet planted, nothing through the floor, wrists barbell-symmetric —
    /// without ever rendering a frame.
    public func jointPositions(skeleton: MascotSkeleton) -> [MascotJoint: Vec3] {
        var positions: [MascotJoint: Vec3] = [:]
        var rotations: [MascotJoint: Mat3] = [:]

        let rootBone = skeleton.bone(.root)
        positions[.root] = rootBone.offset + rootTranslation
        rotations[.root] = Mat3.rotation(rootRotation) * Mat3.rotation(angles(.root))

        // CaseIterable order lists every parent before its children.
        for joint in MascotJoint.allCases where joint != .root {
            guard let parent = joint.parent,
                  let parentPosition = positions[parent],
                  let parentRotation = rotations[parent] else { continue }
            let bone = skeleton.bone(joint)
            positions[joint] = parentPosition + parentRotation.rotate(bone.offset)
            rotations[joint] = parentRotation * Mat3.rotation(angles(joint))
        }
        return positions
    }
}
