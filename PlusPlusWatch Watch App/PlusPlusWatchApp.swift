#if canImport(Session)
import SwiftUI
import WorkoutStore

/// The Watch app: one workout in progress, followed and logged from the wrist, with the phone.
/// It draws on the Watch's own black with PlusPlus's dark colors; the phone's look does not
/// reach it yet.
@main
struct PlusPlusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .preferredColorScheme(.dark)
        }
    }
}

/// The idle page with no workout, else the workout's pages.
struct WatchRoot: View {
    private let options = WatchLaunchOptions.current

    var body: some View {
        #if DEBUG
        if let fixture = options.fixture {
            let (live, at) = fixture.live
            WorkoutPages(live: live, frozenAt: options.freeze ? at : nil) { _ in }
                .environment(\.isLuminanceReduced, options.dim)
        } else {
            IdlePage()
        }
        #else
        IdlePage()
        #endif
    }
}

/// The set page of `live`, read each second of its clock, or once at `frozenAt`.
struct WorkoutPages: View {
    let live: LiveWorkout
    var frozenAt: Date?
    let tap: (SetPageTap) -> Void

    var body: some View {
        if let frozenAt {
            page(at: frozenAt)
        } else {
            TimelineView(.periodic(from: live.workoutSession.clockStart, by: 1)) { context in
                page(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func page(at date: Date) -> some View {
        if let face = live.watchFace(at: date) {
            SetPage(face: face, tap: tap)
        } else {
            IdlePage()
        }
    }
}
#endif
