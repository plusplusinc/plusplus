import SwiftUI
import SwiftData

/// The one slide-to-reveal quick-actions affordance (#88): trailing
/// mono-label buttons behind the row. Horizontal-dominant drags reveal;
/// vertical movement stays with the surrounding scroll. One row open at
/// a time via the shared `openRow` binding.
struct SwipeRevealRow<Content: View, Actions: View>: View {
    let id: PersistentIdentifier
    @Binding var openRow: PersistentIdentifier?
    var enabled: Bool = true
    let actionsWidth: CGFloat
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
                .offset(x: offset)
                .simultaneousGesture(
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
                        // onEnded only adds the flick: momentum past the
                        // current position can open (or close) a row the
                        // finger itself didn't carry across the threshold.
                        .onEnded { value in
                            guard enabled,
                                  abs(value.translation.width) > abs(value.translation.height)
                            else { return }
                            let momentum = value.predictedEndTranslation.width - value.translation.width
                            let projected = (openRow == id ? -actionsWidth : 0) + momentum
                            openRow = projected < -actionsWidth / 2 ? id : (openRow == id ? nil : openRow)
                        }
                )
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: offset)
    }
}

/// One action inside a SwipeRevealRow: 58 pt, mono uppercase label.
struct SwipeActionButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.border), alignment: .leading)
        }
        // Plain, not default: List routes row taps into default-styled
        // buttons anywhere in the row — the second half of the
        // disappearing-rows bug.
        .buttonStyle(.plain)
    }
}
