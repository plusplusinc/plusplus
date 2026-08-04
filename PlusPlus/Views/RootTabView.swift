import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's TWO roots (Dave, 2026-08-04): Today, and Search.
///
/// Routines · Exercises · Kit are gone as destinations — not hidden, replaced.
/// A catalog with an EMPTY query has always been that catalog's whole list
/// (`catalog-scopes.md`), and all three have rendered one `CatalogScopeView`
/// since 2026-07-25, so the search surface dialled to Routines *is* the
/// Routines list. The scope bar is what a tab tap used to be.
///
/// The type keeps its name so the diff stays reversible. Its raw values are the
/// drawer's swipe-gate keys; `FindScope.contextKey` separately carries the
/// three RETIRED raw values on for Operator's view-context. ⚠️ Two different
/// key spaces — see the `onChange` pair below.
enum AppTab: String, CaseIterable {
    case today, search

    var label: String { rawValue }
}

/// The navigation root (#109): creation is contextual (each surface creates its
/// own thing); the FAB menu and the History destination are gone (Today's
/// timeline subsumes history, #110).
///
/// 2026-07-25: **the catalogs and the search scopes are the same three views.**
/// Scoping to Routines lands on one `CatalogScopeView` — search adds a query,
/// it does not take you to a different screen. The older `RoutineListView` /
/// `ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` are gone, their
/// swipes, reorder and creates absorbed into that one surface.
///
/// **2026-08-04 — the tab bar is GONE, and with it the scope control's whole
/// placement problem.** Surface selection is a vertical list at the top of the
/// reveal drawer (`DrawerNavList`), plus a floating key on Today; scope
/// selection is NATIVE `.searchScopes`. Native scopes were retired on builds
/// 140–143 because they render exactly once per app run **on a bottom-morphed
/// field** — and the morph was `Tab(role: .search)`'s. No tab bar, no morph, no
/// bottom field: the scope bar takes its ordinary top placement.
/// `ScopeSegmentedControl` survives unused as the fallback if that bet is wrong
/// on device.
///
/// ⚠️ The retired mechanisms stay retired and are NOT to be re-tried on their
/// old terms: `tabViewBottomAccessory` (137–139, 144 — never rises with the
/// keyboard), a `.bottomBar` `ToolbarItem` (145), a top `safeAreaInset` under
/// the bar (147). They were all answers to "where does the scope control go
/// when the field is at the bottom", and that question no longer exists.
struct RootTabView: View {

    @State private var tab: AppTab = .today
    /// The query, and which catalog the search surface is looking at. Both live
    /// here rather than in `CatalogScopeView` so a landing that switches
    /// surfaces can clear them — a stale invisible query reads as data loss.
    ///
    /// `scope` is the app's memory of which catalog you were last in, so
    /// re-opening search opens where you left off.
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
    /// The GitHub tray, and WHICH door opened it. ⚠️ ONE `@State` behind
    /// ONE `.sheet(item:)`, never two booleans behind two sheets (#509
    /// review): a view can only present one sheet, so a second request
    /// arriving while the first is up is silently dropped AND latches its
    /// flag true — after which every later request is a no-op assignment
    /// and the post-install auto-return is dead until relaunch.
    ///
    /// That is not a hypothetical ordering: the commonest repair for a
    /// broken sync is re-installing the Sync App, `openInstall()` leaves
    /// the app on purpose so the Setup URL can bounce back, and the bounce
    /// lands while the tray the user opened from Today is still on screen.
    /// As an item, a second request REPLACES the first instead of racing it.
    /// `RevealSurface`'s two-sheet pair has a pending-queue for the same
    /// reason; this one has a single slot, which is simpler and enough.
    enum GitHubSheet: String, Identifiable {
        /// Post-authorize return from github.com — opens on the connect step.
        case connect
        /// Today's broken-sync advisory, and any other plain entry: the tray
        /// where it seats itself. That is decided by whether this device
        /// holds a token, not by which door opened it (#509, Q18-A) — a
        /// broken sync has none, so it lands on step 1, which is the only
        /// thing that can help it.
        case tray
        var id: String { rawValue }
    }
    @State private var githubSheet: GitHubSheet?
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

    var body: some View {
        // The whole app rides inside the reveal drawer: tapping ++ slides
        // this TabView aside to uncover the app surface beneath it.
        RevealContainer(controller: reveal) {
            routedAppContent
        }
        // Injected here so BOTH layers see it: the tabs report context,
        // the reveal surface (Operator) reads it.
        .environment(viewContext)
    }

