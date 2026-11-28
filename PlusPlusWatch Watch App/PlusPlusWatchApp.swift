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
            fixturePages(fixture)
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
        if let ended = workout.ended {
            FinishedPage(end: ended) { workout.dismissEnded() }
        } else if let live = workout.live, live.workoutSession.isInProgress {
            WorkoutPages(live: live, isPhoneAway: !workout.isPhoneInReach) { action in
                workout.tap(action)
            }
        } else {
            IdlePage()
        }
    }

    #if DEBUG
    /// A fixed state of the boards, for a screenshot.
    @ViewBuilder
    private func fixturePages(_ fixture: WatchFixture) -> some View {
        let (live, at) = fixture.live
        if fixture == .finished {
            FinishedPage(end: LinkEnd(live.finishing(at: at), at: at)) { }
        } else {
            WorkoutPages(
                live: live,
                frozenAt: options.freeze ? at : nil,
                isPhoneAway: fixture == .unreachable,
                page: WorkoutPages.Page(rawValue: options.page ?? "") ?? .set,
                isEnding: fixture == .endChoice,
                forcesDim: options.dim || fixture == .dimmed,
            ) { _ in }
        }
    }
    #endif
}

/// The workout's three pages, swiped between: its time, the set, and the whole workout. Read
/// each second of its clock, or once at `frozenAt`.
struct WorkoutPages: View {
    enum Page: String {
        case time
        case set
        case list
    }

    let live: LiveWorkout
    var frozenAt: Date?
    var isPhoneAway = false
    @State var page = Page.set
    @State var isEnding = false
    /// Draws wrist down whatever the wrist does: a screenshot's `-watchDim`.
    var forcesDim = false
    let act: (WorkoutAction) -> Void

    var body: some View {
        if let frozenAt {
            pages(at: frozenAt)
        } else {
            TimelineView(.periodic(from: live.workoutSession.clockStart, by: 1)) { context in
                pages(at: context.date)
            }
        }
    }

    private func pages(at date: Date) -> some View {
        TabView(selection: $page) {
            timePage(at: date)
                .tag(Page.time)
            setPage(at: date)
                .tag(Page.set)
            ListPage(name: live.watchTimePage(at: date).name, rows: live.watchList())
                .tag(Page.list)
        }
        .tabViewStyle(.page)
        .onChange(of: page) { isEnding = false }
        .environment(\.forcesDim, forcesDim)
    }

    @ViewBuilder
    private func timePage(at date: Date) -> some View {
        let time = live.watchTimePage(at: date)
        if isEnding {
            EndChoicePage(
                offersFinish: time.offersFinish,
                finish: { act(.finish) },
                discard: { act(.discard) },
            )
        } else {
            TimePage(page: time) {
                act(time.isPaused ? .resume : .pause)
            } end: {
                isEnding = true
            }
        }
    }

    @ViewBuilder
    private func setPage(at date: Date) -> some View {
        if let face = live.watchFace(at: date) {
            SetPage(face: face, isPhoneAway: isPhoneAway) { tap in
                act(tap.action(on: live))
            }
        } else {
            IdlePage()
        }
    }
}

extension EnvironmentValues {
    /// Draws wrist down whatever the wrist does, for a screenshot (`-watchDim`).
    @Entry var forcesDim = false
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
#endif
