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
    /// The engine outcome hand-off for propose_change: the controller
    /// records preview/undo bookkeeping and posts the matching card.
    func handle(_ outcome: ChangeEngine.ChangeOutcome)
}

// MARK: - The @Generable mirror of Kit's ChangeSpec

/// Thin, model-facing twins of the Kit vocabulary. The macro cannot
/// build on Linux, so these stay app-side and map 1:1 onto `ChangeSpec`
/// (pure, Linux-tested) via `toSpec()` — everything downstream of that
/// call is deterministic engine code. Schema tokens count against the
/// 4,096 window: every @Guide line here earns its keep.
@Generable
enum ChangeOpArg {
    case create, update, delete
}

@Generable
enum ChangeKindArg {
    case routine, exercise, superset, library

    /// The one arg→Kit kind mapping (toSpec and find_items share it).
    var changeEntity: ChangeEntity {
        switch self {
        case .routine: .routine
        case .exercise: .exercise
        case .superset: .superset
        case .library: .library
        }
    }
}

@Generable
struct FilterArgs {
    @Guide(description: "Case-insensitive name fragment")
    var nameContains: String? = nil
    @Guide(description: "One of: chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody")
    var muscleGroup: String? = nil
    @Guide(description: "Current tracking, one of: reps, duration, weightReps")
    var trackedBy: String? = nil
    @Guide(description: "Routine name; superset changes only")
    var inRoutine: String? = nil
}

@Generable
struct ValuesArgs {
    var name: String? = nil
    var notes: String? = nil
    @Guide(description: "Routine rest between sets, seconds")
    var restSeconds: Int? = nil
    @Guide(description: "Weekday names like mon,thu. Empty array clears the schedule")
    var scheduleDays: [String]? = nil
    @Guide(description: "Convert tracking, one of: reps, duration, weightReps")
    var trackBy: String? = nil
    @Guide(description: "One of: chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody")
    var muscleGroup: String? = nil
    var reps: Int? = nil
    var durationSeconds: Int? = nil
    var weight: Double? = nil
    @Guide(description: "Sets per block, supersets only")
    var sets: Int? = nil
    @Guide(description: "Equipment names; replaces the list")
    var equipment: [String]? = nil
    @Guide(description: "Exercise names to append to a routine")
    var addExercises: [String]? = nil
    var removeExercises: [String]? = nil
}

@Generable
struct ChangeArgs {
    var operation: ChangeOpArg
    var entity: ChangeKindArg
    @Guide(description: "Exact names to affect. Empty when creating or when filter selects")
    var targets: [String]
    var filter: FilterArgs? = nil
    var values: ValuesArgs? = nil
}

/// `toSpec()`'s outcome — a String reason on failure (Swift's `Result`
/// requires an `Error` failure type, which the reason string is not).
enum ArgMapping {
    case spec(ChangeSpec)
    case invalid(String)
}

