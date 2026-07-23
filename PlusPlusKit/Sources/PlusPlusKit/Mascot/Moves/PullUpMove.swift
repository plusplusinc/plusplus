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

        // The hands belong to the SERVO (the grip round's composition
        // law: the path owns the body, `grippingTheBar` owns the
        // hand). Round 1 pinned the palm with a one-channel bisection
        // — non-monotone mid-pull, so adjacent frames hopped between
        // solutions and the spline whipped; a two-channel corrector
        // then held station but nothing held the WRAP, and the lerped
        // mid-path tilted the grip axis 27 degrees off the bar. The
        // fix is the same architecture every barbell move uses: per
        // baked sample, hang the root on the bar line, then let the
        // whole-arm servo re-solve the arm onto the FIXED bar
        // (palmTarget = the bar itself) with its overhand-wrap
        // objective, seeded by the sample's own lerped arm (the
        // deadlift's armSeed law — the seed picks the basin, so the
        // solved arm is a smooth function of the path). One more hang
        // seats the palms exactly after the arm settles.
        let barPoint = Vec3(station, MascotSupport.pullUpBarHeight, 0)
        let solve = { (pose: MascotPose) -> MascotPose in
            var p = MascotPoseBuilder.hangingFromTheBar(pose)
            p = MascotPoseBuilder.grippingTheBar(
                p,
                station: station,
                palmTarget: barPoint,
                handFollowsForearm: false,
                armSeed: (
                    shoulder: pose.joints[.leftShoulder] ?? .zero,
                    elbow: pose.joints[.leftElbow] ?? .zero,
                    wrist: pose.joints[.leftWrist] ?? .zero
                )
            )
            return MascotPoseBuilder.hangingFromTheBar(p)
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
            from: hangSeed, to: midSeed, t0: 0.06, t1: 0.24, steps: 8,
            effortKeys: [(0, 0.3), (1, 0.7)],
            solve: solve
        ))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: topSeed, t0: 0.24, t1: 0.40, steps: 8,
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
            from: topSeed, to: midSeed, t0: 0.52, t1: 0.72, steps: 8,
            effortKeys: [(0, 0.5), (1, 0.42)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: hangSeed, t0: 0.72, t1: 0.94, steps: 8,
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
