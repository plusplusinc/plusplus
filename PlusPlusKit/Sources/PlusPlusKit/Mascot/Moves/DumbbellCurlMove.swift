import Foundation

/// Dumbbell curl, both arms: elbows pinned to the sides fold the
/// forearms up to the shoulders, a squeeze at the top, then a slow
/// controlled eccentric. The dumbbells parent to the wrists app-side.
enum DumbbellCurlMove {
    static let animation: ExerciseAnimation = {
        let stanceRoll = 4.0
        let legs = MascotPoseBuilder.symmetricLegs(hip: .deg(roll: stanceRoll))

        func standingPose(shoulderPitch: Double, elbowPitch: Double, effort: Double) -> MascotPose {
            // Arms ride slightly abducted (roll 12) so the hanging
            // dumbbells clear the thighs — the collision invariant
            // caught the inner heads 3.4 cm inside the legs when the
            // arms hung straight down.
            MascotPoseBuilder.plantingFeet(MascotPose(
                joints: MascotPoseBuilder.merge(
                    legs,
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: shoulderPitch, roll: 12),
                        elbow: .deg(pitch: elbowPitch)
                    )
                ),
                effort: effort
            ))
        }

        let start = standingPose(shoulderPitch: 0, elbowPitch: -8, effort: 0.15)
        let topOfCurl = standingPose(shoulderPitch: -10, elbowPitch: -125, effort: 0.75)
        var lowering = topOfCurl.lerp(to: start, t: 0.4)
        lowering.effort = 0.35

        return ExerciseAnimation(
            exerciseName: "Dumbbell Curl",
            style: .reps(repDuration: 2.6),
            repsPerDemoSet: 4,
            repKeyframes: [
                MascotKeyframe(t: 0, pose: start, easing: .easeInOut),
                MascotKeyframe(t: 0.38, pose: topOfCurl, easing: .hold),
                MascotKeyframe(t: 0.48, pose: topOfCurl, easing: .easeInOut),
                MascotKeyframe(t: 0.72, pose: lowering, easing: .easeInOut),
                MascotKeyframe(t: 1, pose: start),
            ],
            restBeat: MascotPoseBuilder.tiredBeat(from: start, to: start, duration: 2.4),
            cues: [
                MascotCue("Elbows pinned to your sides"),
                MascotCue("Squeeze at the top", window: 0.22...0.55),
                MascotCue("Lower with control", window: 0.58...0.98),
            ],
            props: [.dumbbellPair],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.6, restDuration: 2.4, repPhase: 0.9
            ),
            restingPhase: 0.38,
            smoothing: .curved
        )
    }()
}
