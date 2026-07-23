import Foundation

/// Pull-up — the catalog's first HANGING move: a dead hang from the
/// fixed bar (`MascotProp.pullUpBar`, geometry in `MascotSupport`),
/// pulling to a chin-height finish, then lowering to a full hang.
/// Support is the BAR, not the floor: `dynamics.hangsFromBar` swaps
/// the grounded invariants for the hang laws (palms on the bar line,
/// one station, the wrap folded OVER the bar bearing the load, the
/// system center of mass under the bar), plus the barbell moves'
/// grip-axis law.
///
/// Re-authored in the articulation round (build-117, Dave: fingers
/// bent backwards around the bar, elbows bent strangely). Both
/// defects were structural: the old wrist never folded over the bar,
/// so the wrap presented its OPENING to the load (the hand continued
/// the forearm straight up, fingertips poking past the bar), and the
/// old station pin swept the upper arms to the body's midline on a
/// narrower-than-shoulders grip (elbow x 0.047 vs shoulder x 0.17 —
/// the crossed-forearms read). The new configs are scratch-descent
/// winners in ONE basin (shoulder yaw +82 -> +12, wrist pronation
/// -85 -> -77): the hang carries the hand folded 65 degrees over the
/// bar with the load dead-center in the wrap (phi 99-100) and the
/// thumb exactly inward; the top pulls shoulder-height 1.22 with the
/// elbows DOWN-OUT-BACK at (0.28, 1.25, -0.09) — outside the hands'
/// line, never near the midline — in a hollow-body lean (rootPitch
/// -14, neck swept back) that carries the oversized helmet BEHIND
/// the bar's plane (6 mm clear at the top; a literal chest-to-bar
/// would swallow the bar in the helmet). Station 0.19 puts the hands
/// just outside the shoulders; the grip's 22-degree diagonal is the
/// full-pronation shortfall the barbell law's 25 allows.
enum PullUpMove {
    static let animation: ExerciseAnimation = {
        let station = 0.19

        let hangSeed = MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricArms(
                    shoulder: .deg(pitch: -176, yaw: 81.3, roll: 2.6),
                    elbow: .deg(pitch: -3.8, yaw: -7.6),
                    wrist: .deg(pitch: 62.1, yaw: -84.2, roll: -1.5)
                ),
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: 10),
                    knee: .deg(pitch: 12), ankle: .deg(pitch: 25)
                )
            ),
            effort: 0.3
        )
        let topSeed = MascotPose(
            rootRotation: .deg(pitch: -17),
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricArms(
                    shoulder: .deg(pitch: -20.0, yaw: -2.2, roll: 149.8),
                    elbow: .deg(pitch: -109.0, yaw: 12.4),
                    wrist: .deg(pitch: 79.4, yaw: -73.4, roll: -34.0)
                ),
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: 23),
                    knee: .deg(pitch: 30), ankle: .deg(pitch: 25)
                ),
                MascotPoseBuilder.torso(
                    spine: .deg(pitch: -8), chest: .deg(pitch: -6),
                    neck: .deg(pitch: -32), head: .deg(pitch: -10)
                )
            ),
            effort: 0.85
        )

        // The station pin: bisect a symmetric shoulder-ROLL delta
        // until the left palm sits exactly at its station along the
        // bar (roll is the frontal-plane reach channel — palm x is
        // monotone in it across this one-basin family), then hang the
        // root so the palms land on the bar line. The OLD pin used
        // shoulder yaw + elbow yaw: yaw at overhead flexion is
        // humeral spin, which swept the elbows across the chest (the
        // build-117 crossed-forearms read), and elbow yaw tilted the
        // hinge plane. Roll moves the arm where a human's lateral
        // reach actually lives. Palm x is root-translation-invariant,
        // so the order is exact.
        let solve = { (pose: MascotPose) -> MascotPose in
            func palmX(_ candidate: MascotPose) -> Double {
                let frames = candidate.jointFrames(skeleton: .standard)
                guard let lw = frames[.leftWrist] else { return station }
                return (lw.position + lw.rotation.rotate(MascotGrip.palmOffset)).x
            }
            func adjusted(_ u: Double) -> MascotPose {
                var candidate = pose
                var joints = candidate.joints
                // 168, not 173: the anatomical bound minus spline
                // overshoot room (never author at a joint stop).
                let rollBound = 168.0 * Double.pi / 180
                let left = joints[.leftShoulder] ?? .zero
                let right = joints[.rightShoulder] ?? .zero
                joints[.leftShoulder] = EulerAngles(
                    pitch: left.pitch, yaw: left.yaw,
                    roll: min(max(left.roll + u * 0.70, -rollBound), rollBound)
                )
                joints[.rightShoulder] = EulerAngles(
                    pitch: right.pitch, yaw: right.yaw,
                    roll: min(max(right.roll - u * 0.70, -rollBound), rollBound)
                )
                candidate.joints = joints
                return candidate
            }
            // BOUNDED authority: enough to hold the whole path on
            // station, far too little to fold the arms across.
            var lowU = -1.0
            var highU = 1.0
            let rising = palmX(adjusted(highU)) > palmX(adjusted(lowU))
            for _ in 0..<36 {
                let mid = (lowU + highU) / 2
                if (palmX(adjusted(mid)) < station) == rising {
                    lowU = mid
                } else {
                    highU = mid
                }
            }
            return MascotPoseBuilder.hangingFromTheBar(adjusted((lowU + highU) / 2))
        }

        // The mid waypoint carries a DEEPER hollow than the endpoints'
        // lerp: the helmet passes bar height mid-path, and the extra
        // lean (rootPitch -18, neck swept) bows the head around the
        // bar — the deadlift's knee-pass waypoint pattern.
        let midSeed: MascotPose = {
            var mid = hangSeed.lerp(to: topSeed, t: 0.5)
            mid.rootRotation = .deg(pitch: -18)
            var joints = mid.joints
            joints[.neck] = .deg(pitch: -25)
            mid.joints = joints
            return mid
        }()

        let hang = solve(hangSeed)
        var repKeyframes = [MascotKeyframe(t: 0, pose: hang, easing: .hold)]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: hangSeed, to: midSeed, t0: 0.06, t1: 0.24, steps: 12,
            effortKeys: [(0, 0.3), (1, 0.7)],
            solve: solve
        ))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: topSeed, t0: 0.24, t1: 0.40, steps: 12,
            effortKeys: [(0, 0.7), (0.7, 0.9), (1, 0.75)],
            solve: solve
        ).dropFirst())
        var topHold = solve(topSeed)
        topHold.effort = 0.65
        // The dwell is PINNED mid-way so the curved spline cannot bow
        // through it — the top pause must read genuinely still.
        repKeyframes.append(MascotKeyframe(t: 0.46, pose: topHold, easing: .linear))
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: topHold, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: topSeed, to: midSeed, t0: 0.52, t1: 0.72, steps: 12,
            effortKeys: [(0, 0.5), (1, 0.42)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: hangSeed, t0: 0.72, t1: 0.94, steps: 12,
            effortKeys: [(0, 0.42), (1, 0.3)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: hang))

        return ExerciseAnimation(
            exerciseName: "Pull-Up",
            style: .reps(repDuration: 3.2),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            // The phew, re-hung: the solve re-pins station and bar
            // line every interior beat, so the breath reads as a
            // hanging shrug and the hang laws hold through the rest.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: hang, to: hang, duration: 2.8, settle: 0.55, solve: solve
            ),
            cues: [
                MascotCue("Start from a full hang"),
                MascotCue("Pull your chest to the bar", window: 0.06...0.40),
                MascotCue("Lower all the way down", window: 0.52...0.94),
            ],
            props: [.pullUpBar],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.2, restDuration: 2.8, repPhase: 0.98
            ),
            restingPhase: 0.0,
            smoothing: .curved,
            dynamics: MascotDynamics(hangsFromBar: true)
        )
    }()
}
