import Foundation

/// Pull-up — the catalog's first HANGING move: a dead hang from the
/// fixed bar (`MascotProp.pullUpBar`, geometry in `MascotSupport`),
/// pulling to a chest-toward-the-bar finish with the face looking up
/// over it, then lowering to a full hang. Support is the BAR, not the
/// floor: `dynamics.hangsFromBar` swaps the grounded invariant for
/// the hang law (palms on the bar line, one station, feet never
/// touching down), plus the barbell moves' grip-axis alignment law.
/// The thumb-chirality (overhand vs suicide-grip read) is NOT
/// test-enforced for the fixed bar — the overhead wrap reaches the
/// bar through a different spin chain than a barbell lift, and the
/// honest wrap for it is a device-pass item.
///
/// The top config is a scratch-descent winner: grip axis 0.0 degrees
/// off the bar, helmet 27 mm clear of it — the clearance comes from a
/// hard neck arch (the "look over the bar" finish), because the
/// helmet's chain radius around the bar is otherwise SHORTER than the
/// helmet itself; a literal chin-over would swallow the bar. The
/// station (0.127) is the top bracket's honest reach at full elbow
/// flexion; a per-sample shoulder-yaw bisection pins every baked
/// sample's palm to it, and `hangingFromTheBar` then seats the palms
/// on the bar line — root translation, never wrist cheating.
enum PullUpMove {
    static let animation: ExerciseAnimation = {
        let station = 0.127

        let hangSeed = MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricArms(
                    shoulder: .deg(pitch: -172, yaw: -93, roll: 15),
                    elbow: .deg(pitch: -5),
                    wrist: .deg(pitch: 5, yaw: -85)
                ),
                MascotPoseBuilder.symmetricLegs(
                    knee: .deg(pitch: 12), ankle: .deg(pitch: 25)
                )
            ),
            effort: 0.3
        )
        let topSeed = MascotPose(
            rootRotation: .deg(pitch: -4),
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricArms(
                    shoulder: .deg(pitch: -73.4, yaw: -63.2, roll: 14.6),
                    elbow: .deg(pitch: -145.0, yaw: 5.1),
                    wrist: .deg(pitch: 36.1, yaw: -68.7, roll: -40.4)
                ),
                MascotPoseBuilder.symmetricLegs(
                    knee: .deg(pitch: 25), ankle: .deg(pitch: 25)
                ),
                MascotPoseBuilder.torso(
                    // -9, not -10: the arch sits a hair inside the
                    // spine's -10 stop so the spline can't graze past.
                    spine: .deg(pitch: -9), chest: .deg(pitch: -8),
                    neck: .deg(pitch: -42), head: .deg(pitch: -12)
                )
            ),
            effort: 0.85
        )

        // The station pin: bisect a symmetric shoulder-yaw delta until
        // the left palm sits exactly at its station along the bar
        // (palm x is monotone in yaw across this move's configs), then
        // hang the root so the palms land on the bar line. Palm x is
        // root-translation-invariant, so the order is exact.
        let solve = { (pose: MascotPose) -> MascotPose in
            func palmX(_ candidate: MascotPose) -> Double {
                let frames = candidate.jointFrames(skeleton: .standard)
                guard let lw = frames[.leftWrist] else { return station }
                return (lw.position + lw.rotation.rotate(MascotGrip.palmOffset)).x
            }
            // Two width DOFs move together: shoulder yaw (the hanging
            // arm's swing) and elbow yaw (the radioulnar share — at
            // the folded top bracket it is the one channel with real
            // lateral reach). Both clamped inside their anatomical
            // tables — an unclamped pin walked the hang's yaw past
            // the joint-range law.
            func adjusted(_ u: Double) -> MascotPose {
                var candidate = pose
                var joints = candidate.joints
                // 92.5, not 94.5: the spline overshoots ~1 degree past
                // its keys at the hang plateau, and the anatomical
                // bound is 95.
                let shoulderBound = 92.5 * Double.pi / 180
                let elbowBound = 22.0 * Double.pi / 180
                let left = joints[.leftShoulder] ?? .zero
                let right = joints[.rightShoulder] ?? .zero
                joints[.leftShoulder] = EulerAngles(
                    pitch: left.pitch,
                    yaw: min(max(left.yaw + u * 0.08, -shoulderBound), shoulderBound),
                    roll: left.roll
                )
                joints[.rightShoulder] = EulerAngles(
                    pitch: right.pitch,
                    yaw: min(max(right.yaw - u * 0.08, -shoulderBound), shoulderBound),
                    roll: right.roll
                )
                let leftElbow = joints[.leftElbow] ?? .zero
                let rightElbow = joints[.rightElbow] ?? .zero
                joints[.leftElbow] = EulerAngles(
                    pitch: leftElbow.pitch,
                    yaw: min(max(leftElbow.yaw + u * 0.15, -elbowBound), elbowBound),
                    roll: leftElbow.roll
                )
                joints[.rightElbow] = EulerAngles(
                    pitch: rightElbow.pitch,
                    yaw: min(max(rightElbow.yaw - u * 0.15, -elbowBound), elbowBound),
                    roll: rightElbow.roll
                )
                candidate.joints = joints
                return candidate
            }
            // BOUNDED authority: enough to hold the whole path on
            // station, far too little to swing the elbows across the
            // midline (an unbounded pin folded the upper arms 45 mm
            // into each other mid-pull).
            var lowU = -1.0
            var highU = 1.0
            let rising = palmX(adjusted(highU)) > palmX(adjusted(lowU))
            for _ in 0..<36 {
                let mid = (lowU + highU) / 2
                if (palmX(adjusted(mid)) < station) == rising {
                    lowU = mid
                } else {
                    highU = mid
                }
            }
            return MascotPoseBuilder.hangingFromTheBar(adjusted((lowU + highU) / 2))
        }

        // The mid-pull waypoint: halfway shapes with the elbows FLARED
        // 12 degrees outward — a straight hang-to-top lerp sweeps the
        // upper arms 21 mm into the helmet (and lets the grip width
        // sag off station); the flare clears both at once, and is what
        // elbows genuinely do mid-pull.
        let midSeed: MascotPose = {
            var mid = hangSeed.lerp(to: topSeed, t: 0.5)
            var joints = mid.joints
            for (joint, side) in [(MascotJoint.leftShoulder, 1.0), (.rightShoulder, -1.0)] {
                let angles = joints[joint] ?? .zero
                joints[joint] = EulerAngles(
                    pitch: angles.pitch, yaw: angles.yaw,
                    roll: angles.roll + side * 12 * .pi / 180
                )
            }
            mid.joints = joints
            return mid
        }()

        // A quarter waypoint too: the hang-to-mid half shape still
        // grazed the helmet by 8 mm (the arm sweeps right past it), so
        // the lower quarter carries its own 6-degree flare — measured
        // 10 mm clear on station.
        let quarterSeed: MascotPose = {
            var quarter = hangSeed.lerp(to: midSeed, t: 0.5)
            var joints = quarter.joints
            for (joint, side) in [(MascotJoint.leftShoulder, 1.0), (.rightShoulder, -1.0)] {
                let angles = joints[joint] ?? .zero
                joints[joint] = EulerAngles(
                    pitch: angles.pitch, yaw: angles.yaw,
                    roll: angles.roll + side * 6 * .pi / 180
                )
            }
            quarter.joints = joints
            return quarter
        }()

        let hang = solve(hangSeed)
        var repKeyframes = [MascotKeyframe(t: 0, pose: hang, easing: .hold)]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: hangSeed, to: quarterSeed, t0: 0.06, t1: 0.16, steps: 4,
            effortKeys: [(0, 0.3), (1, 0.55)],
            solve: solve
        ))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: quarterSeed, to: midSeed, t0: 0.16, t1: 0.28, steps: 4,
            effortKeys: [(0, 0.55), (1, 0.75)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: topSeed, t0: 0.28, t1: 0.40, steps: 4,
            effortKeys: [(0, 0.75), (0.6, 0.9), (1, 0.75)],
            solve: solve
        ).dropFirst())
        var topHold = solve(topSeed)
        topHold.effort = 0.65
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: topHold, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: topSeed, to: midSeed, t0: 0.52, t1: 0.68, steps: 4,
            effortKeys: [(0, 0.5), (1, 0.45)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: midSeed, to: quarterSeed, t0: 0.68, t1: 0.82, steps: 4,
            effortKeys: [(0, 0.45), (1, 0.38)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: quarterSeed, to: hangSeed, t0: 0.82, t1: 0.94, steps: 4,
            effortKeys: [(0, 0.38), (1, 0.3)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: hang))

        return ExerciseAnimation(
            exerciseName: "Pull-Up",
            style: .reps(repDuration: 3.2),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            // The phew, re-hung: the solve re-pins station and bar
            // line every interior beat, so the breath reads as a
            // hanging shrug and the hang law holds through the rest.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: hang, to: hang, duration: 2.8, settle: 0.55, solve: solve
            ),
            cues: [
                MascotCue("Start from a full hang"),
                MascotCue("Pull your chest to the bar", window: 0.06...0.40),
                MascotCue("Lower all the way down", window: 0.52...0.94),
            ],
            props: [.pullUpBar],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.2, restDuration: 2.8, repPhase: 0.98
            ),
            restingPhase: 0.3,
            smoothing: .curved,
            dynamics: MascotDynamics(hangsFromBar: true)
        )
    }()
}
