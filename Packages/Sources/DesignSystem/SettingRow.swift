import SwiftUI

/// A setting the system owns, alone on a Settings card: its name at a row title's size and, on
/// the right, its value, quieter, and after it a green check when it is on or an empty gray
/// circle when it is off. At accessibility sizes, these under the name. Not a switch: the value
/// is the system's answer, which the app only reads. Under a hairline in the same card, a
/// button as wide as the card that changes it (`Change`), neutral when the setting is on and
/// green when it is off, the state with something to do; an arrow after its words when it
/// opens another app, where the setting lives, which VoiceOver hears in the button's hint; and
/// under it, then, a line in the caption style on where to go there. With no button that can
/// take the person there, the line alone. VoiceOver reads the name and the value as one
/// element, the mark after the value left out.
public struct SettingRow: View {
    private let title: String
    private let value: String
    private let isOn: Bool
    private let change: Change

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The way to change the setting.
    public enum Change {
        /// A button: its words, the app it opens when it leaves this one, which VoiceOver hears
        /// in its hint in place of the arrow, the line under it, and what it does.
        case button(String, opens: String? = nil, note: String? = nil, action: () -> Void)
        /// No button can take the person there: only the line on where to go.
        case directions(String)
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
                switch change {
                case let .button(title, opens, note, action):
                    Button(action: action) {
                        HStack(spacing: Spacing.sm) {
                            Text(title)
                            if opens != nil {
                                Image(systemName: "arrow.up.forward")
                                    .imageScale(.small)
                                    .fontWeight(.semibold)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(isOn ? .pillOnSurface : .greenPill())
                    // A hint, not the label: Voice Control finds a button by its visible words.
                    .accessibilityHint(opens.map { "Opens \($0)" } ?? "")
                    note.map(line)
                case let .directions(note):
                    line(note)
                }
            }
            .padding(.top, Spacing.sm + Spacing.xs)
            .padding(.bottom, Spacing.md)
        }
        .settingsCard()
    }

    private func line(_ note: String) -> some View {
        Text(note)
            .font(.ppCaption)
            .foregroundStyle(.pp(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
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
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
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
            change: .button("Sync to Apple Health") { },
        )
        SettingRow(
            "Sync workouts",
            value: "On",
            isOn: true,
            change: .button("Manage in Apple Health", opens: "Apple Health", note: path) { },
        )
        SettingRow(
            "Sync workouts",
            value: "Off",
            isOn: false,
            change: .button("Enable in Apple Health", opens: "Apple Health", note: path) { },
        )
    }
    .padding(Spacing.md)
    .frame(maxHeight: .infinity)
    .sheetGround()
}
