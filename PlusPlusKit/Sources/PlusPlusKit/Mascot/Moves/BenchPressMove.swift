import Foundation

/// Barbell bench press — the SUPPORT CLASS's first move: the bot lies
/// supine ON the flat bench (`MascotProp.flatBench`, geometry in
/// `MascotSupport`), five points of contact held through every frame —
/// head, upper back, and glutes on the pad, both soles planted on the
/// floor — while the bar runs lockout-over-the-shoulders down to a
/// mid-chest touch and back.
///
/// The whole pose came from the ScratchBench numeric scans (the recipe
/// discipline): the BODY placement balances the torso capsules' 10 mm
/// radius spread against the pad with 1.2 degrees of head-up tilt
/// (pelvis +1.5 / abdomen +0.3 / cowl -2.2 mm of graze), the soles land
/// flat at +0.4 mm, and a 7-degree chin tuck rests the helmet exactly
/// on the pad. The ARMS came from coordinate descent: palms exactly on
/// the bar line, grip axis 0.0 degrees off the bar at both ends,
/// vertical forearm (elbow directly under the bar in the side view) at
/// the touch, full-reach lockout stacked over the shoulder line.
enum BenchPressMove {
    static let animation: ExerciseAnimation = {
        // Supine placement (scan winners, one decimal).
        let rootPitch = -88.8
        let hip = 21.0
        let knee = 41.0
        let ankle = -(rootPitch + hip + knee)

        func benchPose(
            shoulder: EulerAngles,
            elbow: Double,
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
                        elbow: .deg(pitch: elbow),
                        wrist: wrist
                    )
                ),
                effort: effort
            )
        }

        // The STANDING servo (`coordinating` — CoM over feet, bar over
        // midfoot) doesn't apply lying down; the bench's servo is the
        // GRIP one: a joint lerp between the two perfectly-gripped
        // endpoints swung the hands 34 degrees off the bar axis at
        // mid-press, so every baked sample re-aims the wrists
        // (`aligningGrip`). Collision + contact invariants police the
        // rest.
        let solve = { (pose: MascotPose) in
            MascotPoseBuilder.aligningGrip(pose)
        }

        // Endpoints run through the solve too (repCycle's contract) —
        // today the scan winners sit under the servo's identity gate so
        // this is a no-op, but it stays true if a future retune lands a
        // hair over the gate.
        // Lockout: bar at full reach (0.726) stacked over the shoulders.
        let lockout = solve(benchPose(
            shoulder: .deg(pitch: -84.9, yaw: -10.1, roll: 25.5),
            elbow: -7.2,
            wrist: .deg(pitch: -3.8, yaw: 3.9, roll: -15.2),
            effort: 0.3
        ))
        // Touch: bar grazing the mid cowl (4 mm proud of the surface),
        // elbow under the bar in the sagittal plane.
        let touch = solve(benchPose(
            shoulder: .deg(pitch: 27.9, yaw: 15.8, roll: 73.0),
            elbow: -133.4,
            wrist: .deg(pitch: -39.0, yaw: 40.6, roll: 33.8),
            effort: 0.55
        ))
        let repKeyframes = MascotPoseBuilder.repCycle(
            top: lockout, bottom: touch,
            steps: 12,
            topEffort: 0.3, bottomEffort: 0.55, driveEffort: 0.92, settleEffort: 0.4,
            solve: solve
        )

        // The bench's own quiet rest beat: the standard happy-tired
        // "phew" tips the chest proud and the chin up — which lying on
        // a bench would drive INTO the pad (the contact invariant
        // rejects it). Supine tired is a shoulder-girdle shrug and a
        // sideways glance, contacts untouched, face doing the tired
        // work through the effort channel.
        // Seam-exact endpoints: the beat starts at the rep's LAST baked
        // pose and ends at its FIRST (they differ only through the
        // solve, but the seam invariant demands exactness).
        let repEnd = repKeyframes.last!.pose
        let repStart = repKeyframes.first!.pose
        var shrug = repEnd
        var shrugJoints = shrug.joints
        for (clavicle, side) in [(MascotJoint.leftClavicle, 1.0), (.rightClavicle, -1.0)] {
            let current = shrugJoints[clavicle] ?? .zero
            shrugJoints[clavicle] = EulerAngles(
                pitch: current.pitch,
                yaw: current.yaw,
                roll: current.roll + side * 4 * .pi / 180
            )
        }
        shrug.joints = shrugJoints
        shrug.effort = 0.08
        var glance = repEnd
        var glanceJoints = glance.joints
        let head = glanceJoints[.head] ?? .zero
        glanceJoints[.head] = EulerAngles(pitch: head.pitch, yaw: 8 * .pi / 180, roll: head.roll)
        glance.joints = glanceJoints
        glance.effort = 0.06
        let restBeat = ExerciseAnimation.RestBeat(duration: 2.6, keyframes: [
            MascotKeyframe(t: 0, pose: repEnd, easing: .easeInOut),
            MascotKeyframe(t: 0.35, pose: shrug, easing: .easeInOut),
            MascotKeyframe(t: 0.7, pose: glance, easing: .easeInOut),
            MascotKeyframe(t: 1, pose: repStart),
        ])

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