extension ChangeArgs {
    /// The one app→Kit mapping. String fields the model got wrong come
    /// back as a reason instead of a spec, so the model can correct
    /// itself off the INVALID digest.
    func toSpec() -> ArgMapping {
        let mappedOperation: ChangeOperation
        switch operation {
        case .create: mappedOperation = .create
        case .update: mappedOperation = .update
        case .delete: mappedOperation = .delete
        }
        let mappedEntity = entity.changeEntity

        var mappedFilter: ChangeFilter? = nil
        if let filter {
            var result = ChangeFilter()
            result.nameContains = filter.nameContains
            result.inRoutine = filter.inRoutine
            if let raw = filter.muscleGroup {
                guard let muscle = Self.muscleGroup(from: raw) else {
                    return .invalid("unknown muscleGroup \(raw)")
                }
                result.muscleGroup = muscle
            }
            if let raw = filter.trackedBy {
                guard let mode = Self.trackMode(from: raw) else {
                    return .invalid("unknown trackedBy \(raw); use reps, duration, or weightReps")
                }
                result.trackedBy = mode
            }
            mappedFilter = result
        }

        var mappedValues: ChangeValues? = nil
        if let values {
            var result = ChangeValues()
            result.name = values.name
            result.notes = values.notes
            result.restSeconds = values.restSeconds
            result.reps = values.reps
            result.durationSeconds = values.durationSeconds
            result.weight = values.weight
            result.sets = values.sets
            result.equipment = values.equipment
            result.addExercises = values.addExercises
            result.removeExercises = values.removeExercises
            if let raw = values.trackBy {
                guard let mode = Self.trackMode(from: raw) else {
                    return .invalid("unknown trackBy \(raw); use reps, duration, or weightReps")
                }
                result.trackBy = mode
            }
            if let raw = values.muscleGroup {
                guard let muscle = Self.muscleGroup(from: raw) else {
                    return .invalid("unknown muscleGroup \(raw)")
                }
                result.muscleGroup = muscle
            }
            if let dayNames = values.scheduleDays {
                var days = Set<Int>()
                for dayName in dayNames {
                    guard let day = ChangeSpec.weekdayNumber(from: dayName) else {
                        return .invalid("unknown weekday \(dayName); use names like mon, thu")
                    }
                    days.insert(day)
                }
                result.scheduleDays = days
            }
            mappedValues = result
        }

        return .spec(ChangeSpec(
            operation: mappedOperation,
            entity: mappedEntity,
            targets: targets,
            filter: mappedFilter,
            values: mappedValues
        ))
    }

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
}

// MARK: - Tools

// The framework's `call` requirement is NONISOLATED — a @MainActor class
// cannot satisfy it implicitly, so the tools are plain classes whose
// `call` bodies hop to the MainActor explicitly (their work is
// ModelContext work). `services` is set once at init and only read.

/// Search the user's data. Digest lines re-enter the context window,
/// so the service caps them by construction.
final class FindItemsTool: Tool {
    let name = "find_items"
    let description = "Search the user's routines, exercises, supersets, or equipment libraries."

    @Generable
    struct Arguments {
        var kind: ChangeKindArg
        @Guide(description: "Case-insensitive name fragment")
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
            let kind = arguments.kind.changeEntity
            var muscle: MuscleGroup? = nil
            if let raw = arguments.muscleGroup {
                guard let mapped = ChangeArgs.muscleGroup(from: raw) else {
                    return "unknown muscleGroup \(raw)"
                }
                muscle = mapped
            }
            return services.dataService.findItems(
                kind: kind,
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

/// Every edit goes through here — and through the engine's validate →
/// resolve → tier pipeline. The tool's return string only steers the
/// model's narration; the preview/receipt cards it triggers are the
/// real record.
final class ProposeChangeTool: Tool {
    let name = "propose_change"
    let description = "Create, edit, or delete routines, exercises, supersets, schedules, or equipment libraries. The app validates, previews, and applies; you never apply anything yourself."

    typealias Arguments = ChangeArgs

    private weak var services: (any OperatorToolServices)?
    init(services: any OperatorToolServices) { self.services = services }

    func call(arguments: ChangeArgs) async throws -> String {
        let services = self.services
        return await MainActor.run {
            guard let services else { return "unavailable" }
            switch arguments.toSpec() {
            case .invalid(let reason):
                return "INVALID: \(reason)"
            case .spec(let spec):
                let outcome = services.engine.propose(spec)
                services.handle(outcome)
                return outcome.digest
            }
        }
    }
}

/// Tappable choices. Deliberately NON-blocking: the card renders, the
/// turn ends, and the tap arrives as the next user message — a held
/// continuation would wedge `isResponding` across a dismissed tray or
/// a killed app.
final class AskUserTool: Tool {
    let name = "ask_user"
    let description = "Show the user tappable choices when you need a decision. Then stop and wait."

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
