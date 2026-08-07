import Foundation
import SwiftData
import PlusPlusKit

@Model
final class Exercise {
    var name: String
    /// The muscle group this exercise is FOR — the primary, and the first
    /// entry of `muscleGroups`. Still the column every single-group reader
    /// uses (the interchange's required field, the substitution pools), so
    /// writing `muscleGroups` keeps it in step, exactly as `metricProfile`
    /// keeps `exerciseType` honest.
    var muscleGroup: MuscleGroup
    /// The SECONDARY groups this exercise also works, Kit-encoded JSON —
    /// additive and optional, so no store migration and existing rows read
    /// `nil`. Never read raw: `muscleGroups` resolves it.
    var muscleGroupsData: Data?
    @Relationship(inverse: \Equipment.exercises) var equipment: [Equipment] = []
    var exerciseType: ExerciseType
    var isBuiltIn: Bool
    /// LEGACY personal-library membership (v2 Library, #63). FROZEN
    /// since the whole-catalog restructure (2026-07-17): an exercise is
    /// a thing you choose to do, not a thing you own, so the Exercises
    /// surface is the whole catalog and membership stopped gating
    /// browsing. No live read or write remains (the Equipment.inLibrary
    /// precedent) — kept for store compatibility and parsed-but-ignored
    /// on import. Curation is `isFavorite` now.
    var inLibrary: Bool = true
    /// Whether the user has favorited this exercise (the whole-catalog
    /// curation flag, 2026-07-17). A filter, a row/detail star, and the
    /// interchange's "what's yours" basis. Literal default migrates
    /// lightweight, exactly as `inLibrary` did; no backfill.
    var isFavorite: Bool = false
    var notes: String?
    var videoURL: String?
    /// Default targets (#187): what a fresh routine entry starts from.
    /// nil falls back to the metric's global default (10 reps / 45 s).
    /// Routine edits bump these — the latest prescription anywhere IS
    /// the new default — and the editor exposes them directly.
    var defaultWeight: Double?
    var defaultReps: Int?
    var defaultRepsUpper: Int?
    var defaultDurationSeconds: Int?
    /// Encoded HeartRateTarget default for cardio exercises — rides the
    /// same #187 bump rule as the other defaults.
    var defaultHeartRateTargetData: Data?
    /// Tracked-metric profile (flexible metrics), Kit-encoded JSON —
    /// additive, so no store migration. nil resolves through
    /// `metricProfile`: built-ins fall back to the seed catalog's
    /// assignment (existing stores get rich cardio profiles with zero
    /// writes), customs to the legacy exerciseType's profile.
    var metricsData: Data?
    /// Default targets for metrics beyond the three columns above —
    /// one Kit-encoded [metric: value] bag (see MetricValues).
    var extraDefaultsData: Data?

    /// Deliberately excludes the heart-rate default: this only feeds
    /// the interchange export filter, and HR targets stay out of the
    /// format until something consumes them (the scheduleData rule).
    var hasDefaultTargets: Bool {
        defaultWeight != nil || defaultReps != nil
            || defaultRepsUpper != nil || defaultDurationSeconds != nil
            || extraDefaultsData != nil
    }

    /// The resolved profile — what the planning sheet and set screen
    /// expose for this exercise. Setting it keeps the legacy
    /// `exerciseType` consistent for old readers (interchange, watch).
    var metricProfile: MetricProfile {
        get {
            if let stored = MetricProfile.decode(from: metricsData) { return stored }
            if isBuiltIn, let seeded = SeedData.builtInProfile(named: name) { return seeded }
            return .derived(from: exerciseType)
        }
        set {
            metricsData = newValue.encoded()
            exerciseType = newValue.legacyType
        }
    }

