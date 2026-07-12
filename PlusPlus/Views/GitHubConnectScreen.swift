import SwiftUI
import UIKit
import PlusPlusKit

/// The SYNC destination (#23): connect a GitHub account by device flow, then
/// see connection state and sync on demand. Your program and history live as
/// JSON in a repo you own — no PlusPlus server ever sees it.
struct GitHubConnectScreen: View {
    /// When true, the screen starts the device flow itself on first appear —
    /// the post-install auto-return (B2): the GitHub Setup-URL bounce presents
    /// this as a sheet, and the user lands straight on the authorize step
    /// instead of hunting for the Connect button.
    var autoConnect: Bool = false
    /// The screen was reached via the post-install redirect (GitHub only sends
    /// users to the Setup URL after a completed install), so we can confirm
    /// step 1 succeeded with a banner while the authorize step runs.
    var justInstalled: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var connectTask: Task<Void, Never>?
    @State private var didAutoConnect = false
    @State private var codeCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var units: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    private var activityError: String? {
        if case .error(let message) = sync.activity { return message }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Confirm step 1 (Install) succeeded when we arrived via the
                // post-install redirect, until the connection actually lands.
                if justInstalled, sync.connection != .connected {
                    installedBanner
                }
                // Authorizing is a transient activity that runs while the
                // connection is still .disconnected — check it first.
                if case .authorizing(let code, let url) = sync.activity {
                    authorizing(code: code, url: url)
                } else {
                    switch sync.connection {
                    case .unconfigured:
                        unconfigured
                    case .disconnected:
                        intro
                        if let message = activityError { errorNote(message) }
                        installButton
                        connectButton
                    case .connected:
                        connectedPanel
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .pushedScreenChrome(title: "GitHub Sync", onBack: { dismiss() })
        .onAppear {
            // One-shot: kick off the device flow only if we arrived here to
            // connect and aren't already connected or mid-authorize.
            guard autoConnect, !didAutoConnect else { return }
            didAutoConnect = true
            let isAuthorizing: Bool = { if case .authorizing = sync.activity { return true }; return false }()
            guard case .disconnected = sync.connection, !isAuthorizing else { return }
            connectTask?.cancel()
            connectTask = Task { await sync.connect() }
        }
        .onDisappear {
            connectTask?.cancel()
            copyResetTask?.cancel()
            sync.authorizingAborted()
        }
    }

    // MARK: - States

    private var installedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed on GitHub")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Now authorize to finish connecting.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.accent.opacity(0.4)))
        .padding(.bottom, 16)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You own your data.")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Two-way sync with a GitHub repo you own: edits in the repo land back in the app. Use it as a simple backup, point an AI agent personal trainer at it, or anything in between. It's yours.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
            Text("No PlusPlus server ever sees it. First time? Make an empty repo on GitHub, then Install below.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
        .padding(.bottom, 16)
    }

    private var unconfigured: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync isn't set up in this build yet.")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("The sync engine ships and is tested; connecting an account lands once the GitHub App is registered. Until then, Settings › Data moves your program and history through the same JSON by hand.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
    }

    private var installButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                openURL(GitHubSyncSettings.installURL)
            } label: {
                keyLabel(icon: "arrow.up.right", title: "Install on GitHub", github: true)
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("installGitHubButton")
            Text("Step 1. Install on the repo to sync. Access to that repo only. Skip if done.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.top, 12)
    }

    private var connectButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                connectTask?.cancel()
                connectTask = Task { await sync.connect() }
            } label: {
                keyLabel(icon: "arrow.triangle.2.circlepath", title: "Connect GitHub", github: true)
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("connectGitHubButton")
            Text("Step 2. Authorize the app. One tap on GitHub.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.top, 12)
    }

    private func authorizing(code: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tap the card to copy the code, so it can be pasted at
            // github.com/login/device rather than retyped. Flat control (a
            // copy action, not a nav/commit key) — stays flat per the grammar.
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

            Button {
                openURL(url)
            } label: {
                keyLabel(icon: "arrow.up.right", title: "Open GitHub", github: true)
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))

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
            .padding(.top, 4)
        }
    }

    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    Text("Read and write access to this repo only.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
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

            Button {
                Task { await sync.sync(context: modelContext, units: units) }
            } label: {
                if sync.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").font(.system(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                } else {
                    keyLabel(icon: "arrow.triangle.2.circlepath", title: "Sync now")
                }
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .disabled(sync.isSyncing)
            .accessibilityIdentifier("syncNowButton")

            if let message = activityError {
                errorNote(message)
            }

            Button("Disconnect", role: .destructive) {
                sync.disconnect()
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 4)

            Text("Removes the token from this phone. Your repo is untouched. Revoke on GitHub anytime.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
    }

    // MARK: - Bits

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.15)) { codeCopied = true }
        // Revert the affordance after a beat so it reads as momentary feedback,
        // not a stuck state. One-shot, cancelled on re-tap and on disappear.
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { codeCopied = false }
        }
    }

    private func keyLabel(icon: String, title: String, github: Bool = false) -> some View {
        HStack(spacing: 8) {
            if github {
                Image("GitHubMark").resizable().scaledToFit().frame(width: 15, height: 15)
            } else {
                Image(systemName: icon).font(.system(.footnote))
            }
            Text(title).font(.system(.subheadline, weight: .bold))
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
    }

    private func errorNote(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}
