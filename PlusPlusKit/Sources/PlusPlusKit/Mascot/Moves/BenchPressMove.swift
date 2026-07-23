import Foundation

/// Barbell bench press — the SUPPORT CLASS's first move: the bot lies
/// supine ON the flat bench (`MascotProp.flatBench`, geometry in
/// `MascotSupport`), five points of contact held through every frame —
/// head, upper back, and glutes on the pad, both soles planted on the
/// floor — while the bar runs lockout-over-the-shoulders down to a
/// mid-chest touch and back.
///
/// The whole pose came from the ScratchBench/ScratchGrip numeric scans
/// (the recipe discipline): the BODY placement balances the torso
/// capsules' 10 mm radius spread against the pad with 1.2 degrees of
/// head-up tilt (pelvis +1.5 / abdomen +0.3 / cowl -2.2 mm of graze),
/// the soles land flat at +0.4 mm, and a 7-degree chin tuck rests the
/// helmet exactly on the pad. The ARMS are seeds in the OVERHAND basin
/// (the grip round, from Dave's device pass: the hands slid 99 mm
/// along the bar into a plate, and the wrap read underhand): the
/// `grippingTheBar` servo owns them at every baked sample — palm
/// pinned to its station, thumb inward, wrists stacked over the elbows
/// through the whole press.
enum BenchPressMove {
    static let animation: ExerciseAnimation = {
        // Supine placement (scan winners, one decimal).
        let rootPitch = -88.8
        let hip = 21.0
        let knee = 41.0
        let ankle = -(rootPitch + hip + knee)

        func benchPose(
            shoulder: EulerAngles,
            elbow: EulerAngles,
            wrist: EulerAngles,
            effort: Double
        ) -> MascotPose {
            MascotPose(
                rootTranslation: Vec3(0, 0.3555 - MascotSkeleton.standard.restRootHeight, 0.08),
                rootRotation: .deg(pitch: rootPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hip),
                        knee: .deg(pitch: knee),
                        ankle: .deg(pitch: ankle)
                    ),
                    MascotPoseBuilder.torso(neck: .deg(pitch: 7), head: .deg(pitch: 4)),
                    MascotPoseBuilder.symmetricArms(
                        shoulder: shoulder,
                        elbow: elbow,
                        wrist: wrist
                    )
                ),
                effort: effort
            )
        }

        // The STANDING servo (`coordinating` — CoM over feet, bar over
        // midfoot) doesn't apply lying down; the bench's servo is the
        // whole-hand barbell one: palm pinned to its STATION on the bar
        // (the grip round: a joint lerp slid the hands 99 mm along the
        // bar, into a plate), the wrap OVERHAND (thumb inward), and the
        // elbow kept under the bar — the forearm stays vertical through
        // the whole press, which is the move's own second cue.
        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.grippingTheBar(pose, station: 0.26, elbowUnderBar: true)
        }
        // ⚠️ Margin note for the next tuner: this arc runs the
        // TIGHTEST hand-wrap graze in the catalog — solved-cycle worst
        // ~5.0 mm against the 6 mm fingers-never-pierce bound (the
        // full-pronation press holds the largest grip-axis skew, and
        // skew shifts the bar within the outer finger's wrap plane).
        // A seed retune or servo-weight change lands a far-away
        // handsNeverPierceWhatTheyHold failure before anything visible.

        // Arm SEEDS in the overhand basin (ScratchGrip winners, one
        // decimal); repCycle emits solve(seed) for every endpoint
        // appearance, so the servo owns the final grip everywhere.
        // Lockout: bar at full reach stacked over the shoulders.
        let lockout = benchPose(
            shoulder: .deg(pitch: -9.1, yaw: -66.7, roll: 89.6),
            elbow: .deg(pitch: -17.6, yaw: 3.8),
            wrist: .deg(pitch: 1.6, yaw: -88.0, roll: 3.7),
            effort: 0.3
        )
        // Touch: bar grazing the mid cowl, elbow under the bar. The
        // depth is scanned against the SOLVED cycle, not the seed —
        // the grip servo's position residual runs the spline's worst
        // sample ~2 mm deeper than the seed pose reads (review catch:
        // the old -139.8 seed claimed 5 mm but shipped 6.8, one
        // millimeter from the invariant). At -137.4 the solved worst
        // is 4.7 mm with the touch still seated on the cowl.
        let touch = benchPose(
            shoulder: .deg(pitch: 18.4, yaw: 26.1, roll: 73.9),
            elbow: .deg(pitch: -137.4, yaw: 8.5),
            wrist: .deg(pitch: -3.2, yaw: -88.0, roll: -11.8),
            effort: 0.55
        )
        let repKeyframes = MascotPoseBuilder.repCycle(
            top: lockout, bottom: touch,
            steps: 12,
            topEffort: 0.3, bottomEffort: 0.55, driveEffort: 0.92, settleEffort: 0.4,
            solve: solve
        )

        // The bench's own quiet rest beat: the shared SUPINE tired
        // beat (shrug + glance, contacts untouched) — the standard
        // chin-up phew would drive the helmet into the pad.
        // Seam-exact endpoints: the beat starts at the rep's LAST
        // baked pose and ends at its FIRST.
        let repEnd = repKeyframes.last!.pose
        let repStart = repKeyframes.first!.pose
        let restBeat = MascotPoseBuilder.supineTiredBeat(from: repEnd, to: repStart, duration: 2.6)

        return ExerciseAnimation(
            exerciseName: "Bench Press",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: restBeat,
            cues: [
                MascotCue("Feet planted, shoulder blades pinned"),
                MascotCue("Wrists stacked over the elbows"),
                MascotCue("Lower to mid chest", window: 0.04...0.45),
                MascotCue("Press to lockout", window: 0.56...0.9),
            ],
            props: [.barbell, .flatBench],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.6, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved
        )
    }()
}
