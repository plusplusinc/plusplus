import Foundation

/// Barbell back squat: the bar racked ON the traps behind the neck,
/// hips travel back and down, knees track forward, drive up through
/// the heels with the effort spike on the ascent.
enum SquatMove {
    static let animation: ExerciseAnimation = {
        // Kept small: roll composed with a deep hip hinge slides the
        // ankles laterally (the planted solver can only pin the mean),
        // and the stance width already comes from the hip offsets.
        let stanceRoll = 3.0
        // BACK-rack hold, v4. v3 shipped a front rack because the old
        // rig couldn't reach behind the neck with legal joints — the
        // real fix (Dave: the mascot can do ALL human movements) was
        // giving the skeleton the shoulder girdle a back rack leans
        // on. With clavicle retraction + a modest shrug the numeric
        // scan lands the palms ON the bar line at the traps (a
        // deliberate ~6 mm graze — a back-squat bar RESTS there), the
        // grip axis within 4 degrees of the bar, elbows folded the
        // proper way pointing down-back. Every angle below is inside
        // the anatomical table in MascotMovesTests.
        let arms = MascotPoseBuilder.symmetricArms(
            clavicle: .deg(yaw: 20.4, roll: 2.8),
            shoulder: .deg(yaw: 85.3, roll: -0.4),
            elbow: .deg(pitch: -143.5),
            wrist: .deg(pitch: 47.2, yaw: -35.4, roll: 42)
        )
        let legsStanding = MascotPoseBuilder.symmetricLegs(
            hip: .deg(roll: stanceRoll)
        )
        // Full-ROM bottom (Dave's depth round): hip crease BELOW the
        // knee — a below-parallel back squat, invariant-enforced (the
        // v2 bottom stopped a thigh's width above parallel and read
        // shallow). The depth scan holds every other rule at once:
        // center of mass over the feet, bar over the midfoot, trap
        // graze unchanged. Ankle CANCELS the accumulated shin lean
        // (knee 135 + hip -100 = +35) so the feet stay FLAT on the
        // floor — round 2 shipped the sign flipped and the heels
        // visibly dug through the floor (the sole-corner floor
        // invariant now catches it).
        let legsBottom = MascotPoseBuilder.symmetricLegs(
            hip: .deg(pitch: -100, roll: stanceRoll),
            knee: .deg(pitch: 135),
            ankle: .deg(pitch: -35)
        )
        // The torso lean is what keeps the TRAP-racked bar over the
        // midfoot as the hips travel back — a back squat leans further
        // than a front squat by design. Both bar path and the center
        // of mass are invariant-enforced. The STANDING hold carries a
        // subtle lean too: this bot's chest is deep (its spine is the
        // body's centerline, not dorsal like a human's), so a trap
        // rack sits ~10 cm behind the neck axis — the slight incline
        // is what a lifter does under the same constraint, and it
        // brings the loaded bar back over the foot.
        let torsoStanding = MascotPoseBuilder.torso(
            spine: .deg(pitch: 5),
            chest: .deg(pitch: 4),
            neck: .deg(pitch: -5),
            head: .deg(pitch: -2)
        )
        let torsoBottom = MascotPoseBuilder.torso(
            spine: .deg(pitch: 33),
            chest: .deg(pitch: 25),
            neck: .deg(pitch: -16),
            head: .deg(pitch: -5)
        )

        // The path servo (MascotPoseBuilder.coordinating): bar over
        // midfoot AND center of mass over the feet at every baked
        // sample — the continuous coordination a real lifter does by
        // feel. Identity at the endpoints.
        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.coordinating(
                pose, props: [.barbell], barOverMidfootAtLeast: -0.085
            )
        }

        let standing = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsStanding, torsoStanding, arms),
            effort: 0.25
        ))
        let bottom = solve(MascotPose(
            joints: MascotPoseBuilder.merge(legsBottom, torsoBottom, arms),
            effort: 0.6
        ))
        // The standard rep cycle: a deliberately slower eccentric
        // (control the descent — invariant-enforced), pause at depth,
        // drive with the effort spike, settle tall.
        let repKeyframes = MascotPoseBuilder.repCycle(
            top: standing, bottom: bottom,
            topEffort: 0.25, bottomEffort: 0.6, driveEffort: 0.9, settleEffort: 0.4,
            solve: solve
        )

        return ExerciseAnimation(
            exerciseName: "Squat",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: standing, to: standing, duration: 2.6),
            cues: [
                MascotCue("Feet shoulder width"),
                MascotCue("Knees track over toes"),
                MascotCue("Hips back and down", window: 0.03...0.45),
                MascotCue("Drive through heels", window: 0.55...0.95),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.6, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