    /// A landing leaves search first: a create lands on the catalog that owns
    /// it (the one-landing law), and that landing has to be VISIBLE — left
    /// searching, the entrance flash would play behind a filtered list.
    @MainActor
    /// A share link from anywhere — a tapped URL or a pasted one (#509,
    /// b17). One handler, so both entry points fail the same way.
    private func openShareLink(_ url: URL) {
        guard RoutineShareLink.isShareLink(url) else { return }
        if let payload = try? RoutineShareLink.payload(from: url) {
            shareImport = ShareImport(payload: payload)
        } else {
            // A raw plusplus://r#… link pasted in Messages/Notes has no
            // viewer webpage to explain a bad payload — say it here instead
            // of swallowing the tap (design review 2026-07-23).
            showShareLinkError = true
        }
    }

    /// Land on a surface, optionally dialling the catalog first.
    ///
    /// ⚠️ The scope is set BEFORE the surface, not after: the search surface
    /// reads `scope` when it builds, so assigning the other way round renders
    /// one frame of the outgoing catalog — the flash the three literal-scope
    /// tabs used to exist to avoid. There is only one instance now, so
    /// ordering is what replaces them.
    ///
    /// The query always dies here. A landing has to be VISIBLE (the
    /// one-landing law): left filtered, the entrance flash would play behind
    /// a query the user can no longer see.
    private func land(on newTab: AppTab, scope newScope: FindScope? = nil) {
        if let newScope { scope = newScope }
        query = ""
        tab = newTab
    }

