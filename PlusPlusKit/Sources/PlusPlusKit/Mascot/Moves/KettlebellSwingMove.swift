import Foundation

/// Kettlebell swing (hardstyle): each rep starts and ends STANDING
/// with the bell hanging at the groin — the only place a bell can
/// actually rest. A hip hinge hikes it back between the legs, the
/// hips snap through, and the bell FLOATS at chest height for one
/// weightless beat before falling back into the stand. The float is a
/// TURNAROUND, never a hold: the physics round (build-117, Dave: "fix
/// the kettlebell swing and physics") retired the old cycle that
/// parked at the float — a motionless horizontal bell is a levitation,
/// and the rest beat used to breathe there for seconds. The float key
/// also carries a small hip-extension counterlean, so the combined
/// body-plus-bell center of mass stays centered while the bell is out
/// (the ZMP law measures the whole cycle's dynamic balance).
///
/// Scan notes: the two-hand narrow grip lives at shoulder yaw -24/-26
/// (palms 4-17 mm off the midline; a scan at -60 crossed the forearms
/// 39 mm into each other); the hike keeps the bell 130 mm clear of
/// the thighs; the stand's analytic wrist (13.7, 24.0, 12.1) holds
/// the hanging grip at 0.0 degrees off the handle axis with the bell
/// 53 mm clear of the body.
enum KettlebellSwingMove {
    static let animation: ExerciseAnimation = {
        func swingPose(
            spine: Double, chest: Double, neck: Double,
            hip: Double, knee: Double,
            shoulder: EulerAngles, wrist: EulerAngles,
            effort: Double
        ) -> MascotPose {
            MascotPose(
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hip, roll: 6), knee: .deg(pitch: knee),
                        ankle: .deg(pitch: -(hip + knee))
                    ),
                    MascotPoseBuilder.torso(
                        spine: .deg(pitch: spine), chest: .deg(pitch: chest),
                        neck: .deg(pitch: neck)
                    ),
                    MascotPoseBuilder.symmetricArms(
                        shoulder: shoulder, elbow: .deg(pitch: -8),
                        wrist: wrist
                    )
                ),
                effort: effort
            )
        }

        // The STAND: tall, bell hanging in front of the thighs — where
        // a rep begins, ends, and rests.
        let stand = swingPose(
            spine: 4, chest: 2, neck: -2, hip: -4, knee: 8,
            shoulder: .deg(pitch: -22, yaw: -24),
            // The analytic wrist for the hanging grip (probe winner:
            // misalignment 0.0 degrees on the handle axis).
            wrist: .deg(pitch: 13.7, yaw: 24.0, roll: 12.1),
            effort: 0.2
        )
        // The FLOAT: standing plank, arms horizontal, bell chest-high
        // for one weightless beat. Hip extension leans the trunk back
        // a touch — the counterweight to the outstretched bell.
        let float = swingPose(
            spine: -2, chest: 0, neck: -4, hip: 3, knee: 4,
            shoulder: .deg(pitch: -85, yaw: -24),
            // Analytic wrap alignment: chain-inverse times the
            // palm-down/fingers-forward hand puts the grip channel
            // EXACTLY on the world-x handle (the closed-form move the
            // aligningGrip lesson demands — the whole-arm servo kept
            // parking 20 mm deep in a wrong wrap basin here).
            wrist: .deg(pitch: 3.0, roll: 24.0),
            effort: 0.35
        )
        // The hike: a soft-kneed hinge, arms swept back so the bell
        // rides between and just behind the knees.
        let back = swingPose(
            spine: 40, chest: 30, neck: -28, hip: -25, knee: 25,
            shoulder: .deg(pitch: -68, yaw: -26),
            wrist: .deg(pitch: -14.0, roll: 26.0),
            effort: 0.5
        )

        // The barbell moves' whole-hand servo, on the short handle:
        // per baked sample it pins each palm to its station (0.02 —
        // the two hands squeeze together on one handle) and aligns
        // the grip channel to the handle axis. Without it the hanging
        // arms' ~25-degree wrap skew ran a finger capsule 10 mm
        // through the handle (swift-reviewer coverage catch — the
        // finger law had been silently skipping kettlebell capsules).
        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.coordinating(pose, props: [.kettlebell])
        }

        let standS = solve(stand)
        let backS = solve(back)
        let floatS = solve(float)
        var repKeyframes = [MascotKeyframe(t: 0, pose: standS, easing: .hold)]
        // Stand -> hike rides gravity (easeIn, the bell accelerating
        // down and back), a beat at the back turnaround, the SNAP off
        // the hips (easeOut: explosive start, coasting up into the
        // float), one weightless beat, then the bell FALLS back into
        // the stand (easeIn again — gravity owns the way down).
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: stand, to: back, t0: 0.04, t1: 0.30, steps: 7,
            easing: .easeIn,
            effortKeys: [(0, 0.25), (1, 0.5)],
            solve: solve
        ))
        repKeyframes.append(MascotKeyframe(t: 0.38, pose: backS, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: back, to: float, t0: 0.38, t1: 0.64, steps: 7,
            easing: .easeOut,
            effortKeys: [(0, 0.6), (0.4, 0.95), (1, 0.4)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 0.70, pose: floatS, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: float, to: stand, t0: 0.70, t1: 0.96, steps: 7,
            easing: .easeIn,
            effortKeys: [(0, 0.35), (1, 0.22)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: standS))

        return ExerciseAnimation(
            exerciseName: "Kettlebell Swing",
            style: .reps(repDuration: 2.2),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            // The phew happens at the STAND, arms down — a bell can
            // hang there all day (the old beat breathed at the float,
            // levering a horizontal bell for seconds).
            restBeat: MascotPoseBuilder.tiredBeat(
                from: standS, to: standS, duration: 2.4, settle: 0.8
            ),
            cues: [
                MascotCue("A hinge, not a squat"),
                MascotCue("Hike the bell back", window: 0.04...0.38),
                MascotCue("Snap the hips through", window: 0.38...0.70),
            ],
            props: [.kettlebell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.2, restDuration: 2.4, repPhase: 0.98
            ),
            restingPhase: 0.0,
            smoothing: .curved
        )
    }()
}
