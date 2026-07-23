import Foundation

/// Reverse lunge, dumbbells at the sides — the catalog's second
/// asymmetric move (the calf raise's dress rehearsal, one level up):
/// the LEFT leg steps BACK onto the ball of the foot, both knees bend
/// until the back knee hovers just off the floor, then the front leg
/// drives back up and the left foot returns home. The demo teaches
/// one side; the movement is its own mirror.
///
/// The stance (right) ankle is ANCHORED to its standing spot at every
/// baked sample — with its leg chain summing to zero at every key,
/// the front sole stays planted flat by construction. The back ball's
/// touch height came from a left-knee bisection at the bottom (6 mm),
/// and the mid-step reach deliberately skims low (~4 cm) rather than
/// lifting high — a quick, light step. Strict single-support balance
/// (weight visibly shifting over the stance foot mid-step) is a known
/// follow-up; it needs a stance-shift solver.
enum ReverseLungeMove {
    static let animation: ExerciseAnimation = {
        let restRight = MascotSkeleton.standard.restPose
            .jointPositions(skeleton: .standard)[.rightAnkle]!

        func lungePose(
            rightHip: Double, rightKnee: Double, rightAnkle: Double,
            leftHip: Double, leftKnee: Double, leftAnkle: Double, leftToe: Double,
            spine: Double, effort: Double
        ) -> MascotPose {
            var joints: [MascotJoint: EulerAngles] = [
                .rightHip: .deg(pitch: rightHip), .rightKnee: .deg(pitch: rightKnee),
                .rightAnkle: .deg(pitch: rightAnkle),
                .leftHip: .deg(pitch: leftHip), .leftKnee: .deg(pitch: leftKnee),
                .leftAnkle: .deg(pitch: leftAnkle), .leftToe: .deg(pitch: leftToe),
            ]
            // Dumbbells hang at the sides in a neutral grip; the
            // curl's thigh-clearance roll.
            for (joint, angles) in MascotPoseBuilder.symmetricArms(
                shoulder: .deg(pitch: 3, roll: 12), wrist: .deg(yaw: -88)
            ) { joints[joint] = angles }
            for (joint, angles) in MascotPoseBuilder.torso(
                spine: .deg(pitch: spine), neck: .deg(pitch: -6)
            ) { joints[joint] = angles }
            return MascotPose(joints: joints, effort: effort)
        }

        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.anchored(pose, anchors: [(.rightAnkle, restRight)])
        }

        let stand = lungePose(
            rightHip: 0, rightKnee: 0, rightAnkle: 0,
            leftHip: 0, leftKnee: 0, leftAnkle: 0, leftToe: 0,
            spine: 2, effort: 0.25
        )
        // The reach: left leg swept back, ball skimming ~4 cm up.
        let reach = lungePose(
            rightHip: -35, rightKnee: 45, rightAnkle: -10,
            leftHip: 24, leftKnee: 15, leftAnkle: -32, leftToe: -45,
            spine: 8, effort: 0.4
        )
        // The bottom: front thigh near horizontal, back ball planted
        // (knee 60.4 = the bisection winner), back knee 10 cm up.
        let bottom = lungePose(
            rightHip: -75, rightKnee: 95, rightAnkle: -20,
            leftHip: 22, leftKnee: 60.4, leftAnkle: -60, leftToe: -60,
            spine: 14, effort: 0.65
        )

        let standS = solve(stand)
        var repKeyframes = [MascotKeyframe(t: 0, pose: standS, easing: .hold)]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: stand, to: reach, t0: 0.06, t1: 0.28, steps: 5,
            effortKeys: [(0, 0.25), (1, 0.4)],
            solve: solve
        ))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: reach, to: bottom, t0: 0.28, t1: 0.52, steps: 6,
            effortKeys: [(0, 0.4), (1, 0.65)],
            solve: solve
        ).dropFirst())
        var bottomHold = solve(bottom)
        bottomHold.effort = 0.6
        repKeyframes.append(MascotKeyframe(t: 0.60, pose: bottomHold, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: reach, t0: 0.60, t1: 0.78, steps: 6,
            easing: .easeOut,
            effortKeys: [(0, 0.7), (0.4, 0.9), (1, 0.5)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: reach, to: stand, t0: 0.78, t1: 0.94, steps: 5,
            effortKeys: [(0, 0.5), (1, 0.25)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: standS))

        return ExerciseAnimation(
            exerciseName: "Reverse Lunge",
            style: .reps(repDuration: 3.4),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: standS, to: standS, duration: 2.6),
            cues: [
                MascotCue("Step back, land on the ball"),
                MascotCue("Lower the back knee", window: 0.06...0.52),
                MascotCue("Drive up through the front heel", window: 0.6...0.94),
            ],
            props: [.dumbbellPair],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.4, restDuration: 2.6, repPhase: 0.02
            ),
            restingPhase: 0.45,
            smoothing: .curved
        )
    }()
}
