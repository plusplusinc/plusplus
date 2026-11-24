import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// What ++ opens: the app's title, then Workouts and Log, each showing in place of the screen
/// showing. The place showing is marked; while a workout shows, Workouts is, since an open
/// workout is one of them, so a drawer never opens with no place marked.
///
/// The mark is taken as the drawer starts to show. A tap on another place slides the mark to it
/// (`DrawerWay.markSlide`), one mark moving, and the drawer closes as it lands, the place
/// swapping under the closing drawer (`AppSession.show(_:throughDrawer:markWait:)`); Log's Go to
/// Workouts plays the same slide in a drawer it opens, held open a moment before and after the
/// slide (`DrawerWay.holdBefore`, `holdAfter`). A tap on the place showing closes the
/// drawer at once, and so does Workouts from an open workout, with the list under it: the mark
/// is already there. A row shows no press (`DrawerButtonStyle`). The mark is then held until the
/// drawer has fully closed. With Reduce Motion
/// the mark changes rows at once and the drawer waits a moment before closing; with VoiceOver a
/// tap goes straight to the place, as the drawer has always done.
struct DrawerMenu: View {
    let session: AppSession

    /// The place marked, taken as the drawer starts to show, until a way moves the session's
    /// mark, which it keeps through the close. The drawer is in the hierarchy only while it
    /// shows, so this is taken anew each time.
    @State private var held: AppSession.Showing?
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let showing = session.drawerMark ?? held ?? session.showing
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Tapping the title closes the drawer, as a tap on the screen beside it does.
                Button {
                    session.closeDrawer()
                } label: {
                    Text(verbatim: "PlusPlus")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Closes the menu")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .padding(.horizontal, Spacing.sm)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button("Workouts", systemImage: "checklist") {
                        go(to: .workouts, from: showing)
                    }
                    // An open workout is one of the Workouts, so it marks their row too.
                    .buttonStyle(.drawer(isSelected: showing != .log))
                    Button("Log", systemImage: "book.closed") {
                        go(to: .log, from: showing)
                    }
                    .buttonStyle(.drawer(isSelected: showing == .log))
                }
                .drawerMarks()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
        }
        // The drawer is built as it starts to show, so this runs each time it does, before its
        // first frame.
        .onAppear { held = session.showing }
        .animation(DrawerWay.markSlide(reduceMotion: reduceMotion), value: showing)
        .task { isTitleFocused = true }
    }

    private func go(to place: AppSession.Showing, from showing: AppSession.Showing) {
        if place == showing {
            session.closeDrawer()
        } else if voiceOver || (showing == .workout && place == .workouts) {
            // From an open workout the mark is on Workouts already, so there is no slide to
            // wait for: the list shows under the closing drawer at once.
            switch place {
            case .workouts: session.showWorkouts()
            case .log: session.showLog()
            case .workout: session.closeDrawer()
            }
        } else {
            session.showThroughDrawer(place, reduceMotion: reduceMotion)
        }
    }
}

extension AppSession {
    /// `show(_:throughDrawer:markWait:)` on the drawer's own beats (`DrawerWay`).
    func showThroughDrawer(_ place: Showing, after lead: Duration = .zero, reduceMotion: Bool) {
        show(
            place,
            after: lead,
            throughDrawer: DrawerOpening(
                arrival: DrawerWay.arrival(reduceMotion: reduceMotion),
                holdBefore: DrawerWay.holdBefore,
                holdAfter: DrawerWay.holdAfter,
            ),
            markWait: DrawerWay.markWait(reduceMotion: reduceMotion),
        )
    }
}

#Preview {
    DrawerMenu(
        session: AppSession(
            workout: Workout(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
    )
}
