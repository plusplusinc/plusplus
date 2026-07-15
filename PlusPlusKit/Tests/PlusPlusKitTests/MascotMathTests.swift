import Testing
@testable import PlusPlusKit
import Foundation

@Suite struct MascotMathTests {
    @Test func vec3Arithmetic() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 6, 8)
        #expect(a + b == Vec3(5, 8, 11))
        #expect(b - a == Vec3(3, 4, 5))
        #expect(2 * a == Vec3(2, 4, 6))
        #expect(Vec3(3, 4, 0).length == 5)
        #expect(a.lerp(to: b, t: 0) == a)
        #expect(a.lerp(to: b, t: 1) == b)
        #expect(a.lerp(to: b, t: 0.5) == Vec3(2.5, 4, 5.5))
    }

    @Test func eulerLerpAndDegrees() {
        let a = EulerAngles.deg(pitch: 0, yaw: 10, roll: -20)
        let b = EulerAngles.deg(pitch: 90, yaw: 30, roll: 20)
        let mid = a.lerp(to: b, t: 0.5)
        #expect(abs(mid.pitch - 45 * .pi / 180) < 1e-12)
        #expect(abs(mid.yaw - 20 * .pi / 180) < 1e-12)
        #expect(abs(mid.roll) < 1e-12)
        #expect(EulerAngles.deg(pitch: 180).pitch == .pi)
    }

    @Test func easingFixedPointsAndMonotonicity() {
        let easings: [MascotEasing] = [.linear, .easeIn, .easeOut, .easeInOut]
        for easing in easings {
            #expect(easing.apply(0) == 0)
            #expect(easing.apply(1) == 1)
            var last = -0.001
            var monotone = true
            for i in 0...100 {
                let v = easing.apply(Double(i) / 100)
                if v < last { monotone = false }
                last = v
            }
            #expect(monotone)
        }
        #expect(MascotEasing.easeInOut.apply(0.5) == 0.5)
        #expect(MascotEasing.hold.apply(0.7) == 0)
    }

    @Test func smoothstepFixedPoints() {
        #expect(mascotSmoothstep(0, 1, -1) == 0)
        #expect(mascotSmoothstep(0, 1, 2) == 1)
        #expect(mascotSmoothstep(0, 1, 0.5) == 0.5)
        #expect(mascotSmoothstep(0.5, 1, 0.75) == 0.5)
    }

    @Test func rotationMatricesMatchHandComputedCases() {
        // 90 degrees about X: +Y maps to +Z.
        let rx = Mat3.rotationX(.pi / 2)
        let y = rx.rotate(Vec3(0, 1, 0))
        #expect(abs(y.x) < 1e-12 && abs(y.y) < 1e-12 && abs(y.z - 1) < 1e-12)
        // 90 degrees about Y: +Z maps to +X.
        let ry = Mat3.rotationY(.pi / 2)
        let z = ry.rotate(Vec3(0, 0, 1))
        #expect(abs(z.x - 1) < 1e-12 && abs(z.y) < 1e-12 && abs(z.z) < 1e-12)
        // 90 degrees about Z: +X maps to +Y.
        let rz = Mat3.rotationZ(.pi / 2)
        let x = rz.rotate(Vec3(1, 0, 0))
        #expect(abs(x.x) < 1e-12 && abs(x.y - 1) < 1e-12 && abs(x.z) < 1e-12)
    }

    @Test func rotationOrderContractIsYawPitchRoll() {
        let e = EulerAngles.deg(pitch: 30, yaw: 40, roll: 50)
        let composed = Mat3.rotationY(e.yaw) * Mat3.rotationX(e.pitch) * Mat3.rotationZ(e.roll)
        let direct = Mat3.rotation(e)
        for v in [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)] {
            let a = composed.rotate(v)
            let b = direct.rotate(v)
            #expect(a.distance(to: b) < 1e-12)
        }
    }

    @Test func restSkeletonSanity() {
        let skeleton = MascotSkeleton.standard
        let positions = skeleton.restPose.jointPositions(skeleton: skeleton)
        let head = positions[.head]!
        let leftAnkle = positions[.leftAnkle]!
        let rightAnkle = positions[.rightAnkle]!

        // Head is the highest joint; ankles are the lowest.
        let allY = positions.values.map(\.y)
        #expect(head.y == allY.max())
        let lowest = allY.min()!
        #expect(abs(leftAnkle.y - lowest) < 1e-9 || abs(rightAnkle.y - lowest) < 1e-9)
        // The head JOINT sits at the neck top; the head mesh extends
        // ~0.11 above it, landing total height in the chunky-bot range.
        #expect(head.y > 0.9 && head.y < 1.15)
        // Ankles are just above the ground: shin length remains for the foot.
        #expect(leftAnkle.y > 0 && leftAnkle.y < 0.05)

        // Left/right joints mirror across x = 0.
        for joint in MascotJoint.allCases where joint.mirrored != joint {
            let a = positions[joint]!
            let b = positions[joint.mirrored]!
            #expect(abs(a.x + b.x) < 1e-9, "\(joint) mirror x")
            #expect(abs(a.y - b.y) < 1e-9, "\(joint) mirror y")
            #expect(abs(a.z - b.z) < 1e-9, "\(joint) mirror z")
        }
    }

    @Test func forwardKinematicsSemantics() {
        let skeleton = MascotSkeleton.standard
        // Positive spine pitch leans the torso forward: the head moves +Z.
        let lean = MascotPose(joints: [.spine: .deg(pitch: 30)])
        let leaned = lean.jointPositions(skeleton: skeleton)
        let rest = skeleton.restPose.jointPositions(skeleton: skeleton)
        #expect(leaned[.head]!.z > rest[.head]!.z + 0.05)
        #expect(leaned[.head]!.y < rest[.head]!.y)
        // Legs are untouched by a torso rotation.
        #expect(leaned[.leftAnkle]!.distance(to: rest[.leftAnkle]!) < 1e-12)

        // Positive knee pitch swings the shin backward (heel toward butt).
        let flex = MascotPose(joints: [.leftKnee: .deg(pitch: 90)])
        let flexed = flex.jointPositions(skeleton: skeleton)
        #expect(flexed[.leftAnkle]!.z < rest[.leftAnkle]!.z - 0.1)

        // Root rotation pitches the whole rig: head toward +Z and down.
        let tipped = MascotPose(rootRotation: .deg(pitch: 80))
        let tippedPositions = tipped.jointPositions(skeleton: skeleton)
        #expect(tippedPositions[.head]!.z > 0.3)
        #expect(tippedPositions[.head]!.y < rest[.head]!.y - 0.2)
    }

    @Test func mirroredPoseSwapsSides() {
        let pose = MascotPose(
            rootTranslation: Vec3(0.1, -0.05, 0.02),
            joints: [
                .leftElbow: .deg(pitch: -90, roll: 10),
                .spine: .deg(pitch: 20, yaw: 15),
            ],
            effort: 0.4
        )
        let mirrored = MascotPoseBuilder.mirrored(pose)
        #expect(mirrored.rootTranslation == Vec3(-0.1, -0.05, 0.02))
        #expect(mirrored.joints[.rightElbow] == EulerAngles.deg(pitch: -90, roll: -10))
        #expect(mirrored.joints[.leftElbow] == nil)
        #expect(mirrored.joints[.spine] == EulerAngles.deg(pitch: 20, yaw: -15))
        #expect(mirrored.effort == 0.4)
        // Mirroring twice is the identity.
        let twice = MascotPoseBuilder.mirrored(mirrored)
        #expect(twice.joints == pose.joints)
        #expect(twice.rootTranslation == pose.rootTranslation)
    }

    @Test func plantingFeetRestoresAnkles() {
        let skeleton = MascotSkeleton.standard
        let squatting = MascotPose(
            joints: MascotPoseBuilder.merge(
                MascotPoseBuilder.symmetricLegs(
                    hip: .deg(pitch: -90),
                    knee: .deg(pitch: 78)
                )
            )
        )
        let planted = MascotPoseBuilder.plantingFeet(squatting, skeleton: skeleton)
        let rest = skeleton.restPose.jointPositions(skeleton: skeleton)
        let posed = planted.jointPositions(skeleton: skeleton)
        let restMeanY = (rest[.leftAnkle]!.y + rest[.rightAnkle]!.y) / 2
        let posedMeanY = (posed[.leftAnkle]!.y + posed[.rightAnkle]!.y) / 2
        #expect(abs(restMeanY - posedMeanY) < 1e-9)
        // The solve moved the root down (a squat descends).
        #expect(planted.rootTranslation.y < -0.1)
    }

    @Test func anchoredPinsJointsToTargets() {
        let skeleton = MascotSkeleton.standard
        let pose = MascotPose(rootRotation: .deg(pitch: 78))
        let positions = pose.jointPositions(skeleton: skeleton)
        let target = Vec3(positions[.leftWrist]!.x, 0.03, positions[.leftWrist]!.z)
        let anchored = MascotPoseBuilder.anchored(pose, skeleton: skeleton, anchors: [(.leftWrist, target)])
        let solved = anchored.jointPositions(skeleton: skeleton)
        #expect(solved[.leftWrist]!.distance(to: target) < 1e-9)
    }
}
