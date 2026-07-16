import Foundation
import FoundationModels
import PlusPlusKit

/// What the tools need from their owner (the controller implements it):
/// reads, the change engine, and a way to post cards into the thread.
@MainActor
protocol OperatorToolServices: AnyObject {
    var dataService: OperatorDataService { get }
    var engine: ChangeEngine { get }
    func post(_ message: OperatorMessage)
    /// The engine outcome hand-off for the edit tools: the controller
    /// records preview/undo bookkeeping and posts the matching card.
    func handle(_ outcome: ChangeEngine.ChangeOutcome)
}

// MARK: - The narrow-tool surface

// Second field round's lesson, made architecture: the ~3B on-device
// model is a classifier/extractor, not a reasoner. The original single
// propose_change tool asked it to COMPOSE an algebra (operation ×
// entity × targets × filter × values) and it kept failing in the field
// (wrong entity, dropped targets, needless ask_user). Each edit is now
// its own single-intent tool: choosing an operation degenerates into
// picking a labeled tool name (classification, which constrained
// decoding makes near-foolproof), and wrong fields become structurally
// impossible because a tool's schema only CONTAINS its own intent's
// fields. Every tool compiles down to the same Kit `ChangeSpec` —
// validation, tiering, previews, receipts, and undo are engine
// territory, exactly as before. Schema tokens ride in the session for
// every turn of the 4,096-token window, so descriptions stay terse.

/// The entity vocabulary shared by find/rename/delete.
@Generable
enum ChangeKindArg {
    case routine, exercise, superset, library

    var changeEntity: ChangeEntity {
        switch self {
        case .routine: .routine
        case .exercise: .exercise
        case .superset: .superset
        case .library: .library
        }
    }
}

/// Shared string→vocabulary parsing. Wrong strings come back as an
/// INVALID digest the model can correct from; nothing guesses.
enum OperatorArgs {
    static func muscleGroup(from raw: String) -> MuscleGroup? {
        MuscleGroup.allCases.first {
            $0.rawValue.compare(raw, options: .caseInsensitive) == .orderedSame
        }
    }

    static func trackMode(from raw: String) -> TrackMode? {
        TrackMode.allCases.first {
            $0.rawValue.compare(raw, options: .caseInsensitive) == .orderedSame
        }
    }

    static func firstUnknownWeekday(in names: [String]) -> String? {
        names.first { ChangeSpec.weekdayNumber(from: $0) == nil }
    }

    static func weekdaySet(_ names: [String]) -> Set<Int> {
        Set(names.compactMap { ChangeSpec.weekdayNumber(from: $0) })
    }
}

/// The one propose pathway every edit tool funnels through. The return
/// string only steers the model's narration; the preview/receipt cards
/// the controller posts are the real record.
@MainActor
private func propose(_ spec: ChangeSpec, services: (any OperatorToolServices)?) -> String {
    guard let services else { return "unavailable" }
    let outcome = services.engine.propose(spec)
    services.handle(outcome)
    return outcome.digest
}

// The framework's `call` requirement is NONISOLATED — a @MainActor class
// cannot satisfy it implicitly, so the tools are plain classes whose
// `call` bodies hop to the MainActor explicitly (their work is
// ModelContext work). `services` is set once at init and only read.

// MARK: - Reads

/// Search the user's data. Digest lines re-enter the context window,
/// so the service caps them by construction.
final class FindItemsTool: Tool {
    let name = "find_items"
    let description = "Search the user's routines, exercises, supersets, or equipment libraries."

    @Generable
    struct Arguments {
        var kind: ChangeKindArg
        @Guide(description: "Name fragment; forgiving, typos still match")
        var nameContains: String? = nil
        @Guide(description: "Exercises only; one of the muscle group names")
        var muscleGroup: String? = nil
        @Guide(description: "Exercises only: limit to the user's library")
        var inLibraryOnly: Bool? = nil
        @Guide(description: "Max lines, 1 to 15")
        var limit: Int? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            guard let services else { return "unavailable" }
            var muscle: MuscleGroup? = nil
            if let raw = arguments.muscleGroup {
                guard let mapped = OperatorArgs.muscleGroup(from: raw) else {
                    return "unknown muscleGroup \(raw)"
                }
                muscle = mapped
            }
            return services.dataService.findItems(
                kind: arguments.kind.changeEntity,
                nameContains: arguments.nameContains,
                muscleGroup: muscle,
                inLibraryOnly: arguments.inLibraryOnly ?? false,
                limit: arguments.limit ?? 8
            )
        }
    }
}