    private var appContent: some View {
        // TWO roots: Today and Search (Dave, 2026-08-04). The catalogs are the
        // search surface's SCOPES now — an empty query has always shown the
        // scope's whole list, so nothing was lost by retiring their tabs.
        //
        // ⚠️ Still a `TabView`, with the bar HIDDEN, rather than a `switch` on
        // `tab`. A switch re-mounts, and re-mounting Today drops its push stack
        // and its scroll position on every round trip through search — plus
        // `TodayView` is the app's most expensive body. `TabView` keeps both
        // roots alive, builds each on first selection, and leaves the whole
        // landing/arrival machinery below untouched.
        //
        // ⚠️ The hide is applied to each root's CONTENT, not to the `TabView`
        // (`.toolbarBackground` at the TabView level is a documented iOS 26
        // no-op, and visibility is the same family). If a residual bottom inset
        // or a glass sliver survives on device, the next two things to try, in
        // order, are moving this inside each root's own `NavigationStack` and
        // falling back to the `switch`.
        TabView(selection: $tab) {
            // Operator's context: the surface line comes from the onChange
            // below; pushed details report (and clear) their own via
            // .operatorContext. The label and symbol are for the accessibility
            // tree only — nothing draws them once the bar is hidden. The Today
            // STATUS icon moved to `DrawerNavList`, which is where a user now
            // sees it.
            Tab("Today", systemImage: "calendar", value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .search, scope: .routines) })
                    .toolbar(.hidden, for: .tabBar)
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                // The field and the scope bar are NOT attached here. They go
                // INSIDE `CatalogScopeView`'s own `NavigationStack` — see its
                // `searchScope` note. Build 140 attached them out here and the
                // scope bar never appeared: `.searchScopes` needs `.searchable`
                // on a view inside a navigation container, and out here the
                // modifier lands above that stack.
                CatalogScopeView(scope: scope, query: $query, tab: .search, searchScope: $scope)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .tint(Theme.textPrimary)
        // Swipe-to-open is gated on the active surface being at its root; keep
        // the reveal controller told which one is showing. Operator's
        // view-context follows the same signal (a surface switch also clears a
        // popped detail's stale line).
        //
        // ⚠️ The two keys are NOT the same string. The reveal gate keys on the
        // SURFACE ("today"/"search"), matching what each root reports through
        // `revealRoot(tab:)`. Operator's context keys on the CATALOG
        // ("routines"/"exercises"/"equipment"), because that is the line
        // `OperatorChips` reads and those three strings are frozen.
        .onChange(of: tab, initial: true) { _, newTab in
            reveal.activeTab = newTab.rawValue
            reveal.activeScope = scope.rawValue
            viewContext.tab = newTab == .today ? "today" : scope.contextKey
            viewContext.detail = nil
        }
        // Operator's outcome navigation: the root switches surface and dials
        // the scope; the search root resolves and pushes (the
        // .plusplusStartRoutine pattern). The drawer closes too, so a
        // half-height Operator tray shows the result landing behind it live
        // (Dave, build-85 round) — and dismissing the tray lands on the
        // result, not the drawer.
        //
        // ⚠️ `OperatorDestination`'s case names are PERSISTED thread data
        // (they round-trip through the receipt's Codable), so they still say
        // "Tab" for surfaces that no longer exist. Renaming them is a stored
        // -data migration, not a refactor. The mapping lives here instead.
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
    }

    /// ⚠️ The URL/notification routing and every app-level presentation live
    /// in their OWN `some View`, split off `appContent` (CI, 2026-08-02).
    /// That chain is ~230 lines of modifiers on one expression and it went
    /// over the type-checker's budget outright — "unable to type-check this
    /// expression in reasonable time" — the moment the GitHub sheet became
    /// an `item:` presentation with a ternary in its builder. Same budget
    /// `TodayView.committedHistory` was extracted for. A `some View`
    /// boundary is what keeps it checkable, so anything added here from now
    /// on belongs BELOW this line, not above it.
    private var routedAppContent: some View {
        appContent
        // Dialling the scope bar is a destination change now, not a filter, so
        // Operator's line follows it the way it used to follow a tab tap.
        //
        // ⚠️ BELOW the split, per the law above — the two `onChange`s this
        // change added went in beside `onChange(of: tab)` first, which read
        // naturally and broke the rule. `appContent` shed three `Tab` builders
        // here, so it very likely had room; "very likely" is not what a budget
        // law is for, and the failure mode is a red `test` job a Linux
        // `swiftc -parse` cannot see.
        .onChange(of: scope) { _, newScope in
            // The drawer's row highlight follows the scope even off the
            // catalog root, so re-opening the drawer from Today still shows
            // which catalog you would return to.
            reveal.activeScope = newScope.rawValue
            guard tab == .search else { return }
            viewContext.tab = newScope.contextKey
            viewContext.detail = nil
        }
        // The drawer's nav list, and Today's floating search key, both land
        // here. A plain in-process slot rather than a notification: this view
        // is always mounted, so there is nobody to miss the signal, and the
        // controller already reaches both layers.
        .onChange(of: reveal.requestedSurface) { _, request in
            guard let request else { return }
            land(on: request.surface, scope: request.scope)
            reveal.requestedSurface = nil
            reveal.close()
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
                githubSheet = .connect
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
            openShareLink(url)
        }
        // The Data tray's paste (#509, b17) lands in the SAME handler a tap
        // does — so an unreadable payload gets the one explanation that
        // already exists rather than a second, quieter failure path.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusPastedShareLink)) { note in
            (note.object as? URL).map(openShareLink)
        }
        // Today's broken-sync advisory (#509, Q19-A). ⚠️ It presents the
        // tray DIRECTLY rather than opening the drawer and asking
        // `RevealSurface` to raise it (review). The drawer route needed a
        // second receiver over there, a sleep long enough to clear the
        // drawer's spring (a magic number Reduce Motion falsifies, since a
        // reduced open finishes early), and a cross-layer write into that
        // view's own presentation state — which its tray queue would fight
        // if anything else were already up. One receiver, one sheet, and
        // the user lands where the card promised instead of watching the
        // app slide aside first.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOpenSyncTray)) { _ in
            githubSheet = .tray
        }
        // Universal-link form of the same GitHub Setup-URL return
        // (https://plusplus.fit/github/…), for when it opens the app directly.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if url.path == "/github/connected" || url.path.hasPrefix("/github/") {
                githubSheet = .connect
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
        // A routine added from outside the routines catalog (Today's setup
        // step, a share import) lands ON the routines list with the
        // entrance flash — one landing for every add (Dave, 2026-07-23).
        // The landing is the search surface dialled to that scope now; the
        // list it shows is the same list it always was.
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
        .sheet(item: $githubSheet) { which in
            GitHubSyncTray(startAtConnect: which == .connect)
                // The same ground the drawer's trays wear. This route is
                // an everyday one from the home surface now, so a system
                // sheet background here would be the one place the warm
                // charcoal drops out (#509 review).
                .presentationCornerRadius(Theme.sheetRadius + 2)
                .presentationBackground(Theme.background)
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
