import Foundation

/// How an animation's keyframes are sampled. `.eased` is the plain
/// per-keyframe easing chain; `.curved` is a C1 cubic (Catmull-Rom
/// tangents, non-uniform knots) over the whole pose vector — every
/// authored move uses it, because chained ease-in-outs stop dead at
/// every keyframe and read as robotic stutter (build-80 device
/// feedback: "the motion is a bit jerky").
public enum MascotSmoothing: Equatable, Sendable {
    case eased
    case curved
}

/// Easing INTO the next keyframe.
public enum MascotEasing: Equatable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// Stay on this keyframe's pose until the next one. Only meaningful
    /// between identical poses (a deliberate pause); between different
    /// poses it would teleport, which the continuity test rejects.
    case hold

    public func apply(_ u: Double) -> Double {
        let t = min(max(u, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        case .hold: return 0
        }
    }
}

public struct MascotKeyframe: Sendable {
    /// Normalized 0...1 within the segment (one rep, or the rest beat)
    /// that owns this keyframe.
    public var t: Double
    public var pose: MascotPose
    public var easing: MascotEasing

    public init(t: Double, pose: MascotPose, easing: MascotEasing = .easeInOut) {
        self.t = t
        self.pose = pose
        self.easing = easing
    }
}

/// A short form cue. A cue with a `window` (rep-relative, 0...1) is
/// SYNCED: the demo sheet highlights it in notes amber while the motion
/// passes through it. A cue without one is STATIC: always listed, never
/// flashing. Most cues should be static — a handful of fast-cycling
/// highlights is unreadable (build-81 feedback); each move carries at
/// most two synced cues, enforced by test.
public struct MascotCue: Equatable, Sendable {
    public var text: String
    public var window: ClosedRange<Double>?

    public init(_ text: String, window: ClosedRange<Double>? = nil) {
        self.text = text
        self.window = window
    }
}

/// Equipment the renderer attaches to the rig. Held props derive their
/// placement from the wrists app-side (a barbell spans both, dumbbells
/// parent one per hand); SUPPORT props are world-fixed furniture whose
/// geometry lives in `MascotSupport` — the kit only declares WHICH
/// props a move carries.
public enum MascotProp: String, CaseIterable, Sendable {
    case barbell
    case dumbbellPair
    /// A flat bench (the support class's first member): the bot lies ON
    /// it, so its pad joins the collision sweep and the bench-contact
    /// invariant proves the five points of contact.
    case flatBench
}

/// The physical context a move declares beyond its pose stream — the
/// hooks the physics invariants key off. The default describes the
/// common case: grounded from start to finish. Built for the dynamic
/// end of the catalog (Dave's rule: the mascot can do ALL human
/// movements, and jumps, swings, and throws obey gravity and inertia
/// like everything else): a move that leaves the ground declares WHERE,
/// and the invariants swap their demand — ground contact everywhere
/// else, a free-fall center-of-mass parabola inside the window.
public struct MascotDynamics: Equatable, Sendable {
    /// REP-relative phase windows (matching cue windows) where the
    /// mascot is deliberately airborne — jump squats, burpee hops. The
    /// something-touches-the-ground invariant skips them; the ballistic
    /// invariant takes over inside them.
    public var airborneWindows: [ClosedRange<Double>]
    /// The hands carry body weight FLAT on the floor (push-up): the
    /// hand is the planted flat palm — fingers extended forward, palm
    /// contact pads expected AT the ground.
    public var handsBearWeight: Bool
    /// The FOREARMS carry the weight (forearm plank): the elbows and
    /// forearms rest on the floor and the hands ride as relaxed
    /// NEUTRAL FISTS — thumb side up, pinky edge near the ground. The
    /// anatomically honest floor hand for an elbow-supported move:
    /// palm-down there would demand more pronation than a horizontal
    /// forearm has (the hand round's census proved it unreachable).
    public var forearmsBearWeight: Bool

    public init(
        airborneWindows: [ClosedRange<Double>] = [],
        handsBearWeight: Bool = false,
        forearmsBearWeight: Bool = false
    ) {
        self.airborneWindows = airborneWindows
        self.handsBearWeight = handsBearWeight
        self.forearmsBearWeight = forearmsBearWeight
    }

