import Testing
import Foundation
@testable import PlusPlusKit

// Scratch diagnostics for the build-117 articulation round. Deleted
// before ship.
struct ScratchArticulationTests {
    // Swing-twist decomposition about the bone axis (local y): how far
    // the hinge axis tilts off local x, and how much twist rides along,
    // for every hinge joint of every move. Calibrates the new law's
    // bounds against device-validated moves.
    @Test func fleetHingeSwingTwist() {
        let deg = 180.0 / Double.pi
        for animation in MascotMoves.all {
            var worstElbowTilt = 0.0, worstElbowTwist = 0.0
            var worstKneeTilt = 0.0, worstKneeTwist = 0.0
            var worstElbowT = 0.0, tiltPitch = 0.0
            for i in 0...160 {
                let t = Double(i) / 160
                let pose = animation.pose(at: t)
                for joint in [MascotJoint.leftElbow, .rightElbow, .leftKnee, .rightKnee] {
                    let angles = pose.angles(joint)
                    let (tilt, twist, swing) = swingTwist(angles)
                    let isElbow = joint == .leftElbow || joint == .rightElbow
                    // Tilt is meaningless on a straight joint.
                    guard swing * deg > 8 else { continue }
                    if isElbow {
                        if tilt > worstElbowTilt {
                            worstElbowTilt = tilt; worstElbowT = t; tiltPitch = angles.pitch * deg
                        }
                        worstElbowTwist = max(worstElbowTwist, twist)
                    } else {
                        worstKneeTilt = max(worstKneeTilt, tilt)
                        worstKneeTwist = max(worstKneeTwist, twist)
                    }
                }
            }
            print(String(format: "%@: elbow tilt=%.1f (t=%.2f pitch=%.0f) twist=%.1f | knee tilt=%.1f twist=%.1f",
                         animation.exerciseName,
                         worstElbowTilt * deg, worstElbowT, tiltPitch, worstElbowTwist * deg,
                         worstKneeTilt * deg, worstKneeTwist * deg))
        }
        #expect(Bool(true))
    }

    // Wrist extremes per move — pitch/yaw/roll canonicalized left — to
    // see who leans on the generous deviation range.
    @Test func fleetWristExtremes() {
        let deg = 180.0 / Double.pi
        for animation in MascotMoves.all {
            var maxAbsRoll = 0.0, minPitch = 0.0, maxPitch = 0.0, maxAbsYaw = 0.0
            for i in 0...160 {
                let t = Double(i) / 160
                let pose = animation.pose(at: t)
                for (joint, mirror) in [(MascotJoint.leftWrist, 1.0), (.rightWrist, -1.0)] {
                    let a = pose.angles(joint)
                    maxAbsRoll = max(maxAbsRoll, abs(a.roll * mirror))
                    maxAbsYaw = max(maxAbsYaw, abs(a.yaw))
                    minPitch = min(minPitch, a.pitch)
                    maxPitch = max(maxPitch, a.pitch)
                }
            }
            print(String(format: "%@: wrist roll<=%.1f yaw<=%.1f pitch %.1f..%.1f",
                         animation.exerciseName,
                         maxAbsRoll * deg, maxAbsYaw * deg, minPitch * deg, maxPitch * deg))
        }
        #expect(Bool(true))
    }

    // Scratch-descent playground for the pull-up re-author: optimize
    // the hang and top arm configs against every law metric at once.
    @Test func solvePullUpConfigs() {
        let station = 0.19
        let deg = 180.0 / Double.pi
        let toRad = Double.pi / 180

        // q = [shPitch, shYaw, shRoll, elPitch, elYaw, wrPitch, wrYaw, wrRoll]
        // (elbow yaw bounded to the radioulnar share, like the solvers.)
        func pose(_ q: [Double], legsKnee: Double, torso: (spine: Double, chest: Double, neck: Double, head: Double), rootPitch: Double) -> MascotPose {
            MascotPoseBuilder.hangingFromTheBar(MascotPose(
                rootRotation: .deg(pitch: rootPitch),
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricArms(
                        shoulder: EulerAngles(pitch: q[0], yaw: q[1], roll: q[2]),
                        elbow: EulerAngles(pitch: q[3], yaw: q[4]),
                        wrist: EulerAngles(pitch: q[5], yaw: q[6], roll: q[7])
                    ),
                    MascotPoseBuilder.symmetricLegs(
                        knee: .deg(pitch: legsKnee), ankle: .deg(pitch: 25)
                    ),
                    MascotPoseBuilder.torso(
                        spine: .deg(pitch: torso.spine), chest: .deg(pitch: torso.chest),
                        neck: .deg(pitch: torso.neck), head: .deg(pitch: torso.head)
                    )
                ),
                effort: 0.5
            ))
        }

