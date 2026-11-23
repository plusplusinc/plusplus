#if os(iOS)
import SwiftUI

/// The Length filter's sheet: the header a chip sheet has, title and Done fixed at the top
/// (`SheetHeader`); three presets on one row, sharing its width; and under them two wheels of
/// minutes, read as "20 – 40 min" (`RangeWheels`). A preset sets both wheels and lights while
/// the wheels read its range; tapping the lit one turns the filter off. Every change applies at
/// once, behind the sheet, as a chip's tap does; Done or a swipe down only closes it.
///
/// The sheet sits at its content's own height, as `ChipSheet` does. At the accessibility sizes
/// the presets stack, one per line, rather than any breaking a word.
public struct LengthSheet: View {
    let presets: [String]
    /// The preset the wheels read, if any.
    let lit: Int?
    let lower: Int
    let upper: Int?
    let lowerValues: [Int]
    let upperValues: [Int?]
    let onPreset: (Int) -> Void
    let onLower: (Int) -> Void
    let onUpper: (Int?) -> Void
    let onDone: () -> Void

    @State private var height: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        presets: [String],
        lit: Int?,
        lower: Int,
        upper: Int?,
        lowerValues: [Int],
        upperValues: [Int?],
        onPreset: @escaping (Int) -> Void,
        onLower: @escaping (Int) -> Void,
        onUpper: @escaping (Int?) -> Void,
        onDone: @escaping () -> Void,
    ) {
        self.presets = presets
        self.lit = lit
        self.lower = lower
        self.upper = upper
        self.lowerValues = lowerValues
        self.upperValues = upperValues
        self.onPreset = onPreset
        self.onLower = onLower
        self.onUpper = onUpper
        self.onDone = onDone
    }

    public var body: some View {
        let room = detentRoom
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SheetHeader(title: "Length", onDone: onDone)
            presetButtons
                // Touching, as `ChipSheet`'s chips: the negative inset takes back the half gap
                // each chip carries, so the capsules line up with the title.
                .padding(-Spacing.xs)
            RangeWheels(
                lower: lower,
                upper: upper,
                lowerValues: lowerValues,
                upperValues: upperValues,
                onLower: onLower,
                onUpper: onUpper,
            )
            // The picker draws its band inset from its sides; out by that much, the band's
            // ends line up with the presets'.
            .padding(.horizontal, -Spacing.sm)
        }
        .padding([.horizontal, .top], Spacing.md)
        .padding(.bottom, Spacing.md)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .sensoryFeedback(.selection, trigger: lit)
        .presentationDetents(height > 0 ? [.height(max(height - room, 0))] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.pp(.surface))
    }

    @ViewBuilder private var presetButtons: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) { chips }
        } else {
            HStack(spacing: 0) { chips }
        }
    }

    private var chips: some View {
        ForEach(presets.indices, id: \.self) { index in
            let isOn = lit == index
            Button { onPreset(index) } label: {
                Text(presets[index])
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity)
            }
            .buttonStyle(ChipButtonStyle(isOn: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

#Preview {
    @Previewable @State var lower = 20
    @Previewable @State var upper: Int? = 40
    Color.pp(.background)
        .sheet(isPresented: .constant(true)) {
            LengthSheet(
                presets: ["≤ 20 min", "20–40 min", "≥ 40 min"],
                lit: lower == 20 && upper == 40 ? 1 : nil,
                lower: lower,
                upper: upper,
                lowerValues: Array(stride(from: 0, through: 90, by: 5)),
                upperValues: Array(stride(from: 0, through: 90, by: 5)) + [nil],
                onPreset: { _ in lower = 20
                    upper = 40
                },
                onLower: { lower = $0 },
                onUpper: { upper = $0 },
                onDone: { },
            )
        }
}
#endif
