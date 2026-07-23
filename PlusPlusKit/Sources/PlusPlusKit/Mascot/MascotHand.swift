import Foundation

/// The mascot's HAND as geometry — palm slab, three fingers, and a
/// thumb, laid out in the wrist joint's local frame for each of the
/// hand's three states (the hand round, from Dave's device pass: curl
/// fingers ran straight through the dumbbell handle, and the planted
/// push-up/plank hands read as curled-under "puppy paws"). ONE source
/// of truth on the `MascotGrip`/`MascotSupport` pattern: the renderer
/// builds its hand meshes from these segments, and the hand invariants
/// prove the SAME segments never pierce equipment and lie flat on the
/// floor — a hand exists in both the pixels and the proof, or in
/// neither.
///
/// Local-frame conventions (the rig's zero hand): palm faces +z,
/// fingers extend -y and curl toward +z, the LEFT thumb sits at +x —
/// which the overhand grip servo maps to world INWARD along the bar.
/// The right hand is the exact mirror (x negated, yaw/roll negated).
public enum MascotHand {
    /// What the hand is doing this whole animation. Picked ONCE per
    /// move by `state(for:)` — the same rule the renderer uses, so the
    /// proof and the pixels can't disagree about what a hand holds.
    public enum State: Equatable {
        /// Wrapped around a cylindrical grip of this radius whose axis
        /// runs along local x through `MascotGrip.palmOffset` (the
        /// barbell shaft, a dumbbell handle).
        case gripped(aroundRadius: Double)
        /// Flat on the floor bearing weight (push-up): palm plane
        /// parallel to the floor, fingers extended forward.
        case planted
        /// A relaxed NEUTRAL FIST (forearm plank): the same wrap as a
        /// grip, closed around nothing — the hand simply continues the
        /// forearm, thumb side up.
        case fist
        /// The goblet CUP: the flat-hand geometry with the palm plane
        /// turned UP, supporting a held weight's underside (distinct
        /// from `.planted` so floor-contact laws never apply to it).
        case cupped
        /// Relaxed half-curl at the side.
        case idle
    }

    public enum Role: Equatable {
        case palm, finger, thumb
    }

    /// One box of the hand: a mesh for the renderer, a capsule for the
    /// invariants. `capsuleAxis` names the box-local axis the capsule
    /// runs along; `capsuleRadius` is the half-thickness that matters
    /// for contact (the tangency direction), not the box envelope.
    public struct Segment {
        public let role: Role
        public let center: Vec3
        public let rotation: EulerAngles
        public let size: Vec3
        public let capsuleAxis: Vec3
        public let capsuleRadius: Double
    }

    /// The planted wrist joint's height above the floor when the palm
    /// plane (local z 0.022) rests flat on it. The anatomical relief
    /// comes from the ARM, not a hand arch: the required wrist
    /// extension is 90° minus the forearm's forward lean, so the
    /// push-up authors its shoulders slightly ahead of its wrists —
    /// which is textbook form anyway.
    public static let plantedWristHeight = 0.022

    /// The per-move hand state — floor support beats gripping (no
    /// current move is both), then the gripped prop's radius, then the
    /// goblet cup; support-only props (the bench) leave the hands
    /// alone. This ONE rule feeds the renderer's meshes AND the hand
    /// invariants' coverage, so a move can't render a grip without
    /// inheriting the grip laws.
    public static func state(for animation: ExerciseAnimation) -> State {
        if animation.dynamics.forearmsBearWeight { return .fist }
        if animation.dynamics.handsBearWeight { return .planted }
        if animation.props.contains(.barbell) {
            return .gripped(aroundRadius: MascotGrip.barRadius)
        }
        if animation.props.contains(.pullUpBar) {
            return .gripped(aroundRadius: MascotSupport.pullUpBarRadius)
        }
        if animation.props.contains(.kettlebell) {
            return .gripped(aroundRadius: MascotGrip.kettlebellHandleRadius)
        }
        if animation.props.contains(.gobletDumbbell) {
            return .cupped
        }
        if animation.props.contains(.dumbbellPair) {
            return .gripped(aroundRadius: MascotGrip.handleRadius)
        }
        return .idle
    }

