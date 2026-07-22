import Foundation

/// Conventional deadlift: hinge back with a flat back until the bar (in
/// hanging arms) reaches the shins, a beat to set the grip, then the
/// pull with the hardest effort of any move, into a tall lockout.
enum DeadliftMove {
    static let animation: ExerciseAnimation = {
        let stanceRoll = 4.0
        // Full-ROM bottom (Dave's depth round): the bar starts FROM THE
        // FLOOR — plates about 8 mm off the ground at the catch — not
        // from knee height (that was a rack pull wearing a deadlift's
        // name). The chunky bot reaches it with a deep hinge (85
        // degrees of torso) plus real knee bend, found by the same
        // numeric scan discipline as the squat: every candidate held
        // balance, bar-over-midfoot, shin clearance, and legal joints
        // simultaneously.
        let spinePitch = 45.0
        let chestPitch = 40.0

        let legsLockout = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -92, roll: stanceRoll),
            knee: .deg(pitch: 112),
            ankle: .deg(pitch: -20)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: spinePitch),
            chest: .deg(pitch: chestPitch),
            neck: .deg(pitch: -38),
            head: .deg(pitch: -12)
        )
        // Arms hang a few degrees forward of plumb so the bar clears
        // the shins by millimeters instead of dragging through them
        // (the collision invariant caught 3.9 cm of bar-into-thigh in
        // an earlier cut with more forward push). These SIMPLE
        // pitch-only arms stay the authored truth on purpose: they are
        // the convention `coordinating`'s clearance nudge speaks
        // (shoulder pitch = swing the hanging bar forward), and they
        // set the bar's PATH. The grip servo below re-solves the whole
        // arm afterward from its own overhand seed — station, wrap,
        // and pronation are its job, not the authored angles'.
        let armsBottom = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -(spinePitch + chestPitch) - 3)
        )

        // Lockout arms sit ~13 degrees forward so the bar rests against
        // the FRONT of the thighs (build-80: straight-down arms put the
        // bar inside the belly; the clearance invariant now forbids
        // it). Was -15 before the grip round: the overhand wrist
        // re-aim carries the palm ~9 mm further forward, and at -15
        // the tired beat's chest lift swung the bar past the
        // over-midfoot bound.
        let armsLockout = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -13)
        )
        // The path servos, composed: `coordinating` swings the bar
        // AROUND the shins (a lerp between legal endpoints dragged it
        // 2.3 cm into the knees mid-hinge) and keeps the mass over the
        // feet; `grippingTheBar` then rebuilds the arm ON that legal
        // bar path from a constant OVERHAND-basin seed (the grip
        // round: the hands slid 33 mm along the bar and the wrap read
        // underhand; the ~180-degree overhand flip splits across
        // shoulder internal rotation ~-88, the elbow's radioulnar
        // share -23, and wrist pronation -88 — every piece anatomical).
        // Every keyframe below, pause and seam included, is
        // solve(seed): the same pure call each time, so stillness
        // stays bit-exact.
        // The overhand arm shape TRACKS the hinge: standing, the wrap
        // is shoulder-roll 17; at the deep hinge, roll 92 — the same
        // basin, rolled with the torso. Seeding the solver from a
        // hinge-interpolated shape keeps Gauss-Newton HOME at every
        // sample (a constant bottom-basin seed left the standing end so
        // far from its start that the solver wandered across basins —
        // the bar spent 57 mm inside the belly at one baked sample).
        // The interpolant reads the POSE's own torso, so the solve
        // stays a pure phase-free function.
        let standingArms: (shoulder: EulerAngles, elbow: EulerAngles, wrist: EulerAngles) = (
            shoulder: .deg(pitch: 0.2, yaw: -90.6, roll: 16.7),
            elbow: .deg(pitch: 0, yaw: -2.2),
            wrist: .deg(pitch: -0.1, yaw: -87.2, roll: 0)
        )
        let hingedArms: (shoulder: EulerAngles, elbow: EulerAngles, wrist: EulerAngles) = (
            shoulder: .deg(pitch: -43.8, yaw: -88.3, roll: 91.9),
            elbow: .deg(pitch: -5.0, yaw: -23.0),
            wrist: .deg(pitch: -0.1, yaw: -88.0, roll: -0.4)
        )
        let fullHinge = (spinePitch + chestPitch) * Double.pi / 180
        let solve = { (pose: MascotPose) in
            let hinge = pose.angles(.spine).pitch + pose.angles(.chest).pitch
            let u = min(max(hinge / fullHinge, 0), 1)
            let seed = (
                shoulder: standingArms.shoulder.lerp(to: hingedArms.shoulder, t: u),
                elbow: standingArms.elbow.lerp(to: hingedArms.elbow, t: u),
                wrist: standingArms.wrist.lerp(to: hingedArms.wrist, t: u)
            )
            // Graze bound 4 mm, not the invariant's 8: `coordinating`
            // stops nudging the moment penetration clears ITS bound,
            // and `grippingTheBar` then rebuilds the arm with a
            // position residual that can carry the bar a couple of
            // millimeters deeper — the composition is only bounded by
            // the headroom reserved here (review catch: at 5 mm the
            // shipped worst case ran 6.7 mm, 1.3 from the invariant;
            // at 4 the solved cycle worst is 4.7).
            return MascotPoseBuilder.grippingTheBar(
                MascotPoseBuilder.coordinating(
                    pose, props: [.barbell], equipmentGrazeAtMost: 0.004
                ),
                station: 0.17,
                armSeed: seed
            )
        }

        // The FIRST-PULL waypoint (build-88: the bar visibly deflected
        // around the knees — proper technique moves the KNEES out of
        // the bar's way, not the bar around the knees): at knee
        // passage the shins are near vertical (hip -40 + knee 44) with
        // the BACK ANGLE UNCHANGED from the floor — knees extend
        // first, hips stay closed, the bar path stays a straight
        // vertical line. Mirrored on the way down: hips hinge back
        // and the bar slides down the thighs past the knees BEFORE
        // the knees bend.
        let legsKneePass = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -40, roll: stanceRoll),
            knee: .deg(pitch: 44),
            ankle: .deg(pitch: -4)
        )
        // Knee-pass arms: the same simple hanging convention — the bar
        // stays against the near-vertical shins with the back angle
        // held; the grip servo owns the real hand.
        let armsKneePass = MascotPoseBuilder.symmetricArms(
            shoulder: .deg(pitch: -(spinePitch + chestPitch))
        )

        // SEEDS: spans lerp between these and solve every sample; the
        // pause and seam keyframes below are solve(seed) — the same
        // pure call as the span ends, so stillness is bit-exact.
        let seedLockout = MascotPose(
            joints: MascotPoseBuilder.merge(legsLockout, armsLockout),
            effort: 0.3
        )
        let seedKneePass = MascotPose(
            joints: MascotPoseBuilder.merge(legsKneePass, torsoBottom, armsKneePass),
            effort: 0.45
        )
        let seedBottom = MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, armsBottom),
            effort: 0.5
        )
        let lockout = solve(seedLockout)
        var bottom = solve(seedBottom)
        bottom.effort = 0.5
        // Slow eccentric staged through the knee pass, a beat at the
        // floor to set the grip, then the pull (knees first, hips
        // through) with the hardest effort of any move. Densely baked:
        // the servo only speaks at the knots. The knee pass is a pure
        // POSITION waypoint, never a velocity zero: each half runs
        // easeIn INTO it and easeOut AWAY from it, so the bar moves
        // continuously through knee height (the default easeInOut on
        // both sides baked a visible hitch into the samples — and gave
        // the pull an upside-down speed shape, peak velocity right off
        // the floor; a real first pull is slowest off the floor and
        // accelerates past the knees).
        var repKeyframes = MascotPoseBuilder.span(
            from: seedLockout, to: seedKneePass, t0: 0, t1: 0.22, steps: 10,
            easing: .easeIn,
            effortKeys: [(0, 0.3), (1, 0.4)],
            solve: solve
        )
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: seedKneePass, to: seedBottom, t0: 0.22, t1: 0.46, steps: 12,
            easing: .easeOut,
            effortKeys: [(0, 0.4), (1, 0.5)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 0.56, pose: bottom, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: seedBottom, to: seedKneePass, t0: 0.56, t1: 0.72, steps: 8,
            easing: .easeIn,
            effortKeys: [(0, 0.5), (0.6, 0.95), (1, 0.8)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: seedKneePass, to: seedLockout, t0: 0.72, t1: 0.9, steps: 8,
            easing: .easeOut,
            effortKeys: [(0, 0.8), (0.5, 0.9), (1, 0.45)],
            solve: solve
        ).dropFirst())
        var finalLockout = lockout
        finalLockout.effort = 0.3
        repKeyframes.append(MascotKeyframe(t: 1, pose: finalLockout))

        return ExerciseAnimation(
            exerciseName: "Deadlift",
            style: .reps(repDuration: 3.5),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            // settle 0.55: the full phew's chest lift swings the
            // hanging bar forward, and on the PRONATED arm (the grip
            // round) that lever runs longer — at 1.0 the bar crossed
            // the over-midfoot bound by 14 mm mid-beat.
            restBeat: MascotPoseBuilder.tiredBeat(from: lockout, to: lockout, duration: 2.8, settle: 0.55),
            cues: [
                MascotCue("Flat back, chest proud"),
                MascotCue("Bar close to the body"),
                MascotCue("Hips hinge back", window: 0.03...0.46),
                MascotCue("Push the floor away", window: 0.56...0.9),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.5, restDuration: 2.8, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
