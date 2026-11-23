#if os(iOS)
import SwiftUI

/// The capsule a filter's button and a sheet's chip both are: one line of `.ppRowDetail` in
/// the same insets, off on the raised surface, on in the light style, so the two are one
/// height. (A chip sheet that floats clear of the screen's edges is drawn at about 96% by the
/// system, so its chips measure a point shorter on screen than the buttons behind it.)
private struct FilterCapsule: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .font(.ppRowDetail)
            .foregroundStyle(Color.pp(isOn ? .onPrimaryKey : .textPrimary))
            .padding(.horizontal, Spacing.md - Spacing.xs)
            .padding(.vertical, Spacing.sm)
            .background(Color.pp(isOn ? .primaryKey : .surfaceRaised), in: .capsule)
            .animation(.tapChange, value: isOn)
    }
}

/// What a filter's button shows: a capsule with its words and a small chevron. Off, it reads
/// the filter's name on the raised surface; on, it reads what is chosen in the light style.
/// Every filter's trigger draws this one view, whether it opens a sheet or a menu, so they look
/// alike. The words are one `Text` whose string changes, so they never crossfade by branch;
/// VoiceOver reads the words alone, without the chevron.
public struct FilterLabel: View {
    let text: String
    let isOn: Bool
    public init(_ text: String, isOn: Bool) {
        self.text = text
        self.isOn = isOn
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(text)
                .fontWeight(isOn ? .semibold : .medium)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .fontWeight(.semibold)
                .accessibilityHidden(true)
        }
        .modifier(FilterCapsule(isOn: isOn))
        // The capsule is drawn smaller than a thumb; the touch is not. A thumb's size, not
        // scaled with the text: at the accessibility sizes the capsule is past it, and a
        // scaled minimum stood the row 127 pt tall around a 74 pt capsule.
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

/// A chip in a filter's sheet: the capsule a filter's button is (`FilterCapsule`), so the
/// sheet reads as more of the row that opened it. One weight on and off: a chip that grew
/// bolder grew wider, and pushed the chips after it along the line.
///
/// The touch is the capsule and half the gap to its neighbors on every side, so chips a gap
/// apart leave no dead strip between them and each is a thumb's height; `ChipSheet` lays them
/// out touching.
struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .modifier(FilterCapsule(isOn: isOn))
            .keyPress(isPressed: configuration.isPressed)
            .padding(Spacing.xs)
            .contentShape(.rect)
    }
}

