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
        jointFrames(skeleton: skeleton).mapValues(\.position)
    }

    /// Positions AND world rotations — what the toe solver and the
    /// ground-contact invariants need (a toe hangs off the ankle's
    /// rotated frame).
    public func jointFrames(skeleton: MascotSkeleton) -> [MascotJoint: (position: Vec3, rotation: Mat3)] {
        var frames: [MascotJoint: (position: Vec3, rotation: Mat3)] = [:]

        let rootBone = skeleton.bone(.root)
        frames[.root] = (
            rootBone.offset + rootTranslation,
            Mat3.rotation(rootRotation) * Mat3.rotation(angles(.root))
        )

        // CaseIterable order lists every parent before its children.
        for joint in MascotJoint.allCases where joint != .root {
            guard let parent = joint.parent, let parentFrame = frames[parent] else { continue }
            let bone = skeleton.bone(joint)
            frames[joint] = (
                parentFrame.position + parentFrame.rotation.rotate(bone.offset),
                parentFrame.rotation * Mat3.rotation(angles(joint))
            )
        }
        return frames
    }

    /// The tip of each foot: the ankle's bone extended through its
    /// rotated frame. "The toes touch the ground" is an invariant about
    /// THESE points, not the ankle joints.
    public func toePositions(skeleton: MascotSkeleton) -> (left: Vec3, right: Vec3) {
        let frames = jointFrames(skeleton: skeleton)
        func toe(_ ankle: MascotJoint) -> Vec3 {
            guard let frame = frames[ankle] else { return .zero }
            let reach = skeleton.bone(ankle).length
            return frame.position + frame.rotation.rotate(Vec3(0, -reach, 0))
        }
        return (toe(.leftAnkle), toe(.rightAnkle))
    }

    /// The four sole corners (heel and toe of each foot), for the
    /// floor-contact invariants. Distinct from `toePositions` (the
    /// pointed-foot reach used by the floor-move toe solver): these
    /// track the flat sole of the renderer's foot mesh.
    public func solePoints(skeleton: MascotSkeleton) -> [Vec3] {
        let frames = jointFrames(skeleton: skeleton)
        var points: [Vec3] = []
        for ankle in [MascotJoint.leftAnkle, .rightAnkle] {
            guard let frame = frames[ankle] else { continue }
            points.append(frame.position + frame.rotation.rotate(MascotSkeleton.soleToeOffset))
            points.append(frame.position + frame.rotation.rotate(MascotSkeleton.soleHeelOffset))
        }
        return points
    }

    /// The largest joint-or-root delta between two poses, EXCLUDING
    /// effort — "is the body still here" for pause detection and
    /// continuity checks.
    public func maxBodyDelta(to other: MascotPose) -> Double {
        var worst = rootTranslation.distance(to: other.rootTranslation)
        let rotDelta = EulerAngles(
            pitch: rootRotation.pitch - other.rootRotation.pitch,
            yaw: rootRotation.yaw - other.rootRotation.yaw,
            roll: rootRotation.roll - other.rootRotation.roll
        )
        worst = max(worst, rotDelta.maxMagnitude)
        for joint in Set(joints.keys).union(other.joints.keys) {
            let d = EulerAngles(
                pitch: angles(joint).pitch - other.angles(joint).pitch,
                yaw: angles(joint).yaw - other.angles(joint).yaw,
                roll: angles(joint).roll - other.angles(joint).roll
            )
            worst = max(worst, d.maxMagnitude)
        }
        return worst
    }

    /// Linear combination over the key union — the smoothing spline's
    /// building block. Terms may carry negative weights (differences).
    public static func weightedSum(_ terms: [(pose: MascotPose, weight: Double)]) -> MascotPose {
        var root = Vec3.zero
        var rootRot = EulerAngles.zero
        var effort = 0.0
        var keys = Set<MascotJoint>()
        for term in terms {
            keys.formUnion(term.pose.joints.keys)
        }
        var joints: [MascotJoint: EulerAngles] = [:]
        for key in keys {
            joints[key] = .zero
        }
        for (pose, weight) in terms {
            root = root + weight * pose.rootTranslation
            rootRot = EulerAngles(
                pitch: rootRot.pitch + weight * pose.rootRotation.pitch,
                yaw: rootRot.yaw + weight * pose.rootRotation.yaw,
                roll: rootRot.roll + weight * pose.rootRotation.roll
            )
            effort += weight * pose.effort
            for key in keys {
                let a = pose.angles(key)
                let current = joints[key] ?? .zero
                joints[key] = EulerAngles(
                    pitch: current.pitch + weight * a.pitch,
                    yaw: current.yaw + weight * a.yaw,
                    roll: current.roll + weight * a.roll
                )
            }
        }
        return MascotPose(rootTranslation: root, rootRotation: rootRot, joints: joints, effort: effort)
    }
}
