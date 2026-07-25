import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's four roots. Search is NOT among them (2026-07-25): it stopped
/// being a destination and became a MODE over whichever catalog you're in —
/// see `AppBottomBar`.
enum AppTab: String, CaseIterable {
    case today, routines, exercises, equipment

    var label: String { rawValue }
}

extension FindScope {
    /// The tab this scope was absorbed from.
    var tab: AppTab {
        switch self {
        case .routines: return .routines
        case .exercises: return .exercises
        case .kit: return .equipment
        }
    }

    /// The scope a tab searches — `nil` for Today, which is a tab, never a
    /// scope (it holds a timeline of derived state, not a list of items).
    init?(tab: AppTab) {
        switch tab {
        case .routines: self = .routines
        case .exercises: self = .exercises
        case .equipment: self = .kit
        case .today: return nil
        }
    }
}

/// v3 navigation root (#109): four bottom tabs — Today · Routines ·
/// Exercises · Equipment. Creation is contextual (each tab's header +
/// creates its own thing); the FAB menu and the History destination are
/// gone (Today's timeline subsumes history, #110).
///
/// 2026-07-25: the native `TabView` gave way to a ZStack of the four roots
/// under `AppBottomBar`, so search can absorb the three catalog tabs into its
/// field while Today keeps its place (the system morph is all-or-nothing and
/// can't express that). Each root keeps its OWN `NavigationStack`, so every
/// value destination stays registered where it was and per-tab navigation
/// state still survives switching — only the chrome changed. Roots stay
/// mounted and hide by opacity (never `if`, which would discard their paths);
/// hidden ones drop hit testing and accessibility, since `opacity(0)` alone
/// leaves both live (ui-interaction.md).
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
    /// Search is a MODE over the tabs, not a tab: while true the field is
    /// expanded, the three catalog scopes ride above it, and the Find-or-create
    /// surface covers the roots. All of it is ephemeral — leaving clears it.
    @State private var searching = false
    @State private var query = ""
    @State private var scope: FindScope = .routines
    @State private var fieldWantsFocus = false
    /// Per-scope result counts for the bar's labels. COMPUTED BY THE SEARCH
    /// SURFACE, not here: it already holds the catalog queries, so counting at
    /// the root would mean duplicate always-live `@Query`s whose every change
    /// re-evaluated the whole four-root tree, plus a fourth ranking pass per
    /// keystroke on top of the three the surface already runs.
    @State private var scopeCounts: [FindScope: Int] = [:]
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

    /// One root layer. Hidden roots stay MOUNTED (an `if` would discard the
    /// navigation path a tab switch is supposed to preserve) but drop hit
    /// testing and accessibility — `opacity(0)` removes neither on its own.
    @ViewBuilder
    private func root<Content: View>(
        _ value: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let visible = tab == value && !searching
        content()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            // Leaving a tab is still the natural boundary to push program
            // edits to GitHub — but these roots no longer unmount, so the
            // trigger has to key on hiding rather than on `onDisappear`
            // (which is why the roots' own `syncsProgramOnClose` came off).
            .syncsProgramOnHide(visible: visible)
    }

    /// Every landing leaves search first. A create made from the search
    /// surface lands on the tab that owns it (the one-landing law), and that
    /// landing has to be VISIBLE — left searching, the entrance flash would
    /// play behind the results covering it.
    @MainActor
    private func land(on newTab: AppTab) {
        query = ""
        withAnimation(Theme.Anim.selection) {
            searching = false
            tab = newTab
        }
    }

    private var appContent: some View {
        // The four roots, one visible at a time, under the bottom bar. This
        // replaced the native TabView so search can absorb three of the tabs
        // into its field while Today stays put (AppBottomBar explains why the
        // system morph can't). Each root keeps its own NavigationStack.
        ZStack {
            // Operator's context: the tab line comes from the onChange
            // below; pushed details report (and clear) their own line via
            // .operatorContext — a tab-level reporter would never re-fire
            // on a pop, so none is attached here.
            root(.today) {
                TodayView(onGoToRoutines: { tab = .routines })
            }
            root(.routines) {
                RoutineListView()
            }
            root(.exercises) {
                ExercisesTabView()
            }
            // Labeled "Kit" (2026-07-20): the tab shows your ACTIVE kit, and
            // the short word is guaranteed to fit the on-row heading beside
            // the switcher. The enum case / reveal signal stay `.equipment`
            // (frozen internal — see the vocabulary note).
            root(.equipment) {
                EquipmentTabView()
            }
            // Search covers the roots while active. Mounted only then, so its
            // stack and collapsed groups start fresh every time — the surface
            // is ephemeral by design (a stale invisible query reads as loss).
            if searching {
                FindOrCreateView(
                    query: $query,
                    scope: $scope,
                    fieldWantsFocus: $fieldWantsFocus,
                    counts: $scopeCounts
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppBottomBar(
                tab: $tab,
                searching: $searching,
                query: $query,
                scope: $scope,
                todaySymbol: todayStatus.systemImage,
                counts: scopeCounts,
                fieldWantsFocus: $fieldWantsFocus,
                onSubmit: { NotificationCenter.default.post(name: .plusplusOpenTopResult, object: nil) }
            )
        }
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
        // Search is a mode, so it reports itself the same way a tab does —
        // and hands the signal back to the underlying tab on the way out.
        .onChange(of: searching) { _, isSearching in
            reveal.activeTab = isSearching ? "search" : tab.rawValue
            viewContext.tab = isSearching ? "search" : tab.rawValue
            viewContext.detail = nil
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
        // A tab's Add row deep-links into search pre-scoped — the same mode
        // the bar's search key opens, just aimed at a scope up front.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusFindOrCreate)) { _ in
            if let pending = FindOrCreateLaunch.pending {
                FindOrCreateLaunch.pending = nil
                scope = pending
            }
            query = ""
            withAnimation(Theme.Anim.selection) {
                searching = true
            }
            fieldWantsFocus = true
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
