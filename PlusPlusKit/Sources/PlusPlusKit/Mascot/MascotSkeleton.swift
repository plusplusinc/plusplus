import Foundation

/// The mascot's joint tree. Hips-rooted; left/right pairs are mirror
/// twins so a pose authored for one side can be flipped
/// (`MascotPoseBuilder.mirrored`). "Left" is the mascot's left, which
/// sits at +X when it faces the viewer along +Z.
public enum MascotJoint: String, CaseIterable, Sendable, Codable {
    case root
    case spine, chest, neck, head
    // Clavicles: the shoulder girdle. A human shoulder is not bolted to
    // the ribcage — the scapula/clavicle slides it up (shrug), back
    // (retraction), and forward (protraction), and whole families of
    // movements (a back-squat rack, rows, overhead work) lean on that
    // motion. Dave's rule: the mascot can do ALL movements a human can,
    // so the rig models the girdle instead of moves working around it.
    case leftClavicle, rightClavicle
    case leftShoulder, leftElbow, leftWrist
    case rightShoulder, rightElbow, rightWrist
    case leftHip, leftKnee, leftAnkle
    case rightHip, rightKnee, rightAnkle
    // The forefoot hinge (metatarsophalangeal line): the ball of the
    // foot. Calf raises, lunge trail feet, and jump mechanics all pivot
    // here — the heel rises while the toe cap stays FLAT on the floor,
    // which a rigid foot can only fake by tipping onto its edge.
    case leftToe, rightToe

    public var parent: MascotJoint? {
        switch self {
        case .root: return nil
        case .spine: return .root
        case .chest: return .spine
        case .neck: return .chest
        case .head: return .neck
        case .leftClavicle, .rightClavicle: return .chest
        case .leftShoulder: return .leftClavicle
        case .rightShoulder: return .rightClavicle
        case .leftElbow: return .leftShoulder
        case .leftWrist: return .leftElbow
        case .rightElbow: return .rightShoulder
        case .rightWrist: return .rightElbow
        case .leftHip, .rightHip: return .root
        case .leftKnee: return .leftHip
        case .leftAnkle: return .leftKnee
        case .rightKnee: return .rightHip
        case .rightAnkle: return .rightKnee
        case .leftToe: return .leftAnkle
        case .rightToe: return .rightAnkle
        }
    }

    /// The sagittal-plane twin: left <-> right, everything on the
    /// midline maps to itself.
    public var mirrored: MascotJoint {
        switch self {
        case .leftClavicle: return .rightClavicle
        case .rightClavicle: return .leftClavicle
        case .leftShoulder: return .rightShoulder
        case .leftElbow: return .rightElbow
        case .leftWrist: return .rightWrist
        case .rightShoulder: return .leftShoulder
        case .rightElbow: return .leftElbow
        case .rightWrist: return .leftWrist
        case .leftHip: return .rightHip
        case .leftKnee: return .rightKnee
        case .leftAnkle: return .rightAnkle
        case .rightHip: return .leftHip
        case .rightKnee: return .leftKnee
        case .rightAnkle: return .leftAnkle
        case .leftToe: return .rightToe
        case .rightToe: return .leftToe
        default: return self
        }
    }
}

/// Bone lengths and rest offsets for the standard bot. The renderer
/// sizes its primitive meshes from `length`/`thickness`; the kit's
/// forward kinematics uses only `offset`. Proportions are deliberately
/// chunky (head about a fifth of total height) so the figure reads
/// friendly rather than anatomical.
public struct MascotSkeleton: Sendable {
    public struct Bone: Sendable {
        /// Rest offset of this joint from its parent (meters). The root's
        /// offset is from the world origin, i.e. the rest hip height.
        public let offset: Vec3
        /// Visual length of the segment hanging off this joint toward its
        /// child (or, for leaves like the head and wrists, the mesh size).
        public let length: Double
        public let thickness: Double

        public init(offset: Vec3, length: Double, thickness: Double) {
            self.offset = offset
            self.length = length
            self.thickness = thickness
        }
    }

    private let bones: [MascotJoint: Bone]

    public init(bones: [MascotJoint: Bone]) {
        self.bones = bones
    }

    public func bone(_ joint: MascotJoint) -> Bone {
        bones[joint] ?? Bone(offset: .zero, length: 0, thickness: 0)
    }

    /// The rest hip height above the ground plane.
    public var restRootHeight: Double { bone(.root).offset.y }