        func metrics(_ p: MascotPose) -> (palmX: Double, axisOff: Double, phiUp: Double, thumbX: Double, normalZ: Double, elbow: Vec3, wrist: Vec3, helmetClear: Double, handAlong: Double, shoulder: Vec3) {
            let frames = p.jointFrames(skeleton: .standard)
            let lw = frames[.leftWrist]!
            let le = frames[.leftElbow]!
            let ls = frames[.leftShoulder]!
            let palm = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
            let gripAxis = lw.rotation.rotate(Vec3(1, 0, 0))
            let axisOff = acos(max(-1, min(1, abs(gripAxis.x)))) * deg
            let palmSide = lw.rotation.rotate(Vec3(0, 1, 0))
            let fingerSide = lw.rotation.rotate(Vec3(0, 0, 1))
            let phiUp = atan2(fingerSide.y, palmSide.y) * deg
            let thumbX = gripAxis.x
            let normalZ = lw.rotation.rotate(Vec3(0, 0, 1)).z
            let head = frames[.head]!
            let helmetCenter = head.position + head.rotation.rotate(Vec3(0, 0.11, 0))
            let dy = helmetCenter.y - MascotSupport.pullUpBarHeight
            let dz = helmetCenter.z - 0
            let helmetClear = (dy * dy + dz * dz).squareRoot() - 0.115 - MascotSupport.pullUpBarRadius
            let hand = lw.rotation.rotate(Vec3(0, -1, 0))
            let f = lw.position - le.position
            let fl = f.length
            let along = fl > 1e-9 ? (hand.x * f.x + hand.y * f.y + hand.z * f.z) / fl : 1
            return (palm.x, axisOff, phiUp, thumbX, normalZ, le.position, lw.position, helmetClear, along, ls.position)
        }

