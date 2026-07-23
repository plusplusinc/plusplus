import Foundation

/// THIS bot's mass model — segment masses TRACKING its own mesh
/// volumes in rough liters (the head alone is ~8 L; the limbs are
/// slender), each hung at the segment midpoint, plus the demo bar's
/// mass at the palm midpoint. ONE source of truth shared by the balance
/// invariants and the authoring path servos (a baked descent leans the
/// torso until the center of mass rides over the feet — the same
/// continuous coordination a real lifter does by feel). Approximate by
/// design, but re-check it whenever a silhouette changes: the build-88
/// muscle/feet pass slimmed the legs (lathes vs boxes, −~17% thigh /
/// −~34% shin) and nearly halved the feet, and the table moved with it.
public enum MascotBalance {
    /// Keyed by the segment's child joint; `.root` is the pelvis.
    /// `.wrist` includes the hand; `.ankle` includes the foot.
    public static let segmentMasses: [MascotJoint: Double] = [
        .root: 5.2, .spine: 6.5, .chest: 6.6, .neck: 0.3, .head: 8.4,
        .leftElbow: 0.6, .rightElbow: 0.6,
        .leftWrist: 0.6, .rightWrist: 0.6,
        .leftKnee: 1.4, .rightKnee: 1.4,
        .leftAnkle: 1.0, .rightAnkle: 1.0,
    ]
    /// The demo barbell (small lathe plates — a teaching bar).
    public static let barMass = 2.0
    /// The other held demo props, same teaching-weight scale. The
    /// dumbbell pair joined the mass model in the scale-out round —
    /// it was weightless before, which flattered any move that swings
    /// dumbbells away from the body line.
    public static let kettlebellMass = 2.4
    public static let gobletMass = 1.6
    public static let dumbbellPairMass = 1.6

    /// The support polygon: x/z extents of every contact point
    /// currently ON the ground (sole corners and palm pads within the
    /// contact threshold), padded by half a contact patch. Two planted
    /// feet make the familiar wide box; a heel-up foot shrinks it to
    /// the toe caps; a single-leg stance narrows x to one foot — the
    /// polygon FOLLOWS the contact, which is what balance really is.
    /// Contact points are modeled on the foot's CENTERLINE, so x grows
    /// by the mesh half-width; the sole corners already are the z
    /// extremes, so z gets only a small contact-patch edge.
    public static func supportPolygon(
        pose: MascotPose,
        skeleton: MascotSkeleton = .standard,
        contactThreshold: Double = 0.02,
        halfWidthX: Double = 0.03,
        patchZ: Double = 0.005
    ) -> (x: ClosedRange<Double>, z: ClosedRange<Double>)? {
        var points: [Vec3] = []
        for point in pose.solePoints(skeleton: skeleton) where point.y <= contactThreshold {
            points.append(point)
        }
        for pad in MascotCollision.palmSpheres(pose: pose, skeleton: skeleton)
        where pad.from.y - pad.radius <= contactThreshold {
            points.append(pad.from)
        }
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minZ = first.z, maxZ = first.z
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        return ((minX - halfWidthX)...(maxX + halfWidthX), (minZ - patchZ)...(maxZ + patchZ))
    }

