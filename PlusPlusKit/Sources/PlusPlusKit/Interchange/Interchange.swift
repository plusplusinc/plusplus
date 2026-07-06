import Foundation

/// Interchange schema v1 — the documented JSON contract shared by the app's
/// export/import, the GitHub repo sync, the CLI, and agent tooling. See
/// docs/PLATFORM.md in the main repo. Exercises are referenced by name
/// (unique within a library); sessions snapshot everything so history files
/// stand alone.
public enum Interchange {
    public static let schemaVersion = 1
}

public struct ExerciseDTO: Codable, Equatable, Sendable {
    public var name: String
    public var muscleGroup: MuscleGroup
    public var exerciseType: ExerciseType
    /// Equipment names, sorted for deterministic output.
    public var equipment: [String]
    public var notes: String?
    public var videoURL: String?
    public var isBuiltIn: Bool

    public init(
        name: String,
        muscleGroup: MuscleGroup,
        exerciseType: ExerciseType,
        equipment: [String],
        notes: String? = nil,
        videoURL: String? = nil,
        isBuiltIn: Bool = false
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.exerciseType = exerciseType
        self.equipment = equipment.sorted()
        self.notes = notes
        self.videoURL = videoURL
        self.isBuiltIn = isBuiltIn
    }
}

public struct WorkoutDTO: Codable, Equatable, Sendable {
    public var name: String
    public var restSeconds: Int
    public var notes: String?
    public var groups: [GroupDTO]

    public init(name: String, restSeconds: Int, notes: String? = nil, groups: [GroupDTO]) {
        self.name = name
        self.restSeconds = restSeconds
        self.notes = notes
        self.groups = groups
    }

    /// A group with more than one exercise is a superset.
    public struct GroupDTO: Codable, Equatable, Sendable {
        public var sets: Int
        public var exercises: [EntryDTO]

        public init(sets: Int, exercises: [EntryDTO]) {
            self.sets = sets
            self.exercises = exercises
        }
    }

    public struct EntryDTO: Codable, Equatable, Sendable {
        /// Exercise name reference.
        public var exercise: String
        public var weight: Double?
        public var reps: Int?
        public var repsUpper: Int?
        public var durationSeconds: Int?

        public init(
            exercise: String,
            weight: Double? = nil,
            reps: Int? = nil,
            repsUpper: Int? = nil,
            durationSeconds: Int? = nil
        ) {
            self.exercise = exercise
            self.weight = weight
            self.reps = reps
            self.repsUpper = repsUpper
            self.durationSeconds = durationSeconds
        }
    }
}

public struct SessionDTO: Codable, Equatable, Sendable {
    public var workoutName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var restSeconds: Int
    public var sets: [SetDTO]

    public init(
        workoutName: String,
        startedAt: Date,
        endedAt: Date?,
        restSeconds: Int,
        sets: [SetDTO]
    ) {
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.restSeconds = restSeconds
        self.sets = sets
    }

    public struct SetDTO: Codable, Equatable, Sendable {
        public var order: Int
        public var groupIndex: Int
        public var setNumber: Int
        public var exerciseName: String
        public var exerciseType: ExerciseType
        public var targetWeight: Double?
        public var targetRepsLower: Int?
        public var targetRepsUpper: Int?
        public var targetDuration: Int?
        public var actualWeight: Double?
        public var actualReps: Int?
        public var actualDuration: Int?
        public var completedAt: Date?

        public init(
            order: Int,
            groupIndex: Int,
            setNumber: Int,
            exerciseName: String,
            exerciseType: ExerciseType,
            targetWeight: Double? = nil,
            targetRepsLower: Int? = nil,
            targetRepsUpper: Int? = nil,
            targetDuration: Int? = nil,
            actualWeight: Double? = nil,
            actualReps: Int? = nil,
            actualDuration: Int? = nil,
            completedAt: Date? = nil
        ) {
            self.order = order
            self.groupIndex = groupIndex
            self.setNumber = setNumber
            self.exerciseName = exerciseName
            self.exerciseType = exerciseType
            self.targetWeight = targetWeight
            self.targetRepsLower = targetRepsLower
            self.targetRepsUpper = targetRepsUpper
            self.targetDuration = targetDuration
            self.actualWeight = actualWeight
            self.actualReps = actualReps
            self.actualDuration = actualDuration
            self.completedAt = completedAt
        }
    }
}

/// The app's single-file export: the whole library plus history. The repo
/// layout stores the same DTOs one entity per file instead.
public struct ExportBundle: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exercises: [ExerciseDTO]
    public var workouts: [WorkoutDTO]
    public var sessions: [SessionDTO]

    public init(
        exercises: [ExerciseDTO],
        workouts: [WorkoutDTO],
        sessions: [SessionDTO]
    ) {
        self.schemaVersion = Interchange.schemaVersion
        // Plain lowercased comparison, not localized — output ordering must be
        // identical on every platform for deterministic diffs.
        self.exercises = exercises.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.workouts = workouts.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.sessions = sessions.sorted { $0.startedAt < $1.startedAt }
    }
}
