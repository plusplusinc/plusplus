import SwiftUI
import SwiftData
import UIKit
import PlusPlusKit

/// The single GitHub sync surface (#23 flow redesign): one tray that carries
/// the whole story instead of a status tray pushing a separate connect screen.
///
/// Not connected, it runs a three-step wizard: **authorize this device, create
/// a repo, install the PlusPlus Sync App on it.** Connected, it offers only
/// Disconnect.
///
/// ⚠️ Authorize comes FIRST, and that reorder is the whole point (#509,
/// Q18-A). The old order put it last, so create-repo and install were
/// "Done? Continue" with nothing checking them and the first real
/// verification ran only after the full device-flow round trip — whoever
/// missed the install found out last, via a generic error, having already
/// paid for the code entry. With a token in hand the install becomes
/// checkable: step 3 asks GitHub, names the repo it found ("installed on
/// owner/repo"), and gates Finish on that answer. It re-checks whenever the
/// app comes back to the foreground, which is exactly when the user returns
/// from installing.
///
/// Repo creation stays honor-system on purpose: the Contents-only App can
/// only ever see repos it is installed on, so an uninstalled repo is
/// invisible to us. The install check covers both — you cannot install on a
/// repo that doesn't exist.
struct GitHubSyncTray: View {
    /// Auto-start the device flow on arrival, for the post-install bounce.
    ///
    /// ⚠️ Consulted ONLY when this device has no token (#509, Q18-A): with
    /// one, the token decides where you land and the install check tells
    /// you the rest. Since the reorder authorizes FIRST, the real
    /// post-install bounce always has a token and never reads this — it
    /// survives for the case where a bounce somehow arrives without one.
    var startAtConnect: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw = WeightUnit.lb.rawValue

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var step: Step = .authorize
    @State private var connectTask: Task<Void, Never>?
    @State private var didInit = false
    @State private var codeCopied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var browser: BrowserURL?
    /// The authorizing card (a tall monospaced code + "Open GitHub") can fall
    /// below the fold at `.medium`; expand to `.large` while it's up so the
    /// one action the user needs stays visible.
    @State private var detent: PresentationDetent = .medium
    /// Direction of the last step change, so the slide transition reads
    /// right-to-left going forward and left-to-right going Back.
    @State private var advancing = true
    /// Step 3's live install check and the task running it.
    @State private var installCheck: InstallCheck = .idle
    @State private var installCheckTask: Task<Void, Never>?
    @State private var finishing = false
    /// Re-check the install whenever the app returns from GitHub — the
    /// install step opens EXTERNALLY, so coming back IS the moment the
    /// answer changes.
    @Environment(\.scenePhase) private var scenePhase

    enum Step: Int { case authorize = 1, createRepo = 2, install = 3 }

    /// The live verdict on step 3 (#509, Q18-A).
    enum InstallCheck: Equatable {
        case idle
        case checking
        case installed(GitHubRepoCoordinate)
        case notInstalled
        case failed(String)
    }

    struct BrowserURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

    private var activityError: String? {
        if case .error(let message) = sync.activity { return message }
        return nil
    }

    private var isAuthorizing: Bool {
        if case .authorizing = sync.activity { return true }
        return false
    }

