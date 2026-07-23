import Foundation

/// Dumbbell lateral raise: a neutral-grip hang at the sides, soft
/// elbows held constant, the arms float out to shoulder height and
/// lower under control. The whole movement is one channel — shoulder
/// abduction (roll) — which is exactly the teaching point: no swing,
/// no shrug, the elbows never bend to cheat the weight up.
enum LateralRaiseMove {
    static let animation: ExerciseAnimation = {
        let legs = MascotPoseBuilder.symmetricLegs(hip: .deg(roll: 4))

        // Neutral grip: wrist yaw -88 spins the handle from the rig's
        // left-right zero to fore-aft (thumb forward), so the palms
        // face the thighs at the hang — and the same fixed wrist reads
        // palm-DOWN at the top, because shoulder roll carries the whole
        // hand with it. One channel moves; everything else is grip.
        func raisePose(shoulderRoll: Double, effort: Double) -> MascotPose {
            MascotPoseBuilder.plantingFeet(MascotPose(
                joints: MascotPoseBuilder.merge(
                    legs,
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(roll: shoulderRoll),
                        elbow: .deg(pitch: -12),
                        wrist: .deg(yaw: -88)
                    )
                ),
                effort: effort
            ))
        }

        // Hang at roll 12 (the curl's thigh-clearance lesson — hanging
        // dumbbells ride just off the legs); top at 86, deltoid height
        // — a lateral raise stops AT the shoulder line, never above.
        let hang = raisePose(shoulderRoll: 12, effort: 0.15)
        let top = raisePose(shoulderRoll: 86, effort: 0.75)
        var squeezeEnd = top
        squeezeEnd.effort = 0.62
        var lowering = top.lerp(to: hang, t: 0.4)
        lowering.effort = 0.3

        return ExerciseAnimation(
            exerciseName: "Lateral Raise",
            style: .reps(repDuration: 2.8),
            repsPerDemoSet: 4,
            // The curl's proven shape: a readable dwell at the hang
            // (wrapping the loop seam), a squeeze-beat at the top that
            // eases off so peak effort lands on the rise, and a lower
            // that takes longer than the raise.
            repKeyframes: [
                MascotKeyframe(t: 0, pose: hang, easing: .hold),
                MascotKeyframe(t: 0.06, pose: hang, easing: .easeInOut),
                MascotKeyframe(t: 0.42, pose: top, easing: .linear),
                MascotKeyframe(t: 0.52, pose: squeezeEnd, easing: .easeInOut),
                MascotKeyframe(t: 0.74, pose: lowering, easing: .easeInOut),
                MascotKeyframe(t: 0.94, pose: hang, easing: .hold),
                MascotKeyframe(t: 1, pose: hang),
            ],
            restBeat: MascotPoseBuilder.tiredBeat(from: hang, to: hang, duration: 2.4),
            cues: [
                MascotCue("Soft bend in the elbows"),
                MascotCue("Float up to shoulder height", window: 0.06...0.42),
                MascotCue("Lower slower than you lifted", window: 0.52...0.94),
            ],
            props: [.dumbbellPair],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.8, restDuration: 2.4, repPhase: 0.9
            ),
            restingPhase: 0.3,
            smoothing: .curved
        )
    }()
}
