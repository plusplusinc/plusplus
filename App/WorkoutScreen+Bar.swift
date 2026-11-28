import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's bar: ++ or End, the title once it is under the bar, and ••• or a workout's time.
extension WorkoutScreen {
    @ToolbarContentBuilder
    var barItems: some ToolbarContent {
        // As a large title does, the title shows small in the bar once it is under it.
        ToolbarItem(placement: .title) {
            // Always there, faded out rather than taken out: the bar drew its edge effect only
            // while the item had something showing, so the band under the bar came and went
            // with the title, on the frame, and a title taken out went on the frame too.
            smallTitle(shownName)
                .opacity(isTitleUnderBar ? 1 : 0)
                .allowsHitTesting(isTitleUnderBar)
                .accessibilityShown(isTitleUnderBar)
        }
        // One item, its key changing in a crossfade: the bar put one in or took one out on
        // the frame.
        let barIsLive = barShowsWorkout
        if barIsLive || !isPushed {
            ToolbarItem(placement: .topBarLeading) {
                ZStack {
                    if barIsLive {
                        EndButton {
                            // Under a finish's "++" the workout has ended: nothing to ask.
                            if session.workoutSession != nil {
                                askToEnd()
                            }
                        }
                        .transition(.opacity)
                    } else {
                        MenuButton(session: session)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: Self.barFade), value: barIsLive)
            }
        }
        // One item, as leading's: ••• outside a workout and its time during one, crossfading
        // inside the time's glass. Taken out, the bar took the item's content out on the frame
        // and only faded its glass. The glass changes size on the frame: it grows at Start
        // before the crossfade, and shrinks at End once the time has faded out.
        ToolbarItem(placement: .topBarTrailing) {
            let timed = session.workoutSession ?? endingTime
            // Trailing, where ••• sits in its own glass, so it holds still as the glass changes.
            ZStack(alignment: .trailing) {
                // Always there, faded rather than put in or taken out. While the item holds only
                // the menu, the bar draws it as a menu item of its own, ignoring any fade, and
                // swaps the two on the frame: at Start the bar fades its ••• out itself, and at
                // End ••• fades in here while the time still holds the item, so it is whole when
                // the glass shrinks. Taken out, a ••• going faded at the glass's top-left corner,
                // where it sat before the glass grew.
                moreMenu
                    .fixedSize()
                    .opacity(barIsLive ? 0 : 1)
                    .allowsHitTesting(timed == nil)
                    .accessibilityShown(timed == nil)
                if let timed {
                    WorkoutTimeKey(workoutSession: timed, togglePause: togglePause)
                        .opacity(barIsLive ? 1 : 0)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: Self.barFade), value: barIsLive)
            .animation(.easeOut(duration: Self.barFade), value: timed == nil)
        }
    }

    /// Shows End's dialog: this screen's own at the root, and for a workout pushed on the
    /// Workouts screen, that screen's, outside its navigation stack. Inside the stack, as this
    /// screen's own would be there, iOS showed a popover with an arrow.
    private func askToEnd() {
        if let pushedEnd {
            pushedEnd.wrappedValue = EndChoices(
                finish: finish,
                discard: { _ = end(session.discard) },
            )
        } else {
            isConfirmingEnd = true
        }
    }

    /// Whether the bar draws the workout in progress: End and its time. Held under a finish's
    /// "++", where the store has already ended it, so the bar changes only as the ending plays.
    var barShowsWorkout: Bool {
        session.workoutSession != nil || phase.isEndBegun
    }

    /// The ending workout's time, stopped at End while a finish holds the screen still, so it
    /// stops counting. One paused keeps its pause, so it looks the same.
    private var endingTime: WorkoutSession? {
        guard var ending = phase.endingWorkoutSession else { return nil }
        if phase.isEndBegun, let end = phase.drawnEnd, !ending.isPaused {
            ending.endedAt = end
        }
        return ending
    }

    /// •••, the workout's own actions: Delete, red, dimmed while the workout has nothing saved.
    /// It asks first in a centered alert, "Delete <name>?", the name as the title shows it;
    /// confirmed, the session shows Workouts on a new workout (`AppSession.delete(_:)`).
    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Delete", systemImage: "trash", role: .destructive) {
                isAskingToDeleteWorkout = true
            }
            .disabled(!session.canDeleteOpen)
        }
        // Named once: hidden from VoiceOver through a representation, the menu read out its
        // Delete too, "More, Delete".
        .accessibilityLabel("More")
        .accessibilityIdentifier("workout.more")
        .hiddenBehindDrawer()
        .alert("Delete \(shownName ?? Self.defaultName)?", isPresented: $isAskingToDeleteWorkout) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                let id = session.current.id
                Task { await session.delete(id) }
            }
        }
    }
}

extension WorkoutScreen {
    /// The title, small in the bar. As a tap on the status bar does, a tap brings the title back.
    /// At the accessibility text sizes the bar keeps touches on its title for the large content
    /// viewer, so there the button is reached through VoiceOver only.
    private func smallTitle(_ shownName: String?) -> some View {
        Button {
            withAnimation(.snappy) {
                scrollPosition.scrollTo(edge: .top)
            }
        } label: {
            // Gray only for New workout, as in the title.
            Text(shownName ?? Self.defaultName)
                .font(.ppInlineTitle)
                .foregroundStyle(.pp(shownName == nil ? .textSecondary : .textPrimary))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        // A heading, as the system's own bar title is.
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Scrolls to the top.")
        .hiddenBehindDrawer()
    }
}