    var body: some View {
        NavigationStack {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keep your data in sync with a GitHub repo")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    description
                    actions
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .padding(.horizontal, 18)
            }
        }
        .sheetChrome(title: "GitHub sync", done: SheetAction("Done", identifier: "closeGitHubSync") { dismiss() })
        // The mark is the tray's IDENTITY, so it stays in the bar rather than
        // moving into the body — a leading ornament, not a control. It is not
        // a `.principal` title view on purpose: UIKit centres one of those in
        // the BAR rather than between the side items, so any trailing key
        // makes the two gaps differ by its own width (navigation.md, the
        // build-150 measurement).
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("GitHubMark").resizable().scaledToFit().frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
        }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isAuthorizing) { _, authorizing in
            if authorizing { detent = .large }
        }
        // Connecting reveals the connected state; `startAuthorize` owns
        // closing the browser (the token lands two steps before this fires).
        .onChange(of: sync.isConnected) { _, connected in
            guard connected else {
                // ⚠️ Disconnecting from the connected card drops the user
                // straight back into the wizard, and `didInit` means
                // `onAppear` will never re-seat it (swift-reviewer). Without
                // this reset they landed on STEP 3 OF 3 showing a stale
                // "installed on owner/repo ✓" for a token that no longer
                // exists, over a Finish that was enabled and did nothing.
                installCheckTask?.cancel()
                installCheck = .idle
                withAnimation(Theme.Anim.selection) {
                    advancing = false
                    step = .authorize
                }
                return
            }
            browser = nil
            // Connecting never backgrounds the app (the authorize step is an
            // in-app browser, not an external one), so no scenePhase → .active
            // transition fires the app-root foreground sync. Without this, the
            // repo's data wouldn't land until the user next backgrounded and
            // returned. Kick the first pass off here so it appears right after
            // connecting. Safe to double up with a foreground sync: sync() is
            // single-flight and no-ops while one is in flight.
            let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
            Task { @MainActor in
                await sync.sync(context: modelContext, units: units)
            }
        }
        // ⚠️ `onDismiss` matters as much as the scenePhase hook below, and
        // is easy to miss: `openInstall()` falls back to the IN-APP browser
        // on a device with no handler for the universal link, and that
        // route never backgrounds the app — so scenePhase never fires and
        // the verdict would sit stale behind a "Check again" the user has
        // no reason to think they need.
        .sheet(item: $browser, onDismiss: {
            guard step == .install, !sync.isConnected else { return }
            checkInstall()
        }) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        // The install step opens EXTERNALLY (`openInstall`), so returning to
        // the app IS the moment the answer can have changed. Re-ask then,
        // rather than making the user find "Check again".
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, step == .install, !sync.isConnected else { return }
            checkInstall()
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            // ⚠️ Where you land is decided by the TOKEN, not by which door
            // opened the tray (#509, Q18-A). A device holding one is past
            // step 1 whatever brought it here — the post-install bounce, a
            // reconnect, or reopening a wizard abandoned halfway — and the
            // install step can tell it in one request which of the
            // remaining states it is actually in. Without a token there is
            // exactly one thing to do, and it is step 1.
            // ⚠️ Nothing to seed while CONNECTED: the wizard isn't on
            // screen, and checking would spend a `/user/installations`
            // round trip on every tray open to fill a verdict nobody sees —
            // which then went stale and misleading the moment the user
            // tapped Disconnect (swift-reviewer).
            if sync.isConnected {
                return
            }
            if sync.hasToken {
                step = .install
                checkInstall()
            } else {
                step = .authorize
                // Only the post-install redirect auto-starts the flow; a
                // manual reconnect waits for the user to tap the primary.
                guard startAtConnect, case .disconnected = sync.connection, !isAuthorizing else { return }
                startAuthorize()
            }
        }
        .onDisappear {
            connectTask?.cancel()
            copyResetTask?.cancel()
            installCheckTask?.cancel()
            sync.authorizingAborted()
        }
    }

    // MARK: - Description

    private var description: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use it as a simple backup, let an AI agent train you to peak physical condition to serve as its mercenary in the machine rebellion, or anything in between.")
            Text("GitHub sync is two-way, so you can inspect and fine-tune your fitness program using the tools of your choice.")
            Text("Only give the PlusPlus app access to a single, dedicated repo in your GitHub account.")
                .foregroundStyle(Theme.textFaint)
        }
        .font(.system(.footnote))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if sync.connection == .unconfigured {
            unconfiguredNote
        } else if sync.isConnected {
            connectedActions
        } else if isAuthorizing {
            authorizingCard
        } else {
            wizard
        }
    }

    private var wizard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepBar
            // Overlap the outgoing/incoming steps in a ZStack so the slide
            // doesn't lay them out as vertical siblings and briefly double
            // the height, shoving the error note.
            // Clipped so the moving step can't draw past the edges mid-slide.
            // Direction follows `advancing`: Continue slides right-to-left,
            // Back reverses.
            ZStack(alignment: .topLeading) {
                switch step {
                case .authorize: authorizeStep.transition(stepTransition)
                case .createRepo: createRepoStep.transition(stepTransition)
                case .install: installStep.transition(stepTransition)
                }
            }
            .clipped()
            if let activityError { errorNote(activityError) }
            abandonKey
        }
    }

    /// The way OUT of a half-finished or broken connection (#509 review).
    ///
    /// ⚠️ Disconnect used to live only in `connectedActions`, so a fault
    /// was a one-way door: `faulted` is cleared by a successful connect or
    /// by `disconnect()`, and while faulted the tray shows this wizard,
    /// which offered neither. Someone who deleted their repo, closed their
    /// GitHub account, or simply changed their mind was left with a red
    /// row in the drawer and an amber card on Today saying "reconnect",
    /// with no way to say no. It only appears once there is something to
    /// forget, so a first-time wizard never carries it.
    @ViewBuilder
    private var abandonKey: some View {
        if sync.hasToken || sync.faulted {
            Button(role: .destructive) {
                installCheckTask?.cancel()
                connectTask?.cancel()
                installCheck = .idle
                sync.disconnect()
                // Slide back the way Back does; a hard cut from step 3 to
                // step 1 reads as a glitch.
                withAnimation(Theme.Anim.selection) {
                    advancing = false
                    step = .authorize
                }
            } label: {
                Text("Stop syncing")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
            }
            .accessibilityIdentifier("abandonGitHubButton")
            .accessibilityHint("Forgets this connection and clears the token from this phone")
            .padding(.top, 2)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: advancing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: advancing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var authorizeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            primaryKey(title: "Connect this app", identifier: "connectGitHubButton") { startAuthorize() }
            guidance("Authorize on GitHub first, so the next two steps can be checked for you.")
        }
    }

    private var createRepoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            primaryKey(title: "Create repo in GitHub", identifier: "createRepoButton") { openCreateRepo() }
            guidance("Make a new, empty repo to hold your training data.")
            continueButton(title: "Done? Continue") { advance(to: .install); checkInstall() }
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            primaryKey(title: "Install on GitHub", identifier: "installGitHubButton") { openInstall() }
            guidance("Install the PlusPlus Sync GitHub app to your repo.")
            installVerdict
            continueButton(title: finishing ? "Finishing\u{2026}" : "Finish", enabled: isInstalled && !finishing) {
                finish()
            }
        }
    }

    private var isInstalled: Bool {
        if case .installed = installCheck { return true }
        return false
    }

    /// What GitHub says, right now, about the install. The step's whole
    /// reason for existing in this order (#509, Q18-A) — an answer here
    /// costs one request and saves the device-flow round trip the old
    /// order spent before finding out.
    @ViewBuilder
    private var installVerdict: some View {
        switch installCheck {
        case .idle, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub\u{2026}")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case .installed(let repo):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("installed on \(repo.owner)/\(repo.repo)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Installed on \(repo.owner) slash \(repo.repo)")
            .accessibilityIdentifier("installVerified")
        case .notInstalled:
            recheckRow("Not installed yet. Install it above, then check again.")
        case .failed(let message):
            recheckRow(message)
        }
    }

    private func recheckRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check again") { checkInstall() }
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("recheckInstallButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Orientation + a way back through the steps (a fresh user who tapped
    /// ahead, or a reconnect that needs to reinstall first).
    private var stepBar: some View {
        HStack {
            Text("STEP \(step.rawValue) OF 3")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .kerning(0.5)
            Spacer()
            if step != .authorize {
                Button("Back") { goBack() }
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var authorizingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tap the card to copy the code, so it can be pasted at
            // github.com/login/device rather than retyped.
            if case .authorizing(let code, let url) = sync.activity {
                Button {
                    copyCode(code)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Approve on GitHub to connect")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 12) {
                            Text(code)
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .accessibilityIdentifier("deviceUserCode")
                            Spacer()
                            Image(systemName: codeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(.title3, weight: .semibold))
                                .foregroundStyle(codeCopied ? Theme.accent : Theme.textFaint)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(codeCopied ? "Copied" : "Filled in when you open GitHub. Tap to copy.")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(codeCopied ? Theme.accent : Theme.textFaint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("copyCodeButton")
                .accessibilityLabel(codeCopied ? "Code copied" : "Copy code \(code)")

                primaryKey(title: "Open GitHub", identifier: "openGitHubButton") { openInApp(url) }
            }

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to approve on GitHub…")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 2)

            Button("Cancel") {
                connectTask?.cancel()
                sync.authorizingAborted()
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 2)

            if let activityError { errorNote(activityError) }
        }
    }

    private var connectedActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let coordinate = sync.coordinate {
                    Text("\(coordinate.owner)/\(coordinate.repo)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                if sync.isSyncing {
                    Text("Syncing…")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                } else if let at = sync.lastSyncedAt {
                    // Foundation's relative style pluralizes correctly on its
                    // own ("1 minute ago", never "1 minutes ago").
                    Text("Synced \(at.formatted(.relative(presentation: .named)))")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

            syncNowButton

            Button(role: .destructive) {
                sync.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.destructive.opacity(0.4)))
            }
            .accessibilityIdentifier("disconnectGitHubButton")

            Text("Removes the token from this phone. Your repo is untouched. Revoke on GitHub anytime.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
    }

    /// Manual "check now" for the connected state. Foreground, boundaries, and
    /// pull-to-refresh sync on their own; this is the on-demand escape hatch.
    private var syncNowButton: some View {
        Button {
            let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
            Task { @MainActor in
                await sync.sync(context: modelContext, units: units)
            }
        } label: {
            HStack(spacing: 8) {
                if sync.isSyncing {
                    ProgressView().controlSize(.small).tint(Theme.onPrimary)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(.subheadline, weight: .bold))
                }
                Text(sync.isSyncing ? "Syncing…" : "Sync now")
                    .font(.system(.subheadline, weight: .bold))
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: Theme.controlRadius))
        .disabled(sync.isSyncing)
        .accessibilityIdentifier("syncNowButton")
    }

    private var unconfiguredNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync isn't set up in this build yet.")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("The sync engine ships and is tested; connecting an account lands once the GitHub App is registered. Until then, Data moves your program and history through the same JSON by hand.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
    }

    // MARK: - Bits

    private func primaryKey(title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("GitHubMark").resizable().scaledToFit().frame(width: 15, height: 15)
                    .accessibilityHidden(true)
                Text(title).font(.system(.subheadline, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: Theme.controlRadius))
        .accessibilityIdentifier(identifier)
    }

    private func continueButton(title: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textFaint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(enabled ? Theme.borderStrong : Theme.border))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("continueStepButton")
    }

    private func guidance(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorNote(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: - Actions

    /// Advance to a later step with a right-to-left slide. `.selection` is the
    /// snappy spring the grammar uses for sliding motion (an ease-out tail
    /// reads muddy on a slide).
    private func advance(to next: Step) {
        withAnimation(Theme.Anim.selection) {
            advancing = true
            step = next
        }
    }

    /// Step back one, sliding left-to-right (the reverse of advancing).
    private func goBack() {
        withAnimation(Theme.Anim.selection) {
            advancing = false
            step = Step(rawValue: step.rawValue - 1) ?? .authorize
        }
    }

    /// Open a web URL inside the app (SFSafariViewController) rather than
    /// kicking out to Safari — keeps the user in the flow. Used by the authorize
    /// step (and the create-repo fallback), which have no deep-link dependency.
    private func openInApp(_ url: URL) {
        browser = BrowserURL(url: url)
    }

    /// Install opens EXTERNALLY (Safari, or the GitHub app if it claims the
    /// link), NOT the in-app browser: `SFSafariViewController` can't hand a
    /// universal link back to the app, so an in-app install would forfeit the
    /// post-install auto-return (plusplus.fit/github/connected → the app). The
    /// other steps have no such dependency and stay in-app.
    /// Same two-step as `openCreateRepo` below (#509, b18): prefer the
    /// GitHub app via the universal link, and fall back to the in-app
    /// browser when it doesn't claim it. Without the completion handler a
    /// device with no GitHub app and no handler for the link got NOTHING —
    /// a Continue step whose only action silently did nothing, on the step
    /// that is already the easiest one to miss.
    private func openInstall() {
        UIApplication.shared.open(GitHubSyncSettings.installURL, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                browser = BrowserURL(url: GitHubSyncSettings.installURL)
            }
        }
    }

    /// Step 1: the device flow alone. On a token it advances to step 2 —
    /// the wizard's forward motion is the ANSWER arriving, not a Continue
    /// the user taps on trust.
    private func startAuthorize() {
        connectTask?.cancel()
        connectTask = Task {
            let authorized = await sync.authorize()
            guard !Task.isCancelled, authorized else { return }
            // ⚠️ Dismiss the in-app browser HERE (swift-reviewer). It used
            // to close off `sync.isConnected`, which the old `connect()`
            // set at the end of the device flow — `authorize()` deliberately
            // does not, so the sheet would have stayed up over GitHub's
            // "device activated" page while the wizard advanced invisibly
            // beneath it. `SafariView` sets no delegate, so its own Done
            // button does nothing and the only exit is a swipe-down the
            // user has no reason to try: the wizard reads as hung.
            browser = nil
            advance(to: .createRepo)
        }
    }

    /// Ask GitHub whether the Sync App is installed on a repo yet (#509,
    /// Q18-A). Cheap (one request), safe to repeat, and the only thing
    /// standing between the user and a Finish that works.
    private func checkInstall() {
        installCheckTask?.cancel()
        guard sync.hasToken else { installCheck = .notInstalled; return }
        installCheck = .checking
        installCheckTask = Task {
            do {
                let repo = try await sync.installedRepository()
                guard !Task.isCancelled else { return }
                withAnimation(Theme.Anim.standard) {
                    installCheck = repo.map(InstallCheck.installed) ?? .notInstalled
                }
            } catch {
                guard !Task.isCancelled else { return }
                // ⚠️ ONE error is not "the question didn't get answered",
                // and it is the one this feature exists for (swift-reviewer):
                // a revoked or expired token 401s here. Reported as a
                // network blip it left Finish permanently dead under a
                // "Check again" that could only ever fail the same way,
                // with the actual fix two un-obvious Back taps away. Drop
                // the dead token and put the user on step 1, which is now
                // the only thing that can help them.
                if Self.isTokenDead(error) {
                    sync.forgetDeadToken()
                    installCheck = .idle
                    withAnimation(Theme.Anim.selection) {
                        advancing = false
                        step = .authorize
                    }
                    return
                }
                withAnimation(Theme.Anim.standard) {
                    installCheck = .failed("Couldn't reach GitHub to check.")
                }
            }
        }
    }

    /// A 401 or an empty stored token — this phone's authorization is gone,
    /// which no amount of re-checking will fix.
    private static func isTokenDead(_ error: Error) -> Bool {
        (error as? GitHubAccount.AccountError) == .notAuthenticated
    }

    /// Step 3's Finish: adopt the repo the check already named.
    private func finish() {
        guard !finishing else { return }
        finishing = true
        Task {
            await sync.finishConnecting()
            finishing = false
        }
    }

    /// Prefer the GitHub app: `github.com/new` opens it directly IF it's
    /// installed and claims that universal link (the completion handler
    /// reports whether it did). Otherwise fall back to github.new in an
    /// in-app browser, which lands straight on the create-repo form.
    private func openCreateRepo() {
        let universal = URL(string: "https://github.com/new")!
        UIApplication.shared.open(universal, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                browser = BrowserURL(url: URL(string: "https://github.new")!)
            }
        }
    }

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Theme.Anim.standard) { codeCopied = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Anim.standard) { codeCopied = false }
        }
    }
}
