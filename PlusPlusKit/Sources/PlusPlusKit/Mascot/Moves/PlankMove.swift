import Foundation

/// Forearm plank: a single 20-second hold. A STRAIGHT line from head
/// to heels (build-88 caught the hips dipping and a harsh pointed
/// ankle), on tucked toes: caps flat on the floor, feet near-vertical
/// on the forefoot hinge, ankles close to neutral. Forearms rest on
/// the floor with the hands as relaxed NEUTRAL FISTS continuing the
/// forearms, pinky edge riding the ground (the hand round: the old
/// curled-under fingers hovered mid-air, and a flat palm-down hand
/// would demand more pronation than a horizontal forearm has). The
/// pose barely moves — breathing micro-sway only — while the effort
/// channel ramps across the hold (Dave's rule for static holds: the
/// strain builds over time, not per rep).
enum PlankMove {
    static let animation: ExerciseAnimation = {
        let holdSeconds = 20.0
        let breathCycles = 4.0
        let hipPitch = 2.0
        let footWorldPitch = 72.0
        let elbowPadY = 0.05
        let toeY = 0.018

        func plankPose(bodyPitch: Double, chestSwayDegrees: Double = 0) -> MascotPose {
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
                    MascotPoseBuilder.torso(
                        chest: .deg(pitch: chestSwayDegrees),
                        neck: .deg(pitch: -6),
                        head: .deg(pitch: -2)
                    )
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
        let basePitch = (low + high) / 2
        let baseRaw = settled(bodyPitch: basePitch).pose
        let basePositions = baseRaw.jointPositions(skeleton: .standard)
        // The elbows' settled world spots become FIXED anchors: every
        // hold sample and rest-beat pose re-pins to them, so breathing
        // lives in the torso while the planted forearms never bob (the
        // old root-lift sway floated the whole body, hands included).
        let elbowAnchors: [(MascotJoint, Vec3)] = elbowJoints.compactMap { joint in
            basePositions[joint].map { (joint, $0) }
        }

        /// The floor closure shared by every emitted pose: pin the
        /// elbows, keep the hands as NEUTRAL FISTS continuing the
        /// forearms (wrist zero — the anatomically honest forearm-
        /// plank hand: palm-down there would demand more pronation
        /// than a horizontal forearm has; real planks rest the pinky
        /// edge of a relaxed fist), and bisect the elbow flexion so
        /// the fist's lowest surface rides just off the floor.
        func flattened(_ pose: MascotPose) -> MascotPose {
            var candidate = MascotPoseBuilder.anchored(pose, anchors: elbowAnchors)
            var neutral = candidate.joints
            // Thumb-up neutral: the rig's zero hand is palm-up on a
            // horizontal forearm, so the relaxed thumbs-up fist is ~90
            // of pronation — riding the wrist stop, pinky edge down.
            neutral[.leftWrist] = .deg(yaw: -88)
            neutral[.rightWrist] = .deg(yaw: 88)
            candidate.joints = neutral
            func fistClearance(elbowPitch: Double) -> Double {
                var probe = candidate
                var joints = probe.joints
                for joint in elbowJoints {
                    let current = joints[joint] ?? .zero
                    joints[joint] = EulerAngles(pitch: elbowPitch, yaw: current.yaw, roll: current.roll)
                }
                probe.joints = joints
                let frames = probe.jointFrames(skeleton: .standard)
                var lowest = Double.infinity
                for (wrist, side) in [(MascotJoint.leftWrist, 1.0), (.rightWrist, -1.0)] {
                    guard let frame = frames[wrist] else { continue }
                    for capsule in MascotHand.capsules(state: .fist, side: side, wrist: frame) {
                        lowest = min(lowest, min(capsule.from.y, capsule.to.y) - capsule.radius)
                    }
                }
                return lowest
            }
            let toRadians = Double.pi / 180
            var lowPitch = -110.0 * toRadians
            var highPitch = -60.0 * toRadians
            for _ in 0..<32 {
                let mid = (lowPitch + highPitch) / 2
                // Less flexion drops the hand end below the horizontal
                // forearm line; more flexion lifts it.
                if fistClearance(elbowPitch: mid) > 0.001 {
                    lowPitch = mid
                } else {
                    highPitch = mid
                }
            }
            let solvedPitch = (lowPitch + highPitch) / 2
            var joints = candidate.joints
            for joint in elbowJoints {
                let current = joints[joint] ?? .zero
                joints[joint] = EulerAngles(pitch: solvedPitch, yaw: current.yaw, roll: current.roll)
            }
            candidate.joints = joints
            return candidate
        }

        // The hold: sampled sinusoidal breathing at a resolution that
        // keeps linear interpolation smooth, effort ramping underneath.
        // Each sample re-runs the whole floor closure, so the chest
        // sway breathes through the HIPS while every contact stays put.
        func holdPose(atPhase phase: Double) -> MascotPose {
            let sway = sin(2 * .pi * breathCycles * phase)
            var pose = flattened(plankPose(bodyPitch: basePitch, chestSwayDegrees: 1.2 * sway))
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
            // A gentle slump only, re-settled onto the floor closure:
            // with the forearms already at floor level, the
            // standing-scale shoulder droop would push the wrists
            // through the ground.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: holdPose(atPhase: 1),
                to: holdPose(atPhase: 0),
                duration: 3.0,
                settle: 0.35,
                solve: { flattened($0) }
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
            dynamics: MascotDynamics(forearmsBearWeight: true)
        )
    }()
}