    /// The system center of mass at an animation phase — the same
    /// mass model, sampled through the baked cycle clock.
    public static func centerOfMass(
        animation: ExerciseAnimation,
        at t: Double,
        skeleton: MascotSkeleton = .standard
    ) -> Vec3 {
        let phase = ((t.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1)
        return centerOfMass(pose: animation.pose(at: phase), props: animation.props, skeleton: skeleton)
    }

    /// The zero-moment point (cart-table model): where the ground
    /// reaction must act for the body's ROTATIONAL dynamics to close.
    /// A body standing still has its ZMP under its center of mass; a
    /// body accelerating its mass sideways or downward shifts the ZMP
    /// exactly the way a real athlete's pressure shifts toward toes or
    /// heels. Physics law: while grounded, the ZMP must lie inside the
    /// support polygon — gravity and momentum leave no other place for
    /// the ground to push from. The CoM acceleration comes from
    /// central differences over the cycle (dt in real seconds, sized
    /// to average across spline knots), and the fraction g/(g + a_y)
    /// is the cart-table height correction.
    ///
    /// Also returns the raw CoM acceleration so callers can bound it
    /// directly (a grounded body cannot out-accelerate gravity
    /// downward, and legs have a real drive ceiling).
    public static func zeroMomentPoint(
        animation: ExerciseAnimation,
        at t: Double,
        dt: Double = 1.0 / 30.0,
        skeleton: MascotSkeleton = .standard
    ) -> (x: Double, z: Double, acceleration: Vec3) {
        let gravity = 9.81
        let dtPhase = dt / animation.cycleDuration
        let before = centerOfMass(animation: animation, at: t - dtPhase, skeleton: skeleton)
        let now = centerOfMass(animation: animation, at: t, skeleton: skeleton)
        let after = centerOfMass(animation: animation, at: t + dtPhase, skeleton: skeleton)
        let acceleration = (1.0 / (dt * dt)) * (before + after - 2.0 * now)
        // A denominator collapsing toward zero is free fall — the ZMP
        // stops being defined; callers skip airborne windows, and the
        // clamp keeps a spline wiggle from exploding the projection.
        let denominator = max(gravity + acceleration.y, 2.0)
        let x = now.x - now.y / denominator * acceleration.x
        let z = now.z - now.y / denominator * acceleration.z
        return (x, z, acceleration)
    }

    /// The whole-body (plus held bar) center of mass.
    public static func centerOfMass(
        pose: MascotPose,
        props: [MascotProp],
        skeleton: MascotSkeleton = .standard
    ) -> Vec3 {
        let frames = pose.jointFrames(skeleton: skeleton)
        var moment = Vec3.zero
        var mass = 0.0
        for (joint, m) in segmentMasses {
            guard let p = frames[joint]?.position else { continue }
            var anchor = p
            if joint != .root, let parent = joint.parent, let pp = frames[parent]?.position {
                anchor = 0.5 * (p + pp)
            }
            moment = moment + m * anchor
            mass += m
        }
        if props.contains(.barbell),
           let left = frames[.leftWrist], let right = frames[.rightWrist] {
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            moment = moment + barMass * (0.5 * (leftPalm + rightPalm))
            mass += barMass
        }
        // The other HELD props hang their mass where the mass actually
        // IS: the goblet and dumbbell pair at the palm midpoint (their
        // mass straddles the hands), the kettlebell at the BELL —
        // 82 mm off the handle along the hang direction, which at the
        // swing's float is fully horizontal-forward; a palm-anchored
        // model flattered the proven balance there (swift-reviewer
        // catch). Fixed props (bench, pull-up bar) carry no body-borne
        // mass.
        let heldMasses: [(MascotProp, Double)] = [
            (.kettlebell, kettlebellMass),
            (.gobletDumbbell, gobletMass),
            (.dumbbellPair, dumbbellPairMass),
        ]
        for (prop, propMass) in heldMasses where props.contains(prop) {
            guard let left = frames[.leftWrist], let right = frames[.rightWrist] else { continue }
            let leftPalm = left.position + left.rotation.rotate(MascotGrip.palmOffset)
            let rightPalm = right.position + right.rotation.rotate(MascotGrip.palmOffset)
            var anchor = 0.5 * (leftPalm + rightPalm)
            if prop == .kettlebell {
                // The bell hangs off the handle along the hands' mean
                // fist line, orthogonalized to the handle axis — the
                // same construction as the collision capsule.
                let span = leftPalm - rightPalm
                let spanLength = span.length
                let axis = spanLength > 1e-6 ? (1 / spanLength) * span : Vec3(1, 0, 0)
                let handDown = 0.5 * (left.rotation.rotate(Vec3(0, -1, 0)) + right.rotation.rotate(Vec3(0, -1, 0)))
                let axialPart = handDown.x * axis.x + handDown.y * axis.y + handDown.z * axis.z
                var hang = handDown - axialPart * axis
                let hangLength = hang.length
                hang = hangLength > 1e-6 ? (1 / hangLength) * hang : Vec3(0, -1, 0)
                anchor = anchor + MascotGrip.kettlebellBellDrop * hang
            }
            moment = moment + propMass * anchor
            mass += propMass
        }
        return (1.0 / mass) * moment
    }
}