/// History stats from real fetches. The instructions tell the model to
/// never guess numbers; this is where the numbers come from.
final class GetStatsTool: Tool {
    let name = "get_stats"
    let description = "Compute workout history stats. Never guess numbers; use this."

    @Generable
    enum StatKindArg {
        case workoutCount, lastDone, setVolume, streak
    }

    @Generable
    struct Arguments {
        var question: StatKindArg
        var exerciseName: String? = nil
        var routineName: String? = nil
        @Guide(description: "Window in days; default 30")
        var days: Int? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            guard let services else { return "unavailable" }
            let kind: OperatorDataService.StatKind
            switch arguments.question {
            case .workoutCount: kind = .workoutCount
            case .lastDone: kind = .lastDone
            case .setVolume: kind = .setVolume
            case .streak: kind = .streak
            }
            return services.dataService.stats(
                kind: kind,
                exerciseName: arguments.exerciseName,
                routineName: arguments.routineName,
                days: arguments.days
            )
        }
    }
}

// MARK: - Gear

final class AddGearTool: Tool {
    let name = "add_gear"
    let description = "Add equipment to the user's gear."

    @Generable
    struct Arguments {
        @Guide(description: "Equipment names to add")
        var names: [String]
        @Guide(description: "Library name; omit for the user's current gear")
        var library: String? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: .library,
                targets: arguments.library.map { [$0] } ?? [],
                values: ChangeValues(addEquipment: arguments.names)
            ), services: services)
        }
    }
}

final class RemoveGearTool: Tool {
    let name = "remove_gear"
    let description = "Remove equipment from the user's gear."

    @Generable
    struct Arguments {
        @Guide(description: "Equipment names to remove")
        var names: [String]
        @Guide(description: "Library name; omit for the user's current gear")
        var library: String? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: .library,
                targets: arguments.library.map { [$0] } ?? [],
                values: ChangeValues(removeEquipment: arguments.names)
            ), services: services)
        }
    }
}

final class ReplaceGearTool: Tool {
    let name = "replace_gear"
    let description = "Replace a library's whole equipment list. The app previews it first."

    @Generable
    struct Arguments {
        @Guide(description: "The complete new equipment list")
        var names: [String]
        @Guide(description: "Library name; omit for the user's current gear")
        var library: String? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: .library,
                targets: arguments.library.map { [$0] } ?? [],
                values: ChangeValues(equipment: arguments.names)
            ), services: services)
        }
    }
}

final class CreateLibraryTool: Tool {
    let name = "create_library"
    let description = "Create a new equipment library."

    @Generable
    struct Arguments {
        var name: String
        @Guide(description: "Equipment names to start it with")
        var gear: [String]? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .create, entity: .library,
                values: ChangeValues(name: arguments.name, equipment: arguments.gear)
            ), services: services)
        }
    }
}

// MARK: - Routines

final class CreateRoutineTool: Tool {
    let name = "create_routine"
    let description = "Create a workout routine."

    @Generable
    struct Arguments {
        var name: String
        @Guide(description: "Exercise names, in order")
        var exercises: [String]? = nil
        @Guide(description: "Weekday names like mon, thu")
        var days: [String]? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            var days: Set<Int>? = nil
            if let names = arguments.days {
                if let bad = OperatorArgs.firstUnknownWeekday(in: names) {
                    return "INVALID: unknown weekday \(bad); use names like mon, thu"
                }
                days = OperatorArgs.weekdaySet(names)
            }
            return propose(ChangeSpec(
                operation: .create, entity: .routine,
                values: ChangeValues(
                    name: arguments.name,
                    scheduleDays: days,
                    addExercises: arguments.exercises
                )
            ), services: services)
        }
    }
}

final class EditRoutineExercisesTool: Tool {
    let name = "edit_routine_exercises"
    let description = "Add or remove exercises in a routine."

    @Generable
    struct Arguments {
        var routine: String
        @Guide(description: "Exercise names to add")
        var add: [String]? = nil
        @Guide(description: "Exercise names to remove")
        var remove: [String]? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: .routine,
                targets: [arguments.routine],
                values: ChangeValues(
                    addExercises: arguments.add,
                    removeExercises: arguments.remove
                )
            ), services: services)
        }
    }
}

final class SetScheduleTool: Tool {
    let name = "set_schedule"
    let description = "Set or clear a routine's weekday schedule."

    @Generable
    struct Arguments {
        var routine: String
        @Guide(description: "Weekday names like mon, thu. Empty clears the schedule")
        var days: [String]
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            if let bad = OperatorArgs.firstUnknownWeekday(in: arguments.days) {
                return "INVALID: unknown weekday \(bad); use names like mon, thu"
            }
            return propose(ChangeSpec(
                operation: .update, entity: .routine,
                targets: [arguments.routine],
                values: ChangeValues(scheduleDays: OperatorArgs.weekdaySet(arguments.days))
            ), services: services)
        }
    }
}

