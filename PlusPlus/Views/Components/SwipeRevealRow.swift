import SwiftUI
import SwiftData

/// The one slide-to-reveal affordance, everywhere (#88; Dave reversed
/// #231's brief native experiment — no mixed affordances). The
/// build-31 snap-back is fixed here: a momentum floor keeps a relaxing
/// finger's lift-drift from reading as close-intent, on top of the
/// cancellation-safe live commit. Horizontal-dominant drags reveal;
/// vertical movement stays with the surrounding scroll. One row open
/// at a time via the shared `openRow` binding.
///
/// ⚠️ CONTRACT for content: the row body carries NO tap affordance of
/// its own — no Button, no `onTapGesture`. Build 33's snap-back was a
/// plain Button firing on the finger-lift that ENDED a reveal drag
/// (the card moves with the finger, so the touch never leaves the
/// button's bounds), and its tap-close branch shut the row the drag
/// had just opened. A slop-based tap style failed the same way,
/// CI-proven — the offset chases the finger, so movement relative to
/// the row is ~zero and no slop heuristic can engage. Row activation
/// is `onTap`, which the component composes with the reveal drag in
/// an ExclusiveGesture: once the drag activates (16 pt), the tap is
/// structurally impossible — arbitration, not heuristics.
/// A row action exposed to assistive tech: the same name+handler the
/// visible swipe button carries, surfaced as a VoiceOver custom action so
/// the swipe (impossible under VoiceOver / Switch Control / Voice Control)
/// is not the only path to it.
struct SwipeRowAction {
    let name: String
    let perform: () -> Void
}

struct SwipeRevealRow<ID: Hashable, Content: View, Actions: View>: View {
    // Identity is generic (Hashable) so callers key the shared open-row
    // state on whatever is stable for them — a routine-family model's
    // `uuid`, or a `persistentModelID` for the browse lists that don't
    // decouple. Only equality/nil is used below.
    let id: ID
    @Binding var openRow: ID?
    var enabled: Bool = true
    let actionsWidth: CGFloat
    /// Row activation for a genuine tap (navigate, open a sheet).
    /// While ANY row is open, a tap closes it instead — the one shared
    /// close affordance, owned here rather than copy-pasted into every
    /// consumer's tap handler.
    var onTap: (() -> Void)? = nil
    /// Mirror of the swipe `actions` as VoiceOver custom actions (#164).
    /// Attached to `content()` only, via `.accessibilityActions` (which adds
    /// rotor actions without collapsing the row into one element the way
    /// `.accessibilityAddTraits` on the container did), so the child labels
    /// the smoke tests query stay individually reachable.
    var accessibilityActions: [SwipeRowAction] = []
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    /// @GestureState, not @State: the system resets it when the touch
    /// sequence is CANCELLED (incoming call, Control Center swipe),
    /// where onEnded never runs — a plain state var left rows frozen
    /// half-swiped (bug hunt finding 3).
    @GestureState private var dragX: CGFloat = 0

    /// The row's resting offset captured at the FIRST drag event, so the
    /// open/closed decision can commit mid-gesture (below) without the
    /// row jumping to the new resting point under the finger.
    @GestureState private var dragBase: CGFloat?

    private var restingOffset: CGFloat {
        openRow == id ? -actionsWidth : 0
    }

