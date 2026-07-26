import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's roots: Today, the three catalogs, and search (Dave, 2026-07-26).
///
/// The catalog cases are NOT four different screens — all four render the same
/// `CatalogScopeView`, and picking one only sets `scope`. Switching between them
/// is meant to read as one surface changing scope, which is why nothing in that
/// path re-mounts.
enum AppTab: String, CaseIterable {
    case today, routines, exercises, equipment
    /// It wears `Tab(role: .search)`, so the system renders it as the separated
    /// circle and morphs the bar into the search field when it's selected. The
    /// field narrows whichever catalog the scope is already on — selecting it
    /// deliberately leaves `scope` alone.
    case search

    var label: String { rawValue }
}

extension FindScope {
    /// The tab that selects this scope.
    var tab: AppTab {
        switch self {
        case .routines: return .routines
        case .exercises: return .exercises
        case .kit: return .equipment
        }
    }

    /// The scope a tab selects — `nil` for the two that don't pick one: Today
    /// (a timeline of derived state, not a list of typed items) and search
    /// (which keeps whatever scope you were already on).
    init?(tab: AppTab) {
        switch tab {
        case .routines: self = .routines
        case .exercises: self = .exercises
        case .equipment: self = .kit
        case .today, .search: return nil
        }
    }
}

