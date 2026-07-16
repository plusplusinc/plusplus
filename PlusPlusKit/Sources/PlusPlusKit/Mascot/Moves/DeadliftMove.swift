import Foundation

/// Conventional deadlift: hinge back with a flat back until the bar (in
/// hanging arms) reaches the shins, a beat to set the grip, then the
/// pull with the hardest effort of any move, into a tall lockout.
enum DeadliftMove {
    static let animation: ExerciseAnimation = {
        let stanceRoll = 4.0
        // Full-ROM bottom (Dave's depth round): the bar starts FROM THE
        // FLOOR — plates about 8 mm off the ground at the catch — not
        // from knee height (that was a rack pull wearing a deadlift's
        // name). The chunky bot reaches it with a deep hinge (85
        // degrees of torso) plus real knee bend, found by the same
        // numeric scan discipline as the squat: every candidate held
        // balance, bar-over-midfoot, shin clearance, and legal joints
        // simultaneously.
        let spinePitch = 45.0
        let chestPitch = 40.0

        let legsLockout = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -92, roll: stanceRoll),
            knee: .deg(pitch: 112),
            ankle: .deg(pitch: -20)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: spinePitch),
            chest: .deg(pitch: chestPitch),
            neck: .deg(pitch: -38),
            head: .deg(pitch: -12)
        )
        // Arms hang a few degrees forward of plumb so the bar clears
        // the shins by millimeters instead of dragging through them
        // (the collision invariant caught 3.9 cm of bar-into-thigh in
        // an earlier cut with more forward push).
        let armsBottom = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -(spinePitch + chestPitch) - 3)
        )

        // Lockout arms sit ~15 degrees forward so the bar rests against
        // the FRONT of the thighs (build-80: straight-down arms put the
        // bar inside the belly; the clearance invariant now forbids it).
        // Not a degree more: the tired beat's chest lift swings the
        // hanging bar forward, and at -16 the swing crossed the
        // bar-over-midfoot bound by a millimeter.
        let armsLockout = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -15)
        )
        // A lerp between the legal endpoints drags the hanging bar
        // THROUGH the knees mid-hinge (the full-depth bottom made it
        // 2.3 cm at the worst sample) and lets the center of mass sag
        // behind the heels — a real lifter swings the bar around the
        // shins and keeps the weight over the feet by feel; this solve
        // is that feel: at every baked sample, ease the shoulders
        // forward until the bar clears the leg capsules to grazing
        // depth, and lean the spine until the center of mass rides
        // over the support polygon. Identity at the endpoints (both
        // already clear and balanced), so the seams stay exact.
        func clearingTheLegs(_ raw: MascotPose) -> MascotPose {
            var candidate = MascotPoseBuilder.plantingFeet(raw)
            for _ in 0..<24 {
                let pen = MascotCollision.maxEquipmentPenetration(pose: candidate, props: [.barbell]).depth
                let frames = candidate.jointFrames(skeleton: .standard)
                let ankleZ = 0.5 * (frames[.leftAnkle]!.position.z + frames[.rightAnkle]!.position.z)
                let comZ = MascotBalance.centerOfMass(pose: candidate, props: [.barbell]).z
                let barInsideLegs = pen > 0.005
                let comBehindHeels = comZ - ankleZ < -0.058
                if !barInsideLegs && !comBehindHeels { break }
                var joints = candidate.joints
                if barInsideLegs {
                    for joint in [MascotJoint.leftShoulder, .rightShoulder] {
                        let a = joints[joint] ?? .zero
                        joints[joint] = EulerAngles(pitch: a.pitch - 0.01, yaw: a.yaw, roll: a.roll)
                    }
                } else {
                    let spine = joints[.spine] ?? .zero
                    joints[.spine] = EulerAngles(pitch: spine.pitch + 0.01, yaw: spine.yaw, roll: spine.roll)
                }
                candidate.joints = joints
                candidate = MascotPoseBuilder.plantingFeet(candidate)
            }
            return candidate
        }

        // Endpoints run through the SAME solve as the path samples
        // (identity when already clear, which the scanned poses are)
        // so the pause keyframes stay exact copies — the spline's
        // stillness detection depends on it.
        let lockout = clearingTheLegs(MascotPose(
            joints: MascotPoseBuilder.merge(legsLockout, armsLockout),
            effort: 0.3
        ))
        let bottom = clearingTheLegs(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, armsBottom),
            effort: 0.5
        ))
        // Hinge down and pull up as baked planted paths; a beat at the
        // bar to set the grip, a beat at the top.
        // Dense baking: the servo only speaks at the knots, and with 8
        // of them the spline dipped the bar 1.5 cm back into the legs
        // BETWEEN samples. 24 knots pin the path to the servo's line.
        var repKeyframes = MascotPoseBuilder.span(
            from: lockout, to: bottom, t0: 0, t1: 0.4, steps: 24,
            effortKeys: [(0, 0.3), (1, 0.5)],
            solve: clearingTheLegs
        )
        repKeyframes.append(MascotKeyframe(t: 0.5, pose: bottom, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: lockout, t0: 0.5, t1: 0.88, steps: 24,
            easing: .easeOut,
            effortKeys: [(0, 0.5), (0.4, 0.95), (1, 0.45)],
            solve: clearingTheLegs
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: lockout))

        return ExerciseAnimation(
            exerciseName: "Deadlift",
            style: .reps(repDuration: 3.5),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: lockout, to: lockout, duration: 2.8),
            cues: [
                MascotCue("Flat back, chest proud"),
                MascotCue("Bar close to the body"),
                MascotCue("Hips hinge back", window: 0.03...0.4),
                MascotCue("Push the floor away", window: 0.5...0.85),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.5, restDuration: 2.8, repPhase: 0.04
            ),
            restingPhase: 0.4,
            smoothing: .curved
        )
    }()
}
