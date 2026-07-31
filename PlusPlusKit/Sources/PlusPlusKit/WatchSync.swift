import Foundation

/// The WatchConnectivity payloads (#6): the phone pushes a Plan (every
/// routine pre-expanded into execution order, exactly the rotation the
/// phone's session factory produces) via updateApplicationContext; the
/// watch sends a SessionResult back via transferUserInfo when a wrist
/// session finishes. Pure Codable values — no SwiftData on the wrist,
/// per the #6 plan. Encoding is ISO 8601 JSON so payloads stay
/// inspectable and platform-stable.
public enum WatchSync {
    public struct Plan: Codable, Equatable, Sendable {
        public var generatedAt: Date
        public var routines: [PlanRoutine]

        public init(generatedAt: Date, routines: [PlanRoutine]) {
            self.generatedAt = generatedAt
            self.routines = routines
        }
    }

    public struct PlanRoutine: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var restSeconds: Int
        /// Pause when the next step is a different exercise or block
        /// (#369); rest covers a new round of the same block. Additive
        /// optional — a plan from a pre-transition phone decodes nil and
        /// the wrist rests everywhere, exactly as before.
        public var transitionSeconds: Int?
        public var steps: [Step]
        /// The routine's stable cross-device identity (#511) — what
        /// session adoption keys on; names are not unique. Additive
        /// optional: a plan from an older phone decodes nil and adoption
        /// falls back to the name, exactly as before.
        public var uuid: UUID?
        /// A synthesized one-step scratch plan for a quick-start sport
        /// (#513) — the wrist renders these under their own section, and
        /// they are not routines the user authored. Additive optional:
        /// an older watch renders them as plain rows, which still work.
        public var isQuickStart: Bool?

        public var id: String { name }

        public init(name: String, restSeconds: Int, transitionSeconds: Int? = nil, steps: [Step], uuid: UUID? = nil, isQuickStart: Bool? = nil) {
            self.name = name
            self.restSeconds = restSeconds
            self.transitionSeconds = transitionSeconds
            self.steps = steps
            self.uuid = uuid
            self.isQuickStart = isQuickStart
        }

        /// Whether this routine runs as an OUTDOOR workout on the wrist —
        /// an HKWorkoutSession is one activity type, so we only switch the
        /// watch config to running/outdoor (and collect GPS distance) when
        /// EVERY step is outdoor. A mixed routine stays strength/indoor.
        ///
        /// ⚠️ Superseded by `sessionModality` for anything that files a
        /// workout: this reads a step's location without asking what SPORT
        /// it is, so it can only ever answer "outdoor run or not". Kept
        /// because a plan pushed by a phone older than the modality field
        /// still decodes into it, and that plan has nothing else to go on.
        public var isOutdoorRun: Bool {
            !steps.isEmpty && steps.allSatisfy { $0.isOutdoor == true }
        }