    /// Grounded throughout — every non-jumping move.
    public static let grounded = MascotDynamics()
}

/// What the face is doing at an instant: blink, effort squint, and the
/// end-of-set tiredness already composited. Deterministic by
/// construction — a pure function of the set phase, no clocks, no random.
public struct MascotFace: Equatable, Sendable {
    /// 1 = the "+" eye fully open; 0 = the vertical stroke collapsed
    /// into a "-".
    public var eyeOpenness: Double
    /// 0...1; the renderer adds the droopy eye tilt from this.
    public var tiredness: Double

    public init(eyeOpenness: Double, tiredness: Double) {
        self.eyeOpenness = eyeOpenness
        self.tiredness = tiredness
    }
}

/// One exercise's demo: a SET, not a bare rep loop. `repsPerDemoSet`
/// reps (or a single timed hold) followed by an authored "set complete"
/// beat — shoulders slump, eyes droop, a slow breath — then the cycle
/// restarts. The whole timeline is a pure function of a 0...1 set phase,
/// so the renderer owns a clock and nothing else.
public struct ExerciseAnimation: Sendable {
    public enum Style: Equatable, Sendable {
        case reps(repDuration: TimeInterval)
        case hold(duration: TimeInterval)
    }

    /// The tired beat. Its keyframes must start and end on the rep
    /// loop's shared endpoint pose so the seams are continuous.
    public struct RestBeat: Sendable {
        public var duration: TimeInterval
        public var keyframes: [MascotKeyframe]

        public init(duration: TimeInterval, keyframes: [MascotKeyframe]) {
            self.duration = duration
            self.keyframes = keyframes
        }
    }

    /// The EXACT built-in exercise name (exercise identity IS the name —
    /// docs/PLATFORM.md); `MascotMoves` keys the catalog on it.
    public var exerciseName: String
    public var style: Style
    public var repsPerDemoSet: Int
    /// One rep (or the single hold), t 0...1, first pose == last pose.
    public var repKeyframes: [MascotKeyframe]
    public var restBeat: RestBeat
    public var cues: [MascotCue]
    public var props: [MascotProp]
    /// Blink centers as SET-relative phases. Authored (or defaulted by
    /// `MascotPoseBuilder.defaultBlinkPhases`) away from high-effort
    /// moments — the tests enforce it.
    public var blinkPhases: [Double]
    /// Rep-relative phase whose pose stands in for the whole animation
    /// when motion is frozen (Reduce Motion, UI test): pick the most
    /// characteristic moment, e.g. a squat at depth.
    public var restingPhase: Double
    public var smoothing: MascotSmoothing
    public var dynamics: MascotDynamics

    public init(
        exerciseName: String,
        style: Style,
        repsPerDemoSet: Int,
        repKeyframes: [MascotKeyframe],
        restBeat: RestBeat,
        cues: [MascotCue],
        props: [MascotProp] = [],
        blinkPhases: [Double],
        restingPhase: Double = 0,
        smoothing: MascotSmoothing = .eased,
        dynamics: MascotDynamics = .grounded
    ) {
        self.exerciseName = exerciseName
        self.style = style
        self.repsPerDemoSet = repsPerDemoSet
        self.repKeyframes = repKeyframes
        self.restBeat = restBeat
        self.cues = cues
        self.props = props
        self.blinkPhases = blinkPhases
        self.restingPhase = restingPhase
        self.smoothing = smoothing
        self.dynamics = dynamics
    }

    // MARK: - Timeline

    public var repDuration: TimeInterval {
        switch style {
        case .reps(let repDuration): return repDuration
        case .hold(let duration): return duration
        }
    }

    public var workDuration: TimeInterval { Double(repsPerDemoSet) * repDuration }
    public var cycleDuration: TimeInterval { workDuration + restBeat.duration }

    public enum Segment: Equatable, Sendable {
        case rep(index: Int, phase: Double)
        case rest(phase: Double)
    }

