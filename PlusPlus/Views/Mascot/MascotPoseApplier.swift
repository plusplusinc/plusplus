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
        // floor keeps the collapsed stroke reading as a "-", not a
        // gap). Tired lids stay LEVEL — half-closed reads serene; the
        // build-80 droop tilt read sad, and this mascot is always
        // happy.
        let openness = Float(max(face.eyeOpenness, 0.1))
        for bar in rig.eyeVerticalBars {
            bar.scale = [1, openness, 1]
        }

        // A rigid two-hand prop can't be parented to one hand: it
        // spans both. Solve its transform from the two PALM centers
        // every frame — the palms are where the grip closes, so the
        // thing sits inside the wrapped (or cupping) hands in every
        // orientation. MascotGrip is the shared contract with the
        // kit's equipment-collision invariant: the proof and the
        // pixels use the same geometry, mirroring `equipmentCapsules`.
        if let (kind, entity) = rig.heldEquipment,
           let leftWrist = rig.joints[.leftWrist],
           let rightWrist = rig.joints[.rightWrist] {
            let palmOffset = SIMD3<Float>(MascotGrip.palmOffset)
            let left = leftWrist.convert(position: palmOffset, to: rig.container)
            let right = rightWrist.convert(position: palmOffset, to: rig.container)
            let mid = (left + right) / 2
            let span = left - right
            // The hands' mean fist line (local -y in each wrist frame),
            // for props that hang off or continue the grip.
            func handDown(_ wrist: Entity) -> SIMD3<Float> {
                wrist.convert(position: [0, -1, 0], to: rig.container)
                    - wrist.convert(position: .zero, to: rig.container)
            }
            let meanDown = handDown(leftWrist) + handDown(rightWrist)
            // The mean palm NORMAL (local +z) — what cupped palms face.
            func palmNormal(_ wrist: Entity) -> SIMD3<Float> {
                wrist.convert(position: [0, 0, 1], to: rig.container)
                    - wrist.convert(position: .zero, to: rig.container)
            }
            let meanNormal = palmNormal(leftWrist) + palmNormal(rightWrist)

            switch kind {
            case .barbell:
                entity.position = mid
                if simd_length(span) > 0.001 {
                    entity.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(span))
                }
            case .kettlebell:
                entity.position = mid
                if simd_length(span) > 0.001, simd_length(meanDown) > 0.001 {
                    let x = simd_normalize(span)
                    let downOrth = meanDown - simd_dot(meanDown, x) * x
                    if simd_length(downOrth) > 0.001 {
                        let y = -simd_normalize(downOrth)
                        let z = simd_normalize(simd_cross(x, y))
                        entity.orientation = simd_quatf(simd_float3x3(columns: (x, y, z)))
                    }
                }
            case .gobletDumbbell:
                if simd_length(meanNormal) > 0.001 {
                    // The shaft hangs OPPOSITE the cupped palms' mean
                    // normal (the fist line is the finger direction —
                    // horizontal in a cup, the sideways-dumbbell bug);
                    // top head's CENTER rides half a head-width above
                    // the palm support point — matching the kit's
                    // capsule model.
                    let down = -simd_normalize(meanNormal)
                    entity.position = mid - Float(MascotGrip.dumbbellHeadHalfWidth) * down
                    entity.orientation = simd_quatf(from: [0, -1, 0], to: down)
                }
            default:
                break
            }
        }
    }
}

extension SIMD3<Float> {
    init(_ v: Vec3) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
