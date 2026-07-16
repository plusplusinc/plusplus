import Testing
@testable import PlusPlusKit
import Foundation

/// The invariant sweep every cataloged move must survive. These checks —
/// not a simulator — are what validate the authored animations: loop and
/// seam continuity, no teleports, feet that stay planted, joints that
/// stay human-ish, a face that blinks and tires where it should.
@Suite struct MascotMovesTests {
    private static let skeleton = MascotSkeleton.standard
    private static let sampleCount = 2000

    private static func poseDistance(_ a: MascotPose, _ b: MascotPose) -> Double {
        var worst = a.rootTranslation.distance(to: b.rootTranslation)
        let rotDelta = EulerAngles(
            pitch: a.rootRotation.pitch - b.rootRotation.pitch,
            yaw: a.rootRotation.yaw - b.rootRotation.yaw,
            roll: a.rootRotation.roll - b.rootRotation.roll
        )
        worst = max(worst, rotDelta.maxMagnitude)
        for joint in MascotJoint.allCases {
            let d = EulerAngles(
                pitch: a.angles(joint).pitch - b.angles(joint).pitch,
                yaw: a.angles(joint).yaw - b.angles(joint).yaw,
                roll: a.angles(joint).roll - b.angles(joint).roll
            )
            worst = max(worst, d.maxMagnitude)
        }
        return max(worst, abs(a.effort - b.effort))
    }

