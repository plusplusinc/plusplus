import Foundation

/// The authoring vocabulary for exercise animations: pose fragments,
/// symmetry, root solvers, and the shared tired beat. A move file should
/// read as intent (hinge this deep, arms racked, plant the feet) rather
/// than as raw numbers — this is the layer that has to scale from 5
/// authored moves to the whole catalog.
public enum MascotPoseBuilder {

    // MARK: - Pose fragments

    public static func merge(_ fragments: [MascotJoint: EulerAngles]...) -> [MascotJoint: EulerAngles] {
        var result: [MascotJoint: EulerAngles] = [:]
        for fragment in fragments {
            result.merge(fragment) { _, new in new }
        }
        return result
    }

    public static func torso(
        spine: EulerAngles = .zero,
        chest: EulerAngles = .zero,
        neck: EulerAngles = .zero,
        head: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [.spine: spine, .chest: chest, .neck: neck, .head: head]
    }

    /// The same arm on both sides, mirror-symmetric: the right side gets
    /// yaw and roll negated so "splay out" splays out on both.
    public static func symmetricArms(
        shoulder: EulerAngles = .zero,
        elbow: EulerAngles = .zero,
        wrist: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [
            .leftShoulder: shoulder, .leftElbow: elbow, .leftWrist: wrist,
            .rightShoulder: mirroredAngles(shoulder),
            .rightElbow: mirroredAngles(elbow),
            .rightWrist: mirroredAngles(wrist),
        ]
    }

    public static func symmetricLegs(
        hip: EulerAngles = .zero,
        knee: EulerAngles = .zero,
        ankle: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [
            .leftHip: hip, .leftKnee: knee, .leftAnkle: ankle,
            .rightHip: mirroredAngles(hip),
            .rightKnee: mirroredAngles(knee),
            .rightAnkle: mirroredAngles(ankle),
        ]
    }

    // MARK: - Mirroring

    /// Reflection across the sagittal plane: pitch survives, yaw and
    /// roll flip.
    static func mirroredAngles(_ angles: EulerAngles) -> EulerAngles {
        EulerAngles(pitch: angles.pitch, yaw: -angles.yaw, roll: -angles.roll)
    }

    /// The whole pose flipped left-to-right — alternating-side moves
    /// author one side and mirror the other rep.
    public static func mirrored(_ pose: MascotPose) -> MascotPose {
        var flipped: [MascotJoint: EulerAngles] = [:]
        for (joint, angles) in pose.joints {
            flipped[joint.mirrored] = mirroredAngles(angles)
        }
        return MascotPose(
            rootTranslation: Vec3(-pose.rootTranslation.x, pose.rootTranslation.y, pose.rootTranslation.z),
            rootRotation: mirroredAngles(pose.rootRotation),
            joints: flipped,
            effort: pose.effort
        )
    }

    // MARK: - Root solvers

    /// Solves the root translation so the ankles return to their rest
    /// spot (y and z; x stays authored). Author the leg and torso angles,
    /// then let this plant the feet — it is also physically honest: the
    /// hips travel back and down in a squat exactly so the feet DON'T.
    public static func plantingFeet(_ pose: MascotPose, skeleton: MascotSkeleton = .standard) -> MascotPose {
        let rest = skeleton.restPose.jointPositions(skeleton: skeleton)
        let current = pose.jointPositions(skeleton: skeleton)
        guard let restL = rest[.leftAnkle], let restR = rest[.rightAnkle],
              let nowL = current[.leftAnkle], let nowR = current[.rightAnkle] else { return pose }
        let restMean = 0.5 * (restL + restR)
        let nowMean = 0.5 * (nowL + nowR)
        var adjusted = pose
        adjusted.rootTranslation.y += restMean.y - nowMean.y
        adjusted.rootTranslation.z += restMean.z - nowMean.z
        return adjusted
    }

