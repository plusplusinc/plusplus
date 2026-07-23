import Testing
@testable import PlusPlusKit
import Foundation

/// Self-derived motion-quality invariants — rules nobody asked for by
/// name, but that any trustworthy demo must satisfy. Like the physics
/// sweep, these run over the whole catalog so every future move
/// inherits them.
///
/// The set:
/// 1. The body never passes through ITSELF (capsule self-collision).
/// 2. Symmetric moves are exactly bilaterally symmetric (catches
///    one-sided authoring typos the eye misses at demo speed).
/// 3. A barbell stays level (no visible tilt).
/// 4. No joint moves faster than a human could at demo tempo.
/// 5. Effort peaks while the load is RISING — the face strains on the
///    concentric, not at random.
/// 6. Something touches the ground at all times (no airborne frames in
///    non-jumping moves).
/// 7. Synced cues cover actual motion (a highlight synced to a still
///    body is a lie).
/// 8. Demo tempo stays readable (rep and cycle duration bounds).
@Suite struct MascotMotionQualityTests {
    private static let skeleton = MascotSkeleton.standard

    /// The "load" a rep raises and lowers: the palms for weighted
    /// moves, the chest for bodyweight ones (the body IS the load).
    /// One definition, shared by the effort-peak, eccentric-control,
    /// and turnaround-pause laws — three verbatim copies drifted here
    /// before the scale-out round pulled them together.
    static func loadHeight(_ animation: ExerciseAnimation, pose: MascotPose) -> Double {
        if animation.props.isEmpty {
            return pose.jointPositions(skeleton: skeleton)[.chest]!.y
        }
        let frames = pose.jointFrames(skeleton: skeleton)
        let left = frames[.leftWrist]!
        let right = frames[.rightWrist]!
        let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
        let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
        return (leftPalm.y + rightPalm.y) / 2
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func bodyNeverPassesThroughItself(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for i in 0...400 {
            let t = Double(i) / 400
            let worst = MascotCollision.maxSelfPenetration(pose: animation.pose(at: t))
            // The same grazing allowance as equipment: parts may brush
            // (arms against the torso mid-curl), never overlap deeper.
            #expect(worst.depth <= 0.008, "\(name): \(worst.pair) self-penetrates \(worst.depth) at t=\(t)")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func symmetricMovesAreExactlySymmetric(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // Unilateral moves are asymmetric BY DESIGN — the calf raise
        // stands on one leg (the exemption round 2 promised its first
        // asymmetric move).
        guard name != "Single-Leg Calf Raise", name != "Reverse Lunge" else { return }
        for keyframes in [animation.repKeyframes, animation.restBeat.keyframes] {
            for keyframe in keyframes {
                for joint in MascotJoint.allCases where joint.mirrored != joint && "\(joint)".hasPrefix("left") {
                    let left = keyframe.pose.angles(joint)
                    let right = keyframe.pose.angles(joint.mirrored)
                    let symmetric = abs(left.pitch - right.pitch) < 1e-9
                        && abs(left.yaw + right.yaw) < 1e-9
                        && abs(left.roll + right.roll) < 1e-9
                    #expect(symmetric, "\(name) \(joint): asymmetric at keyframe t=\(keyframe.t)")
                }
            }
        }
    }

    @Test(arguments: ["Squat", "Deadlift", "Bench Press", "Overhead Press", "Barbell Row"])
    func theBarStaysLevel(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let maxTilt = sin(3.0 * .pi / 180)
        for i in 0...400 {
            let t = Double(i) / 400
            let frames = animation.pose(at: t).jointFrames(skeleton: Self.skeleton)
            guard let left = frames[.leftWrist], let right = frames[.rightWrist] else { continue }
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            let span = leftPalm - rightPalm
            guard span.length > 1e-6 else { continue }
            let tilt = abs(span.y) / span.length
            #expect(tilt <= maxTilt, "\(name): bar tilts \(tilt) at t=\(t)")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func noJointMovesFasterThanAHuman(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let samples = 2000
        let dt = animation.cycleDuration / Double(samples)
        var previous = animation.pose(at: 0)
        var worst = 0.0
        for i in 1...samples {
            let current = animation.pose(at: Double(i) / Double(samples))
            worst = max(worst, previous.maxBodyDelta(to: current) / dt)
            previous = current
        }
        // 8 rad/s is roughly a brisk arm wave; demo-form tempo should
        // stay well under it. A spline spike or seam glitch will not.
        #expect(worst <= 8, "\(name): peak joint speed \(worst) rad/s")
    }

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Reverse Lunge"])
    func effortPeaksWhileTheLoadRises(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let repShare = animation.repDuration / animation.cycleDuration
        func loadHeight(at t: Double) -> Double {
            Self.loadHeight(animation, pose: animation.pose(at: t))
        }
        var peak = (effort: -Double.infinity, t: 0.0)
        for i in 0...200 {
            let t = Double(i) / 200 * repShare
            let effort = animation.pose(at: t).effort
            if effort > peak.effort {
                peak = (effort, t)
            }
        }
        // The finite-difference window clamps inside the rep: a peak at
        // the very seam must not sample across the wrap into the tired
        // beat.
        let step = repShare / 200
        let lower = max(peak.t - step, 0)
        let upper = min(peak.t + step, repShare)
        let rising = loadHeight(at: upper) - loadHeight(at: lower)
        #expect(rising > 0, "\(name): peak effort at t=\(peak.t) but the load is not rising (\(rising))")
    }

    /// The lowest contact surface's SIGNED height above the floor:
    /// sole corners and palm-pad undersides — the actual mesh surfaces
    /// that can touch ground (the pointed-toe bone reach is a solver
    /// target that dangles below a standing sole, so it stays out).
    /// Shared by the grounded invariant and the airborne (ballistic)
    /// one; signed matters for the airborne check — a body diving
    /// BELOW the floor mid-window must read as touching (negative),
    /// never as clearance, which `abs` would have hidden.
    static func closestGroundContact(_ pose: MascotPose) -> Double {
        var lowest = Double.infinity
        for point in pose.solePoints(skeleton: skeleton) {
            lowest = min(lowest, point.y)
        }
        for palm in MascotCollision.palmSpheres(pose: pose) {
            lowest = min(lowest, palm.from.y - palm.radius)
        }
        return lowest
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func somethingAlwaysTouchesTheGround(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // A hanging move's support is the BAR, not the ground — it
        // owes the hang invariant (hands on the bar, feet clear)
        // instead.
        guard !animation.dynamics.hangsFromBar else { return }
        for i in 0...400 {
            let t = Double(i) / 400
            // A move that declares airborne windows (a jump) is exempt
            // INSIDE them — and owes a gravity parabola there instead
            // (jumpingMovesFollowGravity).
            guard !animation.isAirborne(at: t) else { continue }
            let closest = Self.closestGroundContact(animation.pose(at: t))
            #expect(closest <= 0.02, "\(name): airborne at t=\(t) (closest contact \(closest))")
        }
    }

    /// The hang law (the pull-up bar is the first FIXED grip): a move
    /// that declares `hangsFromBar` keeps both palms ON the bar's
    /// world line at every sample — rest beat included — and nothing
    /// touches the floor (a hanging body that grounds a toe is a
    /// different exercise). Runs over every move and keys on the
    /// declaration, so future hanging moves inherit it for free.
    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func hangingMovesKeepHandsOnTheBar(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        guard animation.dynamics.hangsFromBar else { return }
        #expect(animation.props.contains(.pullUpBar), "\(name): hangs but carries no bar")
        var xMin = Double.infinity
        var xMax = -Double.infinity
        for i in 0...400 {
            let t = Double(i) / 400
            let pose = animation.pose(at: t)
            let frames = pose.jointFrames(skeleton: Self.skeleton)
            for wrist in [MascotJoint.leftWrist, .rightWrist] {
                guard let frame = frames[wrist] else { continue }
                let palm = frame.position + frame.rotation.rotate(MascotGrip.palmOffset)
                let dy = palm.y - MascotSupport.pullUpBarHeight
                let dz = palm.z
                let offBar = (dy * dy + dz * dz).squareRoot()
                #expect(offBar <= 0.008,
                        "\(name): a palm rides \(offBar * 1000) mm off the bar line at t=\(t)")
                #expect(abs(palm.x) + MascotGrip.fistRadius <= MascotSupport.pullUpBarHalfLength,
                        "\(name): a hand hangs past the bar's end at t=\(t)")
                if wrist == .leftWrist {
                    xMin = min(xMin, palm.x)
                    xMax = max(xMax, palm.x)
                }
            }
            let closest = Self.closestGroundContact(pose)
            #expect(closest > 0.02, "\(name): a hanging move touches the floor at t=\(t)")
        }
        // The barbell's one-station law, inherited by the fixed bar: a
        // hand may not slide along it mid-rep.
        #expect(xMax - xMin <= 0.008,
                "\(name): the hand slides \((xMax - xMin) * 1000) mm along the bar")
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func syncedCuesCoverActualMotion(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let repShare = animation.repDuration / animation.cycleDuration
        for cue in animation.cues {
            guard let window = cue.window else { continue }
            var travel = 0.0
            var previous = animation.pose(at: window.lowerBound * repShare)
            for i in 1...40 {
                let phase = window.lowerBound + (window.upperBound - window.lowerBound) * Double(i) / 40
                let current = animation.pose(at: phase * repShare)
                travel += previous.maxBodyDelta(to: current)
                previous = current
            }
            #expect(travel >= 0.05, "\(name): '\(cue.text)' is synced to a still body (travel \(travel))")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func demoTempoStaysReadable(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        #expect(animation.repDuration >= 1.5 && animation.repDuration <= 25, "\(name): rep duration")
        #expect(animation.cycleDuration >= 5 && animation.cycleDuration <= 32, "\(name): cycle duration")
    }

    /// "Control the negative": on rep-style moves the load never FALLS
    /// — its peak downward speed stays comfortably under its peak
    /// upward speed, i.e. the eccentric is the slow half. Textbook
    /// tempo, enforced (holds are exempt: nothing travels).
    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Reverse Lunge"])
    func theEccentricIsControlled(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let workShare = animation.workDuration / animation.cycleDuration
        func loadHeight(at t: Double) -> Double {
            Self.loadHeight(animation, pose: animation.pose(at: t))
        }
        let samples = 400
        let dt = animation.cycleDuration * workShare / Double(samples)
        var peakDown = 0.0
        var peakUp = 0.0
        var previous = loadHeight(at: 0)
        for i in 1...samples {
            let height = loadHeight(at: Double(i) / Double(samples) * workShare)
            let velocity = (height - previous) / dt
            peakDown = max(peakDown, -velocity)
            peakUp = max(peakUp, velocity)
            previous = height
        }
        #expect(peakDown <= 0.9 * peakUp,
                "\(name): the load drops faster than it rises (down \(peakDown) vs up \(peakUp) m/s)")
    }

    /// Every rep-style move owes its turnarounds a NATURAL PAUSE
    /// (build-88 on-device: curls rolled straight from rep to rep with
    /// no beat at the bottom). Concretely: each rep holds at least two
    /// genuinely still windows long enough to read (≥4% of the rep),
    /// and they sit where the load actually turns around — one at the
    /// bottom of its travel, one at the top. An eased turnaround
    /// without a dwell only grazes zero speed for an instant, so the
    /// window-length bar separates a real pause from a slow reversal.
    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Reverse Lunge"])
    func everyRepPausesAtItsTurnarounds(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        let repShare = animation.repDuration / animation.cycleDuration
        let samples = 500
        let dt = animation.repDuration / Double(samples)
        var poses: [MascotPose] = []
        poses.reserveCapacity(samples)
        for i in 0..<samples {
            poses.append(animation.pose(at: Double(i) / Double(samples) * repShare))
        }
        // Stillness, measured circularly — the rep loops, and a bottom
        // dwell that wraps the seam (the curl's) is one pause, not two.
        let still = (0..<samples).map { i in
            poses[i].maxBodyDelta(to: poses[(i + 1) % samples]) / dt < 0.1
        }
        guard let firstMoving = still.firstIndex(of: false) else {
            Issue.record("\(name): the whole rep is still")
            return
        }
        var windows: [[Int]] = []
        var run: [Int] = []
        for offset in 1...samples {
            let i = (firstMoving + offset) % samples
            if still[i] {
                run.append(i)
            } else if !run.isEmpty {
                windows.append(run)
                run = []
            }
        }
        if !run.isEmpty { windows.append(run) }
        let pauses = windows.filter { $0.count >= samples * 4 / 100 }
        #expect(pauses.count >= 2, "\(name): \(pauses.count) readable pauses (needs bottom AND top)")

        // The pauses must SEAT at the turnarounds: the load's lowest
        // and highest points each live inside a pause window.
        func loadHeight(_ pose: MascotPose) -> Double {
            Self.loadHeight(animation, pose: pose)
        }
        let heights = poses.map(loadHeight)
        let lowest = heights.min()!
        let highest = heights.max()!
        let nearBottom = pauses.contains { $0.contains { heights[$0] <= lowest + 0.012 } }
        let nearTop = pauses.contains { $0.contains { heights[$0] >= highest - 0.012 } }
        #expect(nearBottom, "\(name): no pause at the bottom turnaround")
        #expect(nearTop, "\(name): no pause at the top turnaround")
    }

    // MARK: - Ballistics (jumps obey gravity)

    /// The mean vertical acceleration of the ROOT across a rep-relative
    /// window, by central finite differences over the window's interior
    /// (edges skipped: takeoff and landing blend into grounded motion).
    /// The root stands in for the center of mass — an airborne body's
    /// pose changes redistribute mass a little, but the authored jump
    /// keeps its pose near-rigid in flight, so root acceleration IS the
    /// CoM's to well within the tolerance.
    static func meanVerticalAcceleration(
        _ animation: ExerciseAnimation,
        window: ClosedRange<Double>
    ) -> Double {
        let repShare = animation.repDuration / animation.cycleDuration
        let margin = (window.upperBound - window.lowerBound) * 0.18
        let inner = (window.lowerBound + margin)...(window.upperBound - margin)
        let samples = 24
        let dtPhase = (inner.upperBound - inner.lowerBound) / Double(samples)
        let dt = dtPhase * animation.repDuration
        var total = 0.0
        var count = 0
        func rootY(_ phase: Double) -> Double {
            animation.pose(at: phase * repShare).rootTranslation.y
        }
        for i in 1..<samples {
            let phase = inner.lowerBound + dtPhase * Double(i)
            let a = (rootY(phase + dtPhase) - 2 * rootY(phase) + rootY(phase - dtPhase)) / (dt * dt)
            total += a
            count += 1
        }
        return total / Double(count)
    }

    /// Every declared airborne window is real free flight: the body
    /// actually leaves the ground, and the root falls at gravity
    /// (9.81 m/s^2, +/-25% for spline smoothing) — no floaty jumps, no
    /// rocket jumps. Runs over every cataloged move that declares
    /// windows (none of the first five do) and is PROVEN by the
    /// synthetic jump below, so the machinery is live before the first
    /// real jumping move lands.
    static func expectBallistic(_ animation: ExerciseAnimation, name: String) {
        let repShare = animation.repDuration / animation.cycleDuration
        for window in animation.dynamics.airborneWindows {
            let a = Self.meanVerticalAcceleration(animation, window: window)
            #expect(a <= -9.81 * 0.75 && a >= -9.81 * 1.25,
                    "\(name): airborne window \(window) accelerates at \(a) m/s^2, not gravity")
            let mid = (window.lowerBound + window.upperBound) / 2
            let clearance = Self.closestGroundContact(animation.pose(at: mid * repShare))
            #expect(clearance > 0.02, "\(name): declared airborne but still touching at phase \(mid)")
        }
    }

    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func jumpingMovesFollowGravity(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        Self.expectBallistic(animation, name: name)
    }

    /// The proof harness for the ballistic invariant: a synthetic jump
    /// authored ON a gravity parabola passes; the same jump stretched
    /// into a floaty half-gravity arc is caught. This is what keeps the
    /// checker honest until the catalog's first real jump.
    @Test func syntheticJumpProvesTheBallisticChecker() {
        func jump(gravityScale: Double) -> ExerciseAnimation {
            let repSeconds = 1.6
            let crouch = MascotPoseBuilder.plantingFeet(MascotPose(
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: -55), knee: .deg(pitch: 70), ankle: .deg(pitch: -15)
                    ),
                    MascotPoseBuilder.torso(spine: .deg(pitch: 18))
                ),
                effort: 0.5
            ))
            let airborne: ClosedRange<Double> = 0.50...0.75
            let apexPhase = 0.625
            let rise = 9.81 * gravityScale / 2 * pow((airborne.upperBound - airborne.lowerBound) / 2 * repSeconds, 2)
            var keyframes: [MascotKeyframe] = [
                MascotKeyframe(t: 0, pose: MascotPose(effort: 0.2), easing: .easeInOut),
                MascotKeyframe(t: 0.32, pose: crouch, easing: .easeOut),
            ]
            // Flight path sampled densely so the spline TRACKS the
            // parabola instead of approximating it through two knots.
            let flightSamples = 10
            for i in 0...flightSamples {
                let phase = airborne.lowerBound + (airborne.upperBound - airborne.lowerBound) * Double(i) / Double(flightSamples)
                let dt = (phase - apexPhase) * repSeconds
                let y = rise - 9.81 * gravityScale / 2 * dt * dt
                keyframes.append(MascotKeyframe(
                    t: phase,
                    pose: MascotPose(rootTranslation: Vec3(0, y, 0), effort: 0.9),
                    easing: .linear
                ))
            }
            keyframes.append(MascotKeyframe(t: 0.86, pose: crouch, easing: .easeOut))
            keyframes.append(MascotKeyframe(t: 1, pose: MascotPose(effort: 0.2)))
            return ExerciseAnimation(
                exerciseName: "Synthetic Jump",
                style: .reps(repDuration: repSeconds),
                repsPerDemoSet: 2,
                repKeyframes: keyframes,
                restBeat: ExerciseAnimation.RestBeat(duration: 2, keyframes: [
                    MascotKeyframe(t: 0, pose: MascotPose(effort: 0.2)),
                    MascotKeyframe(t: 1, pose: MascotPose(effort: 0.2)),
                ]),
                cues: [MascotCue("Land soft")],
                blinkPhases: [0.9],
                smoothing: .curved,
                dynamics: MascotDynamics(airborneWindows: [airborne])
            )
        }

        let real = jump(gravityScale: 1)
        Self.expectBallistic(real, name: "Synthetic Jump")
        // The exemption works both ways: grounded at the authored
        // standing and crouch keyframes...
        let repShare = real.repDuration / real.cycleDuration
        #expect(Self.closestGroundContact(real.pose(at: 0)) <= 0.02)
        #expect(Self.closestGroundContact(real.pose(at: 0.32 * repShare)) <= 0.02)
        #expect(real.isAirborne(at: 0.6 * repShare))
        #expect(!real.isAirborne(at: 0.9 * repShare))

        // ...and a floaty half-gravity arc is REJECTED by the same
        // measurement the invariant applies.
        let floaty = jump(gravityScale: 0.5)
        for window in floaty.dynamics.airborneWindows {
            let a = Self.meanVerticalAcceleration(floaty, window: window)
            #expect(a > -9.81 * 0.75, "the floaty jump should read as under-gravity, got \(a)")
        }
    }
}
