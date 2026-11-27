import SwiftUI

/// A setting the system owns, alone on a Settings card: its name at a row title's size and, on
/// the right, a small green button that starts it (`button`), or its value, quieter, and after
/// it a green check when it is on or a gray struck circle when it is off. At accessibility
/// sizes, these under the name. Not a switch: the value is the system's answer, which the app
/// only reads. An answered row carries, under a hairline in the same card, a button that leaves
/// for where the setting lives, an arrow after its words saying so (neutral when the setting
/// is on, green when it is off, the one state with something to do), and under it a line on
/// where to go from there. VoiceOver reads the name and the value as one element.
public struct SettingRow: View {
    private let title: String
    private let value: String
    private let isOn: Bool
    private let leaves: Leave?
    private let button: (title: String, action: () -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The button's height at the default text size, a step under a tap target's, as it sits
    /// inside a row that is one.
    private static let buttonHeight: CGFloat = 36

    /// The way out to where the setting lives: the button's words, the line under it on where
    /// to go from there, and what the button does.
    public struct Leave {
        let title: String
        let note: String
        let action: () -> Void

        public init(_ title: String, note: String, action: @escaping () -> Void) {
            self.title = title
            self.note = note
            self.action = action
        }
    }

    public init(_ title: String, value: String, isOn: Bool, leaves: Leave? = nil) {
        self.title = title
        self.value = value
        self.isOn = isOn
        self.leaves = leaves
        button = nil
    }

    public init(_ title: String, button: String, action: @escaping () -> Void) {
        self.title = title
        value = ""
        isOn = false
        leaves = nil
        self.button = (button, action)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if let leaves {
                Rectangle()
                    .fill(.pp(.separator))
                    .frame(height: 1 / displayScale)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Button(action: leaves.action) {
                        HStack(spacing: Spacing.sm) {
                            Text(leaves.title)
                            Image(systemName: "arrow.up.forward")
                                .imageScale(.small)
                                .fontWeight(.semibold)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(isOn ? .pillOnSurface(widens: true) : .greenPill(widens: true))
                    Text(leaves.note)
                        .font(.ppCaption)
                        .foregroundStyle(.pp(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.sm + Spacing.xs)
                .padding(.bottom, Spacing.md)
            }
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
            if let button {
                Button(button.title, action: button.action)
                    .buttonStyle(.greenPill(height: Self.buttonHeight))
                    .padding(.trailing, -Spacing.sm)
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, button == nil ? Spacing.sm + Spacing.xs : Spacing.sm)
        .accessibilityElement(children: button == nil ? .combine : .contain)
    }
}

#Preview {
    let note = "In Health, tap your picture › Privacy › Apps › PlusPlus"
    VStack(spacing: Spacing.md) {
        SettingRow("Sync workouts", button: "Turn on") { }
        SettingRow(
            "Sync workouts",
            value: "On",
            isOn: true,
            leaves: .init("Manage in Health", note: note) { },
        )
        SettingRow(
            "Sync workouts",
            value: "Off",
            isOn: false,
            leaves: .init("Turn on in Health", note: note) { },
        )
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .sheetGround()
}
