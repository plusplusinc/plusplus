import Foundation

/// Sit-up: supine with the knees bent and feet flat (the glute
/// bridge's proven floor placement), hands held on the chest, the
/// torso curls up to ~75 degrees and lowers with control. The pelvis
/// stays grounded and the legs never move — the whole rep is the
/// torso channel, which is the teaching point: no leg drive, no
/// flopping back down.
///
/// The arms fold across the chest ONCE and ride it rigidly (the
/// clavicles are chest children), so the scratch-scanned clearance
/// (forearms 45+ mm clear of every torso capsule) holds at every
/// sample by construction.
enum SitUpMove {
    static let animation: ExerciseAnimation = {
        let restRootHeight = MascotSkeleton.standard.restRootHeight

        func sitPose(spine: Double, chest: Double, neck: Double, effort: Double) -> MascotPose {
            MascotPose(
                rootTranslation: Vec3(0, 0.078 - restRootHeight, 0),
                rootRotation: .deg(pitch: -89),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: -53), knee: .deg(pitch: 144), ankle: .deg(pitch: -2)
                    ),
                    MascotPoseBuilder.torso(
                        spine: .deg(pitch: spine), chest: .deg(pitch: chest),
                        neck: .deg(pitch: neck), head: .deg(pitch: 5)
                    ),
                    // Hands on the chest: folded high enough that the
                    // forearm capsules clear the chest's by 45+ mm
                    // (scratch scan) — reads as hands-on-chest without
                    // ever grazing the self-collision sweep.
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: -14, yaw: -35),
                        elbow: .deg(pitch: -115),
                        wrist: .deg(pitch: -20)
                    )
                ),
                effort: effort
            )
        }

        // Down: lying flat, chin softly tucked so the helmet rests on
        // the floor (the supine placement scan). Up: spine+chest curl
        // to 75 degrees with a slightly deeper tuck — the pelvis stays
        // put, so the feet CANNOT lift (anchored sit-up form, free).
        let down = sitPose(spine: 0, chest: 0, neck: 8, effort: 0.2)
        let top = sitPose(spine: 45, chest: 30, neck: 14, effort: 0.75)
        var squeezeEnd = top
        squeezeEnd.effort = 0.6
        var lowering = top.lerp(to: down, t: 0.42)
        lowering.effort = 0.32

        return ExerciseAnimation(
            exerciseName: "Sit-Up",
            style: .reps(repDuration: 2.8),
            repsPerDemoSet: 4,
            // Concentric snappier than the curl's (0.06-0.36), the
            // eccentric stretched across nearly half the rep — the
            // eccentric-control invariant flagged the first timing's
            // near-tie.
            repKeyframes: [
                MascotKeyframe(t: 0, pose: down, easing: .hold),
                MascotKeyframe(t: 0.06, pose: down, easing: .easeInOut),
                MascotKeyframe(t: 0.36, pose: top, easing: .linear),
                MascotKeyframe(t: 0.48, pose: squeezeEnd, easing: .easeInOut),
                MascotKeyframe(t: 0.70, pose: lowering, easing: .easeInOut),
                MascotKeyframe(t: 0.94, pose: down, easing: .hold),
                MascotKeyframe(t: 1, pose: down),
            ],
            // Supine tired: the bench/bridge shrug-and-glance — the
            // standard chin-up phew would drive the helmet through the
            // floor.
            restBeat: {
                var shrug = down
                var shrugJoints = shrug.joints
                for (clavicle, side) in [(MascotJoint.leftClavicle, 1.0), (.rightClavicle, -1.0)] {
                    let current = shrugJoints[clavicle] ?? .zero
                    shrugJoints[clavicle] = EulerAngles(
                        pitch: current.pitch, yaw: current.yaw,
                        roll: current.roll + side * 4 * .pi / 180
                    )
                }
                shrug.joints = shrugJoints
                shrug.effort = 0.08
                var glance = down
                var glanceJoints = glance.joints
                let head = glanceJoints[.head] ?? .zero
                glanceJoints[.head] = EulerAngles(pitch: head.pitch, yaw: 8 * .pi / 180, roll: head.roll)
                glance.joints = glanceJoints
                glance.effort = 0.06
                return ExerciseAnimation.RestBeat(duration: 2.4, keyframes: [
                    MascotKeyframe(t: 0, pose: down, easing: .easeInOut),
                    MascotKeyframe(t: 0.35, pose: shrug, easing: .easeInOut),
                    MascotKeyframe(t: 0.7, pose: glance, easing: .easeInOut),
                    MascotKeyframe(t: 1, pose: down),
                ])
            }(),
            cues: [
                MascotCue("Hands on your chest"),
                MascotCue("Curl up, ribs toward hips", window: 0.06...0.42),
                MascotCue("Lower with control", window: 0.52...0.94),
            ],
            props: [],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.8, restDuration: 2.4, repPhase: 0.02
            ),
            restingPhase: 0.35,
            smoothing: .curved
        )
    }()
}
