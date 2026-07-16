import Foundation

/// Barbell back squat: bar racked across the shoulders (wrists just
/// behind the neck), hips travel back and down, knees track forward,
/// drive up through the heels with the effort spike on the ascent.
enum SquatMove {
    static let animation: ExerciseAnimation = {
        // Kept small: roll composed with a deep hip hinge slides the
        // ankles laterally (the planted solver can only pin the mean),
        // and the stance width already comes from the hip offsets.
        let stanceRoll = 3.0
        // Rack hold, v2 (build-80: "arms look extremely uncomfortable"):
        // upper arms tucked closer (32 degrees out), elbows folded so
        // the forearms rise just behind the shoulders, wrists cocked
        // back so the palms face up under the bar.
        let arms = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: 14, roll: 18),
            elbow: .deg(pitch: 155),
            wrist: .deg(pitch: -8)
        )
        let legsStanding = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        // Textbook bottom geometry (build-80: "looks like it would
        // fall backwards" — thighs past horizontal shoved the hips 33
        // cm back and nothing could counterbalance): thighs stop just
        // above parallel (70 degrees), shins lean 22 (knees over
        // toes), torso leans 45 — which lands the center of mass AND
        // the bar over the midfoot. Both are enforced by invariants.
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -70, roll: stanceRoll),
            knee: .deg(pitch: 98),
            ankle: .deg(pitch: 28)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: 26),
            chest: .deg(pitch: 19),
            neck: .deg(pitch: -30),
            head: .deg(pitch: -8)
        )

        let standing = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(legsStanding, arms),
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
                MascotCue("Feet shoulder width", window: 0.0...0.15),
                MascotCue("Hips back, chest up", window: 0.1...0.42),
                MascotCue("Knees track over toes", window: 0.28...0.6),
                MascotCue("Drive through heels", window: 0.55...0.92),
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
