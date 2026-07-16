import SwiftUI
import RealityKit
import PlusPlusKit

/// Builds the mascot's RealityKit entity tree from the kit skeleton:
/// one pivot entity per joint (meshes hang off the pivot so rotation
/// happens AT the joint), the dark face panel carrying the embedded
/// "+" eyes, four-fingered cartoon hands, the dot-grid room, and any
/// props the move declares. Everything is generated — no bundled
/// assets, the whole character is code.
///
/// Art direction (build-80 round): matte white body panels over dark
/// charcoal joints — sleek-robot articulation, ASIMO-adjacent without
/// copying — big cartoon feet (also load-bearing: they're the support
/// polygon the kit's balance invariants check against), and the
/// equipment in brand green.
@MainActor
final class MascotRig {
    /// The scene-space parent: bot, room, and props all live here.
    let container: Entity
    let joints: [MascotJoint: Entity]
    let rootRestPosition: SIMD3<Float>
    /// The vertical stroke of each "+" eye; its y-scale is the eye
    /// openness (1 = "+", collapsed = "-").
    let eyeVerticalBars: [ModelEntity]
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
        @discardableResult
        func attach(_ mesh: MeshResource, to joint: MascotJoint, offset: SIMD3<Float>, role: MascotPalette.Role) -> ModelEntity {
            let model = ModelEntity(mesh: mesh)
            model.position = offset
            joints[joint]?.addChild(model)
            themed.append((model, role))
            return model
        }

        // Torso: white pelvis and chest cowl over a dark abdomen —
        // panels over an undersuit.
        attach(box(0.24, 0.15, 0.15, corner: 0.055), to: .root, offset: [0, 0.005, 0], role: .panel)
        attach(box(0.19, 0.15, 0.125), to: .spine, offset: [0, 0.085, 0], role: .joint)
        attach(box(0.30, 0.19, 0.165, corner: 0.06), to: .chest, offset: [0, 0.055, 0], role: .panel)
        attach(box(0.075, 0.075, 0.075), to: .neck, offset: [0, 0.03, 0], role: .joint)

        // Head: white helmet, dark face panel on its front, the green
        // "+" eyes EMBEDDED in the panel (build-80: no floating glyphs).
        attach(box(0.21, 0.23, 0.20, corner: 0.075), to: .head, offset: [0, 0.11, 0], role: .panel)
        let facePanel = ModelEntity(mesh: box(0.148, 0.112, 0.024, corner: 0.012))
        facePanel.position = [0, 0.115, 0.093]
        joints[.head]?.addChild(facePanel)
        themed.append((facePanel, .facePanel))

        var verticalBars: [ModelEntity] = []
        for x in [Float(0.042), -0.042] {
            let pivot = Entity()
            pivot.position = [x, 0.008, 0.011]
            facePanel.addChild(pivot)
            let horizontal = ModelEntity(mesh: box(0.036, 0.009, 0.006))
            let vertical = ModelEntity(mesh: box(0.009, 0.036, 0.006))
            pivot.addChild(horizontal)
            pivot.addChild(vertical)
            themed.append((horizontal, .eye))
            themed.append((vertical, .eye))
            verticalBars.append(vertical)
        }
        eyeVerticalBars = verticalBars

