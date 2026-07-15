import RealityKit
import PlusPlusKit
import simd

/// Maps kit poses onto the rig. The Euler-to-quaternion conversion here
/// and Kit's `Mat3.rotation` are two implementations of ONE contract —
/// R = Ry(yaw) * Rx(pitch) * Rz(roll), intrinsic — pinned together by
/// `MascotMathParityTests`. Change one without the other and the mascot
/// folds inside-out; the parity test fails first.
enum MascotPoseApplier {
    /// Deliberately not @MainActor: pure math, so the parity test can
    /// exercise it directly.
    static func quaternion(from euler: EulerAngles) -> simd_quatf {
        let yaw = simd_quatf(angle: Float(euler.yaw), axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(euler.pitch), axis: [1, 0, 0])
        let roll = simd_quatf(angle: Float(euler.roll), axis: [0, 0, 1])
        return yaw * pitch * roll
    }

    @MainActor
    static func apply(_ pose: MascotPose, face: MascotFace, to rig: MascotRig) {
        for (joint, entity) in rig.joints where joint != .root {
            entity.transform.rotation = quaternion(from: pose.angles(joint))
        }
        if let root = rig.joints[.root] {
            // Whole-body orientation composes before the root joint's
            // own angles, exactly as the kit's forward kinematics does.
            root.transform.rotation = quaternion(from: pose.rootRotation)
                * quaternion(from: pose.angles(.root))
            root.position = rig.rootRestPosition + SIMD3<Float>(pose.rootTranslation)
        }

        // The face: openness scales the "+" eyes' vertical strokes (a
        // floor keeps the collapsed stroke reading as a "-", not a gap);
        // tiredness droops the eyes outward.
        let openness = Float(max(face.eyeOpenness, 0.1))
        for bar in rig.eyeVerticalBars {
            bar.scale = [1, openness, 1]
        }
        let droop = Float(face.tiredness) * 0.22
        rig.leftEyePivot.transform.rotation = simd_quatf(angle: -droop, axis: [0, 0, 1])
        rig.rightEyePivot.transform.rotation = simd_quatf(angle: droop, axis: [0, 0, 1])

        // A rigid barbell can't be parented to one hand: it spans both.
        // Solve its transform from the two wrist world positions every
        // frame (kit tests keep the wrists symmetric enough for this).
        if let barbell = rig.barbell,
           let left = rig.joints[.leftWrist]?.position(relativeTo: rig.container),
           let right = rig.joints[.rightWrist]?.position(relativeTo: rig.container) {
            barbell.position = (left + right) / 2 + [0, -0.02, 0.01]
            let span = left - right
            if simd_length(span) > 0.001 {
                barbell.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(span))
            }
        }
    }
}

extension SIMD3<Float> {
    init(_ v: Vec3) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
