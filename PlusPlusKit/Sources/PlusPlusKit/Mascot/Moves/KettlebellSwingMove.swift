import Foundation

/// Kettlebell swing (hardstyle): both hands close together on the one
/// short handle, a hip HINGE hikes the bell back between the legs,
/// then the hips snap through to a standing plank with the bell
/// floating at chest height. The bell hangs off the hands' mean fist
/// line in both the collision model and the renderer — at the float
/// it continues the horizontal arms, which is exactly where
/// centrifugal force holds a real bell.
///
/// Scan notes: the two-hand narrow grip lives at shoulder yaw -24/-26
/// (palms 4-17 mm off the midline; a scan at -60 crossed the forearms
/// 39 mm into each other), the hike keeps the bell 130 mm clear of
/// the thighs, and the float's forward bell shifts the center of mass
/// +0.05 — still well inside the toe-side support bound.
enum KettlebellSwingMove {
    static let animation: ExerciseAnimation = {
        func swingPose(
            spine: Double, chest: Double, neck: Double,
            hip: Double, knee: Double,
            shoulder: EulerAngles, wristPitch: Double,
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
                        wrist: .deg(pitch: wristPitch)
                    )
                ),
                effort: effort
            )
        }

        // The float: standing plank, arms horizontal, bell chest-high.
        let top = swingPose(
            spine: 0, chest: 0, neck: -4, hip: 0, knee: 4,
            shoulder: .deg(pitch: -85, yaw: -24), wristPitch: 0,
            effort: 0.35
        )
        // The hike: a soft-kneed hinge, arms swept back so the bell
        // rides between and just behind the knees.
        let back = swingPose(
            spine: 40, chest: 30, neck: -28, hip: -25, knee: 25,
            shoulder: .deg(pitch: -68, yaw: -26), wristPitch: 10,
            effort: 0.5
        )

        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.coordinating(pose, props: [.kettlebell])
        }

        let topS = solve(top)
        let backS = solve(back)
        var repKeyframes = [MascotKeyframe(t: 0, pose: topS, easing: .hold)]
        // The drop rides gravity: accelerating INTO the hike (easeIn),
        // a beat at the back turnaround, then the SNAP — explosive off
        // the hips (easeOut: fast start), coasting up into the float.
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: top, to: back, t0: 0.04, t1: 0.44, steps: 8,
            easing: .easeIn,
            effortKeys: [(0, 0.32), (1, 0.5)],
            solve: solve
        ))
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: backS, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: back, to: top, t0: 0.52, t1: 0.88, steps: 8,
            easing: .easeOut,
            effortKeys: [(0, 0.6), (0.25, 0.95), (1, 0.4)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: topS))

        return ExerciseAnimation(
            exerciseName: "Kettlebell Swing",
            style: .reps(repDuration: 2.0),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            // Reduced settle: the phew's chest lift levers the
            // outstretched bell (the deadlift's hanging-bar lesson).
            restBeat: MascotPoseBuilder.tiredBeat(
                from: topS, to: topS, duration: 2.4, settle: 0.55
            ),
            cues: [
                MascotCue("A hinge, not a squat"),
                MascotCue("Hike the bell back", window: 0.06...0.44),
                MascotCue("Snap the hips through", window: 0.52...0.88),
            ],
            props: [.kettlebell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.0, restDuration: 2.4, repPhase: 0.98
            ),
            restingPhase: 0.0,
            smoothing: .curved
        )
    }()
}
