import Foundation

/// Forearm plank: a single 20-second hold. The pose barely moves —
/// breathing micro-sway only — while the effort channel ramps across
/// the hold (Dave's rule for static holds: the strain builds over time,
/// not per rep), so the eyes squeeze harder the longer the hold runs.
enum PlankMove {
    static let animation: ExerciseAnimation = {
        let bodyPitch = 80.0
        let holdSeconds = 20.0
        let breathCycles = 4.0

        var base = MascotPose(
            rootRotation: .deg(pitch: bodyPitch),
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricArms(
                    shoulder: .deg(pitch: -bodyPitch),
                    elbow: .deg(pitch: -90)
                ),
                // Hip pitch tuned so the ankles sit low enough for the
                // toe solve to actually reach the floor (at +8 the feet
                // hung in the air — build-80). Neck near neutral.
                MascotPoseBuilder.symmetricLegs(hip: .deg(pitch: 3), ankle: .deg(pitch: -70)),
                MascotPoseBuilder.torso(neck: .deg(pitch: -14), head: .deg(pitch: -6))
            ),
            effort: 0
        )
        // Rest the forearms on the floor: solve the root so the elbows
        // sit at pad height.
        let positions = base.jointPositions(skeleton: .standard)
        let elbowJoints: [MascotJoint] = [.leftElbow, .rightElbow]
        let elbowTargets: [(MascotJoint, Vec3)] = elbowJoints.compactMap { joint in
            guard let now = positions[joint] else { return nil }
            return (joint, Vec3(now.x, 0.05, now.z))
        }
        base = MascotPoseBuilder.anchored(base, anchors: elbowTargets)
        base = MascotPoseBuilder.solvingToes(base)

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
