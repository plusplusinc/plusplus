import SwiftUI

/// The welcome beat (Dave, 2026-07-10): three screens before the tabs
/// on first launch — the idea, the mechanics, the Health ask — then the
/// setup timeline takes over as always. Deliberately light: no account,
/// no questionnaire, one permission (notifications keep their
/// contextual ask at the first rest, #246). Every screen is escapable;
/// "skip intro" exits the whole thing.
struct WelcomeView: View {
    let onDone: () -> Void

    @State private var page = 0
    @State private var connecting = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < 2 {
                        Button {
                            finish()
                        } label: {
                            Text("skip intro")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .contentShape(Capsule())
                        }
                        .accessibilityIdentifier("welcomeSkipButton")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(height: 42)

                TabView(selection: $page) {
                    ideaPage.tag(0)
                    mechanicsPage.tag(1)
                    healthPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.top, 4)

                controls
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Pages

    /// What this is: the mark, the tagline, the one idea.
    private var ideaPage: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("++")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text("PlusPlus")
                .font(.system(.title2, weight: .bold))
            Text("The hackable workout tracker for incrementing yourself.")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text("Privacy-first and customizable to the core. Own your data, and your results.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    /// How it works: three rows, one line each — routines, Today, progress.
    private var mechanicsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("HOW IT WORKS")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 18)
            mechanicsRow(
                symbol: "dumbbell.fill",
                title: "Build routines from your gear",
                caption: "the catalog adapts to the equipment you have"
            )
            mechanicsRow(
                symbol: "calendar",
                title: "Today shows what's ready",
                caption: "what's next on top, history below"
            )
            mechanicsRow(
                symbol: "chart.line.uptrend.xyaxis",
                title: "See your progress on every set",
                caption: "last time's numbers are right there; green means you went up"
            )
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func mechanicsRow(symbol: String, title: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                Text(caption)
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    /// The one permission worth asking for up front: heart rate needs
    /// to be readable BEFORE the first workout to show up in it.
    private var healthPage: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Heart rate, live")
                .font(.system(.title3, weight: .bold))
            Text("Connect Apple Health to see your heart rate while you train. Every record keeps the average and peak.")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text("finished workouts save back to Health · your data stays on your devices")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Controls

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.textPrimary : Theme.surfaceRaised)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(Theme.Anim.standard, value: page)
    }

    /// Every page reserves the two-key height — primary cap 50 + 4 travel,
    /// 10 gap, quiet cap 44 + 3 travel — so the dots and the primary key
    /// sit at identical positions on all three screens; pages 1–2 leave
    /// the "Not now" slot empty.
    private static let controlsHeight: CGFloat = 111

    private var controls: some View {
        Group {
            if page < 2 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { page += 1 }
                } label: {
                    Text("Continue")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                .accessibilityIdentifier("welcomeContinueButton")
            } else {
                VStack(spacing: 10) {
                    Button {
                        connectHealth()
                    } label: {
                        Text(connecting ? "Connecting…" : "Connect Apple Health")
                            .font(.system(.body, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                    .disabled(connecting)
                    .accessibilityIdentifier("welcomeConnectHealthButton")

                    Button {
                        finish()
                    } label: {
                        Text("Not now")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.border))
                    }
                    .buttonStyle(.quietKey)
                    .accessibilityIdentifier("welcomeSkipHealthButton")
                }
            }
        }
        .frame(height: Self.controlsHeight, alignment: .top)
    }

    /// The system sheet does the real asking; whatever the user decides
    /// there, the intro is over. Under UI test the request is skipped
    /// outright (HealthAccess is inert) so no sheet can eat a tap.
    private func connectHealth() {
        guard !connecting else { return }
        connecting = true
        HealthAccess.requestEverything {
            finish()
        }
    }

    private func finish() {
        SetupState.markWelcomeSeen()
        onDone()
    }
}
