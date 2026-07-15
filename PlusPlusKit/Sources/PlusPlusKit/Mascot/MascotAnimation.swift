import Foundation

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

/// A short form cue and the rep-relative window (0...1 within a single
/// rep, or within the hold) where it applies. The demo sheet highlights
/// the active cue in notes amber while the motion passes through it.
public struct MascotCue: Equatable, Sendable {
    public var text: String
    public var window: ClosedRange<Double>

    public init(_ text: String, window: ClosedRange<Double>) {
        self.text = text
        self.window = window
    }
}

/// Equipment the renderer attaches to the rig. Placement is derived from
/// the wrists app-side (a barbell spans both, dumbbells parent one per
/// hand), so the kit only declares WHICH props a move carries.
public enum MascotProp: String, CaseIterable, Sendable {
    case barbell
    case dumbbellPair
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

    public init(
        exerciseName: String,
        style: Style,
        repsPerDemoSet: Int,
        repKeyframes: [MascotKeyframe],
        restBeat: RestBeat,
        cues: [MascotCue],
        props: [MascotProp] = [],
        blinkPhases: [Double],
        restingPhase: Double = 0
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
        switch segment(at: t) {
        case .rep(_, let phase): return Self.sample(repKeyframes, at: phase)
        case .rest(let phase): return Self.sample(restBeat.keyframes, at: phase)
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

    /// Indices into `cues` active at a set phase. Cue windows are
    /// rep-relative, so a cue lights up on EVERY rep as the motion passes
    /// through it; nothing is active during the tired beat.
    public func activeCueIndices(at t: Double) -> [Int] {
        guard case .rep(_, let phase) = segment(at: t) else { return [] }
        return cues.indices.filter { cues[$0].window.contains(phase) }
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
