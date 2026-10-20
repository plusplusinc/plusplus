import SwiftUI

/// A heading over a list that collapses and expands it: its title, and a chevron that points
/// down while the list shows and turns to point at the title once it is collapsed.
public struct DrawerHeading: View {
    private let title: LocalizedStringKey
    @Binding private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    /// The 44 pt minimum touch target; the width is the drawer's.
    private static let minHeight: CGFloat = 44

    public init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>) {
        self.title = title
        _isExpanded = isExpanded
    }

    public var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(title)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .font(.ppRowDetail.weight(.semibold))
            .foregroundStyle(.pp(.textSecondary))
            .frame(minHeight: Self.minHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .hotReloadable()
    }
}

#Preview {
    @Previewable @State var isExpanded = true
    VStack(alignment: .leading) {
        DrawerHeading("Routines", isExpanded: $isExpanded)
        if isExpanded {
            Text(verbatim: "Leg day")
        }
    }
    .padding()
    .background(Color.pp(.background))
}
