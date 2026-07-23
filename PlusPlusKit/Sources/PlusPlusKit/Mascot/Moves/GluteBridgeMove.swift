import Foundation

/// Glute bridge — the first FLOOR-SUPINE move: lying on the back,
/// knees bent with the shins near vertical, drive the hips to a
/// straight shoulder-to-knee line, squeeze, lower with control. The
/// torso stays a rigid plank pivoting about the shoulder blades (only
/// the cowl and helmet keep floor contact at the top — the mid back
/// LIFTS) and the chin stays tucked so the head rests flat throughout.
///
/// All placement numbers are scratch-scan winners (the recipe
/// discipline): the DOWN pose rests every back capsule on the floor
/// within a graze (root->spine +3.0 / spine->chest -1.1 / cowl -3.0 /
/// helmet +5.1 mm) with the soles planted at +0.5 mm; the UP pose
/// pivots to root pitch -108 with the cowl re-seated by a rootY/rootZ
/// solve (-1.0 mm), the helmet held by a 25-degree chin tuck
/// (-0.5 mm), and the ankles re-planted on their DOWN spots by a
/// hip x knee scan (error 1.0 mm).
enum GluteBridgeMove {
    static let animation: ExerciseAnimation = {
        let restRootHeight = MascotSkeleton.standard.restRootHeight

        func bridgePose(
            rootPitch: Double, rootY: Double, rootZ: Double,
            hip: Double, knee: Double, neck: Double,
            effort: Double
        ) -> MascotPose {
            // Flat soles by the supine chain rule (the bench's): the
            // leg chain's pitches cancel.
            let ankle = -(rootPitch + hip + knee)
            return MascotPose(
                rootTranslation: Vec3(0, rootY - restRootHeight, rootZ),
                rootRotation: .deg(pitch: rootPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hip), knee: .deg(pitch: knee), ankle: .deg(pitch: ankle)
                    ),
                    MascotPoseBuilder.torso(neck: .deg(pitch: neck), head: .deg(pitch: 5)),
                    // Arms rest at the sides, angled a touch floorward
                    // (shoulder pitch is "behind the body" — toward the
                    // floor when supine) so the palms press down.
                    MascotPoseBuilder.symmetricArms(
                        shoulder: .deg(pitch: 10, roll: 8),
                        wrist: .deg(yaw: -60)
                    )
                ),
                effort: effort
            )
        }

        let down = bridgePose(
            rootPitch: -89, rootY: 0.078, rootZ: 0,
            hip: -53, knee: 144, neck: 8, effort: 0.2
        )
        let up = bridgePose(
            rootPitch: -108, rootY: 0.192, rootZ: -0.014,
            hip: 3.5, knee: 124, neck: 25, effort: 0.72
        )

        // Mid-lerp the pivot arc is not linear in these coordinates:
        // re-plant the ankles on the DOWN pose's spots every baked
        // sample, then lift the root a hair if the grounded cowl or
        // helmet dips deeper than its endpoint graze. Deterministic,
        // identity at both endpoints.
        let downFrames = down.jointFrames(skeleton: .standard)
        let ankleTargets: [(MascotJoint, Vec3)] = [
            (.leftAnkle, downFrames[.leftAnkle]!.position),
            (.rightAnkle, downFrames[.rightAnkle]!.position),
        ]
        let solve = { (pose: MascotPose) -> MascotPose in
            var candidate = MascotPoseBuilder.anchored(pose, anchors: ankleTargets)
            for _ in 0..<12 {
                var lowest = 0.0
                for capsule in MascotCollision.bodyCapsules(pose: candidate)
                where capsule.name == "chest->neck" || capsule.name == "head" {
                    lowest = min(lowest, min(capsule.from.y, capsule.to.y) - capsule.radius)
                }
                guard lowest < -0.004 else { break }
                candidate.rootTranslation.y += 0.001
            }
            return candidate
        }

        let downS = solve(down)
        var repKeyframes = [MascotKeyframe(t: 0, pose: downS, easing: .hold)]
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: down, to: up, t0: 0.06, t1: 0.40, steps: 8,
            effortKeys: [(0, 0.2), (1, 0.72)],
            solve: solve
        ))
        // The squeeze: held at the top, effort easing off so the peak
        // lands on the rise.
        var squeezeEnd = solve(up)
        squeezeEnd.effort = 0.6
        repKeyframes.append(MascotKeyframe(t: 0.52, pose: squeezeEnd, easing: .linear))
        repKeyframes.append(contentsOf: MascotPoseBuilder.span(
            from: up, to: down, t0: 0.52, t1: 0.94, steps: 8,
            effortKeys: [(0, 0.55), (1, 0.25)],
            solve: solve
        ).dropFirst())
        repKeyframes.append(MascotKeyframe(t: 1, pose: downS))

        let restBeat = MascotPoseBuilder.supineTiredBeat(from: downS, to: downS, duration: 2.4)

        return ExerciseAnimation(
            exerciseName: "Glute Bridge",
            style: .reps(repDuration: 3.0),
            repsPerDemoSet: 3,
            repKeyframes: repKeyframes,
            restBeat: restBeat,
            cues: [
                MascotCue("Feet flat under the knees"),
                MascotCue("Drive the hips to the ceiling", window: 0.06...0.40),
                MascotCue("Lower with control", window: 0.52...0.94),
            ],
            props: [],
            blinkPhases: MascotPoseBuilder.defaultBlinkPhases(
                reps: 3, repDuration: 3.0, restDuration: 2.4, repPhase: 0.02
            ),
            restingPhase: 0.45,
            smoothing: .curved
        )
    }()
}
