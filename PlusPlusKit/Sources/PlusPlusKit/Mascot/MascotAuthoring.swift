import Foundation

/// The authoring vocabulary for exercise animations: pose fragments,
/// symmetry, root solvers, and the shared tired beat. A move file should
/// read as intent (hinge this deep, arms racked, plant the feet) rather
/// than as raw numbers — this is the layer that has to scale from 5
/// authored moves to the whole catalog.
public enum MascotPoseBuilder {

    // MARK: - Pose fragments

    public static func merge(_ fragments: [MascotJoint: EulerAngles]...) -> [MascotJoint: EulerAngles] {
        var result: [MascotJoint: EulerAngles] = [:]
        for fragment in fragments {
            result.merge(fragment) { _, new in new }
        }
        return result
    }

    public static func torso(
        spine: EulerAngles = .zero,
        chest: EulerAngles = .zero,
        neck: EulerAngles = .zero,
        head: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [.spine: spine, .chest: chest, .neck: neck, .head: head]
    }

    /// The same arm on both sides, mirror-symmetric: the right side gets
    /// yaw and roll negated so "splay out" splays out on both.
    /// `clavicle` is the shoulder girdle (left side conventions: +roll
    /// shrugs the shoulder up, +yaw retracts it back, -yaw protracts it
    /// forward).
    public static func symmetricArms(
        clavicle: EulerAngles = .zero,
        shoulder: EulerAngles = .zero,
        elbow: EulerAngles = .zero,
        wrist: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [
            .leftClavicle: clavicle,
            .leftShoulder: shoulder, .leftElbow: elbow, .leftWrist: wrist,
            .rightClavicle: mirroredAngles(clavicle),
            .rightShoulder: mirroredAngles(shoulder),
            .rightElbow: mirroredAngles(elbow),
            .rightWrist: mirroredAngles(wrist),
        ]
    }

    public static func symmetricLegs(
        hip: EulerAngles = .zero,
        knee: EulerAngles = .zero,
        ankle: EulerAngles = .zero,
        toe: EulerAngles = .zero
    ) -> [MascotJoint: EulerAngles] {
        [
            .leftHip: hip, .leftKnee: knee, .leftAnkle: ankle, .leftToe: toe,
            .rightHip: mirroredAngles(hip),
            .rightKnee: mirroredAngles(knee),
            .rightAnkle: mirroredAngles(ankle),
            .rightToe: mirroredAngles(toe),
        ]
    }

    // MARK: - Mirroring

    /// Reflection across the sagittal plane: pitch survives, yaw and
    /// roll flip.
    static func mirroredAngles(_ angles: EulerAngles) -> EulerAngles {
        EulerAngles(pitch: angles.pitch, yaw: -angles.yaw, roll: -angles.roll)
    }

    /// The whole pose flipped left-to-right — alternating-side moves
    /// author one side and mirror the other rep.
    public static func mirrored(_ pose: MascotPose) -> MascotPose {
        var flipped: [MascotJoint: EulerAngles] = [:]
        for (joint, angles) in pose.joints {
            flipped[joint.mirrored] = mirroredAngles(angles)
        }
        return MascotPose(
            rootTranslation: Vec3(-pose.rootTranslation.x, pose.rootTranslation.y, pose.rootTranslation.z),
            rootRotation: mirroredAngles(pose.rootRotation),
            joints: flipped,
            effort: pose.effort
        )
    }

    // MARK: - Root solvers

    /// Solves the root translation so the ankles return to their rest
    /// spot (y and z; x stays authored). Author the leg and torso angles,
    /// then let this plant the feet — it is also physically honest: the
    /// hips travel back and down in a squat exactly so the feet DON'T.
    public static func plantingFeet(_ pose: MascotPose, skeleton: MascotSkeleton = .standard) -> MascotPose {
        let rest = skeleton.restPose.jointPositions(skeleton: skeleton)
        let current = pose.jointPositions(skeleton: skeleton)
        guard let restL = rest[.leftAnkle], let restR = rest[.rightAnkle],
              let nowL = current[.leftAnkle], let nowR = current[.rightAnkle] else { return pose }
        let restMean = 0.5 * (restL + restR)
        let nowMean = 0.5 * (nowL + nowR)
        var adjusted = pose
        adjusted.rootTranslation.y += restMean.y - nowMean.y
        adjusted.rootTranslation.z += restMean.z - nowMean.z
        return adjusted
    }

    /// Solves the root translation so the given joints land (in the
    /// least-squares mean) on explicit world targets — how floor work
    /// pins hands and toes to the ground.
    public static func anchored(
        _ pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        anchors: [(MascotJoint, Vec3)]
    ) -> MascotPose {
        guard !anchors.isEmpty else { return pose }
        let current = pose.jointPositions(skeleton: skeleton)
        var delta = Vec3.zero
        for (joint, target) in anchors {
            guard let now = current[joint] else { continue }
            delta = delta + (target - now)
        }
        delta = (1.0 / Double(anchors.count)) * delta
        var adjusted = pose
        adjusted.rootTranslation = adjusted.rootTranslation + delta
        return adjusted
    }

