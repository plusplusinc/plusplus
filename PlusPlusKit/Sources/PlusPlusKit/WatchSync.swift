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
        public var steps: [Step]

        public var id: String { name }

        public init(name: String, restSeconds: Int, steps: [Step]) {
            self.name = name
            self.restSeconds = restSeconds
            self.steps = steps
        }

        /// Whether this routine runs as an OUTDOOR workout on the wrist —
        /// an HKWorkoutSession is one activity type, so we only switch the
        /// watch config to running/outdoor (and collect GPS distance) when
        /// EVERY step is outdoor. A mixed routine stays strength/indoor.
        public var isOutdoorRun: Bool {
            !steps.isEmpty && steps.allSatisfy { $0.isOutdoor == true }
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
            isOutdoor: Bool? = nil
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

        public init(
            routineName: String,
            startedAt: Date,
            endedAt: Date,
            restSeconds: Int,
            steps: [StepResult],
            averageHeartRate: Int? = nil,
            maxHeartRate: Int? = nil
        ) {
            self.routineName = routineName
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.restSeconds = restSeconds
            self.steps = steps
            self.averageHeartRate = averageHeartRate
            self.maxHeartRate = maxHeartRate
        }
    }

    public struct StepResult: Codable, Equatable, Sendable {
        public var step: Step
        public var actualWeight: Double?
        public var actualReps: Int?
        public var actualDuration: Int?
        public var completedAt: Date?

        public init(step: Step, actualWeight: Double? = nil, actualReps: Int? = nil, actualDuration: Int? = nil, completedAt: Date? = nil) {
            self.step = step
            self.actualWeight = actualWeight
            self.actualReps = actualReps
            self.actualDuration = actualDuration
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
