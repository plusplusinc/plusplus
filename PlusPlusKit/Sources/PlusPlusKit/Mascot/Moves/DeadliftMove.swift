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
        // The path servo (MascotPoseBuilder.coordinating): the bar
        // swings AROUND the shins instead of through them (a lerp
        // between the legal endpoints dragged it 2.3 cm into the knees
        // mid-hinge) and the center of mass stays over the feet — the
        // continuous coordination a real lifter does by feel. Identity
        // at the endpoints, so the pause seams stay exact.
        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.coordinating(
                pose, props: [.barbell], equipmentGrazeAtMost: 0.005
            )
        }

        let lockout = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsLockout, armsLockout),
            effort: 0.3
        ))
        let bottom = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, armsBottom),
            effort: 0.5
        ))
        // The standard rep cycle (slow eccentric down to the floor, a
        // beat to set the grip, the pull with the hardest effort of
        // any move). Densely baked: the servo only speaks at the
        // knots, and with 8 of them the spline dipped the bar 1.5 cm
        // back into the legs BETWEEN samples — 24 pin the path to the
        // servo's line.
        let repKeyframes = MascotPoseBuilder.repCycle(
            top: lockout, bottom: bottom, steps: 24,
            topEffort: 0.3, bottomEffort: 0.5, driveEffort: 0.95, settleEffort: 0.45,
            solve: solve
        )

        return ExerciseAnimation(
            exerciseName: "Deadlift",
            style: .reps(repDuration: 3.5),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: lockout, to: lockout, duration: 2.8),
            cues: [
                MascotCue("Flat back, chest proud"),
                MascotCue("Bar close to the body"),
                MascotCue("Hips hinge back", window: 0.03...0.46),
                MascotCue("Push the floor away", window: 0.56...0.9),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.5, restDuration: 2.8, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
