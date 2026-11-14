import SwiftUI

/// The presented key, with the swap it is in, which it owns. The bar's reactions to a change come
/// only after the update that drew it, so the stage is what that update draws from: the key as it
/// was while it is presented, so a key swapped leaves with its own words; the live face once the
/// screen has ridden it down out of sight, so the key that comes back up at a workout's start is
/// the workout's, inserted under the animation that brings it back. Drawn as the key it had been,
/// Start came back and was replaced by the workout's key unanimated, once the bar had followed
/// the change (2026-11-13).
struct StagedKey<Face: Equatable & Identifiable, Content: View>: View {
    let face: Face
    let isDropped: Bool
    let below: CGFloat
    let content: (Face, _ isOut: Bool) -> Content

    @State private var stage: KeyStage<Face>
    /// The face as last followed, which the swap's beats read when it rises: `face` in the task
    /// is the one it started with.
    @State private var live: Face

    init(
        face: Face,
        isDropped: Bool,
        below: CGFloat,
        @ViewBuilder content: @escaping (Face, _ isOut: Bool) -> Content,
    ) {
        self.face = face
        self.isDropped = isDropped
        self.below = below
        self.content = content
        _stage = State(initialValue: isDropped ? .dropped : .showing(face))
        _live = State(initialValue: face)
    }

    var body: some View {
        let shown = stage.face(for: face)
        content(shown, stage.isOut)
            // Another key comes in with the bar's own transition, under the animation of the
            // update that brought it: out of sight in a swap, with none.
            .transition(KeyBarTransition(below: below))
            .id(shown.id)
            .onChange(of: face) { _, new in follow(to: new) }
            .onChange(of: isDropped) { _, isDropped in stage.drop(isDropped, live: face) }
            // The swap's beats: the key going away cancels them.
            .task(id: stage.isOut) { await swap() }
    }

    /// Follows the face changing to `new`: another key starts the one showing leaving with its
    /// words, easing in, so it is still in sight until it clears the edge, and the next one comes
    /// up straight after (easing out, it crept out of sight over its last frames).
    private func follow(to new: Face) {
        live = new
        var next = stage
        if next.follow(to: new) {
            withAnimation(.easeIn(duration: PrimaryKeyButtonStyle.swapHalf)) { stage = next }
        } else {
            stage = next
        }
    }

    /// Once the key going is out of sight, the next one in its place below the edge, rising on a
    /// later turn of the run loop. Timed, not on the animation's completion, which came a few
    /// frames after the key had gone.
    private func swap() async {
        guard stage.isOut else { return }
        do {
            try await Task.sleep(for: .seconds(PrimaryKeyButtonStyle.swapHalf), tolerance: .zero)
        } catch {
            return
        }
        // Out of sight, the key becomes the next one with no transition of its own.
        withTransaction(\.disablesAnimations, true) { stage.advance(live: live) }
        // From out of sight: in the same update, the next key took up the old one's place.
        await Task.yield()
        guard !Task.isCancelled, stage.isOut else { return }
        withAnimation(.smooth(duration: PrimaryKeyButtonStyle.swapHalf)) {
            stage.advance(live: live)
        }
    }
}

/// The key down out of sight while `isOut`, as far as its height and what lies below it, in
/// place: the bar keeps its room. No further, so the key coming in starts up as the one going
/// clears the edge: with 8 pt more, the two halves had frames with no key between them. Unfaded
/// both ways: faded going, it was all but gone three frames before it cleared the edge. With
/// Reduce Motion it stays put and fades each way. Measured as it is drawn, so a
/// key that starts out of sight is out of sight from its first frame.
struct KeySwap: ViewModifier, Animatable {
    /// How far out the key is, 0 to 1, which an animation runs through.
    var progress: CGFloat

    init(isOut: Bool) {
        progress = isOut ? 1 : 0
    }

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let progress = progress
        let moves = !reduceMotion
        content
            .visualEffect { content, proxy in
                content.offset(y: moves
                    ? progress * (proxy.size.height + proxy.safeAreaInsets.bottom)
                    : 0)
            }
            .opacity(reduceMotion ? 1 - progress : 1)
    }
}
