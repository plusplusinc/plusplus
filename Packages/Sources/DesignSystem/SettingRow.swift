import SwiftUI

/// A setting the system owns, alone on a Settings card: its name at a row title's size and, on
/// the right, its value, quieter, and after it a green check when it is on or a gray struck
/// circle when it is off. At accessibility sizes, these under the name. Not a switch: the value
/// is the system's answer, which the app only reads. Under a hairline in the same card, a
/// button as wide as the card that changes it (`Change`), neutral when the setting is on and
/// green when it is off, the state with something to do; an arrow after its words when it
/// leaves the app for where the setting lives; and under it a line on what it does or where to
/// go from there. VoiceOver reads the name and the value as one element.
public struct SettingRow: View {
    private let title: String
    private let value: String
    private let isOn: Bool
    private let change: Change

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The way to change the setting: the button's words, whether it leaves the app, the line
    /// under it, and what the button does.
    public struct Change {
        let title: String
        let leavesApp: Bool
        let note: String
        let action: () -> Void

        public init(_ title: String, leavesApp: Bool, note: String, action: @escaping () -> Void) {
            self.title = title
            self.leavesApp = leavesApp
            self.note = note
            self.action = action
        }
    }

    public init(_ title: String, value: String, isOn: Bool, change: Change) {
        self.title = title
        self.value = value
        self.isOn = isOn
        self.change = change
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            Rectangle()
                .fill(.pp(.separator))
                .frame(height: 1 / displayScale)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button(action: change.action) {
                    HStack(spacing: Spacing.sm) {
                        Text(change.title)
                        if change.leavesApp {
                            Image(systemName: "arrow.up.forward")
                                .imageScale(.small)
                                .fontWeight(.semibold)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(isOn ? .pillOnSurface(widens: true) : .greenPill(widens: true))
                Text(change.note)
                    .font(.ppCaption)
                    .foregroundStyle(.pp(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.sm + Spacing.xs)
            .padding(.bottom, Spacing.md)
        }
        .settingsCard()
    }

    @ViewBuilder private var row: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        layout {
            Text(title)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.sm) {
                // One text whose words change, so a new value swaps in place.
                Text(value)
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(.textSecondary))
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle.slash")
                    .font(.ppRowTitle)
                    .foregroundStyle(.pp(isOn ? .accent : .textSecondary))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm + Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let path = "Tap your picture, then Privacy › Apps › PlusPlus"
    VStack(spacing: Spacing.md) {
        SettingRow(
            "Sync workouts",
            value: "Off",
            isOn: false,
            change: .init("Turn on", leavesApp: false, note: "Syncs each workout you finish") { },
        )
        SettingRow(
            "Sync workouts",
            value: "On",
            isOn: true,
            change: .init("Manage in Health", leavesApp: true, note: path) { },
        )
        SettingRow(
            "Sync workouts",
            value: "Off",
            isOn: false,
            change: .init("Turn on in Health", leavesApp: true, note: path) { },
        )
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .sheetGround()
}
