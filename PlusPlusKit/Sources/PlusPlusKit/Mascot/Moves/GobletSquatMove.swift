import Foundation

/// Goblet squat: a single dumbbell held vertically, its top head
/// CUPPED on upturned palms at the sternum, through the squat
/// family's below-parallel descent — torso more upright than the back
/// squat because the load counterweights in front. The hands are the
/// catalog's first `.cupped` pair: the same flat-hand geometry as the
/// planted palm, turned skyward under a weight.
///
/// The cup arms came from `plantingPalms` run with an upward palm
/// normal (the push-up's whole-arm servo reused for a non-floor flat
/// hand), then frozen: palm normal (0.08, 1.00, -0.01), palms 39 mm
/// each side of the midline so the head truly rests on both, and the
/// bell's top head 5.4 mm clear of the chest — a snug hold inside the
/// graze law. Arms ride the chest rigidly, so the hold survives the
/// whole rep by construction.
enum GobletSquatMove {
    static let animation: ExerciseAnimation = {
        // The frozen cup (plantingPalms winner, one decimal). Wrist
        // roll pulled 43 -> 39: the articulation round caps deviation
        // at a human 40; the cupped hold's own capsule law verifies
        // the bell still sits snug.
        let arms = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -35.6, yaw: -44.5, roll: 16.7),
            elbow: .deg(pitch: -122.0, yaw: -11.6),
            wrist: .deg(pitch: 51.7, yaw: 26.1, roll: 39.0)
        )
        let legsStanding = MascotPoseBuilder.symmetricLegs(hip: .deg(roll: 3))
        // The squat family's below-parallel bottom; ankle cancels the
        // accumulated shin lean so the feet stay flat.
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -100, roll: 3),
            knee: .deg(pitch: 135),
            ankle: .deg(pitch: -35)
        )
        // Upright torso both ends — the front-held bell balances the
        // hips' travel, which is the goblet squat's whole point.
        let torsoStanding = MascotPoseBuilder.torso(
            spine: .deg(pitch: 4), chest: .deg(pitch: 3), neck: .deg(pitch: -5)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: 18), chest: .deg(pitch: 12), neck: .deg(pitch: -10)
        )

        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.coordinating(
                pose, props: [.gobletDumbbell], equipmentGrazeAtMost: 0.005
            )
        }

        let standing = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsStanding, torsoStanding, arms),
            effort: 0.25
        ))
        let bottom = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, arms),
            effort: 0.6
        ))
        let repKeyframes = MascotPoseBuilder.repCycle(
            top: standing, bottom: bottom,
            topEffort: 0.25, bottomEffort: 0.6, driveEffort: 0.88, settleEffort: 0.4,
            solve: solve
        )

        return ExerciseAnimation(
            exerciseName: "Goblet Squat",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: standing, to: standing, duration: 2.6),
            cues: [
                MascotCue("Hug the weight at your chest"),
                MascotCue("Sit down between the heels", window: 0.03...0.45),
                MascotCue("Drive up tall", window: 0.55...0.95),
            ],
            props: [.gobletDumbbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.6, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
