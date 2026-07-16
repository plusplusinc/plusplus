import Foundation

/// Where equipment sits in a hand. ONE source of truth shared by the
/// renderer (which places the meshes) and the collision invariant
/// (which proves the equipment never passes through the body) — if
/// these lived in two files they would drift.
public enum MascotGrip {
    /// Palm center in the wrist joint's local frame — the barbell axis
    /// passes through both palms.
    public static let palmOffset = Vec3(0, -0.038, 0.01)
    /// Dumbbell center in the wrist joint's local frame.
    public static let dumbbellOffset = Vec3(0, -0.045, 0.012)
    /// Bar shaft: radius and half-length; plates: radius, half-width,
    /// and distance out along the axis.
    public static let barRadius = 0.017
    public static let barHalfLength = 0.46
    public static let plateRadius = 0.095
    public static let plateHalfWidth = 0.025
    public static let plateOffset = 0.38
    /// Dumbbell: handle half-length/radius, head radius and offset
    /// (along the wrist's local X).
    public static let handleHalfLength = 0.075
    public static let handleRadius = 0.014
    public static let dumbbellHeadRadius = 0.042
    public static let dumbbellHeadOffset = 0.062
}

/// Capsule-based collision between the mascot's equipment and its own
/// body ("the equipment never passes through any part of the body" —
/// Dave). Everything is a capsule: body segments over the FK frames
/// with radii mirroring the renderer's mesh volumes, the bar shaft and
/// plates along the palm-to-palm axis, dumbbell handles and heads in
/// each wrist frame. The HANDS AND FOREARMS are deliberately excluded:
/// the hands grip the equipment, so contact there is correct.
public enum MascotCollision {
    public struct Capsule {
        public let name: String
        public let from: Vec3
        public let to: Vec3
        public let radius: Double
    }

    /// Body capsule radii, mirroring the renderer's meshes. Torso
    /// entries are the box HALF-DEPTHS (the direction a bar approaches
    /// from); the head is a sphere around its mesh center.
    static let segmentRadii: [(child: MascotJoint, radius: Double)] = [
        (.spine, 0.075),   // pelvis/lower torso
        (.chest, 0.08),    // abdomen
        (.neck, 0.085),    // chest cowl
        (.leftElbow, 0.028), (.rightElbow, 0.028),   // upper arms
        (.leftKnee, 0.036), (.rightKnee, 0.036),     // thighs
        (.leftAnkle, 0.031), (.rightAnkle, 0.031),   // shins
    ]

    public static func bodyCapsules(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard
    ) -> [Capsule] {
        let frames = pose.jointFrames(skeleton: skeleton)
        var capsules: [Capsule] = []
        for (child, radius) in segmentRadii {
            guard let parent = child.parent,
                  let a = frames[parent]?.position,
                  let b = frames[child]?.position else { continue }
            capsules.append(Capsule(name: "\(parent)->\(child)", from: a, to: b, radius: radius))
        }
        // Head: a sphere at the helmet's center.
        if let head = frames[.head] {
            let center = head.position + head.rotation.rotate(Vec3(0, 0.11, 0))
            capsules.append(Capsule(name: "head", from: center, to: center, radius: 0.115))
        }
        // Feet: ankle to toe.
        let toes = pose.toePositions(skeleton: skeleton)
        if let leftAnkle = frames[.leftAnkle]?.position {
            capsules.append(Capsule(name: "leftFoot", from: leftAnkle, to: toes.left, radius: 0.03))
        }
        if let rightAnkle = frames[.rightAnkle]?.position {
            capsules.append(Capsule(name: "rightFoot", from: rightAnkle, to: toes.right, radius: 0.03))
        }
        return capsules
    }

    public static func equipmentCapsules(
        pose: MascotPose,
        props: [MascotProp],
        skeleton: MascotSkeleton = .standard
    ) -> [Capsule] {
        guard !props.isEmpty else { return [] }
        let frames = pose.jointFrames(skeleton: skeleton)
        guard let left = frames[.leftWrist], let right = frames[.rightWrist] else { return [] }
        var capsules: [Capsule] = []

        if props.contains(.barbell) {
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            let center = 0.5 * (leftPalm + rightPalm)
            let span = leftPalm - rightPalm
            let length = span.length
            let axis = length > 1e-6 ? (1 / length) * span : Vec3(1, 0, 0)
            capsules.append(Capsule(
                name: "barShaft",
                from: center + (-MascotGrip.barHalfLength) * axis,
                to: center + MascotGrip.barHalfLength * axis,
                radius: MascotGrip.barRadius
            ))
            for side in [-1.0, 1.0] {
                let plateCenter = center + (side * MascotGrip.plateOffset) * axis
                capsules.append(Capsule(
                    name: "plate\(side > 0 ? "L" : "R")",
                    from: plateCenter + (-MascotGrip.plateHalfWidth) * axis,
                    to: plateCenter + MascotGrip.plateHalfWidth * axis,
                    radius: MascotGrip.plateRadius
                ))
            }
        }

        if props.contains(.dumbbellPair) {
            for (frame, label) in [(left, "L"), (right, "R")] {
                let center = frame.position + frame.rotation.rotate(MascotGrip.dumbbellOffset)
                let axis = frame.rotation.rotate(Vec3(1, 0, 0))
                capsules.append(Capsule(
                    name: "handle\(label)",
                    from: center + (-MascotGrip.handleHalfLength) * axis,
                    to: center + MascotGrip.handleHalfLength * axis,
                    radius: MascotGrip.handleRadius
                ))
                for side in [-1.0, 1.0] {
                    let headCenter = center + (side * MascotGrip.dumbbellHeadOffset) * axis
                    capsules.append(Capsule(
                        name: "dumbbellHead\(label)\(side > 0 ? "+" : "-")",
                        from: headCenter,
                        to: headCenter,
                        radius: MascotGrip.dumbbellHeadRadius
                    ))
                }
            }
        }
        return capsules
    }

    /// The deepest equipment-into-body penetration at a set phase, in
    /// meters. Zero or negative = fully clear; small positive = grazing
    /// contact (a deadlift bar resting against the thighs); large
    /// positive = the equipment is inside the body. Also names the
    /// worst pair for test diagnostics.
    public static func maxEquipmentPenetration(
        animation: ExerciseAnimation,
        at t: Double,
        skeleton: MascotSkeleton = .standard
    ) -> (depth: Double, pair: String) {
        let pose = animation.pose(at: t)
        let body = bodyCapsules(pose: pose, skeleton: skeleton)
        let equipment = equipmentCapsules(pose: pose, props: animation.props, skeleton: skeleton)
        var worst = (depth: -Double.infinity, pair: "none")
        for item in equipment {
            for segment in body {
                let distance = mascotSegmentDistance(item.from, item.to, segment.from, segment.to)
                let depth = (item.radius + segment.radius) - distance
                if depth > worst.depth {
                    worst = (depth, "\(item.name) vs \(segment.name)")
                }
            }
        }
        return worst
    }
}
