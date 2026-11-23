#if os(iOS)
import SwiftUI

/// A filter bar's buttons, Add exercise's and the Workouts list's: one line that scrolls sideways
/// when their words don't fit (decided 2026-11-22: the row never wraps), led, while a filter is
/// on, by Clear (`ClearFiltersLabel`), which scrolls with them. Clear fades in and out as the
/// buttons slide over, in whatever transaction the change of filter carries. No count shows;
/// each bar's screen tells VoiceOver the count with each change.
public struct FilterButtonRow<Buttons: View>: View {
    let isOn: Bool
    let onClear: () -> Void
    let buttons: Buttons

    public init(isOn: Bool, onClear: @escaping () -> Void, @ViewBuilder buttons: () -> Buttons) {
        self.isOn = isOn
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
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        FilterButtonRow(isOn: false) { } buttons: {
            FilterLabel("Muscle", isOn: false)
            FilterLabel("Equipment", isOn: false)
        }
        FilterButtonRow(isOn: true) { } buttons: {
            FilterLabel("Back", isOn: true)
            FilterLabel("Equipment", isOn: false)
        }
    }
    .background(Color.pp(.background))
}
#endif
