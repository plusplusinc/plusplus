import Foundation

/// Barbell back squat: the bar racked ON the traps behind the neck,
/// hips travel back and down, knees track forward, drive up through
/// the heels with the effort spike on the ascent.
enum SquatMove {
    static let animation: ExerciseAnimation = {
        // Kept small: roll composed with a deep hip hinge slides the
        // ankles laterally (the planted solver can only pin the mean),
        // and the stance width already comes from the hip offsets.
        let stanceRoll = 3.0
        // BACK-rack hold, v4. v3 shipped a front rack because the old
        // rig couldn't reach behind the neck with legal joints — the
        // real fix (Dave: the mascot can do ALL human movements) was
        // giving the skeleton the shoulder girdle a back rack leans
        // on. With clavicle retraction + a modest shrug the numeric
        // scan lands the palms ON the bar line at the traps (a
        // deliberate ~6 mm graze — a back-squat bar RESTS there), the
        // grip axis within 4 degrees of the bar, elbows folded the
        // proper way pointing down-back. Every angle below is inside
        // the anatomical table in MascotMovesTests.
        let arms = MascotPoseBuilder.symmetricArms(
            clavicle: .deg(yaw: 20.4, roll: 2.8),
            shoulder: .deg(yaw: 85.3, roll: -0.4),
            elbow: .deg(pitch: -143.5),
            wrist: .deg(pitch: 47.2, yaw: -35.4, roll: 42)
        )
        let legsStanding = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        // Textbook bottom geometry (build-80: "looks like it would
        // fall backwards" — thighs past horizontal shoved the hips 33
        // cm back and nothing could counterbalance): thighs stop just
        // above parallel (70 degrees), shins lean 22 (knees over
        // toes). Ankle CANCELS the accumulated shin lean (hip -70 +
        // knee 98 = +28) so the feet stay FLAT on the floor — round 2
        // shipped the sign flipped and the heels visibly dug through
        // the floor (the sole-corner floor invariant now catches it).
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -70, roll: stanceRoll),
            knee: .deg(pitch: 98),
            ankle: .deg(pitch: -28)
        )
        // The torso lean is what keeps the TRAP-racked bar over the
        // midfoot as the hips travel back — a back squat leans further
        // than a front squat by design. Both bar path and the center
        // of mass are invariant-enforced. The STANDING hold carries a
        // subtle lean too: this bot's chest is deep (its spine is the
        // body's centerline, not dorsal like a human's), so a trap
        // rack sits ~10 cm behind the neck axis — the slight incline
        // is what a lifter does under the same constraint, and it
        // brings the loaded bar back over the foot.
        let torsoStanding = MascotPoseBuilder.torso(
            spine: .deg(pitch: 5),
            chest: .deg(pitch: 4),
            neck: .deg(pitch: -5),
            head: .deg(pitch: -2)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: 29),
            chest: .deg(pitch: 21),
            neck: .deg(pitch: -16),
            head: .deg(pitch: -5)
        )

        let standing = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(legsStanding, torsoStanding, arms),
            effort: 0.25
        ))
        let bottom = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, arms),
            effort: 0.6
        ))
        // Descent and drive are baked planted paths (see span()); the
        // pause at depth and the settle at the top are plain keyframes.
        var repKeyframes = MascotPoseBuilder.span(
            from: standing, to: bottom, t0: 0, t1: 0.42,
            effortKeys: [(0, 0.25), (1, 0.6)],
            solve: { MascotPoseBuilder.plantingFeet($0) }
        )
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: bottom, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: standing, t0: 0.52, t1: 0.9,
            easing: .easeOut,
            effortKeys: [(0, 0.6), (0.45, 0.9), (1, 0.4)],
            solve: { MascotPoseBuilder.plantingFeet($0) }
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: standing))

        return ExerciseAnimation(
            exerciseName: "Squat",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: standing, to: standing, duration: 2.6),
            cues: [
                MascotCue("Feet shoulder width"),
                MascotCue("Knees track over toes"),
                MascotCue("Hips back and down", window: 0.03...0.45),
                MascotCue("Drive through heels", window: 0.55...0.95),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.6, repPhase: 0.04
            ),
            restingPhase: 0.42,
            smoothing: .curved
        )
    }()
}
