import Foundation

/// The mascot's joint tree. Hips-rooted; left/right pairs are mirror
/// twins so a pose authored for one side can be flipped
/// (`MascotPoseBuilder.mirrored`). "Left" is the mascot's left, which
/// sits at +X when it faces the viewer along +Z.
public enum MascotJoint: String, CaseIterable, Sendable, Codable {
    case root
    case spine, chest, neck, head
    case leftShoulder, leftElbow, leftWrist
    case rightShoulder, rightElbow, rightWrist
    case leftHip, leftKnee, leftAnkle
    case rightHip, rightKnee, rightAnkle

    public var parent: MascotJoint? {
        switch self {
        case .root: return nil
        case .spine: return .root
        case .chest: return .spine
        case .neck: return .chest
        case .head: return .neck
        case .leftShoulder, .rightShoulder: return .chest
        case .leftElbow: return .leftShoulder
        case .leftWrist: return .leftElbow
        case .rightElbow: return .rightShoulder
        case .rightWrist: return .rightElbow
        case .leftHip, .rightHip: return .root
        case .leftKnee: return .leftHip
        case .leftAnkle: return .leftKnee
        case .rightKnee: return .rightHip
        case .rightAnkle: return .rightKnee
        }
    }

    /// The sagittal-plane twin: left <-> right, everything on the
    /// midline maps to itself.
    public var mirrored: MascotJoint {
        switch self {
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

    /// Zero angles ARE the natural standing pose: the rest offsets hang
    /// the arms at the sides and stack the legs under the hips, so an
    /// empty pose stands the bot upright facing +Z.
    public var restPose: MascotPose { MascotPose() }

    /// The standard bot, about 1.15 m tall.
    public static let standard: MascotSkeleton = {
        let shoulderSpan = 0.17
        let hipSpan = 0.09
        var bones: [MascotJoint: Bone] = [:]
        bones[.root] = Bone(offset: Vec3(0, 0.55, 0), length: 0.10, thickness: 0.22)
        bones[.spine] = Bone(offset: Vec3(0, 0.05, 0), length: 0.18, thickness: 0.22)
        bones[.chest] = Bone(offset: Vec3(0, 0.18, 0), length: 0.12, thickness: 0.26)
        bones[.neck] = Bone(offset: Vec3(0, 0.12, 0), length: 0.06, thickness: 0.07)
        bones[.head] = Bone(offset: Vec3(0, 0.06, 0), length: 0.22, thickness: 0.20)
        for (shoulder, elbow, wrist, side) in [
            (MascotJoint.leftShoulder, MascotJoint.leftElbow, MascotJoint.leftWrist, 1.0),
            (MascotJoint.rightShoulder, MascotJoint.rightElbow, MascotJoint.rightWrist, -1.0),
        ] {
            bones[shoulder] = Bone(offset: Vec3(side * shoulderSpan, 0.10, 0), length: 0.18, thickness: 0.055)
            bones[elbow] = Bone(offset: Vec3(0, -0.18, 0), length: 0.16, thickness: 0.05)
            bones[wrist] = Bone(offset: Vec3(0, -0.16, 0), length: 0.07, thickness: 0.06)
        }
        for (hip, knee, ankle, side) in [
            (MascotJoint.leftHip, MascotJoint.leftKnee, MascotJoint.leftAnkle, 1.0),
            (MascotJoint.rightHip, MascotJoint.rightKnee, MascotJoint.rightAnkle, -1.0),
        ] {
            bones[hip] = Bone(offset: Vec3(side * hipSpan, -0.03, 0), length: 0.26, thickness: 0.07)
            bones[knee] = Bone(offset: Vec3(0, -0.26, 0), length: 0.24, thickness: 0.06)
            bones[ankle] = Bone(offset: Vec3(0, -0.24, 0), length: 0.12, thickness: 0.05)
        }
        return MascotSkeleton(bones: bones)
    }()
}
