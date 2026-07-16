import Foundation

/// Minimal 3D vector for the mascot's pose math. Hand-rolled on purpose:
/// simd does not exist on Linux, and this package's whole value is that
/// every authored exercise animation is numerically validated by
/// `swift test` in the kit-test CI job (and from remote sessions).
public struct Vec3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Double, rhs: Vec3) -> Vec3 {
        Vec3(lhs * rhs.x, lhs * rhs.y, lhs * rhs.z)
    }

    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    public func lerp(to other: Vec3, t: Double) -> Vec3 {
        self + t * (other - self)
    }

    public func distance(to other: Vec3) -> Double {
        (other - self).length
    }
}

/// A joint rotation as intrinsic Euler angles, in radians. Componentwise
/// interpolation is deliberate: authored exercise poses stay well inside
/// gimbal territory (the human-limits test enforces it), and componentwise
/// lerp keeps the math trivially portable and inspectable.
///
/// Sign conventions (right-handed, Y up, the mascot faces +Z):
/// - `pitch` rotates about X: positive tips an upward bone (the spine
///   chain) forward toward +Z, and swings a hanging bone (arms, legs at
///   rest) backward toward -Z.
/// - `yaw` rotates about Y (turning), `roll` about Z (side lean /
///   limb splay).
public struct EulerAngles: Equatable, Sendable {
    public var pitch: Double
    public var yaw: Double
    public var roll: Double

    public init(pitch: Double = 0, yaw: Double = 0, roll: Double = 0) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
    }

    public static let zero = EulerAngles()

    /// Authoring helper: degrees in, radians stored.
    public static func deg(pitch: Double = 0, yaw: Double = 0, roll: Double = 0) -> EulerAngles {
        EulerAngles(pitch: pitch * .pi / 180, yaw: yaw * .pi / 180, roll: roll * .pi / 180)
    }

    public func lerp(to other: EulerAngles, t: Double) -> EulerAngles {
        EulerAngles(
            pitch: pitch + t * (other.pitch - pitch),
            yaw: yaw + t * (other.yaw - yaw),
            roll: roll + t * (other.roll - roll)
        )
    }

    /// The largest absolute component, for continuity/limit tests.
    public var maxMagnitude: Double {
        max(abs(pitch), max(abs(yaw), abs(roll)))
    }
}

/// 3x3 rotation matrix for kit-side forward kinematics (tests and prop
/// math). THE ORDER CONTRACT: `R = Ry(yaw) * Rx(pitch) * Rz(roll)`,
/// intrinsic. The app's renderer composes its quaternions in exactly this
/// order; an app-side parity test pins the two implementations together —
/// change one without the other and that test fails before the mascot
/// folds inside-out on a device.
public struct Mat3: Sendable {
    // Row-major storage.
    public var m: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    public init(rows r0: Vec3, _ r1: Vec3, _ r2: Vec3) {
        m = (r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z)
    }

    public static let identity = Mat3(rows: Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1))

    public static func rotationX(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(rows: Vec3(1, 0, 0), Vec3(0, c, -s), Vec3(0, s, c))
    }

    public static func rotationY(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(rows: Vec3(c, 0, s), Vec3(0, 1, 0), Vec3(-s, 0, c))
    }

    public static func rotationZ(_ a: Double) -> Mat3 {
        let c = cos(a), s = sin(a)
        return Mat3(rows: Vec3(c, -s, 0), Vec3(s, c, 0), Vec3(0, 0, 1))
    }

    /// The order contract lives here: yaw, then pitch, then roll.
    public static func rotation(_ e: EulerAngles) -> Mat3 {
        rotationY(e.yaw) * rotationX(e.pitch) * rotationZ(e.roll)
    }

    public static func * (lhs: Mat3, rhs: Mat3) -> Mat3 {
        let a = lhs.m, b = rhs.m
        return Mat3(
            rows: Vec3(
                a.0 * b.0 + a.1 * b.3 + a.2 * b.6,
                a.0 * b.1 + a.1 * b.4 + a.2 * b.7,
                a.0 * b.2 + a.1 * b.5 + a.2 * b.8
            ),
            Vec3(
                a.3 * b.0 + a.4 * b.3 + a.5 * b.6,
                a.3 * b.1 + a.4 * b.4 + a.5 * b.7,
                a.3 * b.2 + a.4 * b.5 + a.5 * b.8
            ),
            Vec3(
                a.6 * b.0 + a.7 * b.3 + a.8 * b.6,
                a.6 * b.1 + a.7 * b.4 + a.8 * b.7,
                a.6 * b.2 + a.7 * b.5 + a.8 * b.8
            )
        )
    }

    public func rotate(_ v: Vec3) -> Vec3 {
        Vec3(
            m.0 * v.x + m.1 * v.y + m.2 * v.z,
            m.3 * v.x + m.4 * v.y + m.5 * v.z,
            m.6 * v.x + m.7 * v.y + m.8 * v.z
        )
    }
}

/// Closest distance between two line segments — the collision model's
/// primitive (capsule vs capsule = segment distance minus radii).
/// Handles degenerate segments (points) via clamped projection.
public func mascotSegmentDistance(_ a0: Vec3, _ a1: Vec3, _ b0: Vec3, _ b1: Vec3) -> Double {
    let d1 = a1 - a0
    let d2 = b1 - b0
    let r = a0 - b0
    let a = dot(d1, d1)
    let e = dot(d2, d2)
    let f = dot(d2, r)

    var s = 0.0
    var t = 0.0
    if a <= 1e-12 && e <= 1e-12 {
        // Both degenerate: point-point.
    } else if a <= 1e-12 {
        t = clamp01(f / e)
    } else {
        let c = dot(d1, r)
        if e <= 1e-12 {
            s = clamp01(-c / a)
        } else {
            let b = dot(d1, d2)
            let denominator = a * e - b * b
            if denominator > 1e-12 {
                s = clamp01((b * f - c * e) / denominator)
            }
            t = (b * s + f) / e
            if t < 0 {
                t = 0
                s = clamp01(-c / a)
            } else if t > 1 {
                t = 1
                s = clamp01((b - c) / a)
            }
        }
    }
    let closestA = a0 + s * d1
    let closestB = b0 + t * d2
    return closestA.distance(to: closestB)
}

private func dot(_ a: Vec3, _ b: Vec3) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
}

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

/// Hermite smoothstep, clamped. The face channel's effort-to-squint curve
/// uses it; kept public so tests can pin the curve's fixed points.
public func mascotSmoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