    @Test func catalogIntegrity() {
        #expect(MascotMoves.all.count == 5)
        let names = MascotMoves.all.map(\.exerciseName)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(MascotMoves.animation(forExerciseNamed: name)?.exerciseName == name)
        }
        #expect(MascotMoves.animation(forExerciseNamed: "Nonexistent Probe Move") == nil)
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func keyframesAreWellFormed(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for keyframes in [animation.repKeyframes, animation.restBeat.keyframes] {
            #expect(!keyframes.isEmpty)
            #expect(keyframes.first?.t == 0)
            #expect(keyframes.last?.t == 1)
            let sorted = zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.0.t < $0.1.t }
            #expect(sorted, "\(name): keyframe ts must be strictly increasing")
        }
        #expect(animation.repsPerDemoSet >= 1)
        #expect(animation.restBeat.duration > 0, "\(name): the tired beat is part of the demo contract")
        #expect(animation.restingPhase >= 0 && animation.restingPhase <= 1)
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func loopAndSeamContinuity(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let repFirst = animation.repKeyframes.first!.pose
        let repLast = animation.repKeyframes.last!.pose
        // Rep-to-rep seam only matters when the set has more than one rep;
        // a hold flows straight into the tired beat.
        if animation.repsPerDemoSet > 1 {
            #expect(Self.poseDistance(repFirst, repLast) < 1e-9, "\(name): rep loop seam")
        }
        #expect(Self.poseDistance(animation.restBeat.keyframes.first!.pose, repLast) < 1e-9, "\(name): work-to-rest seam")
        #expect(Self.poseDistance(animation.restBeat.keyframes.last!.pose, repFirst) < 1e-9, "\(name): rest-to-work seam")
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func noTeleports(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        var previous = animation.pose(at: 0)
        var worst = 0.0
        for i in 1...Self.sampleCount {
            let t = Double(i) / Double(Self.sampleCount)
            let current = animation.pose(at: t)
            worst = max(worst, Self.poseDistance(previous, current))
            previous = current
        }
        // 3 degrees (0.052 rad) per 1/2000th of the cycle is far above
        // any real authored velocity but far below a seam glitch.
        #expect(worst < 0.052, "\(name): worst per-step delta \(worst)")
    }

    /// Per-joint anatomical ranges in degrees (pitch, yaw, roll),
    /// LEFT-side canonical — right-side joints are mirrored (yaw/roll
    /// negated) before checking. Ranges are a reasonably fit and
    /// flexible human's (build-81 rule: joints bend only the proper
    /// direction, to a human degree). The ankle's generous
    /// plantarflexion stands in for the missing toe joint: a
    /// toes-tucked floor stance reads as one large ankle angle.
    private static let jointRanges: [MascotJoint: (pitch: ClosedRange<Double>, yaw: ClosedRange<Double>, roll: ClosedRange<Double>)] = [
        .root: (-5...5, -5...5, -5...5),
        .spine: (-10...55, -30...30, -20...20),
        .chest: (-10...50, -30...30, -15...15),
        .neck: (-55...40, -60...60, -25...25),
        .head: (-35...35, -45...45, -20...20),
        // The shoulder girdle (clavicle/scapula as one joint): +roll
        // shrugs the shoulder up (elevation, generous — a hard shrug),
        // -roll drops it; +yaw retracts it back, -yaw protracts
        // forward. Pitch barely moves the shoulder (the offset is
        // along the rotation-invariant axis) and stays near zero.
        .leftClavicle: (-15...15, -30...30, -12...40),
        .leftShoulder: (-185...60, -95...95, -25...175),
        .leftElbow: (-150...2, -25...25, -25...25),
        // Wrist yaw IS forearm pronation/supination: the forearm's
        // long axis is the wrist frame's local Y, so yaw at the wrist
        // is exactly the hand rotating about the forearm — a human
        // manages about 90 degrees each way.
        .leftWrist: (-80...80, -90...90, -45...45),
        .leftHip: (-125...25, -40...40, -10...50),
        .leftKnee: (-2...150, -12...12, -12...12),
        .leftAnkle: (-85...30, -15...15, -20...20),
    ]

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func jointsBendOnlyHumanWays(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let toRadians = Double.pi / 180
        for i in 0...200 {
            let t = Double(i) / 200
            let pose = animation.pose(at: t)
            #expect(pose.effort >= -0.01 && pose.effort <= 1.01, "\(name): effort in range")
            for joint in MascotJoint.allCases {
                // Canonicalize to the left side: mirror twins negate
                // yaw and roll.
                let isRight = joint.mirrored != joint && "\(joint)".hasPrefix("right")
                let canonical: MascotJoint = isRight ? joint.mirrored : joint
                guard let range = Self.jointRanges[canonical] else { continue }
                let raw = pose.angles(joint)
                let angles = isRight
                    ? EulerAngles(pitch: raw.pitch, yaw: -raw.yaw, roll: -raw.roll)
                    : raw
                let pitchOK = range.pitch.contains(angles.pitch / toRadians)
                let yawOK = range.yaw.contains(angles.yaw / toRadians)
                let rollOK = range.roll.contains(angles.roll / toRadians)
                #expect(pitchOK && yawOK && rollOK,
                        "\(name) \(joint) at t=\(t): pitch \(angles.pitch / toRadians), yaw \(angles.yaw / toRadians), roll \(angles.roll / toRadians)")
            }
        }
    }

    /// Capsule-surface floor clearance (build-81 rule: no body part or
    /// equipment through the floor). Contact parts — soles, toes,
    /// palms — may TOUCH; everything else keeps its surface above.
    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func nothingGoesThroughTheFloor(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for i in 0...400 {
            let t = Double(i) / 400
            let result = MascotCollision.floorPenetration(animation: animation, at: t)
            #expect(result.contact <= 0.012, "\(name): contact part below floor at t=\(t): \(result.worstPart) \(result.contact)")
            #expect(result.body <= 0.008, "\(name): body below floor at t=\(t): \(result.worstPart) \(result.body)")
            #expect(result.equipment <= 0.005, "\(name): equipment below floor at t=\(t): \(result.worstPart) \(result.equipment)")
        }
    }

