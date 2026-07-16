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
    /// The palm CONTACT PAD: where a weight-bearing flat hand meets the
    /// floor — the bottom of the hand mesh, unlike `palmOffset`, which
    /// is the grip-channel center inside curled fingers (a push-up
    /// authored to the grip point sank the hands 2 cm into the ground).
    public static let contactPadOffset = Vec3(0, -0.0375, 0.008)
    public static let contactPadRadius = 0.012
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
        (.leftShoulder, 0.0275), (.rightShoulder, 0.0275),   // clavicle yokes
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
        // Feet: capsules along the SOLE line of the renderer's SPLIT
        // foot mesh (the forefoot hinge) — rearfoot from heel corner to
        // ball line in the ankle frame, toe cap along the toe joint's
        // hinged frame, both lifted to the boxes' mid-height. (The old
        // ankle-to-pointed-toe segment dived 12 cm under the floor on a
        // standing foot.)
        let midHeight = Vec3(0, 0.025, 0)
        for (ankle, toe, name) in [
            (MascotJoint.leftAnkle, MascotJoint.leftToe, "left"),
            (.rightAnkle, .rightToe, "right"),
        ] {
            guard let ankleFrame = frames[ankle], let toeFrame = frames[toe] else { continue }
            capsules.append(Capsule(
                name: "\(name)Foot",
                from: ankleFrame.position + ankleFrame.rotation.rotate(MascotSkeleton.soleHeelOffset + midHeight),
                to: ankleFrame.position + ankleFrame.rotation.rotate(MascotSkeleton.soleBallOffset + midHeight),
                radius: 0.025
            ))
            capsules.append(Capsule(
                name: "\(name)ToeCap",
                from: toeFrame.position,
                to: toeFrame.position + toeFrame.rotation.rotate(Vec3(0, 0, 0.065)),
                radius: 0.025
            ))
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
        maxEquipmentPenetration(pose: animation.pose(at: t), props: animation.props, skeleton: skeleton)
    }

    /// The bare-pose form — what path solvers use to keep a hanging
    /// bar OUTSIDE the legs at every baked sample, not just at the
    /// authored endpoints.
    public static func maxEquipmentPenetration(
        pose: MascotPose,
        props: [MascotProp],
        skeleton: MascotSkeleton = .standard
    ) -> (depth: Double, pair: String) {
        let body = bodyCapsules(pose: pose, skeleton: skeleton)
        let equipment = equipmentCapsules(pose: pose, props: props, skeleton: skeleton)
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

    /// Palm contact pads (the hands are excluded from the capsule body
    /// model because they GRIP; for floor contact the pad at the flat
    /// hand's underside is what touches).
    public static func palmSpheres(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard
    ) -> [Capsule] {
        let frames = pose.jointFrames(skeleton: skeleton)
        var spheres: [Capsule] = []
        for (wrist, name) in [(MascotJoint.leftWrist, "leftPalm"), (.rightWrist, "rightPalm")] {
            guard let frame = frames[wrist] else { continue }
            let center = frame.position + frame.rotation.rotate(MascotGrip.contactPadOffset)
            spheres.append(Capsule(name: name, from: center, to: center, radius: MascotGrip.contactPadRadius))
        }
        return spheres
    }

    /// How far below the floor anything reaches at a set phase, split
    /// by allowance class: `contact` parts (soles, toes, palms — they
    /// MAY touch the floor), `body` capsules (must stay above it), and
    /// `equipment`. Positive = below the floor plane by that much.
    public static func floorPenetration(
        animation: ExerciseAnimation,
        at t: Double,
        skeleton: MascotSkeleton = .standard
    ) -> (contact: Double, body: Double, equipment: Double, worstPart: String) {
        let pose = animation.pose(at: t)
        var worstContact = -Double.infinity
        var worstBody = -Double.infinity
        var worstEquipment = -Double.infinity
        var worstPart = "none"
        var deepest = -Double.infinity

        func note(_ depth: Double, _ name: String) {
            if depth > deepest {
                deepest = depth
                worstPart = name
            }
        }
        // Contact parts are MESH surfaces that may touch the ground:
        // the sole corners and the palm spheres. (The pointed-toe bone
        // reach is a solver target, not a surface point — a standing
        // foot's reach dangles 9 cm below its sole.)
        for point in pose.solePoints(skeleton: skeleton) {
            let depth = -point.y
            worstContact = max(worstContact, depth)
            note(depth, "sole")
        }
        for palm in palmSpheres(pose: pose, skeleton: skeleton) {
            let depth = -(palm.from.y - palm.radius)
            worstContact = max(worstContact, depth)
            note(depth, palm.name)
        }
        for capsule in bodyCapsules(pose: pose, skeleton: skeleton) {
            // Feet (rearfoot AND toe caps) are contact parts, checked
            // via their sole corners.
            guard !capsule.name.hasSuffix("Foot") && !capsule.name.hasSuffix("ToeCap") else { continue }
            let depth = -(min(capsule.from.y, capsule.to.y) - capsule.radius)
            worstBody = max(worstBody, depth)
            note(depth, capsule.name)
        }
        for item in equipmentCapsules(pose: pose, props: animation.props, skeleton: skeleton) {
            let depth = -(min(item.from.y, item.to.y) - item.radius)
            worstEquipment = max(worstEquipment, depth)
            note(depth, item.name)
        }
        return (worstContact, worstBody, worstEquipment, worstPart)
    }

    /// The deepest body-part-into-body-part penetration, skipping
    /// segment pairs that are adjacent in the joint tree (they join by
    /// construction). Grazing tolerance is the caller's call.
    public static func maxSelfPenetration(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard
    ) -> (depth: Double, pair: String) {
        let body = bodyCapsules(pose: pose, skeleton: skeleton)
        var joints: [String: Set<MascotJoint>] = [:]
        for (child, _) in segmentRadii {
            guard let parent = child.parent else { continue }
            joints["\(parent)->\(child)"] = [parent, child]
        }
        joints["head"] = [.neck, .head]
        joints["leftFoot"] = [.leftKnee, .leftAnkle]
        joints["rightFoot"] = [.rightKnee, .rightAnkle]
        joints["leftToeCap"] = [.leftAnkle, .leftToe]
        joints["rightToeCap"] = [.rightAnkle, .rightToe]

        // Clavicles are pass-through for adjacency: no capsule spans
        // them (the upper-arm capsule starts at the shoulder), so the
        // shoulder's structural neighbor is still the chest.
        func up(_ joint: MascotJoint) -> MascotJoint? {
            var parent = joint.parent
            while parent == .leftClavicle || parent == .rightClavicle {
                parent = parent?.parent
            }
            return parent
        }
        // Adjacent = the segments share a joint or a direct
        // parent-child link. Deliberately NOT "share a grandparent":
        // that would exempt thigh-vs-thigh and arm-vs-arm, and crossed
        // limbs are exactly what a self-collision invariant must see.
        func adjacent(_ a: Set<MascotJoint>, _ b: Set<MascotJoint>) -> Bool {
            if !a.isDisjoint(with: b) { return true }
            for x in a {
                for y in b {
                    if up(x) == y || up(y) == x { return true }
                }
            }
            return false
        }
        // The one legitimate deep-fold contact: a full-depth squat
        // presses the thighs against the abdomen — humans fold there,
        // so that single pairing is allowed while everything else
        // (thigh-thigh, arm-arm, arm-head) stays enforced.
        let foldPairs: Set<String> = [
            "spine->chest|leftHip->leftKnee",
            "spine->chest|rightHip->rightKnee",
        ]
        func deliberateFold(_ a: String, _ b: String) -> Bool {
            foldPairs.contains("\(a)|\(b)") || foldPairs.contains("\(b)|\(a)")
        }

        var worst = (depth: -Double.infinity, pair: "none")
        for i in 0..<body.count {
            for j in (i + 1)..<body.count {
                let a = body[i]
                let b = body[j]
                guard let ja = joints[a.name], let jb = joints[b.name],
                      !adjacent(ja, jb), !deliberateFold(a.name, b.name) else { continue }
                let distance = mascotSegmentDistance(a.from, a.to, b.from, b.to)
                let depth = (a.radius + b.radius) - distance
                if depth > worst.depth {
                    worst = (depth, "\(a.name) vs \(b.name)")
                }
            }
        }
        return worst
    }

    /// Grip alignment for barbell moves: the angle (radians) between
    /// each hand's grip axis (the wrist frame's local X — the direction
    /// wrapped fingers form a channel along) and the bar axis. A hand
    /// whose channel is skew to the bar cannot actually be holding it
    /// (build-81 feedback: "hands facing the right way").
    public static func worstGripMisalignment(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard
    ) -> Double {
        let frames = pose.jointFrames(skeleton: skeleton)
        guard let left = frames[.leftWrist], let right = frames[.rightWrist] else { return 0 }
        let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
        let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
        let span = leftPalm - rightPalm
        let length = span.length
        guard length > 1e-6 else { return 0 }
        let axis = (1 / length) * span
        var worst = 0.0
        for frame in [left, right] {
            let handAxis = frame.rotation.rotate(Vec3(1, 0, 0))
            let cosine = min(max(abs(handAxis.x * axis.x + handAxis.y * axis.y + handAxis.z * axis.z), 0), 1)
            worst = max(worst, Foundation.acos(cosine))
        }
        return worst
    }
}
