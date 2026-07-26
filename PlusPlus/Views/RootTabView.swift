import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's two roots (Dave, 2026-07-25). The three catalogs stopped being
/// tabs: they are a SCOPE you dial on the wheel in the tab bar's bottom
/// accessory, so the bar carries only the two things that are genuinely
/// different places — a timeline of derived state, and everything you can look
/// something up in.
enum AppTab: String, CaseIterable {
    case today
    /// The catalogs. It wears `Tab(role: .search)`, so the system renders it as
    /// the separated circle and morphs the bar into the search field when it's
    /// selected — the field narrows whichever catalog the wheel is pointing at.
    case search

    var label: String { rawValue }
}

/// v3 navigation root (#109): four bottom tabs — Today · Routines ·
/// Exercises · Equipment. Creation is contextual (each tab's header +
/// creates its own thing); the FAB menu and the History destination are
/// gone (Today's timeline subsumes history, #110).
///
/// 2026-07-25: **the catalog tabs and the search scopes are the same three
/// views.** Tapping Routines with search closed and scoping to Routines with it
/// open land on one `CatalogScopeView` — search adds a query, it does not take
/// you to a different screen. The older `RoutineListView` /
/// `ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` are gone, their
/// swipes, reorder and creates absorbed into that one surface (their facet
/// chips deliberately were NOT — the three read alike now, and the field
/// reaches what the chips used to).
///
/// The chrome is the SYSTEM'S again (Dave, 2026-07-25), and the bar carries
/// two tabs: Today and Search. The three catalogs became a SCOPE you dial on
/// `ScopeWheelAccessory`, riding in the TabView's bottom accessory — the one
/// slot the system offers for app content beside its own bar. The hand-drawn
/// `AppBottomBar` is deleted; its three device bugs (content scrolling through
/// it unreadably, no home-indicator clearance, labels off a common baseline)
/// were all things a real tab bar does for free.
///
/// The accessory has two system-chosen placements, and `tabBarMinimizeBehavior`
/// is what moves between them: at the top of a scroll the bar is full and the
/// wheel sits ABOVE it; scrolling down minimizes the bar and the wheel goes
/// INLINE with it, which with two tabs reads as the wheel between Today and
/// Search. That is Podcasts' behaviour, and it is scroll-driven — the app
/// cannot pin a placement, only adapt to the one it's given.
struct RootTabView: View {

