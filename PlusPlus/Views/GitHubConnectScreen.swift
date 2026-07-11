import SwiftUI
import PlusPlusKit

/// The SYNC destination (#23): connect a GitHub account by device flow, then
/// see connection state and sync on demand. Your program and history live as
/// JSON in a private repo you own — no PlusPlus server ever sees it.
struct GitHubConnectScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    @State private var sync = GitHubSyncCoordinator.shared
    @State private var connectTask: Task<Void, Never>?

    private var units: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    private var activityError: String? {
        if case .error(let message) = sync.activity { return message }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
        .onDisappear {
            connectTask?.cancel()
            sync.authorizingAborted()
        }
    }

    // MARK: - States

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep your routines and history in a private GitHub repo you own.")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Readable JSON with clean diffs. Point an agent at it, run Actions on your training data, or just have a durable backup. The app talks to GitHub directly · nothing runs on a PlusPlus server.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textSecondary)
            Text("First time: create a private repo and install PlusPlus Sync on it, then connect. The app syncs to whichever repo you installed it on.")
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
                keyLabel(icon: "arrow.up.right", title: "Install on GitHub")
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("installGitHubButton")
            Text("Step 1 · pick the private repo to sync to. Skip if you've already installed it.")
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
                keyLabel(icon: "arrow.triangle.2.circlepath", title: "Connect GitHub")
            }
            .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
            .accessibilityIdentifier("connectGitHubButton")
            Text("Step 2 · authorize on GitHub with a short code.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.top, 12)
    }

    private func authorizing(code: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter this code at github.com")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("deviceUserCode")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))

            Button {
                openURL(url)
            } label: {
                keyLabel(icon: "arrow.up.right", title: "Open GitHub")
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
                    Circle().fill(Theme.done).frame(width: 8, height: 8)
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
                    Text("\(summary) · \(at.formatted(.relative(presentation: .named)))")
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

            Text("Disconnecting forgets the token on this phone. Your repo and its history stay exactly as they are.")
                .font(.system(.caption))
                .foregroundStyle(Theme.textFaint)
        }
    }

    // MARK: - Bits

    private func keyLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(.footnote))
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