    /// Maps a set-relative phase (any real; wraps into 0..<1) onto the
    /// rep-or-rest timeline.
    public func segment(at t: Double) -> Segment {
        let wrapped = t - t.rounded(.down)
        let workShare = workDuration / cycleDuration
        if wrapped < workShare {
            let repFloat = wrapped / workShare * Double(repsPerDemoSet)
            let index = min(Int(repFloat), repsPerDemoSet - 1)
            return .rep(index: index, phase: repFloat - Double(index))
        }
        let restShare = 1 - workShare
        guard restShare > 0 else { return .rep(index: repsPerDemoSet - 1, phase: 1) }
        return .rest(phase: (wrapped - workShare) / restShare)
    }

    public func pose(at t: Double) -> MascotPose {
        let keyframes: [MascotKeyframe]
        let phase: Double
        switch segment(at: t) {
        case .rep(_, let p):
            keyframes = repKeyframes
            phase = p
        case .rest(let p):
            keyframes = restBeat.keyframes
            phase = p
        }
        switch smoothing {
        case .eased: return Self.sample(keyframes, at: phase)
        case .curved: return Self.sampleCurved(keyframes, at: phase)
        }
    }

    /// Keyframe sampling with per-keyframe easing. Assumes what the
    /// invariant tests enforce: non-empty, sorted, t spanning 0...1.
    public static func sample(_ keyframes: [MascotKeyframe], at phase: Double) -> MascotPose {
        guard let first = keyframes.first else { return MascotPose() }
        let p = min(max(phase, 0), 1)
        guard keyframes.count > 1 else { return first.pose }
        var lower = first
        for upper in keyframes.dropFirst() {
            // Strictly below: exactly AT a keyframe, that keyframe wins
            // (matters for .hold, whose curve never reaches 1).
            if p < upper.t {
                let span = upper.t - lower.t
                guard span > 0 else { return upper.pose }
                let eased = lower.easing.apply((p - lower.t) / span)
                return lower.pose.lerp(to: upper.pose, t: eased)
            }
            lower = upper
        }
        return keyframes[keyframes.count - 1].pose
    }

    /// C1 sampling: cubic Hermite with Catmull-Rom tangents over
    /// non-uniform knots. A knot adjacent to a STILL segment (the body
    /// doesn't move across it — a pause at depth, the settle at the
    /// top) gets a ZERO tangent, so motion eases naturally into and out
    /// of pauses instead of S-wiggling between duplicate poses.
    /// Per-keyframe easing is ignored here — the spline IS the easing.
    public static func sampleCurved(_ keyframes: [MascotKeyframe], at phase: Double) -> MascotPose {
        guard let first = keyframes.first else { return MascotPose() }
        guard keyframes.count > 1 else { return first.pose }
        let p = min(max(phase, 0), 1)

        var index = keyframes.count - 2
        for i in 0..<(keyframes.count - 1) where p < keyframes[i + 1].t {
            index = i
            break
        }
        let k0 = keyframes[index]
        let k1 = keyframes[index + 1]
        let dt = k1.t - k0.t
        guard dt > 0 else { return k1.pose }

        // NOTE: stillness relies on pause keyframes being EXACT value
        // copies of one pose (all five moves author pauses that way).
        // A pause whose endpoints come from two separate solver runs
        // (near-equal, not equal) would silently lose its
        // ease-into-pause — author pauses by reusing the pose value.
        func still(_ a: Int, _ b: Int) -> Bool {
            keyframes[a].pose.maxBodyDelta(to: keyframes[b].pose) < 1e-9
        }
        func tangent(at j: Int) -> MascotPose {
            let before = max(j - 1, 0)
            let after = min(j + 1, keyframes.count - 1)
            if before == after { return MascotPose() }
            // A still neighbor segment pins the velocity to zero.
            if (j > 0 && still(j - 1, j)) || (j < keyframes.count - 1 && still(j, j + 1)) {
                return MascotPose()
            }
            let span = keyframes[after].t - keyframes[before].t
            guard span > 0 else { return MascotPose() }
            return MascotPose.weightedSum([
                (keyframes[after].pose, 1 / span),
                (keyframes[before].pose, -1 / span),
            ])
        }

        let m0 = tangent(at: index)
        let m1 = tangent(at: index + 1)
        let u = (p - k0.t) / dt
        let u2 = u * u
        let u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1
        let h10 = u3 - 2 * u2 + u
        let h01 = -2 * u3 + 3 * u2
        let h11 = u3 - u2
        return MascotPose.weightedSum([
            (k0.pose, h00),
            (m0, h10 * dt),
            (k1.pose, h01),
            (m1, h11 * dt),
        ])
    }

