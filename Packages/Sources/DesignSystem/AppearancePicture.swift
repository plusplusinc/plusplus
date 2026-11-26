import SwiftUI

/// One of Settings' two looks as iOS's Display & Brightness draws its own: a tiny phone of the
/// workout screen in that look (`TinyPhone`), drawn in it whatever the app is in, its name under
/// it, and under the name a round mark, filled with Checklist's check on the chosen one, empty
/// on the other. The chosen phone is also outlined in the page's active color (`accent`). The
/// mark and the outline crossfade on `.tapChange`. `isBlackBelt` draws the dark phone in Black
/// belt's colors, so the picture shows what the person will get. VoiceOver reads one button:
/// the name, selected when chosen.
public struct AppearancePicture: View {
    private let appearance: Appearance
    private let isChosen: Bool
    private let isBlackBelt: Bool
    private let action: () -> Void

    public init(
        _ appearance: Appearance,
        isChosen: Bool,
        isBlackBelt: Bool,
        action: @escaping () -> Void,
    ) {
        self.appearance = appearance
        self.isChosen = isChosen
        self.isBlackBelt = isBlackBelt
        self.action = action
    }

    /// Thick enough to read in the active color around a phone as dark as the card.
    private static let outline: CGFloat = 2
    /// The outline's distance from the phone.
    private static let outlineGap: CGFloat = 3

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                TinyPhone()
                    .environment(\.colorScheme, appearance.colorScheme)
                    .environment(\.isBlackBelt, isBlackBelt)
                    // A picture of the workout screen, so in its screen's look on a sheet too.
                    .environment(\.isOnSheet, false)
                    .padding(Self.outlineGap + Self.outline)
                    .overlay {
                        RoundedRectangle(cornerRadius: TinyPhone.outlineCorner, style: .continuous)
                            .strokeBorder(.pp(.accent), lineWidth: Self.outline)
                            .opacity(isChosen ? 1 : 0)
                    }
                Text(appearance.name)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.textPrimary))
                ZStack {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.pp(.textSecondary))
                        .opacity(isChosen ? 0 : 1)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.pp(.accent))
                        .opacity(isChosen ? 1 : 0)
                }
                .font(.ppCheckMark)
            }
            .animation(.tapChange, value: isChosen)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.name)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// A small picture of the workout screen, in the look around it: a phone-shaped rounded
/// rectangle in `background` with a `separator` edge, so it shows on any card; inside, from the
/// top, the current exercise's dot in the active color (`accent`), a bar for its name
/// (`textPrimary`), its three set bars, one done (`done`) and two to come (`toDo`), and at the
/// bottom the key at the foot of the screen (`accent`). A picture: no text, hidden from
/// VoiceOver. Every length is a multiple of the phone's width, which grows with Dynamic Type up
/// to the largest size short of the accessibility sizes (`largest`), as a list's icons stop
/// growing.
struct TinyPhone: View {
    static let largest = DynamicTypeSize.xxxLarge
    /// The chosen outline's corner, the phone's own opened by the outline's room, at the
    /// default size.
    static let outlineCorner: CGFloat = 20

    var body: some View {
        Picture()
            .dynamicTypeSize(...Self.largest)
    }
}

/// `TinyPhone`, at the text size around it.
private struct Picture: View {
    /// Two across a card on the smallest phone, with room between.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 72

    /// Points at a width of 44; `scale` turns them into this width's.
    private enum Base {
        static let width: CGFloat = 44
        static let height: CGFloat = 72
        static let corner: CGFloat = 9
        static let inset: CGFloat = 7
        static let gap: CGFloat = 5
        static let dot: CGFloat = 7
        static let nameWidth: CGFloat = 22
        static let nameHeight: CGFloat = 3
        static let setHeight: CGFloat = 2
        static let setGap: CGFloat = 2
        static let keyHeight: CGFloat = 10
        static let edge: CGFloat = 1
    }

    private var scale: CGFloat {
        width / Base.width
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Base.corner * scale, style: .continuous)
        VStack(alignment: .leading, spacing: Base.gap * scale) {
            Circle()
                .fill(.pp(.accent))
                .frame(width: Base.dot * scale, height: Base.dot * scale)
            Capsule()
                .fill(.pp(.textPrimary))
                .frame(width: Base.nameWidth * scale, height: Base.nameHeight * scale)
            HStack(spacing: Base.setGap * scale) {
                setBar(.done)
                setBar(.toDo)
                setBar(.toDo)
            }
            Spacer(minLength: 0)
            Capsule()
                .fill(.pp(.accent))
                .frame(height: Base.keyHeight * scale)
        }
        .padding(Base.inset * scale)
        .frame(width: width, height: Base.height * scale, alignment: .topLeading)
        .background(shape.fill(.pp(.background)))
        .overlay(shape.strokeBorder(.pp(.separator), lineWidth: Base.edge))
        .accessibilityHidden(true)
    }

    private func setBar(_ token: ColorToken) -> some View {
        Capsule()
            .fill(.pp(token))
            .frame(maxWidth: .infinity)
            .frame(height: Base.setHeight * scale)
    }
}

#Preview {
    HStack(spacing: Spacing.xl) {
        AppearancePicture(.light, isChosen: false, isBlackBelt: false) { }
        AppearancePicture(.dark, isChosen: true, isBlackBelt: true) { }
    }
    .padding(Spacing.md)
    .background(Color.pp(.surface))
}
