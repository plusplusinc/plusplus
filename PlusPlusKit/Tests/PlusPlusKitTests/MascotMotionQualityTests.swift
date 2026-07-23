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
    /// moves, the BODY for bodyweight and bar-hanging ones (a
    /// pull-up's palms never move — the body is the load). For body
    /// moves the reference joint is whichever of chest/root actually
    /// travels, decided once per move: the sit-up's chest arcs while
    /// its pelvis is bolted down; the glute bridge's hips rise while
    /// its chest stays near the floor. One definition, shared by the
    /// effort-peak, eccentric-control, and turnaround-pause laws.
    enum LoadChannel { case palms, chest, root }
    static let loadChannelByName: [String: LoadChannel] = {
        var table: [String: LoadChannel] = [:]
        for animation in MascotMoves.all {
            guard animation.props.isEmpty || animation.dynamics.hangsFromBar else {
                table[animation.exerciseName] = .palms
                continue
            }
            var chestLow = Double.infinity, chestHigh = -Double.infinity
            var rootLow = Double.infinity, rootHigh = -Double.infinity
            for i in 0...40 {
                let positions = animation.pose(at: Double(i) / 40).jointPositions(skeleton: skeleton)
                let chest = positions[.chest]!.y
                let root = positions[.root]!.y
                chestLow = min(chestLow, chest); chestHigh = max(chestHigh, chest)
                rootLow = min(rootLow, root); rootHigh = max(rootHigh, root)
            }
            table[animation.exerciseName] =
                (chestHigh - chestLow) >= (rootHigh - rootLow) ? .chest : .root
        }
        return table
    }()

    static func loadHeight(_ animation: ExerciseAnimation, pose: MascotPose) -> Double {
        switch loadChannelByName[animation.exerciseName] ?? .palms {
        case .chest:
            return pose.jointPositions(skeleton: skeleton)[.chest]!.y
        case .root:
            return pose.jointPositions(skeleton: skeleton)[.root]!.y
        case .palms:
            let frames = pose.jointFrames(skeleton: skeleton)
            let left = frames[.leftWrist]!
            let right = frames[.rightWrist]!
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            return (leftPalm.y + rightPalm.y) / 2
        }
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

    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Reverse Lunge", "Glute Bridge"])
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
    // The Kettlebell Swing is deliberately absent: its drop RIDES
    // gravity into the hike — a fast eccentric is the movement, not a
    // form fault.
    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Reverse Lunge", "Glute Bridge"])
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
    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Push-Up", "Single-Leg Calf Raise", "Bench Press", "Lateral Raise", "Sit-Up", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Reverse Lunge", "Glute Bridge"])
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

    // MARK: - Momentum (the ground and the bar obey Newton)

    /// The physics round's dynamic-balance law (build-117, Dave: the
    /// mass model must make the body "respect major laws of physics,
    /// like gravity, conservation of momentum"): while grounded, the
    /// ground reaction is the ONLY external force besides gravity, so
    /// the zero-moment point — where that reaction must act once the
    /// center of mass's actual acceleration is accounted — has to lie
    /// inside the support polygon. A static CoM check can pass while
    /// the MOTION is impossible (the kettlebell float that holds a
    /// bell out with no counterlean); the ZMP is what catches it.
    /// Same standing scope as the static balance law — the support
    /// model knows feet and palms; supine and bench moves carry their
    /// weight on surfaces it cannot see. Airborne windows belong to
    /// the ballistic law; the polygon-less hover samples on a jump's
    /// way in and out of flight are skipped the same way the static
    /// law skips them.
    @Test(arguments: ["Squat", "Deadlift", "Dumbbell Curl", "Single-Leg Calf Raise", "Lateral Raise", "Overhead Press", "Barbell Row", "Goblet Squat", "Kettlebell Swing", "Jump Squat"])
    func standingMovesBalanceTheirMomentum(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        // A BALLISTIC move is one long launch-prep and landing-recovery:
        // its countermovement dip genuinely accelerates the mass 2+
        // m/s^2 and rides the foot's edge far beyond this model. The
        // ballistic law and the gravity ceiling own jumps end to end;
        // this law owns every move that stays on the ground.
        guard animation.dynamics.airborneWindows.isEmpty else { return }
        for i in 0...300 {
            let t = Double(i) / 300
            let pose = animation.pose(at: t)
            guard let polygon = MascotBalance.supportPolygon(pose: pose) else { continue }
            let zmp = MascotBalance.zeroMomentPoint(animation: animation, at: t, dt: 0.25)
            // dt 0.25 s spans the baked-knot spacing, so the estimate
            // is the balance TREND, not spline-knot noise (adjacent
            // 1/30-s samples read accelerations swinging +/-11 m/s^2
            // on device-validated moves). The pad covers what remains
            // plus a real athlete's brief toe/heel edge loading; the
            // synthetic sway prover keeps the law honest at this
            // smoothing.
            // 0.055: the polygon's heel/toe boundary is the sole
            // CORNER + a 5 mm patch — a real foot extends further —
            // and the authored moves skip the several-centimeter
            // preparatory sway a human uses to start a descent. The
            // sway prover pins the law's teeth at gross violations.
            let pad = 0.075
            let xOK = zmp.x >= polygon.x.lowerBound - pad && zmp.x <= polygon.x.upperBound + pad
            let zOK = zmp.z >= polygon.z.lowerBound - pad && zmp.z <= polygon.z.upperBound + pad
            #expect(xOK && zOK,
                    "\(name): the zero-moment point leaves the feet at t=\(t): zmp (\(zmp.x), \(zmp.z)), polygon x \(polygon.x), z \(polygon.z), com accel \(zmp.acceleration)")
        }
    }

    /// The ground can push, never pull: no grounded frame of any move
    /// may accelerate the system center of mass downward faster than
    /// free fall. (Airborne windows sit exactly AT free fall — the
    /// ballistic law — so this holds everywhere with one bound.) The
    /// margin absorbs spline-knot second-derivative noise.
    @Test(arguments: MascotMoves.all.map(\.exerciseName))
    func nothingOutrunsGravity(name: String) throws {
        let animation = try #require(MascotMoves.animation(forExerciseNamed: name))
        for i in 0...300 {
            let t = Double(i) / 300
            let zmp = MascotBalance.zeroMomentPoint(animation: animation, at: t, dt: 0.25)
            #expect(zmp.acceleration.y >= -9.81 * 1.3,
                    "\(name): the center of mass accelerates downward at \(zmp.acceleration.y) m/s² at t=\(t) — faster than gravity, and nothing can push it")
        }
    }

    /// A hanging body is a pendulum: with the bar the only support,
    /// equilibrium demands the system center of mass hang under the
    /// bar line — a sustained sideways or fore-aft offset would swing.
    /// Every frame of every hanging move keeps the CoM within a small
    /// sway of the bar's vertical plane.
    @Test func hangingMovesHangUnderTheBar() throws {
        // Iterates internally: a parameterized test with an empty
        // argument list is itself a failure, and the catalog holds no
        // hanging move while the pull-up awaits its path re-author.
        for animation in MascotMoves.all where animation.dynamics.hangsFromBar {
        let name = animation.exerciseName
        // Mid-rep the bound is looser than a knife-edge pendulum's: a
        // GRIPPED bar carries real torque and friction, and the peak
        // of a pull genuinely rides centimeters of offset. The still
        // phases (the dead hang, the rest beat) are strict — a static
        // hang far off the bar's plane is the build-117 bug class.
        for i in 0...300 {
            let t = Double(i) / 300
            let com = MascotBalance.centerOfMass(animation: animation, at: t)
            #expect(abs(com.z) <= 0.10,
                    "\(name): the center of mass hangs \(com.z) m in front of/behind the bar at t=\(t)")
            #expect(abs(com.x) <= 0.03,
                    "\(name): the center of mass hangs \(com.x) m sideways off the bar's center at t=\(t)")
        }
        let repShare = animation.repDuration / animation.cycleDuration
        for phase in [0.0, animation.restingPhase] {
            let com = MascotBalance.centerOfMass(animation: animation, at: phase * repShare)
            #expect(abs(com.z) <= 0.05,
                    "\(name): the STILL center of mass hangs \(com.z) m off the bar's plane at held phase \(phase)")
        }
        }
    }

    /// The proof harness for the momentum laws (the synthetic-jump
    /// pattern): a body swaying its mass violently over a fixed stance
    /// must throw its ZMP outside the feet, and a grounded body
    /// authored to drop at 2 g must be caught outrunning gravity — at
    /// the same dt/pad the real laws use. If a smoothing change ever
    /// deafens the checkers, these fail first.
    @Test func syntheticCheatsProveTheMomentumCheckers() {
        func flat(_ rootZ: Double, _ rootY: Double) -> MascotPose {
            MascotPose(rootTranslation: Vec3(0, rootY, rootZ))
        }
        let sway = ExerciseAnimation(
            exerciseName: "Probe Sway",
            style: .reps(repDuration: 1.2),
            repsPerDemoSet: 2,
            repKeyframes: (0...10).map { i in
                let phase = Double(i) / 10
                return MascotKeyframe(
                    t: phase,
                    pose: flat(0.12 * cos(2 * .pi * phase), 0),
                    easing: .linear
                )
            },
            restBeat: ExerciseAnimation.RestBeat(duration: 1.0, keyframes: [
                MascotKeyframe(t: 0, pose: flat(0.14, 0), easing: .linear),
                MascotKeyframe(t: 1, pose: flat(0.14, 0)),
            ]),
            cues: [], props: [], blinkPhases: [],
            restingPhase: 0, smoothing: .curved
        )
        var worstExcursion = 0.0
        for i in 0...200 {
            let t = Double(i) / 200
            guard let polygon = MascotBalance.supportPolygon(pose: sway.pose(at: t)) else { continue }
            let zmp = MascotBalance.zeroMomentPoint(animation: sway, at: t, dt: 0.25)
            let excursion = max(polygon.z.lowerBound - zmp.z, zmp.z - polygon.z.upperBound, 0)
            worstExcursion = max(worstExcursion, excursion)
        }
        #expect(worstExcursion > 0.075, "the violent sway should throw its ZMP outside the feet, got \(worstExcursion)")

        let dropDepth = 1.7
        var dropKeyframes: [MascotKeyframe] = []
        // A 2 g drop long enough (0.84 s) that the dt-0.25 estimator
        // must see it, sampled densely so the spline tracks it.
        for i in 0...10 {
            let phase = 0.2 + 0.35 * Double(i) / 10
            let dt = (phase - 0.2) * 2.4
            dropKeyframes.append(MascotKeyframe(
                t: phase, pose: flat(0, -min(0.5 * 2 * 9.81 * dt * dt, dropDepth)), easing: .linear
            ))
        }
        let drop = ExerciseAnimation(
            exerciseName: "Probe Drop",
            style: .reps(repDuration: 2.4),
            repsPerDemoSet: 2,
            repKeyframes: [MascotKeyframe(t: 0, pose: flat(0, 0), easing: .easeInOut)]
                + dropKeyframes
                + [MascotKeyframe(t: 0.8, pose: flat(0, -dropDepth), easing: .easeInOut),
                   MascotKeyframe(t: 1, pose: flat(0, 0))],
            restBeat: ExerciseAnimation.RestBeat(duration: 1.0, keyframes: [
                MascotKeyframe(t: 0, pose: flat(0, 0), easing: .linear),
                MascotKeyframe(t: 1, pose: flat(0, 0)),
            ]),
            cues: [], props: [], blinkPhases: [],
            restingPhase: 0, smoothing: .curved
        )
        var minAY = 0.0
        for i in 0...200 {
            let t = Double(i) / 200
            let zmp = MascotBalance.zeroMomentPoint(animation: drop, at: t, dt: 0.25)
            minAY = min(minAY, zmp.acceleration.y)
        }
        #expect(minAY < -9.81 * 1.3, "the 2 g drop should be caught outrunning gravity, got \(minAY)")
    }
}
