#if os(iOS)
import SwiftUI

/// What a filter's button shows: a capsule with its words and a small chevron. Off, it reads
/// the filter's name on the raised surface; on, it reads what is chosen in the light style.
/// Every filter's trigger draws this one view, whether it opens a sheet or a menu, so they look
/// alike. The words are one `Text` whose string changes, so they never crossfade by branch.
public struct FilterLabel: View {
    let text: String
    let isOn: Bool
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 44

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
        .font(.ppRowDetail)
        .foregroundStyle(Color.pp(isOn ? .onPrimaryKey : .textPrimary))
        .padding(.horizontal, Spacing.md - Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .background(Color.pp(isOn ? .primaryKey : .surfaceRaised), in: .capsule)
        .animation(.tapChange, value: isOn)
        // The capsule is drawn smaller than a thumb; the touch is not.
        .frame(minHeight: minHeight)
        .contentShape(.rect)
    }
}

/// A chip in a filter's sheet: off on the raised surface, on in the light style, as
/// `FilterLabel` is.
public struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ppButton)
            .foregroundStyle(Color.pp(isOn ? .onPrimaryKey : .textPrimary))
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: minHeight)
            .background(Color.pp(isOn ? .primaryKey : .surfaceRaised), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.tapChange, value: isOn)
            .contentShape(.capsule)
    }
}

/// A filter's sheet of chips, any number chosen: a header with the title and Done, then every
/// item as a chip, wrapping. A tap toggles a chip at once, so whatever the filter narrows
/// changes behind the sheet with each tap; Done or a swipe down only closes it. The sheet sits
/// at its content's own height.
public struct ChipSheet<Item: Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var chosen: Set<Item>
    let name: (Item) -> String
    let onDone: () -> Void

    @State private var height: CGFloat = 0

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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(title)
                        .font(.ppBarTitle)
                        .foregroundStyle(Color.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.ppButton)
                        .foregroundStyle(Color.pp(.textPrimary))
                        .frame(minHeight: 44)
                }
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(items, id: \.self) { item in
                        chip(item)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.selection, trigger: chosen)
        .presentationDetents(height > 0 ? [.height(height)] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.surface))
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

/// The line under the filter buttons while one is on: how many exercises show, and Clear.
public struct FilterCount: View {
    let text: String
    let onClear: () -> Void

    public init(_ text: String, onClear: @escaping () -> Void) {
        self.text = text
        self.onClear = onClear
    }

    public var body: some View {
        HStack {
            Text(text)
                .foregroundStyle(Color.pp(.textSecondary))
            Spacer()
            Button("Clear", action: onClear)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textPrimary))
                .accessibilityLabel("Clear filters")
        }
        .font(.ppRowDetail)
    }
}

/// The heading of the exercises one piece of equipment short of a filter: "Also needs a
/// bench" in the letter headings' style, and a small button that adds the piece to the filter.
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
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textSecondary))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onAdd) {
                // The + is a symbol, not a character, so it centers on the name's line; a
                // typed "+" sits on the baseline, low beside capitals. Its leading inset is
                // the one the capsule's height leaves above and below it, so it sits in the
                // middle of the capsule's round end.
                HStack(alignment: .center, spacing: Spacing.xs) {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(addTitle)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.pp(.textPrimary))
                .padding(.leading, Spacing.sm)
                .padding(.trailing, Spacing.sm + Spacing.xs)
                .padding(.vertical, Spacing.xs)
                .background(Color.pp(.surfaceRaised), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(addTitle.lowercased()) to Equipment")
        }
        .font(.ppRowDetail)
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
            FilterLabel("Chest, Back", isOn: true)
            FilterLabel("Stretch", isOn: true)
            FilterLabel("Dumbbells, Bench", isOn: true)
        }
        FilterCount("4 exercises") { }
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