        // Limbs: white segments with dark joint spheres at every
        // articulation point.
        for (joint, size, offset) in [
            (MascotJoint.leftShoulder, (0.055, 0.17, 0.055), SIMD3<Float>(0, -0.09, 0)),
            (.rightShoulder, (0.055, 0.17, 0.055), [0, -0.09, 0]),
            (.leftElbow, (0.05, 0.15, 0.05), [0, -0.08, 0]),
            (.rightElbow, (0.05, 0.15, 0.05), [0, -0.08, 0]),
            (.leftHip, (0.072, 0.25, 0.072), [0, -0.13, 0]),
            (.rightHip, (0.072, 0.25, 0.072), [0, -0.13, 0]),
            (.leftKnee, (0.062, 0.23, 0.062), [0, -0.12, 0]),
            (.rightKnee, (0.062, 0.23, 0.062), [0, -0.12, 0]),
        ] {
            attach(box(size.0, size.1, size.2), to: joint, offset: offset, role: .panel)
        }
        for (joint, radius) in [
            (MascotJoint.leftShoulder, Float(0.048)), (.rightShoulder, 0.048),
            (.leftElbow, 0.04), (.rightElbow, 0.04),
            (.leftHip, 0.05), (.rightHip, 0.05),
            (.leftKnee, 0.042), (.rightKnee, 0.042),
        ] {
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius))
            joints[joint]?.addChild(sphere)
            themed.append((sphere, .joint))
        }

        // Big cartoon feet (matching the kit skeleton's support
        // geometry: heel ~5 cm back, toes ~14.5 cm forward).
        for ankle in [MascotJoint.leftAnkle, .rightAnkle] {
            attach(box(0.07, 0.05, 0.195, corner: 0.022), to: ankle, offset: [0, -0.022, 0.048], role: .panel)
            let sphere = ModelEntity(mesh: .generateSphere(radius: 0.038))
            joints[ankle]?.addChild(sphere)
            themed.append((sphere, .joint))
        }

        // Hands: a dark palm with three fingers and a thumb (cartoon
        // rules). Around a prop the fingers wrap into a grip.
        let gripped = !animation.props.isEmpty
        for (wrist, side) in [(MascotJoint.leftWrist, Float(1)), (.rightWrist, -1)] {
            attach(box(0.06, 0.055, 0.052), to: wrist, offset: [0, -0.02, 0], role: .joint)
            let fingerPitch: Float = gripped ? -1.5 : -0.45
            for (index, dx) in [-0.018, 0, 0.018].enumerated() {
                let finger = ModelEntity(mesh: box(0.015, 0.05, 0.015))
                finger.position = [Float(dx), -0.045, 0.008]
                finger.orientation = simd_quatf(angle: fingerPitch, axis: [1, 0, 0])
                finger.scale = index == 1 ? [1, 1.15, 1] : [1, 1, 1]
                joints[wrist]?.addChild(finger)
                themed.append((finger, .joint))
            }
            let thumb = ModelEntity(mesh: box(0.014, 0.04, 0.014))
            thumb.position = [side * 0.032, -0.028, 0.012]
            thumb.orientation = simd_quatf(angle: gripped ? -1.15 : -0.35, axis: [1, 0, 0])
                * simd_quatf(angle: side * -0.35, axis: [0, 0, 1])
            joints[wrist]?.addChild(thumb)
            themed.append((thumb, .joint))
        }

        // The room: a soft stage disc, a dot-grid floor, and dot-grid
        // walls sized so the clamped orbit camera always stays inside.
        let ground = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.62))
        ground.position = [0, -0.011, 0]
        container.addChild(ground)
        themed.append((ground, .ground))

        let floor = ModelEntity(mesh: .generatePlane(width: 6.4, depth: 6.4))
        floor.position = [0, -0.024, 0]
        container.addChild(floor)
        themed.append((floor, .floor))

        let back = ModelEntity(mesh: .generatePlane(width: 6.4, height: 3.4))
        back.position = [0, 1.65, -2.5]
        container.addChild(back)
        themed.append((back, .wall))
        for side in [Float(1), -1] {
            let wall = ModelEntity(mesh: .generatePlane(width: 6.4, height: 3.4))
            wall.position = [side * 2.7, 1.65, 0]
            wall.orientation = simd_quatf(angle: side * -.pi / 2, axis: [0, 1, 0])
            container.addChild(wall)
            themed.append((wall, .wall))
        }

        // Props: green matte equipment, plates as ROUNDED-EDGE
        // cylinders (a code-generated lathe — Dave's spec).
        // Prop dimensions come from MascotGrip — the shared contract
        // with the kit's equipment-collision invariant, so the proof
        // and the pixels can't drift apart.
        if animation.props.contains(.barbell) {
            let bar = Entity()
            let shaft = ModelEntity(mesh: .generateCylinder(
                height: Float(MascotGrip.barHalfLength * 2),
                radius: Float(MascotGrip.barRadius)
            ))
            shaft.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            bar.addChild(shaft)
            themed.append((shaft, .equipmentDark))
            if let plateMesh = MascotMeshes.roundedCylinder(
                radius: Float(MascotGrip.plateRadius),
                height: Float(MascotGrip.plateHalfWidth * 2),
                edgeRadius: 0.02
            ) {
                for x in [Float(-MascotGrip.plateOffset), Float(MascotGrip.plateOffset)] {
                    let plate = ModelEntity(mesh: plateMesh)
                    plate.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                    plate.position = [x, 0, 0]
                    bar.addChild(plate)
                    themed.append((plate, .equipment))
                }
            }
            container.addChild(bar)
            barbell = bar
        } else {
            barbell = nil
        }
        if animation.props.contains(.dumbbellPair) {
            let headMesh = MascotMeshes.roundedCylinder(
                radius: Float(MascotGrip.dumbbellHeadRadius),
                height: 0.038,
                edgeRadius: 0.014
            )
            for wrist in [MascotJoint.leftWrist, .rightWrist] {
                let dumbbell = Entity()
                dumbbell.position = SIMD3<Float>(MascotGrip.dumbbellOffset)
                let handle = ModelEntity(mesh: .generateCylinder(
                    height: Float(MascotGrip.handleHalfLength * 2),
                    radius: Float(MascotGrip.handleRadius)
                ))
                handle.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                dumbbell.addChild(handle)
                themed.append((handle, .equipmentDark))
                if let headMesh {
                    for x in [Float(-MascotGrip.dumbbellHeadOffset), Float(MascotGrip.dumbbellHeadOffset)] {
                        let head = ModelEntity(mesh: headMesh)
                        head.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                        head.position = [x, 0, 0]
                        dumbbell.addChild(head)
                        themed.append((head, .equipment))
                    }
                }
                joints[wrist]?.addChild(dumbbell)
            }
        }

        self.themed = themed
        apply(palette: palette)
    }

    /// Re-resolves every mesh's material — called on build and whenever
    /// the color scheme flips. The room textures are generated once and
    /// shared across the floor and walls.
    func apply(palette: MascotPalette) {
        let room = palette.makeRoomTextures()
        for (model, role) in themed {
            model.model?.materials = [palette.material(for: role, room: room)]
        }
    }
}
