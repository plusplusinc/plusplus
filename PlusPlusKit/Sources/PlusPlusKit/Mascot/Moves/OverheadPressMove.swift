import Foundation

/// Barbell overhead press: bar racked at the collarbone, pressed past
/// the face to a stacked overhead lockout, lowered under control. The
/// bar PATH is authored geometry — per baked sample the grip servo
/// pins the palms to a piecewise-linear rack -> face-pass -> lockout
/// line (an angle-space lerp arcs the bar through the helmet; the
/// scratch trial measured 54 mm of bar-in-head before the targets
/// took over, 9.6 mm of clearance after). The head dips back through
/// the middle leg — the classic "move your face" — and returns once
/// the bar is past.
///
/// All three arm configs are scratch-scan winners solved in ONE
/// shoulder-roll basin (rolls 45/35/2 — a rack scanned unbounded
/// landed at roll 100, elbows flared sideways, and the unwind swung
/// the mid-press wild), scanned WITH the servo's hand-continues-
/// forearm objective: palm exactly on target, grip axis 0.0 degrees
/// off the bar, thumb fully inward, inside every anatomical bound.
enum OverheadPressMove {
    static let animation: ExerciseAnimation = {
        let legs = MascotPoseBuilder.symmetricLegs(hip: .deg(roll: 3))

        func pressPose(
            spine: Double, neck: Double,
            shoulder: EulerAngles, elbow: EulerAngles, wrist: EulerAngles,
            effort: Double
        ) -> MascotPose {
            MascotPoseBuilder.plantingFeet(MascotPose(
                joints: MascotPoseBuilder.merge(
                    legs,
                    MascotPoseBuilder.torso(spine: .deg(pitch: spine), neck: .deg(pitch: neck)),
                    MascotPoseBuilder.symmetricArms(shoulder: shoulder, elbow: elbow, wrist: wrist)
                ),
                effort: effort
            ))
        }

        // Scan winners (one decimal), all in the same roll basin, and
        // scanned with the servo's own hand-continues-forearm term so
        // the per-sample servo starts near its own optimum.
        let rack = pressPose(
            spine: -3, neck: 0,
            shoulder: .deg(pitch: -49.2, yaw: 28.0, roll: 45.0),
            elbow: .deg(pitch: -127.4, yaw: -23.0),
            wrist: .deg(pitch: -49.1, yaw: -88.0, roll: -40.3),
            effort: 0.35
        )
        let mid = pressPose(
            spine: -2, neck: -14,
            shoulder: .deg(pitch: -101.3, yaw: 19.8, roll: 35.0),
            elbow: .deg(pitch: -93.8, yaw: -23.0),
            wrist: .deg(pitch: -57.6, yaw: -87.8, roll: -39.5),
            effort: 0.75
        )
        let lockout = pressPose(
            spine: 0, neck: 0,
            shoulder: .deg(pitch: -157.1, yaw: 80.6, roll: 2.2),
            elbow: .deg(pitch: -15.5, yaw: -13.6),
            wrist: .deg(pitch: 6.1, yaw: -85.2, roll: 7.5),
            effort: 0.85
        )

        // The authored bar line (shoulder rest height 0.907): collarbone
        // rack, the face-pass held forward of the tipped-back helmet,
        // lockout stacked over the shoulders above the helmet top.
        let rackBar = Vec3(0.26, 0.927, 0.14)
        let midBar = Vec3(0.26, 1.10, 0.15)
        let lockBar = Vec3(0.26, 1.266, 0.02)
        let station = 0.26

        // The grip servo balances station against its wrist-stack
        // residuals, and at this move's mid-press configs its
        // equilibrium parks the palm up to 10 mm outboard of the
        // target — past the 8 mm one-station law. The equilibrium is
        // locally affine in the target, so one FEEDFORWARD round
        // cancels it: solve, measure the x offset, re-solve with the
        // target shifted the other way. Deterministic and smooth.
        func solved(_ sample: MascotPose, bar: Vec3) -> MascotPose {
            func once(_ target: Vec3) -> MascotPose {
                MascotPoseBuilder.grippingTheBar(
                    MascotPoseBuilder.coordinating(sample, props: [.barbell]),
                    station: station, palmTarget: target
                )
            }
            let first = once(bar)
            let frames = first.jointFrames(skeleton: .standard)
            guard let lw = frames[.leftWrist] else { return first }
            let error = (lw.position + lw.rotation.rotate(MascotGrip.palmOffset)).x - station
            return once(Vec3(bar.x - error, bar.y, bar.z))
        }

        // A span variant whose solve tracks the authored bar line —
        // the target lerps with the pose, so the bar path can never
        // wander off the authored geometry between keys. The lerp is
        // EASED inside each leg: velocity reaches zero at both ends,
        // so the spline can't overshoot at the rack/face-pass/lockout
        // corners (a linear bake drifted the palm 11 mm off station
        // exactly at the face-pass corner; denser and
        // continuation-seeded bakes both jittered worse). Eased f=0/1
        // hit the endpoint configs EXACTLY, so every leg boundary key
        // is the same canonical solve and all seams are exact by
        // pure-function determinism.
        func barLeg(
            from: MascotPose, fromBar: Vec3, to: MascotPose, toBar: Vec3,
            t0: Double, t1: Double, effortKeys: [(Double, Double)]
        ) -> [MascotKeyframe] {
            let steps = 6
            return (0...steps).map { i in
                let f = Double(i) / Double(steps)
                let e = MascotEasing.easeInOut.apply(f)
                var pose = solved(from.lerp(to: to, t: e), bar: fromBar.lerp(to: toBar, t: e))
                pose.effort = MascotPoseBuilder.effortValue(at: f, keys: effortKeys)
                return MascotKeyframe(t: t0 + (t1 - t0) * f, pose: pose, easing: .linear)
            }
        }

        let rackS = solved(rack, bar: rackBar)
        var repKeyframes = [MascotKeyframe(t: 0, pose: rackS, easing: .hold)]
        repKeyframes.append(contentsOf: barLeg(
            from: rack, fromBar: rackBar, to: mid, toBar: midBar,
            t0: 0.06, t1: 0.22, effortKeys: [(0, 0.35), (1, 0.8)]
        ))
        let pressHigh = barLeg(
            from: mid, fromBar: midBar, to: lockout, toBar: lockBar,
            t0: 0.22, t1: 0.38, effortKeys: [(0, 0.8), (0.5, 0.9), (1, 0.6)]
        )
        repKeyframes.append(contentsOf: pressHigh.dropFirst())
        // Lockout hold: the EXACT baked lockout pose (pause stillness
        // demands bitwise identity), effort easing off so the peak
        // sits mid-drive.
        var lockHold = pressHigh.last!.pose
        lockHold.effort = 0.5
        repKeyframes.append(MascotKeyframe(t: 0.50, pose: lockHold, easing: .linear))
        repKeyframes.append(contentsOf: barLeg(
            from: lockout, fromBar: lockBar, to: mid, toBar: midBar,
            t0: 0.50, t1: 0.73, effortKeys: [(0, 0.5), (1, 0.42)]
        ).dropFirst())
        repKeyframes.append(contentsOf: barLeg(
            from: mid, fromBar: midBar, to: rack, toBar: rackBar,
            t0: 0.73, t1: 0.94, effortKeys: [(0, 0.42), (1, 0.35)]
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: rackS))

        return ExerciseAnimation(
            exerciseName: "Overhead Press",
            style: .reps(repDuration: 3.2),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            // The standing phew, with the bar re-pinned to its rack
            // line every interior beat — the mascot breathes behind a
            // stationary bar, so the one-station law holds through the
            // rest too.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: rackS, to: rackS, duration: 2.6,
                solve: { pose in
                    MascotPoseBuilder.grippingTheBar(
                        pose, station: station, palmTarget: rackBar
                    )
                }
            ),
            cues: [
                MascotCue("Elbows under the bar"),
                MascotCue("Press past your face", window: 0.06...0.38),
                MascotCue("Lower to the collarbone", window: 0.50...0.94),
            ],
            props: [.barbell],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.2, restDuration: 2.6, repPhase: 0.98
            ),
            restingPhase: 0.46,
            smoothing: .curved
        )
    }()
}
