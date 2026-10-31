import DesignSystem
import SwiftUI
import WorkoutStore

/// The screen's bar: ++ or End, the title once it is under the bar, and a workout's time.
extension RoutineScreen {
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
        if session.workout != nil || !isPushed {
            ToolbarItem(placement: .topBarLeading) {
                ZStack {
                    if session.workout != nil {
                        EndButton { isConfirmingEnd = true }
                            .transition(.opacity)
                    } else {
                        MenuButton(session: session)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: Self.barFade), value: session.workout == nil)
            }
        }
        // The time fades out of its glass, and then the glass goes, the bar fading it: the bar
        // took the item out with its content on the frame, and only the glass faded.
        if let workout = session.workout ?? endingWorkout {
            ToolbarItem(placement: .topBarTrailing) {
                WorkoutTimeKey(session: session, workout: workout)
                    .opacity(session.workout == nil ? 0 : 1)
                    .animation(.easeOut(duration: Self.barFade), value: session.workout == nil)
            }
        }
    }
}

extension RoutineScreen {
    /// The title, small in the bar. As a tap on the status bar does, a tap brings the title back.
    /// At the accessibility text sizes the bar keeps touches on its title for the large content
    /// viewer, so there the button is reached through VoiceOver only.
    private func smallTitle(_ shownName: String?) -> some View {
        Button {
            withAnimation(.snappy) {
                scrollPosition.scrollTo(edge: .top)
            }
        } label: {
            // Gray only for New routine, as in the title.
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

extension View {
    /// Shown to VoiceOver and the UI tests only while `isShown`. `accessibilityHidden` left the
    /// bar's title read out while faded away.
    fileprivate func accessibilityShown(_ isShown: Bool) -> some View {
        accessibilityRepresentation {
            if isShown {
                self
            }
        }
    }
}
