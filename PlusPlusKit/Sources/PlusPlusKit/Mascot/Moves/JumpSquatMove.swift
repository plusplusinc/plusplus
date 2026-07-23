import Foundation

/// Jump squat — the catalog's first BALLISTIC move: load a crouch,
/// drive up, LEAVE THE GROUND, land back in the crouch and settle
/// tall. The declared airborne window rides the synthetic-jump
/// harness's proven pattern: the flight path is a true gravity
/// parabola sampled densely on linear keys (the ballistic invariant
/// measures the root falling at 9.81 m/s^2 across the window's
/// interior), and the flight POSE is held rigid so the root's
/// acceleration IS the center of mass's.
///
/// The flight base height is solved so the soles sit exactly at the
/// floor when the parabola crosses zero — the grounded invariant
/// hands over to the ballistic one at the window edges with no gap
/// and no hover.
enum JumpSquatMove {
    static let animation: ExerciseAnimation = {
        let repSeconds = 1.6

        let stand = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricLegs(hip: .deg(roll: 3)),
                MascotPoseBuilder.symmetricArms(shoulder: .deg(roll: 8))
            ),
            effort: 0.2
        ))
        // The loaded crouch: arms swept back, ready to swing.
        let crouch = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: -55, roll: 3), knee: .deg(pitch: 70), ankle: .deg(pitch: -15)
                ),
                MascotPoseBuilder.torso(spine: .deg(pitch: 18), chest: .deg(pitch: 10), neck: .deg(pitch: -14)),
                MascotPoseBuilder.symmetricArms(shoulder: .deg(pitch: 18, roll: 10))
            ),
            effort: 0.5
        ))
        // The landing absorb: same legs, arms finishing forward-down
        // from the flight swing (a straight swing back to the loaded
        // arms would cross the human joint-speed bound).
        // Shallower than the loaded crouch on purpose: the landing
        // has ~0.18 s to fold and ~0.22 s to recover, and a full-depth
        // absorb crossed the human joint-speed bound both ways.
        let landCrouch = MascotPoseBuilder.plantingFeet(MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: -35, roll: 3), knee: .deg(pitch: 45), ankle: .deg(pitch: -10)
                ),
                MascotPoseBuilder.torso(spine: .deg(pitch: 12), chest: .deg(pitch: 7), neck: .deg(pitch: -10)),
                MascotPoseBuilder.symmetricArms(shoulder: .deg(pitch: -10, roll: 10))
            ),
            effort: 0.7
        ))
        // Flight: held rigid through the window — slightly tucked
        // legs, arms swung up.
        // Flat feet in flight, deliberately: pointed toes forced the
        // ankle to rotate through the grounded transitions, and every
        // corner treatment either dug the toe corner into the floor
        // or spiked joint speed. A neutral foot keeps the whole
        // crouch-flight-crouch chain sole-safe with plain keys.
        var flight = MascotPose(
            joints: MascotPoseBuilder.merge(
                // The chain SUMS TO ZERO (hip -7 + knee 12 + ankle -5)
                // like the crouch's, so every lerped sample between
                // ground and flight keeps the soles parallel to the
                // floor — a tilting sole was what kept digging a toe
                // corner in mid-transition.
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: -7, roll: 3), knee: .deg(pitch: 12), ankle: .deg(pitch: -5)
                ),
                MascotPoseBuilder.torso(spine: .deg(pitch: 4)),
                MascotPoseBuilder.symmetricArms(shoulder: .deg(pitch: -38, roll: 12))
            ),
            effort: 0.85
        )
        // Base height: soles exactly on the floor when the parabola
        // reads zero (the window edges), so grounded hands over to
        // ballistic without a hover.
        let flightSoleLow = flight.solePoints(skeleton: .standard).map(\.y).min() ?? 0
        flight.rootTranslation.y -= flightSoleLow - 0.006

        let airborne: ClosedRange<Double> = 0.50...0.75
        let apexPhase = 0.625
        let rise = 9.81 / 2 * pow((airborne.upperBound - airborne.lowerBound) / 2 * repSeconds, 2)

        // Every grounded leg is a DENSE span (a sparse two-key descent
        // let the spline dig the soles 24 mm under the floor mid-way).
        // Grounded flat-to-flat legs re-plant per sample; the launch
        // and landing legs use a one-sided SOLE CLAMP instead — the
        // root is allowed to rise off its lerp, never to drive the
        // sole under the floor. Identity at planted endpoints, so all
        // seams stay exact.
        let plant = { (pose: MascotPose) in MascotPoseBuilder.plantingFeet(pose) }
        let soleClamped = { (pose: MascotPose) -> MascotPose in
            var candidate = pose
            let low = candidate.solePoints(skeleton: .standard).map(\.y).min() ?? 0
            if low < -0.001 {
                candidate.rootTranslation.y += -0.001 - low
            }
            return candidate
        }

        var repKeyframes: [MascotKeyframe] = [
            MascotKeyframe(t: 0, pose: stand, easing: .hold),
            MascotKeyframe(t: 0.10, pose: stand, easing: .easeInOut),
        ]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: stand, to: crouch, t0: 0.10, t1: 0.32, steps: 5,
            effortKeys: [(0, 0.2), (1, 0.5)],
            solve: plant
        ).dropFirst())
        // Launch: crouch up to the flight pose at its window-edge
        // height, sole-clamped so the extension can't scrape.
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: crouch, to: flight, t0: 0.32, t1: airborne.lowerBound, steps: 4,
            easing: .easeIn,
            effortKeys: [(0, 0.5), (1, 0.9)],
            solve: soleClamped
        ).dropFirst())
        // Flight sampled densely so the spline TRACKS the parabola
        // (the synthetic-jump harness's rule) — pose rigid, only the
        // root falls. The window-edge samples ARE the launch/landing
        // span endpoints (parabola zero), so the handoff is seamless.
        let flightSamples = 10
        for i in 1...flightSamples {
            let phase = airborne.lowerBound
                + (airborne.upperBound - airborne.lowerBound) * Double(i) / Double(flightSamples)
            let dt = (phase - apexPhase) * repSeconds
            var sample = flight
            sample.rootTranslation.y += rise - 9.81 / 2 * dt * dt
            sample.effort = 0.85
            repKeyframes.append(MascotKeyframe(t: phase, pose: sample, easing: .linear))
        }
        // Landing absorb, then a long recover — a fast one crossed the
        // human joint-speed bound at the seam.
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: flight, to: landCrouch, t0: airborne.upperBound, t1: 0.86, steps: 4,
            effortKeys: [(0, 0.85), (1, 0.6)],
            solve: soleClamped
        ).dropFirst())
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: landCrouch, to: stand, t0: 0.86, t1: 1, steps: 4,
            effortKeys: [(0, 0.6), (1, 0.2)],
            solve: plant
        ).dropFirst())

        return ExerciseAnimation(
            exerciseName: "Jump Squat",
            style: .reps(repDuration: repSeconds),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: MascotPoseBuilder.tiredBeat(from: stand, to: stand, duration: 2.4),
            cues: [
                MascotCue("Land soft, sink into the crouch"),
                MascotCue("Load the spring", window: 0.06...0.4),
                MascotCue("Explode straight up", window: 0.4...0.75),
            ],
            props: [],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: repSeconds, restDuration: 2.4, repPhase: 0.03
            ),
            restingPhase: 0.28,
            smoothing: .curved,
            dynamics: MascotDynamics(airborneWindows: [airborne])
        )
    }()
}
