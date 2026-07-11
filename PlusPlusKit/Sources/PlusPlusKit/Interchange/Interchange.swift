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
    /// Default targets (#187) — what a fresh routine entry starts from.
    /// All optional and additive: absent fields keep schema v1 bundles
    /// byte-identical, and older readers ignore them.
    public var defaultWeight: Double?
    public var defaultReps: Int?
    public var defaultRepsUpper: Int?
    public var defaultDurationSeconds: Int?
    /// Tracked-metric profile (flexible metrics): metric identifiers from
    /// the curated vocabulary, sorted for deterministic output. Absent
    /// means the legacy profile `exerciseType` implies (weightReps →
    /// weight+reps, duration → duration), so every existing file keeps
    /// its exact meaning. `exerciseType` stays authoritative for old
    /// readers; writers keep the two consistent.
    public var metrics: [String]?
    /// What this exercise's distance/pace/speed numbers are denominated
    /// in. Absent means meters. Never converts values — a declaration,
    /// like the bundle's `units`.
    public var distanceUnit: DistanceUnit?
    /// Default targets for metrics beyond the three dedicated fields
    /// above, keyed by metric identifier.
    public var extraDefaults: [String: Double]?

    public init(
        name: String,
        muscleGroup: MuscleGroup,
        exerciseType: ExerciseType,
        equipment: [String],
        notes: String? = nil,
        videoURL: String? = nil,
        isBuiltIn: Bool = false,
        defaultWeight: Double? = nil,
        defaultReps: Int? = nil,
        defaultRepsUpper: Int? = nil,
        defaultDurationSeconds: Int? = nil,
        metrics: [String]? = nil,
        distanceUnit: DistanceUnit? = nil,
        extraDefaults: [String: Double]? = nil
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.exerciseType = exerciseType
        self.equipment = equipment.sorted()
        self.notes = notes
        self.videoURL = videoURL
        self.isBuiltIn = isBuiltIn
        self.defaultWeight = defaultWeight
        self.defaultReps = defaultReps
        self.defaultRepsUpper = defaultRepsUpper
        self.defaultDurationSeconds = defaultDurationSeconds
        self.metrics = metrics?.sorted()
        self.distanceUnit = distanceUnit
        self.extraDefaults = extraDefaults
    }
}

public struct RoutineDTO: Codable, Equatable, Sendable {
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
        /// Per-block rest override in seconds — what interval blocks use
        /// (2-minute rests between rows while the routine default stays
        /// 90 s). Absent means the routine's `restSeconds`.
        public var restSeconds: Int?

        public init(sets: Int, exercises: [EntryDTO], restSeconds: Int? = nil) {
            self.sets = sets
            self.exercises = exercises
            self.restSeconds = restSeconds
        }
    }

    public struct EntryDTO: Codable, Equatable, Sendable {
        /// Exercise name reference.
        public var exercise: String
        public var weight: Double?
        public var reps: Int?
        public var repsUpper: Int?
        public var durationSeconds: Int?
        /// Targets for metrics beyond the three dedicated fields, keyed
        /// by metric identifier ("distance", "pace", "resistance", …).
        public var extraTargets: [String: Double]?

        public init(
            exercise: String,
            weight: Double? = nil,
            reps: Int? = nil,
            repsUpper: Int? = nil,
            durationSeconds: Int? = nil,
            extraTargets: [String: Double]? = nil
        ) {
            self.exercise = exercise
            self.weight = weight
            self.reps = reps
            self.repsUpper = repsUpper
            self.durationSeconds = durationSeconds
            self.extraTargets = extraTargets
        }
    }
}

public struct SessionDTO: Codable, Equatable, Sendable {
    public var routineName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var restSeconds: Int
    public var sets: [SetDTO]