    /// Orients both PLANTED flat hands onto the floor: the palm plane
    /// faces straight down and the fingers extend forward (+z, the
    /// direction floor moves face). Solved as a damped Gauss-Newton
    /// over the WHOLE left arm (shoulder 3, elbow pitch/yaw, wrist 3),
    /// because a flat planted hand is not a wrist-only property: the
    /// fingers-forward twist is ~180 degrees about the forearm and
    /// anatomy splits it across humeral rotation at the shoulder plus
    /// pronation — the `grippingTheBar` split again — and the last
    /// degrees of palm-down come from the hand PLANTING slightly ahead
    /// of the shoulder line (`elbowBehind`, the elbow stacked a touch
    /// behind the wrist): the forearm's continuation then points
    /// down-and-forward, and the hand only has to bend back 90 minus
    /// that lean to lie flat — a perfectly vertical forearm would
    /// demand the full 90 of wrist extension the joint doesn't have,
    /// and a forward-tipped one even more (the first cut leaned the
    /// wrong way and pinned every sample on the pitch stop).
    /// Residuals: the WRIST stays where the move's chain solvers
    /// planted it (weight 30); the elbow stacks over the wrist fore-
    /// aft (laterally only a soft preference — a deep rep flares the
    /// elbows out, and that flare keeps the palm reachable); palm
    /// normal down; fingers forward-inward (deliberately softer — a
    /// real loaded hand yields fingers-inward before it yields palm
    /// contact); a soft pull toward the seed picks one point of the
    /// null space, smoothly. `wristSeed` picks the basin; shoulder and
    /// elbow seed from the pose's own smoothly-solved angles, so the
    /// per-sample map stays continuous. At the DEEP bottom the whole
    /// twist chain tops out and the palm keeps a residual tilt — the
    /// move's lowest-point anchoring turns that into the hand rocking
    /// forward onto its planted fingers, heel proud, which is what a
    /// loaded hand actually does. Symmetric: solves the left arm,
    /// mirrors the right.
    public static func plantingPalms(
        _ pose: MascotPose,
        wristSeed: EulerAngles = .deg(pitch: 70),
        shoulderSpinSeed: (yaw: Double, roll: Double)? = nil,
        elbowBehind: Double = 0.04,
        skeleton: MascotSkeleton = .standard
    ) -> MascotPose {
        let normalTarget = Vec3(0, -1, 0)
        // Fingers point forward-INWARD (~40 degrees), like a real
        // loaded push-up hand: dead-forward fingers plus a flat palm
        // need ~180 degrees of twist about the forearm, and the whole
        // anatomical chain (pronation 88 + the elbow's radioulnar 23 +
        // reachable humeral spin) tops out ~40 short — the census put
        // the feasibility floor at a 14-19 degree palm TILT with
        // fingertips hovering off the floor, and a flat palm with
        // turned-in fingers beats tilted fingers in the air.
        let inward = 40.0 * .pi / 180
        let fingerTarget = Vec3(-Foundation.sin(inward), 0, Foundation.cos(inward))

        let startFrames = pose.jointFrames(skeleton: skeleton)
        guard let wristHome = startFrames[.leftWrist]?.position else { return pose }

        func applied(_ q: [Double]) -> MascotPose {
            var next = pose
            var joints = next.joints
            joints[.leftShoulder] = EulerAngles(pitch: q[0], yaw: q[1], roll: q[2])
            joints[.rightShoulder] = EulerAngles(pitch: q[0], yaw: -q[1], roll: -q[2])
            joints[.leftElbow] = EulerAngles(pitch: q[3], yaw: q[4])
            joints[.rightElbow] = EulerAngles(pitch: q[3], yaw: -q[4])
            joints[.leftWrist] = EulerAngles(pitch: q[5], yaw: q[6], roll: q[7])
            joints[.rightWrist] = EulerAngles(pitch: q[5], yaw: -q[6], roll: -q[7])
            next.joints = joints
            return next
        }

        func residual(_ q: [Double], seed: [Double]) -> [Double]? {
            let frames = applied(q).jointFrames(skeleton: skeleton)
            guard let lw = frames[.leftWrist], let le = frames[.leftElbow] else { return nil }
            let normal = lw.rotation.rotate(Vec3(0, 0, 1))
            let fingers = lw.rotation.rotate(Vec3(0, -1, 0))
            // 100, not the grip servo's 30: at the deep bottom the
            // palm target is genuinely infeasible (residual ~1.0), and
            // at 30 the solver happily sold 26 mm of planted-wrist
            // position to shave orientation — hands visibly skating.
            // The planted spot is non-negotiable; orientation takes
            // the whole infeasibility instead.
            let wPos = 100.0
            var r = [
                wPos * (lw.position.x - wristHome.x),
                wPos * (lw.position.y - wristHome.y),
                wPos * (lw.position.z - wristHome.z),
                // The stack, fore-aft: elbow a touch behind the
                // planted wrist; height stays free (the flexion the
                // depth needs). Laterally only a soft preference — a
                // deep push-up FLARES the elbows outward (the humerus
                // abducts), and that flare is precisely what keeps the
                // palm reachable-flat at the bottom: with a sideways
                // upper arm, palm-down is mostly plain wrist extension
                // instead of a maxed-out pronation chain.
                0.5 * (le.position.x - lw.position.x),
                6.0 * (le.position.z - (lw.position.z - elbowBehind)),
                normal.x - normalTarget.x,
                normal.y - normalTarget.y,
                normal.z - normalTarget.z,
                0.45 * (fingers.x - fingerTarget.x),
                0.45 * (fingers.y - fingerTarget.y),
                0.45 * (fingers.z - fingerTarget.z),
            ]
            for i in 0..<q.count {
                r.append(0.3 * (q[i] - seed[i]))
            }
            return r
        }

        let toRadians = Double.pi / 180
        // The same left-canonical bounds as `grippingTheBar`.
        let bounds: [ClosedRange<Double>] = [
            (-183 * toRadians)...(58 * toRadians),   // shoulder pitch
            (-93 * toRadians)...(93 * toRadians),    // shoulder yaw
            (-23 * toRadians)...(173 * toRadians),   // shoulder roll
            (-148 * toRadians)...(0),                // elbow pitch
            (-23 * toRadians)...(23 * toRadians),    // elbow yaw
            (-78 * toRadians)...(90 * toRadians),    // wrist pitch (loaded extension)
            (-88 * toRadians)...(88 * toRadians),    // wrist yaw (pronation)
            (-43 * toRadians)...(43 * toRadians),    // wrist roll
        ]
        let shoulder = pose.joints[.leftShoulder] ?? .zero
        let elbow = pose.joints[.leftElbow] ?? .zero
        // The shoulder's pitch seeds from the pose (it is the move's
        // own smoothly-solved channel); its yaw/roll may seed from an
        // AUTHORED humeral spin — for a hanging arm, spinning about
        // the bone is nearly free in position but half a turn away in
        // joint space, and the soft seed anchor won't cross that on
        // its own (the flat palm's fingers-forward twist lives there).
        var q = [
            shoulder.pitch,
            shoulderSpinSeed?.yaw ?? shoulder.yaw,
            shoulderSpinSeed?.roll ?? shoulder.roll,
            elbow.pitch, elbow.yaw,
            wristSeed.pitch, wristSeed.yaw, wristSeed.roll,
        ]
        let seedQ = q
        let n = 8
        // Levenberg-Marquardt with BACKTRACKING, not plain damped
        // Gauss-Newton: near the deep bottom the palm target is
        // infeasible and several joints ride their stops — a plain
        // clamped step corner-locks there (the descent direction
        // points out of bounds on coupled coordinates, the clamp
        // zeroes it, and iteration freezes 20+ mm from the planted
        // wrist). Shrinking the step until the residual actually
        // improves, and raising the damping when nothing does, walks
        // along the active bounds instead of freezing on them.
        var lambda = 0.01
        for _ in 0..<60 {
            guard let r0 = residual(q, seed: seedQ) else { return pose }
            let errorSq = r0.reduce(0) { $0 + $1 * $1 }
            if errorSq < 1e-7 { break }
            let h = 0.0008
            var J = [[Double]](repeating: [Double](repeating: 0, count: n), count: r0.count)
            for j in 0..<n {
                var qh = q
                qh[j] += h
                guard let rh = residual(qh, seed: seedQ) else { return pose }
                for i in 0..<r0.count {
                    J[i][j] = (rh[i] - r0[i]) / h
                }
            }
            var A = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
            var b = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in 0..<n {
                    var sum = 0.0
                    for k in 0..<r0.count { sum += J[k][i] * J[k][j] }
                    A[i][j] = sum
                }
                A[i][i] += lambda
                var sum = 0.0
                for k in 0..<r0.count { sum += J[k][i] * r0[k] }
                b[i] = -sum
            }
            guard let d = Self.solveLinear(A, b) else { break }
            var stepped = false
            var scale = 1.0
            for _ in 0..<6 {
                var candidate = q
                for j in 0..<n {
                    candidate[j] = min(max(q[j] + scale * d[j], bounds[j].lowerBound), bounds[j].upperBound)
                }
                if let rc = residual(candidate, seed: seedQ),
                   rc.reduce(0, { $0 + $1 * $1 }) < errorSq {
                    q = candidate
                    stepped = true
                    lambda = max(lambda / 2, 1e-4)
                    break
                }
                scale /= 2
            }
            if !stepped {
                lambda *= 8
                if lambda > 1e4 { break }
            }
        }
        return applied(q)
    }

    // MARK: - Spans

    /// Generates the keyframes for a transition between two poses,
    /// re-solving every intermediate sample. Interpolating two planted
    /// poses does NOT keep the feet planted in between (forward
    /// kinematics is nonlinear in the joint angles — the first squat
    /// authored without this drifted its ankles 8 cm mid-descent), so
    /// transitions are baked as short planted paths instead. The easing
    /// is baked into the sampling; emitted keyframes are linear.
    /// `effortKeys` maps span fraction to effort, piecewise linear.
    public static func span(
        from: MascotPose,
        to: MascotPose,
        t0: Double,
        t1: Double,
        steps: Int = 8,
        easing: MascotEasing = .easeInOut,
        effortKeys: [(Double, Double)]? = nil,
        solve: (MascotPose) -> MascotPose = { $0 }
    ) -> [MascotKeyframe] {
        (0...steps).map { i in
            let f = Double(i) / Double(steps)
            var pose = solve(from.lerp(to: to, t: easing.apply(f)))
            if let keys = effortKeys {
                pose.effort = effortValue(at: f, keys: keys)
            }
            return MascotKeyframe(t: t0 + (t1 - t0) * f, pose: pose, easing: .linear)
        }
    }

    static func effortValue(at f: Double, keys: [(Double, Double)]) -> Double {
        guard let first = keys.first else { return 0 }
        if f <= first.0 { return first.1 }
        for (a, b) in zip(keys, keys.dropFirst()) {
            if f <= b.0 {
                let span = b.0 - a.0
                guard span > 0 else { return b.1 }
                return a.1 + (b.1 - a.1) * (f - a.0) / span
            }
        }
        return keys[keys.count - 1].1
    }

    // MARK: - Path coordination (the lifter's "feel", as a solver)

    /// Per-sample path corrections for baked spans. A joint-space lerp
    /// between two LEGAL poses is not itself legal — mid-descent the
    /// hips travel back faster than the torso leans, dragging a held
    /// bar through the knees and sagging the center of mass behind the
    /// heels. A real lifter coordinates continuously; this solver is
    /// that coordination: plant the feet, then in small steps ease the
    /// SHOULDERS forward while held equipment penetrates the body
    /// deeper than a graze, and lean the SPINE forward while the bar or
    /// the center of mass rides behind its line. Identity for poses
    /// already inside every bound — so endpoints pass through
    /// unchanged and pause seams stay exact.
    public static func coordinating(
        _ pose: MascotPose,
        props: [MascotProp] = [],
        comOverFeetAtLeast: Double? = -0.058,
        barOverMidfootAtLeast: Double? = nil,
        equipmentGrazeAtMost: Double? = nil,
        skeleton: MascotSkeleton = .standard
    ) -> MascotPose {
        var candidate = plantingFeet(pose, skeleton: skeleton)
        // 96 steps of 0.0025 rad, not 24 of 0.01: the correction total
        // is the same, but the QUANTUM matters — with coarse steps,
        // neighboring baked samples land different integer numbers of
        // nudges apart, and the ~0.6-degree stair-step reads as shake
        // on device (Dave's deadlift note).
        for _ in 0..<96 {
            let frames = candidate.jointFrames(skeleton: skeleton)
            let ankleZ = 0.5 * ((frames[.leftAnkle]?.position.z ?? 0) + (frames[.rightAnkle]?.position.z ?? 0))

            var equipmentTooDeep = false
            if let graze = equipmentGrazeAtMost {
                equipmentTooDeep = MascotCollision.maxEquipmentPenetration(
                    pose: candidate, props: props, skeleton: skeleton
                ).depth > graze
            }
            var massBehind = false
            if let comFloor = comOverFeetAtLeast {
                massBehind = MascotBalance.centerOfMass(pose: candidate, props: props, skeleton: skeleton).z - ankleZ < comFloor
            }
            var barBehind = false
            if let barFloor = barOverMidfootAtLeast,
               let left = frames[.leftWrist], let right = frames[.rightWrist] {
                let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
                let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
                barBehind = 0.5 * (leftPalm.z + rightPalm.z) - ankleZ < barFloor
            }
            if !equipmentTooDeep && !massBehind && !barBehind { break }

            var joints = candidate.joints
            if equipmentTooDeep {
                for joint in [MascotJoint.leftShoulder, .rightShoulder] {
                    let a = joints[joint] ?? .zero
                    joints[joint] = EulerAngles(pitch: a.pitch - 0.0025, yaw: a.yaw, roll: a.roll)
                }
            } else {
                let spine = joints[.spine] ?? .zero
                joints[.spine] = EulerAngles(pitch: spine.pitch + 0.0025, yaw: spine.yaw, roll: spine.roll)
            }
            candidate.joints = joints
            candidate = plantingFeet(candidate, skeleton: skeleton)
        }
        return candidate
    }

    /// The WHOLE-HAND barbell servo (device feedback on the bench
    /// press: the hands slid 99 mm along the bar — into a plate — and
    /// the wrap read underhand). A hand holding a barbell keeps ONE
    /// STATION on it and wraps it OVERHAND; neither survives a
    /// joint-space lerp, and neither is a wrist-only property:
    /// flipping the wrap side is ~180 degrees about the forearm, which
    /// anatomy splits between shoulder internal rotation and forearm
    /// pronation (with the elbow's radioulnar share carrying the last
    /// few degrees). So the servo solves the whole LEFT arm — shoulder
    /// (3), elbow pitch + yaw, wrist (3) — by damped Gauss-Newton
    /// against:
    ///   1. palm center at (±station, current y, current z) — the
    ///      sample's press height is preserved, the slide corrected;
    ///   2. the grip axis mapped to MINUS x (left thumb INWARD; thumb
    ///      outward is a supinated/underhand wrap);
    ///   3. the metacarpals continuing the forearm line (the "wrists
    ///      stacked" cue — the forearm presses the palm into the bar).
    /// Seeded from the sample's own lerped angles and regularized to
    /// stay near them: the minimizer is locally unique, so the map is
    /// continuous (the wrist-snap lesson — per-sample greedy search is
    /// not). Endpoints must be authored in the OVERHAND basin, or the
    /// seed hands the solver the wrong local minimum. The right side is
    /// the exact sagittal mirror.
    public static func grippingTheBar(
        _ pose: MascotPose,
        station: Double,
        palmTarget: Vec3? = nil,
        elbowUnderBar: Bool = false,
        armSeed: (shoulder: EulerAngles, elbow: EulerAngles, wrist: EulerAngles)? = nil,
        skeleton: MascotSkeleton = .standard
    ) -> MascotPose {
        let toRadians = Double.pi / 180
        // Left-canonical joint bounds, a couple of degrees inside the
        // anatomical table. Elbow YAW is a solve variable on purpose:
        // real forearm rotation is distributed radioulnar, and the
        // table models part of it at the elbow — the last ~25 degrees
        // of a full pronation live there when shoulder and wrist have
        // given all their range (the deadlift bottom and bench touch
        // both need it).
        let bounds: [(ClosedRange<Double>)] = [
            (-183 * toRadians)...(58 * toRadians),   // shoulder pitch
            (-93 * toRadians)...(93 * toRadians),    // shoulder yaw
            (-23 * toRadians)...(173 * toRadians),   // shoulder roll
            (-148 * toRadians)...(0),                // elbow pitch
            (-23 * toRadians)...(23 * toRadians),    // elbow yaw
            (-78 * toRadians)...(78 * toRadians),    // wrist pitch
            (-88 * toRadians)...(88 * toRadians),    // wrist yaw
            (-43 * toRadians)...(43 * toRadians),    // wrist roll
        ]

        func applied(_ q: [Double]) -> MascotPose {
            var next = pose
            var joints = next.joints
            joints[.leftShoulder] = EulerAngles(pitch: q[0], yaw: q[1], roll: q[2])
            joints[.rightShoulder] = EulerAngles(pitch: q[0], yaw: -q[1], roll: -q[2])
            joints[.leftElbow] = EulerAngles(pitch: q[3], yaw: q[4])
            joints[.rightElbow] = EulerAngles(pitch: q[3], yaw: -q[4])
            joints[.leftWrist] = EulerAngles(pitch: q[5], yaw: q[6], roll: q[7])
            joints[.rightWrist] = EulerAngles(pitch: q[5], yaw: -q[6], roll: -q[7])
            next.joints = joints
            return next
        }

        /// Residual vector: palm position error (weighted hard), grip
        /// axis vs -x, hand direction vs the forearm line — plus a
        /// small pull toward the SEED angles. The last term is what
        /// makes the per-sample map CONTINUOUS: the arm has a redundant
        /// degree of freedom (rotations about the shoulder-palm axis
        /// trade shoulder pitch/yaw/roll at constant everything else),
        /// and without a preference inside that null space the solver
        /// bounced between nearby solutions knot to knot — the deadlift
        /// read as SHAKY on device, shoulder roll flapping ±15 degrees
        /// between adjacent baked samples. Anchoring softly to the
        /// smoothly-varying seed picks one point, smoothly.
        func residual(_ q: [Double], seed: [Double], target: Vec3) -> [Double]? {
            let frames = applied(q).jointFrames(skeleton: skeleton)
            guard let lw = frames[.leftWrist], let le = frames[.leftElbow] else { return nil }
            let palm = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
            let grip = lw.rotation.rotate(Vec3(1, 0, 0))
            let hand = lw.rotation.rotate(Vec3(0, -1, 0))
            let f = lw.position - le.position
            let fLength = f.length
            guard fLength > 1e-9 else { return nil }
            let fUnit = (1 / fLength) * f
            let wPos = 30.0, wAxis = 1.0, wHand = 0.7
            var r = [
                wPos * (palm.x - target.x),
                wPos * (palm.y - target.y),
                wPos * (palm.z - target.z),
                wAxis * (grip.x - (-1)),
                wAxis * grip.y,
                wAxis * grip.z,
                wHand * (hand.x - fUnit.x),
                wHand * (hand.y - fUnit.y),
                wHand * (hand.z - fUnit.z),
            ]
            if elbowUnderBar {
                // The pressing stack: elbow directly under the bar in
                // the sagittal plane (thumb-in solutions otherwise
                // wander into flared, elbows-behind shapes).
                r.append(6.0 * (le.position.z - palm.z))
            }
            // Null-space anchor (see above): soft, so the hard
            // constraints still win by two orders of magnitude.
            let wSeed = 0.3
            for i in 0..<q.count {
                r.append(wSeed * (q[i] - seed[i]))
            }
            return r
        }

        let startFrames = pose.jointFrames(skeleton: skeleton)
        guard let lw0 = startFrames[.leftWrist] else { return pose }
        let palm0 = lw0.position + lw0.rotation.rotate(MascotGrip.palmOffset)
        // Mid-span samples keep their own press height (only the slide
        // is corrected); endpoint AUTHORING passes the designed target.
        let target = palmTarget ?? Vec3(station, palm0.y, palm0.z)

        // The Gauss-Newton start point picks the BASIN. By default the
        // pose's own angles seed it (bench: endpoints authored in the
        // overhand basin, so lerped samples stay there). A move whose
        // authored arms serve ANOTHER servo's conventions (the
        // deadlift's simple hanging arms, which `coordinating` nudges
        // by shoulder pitch) passes a constant overhand-basin seed
        // instead — a fixed start plus a smoothly-moving target is a
        // continuous map, where lerping wildly different Euler shapes
        // is not.
        let shoulder = armSeed?.shoulder ?? pose.joints[.leftShoulder] ?? .zero
        let elbow = armSeed?.elbow ?? pose.joints[.leftElbow] ?? .zero
        let wrist = armSeed?.wrist ?? pose.joints[.leftWrist] ?? .zero
        var q = [
            shoulder.pitch, shoulder.yaw, shoulder.roll,
            elbow.pitch, elbow.yaw,
            wrist.pitch, wrist.yaw, wrist.roll,
        ]
        let seedQ = q

        let n = 8
        for _ in 0..<24 {
            guard let r0 = residual(q, seed: seedQ, target: target) else { return pose }
            let errorSq = r0.reduce(0) { $0 + $1 * $1 }
            if errorSq < 1e-7 { break }
            // Numeric Jacobian: one row per residual (9-10 hard terms
            // plus the 8 seed anchors), 8 DOF columns.
            let h = 0.0008
            var J = [[Double]](repeating: [Double](repeating: 0, count: n), count: r0.count)
            for j in 0..<n {
                var qh = q
                qh[j] += h
                guard let rh = residual(qh, seed: seedQ, target: target) else { return pose }
                for i in 0..<r0.count {
                    J[i][j] = (rh[i] - r0[i]) / h
                }
            }
            // Damped normal equations (JtJ + lambda I) d = -Jt r.
            var A = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
            var b = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in 0..<n {
                    var sum = 0.0
                    for k in 0..<r0.count { sum += J[k][i] * J[k][j] }
                    A[i][j] = sum
                }
                A[i][i] += 0.01
                var sum = 0.0
                for k in 0..<r0.count { sum += J[k][i] * r0[k] }
                b[i] = -sum
            }
            guard let d = Self.solveLinear(A, b) else { break }
            for j in 0..<n {
                q[j] = min(max(q[j] + d[j], bounds[j].lowerBound), bounds[j].upperBound)
            }
        }
        return applied(q)
    }

    /// Tiny dense Gaussian elimination with partial pivoting — the
    /// servo's normal equations. Returns nil on a singular system.
    static func solveLinear(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        var a = matrix
        var b = rhs
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(a[row][col]) > abs(a[pivot][col]) {
                pivot = row
            }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            if pivot != col {
                a.swapAt(pivot, col)
                b.swapAt(pivot, col)
            }
            for row in (col + 1)..<n {
                let factor = a[row][col] / a[col][col]
                for k in col..<n { a[row][k] -= factor * a[col][k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    // MARK: - The standard rep cycle

    /// The shared shape of a loaded rep: descend (the ECCENTRIC —
    /// deliberately slower, that is what "control the negative" means),
    /// pause at the bottom, drive up with the effort spike, settle at
    /// the top. `top`/`bottom` may be raw SEEDS: every keyframe that
    /// shows an endpoint — the span ends, the pause, the final — is
    /// emitted as `solve(endpoint)`, the SAME pure call each time, so
    /// pause stillness and the loop seam are bit-exact by determinism
    /// (an identity-gated solve behaves as before; a always-solving
    /// servo like `grippingTheBar` no longer needs a gate).
    public static func repCycle(
        top: MascotPose,
        bottom: MascotPose,
        descendUntil: Double = 0.46,
        pauseUntil: Double = 0.56,
        driveUntil: Double = 0.9,
        steps: Int = 8,
        topEffort: Double,
        bottomEffort: Double,
        driveEffort: Double,
        settleEffort: Double,
        solve: @escaping (MascotPose) -> MascotPose
    ) -> [MascotKeyframe] {
        var keyframes = span(
            from: top, to: bottom, t0: 0, t1: descendUntil, steps: steps,
            effortKeys: [(0, topEffort), (1, bottomEffort)],
            solve: solve
        )
        var pausePose = solve(bottom)
        pausePose.effort = bottomEffort
        keyframes.append(MascotKeyframe(t: pauseUntil, pose: pausePose, easing: .linear))
        keyframes.append(contentsOf: span(
            from: bottom, to: top, t0: pauseUntil, t1: driveUntil, steps: steps,
            easing: .easeOut,
            effortKeys: [(0, bottomEffort), (0.45, driveEffort), (1, settleEffort)],
            solve: solve
        ).dropFirst())
        var finalPose = solve(top)
        finalPose.effort = topEffort
        keyframes.append(MascotKeyframe(t: 1, pose: finalPose))
        return keyframes
    }

    // MARK: - The shared tired beat

    /// The end-of-set beat, HAPPY-TIRED by decree (Dave, build-80
    /// feedback: the first cut's forward slump "looks so sad" — the
    /// mascot should always look happy, even when tired). From the
    /// set's final pose: a small proud "phew" — the head tips UP, the
    /// chest lifts on a slow breath, the shoulders stay open, the body
    /// settles a touch — then it eases back into the set's starting
    /// pose. Never a head-drop, never a shoulder slump. The half-lidded
    /// eyes come from the face channel's tiredness cap (level lids —
    /// serene, not droopy). Endpoint poses match the rep loop's
    /// endpoints exactly, so both seams are continuous.
    /// `solve` re-settles the beat's INTERIOR poses (the phew and the
    /// exhale) after their deltas are applied — floor moves pass their
    /// re-anchoring chain so planted hands and toes stay planted while
    /// the chest lifts (the endpoints are the caller's already-solved
    /// loop poses and pass through untouched).
    public static func tiredBeat(
        from end: MascotPose,
        to start: MascotPose,
        duration: TimeInterval,
        settle: Double = 1,
        solve: (MascotPose) -> MascotPose = { $0 }
    ) -> ExerciseAnimation.RestBeat {
        func adding(_ base: MascotPose, _ deltas: [(MascotJoint, EulerAngles)], rootLift: Double, effort: Double) -> MascotPose {
            var pose = base
            var joints = pose.joints
            for (joint, delta) in deltas {
                let current = joints[joint] ?? .zero
                joints[joint] = EulerAngles(
                    pitch: current.pitch + delta.pitch,
                    yaw: current.yaw + delta.yaw,
                    roll: current.roll + delta.roll
                )
            }
            pose.joints = joints
            pose.rootTranslation.y += rootLift
            pose.effort = effort
            return pose
        }
        // The phew: chin up, chest proud, arms opening a hair outward.
        let phew = solve(adding(end, [
            (.neck, .deg(pitch: -7 * settle)),
            (.head, .deg(pitch: -3 * settle)),
            (.chest, .deg(pitch: -4 * settle)),
            (.leftShoulder, .deg(roll: 5 * settle)),
            (.rightShoulder, .deg(roll: -5 * settle)),
        ], rootLift: -0.006 * settle, effort: 0.06))
        // The slow exhale: the chest eases back down, still tall.
        let exhale = solve(adding(end, [
            (.neck, .deg(pitch: -4 * settle)),
            (.head, .deg(pitch: -2 * settle)),
            (.chest, .deg(pitch: -1 * settle)),
            (.leftShoulder, .deg(roll: 2 * settle)),
            (.rightShoulder, .deg(roll: -2 * settle)),
        ], rootLift: -0.009 * settle, effort: 0.05))

        return ExerciseAnimation.RestBeat(duration: duration, keyframes: [
            MascotKeyframe(t: 0, pose: end, easing: .easeOut),
            MascotKeyframe(t: 0.32, pose: phew, easing: .easeInOut),
            MascotKeyframe(t: 0.62, pose: exhale, easing: .easeInOut),
            MascotKeyframe(t: 1, pose: start),
        ])
    }

    // MARK: - Toe solve

    /// Solves the (symmetric) ankle pitch so the foot's lowest SOLE
    /// CORNER rests on the floor — the build-80 push-up floated its
    /// feet because the ankle angle was eyeballed, and the first solver
    /// targeted the pointed-toe bone reach, which left the actual toe
    /// corner of the foot mesh 4-5 cm under the floor (the round-3
    /// sole-corner invariant caught it). Pure bisection over the FK
    /// sole height; call AFTER any root solve (rotating an ankle never
    /// moves the ankle joint itself).
    /// `nearPitch` narrows the search to a window around a previous
    /// solution — the ankle equation has two roots, and a sequence of
    /// independent solves can hop branches between neighboring samples
    /// (which kinks the sampling spline); seeding keeps a baked path's
    /// ankle continuous.
    public static func solvingToes(
        _ pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        targetSoleY: Double = 0.006,
        nearPitch: Double? = nil
    ) -> MascotPose {
        func soleY(anklePitch: Double) -> Double {
            var candidate = pose
            var joints = candidate.joints
            let left = joints[.leftAnkle] ?? .zero
            let right = joints[.rightAnkle] ?? .zero
            joints[.leftAnkle] = EulerAngles(pitch: anklePitch, yaw: left.yaw, roll: left.roll)
            joints[.rightAnkle] = EulerAngles(pitch: anklePitch, yaw: right.yaw, roll: right.roll)
            candidate.joints = joints
            return candidate.solePoints(skeleton: skeleton).map(\.y).min() ?? 0
        }
        // The sole-height curve is NOT monotone in ankle pitch (the
        // lowest corner switches between toe and heel as the foot
        // rotates, so most heights are reached from TWO foot attitudes)
        // — a blind bisection hops branches. Scan densely, collect
        // every crossing of the target height, and pick the crossing
        // nearest the SEED: `nearPitch` when given, otherwise the
        // pose's authored ankle pitch — the author's eyeballed angle
        // states which attitude the foot means to hold, and the solver
        // only refines it to exact contact.
        let seed = nearPitch ?? (pose.joints[.leftAnkle] ?? .zero).pitch
        let low = nearPitch.map { $0 - 0.5 } ?? -1.9
        let high = nearPitch.map { min($0 + 0.5, 0.55) } ?? 0.55
        let steps = 260
        func sample(_ i: Int) -> Double { low + (high - low) * Double(i) / Double(steps) }
        var crossings: [Double] = []
        var previous = soleY(anklePitch: sample(0)) - targetSoleY
        for i in 1...steps {
            let candidate = sample(i)
            let value = soleY(anklePitch: candidate) - targetSoleY
            if value == 0 || (value < 0) != (previous < 0) {
                // Refine the crossing by bisection oriented to THIS
                // branch's local slope.
                var a = sample(i - 1)
                var b = candidate
                let rising = value > previous
                for _ in 0..<30 {
                    let mid = (a + b) / 2
                    let midValue = soleY(anklePitch: mid) - targetSoleY
                    if (midValue < 0) == rising { a = mid } else { b = mid }
                }
                crossings.append((a + b) / 2)
            }
            previous = value
        }
        let pitch: Double
        if let nearest = crossings.min(by: { abs($0 - seed) < abs($1 - seed) }) {
            pitch = nearest
        } else {
            // No crossing in the bracket: land on the closest approach.
            pitch = (0...steps).map(sample).min {
                abs(soleY(anklePitch: $0) - targetSoleY) < abs(soleY(anklePitch: $1) - targetSoleY)
            } ?? 0
        }
        var solved = pose
        var joints = solved.joints
        let left = joints[.leftAnkle] ?? .zero
        let right = joints[.rightAnkle] ?? .zero
        joints[.leftAnkle] = EulerAngles(pitch: pitch, yaw: left.yaw, roll: left.roll)
        joints[.rightAnkle] = EulerAngles(pitch: pitch, yaw: right.yaw, roll: right.roll)
        solved.joints = joints
        return solved
    }

    // MARK: - Blinks

    /// One blink per rep at a low-effort moment, plus two slow blinks in
    /// the tired beat. Returns set-relative centers, sorted.
    public static func defaultBlinkPhases(
        reps: Int,
        repDuration: TimeInterval,
        restDuration: TimeInterval,
        repPhase: Double
    ) -> [Double] {
        let cycle = Double(reps) * repDuration + restDuration
        guard cycle > 0 else { return [] }
        var centers = (0..<reps).map { (Double($0) + repPhase) * repDuration / cycle }
        let workShare = Double(reps) * repDuration / cycle
        let restShare = 1 - workShare
        centers.append(workShare + 0.35 * restShare)
        centers.append(workShare + 0.72 * restShare)
        return centers.sorted()
    }
}
