import SwiftUI
import RealityKit
import PlusPlusKit

/// Builds the mascot's RealityKit entity tree from the kit skeleton:
/// one pivot entity per joint (meshes hang off the pivot so rotation
/// happens AT the joint), the "+" eyes, four-fingered cartoon hands,
/// the ground disc, and any props the move declares. Everything is a
/// generated primitive — no bundled assets, the whole character is
/// code.
@MainActor
final class MascotRig {
    /// The scene-space parent: bot, ground, and props all live here.
    let container: Entity
    let joints: [MascotJoint: Entity]
    let rootRestPosition: SIMD3<Float>
    /// The vertical stroke of each "+" eye; its y-scale is the eye
    /// openness (1 = "+", collapsed = "-").
    let eyeVerticalBars: [ModelEntity]
    let leftEyePivot: Entity
    let rightEyePivot: Entity
    /// What the demo sheet's orbit camera targets.
    let chestTarget: Entity
    let barbell: Entity?

    private var themed: [(ModelEntity, MascotPalette.Role)] = []
    private let skeleton = MascotSkeleton.standard

    init(animation: ExerciseAnimation, palette: MascotPalette) {
        container = Entity()

        // Joint pivots, parented per the skeleton tree.
        var joints: [MascotJoint: Entity] = [:]
        for joint in MascotJoint.allCases {
            let entity = Entity()
            let bone = skeleton.bone(joint)
            entity.position = SIMD3<Float>(bone.offset)
            joints[joint] = entity
            if let parent = joint.parent {
                joints[parent]?.addChild(entity)
            } else {
                container.addChild(entity)
            }
        }
        self.joints = joints
        rootRestPosition = SIMD3<Float>(skeleton.bone(.root).offset)

        func box(_ width: Double, _ height: Double, _ depth: Double, corner: Double? = nil) -> MeshResource {
            let radius = Float(corner ?? (min(width, min(height, depth)) * 0.45))
            return .generateBox(
                size: [Float(width), Float(height), Float(depth)],
                cornerRadius: radius
            )
        }

        var themed: [(ModelEntity, MascotPalette.Role)] = []
        func attach(_ mesh: MeshResource, to joint: MascotJoint, offset: SIMD3<Float>, role: MascotPalette.Role) -> ModelEntity {
            let model = ModelEntity(mesh: mesh)
            model.position = offset
            joints[joint]?.addChild(model)
            themed.append((model, role))
            return model
        }

        // Torso and head. Sizes echo the skeleton's bone lengths with a
        // little overlap so segments read as one body.
        _ = attach(box(0.23, 0.15, 0.15), to: .root, offset: [0, 0.01, 0], role: .body)
        _ = attach(box(0.22, 0.21, 0.14), to: .spine, offset: [0, 0.09, 0], role: .body)
        _ = attach(box(0.26, 0.17, 0.15), to: .chest, offset: [0, 0.06, 0], role: .body)
        _ = attach(box(0.07, 0.07, 0.07), to: .neck, offset: [0, 0.03, 0], role: .body)
        let head = attach(box(0.20, 0.22, 0.19, corner: 0.07), to: .head, offset: [0, 0.11, 0], role: .body)

        // Limbs: capsule-ish boxes hanging from each pivot toward its
        // child, so rotating the pivot swings the segment.
        for (joint, size, offset) in [
            (MascotJoint.leftShoulder, (0.058, 0.19, 0.058), SIMD3<Float>(0, -0.09, 0)),
            (.rightShoulder, (0.058, 0.19, 0.058), [0, -0.09, 0]),
            (.leftElbow, (0.052, 0.17, 0.052), [0, -0.08, 0]),
            (.rightElbow, (0.052, 0.17, 0.052), [0, -0.08, 0]),
            (.leftHip, (0.075, 0.27, 0.075), [0, -0.13, 0]),
            (.rightHip, (0.075, 0.27, 0.075), [0, -0.13, 0]),
            (.leftKnee, (0.065, 0.25, 0.065), [0, -0.12, 0]),
            (.rightKnee, (0.065, 0.25, 0.065), [0, -0.12, 0]),
        ] {
            _ = attach(box(size.0, size.1, size.2), to: joint, offset: offset, role: .body)
        }

        // Feet, toes forward.
        for ankle in [MascotJoint.leftAnkle, .rightAnkle] {
            _ = attach(box(0.065, 0.05, 0.13), to: ankle, offset: [0, -0.02, 0.03], role: .hand)
        }

        // The face: two "+" glyphs on the head's front. Each eye is a
        // pivot (for the tired droop) holding a horizontal bar and a
        // vertical bar whose y-scale is driven by the face channel —
        // a blink collapses the plus into a minus.
        var verticalBars: [ModelEntity] = []
        func buildEye(x: Float) -> Entity {
            let pivot = Entity()
            pivot.position = [x, 0.115, 0.098]
            head.parent?.addChild(pivot)
            let horizontal = ModelEntity(mesh: box(0.034, 0.008, 0.006))
            let vertical = ModelEntity(mesh: box(0.008, 0.034, 0.006))
            pivot.addChild(horizontal)
            pivot.addChild(vertical)
            themed.append((horizontal, .eye))
            themed.append((vertical, .eye))
            verticalBars.append(vertical)
            return pivot
        }
        leftEyePivot = buildEye(x: 0.048)
        rightEyePivot = buildEye(x: -0.048)
        eyeVerticalBars = verticalBars

        // Hands: a palm with three fingers and a thumb (cartoon rules).
        // Around a prop the fingers wrap into a grip; otherwise they
        // rest in a relaxed curl.
        let gripped = !animation.props.isEmpty
        for (wrist, side) in [(MascotJoint.leftWrist, Float(1)), (.rightWrist, -1)] {
            _ = attach(box(0.06, 0.055, 0.052), to: wrist, offset: [0, -0.02, 0], role: .hand)
            let fingerPitch: Float = gripped ? -1.45 : -0.45
            for (index, dx) in [-0.018, 0, 0.018].enumerated() {
                let finger = ModelEntity(mesh: box(0.015, 0.05, 0.015))
                finger.position = [Float(dx), -0.045, 0.008]
                finger.orientation = simd_quatf(angle: fingerPitch, axis: [1, 0, 0])
                // Middle finger a touch longer, like a mitten that tried.
                finger.scale = index == 1 ? [1, 1.15, 1] : [1, 1, 1]
                joints[wrist]?.addChild(finger)
                themed.append((finger, .hand))
            }
            let thumb = ModelEntity(mesh: box(0.014, 0.04, 0.014))
            thumb.position = [side * 0.032, -0.028, 0.012]
            thumb.orientation = simd_quatf(angle: gripped ? -1.1 : -0.35, axis: [1, 0, 0])
                * simd_quatf(angle: side * -0.35, axis: [0, 0, 1])
            joints[wrist]?.addChild(thumb)
            themed.append((thumb, .hand))
        }

        // The ground: a soft platform disc under the bot.
        let ground = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.6))
        ground.position = [0, -0.011, 0]
        container.addChild(ground)
        themed.append((ground, .ground))

        // Props, built from primitives like everything else.
        if animation.props.contains(.barbell) {
            let bar = Entity()
            let shaft = ModelEntity(mesh: .generateCylinder(height: 0.92, radius: 0.017))
            shaft.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            bar.addChild(shaft)
            themed.append((shaft, .bar))
            for x in [Float(-0.38), 0.38] {
                let plate = ModelEntity(mesh: .generateCylinder(height: 0.045, radius: 0.095))
                plate.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                plate.position = [x, 0, 0]
                bar.addChild(plate)
                themed.append((plate, .plate))
            }
            container.addChild(bar)
            barbell = bar
        } else {
            barbell = nil
        }
        if animation.props.contains(.dumbbellPair) {
            for wrist in [MascotJoint.leftWrist, .rightWrist] {
                let dumbbell = Entity()
                dumbbell.position = [0, -0.045, 0.012]
                let handle = ModelEntity(mesh: .generateCylinder(height: 0.15, radius: 0.014))
                handle.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                dumbbell.addChild(handle)
                themed.append((handle, .bar))
                for x in [Float(-0.062), 0.062] {
                    let head = ModelEntity(mesh: .generateCylinder(height: 0.035, radius: 0.042))
                    head.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                    head.position = [x, 0, 0]
                    dumbbell.addChild(head)
                    themed.append((head, .plate))
                }
                joints[wrist]?.addChild(dumbbell)
            }
        }

        chestTarget = joints[.chest] ?? container
        self.themed = themed
        apply(palette: palette)
    }

    /// Re-resolves every mesh's material — called on build and whenever
    /// the color scheme flips.
    func apply(palette: MascotPalette) {
        for (model, role) in themed {
            model.model?.materials = [palette.material(for: role)]
        }
    }
}