/// A filter's sheet of chips, any number chosen: a header with the title and a round glass ×,
/// then every item as a chip, wrapping. A tap toggles a chip at once, so whatever the filter
/// narrows changes behind the sheet with each tap; the × (`GlassCloseButton`, Add exercise's
/// own Close, read "Done" since nothing it closes is undone) or a swipe down only closes it.
///
/// The sheet opens at half height (decided 2026-11-23), the header and chips at its top and
/// empty room below, so no chip sits near the bottom of the screen. Chips that fit stay still
/// under a drag. Where they don't fit in half height, as Equipment's at the largest text
/// sizes, the sheet also offers full height, and the chips scroll under the header, which
/// stays put. Where the title and the × won't fit side by side, the × goes under the title
/// (`LineOrStack`), which beside it broke mid-word.
public struct ChipSheet<Item: Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var chosen: Set<Item>
    let name: (Item) -> String
    let onDone: () -> Void

    @State private var detent = PresentationDetent.medium
    /// Measured at half height only: at full height the chips may fit, and dropping `.large`
    /// then would pull the sheet back down under the finger.
    @State private var overflowsAtMedium = false

    public init(
        title: String,
        items: [Item],
        chosen: Binding<Set<Item>>,
        name: @escaping (Item) -> String,
        onDone: @escaping () -> Void,
    ) {
        self.title = title
        self.items = items
        _chosen = chosen
        self.name = name
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], Spacing.md)
            ScrollView {
                // Touching: each chip carries half the gap around its capsule
                // (`ChipButtonStyle`), which the negative inset takes back at the edges, so
                // the capsules line up with the title.
                FlowLayout(spacing: 0) {
                    ForEach(items, id: \.self) { item in
                        chip(item)
                    }
                }
                .padding(-Spacing.xs)
                .padding([.horizontal, .bottom], Spacing.md)
                .padding(.top, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height + 1
            } action: { _, overflowing in
                if detent == .medium {
                    overflowsAtMedium = overflowing
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sensoryFeedback(.selection, trigger: chosen)
        .presentationDetents(
            overflowsAtMedium ? [.medium, .large] : [.medium],
            selection: $detent,
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.surface))
    }

    private var header: some View {
        LineOrStack(spacing: 0) {
            Text(title)
                .font(.ppBarTitle)
                .foregroundStyle(Color.pp(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            GlassCloseButton("Done", action: onDone)
                // The size Add exercise's Close reaches, which the bar stops growing; uncapped,
                // at the largest sizes it stood 120 pt and pushed under the title.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private func chip(_ item: Item) -> some View {
        let isOn = chosen.contains(item)
        return Button(name(item)) {
            if isOn {
                chosen.remove(item)
            } else {
                chosen.insert(item)
            }
        }
        .buttonStyle(ChipButtonStyle(isOn: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A line's words leading and its small button trailing, in `.ppRowDetail`.
struct TextAndButton<Words: View, Trailing: View>: View {
    @ViewBuilder let words: Words
    @ViewBuilder let button: Trailing

    var body: some View {
        LineOrStack {
            words
            button
        }
        .font(.ppRowDetail)
    }
}

/// A line's own small button, Clear and "+ Bench": its capsule (`SmallCapsuleLabel`) laid out
/// at the capsule's size, so the line stands as tall as its words, while the button, its touch
/// and what VoiceOver outlines, reaches past the capsule to a thumb's height and a gap's width
/// on each side (`TouchOutset`). A thumb's size, not scaled with the text, as `FilterLabel`'s.
struct SmallCapsuleButton: View {
    let systemImage: String
    let title: String
    var symbolColor = ColorToken.textPrimary
    let action: () -> Void
    @Environment(\.touchRoom) private var room
    /// Read by `OfferButtons`, a `Layout`, whose methods are nonisolated.
    nonisolated static let touchHeight: CGFloat = 44

    var body: some View {
        let outset = TouchOutset(minHeight: Self.touchHeight, sides: Spacing.sm, room: room)
        outset {
            Button(action: action) {
                // Fills the room `TouchOutset` places it in, the capsule on its own spot, and
                // takes touches across all of it.
                TouchInset(outset: outset) {
                    SmallCapsuleLabel(
                        systemImage: systemImage,
                        title: title,
                        symbolColor: symbolColor,
                    )
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The small capsule a line's own button wears, Clear and "+ Bench": a symbol and a word.
///
/// The symbol is a symbol, not a character, so it centers on the word's line; a typed "+"
/// sits on the baseline, low beside capitals. Its leading inset is the one the capsule's
/// height leaves above and below it, so it sits in the middle of the capsule's round end.
/// The symbol is in the word's color unless `symbolColor` says otherwise: an offer's + is
/// green, as the app's other + marks that make or add something are.
struct SmallCapsuleLabel: View {
    let systemImage: String
    let title: String
    var symbolColor = ColorToken.textPrimary

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(Color.pp(symbolColor))
                .accessibilityHidden(true)
            Text(title)
        }
        .fontWeight(.semibold)
        .foregroundStyle(Color.pp(.textPrimary))
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.sm + Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(Color.pp(.surfaceRaised), in: .capsule)
    }
}

/// The heading of the exercises one piece of equipment short of a filter: "Also needs a
/// bench" in the letter headings' style, read as a heading, and a small button that adds the
/// piece to the filter, read as "Add bench to Equipment". Where the two won't fit side by
/// side, the button goes under the words (`LineOrStack`).
public struct NeedsHeader: View {
    let title: String
    let addTitle: String
    let onAdd: () -> Void

    public init(title: String, addTitle: String, onAdd: @escaping () -> Void) {
        self.title = title
        self.addTitle = addTitle
        self.onAdd = onAdd
    }

    public var body: some View {
        TextAndButton {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textSecondary))
                .accessibilityAddTraits(.isHeader)
        } button: {
            SmallCapsuleButton(systemImage: "plus", title: addTitle, action: onAdd)
                .accessibilityLabel("Add \(addTitle.lowercased()) to Equipment")
        }
    }
}

/// Create's row label: a green + and its title, and under the title, while it carries
/// anything, what the exercise it makes will start with, as an exercise row's equipment line
/// reads. At the accessibility sizes the title wraps beside the +, in a column of its own: a
/// list's label there ran its second line back under the +, past its own frame.
public struct CreateLabel: View {
    let title: String
    let detail: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: "plus")
                    .accessibilityHidden(true)
                lines
            }
        } else {
            Label { lines } icon: { Image(systemName: "plus") }
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.ppRowDetail)
                    .foregroundStyle(Color.pp(.textSecondary))
            }
        }
    }
}

#Preview("Labels") {
    VStack(alignment: .leading, spacing: Spacing.md) {
        FlowLayout(spacing: Spacing.sm) {
            FilterLabel("Muscle", isOn: false)
            FilterLabel("Kind", isOn: false)
            FilterLabel("Equipment", isOn: false)
        }
        FlowLayout(spacing: Spacing.sm) {
            ClearFiltersLabel()
            FilterLabel("Chest, Back", isOn: true)
            FilterLabel("Stretch", isOn: true)
            FilterLabel("Dumbbells, Bench", isOn: true)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.pp(.background))
}

#Preview("Sheet") {
    @Previewable @State var chosen: Set = ["Dumbbells", "No equipment"]
    Color.pp(.background)
        .sheet(isPresented: .constant(true)) {
            ChipSheet(
                title: "Equipment",
                items: [
                    "No equipment", "Dumbbells", "Kettlebell", "Barbell", "Medicine ball",
                    "Bench", "Band", "Pull-up bar", "Rings", "Balance board",
                ],
                chosen: $chosen,
                name: { $0 },
                onDone: { },
            )
        }
}
#endif
