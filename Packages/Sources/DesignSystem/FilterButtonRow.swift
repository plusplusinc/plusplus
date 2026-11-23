#if os(iOS)
import SwiftUI

/// A filter bar's buttons, Add exercise's and the Workouts list's: one line that scrolls sideways
/// when their words don't fit (decided 2026-11-22: the row never wraps), led, while a filter is
/// on, by Clear (`ClearFiltersLabel`), which scrolls with them. Clear fades in and out as the
/// buttons slide over, in whatever transaction the change of filter carries
/// (`Animation.filterChange(reduceMotion:)`). With Reduce Motion nothing slides: the row
/// crossfades whole to what `shows` names. No count shows; each bar's screen tells VoiceOver
/// the count with each change.
public struct FilterButtonRow<Buttons: View>: View {
    let isOn: Bool
    /// What the buttons show, the filter: with Reduce Motion, a new value is a new row.
    let shows: AnyHashable
    let onClear: () -> Void
    let buttons: Buttons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isOn: Bool,
        shows: some Hashable,
        onClear: @escaping () -> Void,
        @ViewBuilder buttons: () -> Buttons,
    ) {
        self.isOn = isOn
        self.shows = AnyHashable(shows)
        self.onClear = onClear
        self.buttons = buttons()
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                if isOn {
                    Button(action: onClear) { ClearFiltersLabel() }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                }
                buttons
            }
            // Inside the scroll's content, so the first button lines up with the rows and the
            // last scrolls clear of the edge.
            .padding(.horizontal, Spacing.md)
            .id(reduceMotion ? shows : AnyHashable(0))
            .transition(.opacity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Room under the buttons' touches before what follows, a list's first row or an offer
        // line, the same on both screens.
        .padding(.bottom, Spacing.sm)
    }
}

extension Animation {
    /// A change of filter, from a button, a chip, Clear, or an offer: `.tapChange`, so both
    /// bars move alike; with Reduce Motion, a crossfade's ease, as the search field's.
    public static func filterChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .tapChange
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        FilterButtonRow(isOn: false, shows: 0) { } buttons: {
            FilterLabel("Muscle", isOn: false)
            FilterLabel("Equipment", isOn: false)
        }
        FilterButtonRow(isOn: true, shows: 1) { } buttons: {
            FilterLabel("Back", isOn: true)
            FilterLabel("Equipment", isOn: false)
        }
    }
    .background(Color.pp(.background))
}
#endif
