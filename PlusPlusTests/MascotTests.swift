import Foundation
import Testing
import simd
import PlusPlusKit
@testable import PlusPlus

/// The app-side mascot contracts: the animation catalog stays keyed to
/// REAL built-in exercise names (a seed rename would otherwise orphan a
/// demo silently — exercise identity IS the name), and the renderer's
/// quaternion composition matches the kit's rotation matrices exactly.
@Suite struct MascotTests {
    @Test func everyMascotMoveMatchesABuiltInExercise() {
        for animation in MascotMoves.all {
            let definition = SeedData.builtInDefinition(named: animation.exerciseName)
            #expect(definition != nil, "\(animation.exerciseName) has no seed-catalog counterpart")
        }
    }

    @Test func thePrototypeMovesAreCovered() {
        for name in ["Squat", "Deadlift", "Push-Up", "Dumbbell Curl", "Plank", "Bench Press"] {
            #expect(MascotMoves.animation(forExerciseNamed: name) != nil, "missing demo for \(name)")
        }
        // Name matching is exact: no entry, no FORM section. (Running
        // is a real built-in with no authored demo yet.)
        #expect(MascotMoves.animation(forExerciseNamed: "squat") == nil)
        #expect(MascotMoves.animation(forExerciseNamed: "Running") == nil)
    }

    /// THE order contract: `MascotPoseApplier.quaternion(from:)` (simd,
    /// app-side) and `Mat3.rotation` (hand-rolled, kit-side, what every
    /// Linux invariant test validates against) must be the same
    /// rotation. A mismatch here means the animations that pass kit
    /// validation would render folded on device.
    @Test func quaternionCompositionMatchesKitMatrices() {
        let degreesGrid: [Double] = [-150, -90, -45, -10, 0, 10, 45, 90, 150]
        let basis: [Vec3] = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1), Vec3(0.5, -0.7, 0.3)]
        for pitch in degreesGrid {
            for yaw in degreesGrid {
                for roll in degreesGrid {
                    let euler = EulerAngles.deg(pitch: pitch, yaw: yaw, roll: roll)
                    let matrix = Mat3.rotation(euler)
                    let quaternion = MascotPoseApplier.quaternion(from: euler)
                    for vector in basis {
                        let viaMatrix = matrix.rotate(vector)
                        let viaQuat = quaternion.act(SIMD3<Float>(
                            Float(vector.x), Float(vector.y), Float(vector.z)
                        ))
                        let dx = abs(Float(viaMatrix.x) - viaQuat.x)
                        let dy = abs(Float(viaMatrix.y) - viaQuat.y)
                        let dz = abs(Float(viaMatrix.z) - viaQuat.z)
                        let matches = dx < 1e-5 && dy < 1e-5 && dz < 1e-5
                        #expect(matches, "mismatch at pitch \(pitch), yaw \(yaw), roll \(roll)")
                    }
                }
            }
        }
    }
}