    // MARK: - Face channel

    /// Tiredness is a smooth bump across the rest beat: eases in over its
    /// first quarter, holds, releases over the last quarter — so eye
    /// openness is continuous into the next set.
    public func tiredness(at t: Double) -> Double {
        guard case .rest(let phase) = segment(at: t) else { return 0 }
        return mascotSmoothstep(0, 0.25, phase) * (1 - mascotSmoothstep(0.75, 1, phase))
    }

    public func face(at t: Double) -> MascotFace {
        let effort = pose(at: t).effort
        let squint = 1 - 0.7 * mascotSmoothstep(0.5, 1.0, effort)
        let tired = tiredness(at: t)
        let tiredCap = 1 - 0.5 * tired
        let openness = min(squint, tiredCap) * blinkFactor(at: t, tiredness: tired)
        return MascotFace(eyeOpenness: min(max(openness, 0), 1), tiredness: tired)
    }

    /// A cosine bump at each blink center: 1 outside, dipping to 0.1 at
    /// the center. Tired blinks run slower (wider). Distances wrap
    /// around the loop seam.
    private func blinkFactor(at t: Double, tiredness: Double) -> Double {
        let wrapped = t - t.rounded(.down)
        let baseBlinkSeconds = 0.18
        let width = baseBlinkSeconds / cycleDuration * (1 + tiredness)
        guard width > 0 else { return 1 }
        var factor = 1.0
        for center in blinkPhases {
            let raw = abs(wrapped - center)
            let distance = min(raw, 1 - raw)
            if distance < width / 2 {
                let bump = 0.5 + 0.5 * cos(2 * .pi * distance / width)
                factor = min(factor, 1 - 0.9 * bump)
            }
        }
        return factor
    }

    // MARK: - Cues and frozen-mode support

    /// Indices into `cues` active at a set phase — SYNCED cues only
    /// (static cues are always shown, never highlighted). Windows are
    /// rep-relative, so a synced cue lights up on EVERY rep as the
    /// motion passes through it; nothing is active during the tired
    /// beat.
    public func activeCueIndices(at t: Double) -> [Int] {
        guard case .rep(_, let phase) = segment(at: t) else { return [] }
        return cues.indices.filter { cues[$0].window?.contains(phase) ?? false }
    }

    /// Whether the mascot is deliberately airborne at a SET-relative
    /// phase — true only inside a rep, within one of the declared
    /// airborne windows. The tired beat is always grounded.
    public func isAirborne(at t: Double) -> Bool {
        guard case .rep(_, let phase) = segment(at: t) else { return false }
        return dynamics.airborneWindows.contains { $0.contains(phase) }
    }

    /// The static stand-in when motion is frozen (Reduce Motion,
    /// --uitest-reset). Eyes render open; the renderer skips face().
    public var restingPose: MascotPose {
        Self.sample(repKeyframes, at: restingPhase)
    }

    /// Set-relative phases for the Reduce-Motion step-through: one stop
    /// per rep keyframe within the first rep. The final keyframe is
    /// dropped — its pose is the first one again (loop continuity). A
    /// hold's dense sampled keyframes collapse to five evenly spaced
    /// stops instead.
    public var stepPhases: [Double] {
        let repShare = repDuration / cycleDuration
        if case .hold = style {
            return [0, 0.2, 0.4, 0.6, 0.8].map { $0 * repShare }
        }
        let raw = repKeyframes.dropLast().map(\.t)
        // Baked span paths carry many mechanical keyframes; the
        // step-through wants a handful of stops, so dense reps
        // downsample to six even steps.
        guard raw.count > 8 else { return raw.map { $0 * repShare } }
        return (0..<6).map { Double($0) / 6 * repShare }
    }
}
