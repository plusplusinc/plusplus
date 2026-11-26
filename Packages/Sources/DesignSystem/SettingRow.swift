import SwiftUI

/// A setting the system owns, alone on a Settings card: its name at a row title's size and its
/// value trailing, quieter; at accessibility sizes, the value under the name. Not a switch: the
/// value is the system's answer, which the app only reads. With an action, a tap anywhere on the
/// card runs it and VoiceOver reads it as a button with `hint`; without one, the row is plain
/// text, drawn at full strength rather than dimmed as a disabled button would be. VoiceOver reads
/// the name and the value as one element.
public struct SettingRow: View {
    private let title: String
    private let value: String
    private let hint: String
    private let action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ title: String, value: String, hint: String = "", action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    row
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
        // Combined, so a button keeps its action and trait under the one label.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(action == nil ? "" : hint)
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
            // One text whose words change, so a new value swaps in place.
            Text(value)
                .font(.ppRowTitle)
                .foregroundStyle(.pp(.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm + Spacing.xs)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        SettingRow("Save workouts", value: "Off", hint: "Asks to save workouts") { }
        SettingRow("Save workouts", value: "On")
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .sheetGround()
}