    /// The Today tab's icon reflects whether there's anything to do today
    /// (2026-07-24) — onboarding steps or scheduled workouts — so it lives
    /// at the root, computed from queries here (the icon must stay live
    /// even when Today isn't the front tab, so it can't wait on TodayView's
    /// body). Same finished-session filter and routine set TodayView reads.
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]
    @AppStorage(SetupState.equipmentDoneKey) private var equipmentDone = false
    /// Bumped on day change so the Today icon re-derives at midnight (the
    /// same guard TodayView uses against a resident app rendering
    /// yesterday's plan).
    @State private var dayToken = 0

    @State private var tab: AppTab = .today
    /// The query, and which catalog the wheel is pointing at. Both live here:
    /// the field is the system's (attached to the search tab) and the wheel is
    /// the tab bar's accessory, so both sit outside the surface they drive.
    @State private var query = ""
    @State private var scope: FindScope = .routines
    /// The slide-to-reveal drawer behind the ++ key (replaces the pushed
    /// AppMenuScreen). Lives here, above the tabs' NavigationStacks, so it
    /// moves the whole TabView as one layer.
    @State private var reveal = RevealController()
    /// What screen is frontmost, as one compact line — Operator's
    /// view-context (injected app-wide; screens report via
    /// `.operatorContext(_:)`).
    @State private var viewContext = ViewContext()
    /// The launch beat (splash + first-launch welcome, fused): a cold open
    /// always opens on the `++` mark; `introShowsWelcome` decides whether
    /// it settles into the welcome content or dissolves straight to Today.
    @State private var showingIntro: Bool
    private let introShowsWelcome: Bool
    private let introInstant: Bool
    /// A share link the app was opened with, awaiting import (#145).
    @State private var shareImport: ShareImport?
    /// A tapped share link whose payload couldn't be read — said out
    /// loud, never silently dropped (design review 2026-07-23).
    @State private var showShareLinkError = false
    /// Post-install return from GitHub (the Setup-URL bounce, #23): present
    /// the connect step so the user just authorizes.
    @State private var showGitHubConnect = false
    /// #155: the store couldn't be opened and was reset this launch. Read
    /// once at init (the flag is set during app init, before any view), so
    /// we tell the user rather than pretending nothing happened.
    @State private var showStoreResetNotice: Bool

    init() {
        // The launch beat: a cold open ALWAYS opens on the ++ mark
        // (IntroView), then the app. On first launch the same mark settles
        // into the welcome content; on later launches it just holds a beat
        // and dissolves to Today. Everyone lands on Today — a fresh
        // install's timeline IS the onboarding (setup steps render as gated
        // entries there).
        let welcome = !SetupState.welcomeSeen
        let uitest = CommandLine.arguments.contains("--uitest-reset")
        // Under UI test the pure-splash (returning-user) case is skipped so
        // the smoke suite lands on the tabs immediately; the welcome test
        // still gets its screen (it forces welcomeSeen false).
        _showingIntro = State(initialValue: welcome || !uitest)
        introShowsWelcome = welcome
        introInstant = uitest
        _showStoreResetNotice = State(initialValue: SetupState.storeWasReset)
    }

    /// The Today tab's icon: dashed-open when work waits, filled-checkmark
    /// when today's work is done, plain-open when the day held nothing.
    private var todayStatus: TodayStatus {
        _ = dayToken
        return TodayStatus.current(
            routines: routines,
            sessions: finishedSessions,
            equipmentDone: equipmentDone,
            today: Date(),
            calendar: .current
        )
    }

    var body: some View {
        // The whole app rides inside the reveal drawer: tapping ++ slides
        // this TabView aside to uncover the app surface beneath it.
        RevealContainer(controller: reveal) {
            appContent
        }
        // Injected here so BOTH layers see it: the tabs report context,
        // the reveal surface (Operator) reads it.
        .environment(viewContext)
    }

    /// A landing leaves search first: a create lands on the catalog that owns
    /// it (the one-landing law), and that landing has to be VISIBLE — left
    /// searching, the entrance flash would play behind a filtered list.
    @MainActor
    private func land(on newTab: AppTab, scope newScope: FindScope? = nil) {
        query = ""
        if let newScope { scope = newScope }
        tab = newTab
    }

    /// One root layer. Hidden roots stay MOUNTED (an `if` would discard the
    /// navigation path a tab switch is supposed to preserve) but drop hit
    /// testing and accessibility — `opacity(0)` removes neither on its own.
    @ViewBuilder
    private func root<Content: View>(
        _ visible: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            // Leaving a catalog is still the boundary that pushes program
            // edits to GitHub, but these roots no longer unmount, so the
            // trigger keys on hiding rather than on `onDisappear`.
            .syncsProgramOnHide(visible: visible)
    }

    private var appContent: some View {
        // TWO tabs, and the chrome is the system's (Dave, 2026-07-25). The
        // hand-drawn bar is gone: build 133's three device bugs — content
        // scrolling through it unreadably, no clearance above the home
        // indicator, labels off a common baseline — were all things a real tab
        // bar does for free.
        TabView(selection: $tab) {
            // Operator's context: the tab line comes from the onChange below;
            // pushed details report (and clear) their own via .operatorContext.
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .search, scope: .routines) })
            }
            // A PLAIN tab, deliberately not `Tab(role: .search)` (Dave,
            // 2026-07-25): the role is what makes the system render search as
            // the separated floating circle, so dropping it is what seats it in
            // the group beside Today. The role also owned the bar→field morph,
            // so the field has to come from somewhere else — see
            // `CatalogScopeView`'s bottom-bar search item.
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                // ONE catalog at a time — the wheel picks which. `.id(scope)`
                // is load-bearing: without it SwiftUI reuses the view across a
                // scope change and the previous catalog's navigation path,
                // expanded groups and arrival slot come along with it.
                CatalogScopeView(scope: scope, query: $query, isActive: true)
                    .id(scope)
            }
        }
        // The scope picker rides the accessory slot — the one place the system
        // agrees to put app content beside its own bar. It shows on BOTH tabs
        // (Dave, 2026-07-25), so picking a catalog from Today is possible; the
        // picker therefore also switches to the tab that shows catalogs, since
        // the segmented value only ever means "which catalog", never "where
        // you are".
        .tabViewBottomAccessory {
            ScopeSegmentedAccessory(scope: $scope) { tab = .search }
        }
        // What moves the accessory between its two placements: scrolled to the
        // top the bar is full and the picker sits in its own row ABOVE it;
        // scrolling down minimizes the bar and the picker goes INLINE with it,
        // which with two tabs reads as the picker between Today and Search. The
        // placement is the system's to choose — the app only adapts.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.textPrimary)
        // Swipe-to-open is gated on the active tab being at its root; keep
        // the reveal controller told which tab is showing. Operator's
        // view-context follows the same signal (a tab switch also clears
        // a popped detail's stale line).
        .onChange(of: tab, initial: true) { _, newTab in
            reveal.activeTab = newTab.rawValue
            viewContext.tab = newTab.rawValue
            viewContext.detail = nil
        }
        // Nothing to report when search opens: it doesn't change which surface
        // is showing, only what that surface is narrowed to. The drawer's
        // swipe gate and Operator's view-context both stay on the tab.
        // Operator's outcome navigation: the root switches tabs; the
        // owning tab root resolves and pushes (the .plusplusStartRoutine
        // pattern). The drawer closes too, so a half-height Operator
        // tray shows the result landing behind it live (Dave, build-85
        // round) — and dismissing the tray lands on the result, not the
        // drawer.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { note in
            guard let destination = note.object as? OperatorDestination else { return }
            switch destination {
            case .today: land(on: .today)
            case .routine: land(on: .search, scope: .routines)
            case .exercisesTab: land(on: .search, scope: .exercises)
            case .equipmentTab: land(on: .search, scope: .kit)
            }
            reveal.close()
        }
        .overlay {
            if showingIntro {
                IntroView(showWelcome: introShowsWelcome, instant: introInstant) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showingIntro = false
                    }
                }
                .transition(.opacity)
            }
        }
        // plusplus://r#… (and, once universal links land, the https
        // viewer URL) opens the import preview. A bad payload is
        // ignored — the viewer webpage is the place that explains.
        .onOpenURL { url in
            // Widget taps land on Today (#147).
            if url.scheme == RoutineShareLink.appScheme, url.host == "today" {
                land(on: .today)
                return
            }
            // Post-install bounce from GitHub (plusplus://github/connected):
            // present the connect step, which auto-starts the device flow.
            if url.scheme == RoutineShareLink.appScheme, url.host == "github" {
                showGitHubConnect = true
                return
            }
            // A calendar event's start link (plusplus://start/<name>, #333):
            // hand off to the same pathway Siri's StartRoutineIntent uses —
            // TodayView resolves the name and starts the session, the root
            // switches to Today.
            if let name = WorkoutCalendarLink.routineName(from: url) {
                NotificationCenter.default.post(name: .plusplusStartRoutine, object: name)
                return
            }
            if RoutineShareLink.isShareLink(url) {
                if let payload = try? RoutineShareLink.payload(from: url) {
                    shareImport = ShareImport(payload: payload)
                } else {
                    // A raw plusplus://r#… link pasted in Messages/Notes has
                    // no viewer webpage to explain a bad payload — say it
                    // here instead of swallowing the tap (design review
                    // 2026-07-23).
                    showShareLinkError = true
                }
            }
        }
        // Universal-link form of the same GitHub Setup-URL return
        // (https://plusplus.fit/github/…), for when it opens the app directly.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if url.path == "/github/connected" || url.path.hasPrefix("/github/") {
                showGitHubConnect = true
            } else if let name = WorkoutCalendarLink.routineName(from: url) {
                // https://plusplus.fit/start/<name> — the universal-link
                // form of a calendar event's start link (#333).
                NotificationCenter.default.post(name: .plusplusStartRoutine, object: name)
            }
        }
        // Siri/Shortcuts "Start Routine" (#147): the intent posts, the
        // root switches to Today, and Today starts the session.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusStartRoutine)) { _ in
            land(on: .today)
        }
        // Re-derive the Today icon at midnight — a resident app would
        // otherwise keep yesterday's due list (the same day-rollover guard
        // TodayView carries).
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            dayToken += 1
        }
        // A routine added from outside the Routines tab (Today's setup
        // step, a share import) lands ON the Routines list with the
        // entrance flash — one landing for every add (Dave, 2026-07-23).
        .onReceive(NotificationCenter.default.publisher(for: .plusplusRoutineArrived)) { _ in
            land(on: .search, scope: .routines)
        }
        // The exercise/equipment twins (universal search): a create/add
        // lands on its list, same one-landing law.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusExerciseArrived)) { _ in
            land(on: .search, scope: .exercises)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plusplusEquipmentArrived)) { _ in
            land(on: .search, scope: .kit)
        }
        // Closing a finished workout's recap goes home: whatever screen
        // presented the session cover, the finish lands on Today, where
        // the just-committed card converts itself to done.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusWorkoutFinished)) { _ in
            land(on: .today)
        }
        .sheet(item: $shareImport) { item in
            ShareImportSheet(payload: item.payload)
                .presentationDetents([.large])
        }
        .alert("That link couldn't be read", isPresented: $showShareLinkError) {
            Button("OK") {}
        } message: {
            Text("It may be incomplete or from a newer version of PlusPlus.")
        }
        .sheet(isPresented: $showGitHubConnect) {
            GitHubSyncTray(startAtConnect: true)
        }
        // #155: never a silent wipe. If the store couldn't be opened and
        // was reset this launch, say so plainly (calm, no blame) and note
        // the saved backup. One-shot: the flag clears on dismiss.
        .alert("Your data was reset", isPresented: $showStoreResetNotice) {
            Button("OK") { SetupState.clearStoreResetFlag() }
        } message: {
            Text(SetupState.storeResetBackupSaved
                 ? "PlusPlus couldn't open your saved data, so it started fresh. A copy of the old data was saved to the Files app in case it can be recovered."
                 : "PlusPlus couldn't open your saved data, so it started fresh.")
        }
    }

}

/// The ++ glyph anchoring every tab header, top-left — the one place
/// the brand green appears in chrome.
struct HeaderGlyph: View {
    var body: some View {
        Text("++")
            .font(.system(.subheadline, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
    }
}

/// The ++ wearing its key — every root header's top-left opens the app
/// surface (Dave, build 44: "every root view, not just Today"). The glyph
/// stays brand green — content is the brand, the key says "press me". It no
/// longer pushes onto a tab's stack; it toggles the shared reveal drawer,
/// which slides the whole app aside to uncover the surface beneath.
struct AppMenuKey: View {
    @Environment(RevealController.self) private var reveal

    var body: some View {
        Button { reveal.toggle() } label: {
            HeaderGlyph()
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel("Menu")
        .accessibilityHint(reveal.isOpen ? "Closes the menu" : "Opens the menu and settings")
        .accessibilityIdentifier("appMenuButton")
    }
}
