import SwiftUI

/// The single-effort commit key: on a session that is ONE continuous
/// effort, the key that logs it also ENDS the workout, so it SLIDES
/// instead of tapping (Dave, Q4 2026-08-01) — a run is finished
/// deliberately, never by a stray thumb mid-stride. The raised-key
/// grammar supplies the mechanism: the cap slides the length of its own
/// base plate (the plate IS the track, worn full-width where a tap key
/// hides it beneath the cap), sinking onto it while touched, and
/// commits at the end of travel. A tap or an abandoned drag springs the
/// cap home — the wiggle is what teaches the slide.
///
/// ⚠️ Assistive access activates it DIRECTLY: the control is
/// represented as a plain Button (same label, same identifier), so
/// VoiceOver, Switch Control and Voice Control finish without a drag —
/// a drag is not a gate they can be asked to pass. A hidden sibling
/// carries Return for external keyboards (WCAG 2.1.1), as the tap keys
/// do. ⚠️ XCUITest is NOT covered by the representation: `tap()`
/// synthesizes a TOUCH at the frame, not the accessibility activation
/// VoiceOver performs, and a touch dies on the drag layer — so under
/// `--uitest-reset` a tap commits (the test-only door, StartFlashButton's
/// skipped-flash precedent). The slide gesture itself is
/// XCUITest-invisible either way: device-pass territory, like every
/// gesture layer in this app.
///
/// ⚠️ The drag's transient state is `@GestureState`, not `@State`
/// (ui-interaction.md's latch law, extended by review): a CANCELLED
/// sequence — an incoming call, the app switcher — never runs
/// `onEnded`, and `@State` left the cap stranded sunk mid-track with a
/// stale latch eating the next slide. GestureState resets on end AND
/// cancel, springing the cap home through the reset transaction. The
/// first-event direction latch stays even though both current mounts
/// sit below their ScrollViews, not inside them — the next mount may
/// not, and recognition must never starve an enclosing scroll.
struct SlideToFinishKey: View {
    let label: String
    var minHeight: CGFloat = 54
    var font: Font = .system(.body, weight: .bold)
    var identifier: String = "completeSetButton"
    let onCommit: () -> Void

    /// RaisedKeyStyle's standard travel — the cap sits proud by this
    /// much and sinks onto the plate while touched.
    private let travel: CGFloat = 4
    /// How much of the track the cap must cover to commit.
    private let commitFraction: CGFloat = 0.85

    /// XCUITest's `tap()` cannot cross a 10 pt drag threshold and is
    /// not an accessibility activation — see the doc comment.
    private static let testTapCommits = CommandLine.arguments.contains("--uitest-reset")

    private struct DragState: Equatable {
        /// First-event direction verdict — nil until the sequence's
        /// first change, then fixed (the latch law).
        var latch: Bool?
        var x: CGFloat = 0
    }

    @GestureState(resetTransaction: Transaction(animation: Theme.Anim.selection))
    private var drag = DragState()
    /// One commit per mounted key: the finish takes a beat to change
    /// the screen, and every activation door checks it.
    @State private var committed = false

    /// The cap grows with Dynamic Type — the tap keys this replaces
    /// used `minHeight` and grew at AX sizes; a fixed clamp on the
    /// primary commit key would shrink type in both axes (review).
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    @Environment(\.layoutDirection) private var layoutDirection

    private var capHeight: CGFloat { minHeight * max(1, typeScale) }
    /// RTL mirrors the slide: `offset(x:)` and `translation.width` are
    /// not layout-direction-aware, so the sign is; the `.trailing`
    /// chevron alignment and `chevron.forward` mirror on their own.
    private var mirror: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    var body: some View {
        GeometryReader { geo in
            let capWidth = max(geo.size.width * 0.62, 132)
            let maxTravel = max(geo.size.width - capWidth, 1)
            let core = track(capWidth: capWidth, maxTravel: maxTravel)
            if Self.testTapCommits {
                core.onTapGesture { fire() }
            } else {
                core
            }
        }
        .frame(height: capHeight + travel)
        .accessibilityRepresentation {
            Button(label) { fire() }
                .accessibilityIdentifier(identifier)
        }
        .background {
            // Return finishes for external-keyboard users (WCAG 2.1.1),
            // exactly as the tap keys' own `.keyboardShortcut` does.
            Button("") { fire() }
                .keyboardShortcut(.defaultAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func fire() {
        guard !committed else { return }
        committed = true
        onCommit()
    }

    private func track(capWidth: CGFloat, maxTravel: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // The plate, worn as the full-width track — same top inset
            // RaisedKeyStyle gives it, so the strip under the cap's
            // bottom edge reads as the same key's underside.
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.borderStrong)
                .padding(.top, travel)
            // The slide hint lives in the exposed run of track.
            Image(systemName: "chevron.forward.2")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: capHeight)
                .padding(.trailing, 18)
                .padding(.top, travel)
                .accessibilityHidden(true)
            Text(label)
                .font(font)
                .foregroundStyle(Theme.onPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: capWidth)
                .frame(height: capHeight)
                .background(Theme.primaryFill, in: RoundedRectangle(cornerRadius: 12))
                .offset(x: mirror * min(drag.x, maxTravel),
                        y: drag.latch == true ? travel : 0)
                .animation(Theme.Anim.press, value: drag.latch)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .updating($drag) { value, state, _ in
                    if state.latch == nil {
                        state.latch = abs(value.translation.width) > abs(value.translation.height)
                    }
                    guard state.latch == true else { return }
                    state.x = max(0, value.translation.width * mirror)
                }
                .onEnded { value in
                    // GestureState is already resetting here, so the
                    // verdict re-derives from the FINAL translation.
                    // It can only disagree with the first-event latch
                    // toward refusing — a pull that ended more vertical
                    // than horizontal does not finish a workout.
                    guard abs(value.translation.width) > abs(value.translation.height),
                          max(0, value.translation.width * mirror) >= maxTravel * commitFraction
                    else { return }
                    fire()
                }
        )
    }
}