        func descend(seed: [Double], legsKnee: Double, torso: (spine: Double, chest: Double, neck: Double, head: Double), rootPitch: Double, shape: @escaping ((palmX: Double, axisOff: Double, phiUp: Double, thumbX: Double, normalZ: Double, elbow: Vec3, wrist: Vec3, helmetClear: Double, handAlong: Double, shoulder: Vec3)) -> Double, label: String, quiet: Bool = false, boundsOverride: [ClosedRange<Double>]? = nil) -> [Double] {
            var q = seed
            func cost(_ candidate: [Double]) -> Double {
                let m = metrics(pose(candidate, legsKnee: legsKnee, torso: torso, rootPitch: rootPitch))
                let frames = pose(candidate, legsKnee: legsKnee, torso: torso, rootPitch: rootPitch).jointFrames(skeleton: .standard)
                let axis = frames[.leftWrist]!.rotation.rotate(Vec3(1, 0, 0))
                var c = 0.0
                c += 4000 * pow(m.palmX - station, 2) * 1000
                // The whole chirality/alignment story in one target:
                // the left hand's thumb axis IS -x̂ (inward along the
                // bar, exactly overhand).
                c += 60 * (pow(axis.x + 1, 2) + axis.y * axis.y + axis.z * axis.z)
                c += 1.5 * pow((m.phiUp - 75) / 40, 2)
                c += 10 * pow(max(0, 0.3 - m.normalZ), 2)
                c += 20 * pow(max(0, 0.008 - m.helmetClear) * 20, 2)
                c += shape(m)
                for (i, s) in seed.enumerated() { c += 0.02 * pow((candidate[i] - s) / (10 * toRad), 2) }
                return c
            }
            let bounds: [ClosedRange<Double>] = boundsOverride ?? [
                (-183 * toRad)...(58 * toRad),
                (-92 * toRad)...(92 * toRad),
                (-23 * toRad)...(173 * toRad),
                (-148 * toRad)...(0),
                (-23 * toRad)...(23 * toRad),
                (-78 * toRad)...(90 * toRad),
                (-88 * toRad)...(88 * toRad),
                (-38 * toRad)...(38 * toRad),
            ]
            var step = 8 * toRad
            var currentCost = cost(q)
            while step > 0.05 * toRad {
                var improved = false
                for i in 0..<q.count {
                    for direction in [1.0, -1.0] {
                        var candidate = q
                        candidate[i] = min(max(q[i] + direction * step, bounds[i].lowerBound), bounds[i].upperBound)
                        let c = cost(candidate)
                        if c < currentCost {
                            q = candidate
                            currentCost = c
                            improved = true
                        }
                    }
                }
                if !improved { step *= 0.5 }
            }
            if !quiet {
                let m = metrics(pose(q, legsKnee: legsKnee, torso: torso, rootPitch: rootPitch))
                print(String(format: "%@: sh=(%.1f,%.1f,%.1f) el=(%.1f,%.1f) wr=(%.1f,%.1f,%.1f)",
                             label, q[0] * deg, q[1] * deg, q[2] * deg, q[3] * deg, q[4] * deg, q[5] * deg, q[6] * deg, q[7] * deg))
                print(String(format: "   palmX=%.4f axisOff=%.1f phiUp=%.0f thumbX=%.2f normalZ=%.2f helmetClear=%.3f along=%.2f elbow=(%.3f,%.3f,%.3f)",
                             m.palmX, m.axisOff, m.phiUp, m.thumbX, m.normalZ, m.helmetClear, m.handAlong, m.elbow.x, m.elbow.y, m.elbow.z))
            }
            return q
        }

        // Seed grids: the descent can't cross a humeral-spin or
        // pronation basin, so scan the basin choices and keep the best
        // (the OHP config-family pattern).
        let hangShape: ((palmX: Double, axisOff: Double, phiUp: Double, thumbX: Double, normalZ: Double, elbow: Vec3, wrist: Vec3, helmetClear: Double, handAlong: Double, shoulder: Vec3)) -> Double = { m in
            8 * pow(max(0, 0.15 - m.elbow.x) * 10, 2)
        }
        var bestHang: (cost: Double, q: [Double])? = nil
        for shYaw in [Double]() {
            for wrYaw in [-85.0, -40, 40, 85] {
                for wrPitch in [45.0, 70.0, 88.0] {
                    let q = descend(
                        seed: [-176 * toRad, shYaw * toRad, 8 * toRad, -6 * toRad, 0, wrPitch * toRad, wrYaw * toRad, 0],
                        legsKnee: 12,
                        torso: (0, 0, 0, 0), rootPitch: 0,
                        shape: hangShape,
                        label: "hang(\(Int(shYaw)),\(Int(wrYaw)),\(Int(wrPitch)))",
                        quiet: true
                    )
                    let m = metrics(pose(q, legsKnee: 12, torso: (0, 0, 0, 0), rootPitch: 0))
                    guard m.thumbX <= -0.80, m.axisOff <= 12, m.phiUp >= 25, m.phiUp <= 130, m.normalZ >= 0.1 else { continue }
                    let c = m.axisOff + abs(m.phiUp - 75) * 0.1
                    if bestHang == nil || c < bestHang!.cost { bestHang = (c, q) }
                }
            }
        }
        if let best = bestHang {
            let m = metrics(pose(best.q, legsKnee: 12, torso: (0, 0, 0, 0), rootPitch: 0))
            print(String(format: "HANG WINNER: sh=(%.1f,%.1f,%.1f) el=(%.1f,%.1f) wr=(%.1f,%.1f,%.1f)",
                         best.q[0] * deg, best.q[1] * deg, best.q[2] * deg, best.q[3] * deg,
                         best.q[4] * deg, best.q[5] * deg, best.q[6] * deg, best.q[7] * deg))
            print(String(format: "   palmX=%.4f axisOff=%.1f phiUp=%.0f thumbX=%.2f normalZ=%.2f helmetClear=%.3f elbow=(%.3f,%.3f,%.3f)",
                         m.palmX, m.axisOff, m.phiUp, m.thumbX, m.normalZ, m.helmetClear, m.elbow.x, m.elbow.y, m.elbow.z))
        } else {
            print("HANG: NO legal basin found")
        }

