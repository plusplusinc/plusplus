import SwiftUI
import UIKit
import PlusPlusKit

/// The single GitHub sync surface (#23 flow redesign): one tray that carries
/// the whole story instead of a status tray pushing a separate connect screen.
///
/// Not connected, it runs a three-step wizard with exactly one enabled primary
/// action at a time: create a repo, install the PlusPlus Sync App on it, then
/// authorize this device. Connected, it offers only Disconnect. The post-install
/// auto-return (`startAtConnect`) and a reconnect after a fault both drop the
/// user straight on the authorize step, since the repo and App install already
/// exist by then.
struct GitHubSyncTray: View {
    /// Present already advanced to the authorize step. The post-install
    /// auto-return sets this: GitHub only bounces back after a completed
    /// install, so create-repo and install are behind us and we auto-start
    /// the device flow to finish connecting.
    var startAtConnect: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var step: Step = .createRepo
    @State private var connectTask: Task<Void, Never>?
    @State private var didInit = false
    @State private var codeCopied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var browser: BrowserURL?
    /// The authorizing card (a tall monospaced code + "Open GitHub") can fall
    /// below the fold at `.medium`; expand to `.large` while it's up so the
    /// one action the user needs stays visible.
    @State private var detent: PresentationDetent = .medium

    enum Step: Int { case createRepo = 1, install = 2, connect = 3 }

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
        VStack(alignment: .leading, spacing: 0) {
            header
            Text("Keep your data in sync with a GitHub repo")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    description
                    actions
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 18)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: isAuthorizing) { _, authorizing in
            if authorizing { detent = .large }
        }
        .sheet(item: $browser) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            // Reconnect (faulted) and the post-install return both belong on
            // the authorize step: the repo and App install already exist, only
            // this device's token is missing.
            if startAtConnect || sync.faulted { step = .connect }
            // Only the redirect auto-starts the flow; a manual reconnect waits
            // for the user to tap the primary.
            guard startAtConnect, case .disconnected = sync.connection, !isAuthorizing else { return }
            startConnect()
        }
        .onDisappear {
            connectTask?.cancel()
            copyResetTask?.cancel()
            sync.authorizingAborted()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("GitHubMark").resizable().scaledToFit().frame(width: 22, height: 22)
            Text("GitHub sync")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
                    .contentShape(Circle())
            }
            .accessibilityIdentifier("closeGitHubSync")
        }
        .padding(.top, 14)
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
            switch step {
            case .createRepo:
                primaryKey(title: "Create repo in GitHub", identifier: "createRepoButton") { openCreateRepo() }
                guidance("Make a new, empty repo to hold your training data.")
                continueButton { step = .install }
            case .install:
                primaryKey(title: "Install on GitHub", identifier: "installGitHubButton") { openURL(GitHubSyncSettings.installURL) }
                guidance("Install the PlusPlus Sync GitHub app to your repo.")
                continueButton { step = .connect }
            case .connect:
                primaryKey(title: "Connect this app", identifier: "connectGitHubButton") { startConnect() }
                guidance("Authorize on GitHub to link this iPhone to your repo.")
            }
            if let activityError { errorNote(activityError) }
        }
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
            if step != .createRepo {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .createRepo
                }
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

                primaryKey(title: "Open GitHub", identifier: "openGitHubButton") { openURL(url) }
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
                if let summary = sync.lastSyncSummary, let at = sync.lastSyncedAt {
                    Text("\(summary). \(at.formatted(.relative(presentation: .named)))")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                } else if let at = sync.lastSyncedAt {
                    Text("Last synced \(at.formatted(.relative(presentation: .named)))")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

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
                Text(title).font(.system(.subheadline, weight: .bold))
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: Theme.controlRadius))
        .accessibilityIdentifier(identifier)
    }

    private func continueButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Done? Continue")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.plain)
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

    private func startConnect() {
        connectTask?.cancel()
        connectTask = Task { await sync.connect() }
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