    /// The foot sole's landmarks, matching the renderer's split foot
    /// mesh. Heel and BALL corners live in the ANKLE's local frame;
    /// the toe cap's front corner lives in the TOE joint's frame (the
    /// forefoot hinge at the ball line — ankle-local (0, -0.022, 0.08)).
    /// Zero toe angle reproduces the old rigid foot EXACTLY: hinge z
    /// 0.08 + cap length 0.065 = the old toe corner at z 0.145.
    /// Floor-contact invariants check these corners (a rotated foot
    /// digs a corner in long before a joint gets near the ground).
    public static let soleHeelOffset = Vec3(0, -0.047, -0.05)
    public static let soleBallOffset = Vec3(0, -0.047, 0.08)
    public static let toeCapFrontOffset = Vec3(0, -0.025, 0.065)

    /// Zero angles ARE the natural standing pose: the rest offsets hang
    /// the arms at the sides and stack the legs under the hips, so an
    /// empty pose stands the bot upright facing +Z.
    public var restPose: MascotPose { MascotPose() }

    /// The standard bot, about 1.15 m tall.
    public static let standard: MascotSkeleton = {
        let shoulderSpan = 0.17
        let hipSpan = 0.09
        var bones: [MascotJoint: Bone] = [:]
        // Rest hip height puts the SOLES exactly on the floor plane:
        // hip 0.03 + thigh 0.26 + shin 0.24 below the root leaves the
        // ankle at 0.047, and the sole sits 0.047 under the ankle. The
        // round-3 floor invariants measure sole corners against y = 0,
        // so rest = standing on the ground by construction (the first
        // cut used 0.55 and the whole bot stood 2.7 cm sunk).
        bones[.root] = Bone(offset: Vec3(0, 0.577, 0), length: 0.10, thickness: 0.22)
        bones[.spine] = Bone(offset: Vec3(0, 0.05, 0), length: 0.18, thickness: 0.22)
        bones[.chest] = Bone(offset: Vec3(0, 0.18, 0), length: 0.12, thickness: 0.26)
        bones[.neck] = Bone(offset: Vec3(0, 0.12, 0), length: 0.06, thickness: 0.07)
        bones[.head] = Bone(offset: Vec3(0, 0.06, 0), length: 0.22, thickness: 0.20)
        for (clavicle, shoulder, elbow, wrist, side) in [
            (MascotJoint.leftClavicle, MascotJoint.leftShoulder, MascotJoint.leftElbow, MascotJoint.leftWrist, 1.0),
            (MascotJoint.rightClavicle, MascotJoint.rightShoulder, MascotJoint.rightElbow, MascotJoint.rightWrist, -1.0),
        ] {
            // The old chest->shoulder offset split at the girdle: the
            // clavicle roots near the sternum, the shoulder hangs off
            // its lateral end. Zero clavicle angles reproduce the old
            // shoulder position exactly, so every pose authored before
            // the girdle existed is unchanged.
            bones[clavicle] = Bone(offset: Vec3(side * 0.05, 0.10, 0), length: shoulderSpan - 0.05, thickness: 0.04)
            bones[shoulder] = Bone(offset: Vec3(side * (shoulderSpan - 0.05), 0, 0), length: 0.18, thickness: 0.055)
            bones[elbow] = Bone(offset: Vec3(0, -0.18, 0), length: 0.16, thickness: 0.05)
            bones[wrist] = Bone(offset: Vec3(0, -0.16, 0), length: 0.07, thickness: 0.06)
        }
        for (hip, knee, ankle, toe, side) in [
            (MascotJoint.leftHip, MascotJoint.leftKnee, MascotJoint.leftAnkle, MascotJoint.leftToe, 1.0),
            (MascotJoint.rightHip, MascotJoint.rightKnee, MascotJoint.rightAnkle, MascotJoint.rightToe, -1.0),
        ] {
            bones[hip] = Bone(offset: Vec3(side * hipSpan, -0.03, 0), length: 0.26, thickness: 0.07)
            bones[knee] = Bone(offset: Vec3(0, -0.26, 0), length: 0.24, thickness: 0.06)
            // Big cartoon feet, deliberately: a wide support polygon is
            // what lets the chunky proportions squat to textbook depth
            // and stay balanced (ASIMO's feet are huge for the same
            // reason).
            bones[ankle] = Bone(offset: Vec3(0, -0.24, 0), length: 0.14, thickness: 0.05)
            // The forefoot hinge sits at the ball line, mid-height of
            // the foot box; the toe cap hangs off it.
            bones[toe] = Bone(offset: Vec3(0, -0.022, 0.08), length: 0.065, thickness: 0.05)
        }
        return MascotSkeleton(bones: bones)
    }()
}
