import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's roots. Search is NOT among them: it is a MODE over whichever
/// catalog you're in, so it adds a query rather than a destination.
enum AppTab: String, CaseIterable {
    case today, routines, exercises, equipment
    /// The native search-role item: the system renders it as the separated
    /// circle beside the tab group and morphs the bar into the search field
    /// when it's selected.
    case search

    var label: String { rawValue }
}

extension FindScope {
    /// The tab this scope is shown by. They are the same thing seen twice —
    /// the bar's middle group selects a tab, and that tab IS the scope.
    var tab: AppTab {
        switch self {
        case .routines: return .routines
        case .exercises: return .exercises
        case .kit: return .equipment
        }
    }

    /// The catalog a tab shows — `nil` for Today, which holds a timeline of
    /// derived state rather than a list of typed items.
    init?(tab: AppTab) {
        switch tab {
        case .routines: self = .routines
        case .exercises: self = .exercises
        case .equipment: self = .kit
        // Neither is a catalog: Today holds a timeline of derived state, and
        // the search tab holds the three scopes rather than being one.
        case .today, .search: return nil
        }
    }
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
/// The chrome is NESTED TabViews (Dave, 2026-07-25), and it is the system's
/// again — the hand-drawn `AppBottomBar` is deleted. Build 133's three device
/// bugs were scroll-edge legibility, home-indicator clearance and label
/// alignment: all three are things a real tab bar does for free, and paying
/// for them by hand a third time was the wrong trade.
///
/// OUTER bar: Today · Routines · Exercises · Kit · Search(role). INNER bar:
/// the same three catalogs, inside the search tab, riding above the field the
/// outer bar morphs into. While search is selected the three outer catalog
/// tabs are DROPPED from the builder — they are the inner bar now, and their
/// absence is what leaves Today alone beside the field. Today never moves: it
/// holds a timeline of derived state, not a list of typed items, so it is a
/// tab and never a scope.
///
/// The cost of nesting: a `Tab`'s content is its own view tree, so each
/// catalog exists twice — once as an outer tab (browsing, no query) and once
/// inside search (carrying the query). `CatalogScopeView.Hosting` tells the two
/// copies apart so only the outer one answers landings.
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
    /// The search query, and which scope the INNER bar is pointing at. Both
    /// live here because both outlive any one scope's view: switching scope
    /// mid-search has to keep what you typed.
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
    private func land(on newTab: AppTab) {
        query = ""
        tab = newTab
    }

    /// Entering search opens on the catalog you were already in — search
    /// narrows where you are, it doesn't relocate you. From Today (a tab, never
    /// a scope) it opens on whichever scope was last showing.
    @MainActor
    private func syncScope(entering newTab: AppTab) {
        if let entered = FindScope(tab: newTab) {
            scope = entered
        }
        // Leaving search drops the query: a stale invisible one reads as data
        // loss, and the outer catalogs deliberately browse unfiltered.
        if newTab != .search {
            query = ""
        }
    }

    /// A catalog as an OUTER tab: browsing, no query. The search tab hosts its
    /// own copy of the same three scopes, which is the one wrinkle of nesting —
    /// a `Tab`'s content is its own view tree, so a catalog reachable both as a
    /// tab and inside search exists twice. Only these outer ones answer
    /// landings, so an entrance flash can never play on the invisible copy.
    private func catalog(_ scope: FindScope) -> some View {
        CatalogScopeView(scope: scope, hosting: .tabRoot, query: .constant(""), isActive: tab == scope.tab)
    }

    /// The search tab: the INNER TabView. Its bar is the three catalogs the
    /// outer bar just gave up, and each scope carries the native `.searchable`
    /// — the field is per-scope, so its prompt names what it actually searches
    /// ("Search equipment" on Kit, the kit-vs-equipment vocabulary law).
    /// `.searchable` sits on `CatalogScopeView` because that view IS a
    /// `NavigationStack`, which the field needs in order to render at all.
    private var searchHost: some View {
        TabView(selection: $scope) {
            Tab(FindScope.routines.label, systemImage: FindScope.routines.symbolName, value: FindScope.routines) {
                searchScope(.routines)
            }
            Tab(FindScope.exercises.label, systemImage: FindScope.exercises.symbolName, value: FindScope.exercises) {
                searchScope(.exercises)
            }
            Tab(FindScope.kit.label, systemImage: FindScope.kit.symbolName, value: FindScope.kit) {
                searchScope(.kit)
            }
        }
    }

    private func searchScope(_ item: FindScope) -> some View {
        CatalogScopeView(scope: item, hosting: .searchTab, query: $query, isActive: scope == item)
            .searchable(text: $query, prompt: "Search \(item.searchNoun)")
            // Return opens the best hit. The field is the system's, so the key
            // travels as a signal to whichever scope is showing.
            .onSubmit(of: .search) {
                NotificationCenter.default.post(name: .plusplusOpenTopResult, object: nil)
            }
    }

    private var appContent: some View {
        // NESTED TabViews (Dave, 2026-07-25), replacing the hand-drawn bar:
        // the chrome goes back to the system, which owns the hit targets, the
        // accessibility, the Liquid Glass, the scroll-edge legibility and the
        // home-indicator clearance — the three things build 133's custom bar
        // got wrong were all of them.
        //
        // OUTER bar: Today · Routines · Exercises · Kit · Search.
        // INNER bar: the three catalogs again, inside the search tab, riding
        // above the field the outer bar morphs into.
        TabView(selection: $tab) {
            // Operator's context: the tab line comes from the onChange below;
            // pushed details report (and clear) their own line via
            // .operatorContext, so no tab-level reporter is attached here.
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { tab = .routines })
            }
            // While search is selected these three are ABSENT from the outer
            // bar. They haven't gone anywhere — they're the inner bar now — and
            // dropping them is what leaves Today as the one item beside the
            // search field (Dave's ask). Today itself never leaves: it is a
            // tab, never a scope.
            if tab != .search {
                Tab(FindScope.routines.label, systemImage: FindScope.routines.symbolName, value: AppTab.routines) {
                    catalog(.routines)
                }
                Tab(FindScope.exercises.label, systemImage: FindScope.exercises.symbolName, value: AppTab.exercises) {
                    catalog(.exercises)
                }
                // Labeled "Kit" (2026-07-20); the enum case stays `.equipment`.
                Tab(FindScope.kit.label, systemImage: FindScope.kit.symbolName, value: AppTab.equipment) {
                    catalog(.kit)
                }
            }
            Tab(value: AppTab.search, role: .search) {
                searchHost
            }
        }
        .tint(Theme.textPrimary)
        // Swipe-to-open is gated on the active tab being at its root; keep
        // the reveal controller told which tab is showing. Operator's
        // view-context follows the same signal (a tab switch also clears
        // a popped detail's stale line).
        .onChange(of: tab, initial: true) { oldTab, newTab in
            reveal.activeTab = newTab.rawValue
            viewContext.tab = newTab.rawValue
            viewContext.detail = nil
            // Seed the inner bar from the tab you came FROM when opening
            // search; clear the query when leaving it.
            syncScope(entering: newTab == .search ? oldTab : newTab)
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
            case .routine: land(on: .routines)
            case .exercisesTab: land(on: .exercises)
            case .equipmentTab: land(on: .equipment)
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
            land(on: .routines)
        }
        // The exercise/equipment twins (universal search): a create/add
        // lands on its list, same one-landing law.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusExerciseArrived)) { _ in
            land(on: .exercises)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plusplusEquipmentArrived)) { _ in
            land(on: .equipment)
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