    @Test(arguments: ["Squat", "Deadlift"])
    func handsActuallyGripTheBar(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let limit = 20.0 * .pi / 180
        for i in 0...400 {
            let t = Double(i) / 400
            let misalignment = MascotCollision.worstGripMisalignment(pose: animation.pose(at: t))
            #expect(misalignment <= limit,
                    "\(name): a hand's grip channel is \(misalignment * 180 / .pi) degrees off the bar axis at t=\(t)")
        }
    }

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl"])
    func standingMovesKeepFeetPlanted(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let reference = animation.pose(at: 0).jointPositions(skeleton: Self.skeleton)
        for i in 0...400 {
            let t = Double(i) / 400
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            for ankle in [MascotJoint.leftAnkle, .rightAnkle] {
                // The root solver pins the ankle MEAN per keyframe;
                // per-foot residual between keyframes stays within a
                // heel-adjustment couple of centimeters.
                let drift = positions[ankle]!.distance(to: reference[ankle]!)
                #expect(drift < 0.025, "\(name) \(ankle): drifts \(drift) at t=\(t)")
            }
        }
    }

    @Test(arguments: ["Squat", "Deadlift"])
    func barbellWristsStaySymmetric(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        #expect(animation.props.contains(.barbell))
        for i in 0...400 {
            let t = Double(i) / 400
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            let left = positions[.leftWrist]!
            let right = positions[.rightWrist]!
            #expect(abs(left.x + right.x) < 0.005, "\(name): wrist x symmetry at t=\(t)")
            #expect(abs(left.y - right.y) < 0.005, "\(name): wrist y symmetry at t=\(t)")
            #expect(abs(left.z - right.z) < 0.005, "\(name): wrist z symmetry at t=\(t)")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func faceChannelBehaves(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        var minOpenness = 1.0
        var maxTiredness = 0.0
        var previousOpenness = animation.face(at: 0).eyeOpenness
        var worstStep = 0.0
        // Blink speed is a real-time constant, so continuity is sampled
        // at a fixed time resolution (5 ms), not a fixed count.
        let faceSamples = max(Self.sampleCount, Int(animation.cycleDuration * 200))
        for i in 0...faceSamples {
            let t = Double(i) / Double(faceSamples)
            let face = animation.face(at: t)
            #expect(face.eyeOpenness >= 0 && face.eyeOpenness <= 1, "\(name): openness range")
            minOpenness = min(minOpenness, face.eyeOpenness)
            maxTiredness = max(maxTiredness, face.tiredness)
            worstStep = max(worstStep, abs(face.eyeOpenness - previousOpenness))
            previousOpenness = face.eyeOpenness
        }
        #expect(minOpenness <= 0.3, "\(name): at least one real blink per cycle")
        #expect(maxTiredness >= 0.5, "\(name): the tired beat reads on the face")
        #expect(worstStep < 0.12, "\(name): openness continuity, worst step \(worstStep)")

        #expect(!animation.blinkPhases.isEmpty)
        for center in animation.blinkPhases {
            #expect(center >= 0 && center < 1, "\(name): blink center in range")
            let effortAtBlink = animation.pose(at: center).effort
            #expect(effortAtBlink <= 0.6, "\(name): no blink mid-grind (effort \(effortAtBlink) at \(center))")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func cuesAreValid(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        #expect(!animation.cues.isEmpty)
        for cue in animation.cues {
            #expect(!cue.text.isEmpty)
            #expect(cue.text.count <= 42, "\(name): cue fits a line: '\(cue.text)'")
            #expect(!cue.text.contains("\u{2014}"), "\(name): no em dashes in user copy")
            if let window = cue.window {
                #expect(window.lowerBound >= 0 && window.upperBound <= 1)
                #expect(window.lowerBound < window.upperBound)
            }
        }
        // The pacing law (build-81: highlights cycled too fast): at
        // most two SYNCED cues per move, each window generous enough
        // to read, and at least one static cue for the rest.
        let synced = animation.cues.compactMap(\.window)
        let staticCount = animation.cues.count - synced.count
        #expect((1...2).contains(synced.count), "\(name): \(synced.count) synced cues")
        #expect(staticCount >= 1, "\(name): at least one static cue")
        let allWide = synced.allSatisfy { ($0.upperBound - $0.lowerBound) >= 0.3 }
        #expect(allWide, "\(name): synced windows at least 30 percent of a rep")
        // Every synced cue actually gets its moment: active at its
        // window midpoint.
        let workShare = animation.workDuration / animation.cycleDuration
        let repShare = workShare / Double(animation.repsPerDemoSet)
        for (index, cue) in animation.cues.enumerated() {
            guard let window = cue.window else { continue }
            let mid = (window.lowerBound + window.upperBound) / 2
            let active = animation.activeCueIndices(at: mid * repShare)
            #expect(active.contains(index), "\(name): cue \(index) fires at its midpoint")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func stepPhasesAreUsable(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let phases = animation.stepPhases
        #expect(!phases.isEmpty && phases.count <= 8, "\(name): \(phases.count) step phases")
        let sorted = zip(phases, phases.dropFirst()).allSatisfy { $0.0 < $0.1 }
        #expect(sorted)
        let workShare = animation.workDuration / animation.cycleDuration
        let inRange = phases.allSatisfy { $0 >= 0 && $0 <= workShare }
        #expect(inRange)
    }

    // MARK: - Physics (build-80 device feedback: "all motion respects physics")

    @Test(arguments: ["Push-Up", "Plank"])
    func floorMovesKeepToesOnTheGround(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // Sole TOE corners (indices 0 and 2: left toe, right toe) — the
        // foot mesh's actual contact edge in a toes-tucked floor pose.
        let reference = animation.pose(at: 0).solePoints(skeleton: Self.skeleton)
        for i in 0...400 {
            let t = Double(i) / 400
            let soles = animation.pose(at: t).solePoints(skeleton: Self.skeleton)
            for index in [0, 2] {
                let toe = soles[index]
                #expect(toe.y >= -0.012 && toe.y <= 0.035, "\(name): toe floats at t=\(t): y=\(toe.y)")
                let drift = toe.distance(to: reference[index])
                #expect(drift < 0.03, "\(name): toe slides at t=\(t): drift \(drift)")
            }
        }
    }

    /// THIS bot's mass distribution — segment masses proportional to
    /// its own mesh volumes in liters (the head alone is ~8 L; the
    /// limbs are skinny capsules), each hung at the segment midpoint.
    /// Keyed by the segment's child joint; `.root` is the pelvis.
    private static let segmentMass: [MascotJoint: Double] = [
        .root: 5.2, .spine: 6.5, .chest: 6.6, .neck: 0.3, .head: 8.4,
        .leftElbow: 0.65, .rightElbow: 0.65,
        .leftWrist: 0.65, .rightWrist: 0.65,
        .leftKnee: 1.5, .rightKnee: 1.5,
        .leftAnkle: 1.5, .rightAnkle: 1.5,
    ]

    /// The bar's center: the palm midpoint (the renderer solves the
    /// bar from the palms; the wrist JOINTS can sit centimeters off the
    /// bar line in a rotated grip like the back-squat rack).
    private static func barCenter(_ pose: MascotPose) -> Vec3 {
        let frames = pose.jointFrames(skeleton: skeleton)
        let left = frames[.leftWrist]!
        let right = frames[.rightWrist]!
        let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
        let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
        return 0.5 * (leftPalm + rightPalm)
    }

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl"])
    func standingMovesStayBalancedOverTheFeet(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let barMass = animation.props.contains(.barbell) ? 2.0 : 0.0
        for i in 0...400 {
            let t = Double(i) / 400
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            let ankleZ = (positions[.leftAnkle]!.z + positions[.rightAnkle]!.z) / 2
            var moment = 0.0
            var mass = 0.0
            for (joint, m) in Self.segmentMass {
                guard let p = positions[joint] else { continue }
                let anchor: Vec3
                if joint != .root, let parent = joint.parent, let pp = positions[parent] {
                    anchor = 0.5 * (p + pp)
                } else {
                    anchor = p
                }
                moment += m * anchor.z
                mass += m
            }
            if barMass > 0 {
                moment += barMass * Self.barCenter(animation.pose(at: t)).z
                mass += barMass
            }
            let comZ = moment / mass
            // The support polygon runs from the big cartoon foot's heel
            // (~5.5 cm behind the ankle) to its toes (~14 cm ahead).
            // Mid-transition the moving body may ride the heel edge by
            // a few millimeters (dynamic balance — deceleration loads
            // the polygon's edge); the held positions are checked
            // strictly below.
            #expect(comZ >= ankleZ - 0.065 && comZ <= ankleZ + 0.14,
                    "\(name): center of mass off the feet at t=\(t): com z \(comZ), ankles \(ankleZ)")
        }
        // At the held positions (rep start and the bottom), the center
        // of mass sits strictly inside the support polygon — a demo
        // that paused there must not tip (the build-80 squat read as
        // defying gravity).
        let repShare = animation.repDuration / animation.cycleDuration
        for phase in [0.0, animation.restingPhase] {
            let positions = animation.pose(at: phase * repShare).jointPositions(skeleton: Self.skeleton)
            let ankleZ = (positions[.leftAnkle]!.z + positions[.rightAnkle]!.z) / 2
            var moment = 0.0
            var mass = 0.0
            for (joint, m) in Self.segmentMass {
                guard let p = positions[joint] else { continue }
                let anchor: Vec3
                if joint != .root, let parent = joint.parent, let pp = positions[parent] {
                    anchor = 0.5 * (p + pp)
                } else {
                    anchor = p
                }
                moment += m * anchor.z
                mass += m
            }
            if barMass > 0 {
                moment += barMass * Self.barCenter(animation.pose(at: phase * repShare)).z
                mass += barMass
            }
            let comZ = moment / mass
            #expect(comZ >= ankleZ - 0.055 && comZ <= ankleZ + 0.14,
                    "\(name): held position tips at phase \(phase): com z \(comZ)")
        }
    }

    @Test(arguments: ["Squat", "Deadlift"])
    func barbellTracksMidfootAndClearsTheBody(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for i in 0...400 {
            let t = Double(i) / 400
            let pose = animation.pose(at: t)
            let positions = pose.jointPositions(skeleton: Self.skeleton)
            let bar = Self.barCenter(pose)
            let ankleZ = (positions[.leftAnkle]!.z + positions[.rightAnkle]!.z) / 2
            // Textbook bar path: over the midfoot. Real bar paths
            // wander a couple of centimeters mid-transition (the
            // classic S-curve), so the moving bound is a touch looser
            // than the loaded-position bound checked below.
            #expect(bar.z >= ankleZ - 0.10 && bar.z <= ankleZ + 0.13,
                    "\(name): bar off midfoot at t=\(t): bar z \(bar.z), ankles \(ankleZ)")
            // And never inside the body (build-80 deadlift lockout
            // absorbed the bar into the belly): keep a torso-half-depth
            // distance from the hip and lower-spine joints in the
            // sagittal plane.
            for torso in [MascotJoint.root, .spine] {
                let joint = positions[torso]!
                let dy = bar.y - joint.y
                let dz = bar.z - joint.z
                let distance = (dy * dy + dz * dz).squareRoot()
                #expect(distance >= 0.09, "\(name): bar inside the body at t=\(t) near \(torso): \(distance)")
            }
        }
        // At the loaded positions (start of the rep and the bottom),
        // the bar is strictly over the midfoot.
        let repShare = animation.repDuration / animation.cycleDuration
        for phase in [0.0, animation.restingPhase] {
            let pose = animation.pose(at: phase * repShare)
            let positions = pose.jointPositions(skeleton: Self.skeleton)
            let bar = Self.barCenter(pose)
            let ankleZ = (positions[.leftAnkle]!.z + positions[.rightAnkle]!.z) / 2
            #expect(bar.z >= ankleZ - 0.08 && bar.z <= ankleZ + 0.13,
                    "\(name): bar off midfoot at loaded phase \(phase): bar z \(bar.z)")
        }
    }

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl"])
    func equipmentNeverPassesThroughTheBody(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        #expect(!animation.props.isEmpty)
        for i in 0...400 {
            let t = Double(i) / 400
            let worst = MascotCollision.maxEquipmentPenetration(animation: animation, at: t)
            // Up to 8 mm of grazing contact is deliberate (a deadlift
            // bar RESTS against the thighs); deeper means the equipment
            // is inside the body (Dave's build-81 follow-up).
            #expect(worst.depth <= 0.008,
                    "\(name): \(worst.pair) penetrates \(worst.depth) at t=\(t)")
        }
    }

    @Test func pushUpHitsTextbookDepthWithANeutralNeck() throws {
        let pushUp = try #require(MascotMoves.animation(forExerciseNamed: "Push-Up"))
        let workShare = pushUp.workDuration / pushUp.cycleDuration
        var chestTop = -Double.infinity
        var chestBottom = Double.infinity
        for i in 0...200 {
            let t = Double(i) / 200 * workShare * 0.999
            let chestY = pushUp.pose(at: t).jointPositions(skeleton: Self.skeleton)[.chest]!.y
            chestTop = max(chestTop, chestY)
            chestBottom = min(chestBottom, chestY)
        }
        #expect(chestTop - chestBottom >= 0.10, "full range of motion: travel \(chestTop - chestBottom)")
        // 0.19 at the chest JOINT = the chest cowl's surface about a
        // centimeter off the floor, with the flat hands honestly ON it
        // (round 3 raised the wrists so the hand mesh stopped sinking
        // 2 cm into the ground).
        #expect(chestBottom <= 0.19, "chest reaches toward the floor: bottom \(chestBottom)")
        let neutralNeck = 21.0 * .pi / 180
        for keyframe in pushUp.repKeyframes {
            let pitch = abs(keyframe.pose.angles(.neck).pitch)
            #expect(pitch <= neutralNeck, "neck stays neutral: \(pitch)")
        }
    }

    // MARK: - Per-move semantics (the authored shapes mean what they say)

    @Test func squatDescendsAndRacksTheBar() throws {
        let squat = try #require(MascotMoves.animation(forExerciseNamed: "Squat"))
        let repShare = (squat.repDuration / squat.cycleDuration)
        let bottom = squat.pose(at: 0.42 * repShare)
        #expect(bottom.rootTranslation.y < -0.12, "squat bottom drops the hips")
        // BACK rack (v4, on the clavicle-upgraded rig): the bar rides
        // ON the traps — behind and just below the neck joint, hands
        // wider than the shoulders. Checked at the bottom AND standing
        // so the rack holds through the whole rep.
        for phase in [0.0, 0.42] {
            let positions = squat.pose(at: phase * repShare).jointPositions(skeleton: Self.skeleton)
            let neck = positions[.neck]!
            for wrist in [MascotJoint.leftWrist, .rightWrist] {
                let p = positions[wrist]!
                #expect(abs(p.x) > 0.2, "hands outside the shoulders")
                #expect(p.z < neck.z - 0.03, "back squat: bar behind the neck at phase \(phase)")
                let dy = p.y - neck.y
                let dz = p.z - neck.z
                let fromNeck = (dy * dy + dz * dz).squareRoot()
                #expect(fromNeck < 0.17, "bar racked at the traps: \(fromNeck) from the neck at phase \(phase)")
            }
        }
    }

    @Test func deadliftReachesTheShins() throws {
        let deadlift = try #require(MascotMoves.animation(forExerciseNamed: "Deadlift"))
        let repShare = (deadlift.repDuration / deadlift.cycleDuration)
        let bottom = deadlift.pose(at: 0.4 * repShare)
        let positions = bottom.jointPositions(skeleton: Self.skeleton)
        let kneeY = positions[.leftKnee]!.y
        for wrist in [MascotJoint.leftWrist, .rightWrist] {
            let p = positions[wrist]!
            // The chunky bot's arms are proportionally short: knee
            // height is as low as an honest hinge takes the bar.
            #expect(p.y < kneeY + 0.06, "bar reaches the knees at the bottom: y=\(p.y), knee=\(kneeY)")
            #expect(p.y > 0.05, "bar not through the floor")
        }
    }

    @Test func pushUpKeepsHandsPlantedAndBodyInclined() throws {
        let pushUp = try #require(MascotMoves.animation(forExerciseNamed: "Push-Up"))
        let workShare = pushUp.workDuration / pushUp.cycleDuration
        let reference = pushUp.pose(at: 0).jointPositions(skeleton: Self.skeleton)
        for i in 0...200 {
            let t = Double(i) / 200 * workShare
            let positions = pushUp.pose(at: t).jointPositions(skeleton: Self.skeleton)
            for wrist in [MascotJoint.leftWrist, .rightWrist] {
                let p = positions[wrist]!
                #expect(p.y >= 0 && p.y <= 0.07, "hands on the floor at t=\(t): y=\(p.y)")
                let drift = p.distance(to: reference[wrist]!)
                #expect(drift < 0.03, "hands planted at t=\(t): drift \(drift)")
            }
        }
        // The body inclines: head end higher than the feet.
        #expect(reference[.head]!.y > reference[.leftAnkle]!.y)
    }

    @Test func curlBringsTheDumbbellsUp() throws {
        let curl = try #require(MascotMoves.animation(forExerciseNamed: "Dumbbell Curl"))
        #expect(curl.props == [.dumbbellPair])
        let repShare = curl.repDuration / curl.cycleDuration
        let top = curl.pose(at: 0.38 * repShare).jointPositions(skeleton: Self.skeleton)
        let start = curl.pose(at: 0).jointPositions(skeleton: Self.skeleton)
        for wrist in [MascotJoint.leftWrist, .rightWrist] {
            #expect(top[wrist]!.y > start[wrist]!.y + 0.2, "curl lifts the wrists")
            #expect(top[wrist]!.y > 0.72 && top[wrist]!.z > 0.05, "wrists finish up and forward")
        }
    }

    @Test func plankIsAStaticHoldWithRampingEffort() throws {
        let plank = try #require(MascotMoves.animation(forExerciseNamed: "Plank"))
        guard case .hold = plank.style else {
            Issue.record("plank must be a hold"); return
        }
        let workShare = plank.workDuration / plank.cycleDuration
        let base = plank.pose(at: 0)
        var lastEffort = base.effort
        for i in 0...200 {
            let t = Double(i) / 200 * workShare * 0.999
            let pose = plank.pose(at: t)
            #expect(Self.poseDistance(base, pose) < 0.9, "hold stays near its base pose")
            let sway = abs(pose.angles(.chest).pitch - base.angles(.chest).pitch)
            #expect(sway < 5 * .pi / 180, "micro-sway only at t=\(t)")
            // The curved sampler ripples the effort channel by ~1e-4
            // around the ramp's flats; "never releases" means no REAL
            // dip, not spline-noise-free.
            #expect(pose.effort >= lastEffort - 1e-3, "effort never releases mid-hold")
            lastEffort = pose.effort
            let elbowY = pose.jointPositions(skeleton: Self.skeleton)[.leftElbow]!.y
            #expect(elbowY > 0.02 && elbowY < 0.1, "forearms on the floor: elbow y \(elbowY)")
        }
        #expect(plank.pose(at: workShare * 0.98).effort > 0.8, "the hold gets hard near the end")
    }
}
