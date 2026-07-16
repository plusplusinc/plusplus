import Foundation

/// Conventional deadlift: hinge back with a flat back until the bar (in
/// hanging arms) reaches the shins, a beat to set the grip, then the
/// pull with the hardest effort of any move, into a tall lockout.
enum DeadliftMove {
    static let animation: ExerciseAnimation = {
        let stanceRoll = 4.0
        // The chunky bot's arms are short, so the hinge runs deep (78
        // degrees of torso) to get the hanging bar down to the knees.
        let spinePitch = 40.0
        let chestPitch = 38.0

        let legsLockout = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -55, roll: stanceRoll),
            knee: .deg(pitch: 67),
            ankle: .deg(pitch: -12)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: spinePitch),
            chest: .deg(pitch: chestPitch),
            neck: .deg(pitch: -38),
            head: .deg(pitch: -12)
        )
        // Arms hang a few degrees forward of plumb: with the bot's
        // short arms the bar sits AT knee height, and truly vertical
        // arms would drag it through the knee line (the collision
        // invariant caught 3.9 cm of bar-into-thigh).
        let armsBottom = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -(spinePitch + chestPitch) - 8)
        )

        // Lockout arms sit ~16 degrees forward so the bar rests against
        // the FRONT of the thighs (build-80: straight-down arms put the
        // bar inside the belly; the clearance invariant now forbids it).
        let armsLockout = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -16)
        )
        let lockout = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(legsLockout, armsLockout),
            effort: 0.3
        ))
        let bottom = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, armsBottom),
            effort: 0.5
        ))
        // Hinge down and pull up as baked planted paths; a beat at the
        // bar to set the grip, a beat at the top.
        var repKeyframes = MascotPoseBuilder.span(
            from: lockout, to: bottom, t0: 0, t1: 0.4,
            effortKeys: [(0, 0.3), (1, 0.5)],
            solve: { MascotPoseBuilder.plantingFeet($0) }
        )
        repKeyframes.append(MascotKeyframe(t: 0.5, pose: bottom, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: lockout, t0: 0.5, t1: 0.88,
            easing: .easeOut,
            effortKeys: [(0, 0.5), (0.4, 0.95), (1, 0.45)],
            solve: { MascotPoseBuilder.plantingFeet($0) }
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: lockout))

        return ExerciseAnimation(
            exerciseName: "Deadlift",
            style: .reps(repDuration: 3.5),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: lockout, to: lockout, duration: 2.8),
            cues: [
                MascotCue("Hips hinge back", window: 0.05...0.35),
                MascotCue("Flat back, chest proud", window: 0.2...0.5),
                MascotCue("Push the floor away", window: 0.5...0.8),
                MascotCue("Stand tall at the top", window: 0.82...1.0),
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
