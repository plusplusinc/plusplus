import Foundation

/// Forearm plank: a single 20-second hold. A STRAIGHT line from head
/// to heels (build-88 caught the hips dipping and a harsh pointed
/// ankle), on tucked toes: caps flat on the floor, feet near-vertical
/// on the forefoot hinge, ankles close to neutral. The pose barely
/// moves — breathing micro-sway only — while the effort channel ramps
/// across the hold (Dave's rule for static holds: the strain builds
/// over time, not per rep).
enum PlankMove {
    static let animation: ExerciseAnimation = {
        let holdSeconds = 20.0
        let breathCycles = 4.0
        let hipPitch = 2.0
        let footWorldPitch = 72.0
        let elbowPadY = 0.05
        let toeY = 0.018

        func plankPose(bodyPitch: Double) -> MascotPose {
            let anklePitch = footWorldPitch - bodyPitch - hipPitch
            return MascotPose(
                rootRotation: .deg(pitch: bodyPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: -bodyPitch),
                        elbow: .deg(pitch: -90)
                    ),
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hipPitch),
                        ankle: .deg(pitch: anklePitch),
                        toe: .deg(pitch: -footWorldPitch)
                    ),
                    // Head continues the body line, gaze at the floor a
                    // little ahead — never craned up.
                    MascotPoseBuilder.torso(neck: .deg(pitch: -6), head: .deg(pitch: -2))
                ),
                effort: 0
            )
        }

        // Rest the forearms on the floor and bisect the body pitch
        // until the toe hinges ride at cap-flat height — the same
        // chain-closing solve as the push-up, with elbow anchors.
        let elbowJoints: [MascotJoint] = [.leftElbow, .rightElbow]
        func settled(bodyPitch: Double) -> (pose: MascotPose, toeY: Double) {
            var pose = plankPose(bodyPitch: bodyPitch)
            let positions = pose.jointPositions(skeleton: .standard)
            let targets: [(MascotJoint, Vec3)] = elbowJoints.compactMap { joint in
                positions[joint].map { (joint, Vec3($0.x, elbowPadY, $0.z)) }
            }
            pose = MascotPoseBuilder.anchored(pose, anchors: targets)
            return (pose, pose.jointPositions(skeleton: .standard)[.leftToe]!.y)
        }
        var low = 65.0
        var high = 85.0
        for _ in 0..<36 {
            let mid = (low + high) / 2
            if settled(bodyPitch: mid).toeY > toeY {
                high = mid
            } else {
                low = mid
            }
        }
        let base = settled(bodyPitch: (low + high) / 2).pose

        // The hold: sampled sinusoidal breathing at a resolution that
        // keeps linear interpolation smooth, effort ramping underneath.
        func holdPose(atPhase phase: Double) -> MascotPose {
            let sway = sin(2 * .pi * breathCycles * phase)
            var pose = base
            var joints = pose.joints
            let chest = joints[.chest] ?? .zero
            joints[.chest] = EulerAngles(pitch: chest.pitch + 1.2 * .pi / 180 * sway, yaw: chest.yaw, roll: chest.roll)
            pose.joints = joints
            pose.rootTranslation.y += 0.003 * sway
            pose.effort = 0.25 + 0.6 * mascotSmoothstep(0.12, 0.92, phase)
            return pose
        }
        let sampleCount = 33
        let holdKeyframes = (0..<sampleCount).map { index -> MascotKeyframe in
            let phase = Double(index) / Double(sampleCount - 1)
            return MascotKeyframe(t: phase, pose: holdPose(atPhase: phase), easing: .linear)
        }

        let workShare = holdSeconds / (holdSeconds + 3.0)
        return ExerciseAnimation(
            exerciseName: "Plank",
            style: .hold(duration: holdSeconds),
            repsPerDemoSet: 1,
            repKeyframes: holdKeyframes,
            // A gentle slump only: with the forearms already at floor
            // level, the standing-scale shoulder droop would push the
            // wrists through the ground.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: holdPose(atPhase: 1),
                to: holdPose(atPhase: 0),
                duration: 3.0,
                settle: 0.35
            ),
            cues: [
                MascotCue("Straight line head to heels"),
                MascotCue("Keep hips level"),
                MascotCue("Squeeze glutes and brace", window: 0.25...0.75),
            ],
            blinkPhases: [0.08, 0.28, 0.46].map { $0 * workShare }
                + [workShare + 0.35 * (1 - workShare), workShare + 0.72 * (1 - workShare)],
            restingPhase: 0.5,
            smoothing: .curved,
            dynamics: MascotDynamics(handsBearWeight: true)
        )
    }()
}
