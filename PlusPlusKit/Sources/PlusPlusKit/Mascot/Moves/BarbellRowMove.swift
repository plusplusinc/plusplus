import Foundation

/// Barbell row: a deadlift-family hinge HELD isometric (80 degrees of
/// torso over bent knees — scanned so the center of mass stays inside
/// `coordinating`'s reach; a shallower-kneed first cut tipped 20 cm
/// behind the heels, past what the servo can correct) while the arms
/// alone row the bar from a hang below the shoulders to the lower
/// belly and lower it back under control.
///
/// Both arm configs are scratch-scan winners in the overhand basin
/// (thumb fully inward, palm exactly on target, servo-matched
/// hand-continues-forearm objective); the deadlift's composed servo
/// (`coordinating` with graze headroom, then `grippingTheBar`) owns
/// every baked sample, so the bar clears the thighs on the way up and
/// the hands keep one station through pull, squeeze, and rest beat.
enum BarbellRowMove {
    static let animation: ExerciseAnimation = {
        let hip = -45.0, knee = 50.0
        let station = 0.22

        func rowPose(
            shoulder: EulerAngles, elbow: EulerAngles, wrist: EulerAngles,
            effort: Double
        ) -> MascotPose {
            MascotPoseBuilder.plantingFeet(MascotPose(
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hip, roll: 4), knee: .deg(pitch: knee),
                        ankle: .deg(pitch: -(hip + knee))
                    ),
                    MascotPoseBuilder.torso(
                        spine: .deg(pitch: 42), chest: .deg(pitch: 38),
                        neck: .deg(pitch: -20), head: .deg(pitch: -6)
                    ),
                    MascotPoseBuilder.symmetricArms(shoulder: shoulder, elbow: elbow, wrist: wrist)
                ),
                effort: effort
            ))
        }

        // Scan winners (one decimal): the hang plumb below the
        // shoulders, the pull landing the bar at the lower belly.
        let hang = rowPose(
            shoulder: .deg(pitch: 11.4, yaw: -79.2, roll: 86.7),
            elbow: .deg(pitch: -6.4, yaw: 7.5),
            wrist: .deg(pitch: -2.6, yaw: -87.0, roll: 5.0),
            effort: 0.35
        )
        let pulled = rowPose(
            shoulder: .deg(pitch: 9.1, yaw: -23.8, roll: 70.0),
            elbow: .deg(pitch: -105.9, yaw: -15.0),
            wrist: .deg(pitch: -13.9, yaw: -88.0, roll: -43.0),
            effort: 0.8
        )

        let solve = { (pose: MascotPose) -> MascotPose in
            MascotPoseBuilder.grippingTheBar(
                MascotPoseBuilder.coordinating(
                    pose, props: [.barbell], equipmentGrazeAtMost: 0.004
                ),
                station: station
            )
        }

        let hangS = solve(hang)
        var repKeyframes = [MascotKeyframe(t: 0, pose: hangS, easing: .hold)]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: hang, to: pulled, t0: 0.06, t1: 0.36, steps: 8,
            effortKeys: [(0, 0.35), (0.7, 0.85), (1, 0.7)],
            solve: solve
        ))
        var squeezeEnd = solve(pulled)
        squeezeEnd.effort = 0.6
        repKeyframes.append(MascotKeyframe(t: 0.50, pose: squeezeEnd, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: pulled, to: hang, t0: 0.50, t1: 0.94, steps: 8,
            effortKeys: [(0, 0.5), (1, 0.35)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: hangS))

        return ExerciseAnimation(
            exerciseName: "Barbell Row",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            // The phew at reduced settle (a hinged chest lift levers
            // the hanging bar, the deadlift lesson), with the servo
            // re-pinning the grip so the one-station law holds through
            // the rest beat's breath.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: hangS, to: hangS, duration: 2.6, settle: 0.55,
                solve: { pose in
                    MascotPoseBuilder.grippingTheBar(pose, station: station)
                }
            ),
            cues: [
                MascotCue("Flat back, hinge held still"),
                MascotCue("Pull to your belly", window: 0.06...0.36),
                MascotCue("Lower with control", window: 0.5...0.94),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.6, repPhase: 0.98
            ),
            restingPhase: 0.28,
            smoothing: .curved
        )
    }()
}
