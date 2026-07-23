import Testing
import Foundation
@testable import PlusPlusKit

// Scratch probes for the device-report round (deleted before ship):
// palm normals, hand-forearm alignment, and planted-hand travel for
// the moves Dave flagged.
struct ScratchHandProbeTests {
    @Test func dumpHandPresentation() {
        let deg = 180.0 / Double.pi
        let skeleton = MascotSkeleton.standard
        for name in ["Barbell Row", "Lateral Raise", "Dumbbell Curl", "Plank", "Sit-Up", "Kettlebell Swing"] {
            guard let animation = MascotMoves.animation(forExerciseNamed: name) else { continue }
            var normalZMin = 1.0, normalZMax = -1.0
            var alongMin = 1.0
            var palmSpanMin = 1.0, palmSpanMax = -1.0
            for i in 0...200 {
                let t = Double(i) / 200
                let frames = animation.pose(at: t).jointFrames(skeleton: skeleton)
                guard let lw = frames[.leftWrist], let le = frames[.leftElbow], let rw = frames[.rightWrist] else { continue }
                let normal = lw.rotation.rotate(Vec3(0, 0, 1))
                normalZMin = min(normalZMin, normal.z); normalZMax = max(normalZMax, normal.z)
                let hand = lw.rotation.rotate(Vec3(0, -1, 0))
                let f = lw.position - le.position
                let fl = f.length
                if fl > 1e-9 {
                    let along = (hand.x * f.x + hand.y * f.y + hand.z * f.z) / fl
                    alongMin = min(alongMin, along)
                }
                let lp = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
                let rp = rw.position + rw.rotation.rotate(MascotGrip.palmOffset)
                let span = (lp - rp).length
                palmSpanMin = min(palmSpanMin, span); palmSpanMax = max(palmSpanMax, span)
            }
            print(String(format: "%@: palmNormal.z %.2f..%.2f | hand-along-forearm min %.2f | palm span %.3f..%.3f",
                         name, normalZMin, normalZMax, alongMin, palmSpanMin, palmSpanMax))
        }
        // Planted-hand travel: how far palms wander on the floor.
        for name in ["Push-Up", "Plank"] {
            guard let animation = MascotMoves.animation(forExerciseNamed: name) else { continue }
            var minX = Double.infinity, maxX = -Double.infinity
            var minZ = Double.infinity, maxZ = -Double.infinity
            for i in 0...200 {
                let t = Double(i) / 200
                let frames = animation.pose(at: t).jointFrames(skeleton: skeleton)
                guard let lw = frames[.leftWrist] else { continue }
                let palm = lw.position + lw.rotation.rotate(MascotGrip.palmOffset)
                minX = min(minX, palm.x); maxX = max(maxX, palm.x)
                minZ = min(minZ, palm.z); maxZ = max(maxZ, palm.z)
            }
            print(String(format: "%@: left palm travel x %.1f mm, z %.1f mm",
                         name, (maxX - minX) * 1000, (maxZ - minZ) * 1000))
        }
        #expect(Bool(true))
    }
}
