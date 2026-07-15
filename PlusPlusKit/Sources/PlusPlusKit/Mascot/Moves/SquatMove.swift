import Foundation

/// Barbell back squat: bar racked across the shoulders (wrists just
/// behind the neck), hips travel back and down, knees track forward,
/// drive up through the heels with the effort spike on the ascent.
enum SquatMove {
    static let animation: ExerciseAnimation = {
        let stanceRoll = 6.0
        // Rack hold: upper arms out about 55 degrees, forearms folded up
        // and BACK (positive elbow pitch) so the wrists sit behind the
        // neck at shoulder height and the bar reads across the traps.
        let arms = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: 15, roll: 55),
            elbow: .deg(pitch: 120)
        )
        let legsStanding = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -90, roll: stanceRoll),
            knee: .deg(pitch: 78),
            ankle: .deg(pitch: 14)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: 18),
            chest: .deg(pitch: 12),
            neck: .deg(pitch: -20),
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
            restingPhase: 0.42
        )
    }()
}