        let topShape: ((palmX: Double, axisOff: Double, phiUp: Double, thumbX: Double, normalZ: Double, elbow: Vec3, wrist: Vec3, helmetClear: Double, handAlong: Double, shoulder: Vec3)) -> Double = { m in
            var c = 0.0
            // Elbows out (never inside the hands' line) and genuinely
            // below the bar — plus a real pull DEPTH: the shoulder
            // rides up near the bar, not a shallow half-rep.
            c += 16 * pow(max(0, (m.wrist.x - 0.02) - m.elbow.x) * 10, 2)
            c += 8 * pow(max(0, m.elbow.y - 1.26) * 10, 2)
            c += 14 * pow(max(0, 1.20 - m.shoulder.y) * 10, 2)
            return c
        }
        var bestTop: (cost: Double, q: [Double])? = nil
        var nearMisses: [(Double, String)] = []
        // The top stays in the HANG's basin (one-basin config family):
        // shoulder yaw ~-88 humeral spin, wrist yaw positive, wrist
        // folded over the bar; pitch rises out of overhead while the
        // elbow flexes. The HOLLOW LEAN (rootPitch -12, neck swept
        // back) moves the oversized helmet BEHIND the bar's plane —
        // chest-to-bar is geometrically impossible for this head with
        // an upright body.
        let topTorso = (spine: -8.0, chest: -6.0, neck: -28.0, head: -10.0)
        let topRootPitch = -18.0
        let topBounds: [ClosedRange<Double>] = [
            (-100 * toRad)...(-15 * toRad),   // shoulder pitch: frontal pull, no chicken wing
            (-92 * toRad)...(92 * toRad),
            (0)...(135 * toRad),              // roll: out, never adducted across
            (-148 * toRad)...(0),
            (-23 * toRad)...(23 * toRad),
            (35 * toRad)...(90 * toRad),      // wrist stays folded over the bar
            (-88 * toRad)...(-60 * toRad),    // pronation stays in the hang's basin
            (-38 * toRad)...(38 * toRad),
        ]
        for shPitch in [-70.0, -40] {
            for shRoll in [60.0, 100] {
                for elPitch in [-125.0, -140] {
                  for elYaw in [-8.0, 8.0] {
                    for wrPitch in [55.0, 80.0] {
                        let q = descend(
                            seed: [shPitch * toRad, 82 * toRad, shRoll * toRad, elPitch * toRad, elYaw * toRad, wrPitch * toRad, -85 * toRad, 0],
                            legsKnee: 25,
                            torso: topTorso, rootPitch: topRootPitch,
                            shape: topShape,
                            label: "top",
                            quiet: true,
                            boundsOverride: topBounds
                        )
                        let m = metrics(pose(q, legsKnee: 25, torso: topTorso, rootPitch: topRootPitch))
                        let legal = m.thumbX <= -0.85 && m.axisOff <= 15 && m.phiUp >= 30 && m.phiUp <= 130 && m.helmetClear >= 0.010 && m.normalZ >= 0 && m.elbow.y <= 1.30 && m.elbow.x >= 0.13 && m.shoulder.y >= 1.13
                        let c = m.axisOff + abs(m.phiUp - 75) * 0.1
                        let desc = String(format: "seed(%.0f,%.0f,%.0f,%.0f) -> sh=(%.1f,%.1f,%.1f) el=(%.1f,%.1f) wr=(%.1f,%.1f,%.1f) axisOff=%.1f phiUp=%.0f thumbX=%.2f helmet=%.3f shoulderY=%.2f elbow=(%.2f,%.2f,%.2f)",
                                          shPitch, shRoll, elPitch, wrPitch,
                                          q[0] * deg, q[1] * deg, q[2] * deg, q[3] * deg, q[4] * deg, q[5] * deg, q[6] * deg, q[7] * deg,
                                          m.axisOff, m.phiUp, m.thumbX, m.helmetClear, m.shoulder.y, m.elbow.x, m.elbow.y, m.elbow.z)
                        if legal {
                            if bestTop == nil || c < bestTop!.cost { bestTop = (c, q) }
                        } else {
                            nearMisses.append((c, desc))
                        }
                    }
                  }
                }
            }
        }
        if bestTop == nil {
            for (_, desc) in nearMisses.sorted(by: { $0.0 < $1.0 }).prefix(4) {
                print("near miss: \(desc)")
            }
        }
        if let best = bestTop {
            let m = metrics(pose(best.q, legsKnee: 25, torso: topTorso, rootPitch: topRootPitch))
            print(String(format: "TOP WINNER: sh=(%.1f,%.1f,%.1f) el=(%.1f,%.1f) wr=(%.1f,%.1f,%.1f)",
                         best.q[0] * deg, best.q[1] * deg, best.q[2] * deg, best.q[3] * deg,
                         best.q[4] * deg, best.q[5] * deg, best.q[6] * deg, best.q[7] * deg))
            print(String(format: "   palmX=%.4f axisOff=%.1f phiUp=%.0f thumbX=%.2f normalZ=%.2f helmetClear=%.3f elbow=(%.3f,%.3f,%.3f) wrist=(%.3f,%.3f,%.3f)",
                         m.palmX, m.axisOff, m.phiUp, m.thumbX, m.normalZ, m.helmetClear,
                         m.elbow.x, m.elbow.y, m.elbow.z, m.wrist.x, m.wrist.y, m.wrist.z))
        } else {
            print("TOP: NO legal basin found")
        }
        #expect(Bool(true))
    }

    // Swing re-author probe: the analytic wrist for the new STAND
    // config (bell hanging at the groin) + counterlean tuning for the
    // float (CoM/polygon readouts at several lean values).
    @Test func solveSwingConfigs() {
        let toRad = Double.pi / 180
        let deg = 180.0 / Double.pi

        func swingPose(
            spine: Double, chest: Double, neck: Double,
            hip: Double, knee: Double, lean: Double,
            shoulder: EulerAngles, wrist: EulerAngles
        ) -> MascotPose {
            MascotPose(
                joints: MascotPoseBuilder.merge(
                    MascotPoseBuilder.symmetricLegs(
                        hip: .deg(pitch: hip, roll: 6), knee: .deg(pitch: knee),
                        ankle: .deg(pitch: -(hip + knee) - lean)
                    ),
                    MascotPoseBuilder.torso(
                        spine: .deg(pitch: spine), chest: .deg(pitch: chest),
                        neck: .deg(pitch: neck)
                    ),
                    MascotPoseBuilder.symmetricArms(
                        shoulder: shoulder, elbow: .deg(pitch: -8), wrist: wrist
                    )
                ),
                effort: 0.3
            )
        }

        // STAND: descend the 3 wrist channels against grip alignment.
        func standPose(_ w: [Double]) -> MascotPose {
            MascotPoseBuilder.coordinating(swingPose(
                spine: 4, chest: 2, neck: -2, hip: -4, knee: 8, lean: 0,
                shoulder: .deg(pitch: -22, yaw: -24),
                wrist: EulerAngles(pitch: w[0], yaw: w[1], roll: w[2])
            ), props: [.kettlebell])
        }
        var bestStand: (Double, [Double])? = nil
        for seedPitch in [-30.0, 0, 30] {
            for seedRoll in [0.0, 25] {
                var w = [seedPitch * toRad, 0, seedRoll * toRad]
                var step = 8 * toRad
                func cost(_ candidate: [Double]) -> Double {
                    MascotCollision.worstGripMisalignment(pose: standPose(candidate))
                }
                var current = cost(w)
                while step > 0.05 * toRad {
                    var improved = false
                    for i in 0..<3 {
                        for direction in [1.0, -1.0] {
                            var candidate = w
                            candidate[i] = w[i] + direction * step
                            let c = cost(candidate)
                            if c < current { w = candidate; current = c; improved = true }
                        }
                    }
                    if !improved { step *= 0.5 }
                }
                if bestStand == nil || current < bestStand!.0 { bestStand = (current, w) }
            }
        }
        if let (miss, w) = bestStand {
            print(String(format: "SWING STAND wrist=(%.1f,%.1f,%.1f) misalign=%.1f deg",
                         w[0] * deg, w[1] * deg, w[2] * deg, miss * deg))
            let pose = standPose(w)
            let com = MascotBalance.centerOfMass(pose: pose, props: [.kettlebell])
            if let polygon = MascotBalance.supportPolygon(pose: pose) {
                print(String(format: "   stand com z=%.3f polygon z %.3f..%.3f", com.z, polygon.z.lowerBound, polygon.z.upperBound))
            }
            // Bell-vs-thigh clearance sanity via the capsule sweep.
            let worst = MascotCollision.maxEquipmentPenetration(pose: pose, props: [.kettlebell])
            print(String(format: "   stand equipment penetration=%.1f mm (%@)", worst.depth * 1000, worst.pair))
        }

        // FLOAT counterlean: the existing top config at several leans.
        for lean in [0.0, 2.0, 3.5, 5.0] {
            let float = MascotPoseBuilder.coordinating(swingPose(
                spine: 0, chest: 0, neck: -4, hip: 0, knee: 4, lean: lean,
                shoulder: .deg(pitch: -85, yaw: -24),
                wrist: .deg(pitch: 3.0, roll: 24.0)
            ), props: [.kettlebell])
            let com = MascotBalance.centerOfMass(pose: float, props: [.kettlebell])
            guard let polygon = MascotBalance.supportPolygon(pose: float) else { continue }
            print(String(format: "FLOAT lean=%.1f com z=%.3f polygon z %.3f..%.3f mid=%.3f",
                         lean, com.z, polygon.z.lowerBound, polygon.z.upperBound,
                         (polygon.z.lowerBound + polygon.z.upperBound) / 2))
        }
        #expect(Bool(true))
    }

    /// Swing-twist of R = Ry(yaw)Rx(pitch)Rz(roll) about the bone axis
    /// (local y): swing is the rotation taking the bone axis to its
    /// rotated direction (axis necessarily in the x-z plane), twist is
    /// what remains about the bone. Returns (hinge-axis tilt off local
    /// x, twist angle, swing angle).
    private func swingTwist(_ angles: EulerAngles) -> (tilt: Double, twist: Double, swing: Double) {
        let r = Mat3.rotation(angles)
        let b = r.rotate(Vec3(0, 1, 0))
        let swing = acos(max(-1, min(1, b.y)))
        // Swing axis = ŷ × b, in the x-z plane.
        let ax = -b.z
        let az = b.x
        let axisLength = (ax * ax + az * az).squareRoot()
        guard axisLength > 1e-9 else {
            // Straight joint: everything is twist.
            let twist = atan2(r.m.2, r.m.0)
            return (0, abs(twist), swing)
        }
        let axis = Vec3(ax / axisLength, 0, az / axisLength)
        let tilt = atan2(abs(axis.z), abs(axis.x))
        let swingMatrix = rodrigues(axis: axis, angle: swing)
        let twistMatrix = swingMatrix.transposed * r
        // A rotation about y: cos in m0, sin in m2.
        let twist = atan2(twistMatrix.m.2, twistMatrix.m.0)
        return (tilt, abs(twist), swing)
    }

    private func rodrigues(axis: Vec3, angle: Double) -> Mat3 {
        let c = Foundation.cos(angle)
        let s = Foundation.sin(angle)
        let t = 1 - c
        let x = axis.x, y = axis.y, z = axis.z
        return Mat3(
            rows: Vec3(t * x * x + c, t * x * y - s * z, t * x * z + s * y),
            Vec3(t * x * y + s * z, t * y * y + c, t * y * z - s * x),
            Vec3(t * x * z - s * y, t * y * z + s * x, t * z * z + c)
        )
    }
}
