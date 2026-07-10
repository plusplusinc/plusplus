import SwiftUI

/// The app-level page behind Today's ++ button (#266): Settings (moved
/// here from Today's top-right, which now starts workouts), About +
/// What's new, links, and feedback. Sync status joins when #23 ships.
struct AppMenuScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // A raised key (Quiet Arcade): the page's one
                // navigation press.
                Button {
                    showingSettings = true
                } label: {
                    HStack {
                        Text("Settings")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("appearance · units · equipment · data")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderStrong))
                }
                .buttonStyle(.raisedKey(cornerRadius: Theme.controlRadius))
                .accessibilityIdentifier("appMenuSettings")
                .padding(.top, 24)

                SheetSectionLabel("ABOUT")
                    .padding(.top, 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PlusPlus \(version) · build \(build)")
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The hackable workout tracker for incrementing yourself.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                SheetSectionLabel("WHAT'S NEW")
                    .padding(.top, 24)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(WhatsNew.entries.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("BUILD \(entry.build)")
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                            Text(entry.notes)
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < WhatsNew.entries.count - 1 {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                SheetSectionLabel("LINKS")
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    linkRow(title: "plusplus.fit", url: "https://plusplus.fit")
                    Divider().overlay(Theme.border)
                    linkRow(title: "Source on GitHub", url: "https://github.com/plusplusinc/plusplus")
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))

                SheetSectionLabel("FEEDBACK")
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    linkRow(title: "Report an issue or idea", url: "https://github.com/plusplusinc/plusplus/issues/new")
                    Divider().overlay(Theme.border)
                    linkRow(title: "Email", url: "mailto:mr.david.j.cole@gmail.com")
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
                Text("Opens GitHub or Mail — the app itself never phones home.")
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .pushedScreenChrome(title: "PlusPlus", onBack: { dismiss() })
        // isPresented, not a value destination: value registrations on
        // pushed screens are the build-33 missing-destination class.
        .navigationDestination(isPresented: $showingSettings) {
            SettingsScreen()
        }
    }

    private func linkRow(title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }
}

/// Per-build highlights, newest first — curated by hand at each
/// TestFlight dispatch (keep it to one line, no obligation words).
private enum WhatsNew {
    static let entries: [(build: String, notes: String)] = [
        ("46", "Cardio speaks its own numbers — splits, watts, damper, incline · intervals: rounds with their own rest · choose what any exercise tracks · heart rate on screen"),
        ("45", "The ++ key on every tab · catalog pages push and pop one step at a time"),
        ("44", "The ++ wears its key"),
        ("43", "Keys travel deeper · the +1 gets its moment · swipe actions in full color · our own chrome, corner to corner"),
        ("42", "Quiet Arcade: buttons press like real keys · your week as blocks on Today · Log set pops a +1 · rest gains +30s"),
        ("35", "Swipe actions stay put when you let go · this page · start any workout from Today's header"),
        ("34", "Catalogs open on your gear, fixable in place · pick several filters at once"),
        ("33", "A finish screen that names your next session · Today always offers a path"),
        ("32", "Scratch workouts you can keep as routines · equipment you actually own"),
    ]
}