final class SetRestTool: Tool {
    let name = "set_rest"
    let description = "Set a routine's rest between sets."

    @Generable
    struct Arguments {
        var routine: String
        @Guide(description: "Rest in seconds")
        var seconds: Int
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: .routine,
                targets: [arguments.routine],
                values: ChangeValues(restSeconds: arguments.seconds)
            ), services: services)
        }
    }
}

// MARK: - Exercises

final class CreateExerciseTool: Tool {
    let name = "create_exercise"
    let description = "Create a custom exercise."

    @Generable
    struct Arguments {
        var name: String
        @Guide(description: "One of: chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody")
        var muscleGroup: String? = nil
        @Guide(description: "One of: reps, duration, weightReps")
        var trackBy: String? = nil
        @Guide(description: "Equipment names it needs")
        var equipment: [String]? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            var muscle: MuscleGroup? = nil
            if let raw = arguments.muscleGroup {
                guard let mapped = OperatorArgs.muscleGroup(from: raw) else {
                    return "INVALID: unknown muscleGroup \(raw)"
                }
                muscle = mapped
            }
            var mode: TrackMode? = nil
            if let raw = arguments.trackBy {
                guard let mapped = OperatorArgs.trackMode(from: raw) else {
                    return "INVALID: unknown trackBy \(raw); use reps, duration, or weightReps"
                }
                mode = mapped
            }
            return propose(ChangeSpec(
                operation: .create, entity: .exercise,
                values: ChangeValues(
                    name: arguments.name,
                    trackBy: mode,
                    muscleGroup: muscle,
                    equipment: arguments.equipment
                )
            ), services: services)
        }
    }
}

final class EditExerciseTool: Tool {
    let name = "edit_exercise"
    let description = "Change one exercise's defaults, muscle group, notes, or gear."

    @Generable
    struct Arguments {
        var exercise: String
        @Guide(description: "Default reps per set")
        var reps: Int? = nil
        @Guide(description: "Default seconds per set")
        var durationSeconds: Int? = nil
        @Guide(description: "Default weight")
        var weight: Double? = nil
        @Guide(description: "One of the muscle group names")
        var muscleGroup: String? = nil
        var notes: String? = nil
        @Guide(description: "Replaces the exercise's gear list")
        var equipment: [String]? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            var muscle: MuscleGroup? = nil
            if let raw = arguments.muscleGroup {
                guard let mapped = OperatorArgs.muscleGroup(from: raw) else {
                    return "INVALID: unknown muscleGroup \(raw)"
                }
                muscle = mapped
            }
            return propose(ChangeSpec(
                operation: .update, entity: .exercise,
                targets: [arguments.exercise],
                values: ChangeValues(
                    notes: arguments.notes,
                    muscleGroup: muscle,
                    reps: arguments.reps,
                    durationSeconds: arguments.durationSeconds,
                    weight: arguments.weight,
                    equipment: arguments.equipment
                )
            ), services: services)
        }
    }
}

final class ConvertTrackingTool: Tool {
    let name = "convert_tracking"
    let description = "Convert how exercises are tracked, one or many at once."

    @Generable
    struct Arguments {
        @Guide(description: "One of: reps, duration, weightReps")
        var to: String
        @Guide(description: "Exact exercise names; omit when using nameContains")
        var exercises: [String]? = nil
        @Guide(description: "Select every exercise whose name contains this")
        var nameContains: String? = nil
        @Guide(description: "Only exercises currently tracked this way")
        var trackedNow: String? = nil
        @Guide(description: "Seconds per set after converting to duration")
        var durationSeconds: Int? = nil
        @Guide(description: "Reps per set after converting to reps")
        var reps: Int? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            guard let mode = OperatorArgs.trackMode(from: arguments.to) else {
                return "INVALID: unknown trackBy \(arguments.to); use reps, duration, or weightReps"
            }
            var filter: ChangeFilter? = nil
            if arguments.nameContains != nil || arguments.trackedNow != nil {
                var built = ChangeFilter(nameContains: arguments.nameContains)
                if let raw = arguments.trackedNow {
                    guard let current = OperatorArgs.trackMode(from: raw) else {
                        return "INVALID: unknown trackedNow \(raw); use reps, duration, or weightReps"
                    }
                    built.trackedBy = current
                }
                filter = built
            }
            return propose(ChangeSpec(
                operation: .update, entity: .exercise,
                targets: arguments.exercises ?? [],
                filter: filter,
                values: ChangeValues(
                    trackBy: mode,
                    reps: arguments.reps,
                    durationSeconds: arguments.durationSeconds
                )
            ), services: services)
        }
    }
}