    public init(
        routineName: String,
        startedAt: Date,
        endedAt: Date?,
        restSeconds: Int,
        sets: [SetDTO]
    ) {
        self.routineName = routineName
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
        /// Targets/actuals for metrics beyond the dedicated fields, keyed
        /// by metric identifier. Sessions snapshot everything, so these
        /// stand alone like the rest of the set.
        public var extraTargets: [String: Double]?
        public var extraActuals: [String: Double]?
        /// The block's rest override at session time, if it had one.
        public var restSecondsOverride: Int?

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
            completedAt: Date? = nil,
            extraTargets: [String: Double]? = nil,
            extraActuals: [String: Double]? = nil,
            restSecondsOverride: Int? = nil
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
            self.extraTargets = extraTargets
            self.extraActuals = extraActuals
            self.restSecondsOverride = restSecondsOverride
        }
    }
}

/// Gear as a record, not just a name (additive to schema v1): carried only
/// when it has something to say — custom gear (its existence is user data)
/// or any gear with user config (a weight step, a declared metric
/// profile). This is what makes a new-phone restore complete: without it,
/// a repo brings back WHAT you have but not how it's set up. Membership
/// in libraries lives in `equipmentLibraries`; this is the gear itself.
public struct EquipmentDTO: Codable, Equatable, Sendable {
    public var name: String
    public var isBuiltIn: Bool
    /// Per-tap weight increment for exercises on this gear. Absent means
    /// the unit default; unit-agnostic like every stored number.
    public var weightStep: Double?
    /// Suggested tracked-metric profile for new exercises on this gear —
    /// same curated identifiers as ExerciseDTO.metrics, sorted.
    public var metrics: [String]?
    public var distanceUnit: DistanceUnit?

    public init(
        name: String,
        isBuiltIn: Bool = false,
        weightStep: Double? = nil,
        metrics: [String]? = nil,
        distanceUnit: DistanceUnit? = nil
    ) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.weightStep = weightStep
        self.metrics = metrics?.sorted()
        self.distanceUnit = distanceUnit
    }
}

/// A named equipment context (equipment libraries): the curated gear list
/// for one training location — Home, Hotel, the office rack. `equipment`
/// is names, like every gear reference in the contract; an importer
/// resolves unknown names by creating custom equipment, so libraries
/// round-trip even when they carry gear the catalog doesn't know.
/// Which library is ACTIVE is deliberately NOT in the contract: it's
/// device state ("what's with me right now"), not training data, and two
/// devices syncing one repo may legitimately differ.
public struct EquipmentLibraryDTO: Codable, Equatable, Sendable {
    public var name: String
    /// Equipment names, sorted for deterministic output.
    public var equipment: [String]

    public init(name: String, equipment: [String]) {
        self.name = name
        self.equipment = equipment.sorted()
    }
}

/// The app's single-file export: the whole library plus history. The repo
/// layout stores the same DTOs one entity per file instead.
public struct ExportBundle: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    /// What weight numbers are denominated in. Absent means pounds —
    /// every pre-units file stays valid, and values are never converted.
    public var units: WeightUnit?
    public var exercises: [ExerciseDTO]
    public var routines: [RoutineDTO]
    public var sessions: [SessionDTO]
    /// Gear records carrying user signal (customs, configured built-ins).
    /// Optional and additive, like equipmentLibraries below.
    public var equipment: [EquipmentDTO]?
    /// Equipment libraries. Optional and additive: absent means the file
    /// predates them (readers treat it as "no libraries declared" and
    /// leave device state alone), and pre-libraries readers ignore it.
    public var equipmentLibraries: [EquipmentLibraryDTO]?

    public init(
        units: WeightUnit? = nil,
        exercises: [ExerciseDTO],
        routines: [RoutineDTO],
        sessions: [SessionDTO],
        equipment: [EquipmentDTO]? = nil,
        equipmentLibraries: [EquipmentLibraryDTO]? = nil
    ) {
        self.schemaVersion = Interchange.schemaVersion
        self.units = units
        // Plain lowercased comparison, not localized — output ordering must be
        // identical on every platform for deterministic diffs.
        self.exercises = exercises.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.routines = routines.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.sessions = sessions.sorted { $0.startedAt < $1.startedAt }
        self.equipment = equipment?.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.equipmentLibraries = equipmentLibraries?.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
