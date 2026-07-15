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

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func jointsStayHumanish(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let maxAngle = 170.0 * .pi / 180
        let kneeRange = (-2.0 * .pi / 180)...(157.0 * .pi / 180)
        for keyframes in [animation.repKeyframes, animation.restBeat.keyframes] {
            for keyframe in keyframes {
                let pose = keyframe.pose
                #expect(pose.effort >= 0 && pose.effort <= 1, "\(name): effort in range")
                for joint in MascotJoint.allCases {
                    let angles = pose.angles(joint)
                    #expect(angles.maxMagnitude <= maxAngle, "\(name) \(joint): angle magnitude")
                }
                // Knees bend one way only.
                for knee in [MascotJoint.leftKnee, .rightKnee] {
                    let pitch = pose.angles(knee).pitch
                    #expect(kneeRange.contains(pitch), "\(name) \(knee): pitch \(pitch)")
                }
            }
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func nothingGoesThroughTheFloor(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        var lowest = Double.infinity
        for i in 0...400 {
            let t = Double(i) / 400
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            for y in positions.values.map(\.y) {
                lowest = min(lowest, y)
            }
        }
        #expect(lowest >= -0.01, "\(name): lowest joint \(lowest)")
    }

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl"])
    func standingMovesKeepFeetPlanted(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let reference = animation.pose(at: 0).jointPositions(skeleton: Self.skeleton)
        for i in 0...400 {
            let t = Double(i) / 400
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            for ankle in [MascotJoint.leftAnkle, .rightAnkle] {
                let drift = positions[ankle]!.distance(to: reference[ankle]!)
                #expect(drift < 0.02, "\(name) \(ankle): drifts \(drift) at t=\(t)")
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
            #expect(!cue.text.contains("\u{2014}"), "\(name): no em dashes in user copy")
            #expect(cue.window.lowerBound >= 0 && cue.window.upperBound <= 1)
            #expect(cue.window.lowerBound < cue.window.upperBound)
        }
        // Every cue actually gets its moment: active at its window midpoint.
        let workShare = animation.workDuration / animation.cycleDuration
        let repShare = workShare / Double(animation.repsPerDemoSet)
        for (index, cue) in animation.cues.enumerated() {
            let mid = (cue.window.lowerBound + cue.window.upperBound) / 2
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

    // MARK: - Per-move semantics (the authored shapes mean what they say)

    @Test func squatDescendsAndRacksTheBar() throws {
        let squat = try #require(MascotMoves.animation(forExerciseNamed: "Squat"))
        let repShare = (squat.repDuration / squat.cycleDuration)
        let bottom = squat.pose(at: 0.42 * repShare)
        #expect(bottom.rootTranslation.y < -0.12, "squat bottom drops the hips")
        let positions = bottom.jointPositions(skeleton: Self.skeleton)
        let chestY = positions[.chest]!.y
        let neckZ = positions[.neck]!.z
        for wrist in [MascotJoint.leftWrist, .rightWrist] {
            let p = positions[wrist]!
            #expect(p.y > chestY, "bar rides high: wrist above the chest joint")
            #expect(abs(p.x) > 0.2, "hands wider than shoulders")
            #expect(p.z < neckZ, "back squat: bar behind the neck line")
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
            #expect(pose.effort >= lastEffort - 1e-6, "effort never releases mid-hold")
            lastEffort = pose.effort
            let elbowY = pose.jointPositions(skeleton: Self.skeleton)[.leftElbow]!.y
            #expect(elbowY > 0.02 && elbowY < 0.1, "forearms on the floor: elbow y \(elbowY)")
        }
        #expect(plank.pose(at: workShare * 0.98).effort > 0.8, "the hold gets hard near the end")
    }
}
