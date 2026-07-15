import SwiftUI

/// The welcome beat (Dave, 2026-07-15): ONE screen before the tabs on
/// first launch — the mark, the name, the idea, and a single button that
/// drops into Today, where the setup timeline does the real onboarding
/// by doing. The old three-screen intro is gone: the mechanics tour was
/// pure telling (the timeline shows it), and the up-front Health screen
/// moved to a contextual primer on the first workout (HealthStartPrimer),
/// where heart rate is actually about to matter. Shown once per install.
struct WelcomeView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    Text("++")
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                    Text("PlusPlus")
                        .font(.system(.title2, weight: .bold))
                    Text("The hackable workout tracker for incrementing yourself.")
                        .font(.system(.subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    // PROVISIONAL copy (Dave undecided, 2026-07-15): the
                    // "left alone" line — the one value nothing downstream
                    // carries now that the other screens are gone. Easy to
                    // swap; it is the only supporting prose before the app.
                    Text("No account, no nagging, no upsell. Just you and the numbers.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)
                Spacer()
                // PROVISIONAL copy (Dave undecided): the CTA. "Get started"
                // reads as entering the app, not paging through more intro.
                Button {
                    finish()
                } label: {
                    Text("Get started")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                .accessibilityIdentifier("welcomeGetStartedButton")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func finish() {
        SetupState.markWelcomeSeen()
        onDone()
    }
}
