import Foundation

/// Push-up: the rig pitches forward into a straight-arm plank, the
/// elbows fold the body down to the floor, and the press back up
/// carries the effort spike. Hands AND toes stay planted through the
/// rep — the wrists are root-solved, the toes are ankle-solved, and
/// the bottom's body pitch + slight hip flex were tuned numerically so
/// the toes return to the top pose's exact spot (4 mm residual): the
/// body pivots about the toes, the way physics says it must.
enum PushUpMove {
    static let animation: ExerciseAnimation = {
        // Numerically solved constants (round-2 probe work, re-solved
        // in round 3 when the floor contract moved to the REAL foot
        // and hand surfaces): the top rides at 73 degrees so the
        // SHORT-armed chunky bot's toes actually reach the floor; the
        // bottom tips 4.5 degrees further and flexes the hips 15.5
        // degrees, which keeps the toe corners pinned to 2 mm while
        // the chest drops to 0.184 m (0.176 m of travel).
        let topPitch = 73.0
        let bottomPitch = 77.5
        let bottomShoulder = 0.0
        let bottomElbow = -120.0
        let bottomHip = 15.5
        // Wrist height that rests the flat hand's contact pad ON the
        // floor (wrist joint - 0.0475 of hand). The first cut anchored
        // the wrists at 0.03 and the hands sank 2 cm into the ground —
        // the round-3 palm-pad invariant now measures the real hand
        // underside.
        let handY = 0.049

        func plankPose(
            bodyPitch: Double,
            shoulderPitch: Double,
            elbowPitch: Double,
            hipPitch: Double,
            effort: Double
        ) -> MascotPose {
            // Neck near neutral (build-80: it was craned back); the toe
            // solve replaces any eyeballed ankle angle.
            MascotPose(
                rootRotation: .deg(pitch: bodyPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: shoulderPitch),
                        elbow: .deg(pitch: elbowPitch)
                    ),
                    MascotPoseBuilder.symmetricLegs(hip: .deg(pitch: hipPitch), ankle: .deg(pitch: -75)),
                    MascotPoseBuilder.torso(neck: .deg(pitch: -12), head: .deg(pitch: -6))
                ),
                effort: effort
            )
        }

        // Top: arms world-vertical under the shoulders, wrists dropped
        // onto the floor, toes solved down to it.
        var top = plankPose(bodyPitch: topPitch, shoulderPitch: -topPitch, elbowPitch: 0, hipPitch: 0, effort: 0.3)
        let handJoints: [MascotJoint] = [.leftWrist, .rightWrist]
        let topPositions = top.jointPositions(skeleton: .standard)
        let wristTargets: [(MascotJoint, Vec3)] = handJoints.compactMap { joint in
            guard let now = topPositions[joint] else { return nil }
            return (joint, Vec3(now.x, handY, now.z))
        }
        top = MascotPoseBuilder.anchored(top, anchors: wristTargets)
        top = MascotPoseBuilder.solvingToes(top)
        let plantedWrists = top.jointPositions(skeleton: .standard)

        var bottom = plankPose(
            bodyPitch: bottomPitch,
            shoulderPitch: bottomShoulder,
            elbowPitch: bottomElbow,
            hipPitch: bottomHip,
            effort: 0.5
        )
        bottom = MascotPoseBuilder.anchored(bottom, anchors: handJoints.compactMap { joint in
            plantedWrists[joint].map { (joint, $0) }
        })
        bottom = MascotPoseBuilder.solvingToes(bottom)

        // Lower and press as baked paths where every sample keeps the
        // hands pinned AND the toes grounded. A lerped pose alone can't
        // do both — with hands fixed, dropping the chest pivots the
        // body about the TOES, so each sample re-solves its own body
        // pitch: rotate until the ankle base returns to a reachable
        // height (interpolated from the solved endpoints), re-anchor
        // the wrists, then drop the toes. The solved pitches vary
        // smoothly, which keeps the sampling spline calm (per-sample
        // solving without this blew up 25 cm mid-press).
        let topAnkleY = plantedWrists[.leftAnkle]!.y
        let bottomAnkleY = bottom.jointPositions(skeleton: .standard)[.leftAnkle]!.y

        func grounded(_ pose: MascotPose, targetAnkleY: Double) -> MascotPose {
            var candidate = pose
            for _ in 0..<6 {
                candidate = MascotPoseBuilder.anchored(candidate, anchors: handJoints.compactMap { joint in
                    plantedWrists[joint].map { (joint, $0) }
                })
                let ankleY = candidate.jointPositions(skeleton: .standard)[.leftAnkle]!.y
                // Empirically d(ankleY)/d(pitch) is about +0.57 m/rad
                // (raising the pitch raises the foot end), so correct
                // AGAINST the error, one clamped step at a time — the
                // first cut had the sign flipped and the feedback loop
                // back-flipped the bot to 220 degrees.
                let step = min(max(-(ankleY - targetAnkleY) / 0.6, -0.1), 0.1)
                candidate.rootRotation.pitch += step
                candidate.rootRotation.pitch = min(max(candidate.rootRotation.pitch, 1.05), 1.57)
            }
            candidate = MascotPoseBuilder.anchored(candidate, anchors: handJoints.compactMap { joint in
                plantedWrists[joint].map { (joint, $0) }
            })
            return MascotPoseBuilder.solvingToes(candidate)
        }

        func groundedSpan(_ raw: [MascotKeyframe], ankleFrom: Double, ankleTo: Double) -> [MascotKeyframe] {
            let count = raw.count
            return raw.enumerated().map { index, kf in
                let f = Double(index) / Double(count - 1)
                let target = ankleFrom + (ankleTo - ankleFrom) * f
                return MascotKeyframe(t: kf.t, pose: grounded(kf.pose, targetAnkleY: target), easing: .linear)
            }
        }
        let descent = groundedSpan(MascotPoseBuilder.span(
            from: top, to: bottom, t0: 0, t1: 0.42,
            effortKeys: [(0, 0.3), (1, 0.5)]
        ), ankleFrom: topAnkleY, ankleTo: bottomAnkleY)
        let press = groundedSpan(MascotPoseBuilder.span(
            from: bottom, to: top, t0: 0.52, t1: 0.92,
            easing: .easeOut,
            effortKeys: [(0, 0.5), (0.5, 0.9), (1, 0.4)]
        ), ankleFrom: bottomAnkleY, ankleTo: topAnkleY)

        var repKeyframes = descent
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: descent[descent.count - 1].pose, easing: .linear))
        repKeyframes.append(contentsOf: press.dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: repKeyframes[0].pose))
        let loopPose = repKeyframes[0].pose

        return ExerciseAnimation(
            exerciseName: "Push-Up",
            style: .reps(repDuration: 2.2),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: loopPose, to: loopPose, duration: 2.4, settle: 0.7),
            cues: [
                MascotCue("Straight line head to heels"),
                MascotCue("Elbows about 45 degrees"),
                MascotCue("Chest toward the floor", window: 0.06...0.5),
                MascotCue("Press the floor away", window: 0.55...0.95),
            ],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.2, restDuration: 2.4, repPhase: 0.04
            ),
            restingPhase: 0.42,
            smoothing: .curved,
            dynamics: MascotDynamics(handsBearWeight: true)
        )
    }()
}