    /// The hand's segments in the wrist joint's local frame.
    /// `side` is +1 for the left hand, -1 for the right (mirrored).
    public static func segments(state: State, side: Double) -> [Segment] {
        let left = leftSegments(state: state)
        guard side < 0 else { return left }
        return left.map { segment in
            Segment(
                role: segment.role,
                center: Vec3(-segment.center.x, segment.center.y, segment.center.z),
                rotation: EulerAngles(
                    pitch: segment.rotation.pitch,
                    yaw: -segment.rotation.yaw,
                    roll: -segment.rotation.roll
                ),
                size: segment.size,
                capsuleAxis: segment.capsuleAxis,
                capsuleRadius: segment.capsuleRadius
            )
        }
    }

    /// The same segments as world-space capsules, for the invariants.
    public static func capsules(
        state: State,
        side: Double,
        wrist: (position: Vec3, rotation: Mat3)
    ) -> [MascotCollision.Capsule] {
        segments(state: state, side: side).map { segment in
            let center = wrist.position + wrist.rotation.rotate(segment.center)
            let rotation = wrist.rotation * Mat3.rotation(segment.rotation)
            let direction = rotation.rotate(segment.capsuleAxis)
            let length = abs(segment.capsuleAxis.x) * segment.size.x
                + abs(segment.capsuleAxis.y) * segment.size.y
                + abs(segment.capsuleAxis.z) * segment.size.z
            let half = max(length / 2 - segment.capsuleRadius, 0)
            return MascotCollision.Capsule(
                name: "\(side > 0 ? "left" : "right")\(segment.role)",
                from: center + (-half) * direction,
                to: center + half * direction,
                radius: segment.capsuleRadius
            )
        }
    }

    /// The world direction a finger EXTENDS (base toward tip) — the
    /// box's -y through its own rotation and the wrist frame. Pass a
    /// segment from `segments(state:side:)`: mirroring already lives
    /// in the segment's rotation.
    public static func fingerDirection(
        of segment: Segment,
        wrist: (position: Vec3, rotation: Mat3)
    ) -> Vec3 {
        (wrist.rotation * Mat3.rotation(segment.rotation)).rotate(Vec3(0, -1, 0))
    }

    private static let fingerXOffsets = [-0.018, 0.0, 0.018]

    private static func leftSegments(state: State) -> [Segment] {
        switch state {
        case .gripped(let radius):
            return grippedSegments(radius: radius)
        case .planted, .cupped:
            // The cup IS the flat hand — the wrist orientation (palm
            // up under a weight vs palm down on the floor) is the
            // pose's job, not the geometry's.
            return plantedSegments()
        case .fist:
            // The same wrap as a grip, closed around nothing.
            return grippedSegments(radius: 0.010)
        case .idle:
            return idleSegments()
        }
    }

    /// GRIPPED: the fist closes around the grip channel. The palm
    /// slab's underside is the tangent plane resting ON the cylinder;
    /// each finger is three short segments placed TANGENT to a circle
    /// of radius (grip + finger half-thickness + a little slack)
    /// around the channel — tangent placement, not chord placement, so
    /// the inner face touches at its midline and the ends flare away,
    /// never in. Piercing is impossible by construction WHEN the bar
    /// runs along the channel axis; the grip servo's diagonal-grip
    /// allowance (up to 25 degrees of skew, the anatomical pronation
    /// shortfall) shifts the bar sideways within an outer finger's
    /// wrap plane by finger-x times tan(skew) — the tighter gripped
    /// finger spread and the slack absorb most of that, and the
    /// fingers-never-pierce invariant bounds what remains to a
    /// grip-pressure graze. The thumb wraps the far side.
    private static func grippedSegments(radius: Double) -> [Segment] {
        let channel = MascotGrip.palmOffset
        let palmHalfHeight = 0.021
        var segments = [Segment(
            role: .palm,
            center: Vec3(0, channel.y + radius + palmHalfHeight, channel.z),
            rotation: .zero,
            size: Vec3(0.06, palmHalfHeight * 2, 0.05),
            capsuleAxis: Vec3(1, 0, 0),
            capsuleRadius: palmHalfHeight
        )]
        let fingerHalf = 0.0075
        let wrapSlack = 0.002
        let wrapRadius = radius + fingerHalf + wrapSlack
        for dx in [-0.015, 0.0, 0.015] {
            for angle in [35.0, 95.0, 155.0] {
                let phi = angle * .pi / 180
                segments.append(Segment(
                    role: .finger,
                    center: Vec3(
                        dx,
                        channel.y + wrapRadius * Foundation.cos(phi),
                        channel.z + wrapRadius * Foundation.sin(phi)
                    ),
                    rotation: EulerAngles(pitch: phi + .pi / 2),
                    size: Vec3(0.015, 0.032, 0.015),
                    capsuleAxis: Vec3(0, 1, 0),
                    capsuleRadius: fingerHalf
                ))
            }
        }
        let thumbHalf = 0.007
        let thumbWrap = radius + thumbHalf + wrapSlack
        let thumbPhi = -55.0 * .pi / 180
        segments.append(Segment(
            role: .thumb,
            center: Vec3(
                0.026,
                channel.y + thumbWrap * Foundation.cos(thumbPhi),
                channel.z + thumbWrap * Foundation.sin(thumbPhi)
            ),
            rotation: EulerAngles(pitch: thumbPhi + .pi / 2),
            size: Vec3(0.014, 0.036, 0.014),
            capsuleAxis: Vec3(0, 1, 0),
            capsuleRadius: thumbHalf
        ))
        return segments
    }

