import SwiftUI

/// The contextual Health ask (it replaced the welcome flow's Health
/// screen): shown ONCE, the first time a workout is about to start,
/// right where heart rate is about to matter. A soft primer in front of
/// the system sheet — a "Not now" here costs nothing (the system prompt
/// only fires on Connect), and once iOS has denied a read there is no
/// second in-app ask. Every path into a workout funnels through
/// `HealthStartGate`, so the primer covers the due-card Start, routine
/// detail, "Do it again", and the Siri/widget/calendar starts alike.
///
/// Shape (four hard-won rules from the design talk):
///  1. The "already asked?" memory is ours (`SetupState.healthPrimerShown`)
///     — HealthKit hides read authorization by design, so we can't derive it.
///  2. Both buttons proceed into the workout; "Not now" is not a dead end
///     (the user tapped Start to train). Interactive dismissal is disabled
///     so a swipe can't eat the start.
///  3. The actual start runs in the sheet's `onDismiss`, never under the
///     live sheet — dismiss-then-present-cover in one transaction is the
///     documented presentation-drop class.
///  4. Connect resolves the system sheet FIRST, then starts, so the very
///     first workout already has live heart rate.

/// A workout start deferred behind the primer. Carries the closure that
/// actually begins the session; the gate runs it once the primer is
/// resolved and fully dismissed. `Identifiable` so it drives `.sheet(item:)`.
struct HealthStartRequest: Identifiable {
    let id = UUID()
    let begin: () -> Void
}

/// The entry point a start site calls INSTEAD of starting directly.
enum HealthStartGate {
    /// Runs `begin` immediately when the primer has already been shown
    /// (or Health is unavailable, e.g. under UI test); otherwise hands a
    /// request to `present`, which raises the primer. `begin` fires once,
    /// either now or after the primer is dismissed.
    static func begin(_ begin: @escaping () -> Void, orPresent present: (HealthStartRequest) -> Void) {
        if SetupState.healthPrimerShown || !HealthAccess.isAvailable {
            begin()
        } else {
            present(HealthStartRequest(begin: begin))
        }
    }
}

extension View {
    /// Presents the one-time Health primer for a gated workout start.
    /// Bind the `HealthStartRequest?` a start site sets via
    /// `HealthStartGate.begin(_:orPresent:)`.
    func healthStartPrimer(_ request: Binding<HealthStartRequest?>) -> some View {
        modifier(HealthStartPrimerModifier(request: request))
    }
}

private struct HealthStartPrimerModifier: ViewModifier {
    @Binding var request: HealthStartRequest?
    /// The start to run once the sheet is gone — set by whichever button
    /// resolved the primer, consumed in `onDismiss`.
    @State private var proceedOnDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(item: $request, onDismiss: {
            let begin = proceedOnDismiss
            proceedOnDismiss = nil
            begin?()
        }) { req in
            HealthStartPrimer(
                onConnect: {
                    SetupState.markHealthPrimerShown()
                    proceedOnDismiss = req.begin
                    // Resolve the system sheet, THEN dismiss the primer so
                    // its onDismiss starts the workout with HR already
                    // authorized (or declined) — either way the query has
                    // its answer before set one.
                    HealthAccess.requestEverything {
                        request = nil
                    }
                },
                onSkip: {
                    SetupState.markHealthPrimerShown()
                    // Honor the decline: turn the integration off (the
                    // documented, Settings-reversible off switch) so the
                    // live HR monitor — which only gates on this intent —
                    // doesn't independently surface the system read sheet
                    // moments later, which would make "Not now" a lie.
                    HealthSyncCoordinator.shared.disable()
                    proceedOnDismiss = req.begin
                    request = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
    }
}

/// The primer's face. Heart-rate-headlined (the one live, pre-workout
/// reason to ask before the session); the calorie line names the other
/// thing a record keeps, since the system sheet lists active energy too.
struct HealthStartPrimer: View {
    let onConnect: @MainActor () -> Void
    let onSkip: @MainActor () -> Void

    @State private var connecting = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Track your heart rate while you train")
                .font(.system(.title3, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Connect Apple Health to see live heart rate during your workouts. Each record keeps its average, peak, and the calories you burned.")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text("your data stays on your devices")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                Button {
                    guard !connecting else { return }
                    connecting = true
                    onConnect()
                } label: {
                    Text(connecting ? "Connecting…" : "Connect Apple Health")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.raisedPrimaryKey(cornerRadius: 12))
                .disabled(connecting)
                .accessibilityIdentifier("healthPrimerConnectButton")

                Button {
                    onSkip()
                } label: {
                    Text("Not now")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.border))
                }
                .buttonStyle(.quietKey)
                .disabled(connecting)
                .accessibilityIdentifier("healthPrimerSkipButton")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