    /// The user's EXPLICIT list, or nil to follow the catalog. Exposed for
    /// the interchange (an explicit list is exported, an absent one isn't,
    /// so catalog authoring keeps reaching restored stores) and for the
    /// editor's revert. Assigning nil hands the exercise back to the
    /// catalog; assigning a list pins it, single groups included — that is
    /// how pruning a built-in's secondaries sticks.
    var explicitMuscleGroups: [MuscleGroup]? {
        get { MuscleGroups.decode(muscleGroupsData).map { MuscleGroups.normalized($0, fallback: muscleGroup) } }
        set {
            guard let newValue, !newValue.isEmpty else { muscleGroupsData = nil; return }
            let normalized = MuscleGroups.normalized(newValue, fallback: muscleGroup)
            muscleGroup = normalized[0]
            muscleGroupsData = MuscleGroups.encode(normalized)
        }
    }

    /// Every muscle group this exercise works, PRIMARY FIRST — what the
    /// editor's chips select and what the row and detail capsules show.
    /// Resolution mirrors `metricProfile`: an explicit stored list wins,
    /// then a built-in's catalog row (so catalog authoring reaches every
    /// existing store with zero writes), then the single `muscleGroup`.
    /// Setting it re-stamps `muscleGroup` from the primary, so the two can
    /// never disagree.
    var muscleGroups: [MuscleGroup] {
        get {
            if let explicit = explicitMuscleGroups { return explicit }
            if isBuiltIn, let seeded = catalogDefinition?.muscleGroups, seeded.count > 1 {
                return seeded
            }
            return [muscleGroup]
        }
        set { explicitMuscleGroups = newValue }
    }

    /// Extra-metric defaults, decoded. Setter drops entries for metrics
    /// the profile doesn't track — stale values must not resurface if a
    /// metric is re-added later with different intent.
    var extraDefaults: [WorkoutMetric: Double] {
        get { MetricValues.decode(extraDefaultsData) }
        set { extraDefaultsData = MetricValues.encode(newValue) }
    }

    // MARK: - Stepper strides (#391)
    // The per-tap increment the weight/assist ± keys move by is an EQUIPMENT
    // property, not an exercise or session one: your microplates step 2.5 on
    // every barbell lift. It rides the long-standing `Equipment.weightStep`,
    // resolved through `weightStepOverride` (the smallest stride across
    // loadable gear, so the finest plates win). The set screen's increment
    // sheet writes back to that gear so the change sticks and travels with
    // it. Only the load metrics are adjustable this way — every other metric
    // keeps its unit/metric default, which has no equipment home.

    /// Loadable gear that can carry the weight stride (a bench holds no
    /// plates). `isDeleted` guard mirrors `weightStepOverride`.
    private var loadableStepGear: [Equipment] {
        equipment.filter { !$0.isDeleted && SeedData.isLoadable($0) }
    }

    /// The chosen stride for a metric, read off the exercise's gear — the
    /// top layer of step resolution. Only the load metrics have one; every
    /// other metric resolves nil (its default step stands).
    func stepOverride(for metric: WorkoutMetric) -> Double? {
        (metric == .weight || metric == .assistance) ? weightStepOverride : nil
    }

    /// Whether `metric`'s stride can be adjusted from the set screen — only
    /// the load metrics, and only when there's loadable gear to hold the
    /// stride (a gearless bodyweight move keeps the default step).
    func canAdjustStep(for metric: WorkoutMetric) -> Bool {
        (metric == .weight || metric == .assistance) && !loadableStepGear.isEmpty
    }

    /// Persist a chosen weight stride onto the exercise's loadable gear, so
    /// it applies here and everywhere that gear is used. Writing to every
    /// loadable piece keeps `weightStepOverride`'s min-resolution honest (one
    /// straggler at the old stride would otherwise win).
    func setStep(_ value: Double, for metric: WorkoutMetric) {
        guard value > 0, metric == .weight || metric == .assistance else { return }
        for gear in loadableStepGear { gear.weightStep = value }
    }

    /// One lookup for any metric's default target, columns and bag alike.
    func defaultTarget(_ metric: WorkoutMetric) -> Double? {
        switch metric {
        case .weight: defaultWeight
        case .reps: defaultReps.map(Double.init)
        case .duration: defaultDurationSeconds.map(Double.init)
        default: extraDefaults[metric]
        }
    }