    private var offset: CGFloat {
        min(0, max((dragBase ?? restingOffset) + dragX, -actionsWidth - 24))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions()
                .frame(width: actionsWidth)
                .frame(maxHeight: .infinity)
                .opacity(offset < -12 ? 1 : 0)
                // opacity(0) does NOT remove a view from hit testing —
                // and inside a List, taps on the row could dispatch to
                // the hidden action button, silently deleting the row
                // (Dave, build 12: "items inexplicably disappear").
                .allowsHitTesting(offset < -12)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .contentShape(Rectangle())
                // simultaneous with the OUTSIDE world (the List pan must
                // coexist — .gesture starves scrolling, #99); exclusive
                // WITHIN: the drag activating makes the tap impossible.
                .simultaneousGesture(
                    ExclusiveGesture(revealDrag, TapGesture().onEnded { handleTap() })
                )
                // ⚠️ .offset comes AFTER the shape + gesture so the tap
                // target rides the translation. Attached the other way
                // around, the hit region stays at the UNSHIFTED frame:
                // with the row open, an invisible full-width tap area
                // covered the revealed actions, so a finger on DELETE
                // hit the row's tap-close instead — actions "did
                // nothing but hide" (Dave, build 36). XCUITest taps
                // dispatch via accessibility and bypass the overlay,
                // which is why CI never saw it.
                .offset(x: offset)
                // VoiceOver path to the swipe actions (#164). CONTRACT: use
                // `.contain`, NOT `.combine`/`.accessibilityAddTraits`, which
                // flatten the row into one element and hide the child texts the
                // smoke tests query (CI-proven, build 36; testing.md). `.contain`
                // keeps children individually queryable while carrying the rotor
                // actions. Only applied when there ARE actions, so action-less
                // rows are untouched.
                .modifier(RowAccessibilityActions(actions: accessibilityActions))
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: offset)
        // While THIS row is open, the full-width swipe-back stands down:
        // closing a row is a rightward horizontal drag the pop gesture
        // can't distinguish from a back-swipe (#198 review). Balanced on
        // disappear so a pop with a row open can't leak suppression.
        .onChange(of: openRow == id) { _, isOpen in
            PopGestureGate.suppressionCount = max(0, PopGestureGate.suppressionCount + (isOpen ? 1 : -1))
        }
        .onDisappear {
            if openRow == id {
                PopGestureGate.suppressionCount = max(0, PopGestureGate.suppressionCount - 1)
            }
        }
    }

    /// `enabled` gates activation too, mirroring the reveal drag: while
    /// a rail gesture is live, a second finger must neither open sheets
    /// nor close rows.
    private func handleTap() {
        guard enabled else { return }
        if openRow != nil {
            openRow = nil
        } else {
            onTap?()
        }
    }

    private var revealDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($dragBase) { _, state, _ in
                if state == nil { state = restingOffset }
            }
            .updating($dragX) { value, state, _ in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                state = value.translation.width
            }
            // The open/closed decision commits HERE, live at
            // the halfway threshold — not only in onEnded.
            // Inside a List the scroll pan can steal the touch
            // at finger-lift, which CANCELS this gesture:
            // @GestureState resets, onEnded never runs, and a
            // decided-at-end-only row snapped shut under the
            // finger (Dave, build 17: "letting go hides it
            // again"). A cancelled gesture now keeps whatever
            // the drag last crossed.
            .onChanged { value in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height),
                      let base = dragBase
                else { return }
                let dragged = base + value.translation.width
                if dragged < -actionsWidth / 2 {
                    if openRow != id { openRow = id }
                } else if openRow == id {
                    openRow = nil
                }
            }
            // onEnded only adds the flick — and only a REAL
            // flick. A relaxing finger drifts a few points
            // rightward at lift; treating that as momentum
            // closed rows the drag had committed open (Dave,
            // build 31: "on release the item snaps back").
            // Below the floor, the live-committed state from
            // onChanged stands. A genuine rightward flick
            // closes WHATEVER row is open — deliberate: a
            // dismissive flick means "close it" regardless
            // of which row it lands on.
            .onEnded { value in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let momentum = value.predictedEndTranslation.width - value.translation.width
                guard abs(momentum) > 36 else { return }
                let projected = (openRow == id ? -actionsWidth : 0) + momentum
                openRow = projected < -actionsWidth / 2 ? id : nil
            }
    }
}

/// Adds the swipe actions as VoiceOver custom actions without flattening the
/// row (`.contain` keeps child `staticTexts` visible to XCUITest; `.combine`
/// would not). A no-op when there are no actions, so rows that never opted in
/// keep their exact prior accessibility tree.
private struct RowAccessibilityActions: ViewModifier {
    let actions: [SwipeRowAction]

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityActions {
                    ForEach(actions, id: \.name) { act in
                        Button(act.name) { act.perform() }
                    }
                }
        }
    }
}

/// One action inside a SwipeRevealRow: 58 pt, mono uppercase label on
/// a SOLID full-height fill (Quiet Arcade mock 02 — the revealed
/// action is a color block, not tinted text on surface). DELETE is
/// white on destructive per the mock; neutral actions pass
/// primaryFill/onPrimary, which holds contrast in both schemes.
struct SwipeActionButton: View {
    let label: String
    /// The block's fill.
    let color: Color
    var labelColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(labelColor)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(color)
        }
        // Plain, not default: List routes row taps into default-styled
        // buttons anywhere in the row — the second half of the
        // disappearing-rows bug. Safe from the content contract above:
        // this lives in the ACTIONS slot, outside the content gesture,
        // and only receives touches that begin on it while revealed.
        .buttonStyle(.plain)
    }
}
