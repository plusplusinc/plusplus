import Foundation
import AppIntents

/// The App Intents vocabulary (#147): one definition, six surfaces —
/// Siri, Shortcuts, the Action button, Control Center, interactive
/// widgets, Spotlight. Intents stay data-light by reading the widget
/// snapshot instead of the SwiftData stack; StartRoutine hands off to
/// the running app through a notification.

extension Notification.Name {
    /// Posted by StartRoutineIntent with the routine name as `object`.
    static let plusplusStartRoutine = Notification.Name("plusplusStartRoutine")
}

struct RoutineEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine")
    static let defaultQuery = RoutineEntityQuery()

    /// Identity IS the name (#32) — same rule as everywhere else.
    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct RoutineEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        let names = WidgetSnapshot.load()?.routineNames ?? []
        return identifiers.filter(names.contains).map { RoutineEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        (WidgetSnapshot.load()?.routineNames ?? []).map { RoutineEntity(id: $0) }
    }
}

struct StartRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Routine"
    static let description = IntentDescription("Opens PlusPlus and starts a workout from one of your routines.")
    static let openAppWhenRun = true

    @Parameter(title: "Routine")
    var routine: RoutineEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .plusplusStartRoutine, object: routine.id)
        return .result()
    }
}

struct DueTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Due Today"
    static let description = IntentDescription("Tells you which routines are due today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let due = WidgetSnapshot.load()?.due ?? []
        let dialog: IntentDialog
        switch due.count {
        case 0:
            dialog = "Rest day — nothing due."
        case 1:
            dialog = "\(due[0].name) is due — \(due[0].exerciseCount) exercises."
        default:
            dialog = "\(due.count) routines are due: \(due.map(\.name).joined(separator: ", "))."
        }
        return .result(dialog: dialog)
    }
}

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    static let description = IntentDescription("Opens PlusPlus to the Today timeline.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct PlusPlusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start a routine in \(.applicationName)",
                "Start my workout in \(.applicationName)",
            ],
            shortTitle: "Start Routine",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: DueTodayIntent(),
            phrases: [
                "What's due in \(.applicationName)",
                "What's my workout today in \(.applicationName)",
            ],
            shortTitle: "Due Today",
            systemImageName: "smallcircle.filled.circle"
        )
    }
}
