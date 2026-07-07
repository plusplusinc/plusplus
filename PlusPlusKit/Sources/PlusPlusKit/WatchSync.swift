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
    }

    /// One set of one exercise, in execution order (supersets already
    /// rotated). Targets mirror SetLog's.
    public struct Step: Codable, Equatable, Sendable {
        public var exerciseName: String
        public var groupIndex: Int
        public var setNumber: Int
        public var isDuration: Bool
        public var targetWeight: Double?
        public var targetRepsLower: Int?
        public var targetRepsUpper: Int?
        public var targetDuration: Int?

        public init(
            exerciseName: String,
            groupIndex: Int,
            setNumber: Int,
            isDuration: Bool,
            targetWeight: Double? = nil,
            targetRepsLower: Int? = nil,
            targetRepsUpper: Int? = nil,
            targetDuration: Int? = nil
        ) {
            self.exerciseName = exerciseName
            self.groupIndex = groupIndex
            self.setNumber = setNumber
            self.isDuration = isDuration
            self.targetWeight = targetWeight
            self.targetRepsLower = targetRepsLower
            self.targetRepsUpper = targetRepsUpper
            self.targetDuration = targetDuration
        }
    }

    public struct SessionResult: Codable, Equatable, Sendable {
        public var routineName: String
        public var startedAt: Date
        public var endedAt: Date
        public var restSeconds: Int
        public var steps: [StepResult]

        public init(routineName: String, startedAt: Date, endedAt: Date, restSeconds: Int, steps: [StepResult]) {
            self.routineName = routineName
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.restSeconds = restSeconds
            self.steps = steps
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
