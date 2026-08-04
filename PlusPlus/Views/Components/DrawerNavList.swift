// ⚠️ `Foundation` explicitly, beside `SwiftData`: the `#Predicate` macro
// needs it (swiftdata.md), and relying on SwiftUI's re-export is how that
// one bites.
import Foundation
import SwiftUI
import SwiftData

/// The app's surface picker: a vertical list at the top of the reveal drawer
/// (Dave, 2026-08-04), replacing the bottom tab bar.
///
/// Two rows, because there are two roots — **Today** and **Search**. Routines,
/// Exercises and Kit are not missing from this list; they are the search
/// surface's SCOPES, reached from the scope bar under the field. The three of
/// them have rendered one `CatalogScopeView` since 2026-07-25 and an empty
/// query has always shown a scope's whole list, so a scope tap lands on
/// exactly the screen a tab tap used to.
///
/// ⚠️ Rows are FLAT, not raised keys. `design-grammar.md`: caps depress for
/// committing and navigating BUTTONS; chips, toggles, segments and ROWS stay
/// flat. Selection is the one selection look — tinted ground, blue ring,
/// `selectedInk` label — the same anatomy `SelectableChip` wears, never a
/// solid blue fill and never plain `Theme.selected` as the ink.
struct DrawerNavList: View {
    @Environment(RevealController.self) private var reveal

    /// Today's row icon reflects whether anything is outstanding today
    /// (2026-07-24) — onboarding steps or scheduled workouts. It used to be
    /// the Today TAB's icon, computed at the root so it stayed live off-tab;
    /// the drawer is where a user sees it now, and the drawer's list is
    /// rebuilt every time it opens, so the queries belong here.
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]
    @AppStorage(SetupState.equipmentDoneKey) private var equipmentDone = false
    /// The schedule step's no-schedule completion (#505, Q26-A) — the row
    /// icon must agree with the timeline's 3-of-3.
    @AppStorage(SetupState.trainingFreestyleKey) private var trainingFreestyle = false
    /// Bumped on day change so the icon re-derives at midnight (the same
    /// guard TodayView carries against a resident app rendering yesterday's
    /// plan).
    @State private var dayToken = 0

    private var todayStatus: TodayStatus {
        _ = dayToken
        return TodayStatus.current(
            routines: routines,
            sessions: finishedSessions,
            equipmentDone: equipmentDone,
            trainingFreestyle: trainingFreestyle,
            today: Date(),
            calendar: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(
                label: "Today",
                systemImage: todayStatus.systemImage,
                surface: .today,
                identifier: "drawerNavToday"
            )
            row(
                label: "Search",
                systemImage: "magnifyingglass",
                surface: .search,
                identifier: "drawerNavSearch"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            dayToken += 1
        }
    }

    private func row(
        label: String,
        systemImage: String,
        surface: AppTab,
        identifier: String
    ) -> some View {
        let isSelected = reveal.activeTab == surface.rawValue
        return Button {
            // ⚠️ The request goes through the controller, not into the root's
            // state directly — this view sits BENEATH the app layer and cannot
            // reach it. `RootTabView` consumes the slot, lands, and closes the
            // drawer, so the row does not close it itself: closing here would
            // race the landing and slide the app back over whichever surface
            // was still showing.
            reveal.requestSurface(surface)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    // A fixed column so the two labels start on one line
                    // whatever glyph Today is wearing — the calendar variants
                    // are not all the same width.
                    .frame(width: 26, alignment: .leading)
                    .accessibilityHidden(true)
                Text(label)
                Spacer(minLength: 0)
            }
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.selectedInk : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(isSelected ? Theme.selectedTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.keyRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius)
                .strokeBorder(isSelected ? Theme.selectedRing : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.selection, value: isSelected)
        .accessibilityIdentifier(identifier)
        // The row states its own selection; without this VoiceOver reads two
        // identical buttons and never says which one you are on.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