        /// What kind of workout this plan is, for the wrist's
        /// `HKWorkoutSession` configuration and its work-unit vocabulary.
        ///
        /// Falls back to the legacy outdoor-run read when no step carries a
        /// modality — a stale phone build pushes plans without one, and
        /// guessing `.strength` for a run would be worse than the old
        /// answer.
        public var sessionModality: SessionModality {
            let known = steps.compactMap { step -> SessionModality.Leg? in
                guard let modality = step.modality else { return nil }
                return SessionModality.Leg(modality: modality, isOutdoor: step.isOutdoor == true)
            }
            guard known.count == steps.count, !steps.isEmpty else {
                return isOutdoorRun
                    ? SessionModality(primary: .running, isMixed: false, isOutdoor: true)
                    : .empty
            }
            return SessionModality.resolve(known)
        }
    }

    /// One set of one exercise, in execution order (supersets already
    /// rotated). Targets mirror SetLog's. Heart-rate targets arrive
    /// RESOLVED to bpm bounds — the phone knows the user's max HR (date
    /// of birth lives in its Health store); the wrist just compares.
    /// Every post-v1 field rides an additive optional, so a stale watch
    /// build ignores them and a stale phone plan reads as nil.
    public struct Step: Codable, Equatable, Sendable {
        public var exerciseName: String
        public var groupIndex: Int
        public var setNumber: Int
        public var isDuration: Bool
        public var targetWeight: Double?
        public var targetRepsLower: Int?
        public var targetRepsUpper: Int?
        public var targetDuration: Int?
        public var targetHeartRateLowerBPM: Int?
        public var targetHeartRateUpperBPM: Int?
        /// Targets beyond the dedicated fields, keyed by metric raw value
        /// (flexible metrics). Includes what the wrist needs to DISPLAY
        /// ("2000 m · lvl 5"); logging extras stays a phone affordance.
        public var extraTargets: [String: Double]?
        /// The exercise's distance/pace denomination, for display.
        public var distanceUnit: DistanceUnit?
        /// The block's rest override (interval blocks) — the wrist rests
        /// this long after the step instead of the routine default.
        public var restSecondsOverride: Int?
        /// Whether this step is an outdoor, GPS-trackable run/walk — the
        /// wrist reads it to decide the workout's activity/location type
        /// and whether to show live pace (see `PlanRoutine.isOutdoorRun`).
        public var isOutdoor: Bool?
        /// The movement family this step belongs to, so the wrist can file
        /// the workout under the right Health activity type and count in
        /// the right noun (pieces on an erg, reps on the track). Additive
        /// optional: a plan from a phone that predates it decodes nil and
        /// the wrist falls back to `isOutdoorRun`, exactly as before.
        public var modality: ExerciseModality?

        public init(
            exerciseName: String,
            groupIndex: Int,
            setNumber: Int,
            isDuration: Bool,
            targetWeight: Double? = nil,
            targetRepsLower: Int? = nil,
            targetRepsUpper: Int? = nil,
            targetDuration: Int? = nil,
            targetHeartRateLowerBPM: Int? = nil,
            targetHeartRateUpperBPM: Int? = nil,
            extraTargets: [String: Double]? = nil,
            distanceUnit: DistanceUnit? = nil,
            restSecondsOverride: Int? = nil,
            isOutdoor: Bool? = nil,
            modality: ExerciseModality? = nil
        ) {
            self.exerciseName = exerciseName
            self.groupIndex = groupIndex
            self.setNumber = setNumber
            self.isDuration = isDuration
            self.targetWeight = targetWeight
            self.targetRepsLower = targetRepsLower
            self.targetRepsUpper = targetRepsUpper
            self.targetDuration = targetDuration
            self.targetHeartRateLowerBPM = targetHeartRateLowerBPM
            self.targetHeartRateUpperBPM = targetHeartRateUpperBPM
            self.extraTargets = extraTargets
            self.distanceUnit = distanceUnit
            self.restSecondsOverride = restSecondsOverride
            self.isOutdoor = isOutdoor
            self.modality = modality
        }

        /// The noun this step's work is counted in — "piece" on an erg,
        /// "rep" on the track. nil for a walk, and for a plan pushed
        /// before modalities existed (the wrist then says nothing rather
        /// than guessing).
        public var workUnit: WorkUnit? {
            modality?.workUnit
        }
    }

    public struct SessionResult: Codable, Equatable, Sendable {
        public var routineName: String
        public var startedAt: Date
        public var endedAt: Date
        public var restSeconds: Int
        public var steps: [StepResult]
        /// Session heart-rate summary from the wrist's live workout
        /// builder. Additive optionals: results from older watch builds
        /// (or runs where Health was declined) decode with nil.
        public var averageHeartRate: Int?
        public var maxHeartRate: Int?
        /// The live session's shared identity (#511) — the same id the
        /// mirror ops carried, so the phone's import can key on it
        /// instead of the (name, startedAt) heuristic. Additive optional:
        /// a result from an older watch decodes nil and the import falls
        /// back to the heuristic.
        public var sessionId: UUID?

        public init(
            routineName: String,
            startedAt: Date,
            endedAt: Date,
            restSeconds: Int,
            steps: [StepResult],
            averageHeartRate: Int? = nil,
            maxHeartRate: Int? = nil,
            sessionId: UUID? = nil
        ) {
            self.routineName = routineName
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.restSeconds = restSeconds
            self.steps = steps
            self.averageHeartRate = averageHeartRate
            self.maxHeartRate = maxHeartRate
            self.sessionId = sessionId
        }
    }

    public struct StepResult: Codable, Equatable, Sendable {
        public var step: Step
        public var actualWeight: Double?
        public var actualReps: Int?
        public var actualDuration: Int?
        /// What actually happened beyond the three columns — the measured
        /// distance and split of a piece, the damper it was pulled at.
        /// Keyed by metric raw value, like every other extras bag.
        ///
        /// Additive optional: results from a watch build that predates it
        /// decode nil, and the phone then records only the three columns,
        /// exactly as before. ⚠️ Composed through `LoggedActuals.extras`,
        /// never by copying the step's targets — see that type for why.
        public var extraActuals: [String: Double]?
        /// What the heart did during THIS step. The wrist is the device
        /// wearing the sensor, so it is the one that actually knows, and
        /// sending it means a watch-logged set carries the same fact a
        /// phone-logged one does. Additive optionals, like `extraActuals`.
        public var averageHeartRate: Int?
        public var maxHeartRate: Int?
        public var completedAt: Date?

        public init(
            step: Step,
            actualWeight: Double? = nil,
            actualReps: Int? = nil,
            actualDuration: Int? = nil,
            extraActuals: [String: Double]? = nil,
            averageHeartRate: Int? = nil,
            maxHeartRate: Int? = nil,
            completedAt: Date? = nil
        ) {
            self.step = step
            self.actualWeight = actualWeight
            self.actualReps = actualReps
            self.actualDuration = actualDuration
            self.extraActuals = extraActuals
            self.averageHeartRate = averageHeartRate
            self.maxHeartRate = maxHeartRate
            self.completedAt = completedAt
        }
    }

    // MARK: - Codec

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode<Payload: Encodable>(_ payload: Payload) throws -> Data {
        try encoder.encode(payload)
    }

    public static func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        try decoder.decode(type, from: data)
    }
}