    // MARK: - Add-time resolution (config audit, 2026-07-15)
    // What a fresh routine entry / session block starts from: the
    // exercise's own bumped default (#187 — the user's latest word),
    // else the catalog's per-exercise assignment, else the global floor.
    // Computed, not stored — catalog improvements keep reaching every
    // store with zero writes, like the profile fallback above.

    /// The catalog row for a built-in; customs have none.
    private var catalogDefinition: SeedData.BuiltInExerciseDefinition? {
        isBuiltIn ? SeedData.builtInDefinition(named: name) : nil
    }

    /// Set count for a fresh block: a stretch is one hold, a mobility
    /// drill one pass, a steady cardio piece one round; everything else
    /// (customs included — we can't classify intent, and set count has
    /// no per-exercise stored home to bump) keeps the classic 3.
    var defaultSetCount: Int {
        catalogDefinition?.defaultSets ?? 3
    }

    /// The full target prefill for a fresh routine entry or session
    /// config — ONE resolution, so the two add paths can never drift.
    /// Untracked metrics resolve nil. The one place the target field list
    /// lives (see `RoutineExercise.targets`).
    struct AddTimeTargets: Equatable {
        var weight: Double?
        var reps: Int?
        var repsUpper: Int?
        var durationSeconds: Int?
        var heartRateTargetData: Data?
        var extraTargets: [WorkoutMetric: Double]
    }

    /// The duration rule: own default → catalog assignment → a 45 s
    /// floor whenever duration is the profile's ONLY work metric — not
    /// just for bare [duration] profiles. That covers the loaded carries
    /// ([weight, duration]), which used to start with no work target at
    /// all and silently ran an arbitrary 30 s auto-timer in-session.
    /// Profiles with another work metric (a rower's distance) take no
    /// fabricated target — it would hijack the set's driver (the
    /// appendExercise rule). The heart-rate default only prefills where
    /// the prescription is offered at all (`supportsHeartRateTarget`) —
    /// a stretch must not inherit a stale zone onto fresh entries.
    var addTimeTargets: AddTimeTargets {
        let profile = metricProfile
        let catalog = catalogDefinition
        let duration: Int?
        if !profile.contains(.duration) {
            duration = nil
        } else if let own = defaultDurationSeconds ?? catalog?.defaultDurationSeconds {
            duration = own
        } else {
            duration = profile.metrics.filter(\.isWorkMetric) == [.duration] ? 45 : nil
        }
        return AddTimeTargets(
            weight: profile.contains(.weight) ? defaultWeight : nil,
            reps: profile.tracksReps ? (defaultReps ?? catalog?.defaultReps ?? 10) : nil,
            repsUpper: profile.tracksReps ? defaultRepsUpper : nil,
            durationSeconds: duration,
            heartRateTargetData: profile.legacyType == .duration && supportsHeartRateTarget
                ? defaultHeartRateTargetData : nil,
            extraTargets: extraDefaults.filter { profile.contains($0.key) }
        )
    }

    /// Whether a heart-rate prescription is offered for this exercise —
    /// catalog stretches and static holds say no (the definition table's
    /// `supportsHeartRate` column); everything else, customs included,
    /// keeps it.
    var supportsHeartRateTarget: Bool {
        catalogDefinition?.supportsHeartRate ?? true
    }

    // MARK: - Authored attributes (catalog expansion 2026-07-31; editable 2026-08-02, #496)
    // Movement pattern, mechanic, and laterality resolve exactly as
    // `muscleGroups` does: an explicit stored override wins, else the
    // catalog row, else nothing. The override columns are additive
    // optionals, so they migrate lightweight and existing rows read nil.
    //
    // ⚠️ nil means FOLLOW THE CATALOG, not "none" — which is why the
    // editor only offers a "Not set" option where the catalog says
    // nothing (a custom, or a built-in with no authored value). On a
    // built-in that HAS one, picking it back stores nil again, so
    // catalog authoring keeps reaching untouched rows.

    /// The user's explicit pattern, or nil to follow the catalog.
    var movementPatternOverride: MovementPattern?
    /// The user's explicit mechanic, or nil to follow the catalog.
    var mechanicOverride: ExerciseMechanic?
    /// The user's explicit laterality, or nil to follow the catalog.
    var lateralityOverride: ExerciseLaterality?

