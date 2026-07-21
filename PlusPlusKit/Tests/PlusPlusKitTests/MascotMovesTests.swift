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
        #expect(MascotMoves.all.count == 7)
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
    /// direction, to a human degree).
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
        // Hip roll: abduction generous, adduction ~20 (a single-leg
        // stance shifts the pelvis over the foot through adduction).
        .leftHip: (-125...25, -40...40, -20...50),
        .leftKnee: (-2...150, -12...12, -12...12),
        // Ankle pitch: POSITIVE = plantarflexion (the +z toe direction
        // tips down), to a pointed ~50; negative = dorsiflexion, kept
        // generous because the push-up still authors its tucked foot
        // as one large ankle angle.
        .leftAnkle: (-85...50, -15...15, -20...20),
        // The forefoot hinge: NEGATIVE = the cap extends (dorsiflexes)
        // at the ball — a heel raise counter-rotates ~40-55 — and a
        // small positive curl under.
        .leftToe: (-80...35, -8...8, -8...8),
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

    @Test(arguments: ["Squat", "Deadlift", "Bench Press"])
    func handsActuallyGripTheBar(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // 25 degrees, not less: a fully PRONATED grip runs the whole
        // chain to its anatomical stops (shoulder internal rotation +
        // the elbow's radioulnar share + wrist pronation total just
        // under the 180-degree wrap flip at some configurations), and
        // the few degrees left over read as the natural diagonal bar
        // placement in a real overhand grip.
        let limit = 25.0 * .pi / 180
        for i in 0...400 {
            let t = Double(i) / 400
            let misalignment = MascotCollision.worstGripMisalignment(pose: animation.pose(at: t))
            #expect(misalignment <= limit,
                    "\(name): a hand's grip channel is \(misalignment * 180 / .pi) degrees off the bar axis at t=\(t)")
        }
    }

    /// The grip round's first law (device feedback: the bench hands
    /// slid 99 mm along the bar mid-press): a hand holding a barbell
    /// keeps ONE STATION on it — the palm's position along the bar
    /// axis stays put across the whole cycle, rest beat included.
    @Test(arguments: ["Squat", "Deadlift", "Bench Press"])
    func handsHoldOneStationOnTheBar(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        var xMin = Double.infinity
        var xMax = -Double.infinity
        for i in 0...400 {
            let t = Double(i) / 400
            let frames = animation.pose(at: t).jointFrames(skeleton: Self.skeleton)
            guard let lw = frames[.leftWrist] else { continue }
            let palm = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
            xMin = min(xMin, palm.x)
            xMax = max(xMax, palm.x)
        }
        #expect(xMax - xMin <= 0.008,
                "\(name): the hand slides \((xMax - xMin) * 1000) mm along the bar (\(xMin)...\(xMax))")
    }

    /// The grip round's second law — PHYSICS: a hand can never
    /// intersect a weight plate. The plate's inner face is a disc at
    /// plateOffset - plateHalfWidth along the bar; the whole fist stays
    /// axially inside it. (The capsule sweep cannot police this — hands
    /// are exempt there because gripping the SHAFT is correct contact —
    /// and its plate capsules bulge hemispherically along the axis,
    /// overstating a real plate's flat face.)
    @Test(arguments: ["Squat", "Deadlift", "Bench Press"])
    func handsNeverTouchThePlates(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let plateInner = MascotGrip.plateOffset - MascotGrip.plateHalfWidth
        for i in 0...400 {
            let t = Double(i) / 400
            let frames = animation.pose(at: t).jointFrames(skeleton: Self.skeleton)
            guard let lw = frames[.leftWrist] else { continue }
            let palm = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
            let clearance = plateInner - (abs(palm.x) + MascotGrip.fistRadius)
            #expect(clearance > 0,
                    "\(name): the fist is \(-clearance * 1000) mm into the plate face at t=\(t)")
        }
    }

    /// The grip round's third law: every barbell move here grips
    /// PRONATED (overhand) — the left thumb points INWARD along the
    /// bar (thumb-out is a supinated wrap, the underhand read from the
    /// bench device pass), and the metacarpals broadly continue the
    /// forearm rather than folding off it.
    @Test(arguments: ["Squat", "Deadlift", "Bench Press"])
    func theGripIsOverhand(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for i in 0...400 {
            let t = Double(i) / 400
            let frames = animation.pose(at: t).jointFrames(skeleton: Self.skeleton)
            guard let lw = frames[.leftWrist], let le = frames[.leftElbow] else { continue }
            let thumb = lw.rotation.rotate(Vec3(1, 0, 0))
            #expect(thumb.x <= -0.85,
                    "\(name): the left thumb points \(thumb.x) along +x at t=\(t) (overhand needs it inward)")
            let hand = lw.rotation.rotate(Vec3(0, -1, 0))
            let f = lw.position - le.position
            let fLength = f.length
            guard fLength > 1e-9 else { continue }
            let along = (hand.x * f.x + hand.y * f.y + hand.z * f.z) / fLength
            #expect(along >= 0.4,
                    "\(name): the hand folds \(along) off the forearm line at t=\(t)")
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

    @Test(arguments: ["Squat", "Deadlift", "Bench Press"])
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

    /// THIS bot's mass model — segment masses proportional to its own
    /// mesh volumes (the head alone is ~8 L), each hung at the segment
    /// midpoint. The table lives in Kit (`MascotBalance`) — one source of
    /// truth shared with the authoring path servos, like the grip
    /// geometry.

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

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Single-Leg Calf Raise"])
    func standingMovesStayBalancedOverTheFeet(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // The support polygon is computed from what is ACTUALLY in
        // contact — both x and z, so a single-leg stance or a heel-up
        // calf raise shrinks it honestly. Mid-transition the moving
        // body may ride the polygon's edge by a few millimeters
        // (dynamic balance — deceleration loads the edge); held
        // positions are strict.
        func expectBalanced(at t: Double, pad: Double, label: String) {
            let pose = animation.pose(at: t)
            guard let polygon = MascotBalance.supportPolygon(pose: pose) else {
                Issue.record("\(name): nothing touches the ground at \(label)")
                return
            }
            let com = MascotBalance.centerOfMass(pose: pose, props: animation.props)
            let zOK = com.z >= polygon.z.lowerBound - pad && com.z <= polygon.z.upperBound + pad
            let xOK = com.x >= polygon.x.lowerBound - pad && com.x <= polygon.x.upperBound + pad
            #expect(zOK && xOK,
                    "\(name): center of mass off the support at \(label): com (\(com.x), \(com.z)), polygon x \(polygon.x), z \(polygon.z)")
        }
        for i in 0...400 {
            expectBalanced(at: Double(i) / 400, pad: 0.012, label: "t=\(Double(i) / 400)")
        }
        // At the held positions (rep start and the resting pose), the
        // center of mass sits strictly inside the polygon — a demo
        // that paused there must not tip (the build-80 squat read as
        // defying gravity).
        let repShare = animation.repDuration / animation.cycleDuration
        for phase in [0.0, animation.restingPhase] {
            expectBalanced(at: phase * repShare, pad: 0.002, label: "held phase \(phase)")
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

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Bench Press"])
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

    /// The straight-line law, geometrically (build-88 on-device: the
    /// push-up read hips-sagging with the head craned back): through
    /// every WORKING frame of the floor moves, chest–hip–knee and
    /// hip–knee–ankle stay within a few degrees of collinear, and the
    /// head CONTINUES the body line instead of craning off it. The
    /// tired beat is exempt — the proud chest-lift between sets bends
    /// on purpose.
    @Test(arguments: ["Push-Up", "Plank"])
    func floorMovesHoldAStraightLine(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let workShare = animation.workDuration / animation.cycleDuration
        // Bend at the apex joint, in the sagittal plane only — the hips
        // sit wider than the body's midline by design, and lateral
        // offsets are not sag.
        func degreesFromStraight(_ a: Vec3, _ apex: Vec3, _ b: Vec3) -> Double {
            let u = (z: a.z - apex.z, y: a.y - apex.y)
            let v = (z: b.z - apex.z, y: b.y - apex.y)
            let dot = u.z * v.z + u.y * v.y
            let mag = (u.z * u.z + u.y * u.y).squareRoot()
                * (v.z * v.z + v.y * v.y).squareRoot()
            guard mag > 1e-9 else { return 0 }
            return 180 - acos(max(-1, min(1, dot / mag))) * 180 / .pi
        }
        for i in 0...200 {
            let t = Double(i) / 200 * workShare * 0.999
            let positions = animation.pose(at: t).jointPositions(skeleton: Self.skeleton)
            let chest = positions[.chest]!
            let hip = 0.5 * (positions[.leftHip]! + positions[.rightHip]!)
            let knee = 0.5 * (positions[.leftKnee]! + positions[.rightKnee]!)
            let ankle = 0.5 * (positions[.leftAnkle]! + positions[.rightAnkle]!)
            let hipBend = degreesFromStraight(chest, hip, knee)
            let kneeBend = degreesFromStraight(hip, knee, ankle)
            let headBend = degreesFromStraight(hip, positions[.neck]!, positions[.head]!)
            #expect(hipBend <= 8, "\(name): hips \(hipBend) deg off the line at t=\(t)")
            #expect(kneeBend <= 8, "\(name): knees \(kneeBend) deg off the line at t=\(t)")
            #expect(headBend <= 12, "\(name): head \(headBend) deg off the line at t=\(t)")
        }
    }

    /// The bench law — FIVE POINTS OF CONTACT, textbook and enforced at
    /// every frame of the whole cycle (rest beat included): the head,
    /// the upper back, and the glutes stay ON the pad (back surfaces
    /// within a graze-to-12 mm band of the pad top — no bridging, no
    /// sinking through), and both soles stay planted on the floor.
    /// Every future bench/seat move inherits this by joining the
    /// argument list.
    @Test(arguments: ["Bench Press"])
    func benchMovesKeepFiveContactPoints(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        #expect(animation.props.contains(.flatBench))
        let padTop = MascotSupport.benchTopHeight
        for i in 0...400 {
            let t = Double(i) / 400
            let pose = animation.pose(at: t)
            let frames = pose.jointFrames(skeleton: Self.skeleton)
            // Torso back surfaces: joint axis minus the capsule radius,
            // read FROM the collision model — a hardcoded copy would go
            // silently stale when a silhouette pass retunes the table
            // (the muscle pass changed exactly these numbers).
            for (joint, part) in [
                (MascotJoint.spine, "glutes"),
                (.chest, "mid back"),
                (.neck, "upper back"),
            ] {
                let gap = (frames[joint]!.position.y - MascotCollision.segmentRadius(joint)) - padTop
                #expect(gap >= -0.008 && gap <= 0.012,
                        "\(name): \(part) off the pad by \(gap) at t=\(t)")
            }
            let head = frames[.head]!
            let headBottom = (head.position + head.rotation.rotate(MascotCollision.headCenterOffset)).y
                - MascotCollision.headRadius
            let headGap = headBottom - padTop
            #expect(headGap >= -0.008 && headGap <= 0.015,
                    "\(name): head off the pad by \(headGap) at t=\(t)")
            let soles = pose.solePoints(skeleton: Self.skeleton)
            let soleLow = soles.map(\.y).min() ?? 0
            let soleHigh = soles.map(\.y).max() ?? 0
            #expect(soleLow >= -0.012 && soleHigh <= 0.02,
                    "\(name): feet leave the floor (\(soleLow)...\(soleHigh)) at t=\(t)")
        }
    }

    /// Bench press semantics: full range of motion from a mid-chest
    /// TOUCH (the bar grazes the chest cowl, never floats above it) to
    /// a full-reach LOCKOUT stacked over the shoulder line — with the
    /// textbook vertical forearm (elbow under the bar in the side view)
    /// at the touch.
    @Test func benchPressTouchesTheChestAndLocksOut() throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: "Bench Press"))
        let repShare = animation.repDuration / animation.cycleDuration
        func bar(at t: Double) -> (center: Vec3, elbowZ: Double, elbowPitch: Double) {
            let pose = animation.pose(at: t)
            let frames = pose.jointFrames(skeleton: Self.skeleton)
            let left = frames[.leftWrist]!
            let right = frames[.rightWrist]!
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            return (
                0.5 * (leftPalm + rightPalm),
                frames[.leftElbow]!.position.z,
                pose.angles(.leftElbow).pitch * 180 / .pi
            )
        }
        let frames = animation.pose(at: 0).jointFrames(skeleton: Self.skeleton)
        let shoulder = frames[.leftShoulder]!.position

        // Touch, mid-pause: on the cowl (within 12 mm of its surface),
        // over the chest (feet-ward of the shoulder line, but not by
        // much), forearm vertical in the sagittal plane.
        let touch = bar(at: 0.5 * repShare)
        let cowlSurface = frames[.neck]!.position.y + 0.085 + MascotGrip.barRadius
        #expect(touch.center.y <= cowlSurface + 0.012, "bar floats above the chest: \(touch.center.y) vs \(cowlSurface)")
        #expect(touch.center.z > shoulder.z && touch.center.z < shoulder.z + 0.09,
                "touch point off mid chest: \(touch.center.z) vs shoulder \(shoulder.z)")
        #expect(abs(touch.elbowZ - touch.center.z) <= 0.02,
                "forearm not vertical at the touch: elbow z \(touch.elbowZ) vs bar z \(touch.center.z)")

        // Lockout, top dwell: full reach stacked over the shoulders.
        let lock = bar(at: 0.95 * repShare)
        #expect(lock.center.y - shoulder.y >= 0.33, "lockout short of full reach: \(lock.center.y - shoulder.y)")
        #expect(abs(lock.center.z - shoulder.z) <= 0.03,
                "bar not stacked over the shoulders: \(lock.center.z) vs \(shoulder.z)")
        // -20, not -12: holding full pronation (the overhand grip) at
        // this grip width costs the last few degrees of elbow
        // extension, and a SOFT lockout is the safer textbook anyway
        // (hyperextension is the fault worth teaching against).
        #expect(lock.elbowPitch >= -20, "elbows stay bent at lockout: \(lock.elbowPitch)")
        #expect(lock.center.y - touch.center.y >= 0.24, "full range of motion: travel \(lock.center.y - touch.center.y)")
    }

    // MARK: - Per-move semantics (the authored shapes mean what they say)

    @Test func squatDescendsAndRacksTheBar() throws {
        let squat = try #require(MascotMoves.animation(forExerciseNamed: "Squat"))
        let repShare = (squat.repDuration / squat.cycleDuration)
        let bottom = squat.pose(at: 0.5 * repShare)
        #expect(bottom.rootTranslation.y < -0.12, "squat bottom drops the hips")
        // Full range of motion: BELOW parallel — the hip crease sinks
        // under the knee at the bottom (Dave's depth round; a squat
        // that stops high teaches a shallow squat).
        let bottomPositions = bottom.jointPositions(skeleton: Self.skeleton)
        let hipDrop = bottomPositions[.leftHip]!.y - bottomPositions[.leftKnee]!.y
        #expect(hipDrop < -0.01, "below parallel: hip \(hipDrop) vs knee")
        // BACK rack (v4, on the clavicle-upgraded rig): the bar rides
        // ON the traps — behind and just below the neck joint, hands
        // wider than the shoulders. Checked at the bottom AND standing
        // so the rack holds through the whole rep.
        for phase in [0.0, 0.5] {
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

    @Test func deadliftPullsFromTheFloor() throws {
        let deadlift = try #require(MascotMoves.animation(forExerciseNamed: "Deadlift"))
        let repShare = (deadlift.repDuration / deadlift.cycleDuration)
        let bottom = deadlift.pose(at: 0.5 * repShare)
        // Full range of motion (Dave's depth round): the pull starts
        // FROM THE FLOOR — the bar within a couple of centimeters of
        // where the plates rest (plate radius above the ground), never
        // from knee height (a rack pull is a different exercise) and
        // never through the floor.
        let bar = Self.barCenter(bottom)
        #expect(bar.y <= MascotGrip.plateRadius + 0.02,
                "bar catches at the floor: y=\(bar.y) vs plates at \(MascotGrip.plateRadius)")
        #expect(bar.y >= MascotGrip.plateRadius - 0.005, "plates rest ON the floor, not in it: y=\(bar.y)")
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
        let top = curl.pose(at: 0.47 * repShare).jointPositions(skeleton: Self.skeleton)
        let start = curl.pose(at: 0).jointPositions(skeleton: Self.skeleton)
        for wrist in [MascotJoint.leftWrist, .rightWrist] {
            #expect(top[wrist]!.y > start[wrist]!.y + 0.2, "curl lifts the wrists")
            #expect(top[wrist]!.y > 0.72 && top[wrist]!.z > 0.05, "wrists finish up and forward")
        }
        // Full range of motion (Dave's depth round): near-full elbow
        // extension at the bottom (a soft elbow, not a bent-arm rest)
        // to at least 130 degrees of flexion at the squeeze.
        let toDegrees = 180 / Double.pi
        let startFlexion = abs(curl.pose(at: 0).angles(.leftElbow).pitch) * toDegrees
        let topFlexion = abs(curl.pose(at: 0.47 * repShare).angles(.leftElbow).pitch) * toDegrees
        #expect(startFlexion <= 10, "full extension at the bottom: \(startFlexion) degrees")
        #expect(topFlexion >= 128, "full squeeze at the top: \(topFlexion) degrees")
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