    /// PLANTED: a flat weight-bearing hand, everything in one plane —
    /// the palm plane at local z = 0.022 rests on the floor, fingers
    /// extend straight past the slab's far edge, the thumb splays
    /// sideways in the same plane. `plantingPalms` orients the wrist
    /// so this plane lies ON the ground.
    private static func plantedSegments() -> [Segment] {
        var segments = [Segment(
            role: .palm,
            center: Vec3(0, -0.026, 0.010),
            rotation: .zero,
            size: Vec3(0.06, 0.05, 0.024),
            capsuleAxis: Vec3(0, 1, 0),
            capsuleRadius: 0.012
        )]
        for (index, dx) in fingerXOffsets.enumerated() {
            let length = index == 1 ? 0.055 : 0.048
            segments.append(Segment(
                role: .finger,
                center: Vec3(dx, -0.050 - length / 2, 0.014),
                rotation: .zero,
                size: Vec3(0.015, length, 0.016),
                capsuleAxis: Vec3(0, 1, 0),
                capsuleRadius: 0.008
            ))
        }
        let thumbRotation = EulerAngles(roll: 40.0 * .pi / 180)
        let thumbDirection = Mat3.rotation(thumbRotation).rotate(Vec3(0, -1, 0))
        let thumbLength = 0.042
        let thumbBase = Vec3(0.027, -0.030, 0.0145)
        let thumbCenter = thumbBase + (thumbLength / 2) * thumbDirection
        segments.append(Segment(
            role: .thumb,
            center: thumbCenter,
            rotation: thumbRotation,
            size: Vec3(0.014, thumbLength, 0.015),
            capsuleAxis: Vec3(0, 1, 0),
            capsuleRadius: 0.0075
        ))
        return segments
    }

    /// IDLE: the relaxed half-curl at the side (the original cartoon
    /// hand, unchanged by the hand round).
    private static func idleSegments() -> [Segment] {
        var segments = [Segment(
            role: .palm,
            center: Vec3(0, -0.02, 0),
            rotation: .zero,
            size: Vec3(0.06, 0.055, 0.052),
            capsuleAxis: Vec3(0, 1, 0),
            capsuleRadius: 0.026
        )]
        for (index, dx) in fingerXOffsets.enumerated() {
            segments.append(Segment(
                role: .finger,
                center: Vec3(dx, -0.045, 0.008),
                rotation: EulerAngles(pitch: -0.45),
                size: Vec3(0.015, index == 1 ? 0.0575 : 0.05, 0.015),
                capsuleAxis: Vec3(0, 1, 0),
                capsuleRadius: 0.0075
            ))
        }
        segments.append(Segment(
            role: .thumb,
            center: Vec3(0.032, -0.028, 0.012),
            rotation: EulerAngles(pitch: -0.35, roll: -0.35),
            size: Vec3(0.014, 0.04, 0.014),
            capsuleAxis: Vec3(0, 1, 0),
            capsuleRadius: 0.007
        ))
        return segments
    }
}
