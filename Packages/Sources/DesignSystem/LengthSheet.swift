#if os(iOS)
import SwiftUI

/// The Length filter's sheet, a chip sheet's frame (`FilterSheetFrame`: the title and a glass ×,
/// at half height): three presets on one row, sharing its width; and under them two wheels of
/// minutes, read as "20 – 40 min" (`RangeWheels`). A preset sets both wheels and lights while
/// the wheels read its range; tapping the lit one turns the filter off. Every change applies at
/// once, behind the sheet, as a chip's tap does; the × or a swipe down only closes it.
///
/// At the accessibility sizes the presets stack, one per line, rather than any breaking a
/// word, and the sheet overflows half height, so it also offers full height and scrolls.
public struct LengthSheet: View {
    let presets: [String]
    /// Each preset's words as VoiceOver reads them, "20 minutes or less" for "≤ 20 min".
    let spokenPresets: [String]
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

    public init(
        presets: [String],
        spokenPresets: [String],
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
        self.spokenPresets = spokenPresets
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
        FilterSheetFrame(title: "Length", onDone: onDone) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                LengthPresets(
                    presets: presets,
                    spoken: spokenPresets,
                    lit: lit,
                    onPreset: onPreset,
                )
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
        }
        .sensoryFeedback(.selection, trigger: lit)
    }
}

/// The Length sheet's presets as chips, each a third of one row that never wraps, its words
/// shrinking a little before they would; at the accessibility sizes, one per line. VoiceOver
/// reads each in words (`spoken`), "20 minutes or less", not the "≤" it shows.
struct LengthPresets: View {
    let presets: [String]
    let spoken: [String]
    let lit: Int?
    let onPreset: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
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
            .accessibilityLabel(spoken[index])
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
                spokenPresets: ["20 minutes or less", "20 to 40 minutes", "40 minutes or more"],
                lit: lower == 20 && upper == 40 ? 1 : nil,
                lower: lower,
                upper: upper,
                lowerValues: Array(stride(from: 0, through: 90, by: 5)),
                upperValues: Array(stride(from: 5, through: 90, by: 5)) + [nil],
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
