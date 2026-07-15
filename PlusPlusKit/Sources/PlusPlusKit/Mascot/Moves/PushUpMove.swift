import Foundation

/// Push-up: the whole rig pitches forward into a straight-arm plank
/// (hands and toes on the floor), the elbows fold the body down, and
/// the press back up carries the effort spike. The hands stay planted
/// through the rep — the root solver pins the wrists in world space.
enum PushUpMove {
    static let animation: ExerciseAnimation = {
        let bodyPitch = 78.0
        let handY = 0.03

        func plankPose(shoulderPitch: Double, elbowPitch: Double, effort: Double) -> MascotPose {
            MascotPose(
                rootRotation: .deg(pitch: bodyPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: shoulderPitch),
                        elbow: .deg(pitch: elbowPitch)
                    ),
                    MascotPoseBuilder.symmetricLegs(ankle: .deg(pitch: -75)),
                    MascotPoseBuilder.torso(neck: .deg(pitch: -35), head: .deg(pitch: -15))
                ),
                effort: effort
            )
        }

        // Top of the push-up: arms world-vertical under the shoulders,
        // wrists dropped onto the floor.
        var top = plankPose(shoulderPitch: -bodyPitch, elbowPitch: 0, effort: 0.3)
        let handJoints: [MascotJoint] = [.leftWrist, .rightWrist]
        let topPositions = top.jointPositions(skeleton: .standard)
        let wristTargets: [(MascotJoint, Vec3)] = handJoints.compactMap { joint in
            guard let now = topPositions[joint] else { return nil }
            return (joint, Vec3(now.x, handY, now.z))
        }
        top = MascotPoseBuilder.anchored(top, anchors: wristTargets)
        let plantedWrists = top.jointPositions(skeleton: .standard)

        // Bottom: upper arms swing 45 degrees toward the feet, forearms
        // stay vertical, and the root re-solves so the planted wrists do
        // not move.
        var bottom = plankPose(shoulderPitch: -bodyPitch + 45, elbowPitch: -45, effort: 0.5)
        bottom = MascotPoseBuilder.anchored(bottom, anchors: handJoints.compactMap { joint in
            plantedWrists[joint].map { (joint, $0) }
        })

        // Lower and press as baked paths with the wrists re-pinned at
        // every sample, so the hands never leave their spot.
        let pinnedHands: (MascotPose) -> MascotPose = { pose in
            MascotPoseBuilder.anchored(pose, anchors: handJoints.compactMap { joint in
                plantedWrists[joint].map { (joint, $0) }
            })
        }
        var repKeyframes = MascotPoseBuilder.span(
            from: top, to: bottom, t0: 0, t1: 0.42,
            effortKeys: [(0, 0.3), (1, 0.5)],
            solve: pinnedHands
        )
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: bottom, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: bottom, to: top, t0: 0.52, t1: 0.92,
            easing: .easeOut,
            effortKeys: [(0, 0.5), (0.5, 0.9), (1, 0.4)],
            solve: pinnedHands
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: top))

        return ExerciseAnimation(
            exerciseName: "Push-Up",
            style: .reps(repDuration: 2.2),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: top, to: top, duration: 2.4, slump: 0.7),
            cues: [
                MascotCue("Straight line head to heels", window: 0.0...0.3),
                MascotCue("Elbows about 45 degrees", window: 0.2...0.5),
                MascotCue("Chest toward the floor", window: 0.32...0.55),
                MascotCue("Press the floor away", window: 0.55...0.92),
            ],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.2, restDuration: 2.4, repPhase: 0.04
            ),
            restingPhase: 0.42
        )
    }()
}
