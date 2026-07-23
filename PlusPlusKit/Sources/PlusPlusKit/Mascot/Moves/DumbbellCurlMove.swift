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

        // Full ROM (Dave's depth round): near-full extension at the
        // bottom (-5, a soft elbow, never a slammed lockout) up to a
        // -132 squeeze at the top — both ends invariant-enforced.
        let start = standingPose(shoulderPitch: 0, elbowPitch: -5, effort: 0.15)
        let topOfCurl = standingPose(shoulderPitch: -10, elbowPitch: -132, effort: 0.78)

        return ExerciseAnimation(
            exerciseName: "Dumbbell Curl",
            style: .reps(repDuration: 2.6),
            repsPerDemoSet: 4,
            // The lift-first archetype (this move authored it; it now
            // lives in MascotPoseBuilder): bottom dwell wrapping the
            // seam, rise, squeeze whose effort eases off so the peak
            // lands on the concentric, slow lower.
            repKeyframes: MascotPoseBuilder.liftCycle(
                bottom: start, top: topOfCurl,
                bottomEffort: 0.15, topEffort: 0.78, squeezeEffort: 0.68, loweringEffort: 0.35
            ),
            restBeat: MascotPoseBuilder.tiredBeat(from: start, to: start, duration: 2.4),
            cues: [
                MascotCue("Elbows pinned to your sides"),
                MascotCue("Squeeze at the top", window: 0.26...0.58),
                MascotCue("Lower with control", window: 0.58...0.94),
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
