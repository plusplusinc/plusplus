#if os(iOS)
import SwiftUI

/// The capsule a filter's button and a sheet's chip both are: one line of `.ppRowDetail` in
/// the same insets, off on the raised surface, on in the light style, so the two are one
/// height. (A chip sheet that floats clear of the screen's edges is drawn at about 96% by the
/// system, so its chips measure a point shorter on screen than the buttons behind it.)
struct FilterCapsule: ViewModifier {
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
/// alike. VoiceOver reads the words alone, without the chevron.
///
/// New words replace the old at once and fade in over the second half of the capsule's easing
/// to their width (`WordsFade`), while the fill crossfades: crossfaded, the two showed
/// overlapped mid-way. The words are one `Text` whose string changes, so they ride the capsule
/// as it moves (a new `Text` showed at its end place while the capsule was still on its way),
/// cut at the capsule's easing width, so a longer word never runs under the chevron. Words that
/// stay as only the weight changes don't fade.
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
                .fixedSize()
                .contentTransition(.identity)
                .modifier(WordsFade(text))
                // Laid out at full width at once; drawn only as far as the frame has eased.
                .clipped()
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

/// A filter button's new words faded in on the transaction that changes them: hidden from the
/// first frame drawn with them, in through the second half of the change. A `keyframeAnimator`
/// triggered by the words starts an update late, and on a change that rebuilt a list the new
/// words showed whole for a frame or two before going out to fade in.
///
/// How far through the change the words are comes from the animation itself: the modifier
/// animates a number standing for the words, `key`, and its square, from the old words' to the
/// new. Partway, at `p`, the two are `old + p(new - old)` and `old² + p(new² - old²)`, which
/// give `p` knowing only the new words' `key`. That holds for a change from words at rest; one
/// that takes over another mid-way starts off that curve, and its words come in sooner, still cut
/// at the capsule's width. So do words whose numbers happen to match, about one change in ten
/// thousand.
private struct WordsFade: ViewModifier, Animatable {
    var animatableData: AnimatablePair<Double, Double>
    let key: Double

    /// How far through the change the new words stay out of sight, while the capsule does most
    /// of its easing to their width, so they come in on a button near its new size, as the
    /// keyframe fade they replace did.
    static let hiddenFor = 0.5

    init(_ text: String) {
        // Any number per words, so long as different words mostly get different numbers. Kept
        // small, so its square stays precise enough near a change's end that close numbers
        // don't flicker.
        key = Double(UInt(bitPattern: text.hashValue) % 10007) + 1
        animatableData = AnimatablePair(key, key * key)
    }

    /// From 0 as the words change to 1 at the end of the change; 1 at rest.
    private var progress: Double {
        let (value, square) = (animatableData.first, animatableData.second)
        let ahead = key - value
        guard abs(ahead) > 1e-6 else { return 1 }
        let span = 2 * key - (key * key - square) / ahead
        guard abs(span) > 1e-6 else { return 1 }
        return 1 - ahead / span
    }

    func body(content: Content) -> some View {
        let opacity = min(max((progress - Self.hiddenFor) / (1 - Self.hiddenFor), 0), 1)
        // Set as worked out, frame by frame: animated too, the change's own transaction eased
        // it from the old words' 1, and the new words showed whole for two frames.
        return content.animation(nil) { $0.opacity(opacity) }
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

/// A filter's sheet of chips, any number chosen (`FilterSheetFrame`: the title and a glass ×,
/// at half height): every item as a chip, wrapping. A tap toggles a chip at once, so whatever
/// the filter narrows changes behind the sheet with each tap; the × or a swipe down only
/// closes it. Equipment's chips at the largest text sizes overflow half height, and scroll.
public struct ChipSheet<Item: Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var chosen: Set<Item>
    let name: (Item) -> String
    let onDone: () -> Void

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
        FilterSheetFrame(title: title, onDone: onDone) {
            // Touching: each chip carries half the gap around its capsule (`ChipButtonStyle`),
            // which the negative inset takes back at the edges, so the capsules line up with
            // the title.
            FlowLayout(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    chip(item)
                }
            }
            .padding(-Spacing.xs)
        }
        .sensoryFeedback(.selection, trigger: chosen)
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

/// What every filter's sheet is, `ChipSheet`'s and `LengthSheet`'s: a header with the title, read
/// as a heading, and a round glass × (`GlassCloseButton`, Add exercise's own Close, read "Done"
/// since nothing it closes is undone), fixed at the top; under it the content, from the top.
///
/// The sheet opens at half height (decided 2026-11-23), empty room under the content, so
/// nothing sits near the bottom of the screen. Content that fits stays still under a drag.
/// Where it doesn't fit in half height, as at the largest text sizes, the sheet also offers
/// full height, and the content scrolls under the header, which stays put. Where the title and
/// the × won't fit side by side, the × goes under the title (`LineOrStack`), which beside it
/// broke mid-word.
///
/// The sheet is the screen's own color (`background`), as the exercise sheet and Add exercise
/// are: an unchosen chip's `surfaceRaised` stands 1.29:1 from it, and 1.14:1 from `surface`.
struct FilterSheetFrame<Content: View>: View {
    let title: String
    let onDone: () -> Void
    let content: Content

    @State private var detent = PresentationDetent.medium
    /// Measured at half height only: at full height the content may fit, and dropping `.large`
    /// then would pull the sheet back down under the finger.
    @State private var overflowsAtMedium = false

    init(title: String, onDone: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onDone = onDone
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], Spacing.md)
            ScrollView {
                content
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
        .presentationDetents(
            overflowsAtMedium ? [.medium, .large] : [.medium],
            selection: $detent,
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.background))
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
}

/// A line's own small button, an offer's "+ Back" and "+ Bench": its capsule (`SmallCapsuleLabel`)
/// laid out
/// at the capsule's size, so the line stands as tall as its words, while the button, its touch
/// and what VoiceOver outlines, reaches past the capsule to a thumb's height and a gap's width
/// on each side (`TouchOutset`). A thumb's size, not scaled with the text, as `FilterLabel`'s.
struct SmallCapsuleButton: View {
    let systemImage: String
    let title: String
    var symbolColor = ColorToken.textPrimary
    /// Where the capsule sits in its line's width once its word wraps there, as at the largest
    /// text sizes, so it keeps to the edge of the words it goes with.
    var alignment = HorizontalAlignment.center
    let action: () -> Void
    @Environment(\.touchRoom) private var room
    /// Read by `OfferButtons`, a `Layout`, whose methods are nonisolated.
    nonisolated static let touchHeight: CGFloat = 44

    var body: some View {
        let outset = TouchOutset(minHeight: Self.touchHeight, sides: Spacing.sm, room: room)
        outset {
            Button(action: action) {
                // Fills the room `TouchOutset` places it in, the capsule on its own spot within
                // the line's width, so it wraps its word there, and takes touches across all
                // of it.
                TouchInset(outset: outset, alignment: alignment) {
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
/// The symbol is in the word's color unless `symbolColor` says otherwise: an offer's + and
/// "+ Bench"'s are green, as the app's other + marks that make or add something are.
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
