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
    /// Whether this exercise is in the user's library ("my exercises"), the
    /// curation that used to be lost on export/restore. Additive: written only
    /// when `false` (the exception — an exported exercise NOT in the library,
    /// e.g. a removed custom), so the common in-library case stays byte-clean
    /// and every pre-existing file (absent) reads as in-library.
    public var inLibrary: Bool?
    /// Default heart-rate target for new routine entries on this exercise
    /// (zone or bpm range). Additive.
    public var defaultHeartRateTarget: HeartRateTarget?
    /// Whether this exercise happens outdoors under GPS (#378) — the flag
    /// that engages live pace/distance and route capture. Rides the
    /// explicit `metrics` profile and is written only when TRUE, so every
    /// indoor exercise (and every pre-field file) stays byte-identical;
    /// absent means indoor.
    public var isOutdoor: Bool?

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
        isOutdoor: Bool? = nil,
        extraDefaults: [String: Double]? = nil,
        inLibrary: Bool? = nil,
        defaultHeartRateTarget: HeartRateTarget? = nil
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
        self.isOutdoor = isOutdoor
        self.extraDefaults = extraDefaults
        self.inLibrary = inLibrary
        self.defaultHeartRateTarget = defaultHeartRateTarget
    }
}

public struct RoutineDTO: Codable, Equatable, Sendable {
    public var name: String
    public var restSeconds: Int
    /// Pause when the session moves to a DIFFERENT exercise or block
    /// (#369); `restSeconds` covers a new round of the same block. 0 means
    /// no countdown. Additive; absent means the app default (15 s), and a
    /// pre-field file round-trips unchanged.
    public var transitionSeconds: Int?
    public var notes: String?
    /// The recurrence (weekdays / frequency). Additive; absent means
    /// unscheduled, so pre-schedule files round-trip unchanged.
    public var schedule: RoutineSchedule?
    public var groups: [GroupDTO]

    public init(name: String, restSeconds: Int, transitionSeconds: Int? = nil, notes: String? = nil, schedule: RoutineSchedule? = nil, groups: [GroupDTO]) {
        self.name = name
        self.restSeconds = restSeconds
        self.transitionSeconds = transitionSeconds
        self.schedule = schedule
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
        /// Heart-rate target (zone or bpm range) for this entry. Additive.
        public var heartRateTarget: HeartRateTarget?

        public init(
            exercise: String,
            weight: Double? = nil,
            reps: Int? = nil,
            repsUpper: Int? = nil,
            durationSeconds: Int? = nil,
            extraTargets: [String: Double]? = nil,
            heartRateTarget: HeartRateTarget? = nil
        ) {
            self.exercise = exercise
            self.weight = weight
            self.reps = reps
            self.repsUpper = repsUpper
            self.durationSeconds = durationSeconds
            self.extraTargets = extraTargets
            self.heartRateTarget = heartRateTarget
        }
    }
}

public struct SessionDTO: Codable, Equatable, Sendable {
    public var routineName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var restSeconds: Int
    /// Active workout seconds — running time only, excluding pauses and
    /// staging (the app's `WorkoutSession.duration`). Additive; absent
    /// means the record was never clock-tracked, so a reader falls back
    /// to the start→end span, exactly as before this field existed.
    public var activeSeconds: Double?
    /// Recorded heart-rate summary for the session (bpm). Additive.
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    /// Outdoor GPS run summary (#378). Additive; absent means the session
    /// carried no GPS run, so every pre-field file keeps its meaning.
    public var run: RunSummary?
    public var sets: [SetDTO]

    /// Capture-time MEASUREMENTS of the session's GPS track, in raw meters
    /// and seconds (unit-agnostic, unlike the extras maps' exercise-
    /// denominated values). Deliberately summary-only: splits and the pace
    /// curve are pure derivations of the route sidecar (the `.gpx` twin in
    /// the repo layout) and history is append-only — a stored derivation
    /// could never be corrected if the algorithm improved.
    public struct RunSummary: Codable, Equatable, Sendable {
        public var distanceMeters: Double
        /// Time at or above the moving-speed floor — a red light doesn't
        /// count against the run.
        public var movingSeconds: Double
        /// Cumulative climb as computed at record time (smoothed +
        /// hysteresis, see `RouteTrack`); absent when the receiver had no
        /// trusted altitude data.
        public var elevationGainMeters: Double?

        public init(distanceMeters: Double, movingSeconds: Double, elevationGainMeters: Double? = nil) {
            self.distanceMeters = distanceMeters
            self.movingSeconds = movingSeconds
            self.elevationGainMeters = elevationGainMeters
        }
    }

    public init(
        routineName: String,
        startedAt: Date,
        endedAt: Date?,
        restSeconds: Int,
        activeSeconds: Double? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        run: RunSummary? = nil,
        sets: [SetDTO]
    ) {
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.restSeconds = restSeconds
        self.activeSeconds = activeSeconds
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.run = run
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
        /// Heart-rate target the set was performed under (snapshot). Additive.
        public var targetHeartRate: HeartRateTarget?
        /// Tracked-metric profile snapshot (metric identifiers), written
        /// only when it says more than `exerciseType` already implies (a
        /// flexible-metrics set). Absent derives from `exerciseType`, like
        /// `ExerciseDTO.metrics` — so classic weight/reps and duration sets
        /// stay absent and byte-stable with pre-snapshot files. Additive.
        public var metrics: [String]?
        /// What this set's distance/pace/speed numbers are denominated in —
        /// snapshotted with the profile so history stands alone even if the
        /// exercise's unit later changes or the exercise is gone. Absent
        /// means meters (or, for a pre-field file, resolve from the exercise).
        public var distanceUnit: DistanceUnit?
        /// Snapshot of the profile's outdoor flag (#378), riding the same
        /// only-when-the-profile-is-written gate as `metrics`. Written only
        /// when TRUE; absent means indoor, byte-stable with pre-field files.
        public var isOutdoor: Bool?

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
            restSecondsOverride: Int? = nil,
            targetHeartRate: HeartRateTarget? = nil,
            metrics: [String]? = nil,
            distanceUnit: DistanceUnit? = nil,
            isOutdoor: Bool? = nil
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
            self.targetHeartRate = targetHeartRate
            self.metrics = metrics?.sorted()
            self.distanceUnit = distanceUnit
            self.isOutdoor = isOutdoor
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
