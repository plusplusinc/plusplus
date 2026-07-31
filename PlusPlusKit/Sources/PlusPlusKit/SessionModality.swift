import Foundation

/// What KIND of workout a whole session is, resolved from the exercises in
/// it. One session gets one answer because an `HKWorkoutSession` carries
/// one activity type, and because the record has one line to name itself
/// with.
///
/// Platform-pure on purpose: the Kit must stay Linux-buildable, so the
/// HealthKit mapping lives on each platform and both read this. Before
/// this type the phone and the watch disagreed — `HealthRecorder` filed
/// anything with a GPS segment as an outdoor run, while
/// `PlanRoutine.isOutdoorRun` demanded that *every* step be outdoor, so
/// the same run-plus-core session recorded two different ways depending on
/// which device logged it.
public struct SessionModality: Equatable, Sendable {
    /// The family that best names the session. For a session mixing
    /// strength with cardio this is `.strength` with `isMixed` set; for
    /// one mixing several cardio families it is `.cardio` with `isMixed`
    /// set. Platforms read the pair together.
    public let primary: ExerciseModality
    /// More than one family is present, so `primary` is a summary rather
    /// than a description. Health maps this to cross-training or mixed
    /// cardio rather than pretending the session was all one thing.
    public let isMixed: Bool
    /// Every cardio leg is GPS-trackable. Strength legs do not vote —
    /// there is no such thing as an outdoor bench press in this model.
    public let isOutdoor: Bool

    public init(primary: ExerciseModality, isMixed: Bool, isOutdoor: Bool) {
        self.primary = primary
        self.isMixed = isMixed
        self.isOutdoor = isOutdoor
    }

    /// One leg of a session, as either device can describe it.
    public struct Leg: Equatable, Sendable {
        public let modality: ExerciseModality
        public let isOutdoor: Bool

        public init(modality: ExerciseModality, isOutdoor: Bool) {
            self.modality = modality
            self.isOutdoor = isOutdoor
        }
    }

    /// An empty session is strength/indoor — the same thing the app filed
    /// before any of this existed, so a session with no resolvable
    /// exercises behaves exactly as it used to.
    public static let empty = SessionModality(primary: .strength, isMixed: false, isOutdoor: false)

    public static func resolve(_ legs: [Leg]) -> SessionModality {
        guard !legs.isEmpty else { return .empty }

        // Mobility work never renames a session: a hamstring stretch at
        // the end of a lifting day does not make it a mobility workout,
        // and on its own it files as strength, which is what it did before.
        let nonFlexibility = legs.filter { $0.modality != .flexibility }
        let considered = nonFlexibility.isEmpty ? legs : nonFlexibility

        let cardio = considered.filter { $0.modality.isCardio }
        let hasStrength = considered.contains { !$0.modality.isCardio }
        let families = Set(cardio.map(\.modality))

        // Outdoor is a property of the cardio in the session. No cardio,
        // nothing to be outdoors for.
        let outdoor = !cardio.isEmpty && cardio.allSatisfy(\.isOutdoor)

        if cardio.isEmpty {
            return SessionModality(primary: .strength, isMixed: false, isOutdoor: false)
        }
        if hasStrength {
            // Strength plus cardio is genuinely neither; the platform
            // files it as cross-training.
            return SessionModality(primary: .strength, isMixed: true, isOutdoor: outdoor)
        }
        if families.count == 1, let only = families.first {
            return SessionModality(primary: only, isMixed: false, isOutdoor: outdoor)
        }
        // Several cardio families and nothing else — a brick, or a circuit
        // of machines.
        return SessionModality(primary: .cardio, isMixed: true, isOutdoor: outdoor)
    }
}