/// v3 navigation root (#109): bottom tabs, creation contextual (each tab's
/// header + creates its own thing); the FAB menu and the History destination
/// are gone (Today's timeline subsumes history, #110).
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
/// The chrome is the SYSTEM'S (Dave, 2026-07-25), and the bar carries FIVE tabs
/// (Dave, 2026-07-26): Today · Routines · Exercises · Kit · Search. The
/// hand-drawn `AppBottomBar` is deleted; its three device bugs (content
/// scrolling through it unreadably, no home-indicator clearance, labels off a
/// common baseline) were all things a real tab bar does for free.
///
/// The catalogs spent one build as a scope you dialled on a bottom-accessory
/// wheel while the bar carried only Today and Search. They are tabs again —
/// but now that `CatalogScopeView` exists they are tabs over ONE screen, which
/// is what the two-tab round was really after. The scope control survives as
/// the accessory, and only while search is active: the rest of the time the tab
/// bar itself is the scope control, and two of them at once is one too many.
///
/// The accessory has two system-chosen placements, and `tabBarMinimizeBehavior`
/// is what moves between them: at the top of a scroll the bar is full and the
/// control sits in its own row ABOVE it; scrolling down minimizes the bar and it
/// goes INLINE with it. That is Podcasts' behaviour, and it is scroll-driven —
/// the app cannot pin a placement, only adapt to the one it's given.
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
    /// The query, and which catalog SEARCH is looking at. Both live here: the
    /// field is the system's (attached to the search tab) and the scope control
    /// is the tab bar's accessory, so both sit outside the surface they drive.
    ///
    /// `scope` only ever decides what the SEARCH tab shows — the three catalog
    /// tabs carry their own — and it follows whichever of them you last picked,
    /// so opening search narrows where you already were.
    @State private var query = ""
    @State private var scope: FindScope = .routines
    /// Whether search is the selected tab, as a value the app OWNS.
    ///
    /// `tab` is written by the system's selection binding, outside any
    /// animation transaction of ours, so driving the bar off it directly makes
    /// the catalog tabs vanish and the accessory appear with no motion. This
    /// mirror is set inside `withAnimation`, and both the tab hiding and the
    /// accessory read it — so they collapse and arrive as ONE movement
    /// (Dave, 2026-07-26).
    @State private var searchActive = false
    /// Where each catalog was last scrolled to, by scope, so opening search on
    /// the catalog you were browsing lands you where you already were rather
    /// than at the top (Dave, 2026-07-26).
    ///
    /// It has to live here because a `Tab`'s content is its own view tree: the
    /// Routines tab's list and a search tab dialled to routines are two
    /// different scroll views showing the same rows, and this is the only place
    /// both can see.
    @State private var scrollAnchors: [FindScope: AnyHashable] = [:]
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
        // BEFORE the selection, deliberately. While search is active the three
        // catalog tabs are hidden, and a landing selects one of them — so give
        // the bar them back first rather than asking it to select a tab that
        // isn't there. `onChange(of: tab)` would set this a beat too late, and
        // a dropped selection is a silent dead tap (the build-76 class).
        searchActive = false
        tab = newTab
    }

    /// The catalog, once, parameterized by which one. Every catalog tab and the
    /// search tab render THIS — there is one catalog screen in the app, and a
    /// tab only decides what it is looking at.
    ///
    /// The three catalog tabs pass their own scope as a literal rather than
    /// reading `scope`: a `Tab`'s content is its own view tree, so it would
    /// otherwise render one frame with the OUTGOING scope before
    /// `onChange(of: tab)` caught up — a flash of the previous catalog every
    /// switch. Search is the one that reads the state, which is the whole point
    /// of the state: it keeps the catalog you were already on.
    private func catalog(_ shown: FindScope, on appTab: AppTab) -> some View {
        CatalogScopeView(
            scope: shown,
            query: $query,
            tab: appTab,
            // Only the tab actually on screen may WRITE the anchor. All four
            // instances stay mounted, so an ungated setter would let three
            // lists nobody is looking at overwrite the position of the one
            // that is. Reading is unconditional — that's the restore.
            anchor: Binding(
                get: { scrollAnchors[shown] },
                set: { if tab == appTab { scrollAnchors[shown] = $0 } }
            )
        )
    }

    private var appContent: some View {
        // Today · Routines · Exercises · Kit · Search (Dave, 2026-07-26). The
        // three catalog tabs and the search tab all render THE SAME view: a tab
        // decides which catalog, never which screen, so moving between them
        // reads as one surface changing scope rather than four screens.
        TabView(selection: $tab) {
            // Operator's context: the tab line comes from the onChange below;
            // pushed details report (and clear) their own via .operatorContext.
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .routines) })
            }
            // The three catalog tabs step OUT of the bar while search is active
            // (Dave, 2026-07-26), which leaves Today as the one tab beside the
            // morphed field — not "whichever tab you came from". Scope is the
            // accessory's job in there, so three tabs saying the same thing
            // would be redundant anyway.
            //
            // ⚠️ `.hidden(_:)` and NOT an `if`: it PRESERVES the hidden tab's
            // state, where conditional rendering destroys and recreates it.
            // These tabs' navigation stacks and scroll positions have to
            // survive a trip through search.
            Tab(FindScope.routines.label, systemImage: FindScope.routines.symbolName, value: AppTab.routines) {
                catalog(.routines, on: .routines)
            }
            .hidden(searchActive)
            Tab(FindScope.exercises.label, systemImage: FindScope.exercises.symbolName, value: AppTab.exercises) {
                catalog(.exercises, on: .exercises)
            }
            .hidden(searchActive)
            // Labeled "Kit" (2026-07-20); the enum case stays `.equipment`.
            Tab(FindScope.kit.label, systemImage: FindScope.kit.symbolName, value: AppTab.equipment) {
                catalog(.kit, on: .equipment)
            }
            .hidden(searchActive)
            // The SEARCH ROLE (Dave, 2026-07-26: "the sort of search tab that
            // makes the search input expand out of it to the side"). The role is
            // a package deal — the system floats it apart as the separated
            // circle AND gives it the morph into the field — and the morph is
            // the half worth having. A plain tab seats search in the group but
            // leaves the field homeless: `.searchable` then wants the navigation
            // bar this screen hides, which is why build 135 had no visible input
            // at all. Only THIS tab carries the field, for the same reason.
            Tab(value: AppTab.search, role: .search) {
                catalog(scope, on: .search)
                    .searchable(text: $query, prompt: "Search \(scope.searchNoun)")
            }
        }
        // The scope control rides the accessory slot, and ONLY while search is
        // active (Dave, 2026-07-26) — the rest of the time the tab bar itself is
        // the scope control, and two of them at once would be one too many.
        //
        // The row's height change is the system's; the fade and rise are ours,
        // and they run on the same `searchActive` transaction that collapses
        // the catalog tabs, so the bar rearranges in one movement.
        .tabViewBottomAccessory(isEnabled: searchActive) {
            ScopeSegmentedAccessory(scope: $scope)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
        // What moves the accessory between its two placements: scrolled to the
        // top the bar is full and the control sits in its own row ABOVE it;
        // scrolling down minimizes the bar and it goes INLINE with it (where it
        // shows icons only — there is no room for words). The placement is the
        // system's to choose; the app only adapts.
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
            // Picking a catalog tab IS picking a scope, so search opens on the
            // catalog you were just looking at. Search itself sets nothing —
            // that's what makes it a narrowing of where you already are.
            if let picked = FindScope(tab: newTab) { scope = picked }
            // The query belongs to search and dies with it. Only the search tab
            // has a field, so a query that outlived it would leave a filtered
            // list with nothing on screen explaining the filter and no way to
            // clear it — the "stale invisible query reads as data loss" law.
            if newTab != .search { query = "" }
            // The bar's own rearrangement. `land(on:)` has already cleared this
            // on its path, so this is a no-op there and the animation is the
            // one that matters: entering search.
            withAnimation(Theme.Anim.standard) { searchActive = newTab == .search }
        }
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
