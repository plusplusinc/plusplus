import Foundation

/// Single-leg calf raise: standing on the left leg (right foot lifted
/// behind), the weight shifts onto the ball of the stance foot, the
/// heel drives up to a full-extension squeeze, then lowers slow. THE
/// proving move for two structures at once: the forefoot hinge (the
/// heel rises while the toe cap stays FLAT on the floor) and the
/// contact-following support polygon (at the top, balance lives
/// entirely on one toe cap — and the center of mass must live there
/// too, invariant-enforced).
enum SingleLegCalfRaiseMove {
    static let animation: ExerciseAnimation = {
        // Lateral geometry, constant through the move (real form: you
        // shift your weight FIRST, then rise): the stance hip adducts,
        // tipping the pelvis over the stance foot; the ankle roll
        // counters so the foot stays flat; the scan tuned the pair
        // until the center of mass rides the stance foot's line.
        let stanceRoll = -12.0
        // The forward sway: the stance hip EXTENDS a touch (positive
        // pitch swings the anchored leg back, which carries the body
        // FORWARD over the ball of the foot) before the heel leaves
        // the ground — the first cut used flexion and swayed the mass
        // backward off the support, caught by the polygon invariant.
        let swayHip = 8.0
        // Full-ROM heel rise at the forefoot hinge (foot-vs-floor
        // angle; the ankle plantarflexes rise - sway, within the
        // anatomical table).
        let rise = 40.0

        /// One stance-side state: heel rise angle + sway, with the
        /// raised right leg and balance arms constant. The toe pitch
        /// cancels the chain above it so the cap stays FLAT on the
        /// floor at every rise angle.
        func state(rise theta: Double, sway: Double, effort: Double) -> MascotPose {
            var joints: [MascotJoint: EulerAngles] = [:]
            // Stance (left) leg.
            // Sign conventions (pinned by the joint-range sweep):
            // plantarflexion is POSITIVE ankle pitch on this rig (the
            // +z toe direction tips down), and the cap counter-rotates
            // NEGATIVE at the ball (extension) to stay flat: world
            // foot pitch = sway + ankle; cap flat means toe cancels it.
            joints[.leftHip] = .deg(pitch: sway, roll: stanceRoll)
            joints[.leftKnee] = .zero
            joints[.leftAnkle] = .deg(pitch: theta - sway, roll: -stanceRoll)
            joints[.leftToe] = .deg(pitch: -theta)
            // Raised (right) leg: foot lifted behind, relaxed point.
            joints[.rightHip] = .deg(pitch: -8)
            joints[.rightKnee] = .deg(pitch: 72)
            joints[.rightAnkle] = .deg(pitch: -18)
            // Balance arms: slightly out, soft elbows.
            joints[.leftShoulder] = .deg(roll: 14)
            joints[.rightShoulder] = .deg(roll: -14)
            joints[.leftElbow] = .deg(pitch: -10)
            joints[.rightElbow] = .deg(pitch: -10)
            return MascotPose(joints: joints, effort: effort)
        }

        // The bottom's flat stance plants the toe target every other
        // pose anchors to: pivot at the ball, the way a heel raise
        // actually works.
        let flatBottom = MascotPoseBuilder.anchored(
            state(rise: 0, sway: 0, effort: 0.2),
            anchors: [(.leftAnkle, Vec3(0.09, 0.047, 0))]
        )
        let toeTarget = flatBottom.jointPositions(skeleton: .standard)[.leftToe]!
        func anchoredToTheBall(_ pose: MascotPose) -> MascotPose {
            MascotPoseBuilder.anchored(pose, anchors: [(.leftToe, toeTarget)])
        }

        let bottom = anchoredToTheBall(flatBottom)
        let swayed = anchoredToTheBall(state(rise: 0, sway: swayHip, effort: 0.3))
        let top = anchoredToTheBall(state(rise: rise, sway: swayHip, effort: 0.8))

        // Shift, rise, squeeze, lower slow (the eccentric is the long
        // half — invariant-enforced), settle.
        var repKeyframes: [MascotKeyframe] = [
            MascotKeyframe(t: 0, pose: bottom, easing: .easeInOut),
        ]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: swayed, t0: 0, t1: 0.12, steps: 3,
            effortKeys: [(0, 0.2), (1, 0.3)],
            solve: anchoredToTheBall
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: swayed, to: top, t0: 0.12, t1: 0.44, steps: 10,
            effortKeys: [(0, 0.3), (0.75, 0.88), (1, 0.8)],
            solve: anchoredToTheBall
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 0.56, pose: top, easing: .linear))
        // The lower keeps the default ease-in-out: an ease-OUT would
        // front-load the descent speed — dropping, not lowering.
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: top, to: swayed, t0: 0.56, t1: 0.95, steps: 10,
            effortKeys: [(0, 0.8), (0.35, 0.5), (1, 0.3)],
            solve: anchoredToTheBall
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: swayed, to: bottom, t0: 0.95, t1: 1, steps: 2,
            effortKeys: [(0, 0.3), (1, 0.2)],
            solve: anchoredToTheBall
        ).dropFirst())

        return ExerciseAnimation(
            exerciseName: "Single-Leg Calf Raise",
            style: .reps(repDuration: 2.6),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: bottom, to: bottom, duration: 2.4, settle: 0.6),
            cues: [
                MascotCue("Weight on the ball of the foot"),
                MascotCue("Stand tall"),
                MascotCue("Drive up to the top", window: 0.1...0.44),
                MascotCue("Lower with control", window: 0.55...0.95),
            ],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.6, restDuration: 2.4, repPhase: 0.02
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