    /// Solves the root translation so the given joints land (in the
    /// least-squares mean) on explicit world targets — how floor work
    /// pins hands and toes to the ground.
    public static func anchored(
        _ pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        anchors: [(MascotJoint, Vec3)]
    ) -> MascotPose {
        guard !anchors.isEmpty else { return pose }
        let current = pose.jointPositions(skeleton: skeleton)
        var delta = Vec3.zero
        for (joint, target) in anchors {
            guard let now = current[joint] else { continue }
            delta = delta + (target - now)
        }
        delta = (1.0 / Double(anchors.count)) * delta
        var adjusted = pose
        adjusted.rootTranslation = adjusted.rootTranslation + delta
        return adjusted
    }

    // MARK: - Spans

    /// Generates the keyframes for a transition between two poses,
    /// re-solving every intermediate sample. Interpolating two planted
    /// poses does NOT keep the feet planted in between (forward
    /// kinematics is nonlinear in the joint angles — the first squat
    /// authored without this drifted its ankles 8 cm mid-descent), so
    /// transitions are baked as short planted paths instead. The easing
    /// is baked into the sampling; emitted keyframes are linear.
    /// `effortKeys` maps span fraction to effort, piecewise linear.
    public static func span(
        from: MascotPose,
        to: MascotPose,
        t0: Double,
        t1: Double,
        steps: Int = 8,
        easing: MascotEasing = .easeInOut,
        effortKeys: [(Double, Double)]? = nil,
        solve: (MascotPose) -> MascotPose = { $0 }
    ) -> [MascotKeyframe] {
        (0...steps).map { i in
            let f = Double(i) / Double(steps)
            var pose = solve(from.lerp(to: to, t: easing.apply(f)))
            if let keys = effortKeys {
                pose.effort = effortValue(at: f, keys: keys)
            }
            return MascotKeyframe(t: t0 + (t1 - t0) * f, pose: pose, easing: .linear)
        }
    }

    static func effortValue(at f: Double, keys: [(Double, Double)]) -> Double {
        guard let first = keys.first else { return 0 }
        if f <= first.0 { return first.1 }
        for (a, b) in zip(keys, keys.dropFirst()) {
            if f <= b.0 {
                let span = b.0 - a.0
                guard span > 0 else { return b.1 }
                return a.1 + (b.1 - a.1) * (f - a.0) / span
            }
        }
        return keys[keys.count - 1].1
    }

    // MARK: - The shared tired beat

    /// The end-of-set beat, HAPPY-TIRED by decree (Dave, build-80
    /// feedback: the first cut's forward slump "looks so sad" — the
    /// mascot should always look happy, even when tired). From the
    /// set's final pose: a small proud "phew" — the head tips UP, the
    /// chest lifts on a slow breath, the shoulders stay open, the body
    /// settles a touch — then it eases back into the set's starting
    /// pose. Never a head-drop, never a shoulder slump. The half-lidded
    /// eyes come from the face channel's tiredness cap (level lids —
    /// serene, not droopy). Endpoint poses match the rep loop's
    /// endpoints exactly, so both seams are continuous.
    public static func tiredBeat(
        from end: MascotPose,
        to start: MascotPose,
        duration: TimeInterval,
        settle: Double = 1
    ) -> ExerciseAnimation.RestBeat {
        func adding(_ base: MascotPose, _ deltas: [(MascotJoint, EulerAngles)], rootLift: Double, effort: Double) -> MascotPose {
            var pose = base
            var joints = pose.joints
            for (joint, delta) in deltas {
                let current = joints[joint] ?? .zero
                joints[joint] = EulerAngles(
                    pitch: current.pitch + delta.pitch,
                    yaw: current.yaw + delta.yaw,
                    roll: current.roll + delta.roll
                )
            }
            pose.joints = joints
            pose.rootTranslation.y += rootLift
            pose.effort = effort
            return pose
        }
        // The phew: chin up, chest proud, arms opening a hair outward.
        let phew = adding(end, [
            (.neck, .deg(pitch: -7 * settle)),
            (.head, .deg(pitch: -3 * settle)),
            (.chest, .deg(pitch: -4 * settle)),
            (.leftShoulder, .deg(roll: 5 * settle)),
            (.rightShoulder, .deg(roll: -5 * settle)),
        ], rootLift: -0.006 * settle, effort: 0.06)
        // The slow exhale: the chest eases back down, still tall.
        let exhale = adding(end, [
            (.neck, .deg(pitch: -4 * settle)),
            (.head, .deg(pitch: -2 * settle)),
            (.chest, .deg(pitch: -1 * settle)),
            (.leftShoulder, .deg(roll: 2 * settle)),
            (.rightShoulder, .deg(roll: -2 * settle)),
        ], rootLift: -0.009 * settle, effort: 0.05)

        return ExerciseAnimation.RestBeat(duration: duration, keyframes: [
            MascotKeyframe(t: 0, pose: end, easing: .easeOut),
            MascotKeyframe(t: 0.32, pose: phew, easing: .easeInOut),
            MascotKeyframe(t: 0.62, pose: exhale, easing: .easeInOut),
            MascotKeyframe(t: 1, pose: start),
        ])
    }

