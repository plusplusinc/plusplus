import Foundation

/// Push-up: a STRAIGHT line from head to heels (the move's own first
/// cue — build-88 caught the hips sagging and the head craned back),
/// pivoting about tucked toes: the toe caps lie flat on the floor, the
/// feet stand near-vertical on the forefoot hinge, and the ankles sit
/// close to neutral, exactly like a human on their toes. Wrists are
/// root-anchored; each baked sample re-solves the body pitch so the
/// toe hinges ride at cap-flat height while the chest travels.
enum PushUpMove {
    static let animation: ExerciseAnimation = {
        // The straight-line law: hips within a couple of degrees of
        // the body line (invariant-enforced), head continuing the line
        // with the gaze at the floor slightly ahead — never craned.
        let hipPitch = 2.0
        // Feet tucked at 72 degrees to the floor: toe caps flat, toe
        // hinge at -72 (inside the anatomical -80 bound with margin).
        let footWorldPitch = 72.0
        // Wrist height that rests the flat PLANTED hand on the floor
        // (the hand round: heel line and finger pads down, metacarpals
        // arched at the planted slope — the old 0.049 assumed the
        // curled fist block, which read as puppy-paws on device).
        let handY = MascotHand.plantedWristHeight
        // Toe hinge height when the cap lies flat: half the cap's
        // thickness above the floor.
        let toeY = 0.018

        func plankPose(
            bodyPitch: Double,
            shoulderPitch: Double,
            elbowPitch: Double,
            footPitch: Double,
            effort: Double
        ) -> MascotPose {
            // Ankle closes the chain to the given foot angle; the toe
            // cap counter-rotates flat.
            let anklePitch = footPitch - bodyPitch - hipPitch
            return MascotPose(
                rootRotation: .deg(pitch: bodyPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: shoulderPitch),
                        elbow: .deg(pitch: elbowPitch)
                    ),
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hipPitch),
                        ankle: .deg(pitch: anklePitch),
                        toe: .deg(pitch: -footPitch)
                    ),
                    MascotPoseBuilder.torso(neck: .deg(pitch: -5), head: .deg(pitch: -2))
                ),
                effort: effort
            )
        }

        let handJoints: [MascotJoint] = [.leftWrist, .rightWrist]
        let toeJoints: [MascotJoint] = [.leftToe, .rightToe]
        // The palm-flattening seed: near-full wrist extension, with a
        // deliberate NEGATIVE yaw bias — fingers-forward is reachable
        // by spinning the arm either way around the forearm, and an
        // unbiased seed let neighboring samples pick opposite spins
        // (the flip read as the hand snapping over between frames).
        let palmSeed = EulerAngles.deg(pitch: 70, yaw: -60)
        // The humeral-spin half of the twist (census-scanned shape).
        let spinSeed = (yaw: -60.0 * .pi / 180, roll: 60.0 * .pi / 180)

        // Provisional top: wrists dropped to the floor, body pitch
        // bisected until the toe hinges reach cap-flat height. This
        // fixes WHERE the hands and toes live; everything after
        // anchors to those spots exactly.
        func provisionalTop() -> MascotPose {
            func toeHeight(at bodyPitch: Double) -> (pose: MascotPose, y: Double) {
                // -87, not the vertical-arm -72: the straight arm
                // swings ~15 degrees toward the head, planting the
                // hands slightly AHEAD of the shoulder line. That
                // forearm lean is what buys the flat palm its last
                // degrees — the hand bends back 90 minus the lean,
                // and the wrist stops at 78.
                var pose = plankPose(
                    bodyPitch: bodyPitch, shoulderPitch: -87,
                    elbowPitch: 0, footPitch: footWorldPitch, effort: 0.3
                )
                let positions = pose.jointPositions(skeleton: .standard)
                let targets: [(MascotJoint, Vec3)] = handJoints.compactMap { joint in
                    positions[joint].map { (joint, Vec3($0.x, handY, $0.z)) }
                }
                pose = MascotPoseBuilder.anchored(pose, anchors: targets)
                return (pose, pose.jointPositions(skeleton: .standard)[.leftToe]!.y)
            }
            var low = 60.0
            var high = 80.0
            for _ in 0..<36 {
                let mid = (low + high) / 2
                if toeHeight(at: mid).y > toeY {
                    high = mid
                } else {
                    low = mid
                }
            }
            return toeHeight(at: (low + high) / 2).pose
        }

        let top = provisionalTop()
        let topPositions = top.jointPositions(skeleton: .standard)
        let toeAnchors: [(MascotJoint, Vec3)] = toeJoints.compactMap { joint in
            topPositions[joint].map { (joint, $0) }
        }
        let wristAnchors: [(MascotJoint, Vec3)] = handJoints.compactMap { joint in
            topPositions[joint].map { (joint, $0) }
        }
        let wristTarget = topPositions[.leftWrist]!

        /// The honest chain closure: TOES anchored exactly (they are
        /// the pivot — planted toes never slide), the body pitch
        /// bisected so the wrists ride at hand height, and the
        /// SHOULDER solved so the arm actually reaches the planted
        /// hand — interpolating the shoulder while force-anchoring the
        /// wrists swept the feet through a 3 cm arc, which the toe
        /// invariant rejected.
        func settled(
            shoulderGuess: Double,
            elbowPitch: Double,
            effort: Double,
            wristLift: Double = 0
        ) -> MascotPose {
            var shoulderPitch = shoulderGuess
            var solved = top
            for _ in 0..<26 {
                func wristState(at bodyPitch: Double) -> (pose: MascotPose, wrist: Vec3) {
                    var pose = plankPose(
                        bodyPitch: bodyPitch, shoulderPitch: shoulderPitch,
                        elbowPitch: elbowPitch, footPitch: footWorldPitch, effort: effort
                    )
                    pose = MascotPoseBuilder.anchored(pose, anchors: toeAnchors)
                    return (pose, pose.jointPositions(skeleton: .standard)[.leftWrist]!)
                }
                // With the toes pinned, raising the body pitch drops
                // the head end: wrist height FALLS as pitch rises.
                var low = 52.0
                var high = 92.0
                for _ in 0..<32 {
                    let mid = (low + high) / 2
                    if wristState(at: mid).wrist.y > wristTarget.y + wristLift {
                        low = mid
                    } else {
                        high = mid
                    }
                }
                let state = wristState(at: (low + high) / 2)
                solved = state.pose
                let errorZ = state.wrist.z - wristTarget.z
                if abs(errorZ) < 0.0008 { break }
                // MORE NEGATIVE shoulder pitch swings the arm forward
                // (+z, ~0.3 m/rad of lever): correct the hand's z error
                // against that slope. (The first cut had the sign
                // flipped and the solver ran to its clamp — the same
                // lesson as the round-2 grounded() gain.)
                shoulderPitch += errorZ / 0.0052
                // Positive pitches allowed: the stacked bottom sweeps
                // the upper arm back past neutral (shoulder extension).
                shoulderPitch = min(max(shoulderPitch, -95), 55)
            }
            // Flat palms LAST, once the contacts have converged: the
            // arm servo's position residuals keep the planted wrists
            // and the authored elbow depth where this loop put them,
            // spending only null-space rotation on the flattening.
            return MascotPoseBuilder.plantingPalms(
                solved, wristSeed: palmSeed, shoulderSpinSeed: spinSeed
            )
        }

        /// The lowest point of either planted hand — the hand's own
        /// sole-corner law (`solvingToes` for hands): whatever residual
        /// tilt the arm's anatomy leaves at depth, the hand must REST
        /// on the floor, never hover and never pierce.
        func lowestHandPoint(_ pose: MascotPose) -> Double {
            let frames = pose.jointFrames(skeleton: .standard)
            var lowest = Double.infinity
            for (wrist, side) in [(MascotJoint.leftWrist, 1.0), (.rightWrist, -1.0)] {
                guard let frame = frames[wrist] else { continue }
                for capsule in MascotHand.capsules(state: .planted, side: side, wrist: frame) {
                    lowest = min(lowest, min(capsule.from.y, capsule.to.y) - capsule.radius)
                }
            }
            return lowest
        }

        /// Solve, then re-solve with the wrist anchor shifted by
        /// however far the tilted hand's lowest point missed the floor
        /// — lifted out of a pierce OR pulled down out of a hover.
        /// Two correction passes: the re-solve can re-tilt slightly,
        /// and the second pass collapses that residual to sub-mm.
        func settledPlanted(
            shoulderGuess: Double, elbowPitch: Double, effort: Double
        ) -> MascotPose {
            var lift = 0.0
            var solved = settled(
                shoulderGuess: shoulderGuess, elbowPitch: elbowPitch, effort: effort
            )
            for _ in 0..<2 {
                let miss = lowestHandPoint(solved)
                if abs(miss) < 0.001 { break }
                lift -= miss
                solved = settled(
                    shoulderGuess: shoulderGuess, elbowPitch: elbowPitch,
                    effort: effort, wristLift: lift
                )
            }
            return solved
        }

        // Bottom: the ARM STAYS STACKED — the forearm holds its lean
        // over the planted hand while the elbow flexes and the upper
        // arm sweeps back toward horizontal (the hand round: the old
        // folded shoulder -10 / elbow -130 bottom left the palm
        // unreachable-flat at any wrist angle — the census proved a
        // flat palm needs the forearm near vertical the whole rep,
        // which is the elbows-over-wrists cue in solver form).
        let settledTop = settledPlanted(shoulderGuess: -87, elbowPitch: 0, effort: 0.3)
        let bottom = settledPlanted(shoulderGuess: 10, elbowPitch: -122, effort: 0.5)

        // Baked spans: the ELBOW is the depth driver; every sample
        // re-solves shoulder + pitch so both contacts stay planted.
        func groundedSpan(
            from: MascotPose, to: MascotPose,
            t0: Double, t1: Double,
            easing: MascotEasing = .easeInOut,
            effortKeys: [(Double, Double)]
        ) -> [MascotKeyframe] {
            let steps = 10
            return (0...steps).map { i in
                let f = Double(i) / Double(steps)
                let eased = easing.apply(f)
                let sample = from.lerp(to: to, t: eased)
                let shoulder = sample.angles(.leftShoulder).pitch * 180 / .pi
                let elbow = sample.angles(.leftElbow).pitch * 180 / .pi
                var pose = settledPlanted(shoulderGuess: shoulder, elbowPitch: elbow, effort: 0)
                pose.effort = MascotPoseBuilder.effortValue(at: f, keys: effortKeys)
                return MascotKeyframe(t: t0 + (t1 - t0) * f, pose: pose, easing: .linear)
            }
        }

        let descent = groundedSpan(
            from: settledTop, to: bottom, t0: 0, t1: 0.46,
            effortKeys: [(0, 0.3), (1, 0.5)]
        )
        let press = groundedSpan(
            from: bottom, to: settledTop, t0: 0.56, t1: 0.92,
            easing: .easeOut,
            effortKeys: [(0, 0.5), (0.5, 0.9), (1, 0.4)]
        )

        var repKeyframes = descent
        repKeyframes.append(MascotKeyframe(t: 0.56, pose: descent[descent.count - 1].pose, easing: .linear))
        repKeyframes.append(contentsOf: press.dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: repKeyframes[0].pose))
        let loopPose = repKeyframes[0].pose

        return ExerciseAnimation(
            exerciseName: "Push-Up",
            style: .reps(repDuration: 2.2),
            repsPerDemoSet: 4,
            repKeyframes: repKeyframes,
            // The beat's interior poses re-anchor to the planted
            // contacts (least-squares over toes + wrists) and re-flatten
            // the palms, so the phew's chest lift can't hover the hands.
            restBeat: MascotPoseBuilder.tiredBeat(
                from: loopPose, to: loopPose, duration: 2.4, settle: 0.7,
                solve: { beat in
                    MascotPoseBuilder.plantingPalms(MascotPoseBuilder.anchored(
                        beat, anchors: toeAnchors + wristAnchors
                    ), wristSeed: palmSeed, shoulderSpinSeed: spinSeed)
                }
            ),
            cues: [
                MascotCue("Straight line head to heels"),
                MascotCue("Elbows about 45 degrees"),
                MascotCue("Chest toward the floor", window: 0.06...0.46),
                MascotCue("Press the floor away", window: 0.55...0.95),
            ],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 4, repDuration: 2.2, restDuration: 2.4, repPhase: 0.04
            ),
            restingPhase: 0.5,
            smoothing: .curved,
            dynamics: MascotDynamics(handsBearWeight: true)
        )
    }()
}
