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

    /// The end-of-set beat (Dave, 2026-07-15): from the set's final pose,
    /// slump — spine and neck give a little, the arms drift, the whole
    /// body settles a centimeter — take a slow breath, then recover into
    /// the set's starting pose. Endpoint poses match the rep loop's
    /// endpoints exactly, so both seams are continuous.
    public static func tiredBeat(
        from end: MascotPose,
        to start: MascotPose,
        duration: TimeInterval,
        slump: Double = 1
    ) -> ExerciseAnimation.RestBeat {
        func slumped(_ base: MascotPose) -> MascotPose {
            var pose = base
            var joints = pose.joints
            func add(_ joint: MascotJoint, _ delta: EulerAngles) {
                let current = joints[joint] ?? .zero
                joints[joint] = EulerAngles(
                    pitch: current.pitch + delta.pitch,
                    yaw: current.yaw + delta.yaw,
                    roll: current.roll + delta.roll
                )
            }
            add(.spine, .deg(pitch: 8 * slump))
            add(.neck, .deg(pitch: 14 * slump))
            add(.leftShoulder, .deg(pitch: -6 * slump))
            add(.rightShoulder, .deg(pitch: -6 * slump))
            pose.joints = joints
            pose.rootTranslation.y -= 0.012 * slump
            pose.effort = 0.08
            return pose
        }
        let low = slumped(end)
        var breath = low
        var breathJoints = breath.joints
        let chest = breathJoints[.chest] ?? .zero
        breathJoints[.chest] = EulerAngles(pitch: chest.pitch - 3 * slump * .pi / 180, yaw: chest.yaw, roll: chest.roll)
        let neck = breathJoints[.neck] ?? .zero
        breathJoints[.neck] = EulerAngles(pitch: neck.pitch - 4 * slump * .pi / 180, yaw: neck.yaw, roll: neck.roll)
        breath.joints = breathJoints
        breath.rootTranslation.y += 0.004 * slump

        return ExerciseAnimation.RestBeat(duration: duration, keyframes: [
            MascotKeyframe(t: 0, pose: end, easing: .easeOut),
            MascotKeyframe(t: 0.3, pose: low, easing: .easeInOut),
            MascotKeyframe(t: 0.55, pose: breath, easing: .easeInOut),
            MascotKeyframe(t: 1, pose: start),
        ])
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
