#if canImport(Session)
import Session
import SwiftUI
import WorkoutStore

/// The Watch app: one workout in progress, followed and logged from the wrist, with the phone.
/// It draws on the Watch's own black with PlusPlus's dark colors; the phone's look does not
/// reach it yet.
@main
struct PlusPlusWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRoot(workout: delegate.workout)
                .preferredColorScheme(.dark)
        }
    }
}

/// The idle page with no workout, the workout's pages while one runs, and the finished page
/// after.
struct WatchRoot: View {
    let workout: WatchWorkout
    private let options = WatchLaunchOptions.current

    var body: some View {
        #if DEBUG
        if let fixture = options.fixture {
            let (live, at) = fixture.live
            WorkoutPages(live: live, frozenAt: options.freeze ? at : nil) { _ in }
                .environment(\.isLuminanceReduced, options.dim)
        } else {
            running
                .onAppear {
                    if options.state == "demo", workout.live == nil {
                        workout.runAlone(WatchFixture.demo)
                    }
                }
        }
        #else
        running
        #endif
    }

    @ViewBuilder
    private var running: some View {
        if let live = workout.live, live.workoutSession.isInProgress {
            WorkoutPages(live: live, isPhoneAway: !workout.isPhoneInReach) { tap in
                workout.tap(tap.action(on: live))
            }
        } else {
            IdlePage()
        }
    }
}

extension SetPageTap {
    /// The action the key asks of `live`.
    func action(on live: LiveWorkout) -> WorkoutAction {
        switch self {
        case .log, .logEarly: live.currentSet.map(WorkoutAction.log) ?? .resume
        case .skipRest: .skipRest
        case .extendRest: .extendRest(by: 15)
        case .finish: .finish
        case .resume: .resume
        }
    }
}

/// The set page of `live`, read each second of its clock, or once at `frozenAt`.
struct WorkoutPages: View {
    let live: LiveWorkout
    var frozenAt: Date?
    var isPhoneAway = false
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
            SetPage(face: face, isPhoneAway: isPhoneAway, tap: tap)
        } else {
            IdlePage()
        }
    }
}
#endif