// MARK: - Supersets, renames, deletes

final class FormSupersetTool: Tool {
    let name = "form_superset"
    let description = "Group exercises in a routine into a superset."

    @Generable
    struct Arguments {
        var routine: String
        @Guide(description: "Two or more exercise names in that routine")
        var exercises: [String]
        @Guide(description: "Sets per round")
        var sets: Int? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            // Guarded HERE so the digest teaches the real problem: with
            // one exercise, spec validation would say "update needs
            // values" (wrong lesson), and one exercise plus `sets`
            // would silently mutate a solo block's sets instead of
            // forming anything (reviewer finding, 2026-07-16).
            guard arguments.exercises.count >= 2 else {
                return "INVALID: a superset needs at least two exercises"
            }
            return propose(ChangeSpec(
                operation: .update, entity: .superset,
                targets: arguments.exercises,
                filter: ChangeFilter(inRoutine: arguments.routine),
                values: arguments.sets.map { ChangeValues(sets: $0) }
            ), services: services)
        }
    }
}

/// Renameable kinds only — supersets aren't nameable, and a shared
/// four-case enum would let the model pick a dead end it could never
/// escape (the INVALID digest asks for a filter field this tool
/// doesn't have). Structurally impossible beats teachable.
@Generable
enum RenameKindArg {
    case routine, exercise, library

    var changeEntity: ChangeEntity {
        switch self {
        case .routine: .routine
        case .exercise: .exercise
        case .library: .library
        }
    }
}

final class RenameItemTool: Tool {
    let name = "rename_item"
    let description = "Rename a routine, exercise, or library."

    @Generable
    struct Arguments {
        var kind: RenameKindArg
        @Guide(description: "Its current name")
        var from: String
        @Guide(description: "The new name")
        var to: String
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            propose(ChangeSpec(
                operation: .update, entity: arguments.kind.changeEntity,
                targets: [arguments.from],
                values: ChangeValues(name: arguments.to)
            ), services: services)
        }
    }
}

final class DeleteItemTool: Tool {
    let name = "delete_item"
    let description = "Delete routines, exercises, libraries, or dissolve supersets. The app previews deletes first."

    @Generable
    struct Arguments {
        var kind: ChangeKindArg
        @Guide(description: "Names of the things to delete")
        var names: [String]
        @Guide(description: "Supersets only: the routine they're in")
        var routine: String? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            // Pre-checked in the tool's OWN vocabulary: the spec-level
            // digest says "filter.inRoutine", a field name this tool
            // doesn't expose, and the model can't bridge that gap.
            if arguments.kind == .superset, arguments.routine == nil {
                return "INVALID: superset deletes need the routine field"
            }
            let filter: ChangeFilter? = arguments.kind == .superset
                ? arguments.routine.map { ChangeFilter(inRoutine: $0) }
                : nil
            return propose(ChangeSpec(
                operation: .delete, entity: arguments.kind.changeEntity,
                targets: arguments.names,
                filter: filter
            ), services: services)
        }
    }
}

// MARK: - Choices

/// Tappable choices. Deliberately NON-blocking: the card renders, the
/// turn ends, and the tap arrives as the next user message — a held
/// continuation would wedge `isResponding` across a dismissed tray or
/// a killed app.
final class AskUserTool: Tool {
    let name = "ask_user"
    // The second field round earned the extra description tokens: the
    // model re-asked "remove barbell and weight plate" as a pick-ONE
    // radio, so the description now polices both failure modes.
    let description = "Show tappable choices for a decision the user has not already made. Never re-ask items they already named. Set allowMultiple true when several can apply. Then stop and wait."

    @Generable
    struct Arguments {
        var question: String
        @Guide(description: "2 to 5 short choices")
        var options: [String]
        var allowMultiple: Bool? = nil
    }

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: Arguments) async throws -> String {
        let services = self.services
        return await MainActor.run {
            guard let services else { return "unavailable" }
            let options = Array(arguments.options.prefix(5))
            guard options.count >= 2 else {
                return "ask_user needs 2 to 5 options"
            }
            services.post(OperatorMessage(kind: .options(.init(
                question: arguments.question,
                options: options,
                allowMultiple: arguments.allowMultiple ?? false
            ))))
            return "Choices shown. End your reply now; the user's pick arrives as their next message."
        }
    }
}