    /// The program bucket this move files under (hinge, carry…); nil when
    /// neither the user nor the catalog says.
    var movementPattern: MovementPattern? {
        movementPatternOverride ?? catalogDefinition?.movementPattern
    }

    /// Compound vs isolation (programming semantics); nil when unclassified.
    var mechanic: ExerciseMechanic? {
        mechanicOverride ?? catalogDefinition?.mechanic
    }

    /// Bilateral vs unilateral; nil when unclassified.
    var laterality: ExerciseLaterality? {
        lateralityOverride ?? catalogDefinition?.laterality
    }

    /// Whether the user has overridden any authored attribute — one of
    /// the "this built-in is annotated, so export it" conditions.
    var hasAttributeOverrides: Bool {
        movementPatternOverride != nil || mechanicOverride != nil || lateralityOverride != nil
    }

    /// What the CATALOG says, ignoring any override — the editor's
    /// fallback comparison (an override equal to this stays unstored) and
    /// what decides whether a "Not set" option is offerable at all.
    var catalogAttributeDefaults: (pattern: MovementPattern?, mechanic: ExerciseMechanic?, laterality: ExerciseLaterality?) {
        let definition = catalogDefinition
        return (definition?.movementPattern, definition?.mechanic, definition?.laterality)
    }

    /// The movement family this exercise READS as — the universal-search
    /// row's figure icon. Catalog stretch/mobility rows carry an authored
    /// override (derivation can't tell a stretch from a plank); everything
    /// else derives from gear + tracked metrics on the fly. Computed, not
    /// stored — a type marker, not data.
    var modality: ExerciseModality {
        if let authored = catalogDefinition?.modality { return authored }
        return ExerciseModality.derive(
            equipmentNames: Set(equipment.filter { !$0.isDeleted }.map(\.name)),
            metrics: metricProfile.metrics
        )
    }

    /// The modality's SF Symbol (16 pt faint ink on search rows).
    /// Exhaustive on purpose — a new family has to pick a figure rather
    /// than falling to a default that quietly reads as something else.
    var modalitySymbolName: String {
        switch modality {
        case .strength: "figure.strengthtraining.traditional"
        case .cardio: "figure.mixed.cardio"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .rowing: "figure.indoor.rowing"
        case .swimming: "figure.pool.swim"
        case .elliptical: "figure.elliptical"
        case .stairClimbing: "figure.stair.stepper"
        case .jumpRope: "figure.jumprope"
        case .flexibility: "figure.flexibility"
        }
    }

    /// The planning/config sheets' Target HR row gate, in one place: the
    /// cardio prescription rides the duration family, dropped where it's
    /// meaningless — but a target someone already set stays visible and
    /// editable (the stale-prescription rule), never invisible-but-active.
    func showsHeartRateTargetRow(existingTarget: HeartRateTarget?) -> Bool {
        metricProfile.legacyType == .duration
            && (supportsHeartRateTarget || existingTarget != nil)
    }

    /// The per-tap weight increment this exercise's gear implies: the
    /// smallest override among its LOADABLE equipment (microplates win
    /// over a pin stack when both are involved), nil when none is set.
    /// Non-loadable gear is skipped, not migrated (#236): pre-build-32
    /// stores can carry a step on a Bench from when every screen
    /// offered one — the card is gated now, so honoring that value
    /// would wedge stepping with no UI left to reveal or clear it.
    /// isDeleted guard mirrors ExerciseFilterState (bug hunt B1).
    var weightStepOverride: Double? {
        equipment
            .filter { !$0.isDeleted && SeedData.isLoadable($0) }
            .compactMap(\.weightStep).min()
    }

    init(
        name: String,
        muscleGroup: MuscleGroup,
        equipment: [Equipment] = [],
        exerciseType: ExerciseType = .weightReps,
        isBuiltIn: Bool = false,
        notes: String? = nil,
        videoURL: String? = nil
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.exerciseType = exerciseType
        self.isBuiltIn = isBuiltIn
        self.notes = notes
        self.videoURL = videoURL
    }
}