    // MARK: - Toe solve

    /// Solves the (symmetric) ankle pitch so the toes rest on the
    /// floor — the build-80 push-up floated its feet because the ankle
    /// angle was eyeballed. Pure bisection over the FK toe height;
    /// call AFTER any root solve (rotating an ankle never moves the
    /// ankle joint itself).
    /// `nearPitch` narrows the search to a window around a previous
    /// solution — the ankle equation has two roots, and a sequence of
    /// independent solves can hop branches between neighboring samples
    /// (which kinks the sampling spline); seeding keeps a baked path's
    /// ankle continuous.
    public static func solvingToes(
        _ pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        targetToeY: Double = 0.008,
        nearPitch: Double? = nil
    ) -> MascotPose {
        func toeY(anklePitch: Double) -> Double {
            var candidate = pose
            var joints = candidate.joints
            let left = joints[.leftAnkle] ?? .zero
            let right = joints[.rightAnkle] ?? .zero
            joints[.leftAnkle] = EulerAngles(pitch: anklePitch, yaw: left.yaw, roll: left.roll)
            joints[.rightAnkle] = EulerAngles(pitch: anklePitch, yaw: right.yaw, roll: right.roll)
            candidate.joints = joints
            let toes = candidate.toePositions(skeleton: skeleton)
            return min(toes.left.y, toes.right.y)
        }
        // Bracket: toes pointed hard (very negative pitch, lowest toe)
        // vs foot trailing the shin (pitch 0, highest toe). Toe height
        // increases with pitch on this stretch, so bisect accordingly.
        var low = nearPitch.map { $0 - 0.5 } ?? -1.9
        var high = nearPitch.map { min($0 + 0.5, 0) } ?? 0.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if toeY(anklePitch: mid) > targetToeY {
                high = mid
            } else {
                low = mid
            }
        }
        var solved = pose
        var joints = solved.joints
        let pitch = (low + high) / 2
        let left = joints[.leftAnkle] ?? .zero
        let right = joints[.rightAnkle] ?? .zero
        joints[.leftAnkle] = EulerAngles(pitch: pitch, yaw: left.yaw, roll: left.roll)
        joints[.rightAnkle] = EulerAngles(pitch: pitch, yaw: right.yaw, roll: right.roll)
        solved.joints = joints
        return solved
    }

    // MARK: - Blinks

    /// One blink per rep at a low-effort moment, plus two slow blinks in
    /// the tired beat. Returns set-relative centers, sorted.
    public static func defaultBlinkPhases(
        reps: Int,
        repDuration: TimeInterval,
        restDuration: TimeInterval,
        repPhase: Double
    ) -> [Double] {
        let cycle = Double(reps) * repDuration + restDuration
        guard cycle > 0 else { return [] }
        var centers = (0..<reps).map { (Double($0) + repPhase) * repDuration / cycle }
        let workShare = Double(reps) * repDuration / cycle
        let restShare = 1 - workShare
        centers.append(workShare + 0.35 * restShare)
        centers.append(workShare + 0.72 * restShare)
        return centers.sorted()
    }
}
